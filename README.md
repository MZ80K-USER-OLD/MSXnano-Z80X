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

## Tang Nano 20K Dock

This Board  for Tang Nano 20K project is BBC-Micro Board by  [hoglet67](https://github.com/hoglet67)[TangNano20KDock](https://github.com/hoglet67/TangNano20KDock)

 Project url  https://github.com/hoglet67/TangNano20KDock 

 There is a his shop on eBay  https://www.ebay.com/itm/267692589127, 

![TangNano20kDock](D:\Users\HeroineFactory\Documents\GIT\MSXNano-Z80X\msxnano-beeb_dock\pics\TangNano20kDock.png)



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



