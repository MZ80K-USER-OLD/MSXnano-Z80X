all:
	@if not exist bin mkdir bin
	z88dk-z80asm -Oobj -oh161test.com -b h161_test.asm
	cmd /c copy /b obj\h161test.com bin\h161test.com
