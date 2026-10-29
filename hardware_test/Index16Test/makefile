all:
	z88dk-z80asm -Oobj -oindex16.bin -b -l -m index16_test.asm
	cmd /c copy /b obj\index16.bin bin\index16.com
	z88dk-z80asm -Oobj -oi16m2.bin -b -l -m index16_m2.asm
	cmd /c copy /b obj\i16m2.bin bin\i16m2.com
