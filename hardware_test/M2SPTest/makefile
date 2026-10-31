all:
	@if not exist bin mkdir bin
	z88dk-z80asm -Oobj -om2sptest.com -b m2sp_test.asm
	cmd /c copy /b obj\m2sptest.com bin\m2sptest.com
