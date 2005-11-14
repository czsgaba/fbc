''	FreeBASIC - 32-bit BASIC Compiler.
''	Copyright (C) 2004-2005 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
''
''	This program is free software; you can redistribute it and/or modify
''	it under the terms of the GNU General Public License as published by
''	the Free Software Foundation; either version 2 of the License, or
''	(at your option) any later version.
''
''	This program is distributed in the hope that it will be useful,
''	but WITHOUT ANY WARRANTY; without even the implied warranty of
''	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''	GNU General Public License for more details.
''
''	You should have received a copy of the GNU General Public License
''	along with this program; if not, write to the Free Software
''	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.


'' emit abstract interface
''
'' chng: jun/2005 written [v1ctor]
''

defint a-z
option explicit
option escape

#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\reg.bi"
#include once "inc\ir.bi"
#include once "inc\rtl.bi"
#include once "inc\emit.bi"
#include once "inc\emitdbg.bi"
#include once "inc\symb.bi"

declare sub 	 emitSubInit			( )
declare sub 	 emitSubEnd				( )

declare sub 	 emitWriteHeader		( )
declare sub 	 emitWriteRtInit		( byval isdllmain as integer )
declare sub 	 emitWriteFooter		( byval tottime as double )
declare sub 	 emitWriteBss			( byval s as FBSYMBOL ptr )
declare sub 	 emitWriteConst			( byval s as FBSYMBOL ptr )
declare sub 	 emitWriteData			( byval s as FBSYMBOL ptr )
declare sub 	 emitWriteExport		( )


'' globals
	dim shared emit as EMITCTX

'':::::
sub emitInit static

	if( emit.inited ) then
		exit sub
	end if

	''
	emitSubInit( )

	''
	flistNew( @emit.nodeTB, EMIT_INITNODES, len( EMIT_NODE ) )

	''
	flistNew( @emit.vregTB, EMIT_INITVREGNODES, len( IRVREG ) )

	''
	emit.inited 		= TRUE
	emit.pos			= 0

	''
	edbgInit( )

end sub

'':::::
sub emitEnd static

	if( not emit.inited ) then
		exit sub
	end if

	''
	edbgEnd( )

	''
	emitSubEnd( )

	''
	emit.inited = FALSE

end sub

