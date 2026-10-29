all:
	z88dk-z80asm -Oobj -oindex24.bin -b -l -m index24_test.asm
	cmd /c copy /b obj\index24.bin bin\index24.com
	z88dk-z80asm -Oobj -oi24m2.bin -b -l -m index24_m2.asm
	cmd /c copy /b obj\i24m2.bin bin\i24m2.com
