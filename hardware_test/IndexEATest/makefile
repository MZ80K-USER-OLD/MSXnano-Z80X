all:
	@if not exist bin mkdir bin
	z88dk-z80asm -Oobj -oindexea.com -b indexea_test.asm
	cmd /c copy /b obj\indexea.com bin\indexea.com