':::::
private sub hDllMainBegin( )
    dim as FBSYMBOL ptr proc, arg, s, label, exitlabel, initlabel, argreason
   	dim as ASTNODE ptr reason, main
   	dim as ASTPROCNODE ptr procnode
    dim as integer argn

	''
	proc = symbPreAddProc( )

	'' instance
	symbAddArg( proc, "{dllmain_instance}", _
				FB_SYMBTYPE_POINTER+FB_SYMBTYPE_VOID, NULL, 1, _
				FB_POINTERSIZE, FB_ARGMODE_BYVAL, INVALID, FALSE, NULL )

	'' reason
	symbAddArg( proc, "{dllmain_reason}", _
				FB_SYMBTYPE_UINT, NULL, 0, _
				FB_INTEGERSIZE, FB_ARGMODE_BYVAL, INVALID, FALSE, NULL )

	'' reserved
	symbAddArg( proc, "{dllmain_reserved}", _
				FB_SYMBTYPE_POINTER+FB_SYMBTYPE_VOID, NULL, 1, _
				FB_POINTERSIZE, FB_ARGMODE_BYVAL, INVALID, FALSE, NULL )

	''
	proc = symbAddProc( proc, NULL, strptr( "DllMain" ), NULL, _
						FB_SYMBTYPE_INTEGER, NULL, 0, FB_ALLOCTYPE_PUBLIC, _
						FB_FUNCMODE_STDCALL )

    symbSetProcIncFile( proc, INVALID )

    ''
	initlabel = symbAddLabel( NULL )
	exitlabel = symbAddLabel( NULL )

    ''
	procnode = astProcBegin( proc, initlabel, exitlabel, FALSE )

	''
	env.scope = 1
	env.currproc = proc

	arg = symbGetProcHeadArg( proc )
	argn = 1
	do while( arg <> NULL )

		s = symbAddArgAsVar( symbGetName( arg ), arg )
		if( argn = 2 ) then
			argreason = s
		end if

		arg = symbGetArgNext( arg )
		argn += 1
	loop

	symbAddProcResult( proc )

	''
   	astAdd( astNewLABEL( initlabel ) )

   	'' function = TRUE
   	s = symbLookupProcResult( proc )
   	astAdd( astNewASSIGN( astNewVAR( s, 0, symbGetType( proc ) ), _
   						  astNewCONSTi( 1, symbGetType( proc ) ) ) )

	'' if( reason = DLL_PROCESS_ATTACH ) then
	reason = astNewVAR( argreason, 0, symbGetType( argreason ) )
	label = symbAddLabel( NULL )
	astAdd( astNewBOP( IR_OP_NE, reason, astNewCONSTi( 1, IR_DATATYPE_UINT ), label, FALSE ) )

	''	main( 0, NULL )
    main = astNewFUNCT( emit.main.proc )
    astNewPARAM( main, astNewCONSTi( 0, IR_DATATYPE_INTEGER ) )
    astNewPARAM( main, astNewCONSTi( NULL, IR_DATATYPE_POINTER+IR_DATATYPE_VOID ) )
    astAdd( main )

	'' end if
    astAdd( astNewLABEL( label ) )

   	''
   	astAdd( astNewLABEL( exitlabel ) )

   	'' load result
   	s = symbLookupProcResult( proc )
   	astAdd( astNewLOAD( astNewVAR( s, 0, symbGetType( proc ) ), _
   						symbGetType( proc ), _
   						TRUE ) )

   	astProcEnd( procnode )

	env.currproc = NULL
	env.scope = 0

end sub

':::::
private sub hMainBegin( byval isdllmain as integer )
    dim as FBSYMBOL ptr proc, arg
    dim as integer alloctype

	''
	proc = symbPreAddProc( )

	'' argc
	symbAddArg( proc, "{argc}", _
				FB_SYMBTYPE_INTEGER, NULL, 0, _
				FB_INTEGERSIZE, FB_ARGMODE_BYVAL, INVALID, FALSE, NULL )

	'' argv
	symbAddArg( proc, "{argv}", _
				FB_SYMBTYPE_POINTER+FB_SYMBTYPE_POINTER+FB_SYMBTYPE_CHAR, NULL, 2, _
				FB_POINTERSIZE, FB_ARGMODE_BYVAL, INVALID, FALSE, NULL )

	''
	if( not isdllmain ) then
		alloctype = FB_ALLOCTYPE_PUBLIC
	else
		alloctype = FB_ALLOCTYPE_PRIVATE
	end if

	emit.main.proc = symbAddProc( proc, NULL, fbGetEntryPoint( ), NULL, _
								  FB_SYMBTYPE_VOID, NULL, 0, _
								  alloctype or FB_ALLOCTYPE_MAINPROC, _
								  FB_FUNCMODE_CDECL )

    symbSetProcIncFile( emit.main.proc, INVALID )

    ''
	emit.main.initlabel = symbAddLabel( NULL )
	emit.main.exitlabel = symbAddLabel( NULL )

    ''
	emit.main.node = astProcBegin( emit.main.proc, _
								   emit.main.initlabel, emit.main.exitlabel, TRUE )

	''
	env.scope = 1
	env.currproc = emit.main.proc

	arg = symbGetProcHeadArg( emit.main.proc )
	emit.main.argc = symbAddArgAsVar( symbGetName( arg ), arg )
	arg = symbGetProcTailArg( emit.main.proc )
	emit.main.argv = symbAddArgAsVar( symbGetName( arg ), arg )

	'' symbols declared in main() must go to the global tables, as main() has
	'' no beginning or end, all include files are parsed "inside" it, pure hack..
	symbSetSymbolTb( NULL )
	env.currproc = NULL
	env.scope = 0

	''
   	emitWriteRtInit( isdllmain )

   	astAdd( astNewLABEL( emit.main.initlabel ) )

