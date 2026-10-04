# MSXnano-Z80X / Tang Nano 20K Dock — Tubeインタフェース実装仕様（修正版）

## 1. 対象

- Repository: `MZ80K-USER-OLD/MSXnano-Z80X`
- Branch: `feature/beeb-dock`
- Top: `fpga/top_BeebDock.v`

参照: https://github.com/MZ80K-USER-OLD/MSXnano-Z80X/blob/feature/beeb-dock/fpga/top_BeebDock.v

このブランチでは、Tube ULA/FIFOをFPGA内の`tube.v`として実装するのではなく、**外部PiTubeDirect側のTube ULA/FIFOへZ80 I/Oバスを直接接続する構成**になっている。`top_BeebDock.v`にも「The external device owns the Tube ULA/FIFOs」と明記されている。

## 2. 全体構成

```text
MSXnano Z80
   |
   | I/O B8h-BFh
   v
top_BeebDock.v
   |
   +-- ext_copro_addr[2:0]
   +-- ext_copro_cs_n
   +-- ext_copro_rdnw
   +-- ext_copro_reset_n
   +-- ext_copro_data[7:0]
   |
   | VGA/Tube shared pins
   v
Tang Nano 20K Dock
   |
   v
Raspberry Pi / PiTubeDirect
   |
   v
External Tube ULA/FIFO
```

## 3. Tube I/O address

`top_BeebDock.v`では:

```verilog
localparam [7:0] TUBE_IO_BASE = 8'hB8;
```

`tube_req`は`bus_addr[7:3] == TUBE_IO_BASE[7:3]`で生成されるため、Tube範囲は`B8h-BFh`。

| Z80 I/O | A2:A0 | Tube |
|---:|---:|---|
| `B8h` | 000 | R0 Control/Status |
| `B9h` | 001 | R1 Data |
| `BAh` | 010 | R2 Status |
| `BBh` | 011 | R2 Data |
| `BCh` | 100 | R3 Status |
| `BDh` | 101 | R3 Data |
| `BEh` | 110 | R4 Status |
| `BFh` | 111 | R4 Data |

Z80定義:

```asm
TUBE_R0   EQU 0B8H
TUBE_R1   EQU 0B9H
TUBE_R2   EQU 0BAH
TUBE_R2D  EQU 0BBH
TUBE_R3   EQU 0BCH
TUBE_R3D  EQU 0BDH
TUBE_R4   EQU 0BEH
TUBE_R4D  EQU 0BFH
```

以前の`F8h-FFh`案は、このブランチには適用しない。

## 4. RTL接続

```verilog
assign ext_copro_addr = bus_addr[2:0];
assign ext_copro_cs_n = ~tube_req;
assign ext_copro_rdnw = tube_req_r;
assign ext_copro_reset_n = bus_reset_n;
assign ext_copro_data = tube_req_w ? cpu_dout : 8'bz;
```

従って、

```text
Z80 A2:A0 -> ext_copro_addr
Tube request -> ext_copro_cs_n
Z80 write data -> ext_copro_data
external read data -> ext_copro_data -> cpu_din
```

という直接接続である。

## 5. VGA/Tube data bus共有

Tube data busはVGAピンと共有される。

| Tube D | Pin |
|---:|---|
| D7 | `vga_g` |
| D6 | `vga_b_n` |
| D5 | `vga_vs` |
| D4 | `vga_hs` |
| D3 | `vga_r_n` |
| D2 | `vga_b` |
| D1 | `vga_g_n` |
| D0 | `vga_r` |

RTLは`tran`で双方向接続している。

```verilog
tran (ext_copro_data[7], vga_g);
tran (ext_copro_data[6], vga_b_n);
tran (ext_copro_data[5], vga_vs);
tran (ext_copro_data[4], vga_hs);
tran (ext_copro_data[3], vga_r_n);
tran (ext_copro_data[2], vga_b);
tran (ext_copro_data[1], vga_g_n);
tran (ext_copro_data[0], vga_r);
```

## 6. Reset

現行RTL:

```verilog
assign ext_copro_reset_n = bus_reset_n;
```

つまり外部CoPro resetはMSXnanoの`bus_reset_n`に直結している。

これは`tube.v`のR0 P bitによるCoPro resetとは別物。

したがって、以前の

```text
A0h = P set
20h = P clear
```

という説明は、**標準Tube ULAのR0 protocolとしては正しいが、現行`top_BeebDock.v`のFPGA reset信号を直接操作するものではない**。

## 7. Host IRQの重要な現状

現行RTLには:

```verilog
wire tube_irq_n = 1'b1;
```

がある。

Z80 CPU:

```verilog
.INT_n (bus_int_n & vdp_int & tube_irq_n)
```

