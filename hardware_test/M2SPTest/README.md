# M2SPTEST.COM: 24-bit Arithmetic, TEST, and M2 MSP24

MSX-DOS hardware test for all ten `TEST`/`TEST24` encodings and the M2
stack-pointer behavior. It is intended for a bitstream containing the updated
CPU RTL. Do not use an older bitstream: an unsupported opcode may be treated
as a NOP and make the test report failures.

## Run

Build with Z88DK from this directory:

```powershell
$env:Path = "D:\Tool\z88dk\bin;" + $env:Path
make
```

Copy [bin/m2sptest.com](bin/m2sptest.com) to an MSX-DOS disk and run:

```text
A>M2SPTEST
```

Expected output:

```text
M2SPTEST: 24-bit arithmetic + TEST/TEST24 + MSP24
PASS=58 FAIL=00
```

The 58 is hexadecimal (88 byte-level checks). If a check fails, the program
prints the first check index and its actual/expected byte.

## Coverage

- Each 16-bit `TEST` (`BC`, `DE`, `HL`, `IX`, `IY`) with zero and nonzero word
  values. Zero-word cases use a nonzero bank to verify that 16-bit `TEST`
  ignores the bank byte.
- Each `TEST24` form with a zero 24-bit value and a nonzero bank with a zero
  word, checking that the bank participates in the zero test.
- `INC SP` and `DEC SP` carry/borrow across the 16-bit and 24-bit MSP boundaries.
- M2 `LD SP,HL`, `LD SP,IX`, and `LD SP,IY` copy the source bank as well as the
  low word.
- IX24 `ADD/ADC/INC/DEC` and IY24 `SBC/ADD/DEC/INC`, including carry/borrow
  into or out of the bank byte.
- IX/IY `PUSH24/POP24` same-register and cross-register round trips; MSP24 is
  checked after the balanced operations.
- WTOC after wrapping and non-wrapping 16-bit `INC/DEC` on BC/DE, and after
  wrapping `INC IX` / `DEC IY`, checking the complete F byte and carry transfer.
- The ordinary SP remains unchanged.

The test holds interrupts disabled while using M2. It restores the saved
MSP24, IBR, I register, and pair/index bank registers before returning to DOS.
The temporary M2 call stack uses bank `02`, addresses `F000` downward; TEST
instructions and result storage execute in bank `00`.

This program does not validate M0 NOP behavior or M2 interrupt handling.
Simulation is not a substitute for running it on the target FPGA/MSX hardware.

The assembled COM can also be run through the repository's CPU/BDOS simulation
in four CPU-speed/WAIT combinations:

```powershell
& .\fpga\G80A\test\run_m2sp_com.ps1
```
