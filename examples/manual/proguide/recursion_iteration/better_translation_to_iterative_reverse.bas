'' examples/manual/proguide/recursion_iteration/better_translation_to_iterative_reverse.bas
''
'' NOTICE: This file is part of the FreeBASIC Compiler package and can't
''         be included in other distributions without authorization.
''
'' See Also: https://www.freebasic.net/wiki/wikka.php?wakka=ProPgRecursionIteration
'' --------

Function betterTranslationToIterativeReverse (ByVal s As String) As String
	Dim As String cumul = ""
	While Not (s = "")              '' end condition of iterative loop
		cumul = Left(s, 1) & cumul  '' iterative accumulation
		s = Mid(s, 2)
	Wend
	Return cumul
End Function
		
