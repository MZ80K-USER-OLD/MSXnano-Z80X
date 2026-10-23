SRCS := ld24_mem_indirect_test.asm

# This environment's GNU make does not see ComSpec as a make variable, so
# `ifdef ComSpec` style detection (as used by ../Editor/makefile) silently
# falls through to the POSIX branch and invokes a non-existent "cp"/"rm"
# executable. Invoke cmd.exe explicitly instead, which is always present
# on Windows regardless of how make resolves environment variables.
RMF	:= cmd /c del /f /q
CP	:= cmd /c copy /b
/	:= $(strip \)

all: ld24mi.com

ld24mi.com: $(SRCS)
	@echo Assembling MSX edition..
	z88dk-z80asm -DMSXBIOS -Oobj -oBINZ80.bin -b -d -l -m $(SRCS)
	z88dk-appmake +glue -b obj$/BINZ80 --filler 0x00
	$(CP) obj$/BINZ80__.bin  bin$/ld24mi.com
	@echo done

clean:
	$(RMF) obj$/*
	$(RMF) BINZ80$/*
	@echo Cleanup done