なので、現状はTube IRQがZ80 INTへ接続されていない。

したがって、現時点のZ80 Tube driverは**polling方式を基本とする**。

将来IRQを追加する場合は:

```text
PiTubeDirect IRQ
   -> tube_irq_n
   -> Z80 INT_n
```

の経路を追加し、PiTubeDirect側のIRQ極性とDock pinを確認する。

## 8. 標準Tube R0

hoglet67/BeebFpga `tube.v`を標準Tube ULAのRTLリファレンスとして扱う。

R0 control:

| Bit | 名称 | 機能 |
|---:|---|---|
| 7 | S | Set/Clear |
| 6 | T | Tube soft reset |
| 5 | P | CoPro reset |
| 4 | V | R3 two-byte mode |
| 3 | M | R3 NMI enable |
| 2 | J | CoPro IRQ from R4 |
| 1 | I | CoPro IRQ from R1 |
| 0 | Q | Host IRQ from R4 |

代表値:

| 値 | 意味 |
|---:|---|
| `8Eh` | M+J+I set |
| `92h` | V+I set |
| `12h` | V+I clear |
| `A0h` | P set |
| `20h` | P clear |
| `C0h` | T set |
| `81h` | Q set |
| `82h` | I set |
| `84h` | J set |
| `88h` | M set |
| `90h` | V set |
| `10h` | V clear |

`8Eh`はNFS初期化で使用され、M/J/Iを有効化する。

## 9. R0 read

概念的には:

| Bit | 内容 |
|---:|---|
| 7 | R1 CoPro→Host data available |
| 6 | R1 Host→CoPro FIFO not full |
| 5..0 | P,V,M,J,I,Q |

Tはread-backされない。

## 10. R2/R3/R4 status

標準Tube:

```text
bit 7 = data available
bit 6 = FIFO not full
bit 5..0 = 1
```

## 11. IRQ/NMI

標準Tube RTLでは:

```text
Host IRQ:
Q=1 + R4 CoPro->Host data available

CoPro IRQ:
I=1 + R1 Host->CoPro data available
J=1 + R4 Host->CoPro data available

CoPro NMI:
M=1 + R3 availability condition
```

ただし現行`top_BeebDock.v`ではHost IRQが未接続なので、これらは外部Tube ULAのprotocol仕様として扱う。

## 12. NFS R2 command table

| R2 command | 機能 |
|---:|---|
| `00h` | OSRDCH |
| `01h` | OSCLI |
| `02h` | OSBYTE short |
| `03h` | OSBYTE long |
| `04h` | OSWORD |
| `05h` | OSWORD 0 / Read Line |
| `06h` | restore registers |
| `07h` | restore registers + RTS |
| `08h` | OSARGS |
| `09h` | OSBGET |
| `0Ah` | OSBPUT |
| `0Bh` | OSFIND |
| `0Ch` | OSFILE |
| `0Dh` | OSGBPB |

## 13. OSWRCH

CoPro→Host:

```text
R1 <- character
```

Host→CoPro:

```text
R2 <- 00h
R2 <- character
```

## 14. OSCLI

CoPro→Host:

```text
R2 <- 01h
R2 <- command bytes
R2 <- 0Dh
```

完了:

```text
Host -> CoPro
R2 <- 7Fh
```

## 15. OSBYTE short

```text
CoPro -> Host:
02h, X, A

Host -> CoPro:
X
```

## 16. OSBYTE long

```text
CoPro -> Host:
03h, X, Y, A

Host -> CoPro:
status/carry
Y
X
```

Carryはbit 7にエンコードされる。

## 17. OSWORD

```text
CoPro -> Host:
04h
OSWORD number
parameter length
parameter bytes
```

Host:

```text
FFh
```

その後:

```text
CoPro -> Host:
result length

Host -> CoPro:
result bytes
```

これは往復handshakeである。

## 18. OSWORD 0 / Read Line

```text
CoPro -> Host:
05h
5-byte control block
```

正常:

```text
line data
0Dh
```

Escape:

```text
FFh
```

## 19. OSFILE

```text
CoPro -> Host:
0Ch
16-byte control block
filename
0Dh
reason
```

Host→CoPro:

```text
result
updated 16-byte control block
```

結果を常に`FFh`と仮定しない。

## 20. OSGBPB

```text
CoPro -> Host:
0Dh
13-byte parameter block
function
```

Host→CoPro:

```text
carry/status
updated 13-byte block
```

大量転送ではR3との関係を考慮する。

## 21. Error / BRK

Host→CoPro:

```text
R4 <- FFh
R2 <- 00h
R2 <- error number
R2 <- error string
R2 <- 00h
```

