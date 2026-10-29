all:
	@if not exist bin mkdir bin
	z88dk-z80asm -Oobj -oi161test.com -b i161_test.asm
	cmd /c copy /b obj\i161test.com bin\i161test.com
