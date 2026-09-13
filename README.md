# MSXnano on TangNano20KDock
MSX2+ core for the Tang Nano 20k and TangNano20KDock

* Z80
* V9958 with hdmi output
* MSX2+ BIOS
* SD Card support + Nextor 2.1
* 4MB mapper
* 2MB megaram SCC
* RTC
* PSG
* OPLL
* PS/2 KeyBoard Interface
* Tang Nano 20K Dock joystick interface

## Joystick interface

The Tang Nano 20K Dock joystick is read through a serial 74LV165-style
interface and exposed through the MSX PSG.

| Dock signal | FPGA signal | FPGA pin | Direction |
|-------------|-------------|----------|-----------|
| JS_Clk / PHI2 | `js_clk` | 71 | FPGA to Dock |
| JS_Load_N | `js_load_n` | 72 | FPGA to Dock |
| JS_Data | `js_data` | 76 | Dock to FPGA |

`js_clk` is generated from the 3.6 MHz bus clock. The same clock is used as
the Tube parasite-side PHI2 signal when `USE_TUBE` is enabled, so pin 71 is
shared by the joystick clock and Tube PHI2.

The FPGA samples the serialized joystick frame on the falling edge of PHI2,
decodes joystick 1 and joystick 2, and presents the selected joystick through
YM2149 PSG port A (R#14). PSG port B bit 6 (R#15) selects joystick 1 when it
is 0 and joystick 2 when it is 1. The Z80 reads the selected joystick value
from I/O port `A2H`.

## Tube interface

The Acorn Tube core is enabled by the `USE_TUBE` definition in
`fpga/top_BeebDock.v`. The MSX Z80 accesses the Tube registers at I/O ports
`00H` through `07H`. The Host-side Tube signals are generated from the Z80
I/O cycle and are sent to the external CoProcessor through the LED pins.

| LED signal | Tube Host signal | FPGA pin |
|------------|------------------|----------|
| `led[5]` | Host reset | 20 |
| `led[4]` | `h_addr[2]` | 19 |
| `led[3]` | `h_addr[1]` | 18 |
| `led[2]` | `h_cs_b` (`host_cs_n`) | 17 |
| `led[1]` | `h_rdnw` (`host_rnw`) | 16 |
| `led[0]` | `h_addr[0]` | 15 |

The Tube data bus is bidirectional. In Tube mode, the eight VGA signals are
used as the physical data lines and are connected to the Tube data bus with
tri-state connections. The Tube wrapper drives the bus only when the
external Parasite side is selected for a read; otherwise it releases the bus
so that the external side can write data to the Tube.

Pin 71 is shared by the joystick clock and Tube PHI2. Both functions use the
same `dock_phi2` signal, which is derived from the 3.6 MHz bus clock. The
joystick function remains available while the Tube interface is enabled.

### I/O Ports and Registers

The MSX (Host Z80) accesses Tube registers mapped from I/O ports `00H` to `07H`:

| Port | Register | Access | Function |
|------|----------|--------|----------|
| `00H` | R0 Status / Control | Read / Write | Read: Status (Bit 7: Data Available, Bit 6: Not Full, Bits 5-0: Control flags)<br>Write: Control flag modification |
| `01H` | R1 Data | Read / Write | 1-byte FIFO data register |
| `02H` | R2 Status | Read | Status (Bit 7: Data Available, Bit 6: Not Full) |
| `03H` | R2 Data | Read / Write | 1-byte FIFO data register |
| `04H` | R3 Status | Read | Status (Bit 7: Data Available / N-flag, Bit 6: Not Full) |
| `05H` | R3 Data | Read / Write | 2-byte (or 1-byte) FIFO data register (used for fast data transfer / DMA) |
| `06H` | R4 Status | Read | Status (Bit 7: Data Available, Bit 6: Not Full) |
| `07H` | R4 Data | Read / Write | Multi-byte (24-byte) FIFO data register |

#### R0 Control Flags (Write to `00H`)
Writing to `00H` configures the Tube control flags using Bit 7 (`S`) as the set/clear mask selector:
- **Bit 7 (`S`)**: Set mask (1 = Set specified flags to 1, 0 = Clear specified flags to 0).
- **Bit 6 (`T`)**: Soft reset (clears all Tube registers).
- **Bit 5 (`P`)**: CoProcessor reset (`PRST`).
- **Bit 4 (`V`)**: R3 2-byte mode enable (0 = 1-byte mode, 1 = 2-byte mode).
- **Bit 3 (`M`)**: Enable Parasite NMI (`PNMI`) from R3.
- **Bit 2 (`J`)**: Enable Parasite IRQ (`PIRQ`) from R4.
- **Bit 1 (`I`)**: Enable Parasite IRQ (`PIRQ`) from R1.
- **Bit 0 (`Q`)**: Enable Host IRQ (`HIRQ`) from R4.

### Interrupt Generation

The Tube ULA handles host and co-processor (parasite) interrupts based on FIFO status and control flags:

1. **Host IRQ (`HIRQ` / `irq_n` to MSX Z80)**:
   - Triggered when **Bit 0 (`Q`)** is enabled (`1`) and data is available in the Parasite-to-Host R4 FIFO (`h_data_available[3]` = 1).
2. **Co-Processor IRQ (`PIRQ` / `tube_p_irq_n`)**:
   - Triggered when **Bit 1 (`I`)** is enabled (`1`) and data is available in Host-to-Parasite R1 FIFO.
   - Triggered when **Bit 2 (`J`)** is enabled (`1`) and data is available in Host-to-Parasite R4 FIFO.
3. **Co-Processor NMI (`PNMI` / `tube_p_nmi_n`)**:
   - Triggered when **Bit 3 (`M`)** is enabled (`1`) based on R3 FIFO status (single/double byte availability controlled by `V` flag).

### Transmission and Reception Procedures

#### Sending Data (Host to Co-Processor)
1. **Poll Status**: Read the Status Register of the target channel (`00H`, `02H`, `04H`, or `06H`) and check **Bit 6 (Not Full)**.
2. **Write Data**: When Bit 6 is `1`, write data byte(s) to the corresponding Data Register (`01H`, `03H`, `05H`, or `07H`).
3. **Interrupt Handling (Optional)**: If Co-Processor interrupts are enabled (`I` or `J` flag set in R0), writing to R1 or R4 automatically asserts `PIRQ` on the Co-Processor side to notify it of incoming data.

#### Receiving Data (Co-Processor to Host)
1. **Poll Status or Interrupt**:
   - **Polling Mode**: Read the Status Register (`00H`, `02H`, `04H`, or `06H`) and check **Bit 7 (Data Available)**.
   - **Interrupt Mode**: Enable `Q` flag in R0 (`OUT (&H00), &H81`). When the Co-Processor writes data to R4, the MSX Z80 receives an interrupt (`irq_n`).
2. **Read Data**: When Data Available is `1` (or inside the IRQ handler), read data byte(s) from the corresponding Data Register (`01H`, `03H`, `05H`, or `07H`).

## PS/2 keyboard interface

The PS/2 keyboard is connected directly to the FPGA and is converted to the
MSX keyboard matrix by the USB keyboard mapping logic.

| PS/2 signal | FPGA signal | FPGA pin | Direction |
|-------------|-------------|----------|-----------|
| Clock | `ps2_clk` | 73 | Bidirectional |
| Data | `ps2_data` | 74 | Bidirectional |

`ps2_hid_bridge` receives PS/2 scan codes and produces the internal keyboard
state vector. `usb_keyboard_msx` maps that vector to the MSX keyboard matrix.
The keyboard row is selected through the PPI port C lower four bits, and the
selected row is returned through PPI port B. The Z80 reads the keyboard row
from I/O port `A9H` after selecting the row through I/O port `AAH`.

## Tang Nano 20K Dock

This Board  for Tang Nano 20K project is BBC-Micro Board by  [hoglet67](https://github.com/hoglet67)[TangNano20KDock](https://github.com/hoglet67/TangNano20KDock)

 Project url  https://github.com/hoglet67/TangNano20KDock 

 There is a his shop on eBay  https://www.ebay.com/itm/267692589127, 

https://github.com/MZ80K-



![TangNano20kDock](D:\users\HeroineFactory\Documents\GIT\MSXNano-Z80X\msxnano-beeb_dock\pics\TangNano20kDock.png)




## Slot map

Slot map has been updated to improve compatibility without requiring changes.

![mapa_slots4](D:\Users\HeroineFactory\Documents\GIT\MSXNano-Z80X\msxnano-24bit\pics\mapa_slots4.png)

Mapper and megaram can be relocated to slots 1 or 2 using config menu.

## Megaram + Sofarun
Megaram is detected automatically by sofarun using default settings. When using other software you may need to indicate location, Slot 3-3 by default.



![Config](https://github.com/Papipapito/MSXgoauldSD_usbkb/raw/main/pics/config6.png)

## Known issues
* Tape games fail: use poke -1,0

## Flashing
Progamming is done in three steps:
* Flash firmware MSXNanoTang20KBeebDock.fs
* Flash FPGA Companion firmware (https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C)
* Flash disk rom. MSXnano uses the same driver as Wondertang, Nextor-2.1.1.WonderTANG.ROM.bin. Flash Address = 0x100000 (subject to change)



| Step | File                                         | Address    | Tool                                                         | Notes                |
| ---- | -------------------------------------------- | ---------- | ------------------------------------------------------------ | -------------------- |
| 1    | MSXNanoTang20KBeebDock.fs                    | `0x000000` | [Gowin Programmer](https://www.gowinsemi.com/en/support/download_eda/) | External Flash mode  |
| 2    | Wondertang, Nextor-2.1.1.WonderTANG.ROM.bin. | 0x100000   | [BLFlashCube](https://dev.bouffalolab.com/download)          | HExternal Flash mode |

## 
## This Standalone FPGA version of MSXgoauldSD_tn20k

This project is based on MSXnano  by https://github.com/RetroSilicon under GPLv3.

This branch (`standalone`) contains a standalone FPGA implementation.  
All hardware-related files from the original project (PCB, MSX interface, schematics, etc.) have been intentionally removed, because this version does not rely on the original physical hardware.



