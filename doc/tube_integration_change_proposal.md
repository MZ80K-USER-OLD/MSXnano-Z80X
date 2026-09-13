# Tube Integration Change Proposal

## Applied changes

`src/tube/msxnano_tube.v` provides the MSX I/O host interface for the Tube
core. It reserves the fixed I/O range `00H` through `07H`; `io_addr[2:0]`
selects the corresponding Tube register.

All Tube Verilog source files, including the wrapper, are listed in
`MSXNanoTang20KBeebDock.gprj` so that the core is available to the top level.

## Top-level wiring to add after data pins are confirmed

The wrapper exports the external Tube parasite interface. The control signals
from the supplied pin-assignment note map as follows:

| FPGA pin | Tube signal | Wrapper signal |
| --- | --- | --- |
| 15 | `A0` | `tube_p_addr[0]` |
| 16 | `RnW` | `tube_p_rdnw` |
| 17 | `nTUBE` | `tube_p_cs_n` |
| 18 | `A1` | `tube_p_addr[1]` |
| 19 | `A2` | `tube_p_addr[2]` |
| 20 | `nRST` | `tube_p_reset_n` |
| 71 | `PHI2` | `tube_p_phi2` |

The existing CST maps `led[0]` through `led[5]` to pins 20 through 15 in the
opposite order. When Tube is wired into `top_BeebDock.v`, replace that LED
debug output with explicit Tube ports and constraints rather than reusing the
current LED bit order.

## Required hardware confirmation

The host/parasite data exchange requires `tube_p_data_in[7:0]` and
`tube_p_data_out[7:0]`. The supplied note identifies the DOCK J2 data nets but
does not identify their FPGA package pins. Do not add unconstrained top-level
data ports or assign arbitrary package pins: confirm all eight FPGA pins from
the DOCK schematic or a known-good BeebFPGA CST first.

Pin 71 is currently used as `js_clk`, and pin 76 is `js_data`. Tube mode
therefore conflicts with the DOCK joystick interface. Disable the joystick
port constraints and its top-level instance when the Tube pins are enabled;
the BL616 pin 76 assignment is already disabled in the current CST.