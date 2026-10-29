all:
	@if not exist bin mkdir bin
	z88dk-z80asm -Oobj -ov161test.com -b v161_test.asm
	cmd /c copy /b obj\v161test.com bin\v161test.com
