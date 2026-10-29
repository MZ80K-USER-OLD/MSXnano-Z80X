# I161TEST.COM execution verification

See the [hardware test documentation](../../hardware_test/V161IRQTest/README.md)
for execution, expected output, memory allocation and hardware limitations.
No CPU RTL changes were made for this test.

## Records

- [Diagnostic full-matrix attempt](summary.json):
  Normal/Fast x WAIT disabled/enabled x handler marker fault disabled/enabled.
  A complete run requires `PASS=04 FAIL=00`; injected faults require
  `PASS=00 FAIL=04`, with all four cases reporting offset 13, A5 instead of 5A.
- [Focused positive diagnostic run](../v161_irq_com_smoke/summary.json):
  updated COM, Normal, no WAIT, no injection; `PASS=04 FAIL=00`.
- [Earlier no-interrupt negative control](../v161_irq_com_no_irq/summary.json):
  the COM must terminate and report all four interrupt-count timeouts as FAIL.

The latest diagnostic full-matrix attempt was deliberately stopped for runtime
after three of eight runs. `summary.json` remains `complete=false`; its partial
logs are not a full-matrix PASS claim. The focused current-source run is the
durable verification for the added VDP status selection and color markers.
The earlier negative control was run on the pre-diagnostic COM. The CPU RTL
was not changed for the diagnostic revision.

Every run executes the assembled COM, including comparisons, diagnostics,
BDOS calls and DOS termination. The three physical banks are independent.
The VDP model is limited to periodic level IRQ, R#1 writes and status-port
acknowledgement. Any status read resets the VDP control-port write latch;
reading S#0 also acknowledges the vertical IRQ. In M2, interrupt acknowledge
alone does not clear the IRQ.
The IM2 acknowledge vector is FF, and both reads are asserted to be
02:FFFF and 02:0000.

Successful IRQ runs require exactly eight M2 IRQ acceptances,
32 IRQ frame-byte writes, eight IM2 table-byte reads, and four M2 entries.
The no-IRQ control requires zero acceptances/frame writes/table reads in M2.
The benchmark also checks M0-only BDOS calls and absence of extended-bank
writes to the legacy expanded-slot register.

The shared harness models BDOS functions 2/9 enabling interrupts before return.
I161TEST explicitly executes DI after each output service. The shared harness remains compatible with the unchanged V161TEST and four
indexed COMs; the diagnostic revision only enables VDP register emulation in
the IRQ-specific generic. Existing V161TEST hardware evidence is retained
separately from its simulation outcome within its summary.

These simulations are not hardware PASS results and do not implement the
physical SDRAM or MSX-DOS itself. Actual NMI, RETN.L, nested IRQ, daisy-chain
RETI notification and all interrupt acknowledge vectors are outside scope.