## 22. R3

R3は高速転送用の特殊register。

```text
M = R3 NMI enable
V = R3 two-byte mode
```

標準Tubeの能力とPiTubeDirect個別実装の制限を分けて評価する。

## 23. Z80 low-level driver

```asm
TUBE_R0   EQU 0B8H
TUBE_R1   EQU 0B9H
TUBE_R2   EQU 0BAH
TUBE_R2D  EQU 0BBH
TUBE_R3   EQU 0BCH
TUBE_R3D  EQU 0BDH
TUBE_R4   EQU 0BEH
TUBE_R4D  EQU 0BFH
```

R1 receive:

```asm
TUBE_R1_GET:
.wait:
        IN   A,(TUBE_R0)
        BIT  7,A
        JR   Z,.wait
        IN   A,(TUBE_R1)
        RET
```

R1 send:

```asm
TUBE_R1_PUT:
        PUSH AF
.wait:
        IN   A,(TUBE_R0)
        BIT  6,A
        JR   Z,.wait
        POP  AF
        OUT  (TUBE_R1),A
        RET
```

R2 receive:

```asm
TUBE_R2_GET:
.wait:
        IN   A,(TUBE_R2)
        BIT  7,A
        JR   Z,.wait
        IN   A,(TUBE_R2D)
        RET
```

R2 send:

```asm
TUBE_R2_PUT:
        PUSH AF
.wait:
        IN   A,(TUBE_R2)
        BIT  6,A
        JR   Z,.wait
        POP  AF
        OUT  (TUBE_R2D),A
        RET
```

## 24. 推奨API

```text
TUBE_INIT
TUBE_RESET
TUBE_COPRO_RESET
TUBE_COPRO_START

TUBE_R1_GET
TUBE_R1_PUT
TUBE_R2_GET
TUBE_R2_PUT
TUBE_R3_GET
TUBE_R3_PUT
TUBE_R4_GET
TUBE_R4_PUT

TUBE_IRQ_HANDLER   ; IRQ追加時
```

ただし`TUBE_COPRO_RESET`は現行RTLではR0 P bitによるFPGA側resetではなく、外部Tube ULAのprotocol操作として扱う。

## 25. 実機試験順序

1. `IN A,(B8h)` — R0 read
2. `IN A,(BAh)` — R2 status
3. `OUT (BBh),A` — R2 write
4. PiTubeDirectからR2 dataを送り、R2 bit7を確認
5. R1 read/write
6. R4 read/write
7. R3
8. NFS startup
9. OSWRCH / OSRDCH
10. OSBYTE / OSWORD
11. OSCLI
12. OSFILE / OSGBPB
13. Error / BRK
14. 必要ならR3高速転送
15. 必要ならHost IRQ追加

## 26. 重要な訂正点

### I/O address

誤:

```text
F8h-FFh
```

正:

```text
B8h-BFh
```

### FPGA内Tube

現行版:

```text
Z80
 ↓
top_BeebDock.v
 ↓
external Tube ULA/FIFO
 ↓
PiTubeDirect
```

### Host IRQ

現行版:

```verilog
wire tube_irq_n = 1'b1;
```

よって未接続。

### CoPro reset

現行版:

```verilog
assign ext_copro_reset_n = bus_reset_n;
```

### `tube.v`

FPGA内の実装ではなく、標準Tube ULA/FIFO動作を理解するためのRTLリファレンスとして使用する。

## 27. 今後の実装

次の作業では、PiTubeDirect側の実際のGPIO/Dock接続まで含めて、

```text
Z80
 ↓
B8-BF
 ↓
top_BeebDock.v
 ↓
VGA shared pins
 ↓
Tang Nano 20K Dock
 ↓
Raspberry Pi
 ↓
PiTubeDirect
 ↓
Tube ULA/FIFO
```

を一本ずつ対応付ける。

その後、Z80 assemblerの`tube_z80.asm`を作成し、低レベルI/O → startup → OSWRCH/OSRDCH → OSBYTE/OSWORD → OSCLI → OSFILE/OSGBPB → Error → R3の順で実装する。

## 28. 参照

- MSXnano-Z80X `top_BeebDock.v`: https://github.com/MZ80K-USER-OLD/MSXnano-Z80X/blob/feature/beeb-dock/fpga/top_BeebDock.v
- BeebFpga Tube RTL: https://github.com/hoglet67/BeebFpga/blob/8423a54d13e802f0f4a032642c76c9e603175f84/src/common/Tube/tube.v
- PiTubeDirect: https://github.com/hoglet67/PiTubeDirect
- Acorn NFS 3.34: https://acornaeology.uk/acorn-nfs/3.34.html
