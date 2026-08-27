# BeebFPGA Tang Nano 20K Dock - Tube Pin Assignment

This document provides the pin assignment between the Tang Nano 20K FPGA and the Raspberry Pi GPIO header configured as the Tube interface for BeebFPGA (primarily used for PiTubeDirect).

## 📌 Tube / Raspberry Pi GPIO Pin Assignment Table

| Schematic Signal Name | FPGA Pin Number | Pi GPIO Pin Number | Pi Broadcom (BCM) GPIO | Description / Role |
| :--- | :---: | :---: | :---: | :--- |
| **TUBE_D0** | **Pin 25** | Pin 15 | GPIO 22 | Data Bus Bit 0 |
| **TUBE_D1** | **Pin 26** | Pin 16 | GPIO 23 | Data Bus Bit 1 |
| **TUBE_D2** | **Pin 29** | Pin 18 | GPIO 24 | Data Bus Bit 2 |
| **TUBE_D3** | **Pin 30** | Pin 22 | GPIO 25 | Data Bus Bit 3 |
| **TUBE_D4** | **Pin 31** | Pin 37 | GPIO 26 | Data Bus Bit 4 |
| **TUBE_D5** | **Pin 32** | Pin 13 | GPIO 27 | Data Bus Bit 5 |
| **TUBE_D6** | **Pin 41** | Pin 11 | GPIO 17 | Data Bus Bit 6 |
| **TUBE_D7** | **Pin 42** | Pin 12 | GPIO 18 | Data Bus Bit 7 |
| **TUBE_A0** | **Pin 76** | Pin 7 | GPIO 4 | Address Bus Bit 0 |
| **TUBE_A1** | **Pin 80** | Pin 36 | GPIO 16 | Address Bus Bit 1 |
| **TUBE_A2** | **Pin 48** | Pin 38 | GPIO 20 | Address Bus Bit 2 |
| **TUBE_nRST** | **Pin 49** | Pin 40 | GPIO 21 | Tube Reset (Active Low) |
| **TUBE_nNTI** | **Pin 51** | Pin 29 | GPIO 5 | Not Triangle Interrupt (Active Low) |
| **TUBE_nIRQ** | **Pin 54** | Pin 31 | GPIO 6 | Interrupt Request (Active Low) |
| **TUBE_nWR** | **Pin 55** | Pin 33 | GPIO 13 | Write Enable (Active Low) |
| **TUBE_nRD** | **Pin 56** | Pin 35 | GPIO 19 | Read Enable (Active Low) |

---

## 🔍 Notes and Supplementary Information

### 1. Power and Ground Supply
* **5V Power:** Supplied to Raspberry Pi GPIO **Pin 2** and **Pin 4**.
* **3.3V Power:** Connected to **Pin 1**.
* **Ground (GND):** **Pin 6, 9, 14, 20, 25, 30, 34, 39** are tied to the common ground plane of the FPGA and Dock board.

### 2. Voltage Levels and Direct Connection
* The I/O banks of the **Gowin GW2AR-LV18QN88C8** FPGA on Tang Nano 20K operate at **3.3V LVCMOS**.
* Since Raspberry Pi's GPIO pins are also strictly 3.3V logic, this board utilizes a **direct, 1-to-1 parallel layout** without any level-shifting ICs. Do not connect any 5V logic devices to these signal pins.

### 3. SPI Communication is NOT Used
* **Parallel Interface Architecture:** The original BBC Micro Tube port relies completely on an 8-bit parallel architecture. 
* **PiTubeDirect Operation:** PiTubeDirect drives communication by polling and writing to the entire Raspberry Pi GPIO register at a high-speed parallel level. It does not implement SPI or other serial bus protocols for Tube co-processor operation.
* *Note:* SPI is reserved strictly for onboard functions such as the 64Mbit SPI Flash for FPGA bitstream loading and separate MicroSD card storage logic.

---
*Reference: hoglet67/TangNano20KDock official schematics.*