end sub

'':::::
private sub hMainEnd( byval isdllmain as integer )

   	astAdd( astNewLABEL( emit.main.exitlabel ) )

    '' end( 0 )
    if( not isdllmain ) then
    	rtlExitRt( NULL )
    end if

    '' set default data label (def label isn't global as it could clash with other
    '' modules, so DataRestore alone can't figure out where to start)
    if( symbFindByNameAndClass( strptr( FB_DATALABELNAME ), FB_SYMBCLASS_LABEL ) <> NULL ) then
    	rtlDataRestore( NULL, emit.main.initnode, TRUE )
    end if

	''
	astProcEnd( emit.main.node )

end sub

':::::
private sub hModLevelBegin( )
    dim as FBSYMBOL ptr proc

	''
	proc = symbAddProc( symbPreAddProc( ), _
						strptr( "{main}" ), fbGetModuleEntry( ), NULL, _
						FB_SYMBTYPE_VOID, NULL, 0, _
						FB_ALLOCTYPE_PRIVATE or FB_ALLOCTYPE_CONSTRUCTOR or _
						FB_ALLOCTYPE_MODLEVELPROC, _
						FB_FUNCMODE_CDECL )

    symbSetProcIncFile( proc, INVALID )
    symbSetProcIsCalled( proc, TRUE )

    ''
	emit.main.initlabel = symbAddLabel( NULL )
	emit.main.exitlabel = symbAddLabel( NULL )

    ''
	emit.main.node = astProcBegin( proc, emit.main.initlabel, emit.main.exitlabel, TRUE )

	'' see hMainBegin..
	symbSetSymbolTb( NULL )
	env.currproc = NULL
	env.scope = 0

   	astAdd( astNewLABEL( emit.main.initlabel ) )

end sub

'':::::
private sub hModLevelEnd( )

   	astAdd( astNewLABEL( emit.main.exitlabel ) )

	''
	astProcEnd( emit.main.node )

end sub

'':::::
function emitOpen( ) as integer
    dim as integer isdllmain

	if( hFileExists( env.outf.name ) ) then
		kill env.outf.name
	end if

	env.outf.num = freefile
	if( open( env.outf.name, for binary, access read write, as #env.outf.num ) <> 0 ) then
		return FALSE
	end if

	'' header
	emitWriteHeader( )

	''
	if( env.outf.ismain ) then
		isdllmain = FALSE
		if( env.clopt.target = FB_COMPTARGET_WIN32 ) then
			if( env.clopt.outtype = FB_OUTTYPE_DYNAMICLIB ) then
				isdllmain = TRUE
			end if
		end if

		hMainBegin( isdllmain )

		if( isdllmain ) then
			hDllMainBegin( )
		end if
	else
		hModLevelBegin( )
	end if

	function = TRUE

end function

'':::::
sub emitClose( byval tottime as double )
	dim as integer isdllmain

    ''
    if( env.outf.ismain ) then
		isdllmain = FALSE
		if( env.clopt.target = FB_COMPTARGET_WIN32 ) then
			if( env.clopt.outtype = FB_OUTTYPE_DYNAMICLIB ) then
				isdllmain = TRUE
			end if
		end if

    	hMainEnd( isdllmain )
    else
    	hModLevelEnd( )
    end if

    ''
    emitWriteFooter( tottime )

	'' const
	emitWriteConst( symbGetGlobalTbHead( ) )

	'' data
	emitWriteData( symbGetGlobalTbHead( ) )

	'' bss
	emitWriteBss( symbGetGlobalTbHead( ) )

	''
	if( env.clopt.export ) then
		emitWriteExport( )
	end if

	''
	edbgEmitFooter( )

	''
	if( close( #env.outf.num ) <> 0 ) then
		'' ...
	end if

end sub

'':::::
sub hWriteStr( byval addtab as integer, byval s as string ) static
    dim as string ostr

	if( addtab ) then
		ostr = "\t" + s
	else
		ostr = s
	end if

	ostr += NEWLINE

	if( put( #env.outf.num, , ostr ) <> 0 ) then
		'' ...
	end if

end sub

'':::::
sub emitReset( ) static
	dim as integer c, r

	flistReset( @emit.nodeTB )
	flistReset( @emit.vregTB )

	emit.curnode = NULL

	'' reset reg usage
	for c = 0 to EMIT_REGCLASSES-1
		EMIT_REGCLEARALL( c )
	next

end sub

'':::::
sub emitFlush( ) static
    dim as EMIT_NODE ptr n

	n = flistGetHead( @emit.nodeTB )
	do while( n <> NULL )

		emit.curnode = n

		select case as const n->class

		case EMIT_NODECLASS_BOP
			cptr( EMIT_BOPCB, emit_opfTB(n->bop.op) )( n->bop.dvreg, n->bop.svreg )

		case EMIT_NODECLASS_UOP
			cptr( EMIT_UOPCB, emit_opfTB(n->uop.op ) )( n->uop.dvreg )

		case EMIT_NODECLASS_REL
			cptr( EMIT_RELCB, emit_opfTB(n->rel.op) )( n->rel.rvreg, n->rel.label, n->rel.dvreg, n->rel.svreg )

		case EMIT_NODECLASS_STK
			cptr( EMIT_STKCB, emit_opfTB(n->stk.op) )( n->stk.vreg, n->stk.extra )

		case EMIT_NODECLASS_BRC
			cptr( EMIT_BRCCB, emit_opfTB(n->brc.op) )( n->brc.vreg, n->brc.sym, n->brc.extra )

		case EMIT_NODECLASS_SOP
			cptr( EMIT_SOPCB, emit_opfTB(n->sop.op) )( n->sop.sym )

		case EMIT_NODECLASS_LIT
			cptr( EMIT_LITCB, emit_opfTB(EMIT_OP_LIT) )( n->lit.text )

			ZstrFree( n->lit.text )

		case EMIT_NODECLASS_JTB
			cptr( EMIT_JTBCB, emit_opfTB(EMIT_OP_JMPTB) )( n->jtb.dtype, n->jtb.text )

			ZstrFree( n->jtb.text )

		case EMIT_NODECLASS_MEM
			cptr( EMIT_MEMCB, emit_opfTB(n->mem.op) )( n->mem.dvreg, n->mem.svreg, n->mem.bytes )

		end select

		n = flistGetNext( n )
	loop

end sub

'':::::
function emitGetRegClass( byval dclass as integer ) as REGCLASS ptr

	function = emit.regTB(dclass)

end function

'':::::
function emitGetPos as integer static

	function = emit.pos

end function

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' procs
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitProcBegin( byval proc as FBSYMBOL ptr ) static

    proc->proc.stk.localptr = EMIT_LOCSTART
	proc->proc.stk.argptr = EMIT_ARGSTART

end sub

'':::::
sub emitProcEnd( byval proc as FBSYMBOL ptr ) static

	'' do nothing

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' node creation
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
private function hNewVR( byval v as IRVREG ptr ) as IRVREG ptr
    dim as IRVREG ptr n
    dim as integer dclass

	if( v = NULL ) then
		return NULL
	end if

	n = flistNewItem( @emit.vregTB )

	n->typ   = v->typ
	n->dtype = v->dtype
	n->sym	 = v->sym
	n->ofs	 = v->ofs
	n->mult  = v->mult
	n->value = v->value

	if( v->typ = IR_VREGTYPE_REG ) then
		dclass = irGetDataClass( v->dtype )
		n->reg = emit.regTB(dclass)->getRealReg( emit.regTB(dclass), v->reg )
		EMIT_REGSETUSED( dclass, n->reg )
	end if

	'' recursive
	n->vaux  = hNewVR( v->vaux )
	n->vidx  = hNewVR( v->vidx )

	function = n

end function

'':::::
private function hNewNode( byval class as EMIT_NODECLASS_ENUM, _
						   byval updatepos as integer = TRUE ) as EMIT_NODE ptr static
	dim as EMIT_NODE ptr n
	dim as integer i

	n = flistNewItem( @emit.nodeTB )

	n->class 	= class

	'' save register's state
	for i = 0 to EMIT_REGCLASSES-1
		n->regFreeTB(i) = emit.regTB(i)->freeTB
	next

	if( updatepos ) then
		emit.pos += 1
	end if

	function = n

end function

'':::::
private function hNewBOP( byval op as integer, _
					 	  byval dvreg as IRVREG ptr, _
			 		 	  byval svreg as IRVREG ptr ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_BOP )

	n->bop.op	 = op
	n->bop.dvreg = hNewVR( dvreg )
	n->bop.svreg = hNewVR( svreg )

	function = n

end function

'':::::
private function hNewUOP( byval op as integer, _
					 	  byval dvreg as IRVREG ptr ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_UOP )

	n->uop.op	 = op
	n->uop.dvreg = hNewVR( dvreg )

	function = n

end function

'':::::
private function hNewREL( byval op as integer, _
					 	  byval rvreg as IRVREG ptr, _
					 	  byval label as FBSYMBOL ptr, _
					 	  byval dvreg as IRVREG ptr, _
			 		 	  byval svreg as IRVREG ptr ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_REL )

	n->rel.op	 = op
	n->rel.rvreg = hNewVR( rvreg )
	n->rel.label = label
	n->rel.dvreg = hNewVR( dvreg )
	n->rel.svreg = hNewVR( svreg )

	function = n

end function

'':::::
private function hNewSTK( byval op as integer, _
					 	  byval vreg as IRVREG ptr, _
					 	  byval extra as integer = 0 ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_STK )

	n->stk.op	 = op
	n->stk.vreg  = hNewVR( vreg )
	n->stk.extra = extra

	function = n

end function

'':::::
private function hNewBRANCH( byval op as integer, _
					 	  	 byval vreg as IRVREG ptr, _
					 	  	 byval sym as FBSYMBOL ptr, _
					 	  	 byval extra as integer = 0 ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_BRC )

	n->brc.op	 = op
	n->brc.sym	 = sym
	n->brc.vreg  = hNewVR( vreg )
	n->brc.extra = extra

	function = n

end function

'':::::
private function hNewSYMOP( byval op as integer, _
					 	    byval sym as FBSYMBOL ptr ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_SOP, FALSE )

	n->sop.op	= op
	n->sop.sym	= sym

	function = n

end function

'':::::
private function hNewLIT( byval text as zstring ptr, _
						  byval doupdate as integer ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_LIT, doupdate )

	n->lit.text   = ZstrAllocate( len( *text ) )
	*n->lit.text  = *text

	function = n

end function

'':::::
private function hNewJMPTB( byval dtype as integer, _
							byval text as zstring ptr ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_JTB, FALSE )

	n->jtb.dtype = dtype
	n->jtb.text = ZstrAllocate( len( *text ) )
	*n->jtb.text = *text

	function = n

end function

'':::::
private function hNewMEM( byval op as integer, _
					 	  byval dvreg as IRVREG ptr, _
			 		 	  byval svreg as IRVREG ptr, _
			 		 	  byval bytes as integer ) as EMIT_NODE ptr static

	dim as EMIT_NODE ptr n

	n = hNewNode( EMIT_NODECLASS_MEM )

	n->mem.op	 = op
	n->mem.dvreg = hNewVR( dvreg )
	n->mem.svreg = hNewVR( svreg )
	n->mem.bytes = bytes

	function = n

end function

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' load & store
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitLOAD( byval dvreg as IRVREG ptr, _
			  byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_LOADL2L, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_LOADF2L, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_LOADI2L, dvreg, svreg )
		end select

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_LOADL2F, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_LOADF2F, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_LOADI2F, dvreg, svreg )
		end select

	case else

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_LOADL2I, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_LOADF2I, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_LOADI2I, dvreg, svreg )
		end select

	end select

end sub

'':::::
sub emitSTORE( byval dvreg as IRVREG ptr, _
			   byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_STORL2L, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_STORF2L, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_STORI2L, dvreg, svreg )
		end select

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_STORL2F, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_STORF2F, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_STORI2F, dvreg, svreg )
		end select

	case else

		select case as const svreg->dtype
		'' longint?
		case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
			hNewBOP( EMIT_OP_STORL2I, dvreg, svreg )

		'' float?
		case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
			hNewBOP( EMIT_OP_STORF2I, dvreg, svreg )

		case else
			hNewBOP( EMIT_OP_STORI2I, dvreg, svreg )
		end select

	end select

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' BOP
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitMOV( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_MOVL, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewBOP( EMIT_OP_MOVF, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_MOVI, dvreg, svreg )
	end select

end sub

'':::::
sub emitADD( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_ADDL, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewBOP( EMIT_OP_ADDF, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_ADDI, dvreg, svreg )
	end select

end sub

'':::::
sub emitSUB( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_SUBL, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewBOP( EMIT_OP_SUBF, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_SUBI, dvreg, svreg )
	end select

end sub

'':::::
sub emitMUL( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_MULL, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewBOP( EMIT_OP_MULF, dvreg, svreg )

	case else
		if( irIsSigned( dvreg->dtype ) ) then
			hNewBOP( EMIT_OP_SMULI, dvreg, svreg )
		else
			hNewBOP( EMIT_OP_MULI, dvreg, svreg )
		end if
	end select

end sub

'':::::
sub emitDIV( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_DIVF, dvreg, svreg )

end sub

'':::::
sub emitINTDIV( byval dvreg as IRVREG ptr, _
			    byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_DIVI, dvreg, svreg )

end sub

'':::::
sub emitMOD( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_MODI, dvreg, svreg )

end sub

'':::::
sub emitSHL( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_SHLL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_SHLI, dvreg, svreg )
	end select

end sub

'':::::
sub emitSHR( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_SHRL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_SHRI, dvreg, svreg )
	end select

end sub

'':::::
sub emitAND( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_ANDL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_ANDI, dvreg, svreg )
	end select

end sub

'':::::
sub emitOR( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_ORL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_ORI, dvreg, svreg )
	end select

end sub

'':::::
sub emitXOR( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_XORL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_XORI, dvreg, svreg )
	end select

end sub

'':::::
sub emitEQV( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_EQVL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_EQVI, dvreg, svreg )
	end select

end sub

'':::::
sub emitIMP( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewBOP( EMIT_OP_IMPL, dvreg, svreg )

	case else
		hNewBOP( EMIT_OP_IMPI, dvreg, svreg )
	end select

end sub

'':::::
sub emitATN2( byval dvreg as IRVREG ptr, _
			  byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_ATN2, dvreg, svreg )

end sub

'':::::
sub emitPOW( byval dvreg as IRVREG ptr, _
			 byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_POW, dvreg, svreg )

end sub

'':::::
sub emitADDROF( byval dvreg as IRVREG ptr, _
			    byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_ADDROF, dvreg, svreg )

end sub

'':::::
sub emitDEREF( byval dvreg as IRVREG ptr, _
			   byval svreg as IRVREG ptr ) static

	hNewBOP( EMIT_OP_DEREF, dvreg, svreg )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' REL
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitGT( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CGTL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CGTF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CGTI, rvreg, label, dvreg, svreg )
	end select

end sub

'':::::
sub emitLT( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CLTL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CLTF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CLTI, rvreg, label, dvreg, svreg )
	end select

end sub

'':::::
sub emitEQ( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CEQL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CEQF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CEQI, rvreg, label, dvreg, svreg )
	end select

end sub

'':::::
sub emitNE( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CNEL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CNEF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CNEI, rvreg, label, dvreg, svreg )
	end select

end sub

'':::::
sub emitGE( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CGEL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CGEF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CGEI, rvreg, label, dvreg, svreg )
	end select

end sub

'':::::
sub emitLE( byval rvreg as IRVREG ptr, _
		    byval label as FBSYMBOL ptr, _
		    byval dvreg as IRVREG ptr, _
		    byval svreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewREL( EMIT_OP_CLEL, rvreg, label, dvreg, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewREL( EMIT_OP_CLEF, rvreg, label, dvreg, svreg )

	case else
		hNewREL( EMIT_OP_CLEI, rvreg, label, dvreg, svreg )
	end select

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' UOP
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitNEG( byval dvreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewUOP( EMIT_OP_NEGL, dvreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewUOP( EMIT_OP_NEGF, dvreg )

	case else
		hNewUOP( EMIT_OP_NEGI, dvreg )
	end select

end sub

'':::::
sub emitNOT( byval dvreg as IRVREG ptr ) static

	select case dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewUOP( EMIT_OP_NOTL, dvreg )

	case else
		hNewUOP( EMIT_OP_NOTI, dvreg )
	end select

end sub

'':::::
sub emitABS( byval dvreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewUOP( EMIT_OP_ABSL, dvreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewUOP( EMIT_OP_ABSF, dvreg )

	case else
		hNewUOP( EMIT_OP_ABSI, dvreg )
	end select

end sub

'':::::
sub emitSGN( byval dvreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewUOP( EMIT_OP_SGNL, dvreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewUOP( EMIT_OP_SGNF, dvreg )

	case else
		hNewUOP( EMIT_OP_SGNI, dvreg )
	end select

end sub

'':::::
sub emitSIN( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_SIN, dvreg )

end sub

'':::::
sub emitASIN( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_ASIN, dvreg )

end sub

'':::::
sub emitCOS( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_COS, dvreg )

end sub

'':::::
sub emitACOS( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_ACOS, dvreg )

end sub

'':::::
sub emitTAN( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_TAN, dvreg )

end sub

'':::::
sub emitATAN( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_ATAN, dvreg )

end sub

'':::::
sub emitSQRT( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_SQRT, dvreg )

end sub

'':::::
sub emitLOG( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_LOG, dvreg )

end sub

'':::::
sub emitFLOOR( byval dvreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_FLOOR, dvreg )

end sub

'':::::
sub emitXchgTOS( byval svreg as IRVREG ptr ) static

	hNewUOP( EMIT_OP_XCHGTOS, svreg )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' STK
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitPUSH( byval svreg as IRVREG ptr ) static

	select case as const svreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewSTK( EMIT_OP_PUSHL, svreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewSTK( EMIT_OP_PUSHF, svreg )

	case else
		hNewSTK( EMIT_OP_PUSHI, svreg )
	end select

end sub

'':::::
sub emitPOP( byval dvreg as IRVREG ptr ) static

	select case as const dvreg->dtype
	'' longint?
	case IR_DATATYPE_LONGINT, IR_DATATYPE_ULONGINT
		hNewSTK( EMIT_OP_POPL, dvreg )

	'' float?
	case IR_DATATYPE_SINGLE, IR_DATATYPE_DOUBLE
		hNewSTK( EMIT_OP_POPF, dvreg )

	case else
		hNewSTK( EMIT_OP_POPI, dvreg )
	end select

end sub

'':::::
sub emitPUSHUDT( byval svreg as IRVREG ptr, _
				 byval sdsize as integer ) static

	hNewSTK( EMIT_OP_PUSHUDT, svreg, sdsize )

end sub

''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' MISC
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitCOMMENT( byval text as zstring ptr ) static

	hNewLIT( "##" + *text, FALSE )

end sub

'':::::
sub emitASM( byval text as zstring ptr ) static
    dim as integer c

    hNewLIT( text, TRUE )

	'' reset reg usage
	for c = 0 to EMIT_REGCLASSES-1
		EMIT_REGTRASHALL( c )						'' can't check the reg usage
	next

end sub

'':::::
sub emitLIT( byval text as zstring ptr ) static

	hNewLIT( text, FALSE )

end sub

'':::::
sub emitALIGN( byval bytes as integer ) static
    static as IRVREG vr

	vr.typ   = IR_VREGTYPE_IMM
	vr.value = bytes
	hNewUOP( EMIT_OP_ALIGN, @vr )

end sub

'':::::
sub emitSTACKALIGN( byval bytes as integer ) static
    static as IRVREG vr

	vr.typ   = IR_VREGTYPE_IMM
	vr.value = bytes
	hNewUOP( EMIT_OP_STKALIGN, @vr )

end sub

'':::::
sub emitJMPTB( byval dtype as integer, _
			   byval text as zstring ptr ) static

	hNewJMPTB( dtype, text )

end sub

'':::::
sub emitCALL( byval label as FBSYMBOL ptr, _
			  byval bytestopop as integer ) static

	hNewBRANCH( EMIT_OP_CALL, NULL, label, bytestopop )

end sub

'':::::
sub emitCALLPTR( byval svreg as IRVREG ptr, _
				 byval bytestopop as integer ) static

	hNewBRANCH( EMIT_OP_CALLPTR, svreg, NULL, bytestopop )

end sub

'':::::
sub emitBRANCH( byval op as integer, _
		 		byval label as FBSYMBOL ptr ) static

	hNewBRANCH( EMIT_OP_BRANCH, NULL, label, op )

end sub

'':::::
sub emitJUMP( byval label as FBSYMBOL ptr ) static

	hNewBRANCH( EMIT_OP_JUMP, NULL, label )

end sub

'':::::
sub emitJUMPPTR( byval svreg as IRVREG ptr ) static

	hNewBRANCH( EMIT_OP_JUMPPTR, svreg, NULL )

end sub

'':::::
sub emitRET( byval bytestopop as integer ) static
    static as IRVREG vr

	vr.typ   = IR_VREGTYPE_IMM
	vr.value = bytestopop
	hNewUOP( EMIT_OP_RET, @vr )

end sub

'':::::
sub emitLABEL( byval label as FBSYMBOL ptr ) static

	hNewSYMOP( EMIT_OP_LABEL, label )

end sub

'':::::
sub emitPUBLIC( byval label as FBSYMBOL ptr ) static

	hNewSYMOP( EMIT_OP_PUBLIC, label )

end sub


''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
'' MEM
''::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

'':::::
sub emitMEMMOVE( byval dvreg as IRVREG ptr, _
			     byval svreg as IRVREG ptr, _
			     byval bytes as integer ) static

	hNewMEM( EMIT_OP_MEMMOVE, dvreg, svreg, bytes )

end sub

'':::::
sub emitMEMSWAP( byval dvreg as IRVREG ptr, _
			     byval svreg as IRVREG ptr, _
			     byval bytes as integer ) static

	hNewMEM( EMIT_OP_MEMSWAP, dvreg, svreg, bytes )

end sub

'':::::
sub emitMEMCLEAR( byval dvreg as IRVREG ptr, _
			      byval svreg as IRVREG ptr, _
			      byval bytes as integer ) static

	hNewMEM( EMIT_OP_MEMCLEAR, dvreg, svreg, bytes )

end sub





