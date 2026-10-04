# BeebFPGA Tube インタフェース仕様書
## 内部 Co-Processor／外部 Co-Processor／MSX-Nano 移植検討

対象リポジトリ: `hoglet67/BeebFpga`  
対象コミット: `8423a54d13e802f0f4a032642c76c9e603175f84`  
対象ボード: Tang Nano 20K  
作成日: 2026-09-21

---

## 1. 目的

BeebFPGA の Tube インタフェース実装について、

1. FPGA 内部の Co-Processor に接続する場合
2. FPGA 外部の Co-Processor に接続する場合
3. MSX-Nano へ同様のインタフェースを移植する場合

を明確に区別し、データ転送方向、信号、FIFO の配置、クロック境界、MSX-Nano への実装方針を仕様として整理する。

最も重要な結論は次の通りである。

- **内部 Co-Processor 構成では、FPGA 内に Tube ULA を実装し、その内部に双方向の小容量 FIFO／ラッチを持つ。**
- **外部 Co-Processor 構成では、BeebFPGA の FPGA 側に追加の送受信 FIFO は置かず、Host CPU の Tube アクセスを `ext_tube_*` バスとして外部へ直接出す。**
- したがって外部 Co-Processor 側は、Tube ULA 相当のレジスタ／FIFO／ステータス制御を外部側で実装する必要がある。
- MSX-Nano で内部 Co-Processor を接続する場合は、BeebFPGA の `tube.v` 相当を FPGA 内に持つ構成が適切である。
- MSX-Nano で外部 Co-Processor を接続する場合は、BeebFPGA と同様に Host 側の Tube レジスタアクセスを外部バス化する方法が可能である。ただし外部装置が MSX CPU の I/O タイミング内に応答できない場合、単純な FIFO 追加だけでは解決せず、FPGA 内に Tube ULA を残して、その Parasite 側を別の非同期リンクに変換する構成の方が安全である。

---

## 2. BeebFPGA における Tube の基本構造

Tube は単なるシリアル通信や UART ではない。

Host CPU と Parasite CPU の間に、4組の通信レジスタを持つ双方向の通信 ULA として実装されている。

概念図:

```text
             Tube ULA
     ┌───────────────────────┐
Host │ R1  R2  R3  R4       │ Parasite
 CPU │  →   →   →   →       │ CPU
     │  ←   ←   ←   ←       │
     └───────────────────────┘
```

方向は独立している。

```text
Host → Parasite
Parasite → Host
```

BeebFPGA では `tube.v` がこの Tube ULA を実装する。

主要な内部モジュールは以下。

```text
tube.v
 ├─ hp_bytequad   Host → Parasite
 │   ├─ hp_byte   Register 1
 │   ├─ hp_byte   Register 2
 │   ├─ hp_reg3   Register 3
 │   └─ hp_byte   Register 4
 │
 └─ ph_bytequad   Parasite → Host
     ├─ ph_byte   Register 1
     ├─ ph_byte   Register 2
     ├─ ph_reg3   Register 3
     └─ ph_byte   Register 4
```

---

## 3. Tube ULA 内部 FIFO の深さ

### 3.1 Register 1

Host → Parasite:

```text
hp_byte
```

1 byte のバッファ。

Parasite → Host:

```text
ph_byte
```

1 byte のバッファ。

### 3.2 Register 2

Register 1 と同じく各方向 1 byte。

### 3.3 Register 3

高速ブロック転送用。

```text
hp_reg3
ph_reg3
```

はそれぞれ 2 byte の保存領域を持つ。

V フラグによって、

```text
V=0 : 1-byte mode
V=1 : 2-byte mode
```

として動作する。

2-byte mode では 2 byte が揃うまで Data Available を有効にしない。

### 3.4 Register 4

各方向 1 byte。

### 3.5 FIFO 容量まとめ

| Register | Host → Parasite | Parasite → Host |
|---|---:|---:|
| R1 | 1 byte | 1 byte |
| R2 | 1 byte | 1 byte |
| R3 | 1/2 byte | 1/2 byte |
| R4 | 1 byte | 1 byte |

したがって Tube ULA は「大容量 FIFO」を持つのではなく、通信レジスタごとに極めて浅い FIFO／メールボックスを持つ。

---

# Part A: FPGA 内部 Co-Processor

## 4. 内部 Co-Processor 構成

BeebFPGA の内部 6502 Co-Processor は、

```text
BBC Host CPU
     │
     │ Host bus
     ▼
┌───────────────┐
│   Tube ULA    │
│    tube.v     │
└───────┬───────┘
        │ Parasite bus
        ▼
┌───────────────┐
│ CoPro 6502    │
└───────────────┘
```

という構成である。

`CoPro6502.vhd` 内部で `tube` を直接インスタンス化している。

### 4.1 Host 側信号

内部 Tube ULA への Host 側信号:

```text
h_addr[2:0]
h_cs_b
h_data_in[7:0]
h_data_out[7:0]
h_phi2
h_rdnw
h_rst_b
h_irq_b
```

意味:

| Signal | Direction | Meaning |
|---|---|---|
| `h_addr[2:0]` | Host→Tube | Tube register address |
| `h_cs_b` | Host→Tube | Host chip select, active low |
| `h_data_in[7:0]` | Host→Tube | Host write data |
| `h_data_out[7:0]` | Tube→Host | Host read data |
| `h_phi2` | Host→Tube | Host-side clock |
| `h_rdnw` | Host→Tube | 1=Read, 0=Write |
| `h_rst_b` | Host→Tube | Reset |
| `h_irq_b` | Tube→Host | Host interrupt |

### 4.2 Parasite 側信号

```text
p_addr[2:0]
p_cs_b
p_data_in[7:0]
p_data_out[7:0]
p_rdnw
p_phi2
p_rst_b
p_nmi_b
p_irq_b
```

意味:

| Signal | Direction | Meaning |
|---|---|---|
| `p_addr[2:0]` | Parasite→Tube | Parasite register address |
| `p_cs_b` | Parasite→Tube | Parasite chip select |
| `p_data_in[7:0]` | Parasite→Tube | Parasite write data |
| `p_data_out[7:0]` | Tube→Parasite | Parasite read data |
| `p_rdnw` | Parasite→Tube | Read/write |
| `p_phi2` | Parasite→Tube | Parasite-side clock |
| `p_rst_b` | Tube→Parasite | Parasite reset |
| `p_nmi_b` | Tube→Parasite | Parasite NMI |
| `p_irq_b` | Tube→Parasite | Parasite IRQ |

---

## 5. 内部 Co-Processor: Host → Parasite 転送

データ経路:

```text
BBC CPU
  │
  │ cpu_do
  ▼
h_data_in
  │
  ▼
Tube ULA
  │
  │ hp_byte / hp_reg3
  ▼
Host→Parasite FIFO
  │
  ▼
p_data_out
  │
  ▼
Parasite CPU
```

BeebFPGA の内部 6502 接続では概念的に、

```text
cpu_do
   ↓
h_data_in
   ↓
tube.v
   ↓
hp_bytequad
   ↓
p_data_out
   ↓
6502 cpu_din
```

となる。

### FIFO 使用

**使用する。**

ただし大容量 FIFO ではない。

- R1: 1 byte
- R2: 1 byte
- R3: 1 or 2 byte
- R4: 1 byte

である。

この FIFO が Host と Parasite の速度差／クロック差を吸収する Tube ULA 本来の通信機構となる。

---

## 6. 内部 Co-Processor: Parasite → Host 転送

データ経路:

```text
Parasite CPU
  │
  │ p_data_in
  ▼
Tube ULA
  │
  │ ph_byte / ph_reg3
  ▼
Parasite→Host FIFO
  │
  ▼
h_data_out
  │
  ▼
BBC CPU
```

### FIFO 使用

**使用する。**

Host→Parasite と独立した FIFO が存在する。

このため Tube は本質的に双方向メールボックス／浅い FIFO の集合である。

---

## 7. 内部構成で FIFO が必要な理由

内部 Host CPU と内部 Parasite CPU は別タイミングで動作できる。

そのため、

```text
Host clock domain
       │
       ▼
Tube FIFO/status
       │
       ▼
Parasite clock domain
```

というクロックドメイン境界が存在する。

FIFO データ本体だけでなく、

```text
data available
full
empty
IRQ
NMI
```

などの状態管理が重要である。

BeebFPGA の `hp_flag_m` / `ph_flag_m` 系ロジックが、その状態遷移と両クロック側の同期を担当する。

---

# Part B: 外部 Co-Processor

## 8. 外部 Co-Processor 構成

外部接続の場合、BeebFPGA は内部 Tube ULA を通して外部 CPU に接続する構成にはなっていない。

概念的には、

```text
BBC CPU
  │
  │ Host Tube register access
  ▼
bbc_micro_core
  │
  │ ext_tube_*
  ▼
FPGA pins
  │
  ▼
External Co-Processor / PiTubeDirect
  │
  ▼
External Tube implementation
```

となる。

重要点:

**FPGA 側 `GenCoProExt` に追加の送受信 FIFO は存在しない。**

Host CPU のバス情報をレジスタ化して外部へ直接出している。

---

## 9. 外部 Tube 信号

`bbc_micro_core.vhd` の外部 Tube ポート:

```text
ext_tube_r_nw
ext_tube_nrst
ext_tube_ntube
ext_tube_phi2
ext_tube_a[6:0]
ext_tube_di[7:0]
ext_tube_do[7:0]
```

方向は FPGA を基準とすると次の通り。

| Signal | FPGA direction | Meaning |
|---|---|---|
| `ext_tube_r_nw` | Output | Host read/write |
| `ext_tube_nrst` | Output | Reset |
| `ext_tube_ntube` | Output | Tube select, active low |
| `ext_tube_phi2` | Output | Host Tube clock |
| `ext_tube_a[6:0]` | Output | Address |
| `ext_tube_di[7:0]` | Output | FPGA/BBC → external device data |
| `ext_tube_do[7:0]` | Input | external device → FPGA/BBC data |

---

## 10. Tang Nano 20K → 外部 Co-Processor

### 10.1 書き込み時

Host CPU が Tube レジスタへ write すると、

```text
cpu_a
cpu_do
cpu_r_nw
ext_tube_enable
```

が外部信号へ変換される。

BeebFPGA の `GenCoProExt` は以下の関係である。

```text
ext_tube_r_nw  <= cpu_r_nw
ext_tube_ntube <= not ext_tube_enable
ext_tube_a     <= cpu_a(6 downto 0)
ext_tube_di    <= cpu_do
```

従って Tang Nano 20K から外部 Co-Processor への主な送信信号は、

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_a[6:0]
ext_tube_di[7:0]
ext_tube_nrst
```

である。

データ本体は:

```text
ext_tube_di[7:0]
```

で送信される。

### 10.2 FIFO

**BeebFPGA の外部 Co-Processor パスには、FPGA 側の追加 FIFO はない。**

すなわち、

```text
cpu_do
   ↓
ext_tube_di
   ↓
FPGA pin
   ↓
External Tube device
```

である。

---

## 11. 外部 Co-Processor → Tang Nano 20K

外部装置から Host CPU に返すデータは、

```text
ext_tube_do[7:0]
```

を使用する。

概念:

```text
External Co-Processor / Tube implementation
          │
          │ ext_tube_do[7:0]
          ▼
     Tang Nano 20K
          │
          ▼
      CPU input MUX
          │
          ▼
       BBC CPU
```

### FIFO

**FPGA 側の外部 Tube パスには受信 FIFO はない。**

外部装置が Tube の状態とデータレジスタを保持し、Host read cycle に応じて `ext_tube_do` を返す。

つまり外部構成では FIFO の責任位置が変わる。

```text
内部 CoPro:
FPGA内 Tube ULA が FIFO を持つ

外部 CoPro:
外部装置側が Tube ULA 相当を持つ
FPGA は Host bus bridge
```

---

## 12. 内部／外部構成の重要な違い

| Item | Internal Co-Processor | External Co-Processor |
|---|---|---|
| Tube ULA | FPGA 内 | 外部側 |
| Host→Parasite FIFO | FPGA 内 | 外部側 |
| Parasite→Host FIFO | FPGA 内 | 外部側 |
| FPGA 外部バス | 不要 | `ext_tube_*` |
| Host CPU read data | `tube_do` | `ext_tube_do` |
| Clock-domain bridging | FPGA Tube ULA | 外部 Tube implementation |
| FPGA large FIFO | 不要 | 不要 |
| FPGA shallow Tube FIFO | 必要 | 不要 |

---

## 13. 外部接続に単純 FIFO を追加してはいけない理由

外部 Co-Processor が遅い場合、

```text
BBC/MSX CPU read
   ↓
FIFOへread要求を格納
   ↓
後で外部CPUが処理
```

という設計だけでは不十分である。

CPU の read cycle では、CPU がそのバスサイクル中に読み出しデータを要求する。

したがって外部装置がリアルタイムに応答できない場合、

```text
Host CPU
   ↓
FPGA Tube ULA
   ↓
非同期通信/FIFO
   ↓
External CPU
```

とする方が良い。

この場合 FPGA が Tube の Host 側を完全に終端し、外部 CPU には Parasite 側の意味論を提供する。

つまり、遅い外部 MCU への対応には「外部 Tube バスに FIFO を足す」のではなく、

**FPGA 内 Tube ULA + 外部通信用ブリッジ**

とするのが正しい設計となる。

---

# Part C: MSX-Nano への実装

## 14. MSX-Nano の Host 側

MSX-Nano では Tube を Z80 の I/O デバイスとして配置するのが自然である。

初期検討では `E0h-E7h` を割り当てる案としていたが、この領域は MIDI インタフェース等との競合があるため、本仕様では採用しない。

標準割り当ては、歴史的に実験・拡張用途で使われてきた領域を意識して **B8h-BFh** とする。`10h-17h` はユーザー開放領域を利用する代替候補として残す。

標準割り当て:

| MSX port | Tube function |
|---|---|
| B8h | Register 0 / status-control |
| B9h | Register 1 data |
| BAh | Register 2 status |
| BBh | Register 2 data |
| BCh | Register 3 status |
| BDh | Register 3 data |
| BEh | Register 4 status |
| BFh | Register 4 data |

Tube `h_addr[2:0]` とは、

```text
bus_addr[2:0]
```

を対応させる。

### I/O ベースアドレス方針

- **標準:** `B8h-BFh`
- **代替:** `10h-17h`
- **廃止:** `E0h-E7h`（MIDI インタフェース等との競合を避けるため）

HDLではベースアドレスを定数化し、固定配線しない。例えば Verilog では次のようにする。

```verilog
parameter [7:0] TUBE_IO_BASE = 8'hB8;

wire tube_req =
       (bus_addr[7:3] == TUBE_IO_BASE[7:3]) &&
       (bus_iorq_n == 1'b0) &&
       (bus_m1_n   == 1'b1);
```

これにより `TUBE_IO_BASE = 8'h10` とすれば `10h-17h` に変更できる。

---

## 15. MSX-Nano 内部 Co-Processor 案

推奨構成:

```text
MSX Z80/G80a
     │
     │ I/O B8-BF
     ▼
┌───────────────┐
│ MSX Tube ULA  │
│  tube.v系     │
└───────┬───────┘
        │
        │ Parasite bus
        ▼
┌───────────────┐
│ Z80 / T80 /   │
│ 24-bit CPU    │
└───────────────┘
```

この場合、

**Tube ULA 内部の FIFO は必要。**

理由:

- Host と Parasite の独立動作
- クロック差
- Register 3 の 1/2-byte 動作
- IRQ / NMI
- full / data available の管理

を Tube ULA が担うためである。

---

## 16. MSX-Nano Host バス接続

既存 MSX-Nano 信号を利用する。

```text
bus_addr[15:0]
cpu_din[7:0]
cpu_dout[7:0]
bus_m1_n
bus_mreq_n
bus_iorq_n
bus_rd_n
bus_wr_n
bus_reset_n
```

Tube select 例:

```verilog
wire tube_req;

assign tube_req =
       (bus_addr[7:3] == 5'b10111) &&
       (bus_iorq_n == 1'b0) &&
       (bus_m1_n   == 1'b1);
```

これは B8h-BFh をデコードする。

---

## 17. MSX-Nano 内部 Tube の推奨インタフェース

BeebFPGA オリジナルは 6502 の PHI2 を直接使用する。

MSX-Nano では Clock Enable ベースに整理する方がよい。

推奨ラッパ:

```verilog
module msx_tube (
    input  wire       clk,
    input  wire       reset_n,

    // MSX host
    input  wire       host_ce,
    input  wire [2:0] host_addr,
    input  wire       host_rd,
    input  wire       host_wr,
    input  wire [7:0] host_din,
    output wire [7:0] host_dout,

    // Parasite CPU
    input  wire       parasite_ce,
    input  wire [2:0] parasite_addr,
    input  wire       parasite_rd,
    input  wire       parasite_wr,
    input  wire [7:0] parasite_din,
    output wire [7:0] parasite_dout,

    output wire       host_irq_n,
    output wire       parasite_irq_n,
    output wire       parasite_nmi_n,
    output wire       parasite_reset_n
);
```

全ロジックは Tang Nano 20K の master clock で動かし、

```text
host_ce
parasite_ce
```

で各 CPU の有効サイクルを識別する。

**CE をクロック端子として直接使わない。**

---

## 18. MSX-Nano → 内部 Co-Processor

データ経路:

```text
MSX Z80
  │ cpu_dout
  │
  ▼
MSX Tube Host port
  │
  ▼
hp_byte / hp_reg3
  │
  ▼
Host→Parasite FIFO
  │
  ▼
Parasite CPU
```

主な信号例:

```text
host_addr[2:0]
host_wr
host_din[7:0]
host_ce
```

Parasite 側では:

```text
parasite_addr[2:0]
parasite_rd
parasite_dout[7:0]
```

で受信する。

---

## 19. 内部 Co-Processor → MSX-Nano

データ経路:

```text
Parasite CPU
  │
  ▼
parasite_din[7:0]
  │
  ▼
ph_byte / ph_reg3
  │
  ▼
Parasite→Host FIFO
  │
  ▼
host_dout[7:0]
  │
  ▼
cpu_din
  │
  ▼
MSX Z80
```

MSX-Nano の `cpu_din` MUX に Tube を追加する。

例:

```verilog
cpu_din =
    tube_rd ? tube_dout :
    ...;
```

---

# Part D: MSX-Nano + 外部 Co-Processor

## 20. BeebFPGA と同じ direct external Tube 方式

MSX-Nano にも BeebFPGA と同じ方式を追加できる。

概念:

```text
MSX Z80
   │
   │ B8-BF I/O access
   ▼
MSX host bus decoder
   │
   ▼
ext_tube_* equivalent
   │
   ▼
Tang Nano 20K GPIO
   │
   ▼
External Tube device
```

MSX-Nano 用には例えば以下の信号を定義できる。

```text
msx_ext_tube_clk
msx_ext_tube_rd_n
msx_ext_tube_wr_n
msx_ext_tube_cs_n
msx_ext_tube_reset_n
msx_ext_tube_a[2:0]
msx_ext_tube_di[7:0]
msx_ext_tube_do[7:0]
```

BeebFPGA 互換ピン名をそのまま使うなら、

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_nrst
ext_tube_a
ext_tube_di
ext_tube_do
```

としてもよい。

---

## 21. MSX-Nano → 外部 Co-Processor

書き込み時:

```text
bus_addr[2:0]
cpu_dout[7:0]
bus_wr_n
tube_req
```

から、

```text
ext_tube_a
ext_tube_di
ext_tube_r_nw
ext_tube_ntube
```

を生成する。

例:

```text
ext_tube_a      ← bus_addr
ext_tube_di     ← cpu_dout
ext_tube_r_nw   ← not write
ext_tube_ntube  ← not tube_req
```

この direct external 方式では、

**FPGA 側に Host→External FIFO を追加しない。**

---

## 22. 外部 Co-Processor → MSX-Nano

外部装置からは、

```text
ext_tube_do[7:0]
```

を FPGA に入力する。

MSX Z80 が B8-BF を read しているとき、

```text
cpu_din ← ext_tube_do
```

とする。

この場合も、

**FPGA 側に External→Host FIFO は追加しない。**

外部装置自身が Tube ULA のデータ／status を保持していることが前提である。

---

## 23. MSX-Nano 外部 Co-Processor の推奨2方式

### 方式 A: BeebFPGA と同じ direct Tube bus

```text
MSX Z80
   │
   ▼
FPGA bus bridge
   │
   ▼
External Tube ULA / fast MCU / FPGA
```

適する条件:

- 外部装置がバスタイミングにリアルタイム応答可能
- PIO/FPGA/CPLD 等で Tube バスを確実に処理可能
- PiTubeDirect 型の実装を行う場合

FPGA 内の追加 FIFO:

```text
不要
```

### 方式 B: FPGA 内 Tube ULA + 外部 Parasite bridge

```text
MSX Z80
   │
   ▼
FPGA Tube ULA
   │
   │ Parasite-side transactions
   ▼
Async FIFO / mailbox / SPI / parallel bus
   │
   ▼
External Co-Processor
```

適する条件:

- 外部 CPU が Tube Host bus タイミングに直接追従できない
- SPI や UART、USB、低速 GPIO を利用したい
- RP2040/RP2350/MCU 等でソフトウェア処理したい
- 外部 CPU の処理停止や割り込み遅延を許容したい

この場合は FPGA 内に Tube ULA の浅い FIFO があり、その外側の transport 用に必要ならさらに FIFO を追加できる。

---

## 24. FIFO についての最終整理

### 内部 Co-Processor

```text
MSX/BBC Host
   ↓
Tube ULA
   ↓
Internal Co-Processor
```

FPGA 内 Tube FIFO:

```text
必要
```

### 外部 Direct Tube

```text
MSX/BBC Host
   ↓
FPGA bus bridge
   ↓
External Tube implementation
```

FPGA 内 Tube FIFO:

```text
不要
```

External 側 Tube FIFO:

```text
必要
```

### 外部 Buffered Bridge

```text
MSX/BBC Host
   ↓
FPGA Tube ULA
   ↓
transport FIFO
   ↓
External Co-Processor
```

FPGA Tube FIFO:

```text
必要
```

追加 transport FIFO:

```text
通信方式次第で必要
```

---

## 25. Tang Nano 20K / MSX-Nano に対する推奨

MSX-Nano へ最初に実装する場合は、次の順序が最も安全である。

1. `tube.v` 系を MSX Host bus に接続
2. B8h-BFh に配置（10h-17h は代替設定として選択可能にする）
3. 内部 Parasite Z80 を接続
4. Host→Parasite / Parasite→Host の R1 転送を確認
5. R2/R4 を確認
6. Register 3 の 1-byte mode
7. Register 3 の 2-byte mode
8. Host IRQ
9. Parasite IRQ/NMI
10. Parasite CPU を高速化
11. 24-bit 拡張 CPU へ置換
12. 最後に外部 Co-Processor bridge を追加

理由は、内部 Tube ULA を先に完成させることで Tube protocol 自体と外部物理 I/O 問題を分離できるからである。

---

## 26. 推奨ファイル構成

MSX-Nano に追加する場合:

```text
fpga/
 ├─ top.v
 └─ tube/
     ├─ msx_tube.v
     ├─ tube_core.v
     ├─ hp_bytequad.v
     ├─ hp_byte.v
     ├─ hp_reg3.v
     ├─ hp_flag_m.v
     ├─ ph_bytequad.v
     ├─ ph_byte.v
     ├─ ph_reg3.v
     └─ ph_flag_m.v
```

外部 direct Tube を追加するなら:

```text
tube/
 └─ msx_ext_tube_bridge.v
```

外部 buffered bridge を追加するなら:

```text
tube/
 ├─ msx_tube.v
 ├─ parasite_bridge.v
 └─ async_fifo.v
```

---

## 27. 実装時の重要注意事項

### 27.1 Clock Enable をクロックとして使わない

悪い例:

```verilog
always @(posedge clk_enable_3m6_54)
```

推奨:

```verilog
always @(posedge clk_54m) begin
    if (host_ce) begin
        ...
    end
end
```

### 27.2 Host/Parasite CDC を壊さない

Tube の full/data-available フラグは通信の本質である。

単純にデータレジスタだけコピーすると、

- 上書き
- 二重読み出し
- IRQ 消失
- NMI 異常
- 2-byte Register 3 の破綻

が起きる。

### 27.3 direct external bus は同期 read が必要

`ext_tube_do` を Host CPU の read cycle 中に有効にする必要がある。

外部装置が間に合わない場合は、WAIT のような機構を追加するか、FPGA 内 Tube ULA 方式に切り替える。

### 27.4 MSX では WAIT を利用する余地がある

BBC 側 direct Tube と異なり、MSX/Z80 には WAIT 機構がある。

そのため将来的には、

```text
external Tube read not ready
        ↓
WAIT_n assert
        ↓
ext_tube_do ready
        ↓
WAIT_n release
```

という拡張も可能。

ただしこれは Acorn Tube 本来のインタフェースではなく、MSX-Nano 独自拡張になる。

---


---

# Part E: Tang Nano 20K Dock + PiTubeDirect + Raspberry Pi

## 29. PiTubeDirect を外部 Co-Processor として用いる構成

BeebFPGA の Tang Nano 20K には、PiTubeDirect を接続することを前提にした専用ビルドが存在する。

対象コミット `8423a54d13e802f0f4a032642c76c9e603175f84` には、少なくとも以下の Tang Nano 20K 用構成がある。

```text
tang20k_debugger_pitube
tang20k_nodebugger_pitube
```

したがって Tang Nano 20K + Dock ボード + Raspberry Pi + PiTubeDirect は、BeebFPGA が想定している正式な外部 Tube 構成の一つと考えてよい。

概念構成は次のようになる。

```text
┌──────────────────────────────┐
│ Tang Nano 20K                │
│                              │
│ BBC Micro FPGA core          │
│        │                     │
│        │ ext_tube_*          │
│        ▼                     │
│ FPGA GPIO                    │
└────────┬─────────────────────┘
         │
         │ Tang Nano 20K Dock
         │ / physical GPIO
         ▼
┌──────────────────────────────┐
│ Raspberry Pi                 │
│                              │
│ PiTubeDirect                 │
│   ├─ Tube ULA emulation      │
│   └─ Co-Processor emulator   │
│        ├─ 65C02              │
│        ├─ Z80                │
│        ├─ 80x86              │
│        ├─ MC6809             │
│        ├─ PDP-11             │
│        ├─ ARM2               │
│        ├─ NS32016            │
│        ├─ 65C816             │
│        └─ その他             │
└──────────────────────────────┘
```

重要なのは、Raspberry Pi が単に「外部CPU」なのではなく、PiTubeDirect ソフトウェア上で、

1. FPGA が出す外部 Tube バスを処理する
2. Tube ULA の Host/Parasite 間レジスタ状態を管理する
3. 選択された Co-Processor CPU をエミュレートする

という複数の役割を担う点である。

---

## 30. Tang Nano 20K 側の役割

Tang Nano 20K 側では `IncludeCoProExt` が有効な構成で、BBC CPU の Tube アクセスを外部信号へ変換する。

外部 Tube 信号は、

```text
ext_tube_r_nw
ext_tube_nrst
ext_tube_ntube
ext_tube_phi2
ext_tube_a[6:0]
ext_tube_di[7:0]
ext_tube_do[7:0]
```

である。

Tang Nano 20K 側は基本的に、

```text
BBC CPU bus
     ↓
ext_tube_* bus bridge
     ↓
Dock / GPIO
```

の役割を担う。

この経路では FPGA 内に PiTubeDirect 用の大容量 TX/RX FIFO は置かれない。

---

## 31. Tang Nano 20K → Raspberry Pi

BBC Host CPU が Tube register へ書き込むと、Tang Nano 20K から Raspberry Pi 側へ次の情報が提示される。

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_a[6:0]
ext_tube_di[7:0]
ext_tube_nrst
```

主なデータ信号は、

```text
ext_tube_di[7:0]
```

である。

概念:

```text
BBC CPU cpu_do
      │
      ▼
ext_tube_di[7:0]
      │
      ▼
Tang Nano Dock GPIO
      │
      ▼
Raspberry Pi GPIO
      │
      ▼
PiTubeDirect
      │
      ▼
Tube register state
      │
      ▼
selected CPU emulator
```

ここで Tang Nano 20K はデータを FIFO に蓄積して Raspberry Pi に後送するのではない。

**CPU バスサイクルそのものを PiTubeDirect に見せる方式**である。

---

## 32. Raspberry Pi → Tang Nano 20K

BBC Host CPU が Tube register を read すると、PiTubeDirect は対応する Tube register/status の値を Raspberry Pi GPIO に提示する。

FPGA には、

```text
ext_tube_do[7:0]
```

として入力される。

概念:

```text
selected CPU emulator
      │
      ▼
PiTubeDirect Tube state
      │
      ▼
Raspberry Pi GPIO
      │
      ▼
ext_tube_do[7:0]
      │
      ▼
Tang Nano 20K
      │
      ▼
BBC CPU input mux
```

したがって direct PiTubeDirect 構成でも、Tang Nano 20K 側の受信 FIFOは不要である。

---

## 33. PiTubeDirect 側で Tube FIFO はどこにあるか

PiTubeDirect 構成では、BeebFPGA FPGA 内部の `tube.v` に存在した Host↔Parasite の通信状態を、PiTubeDirect 側がソフトウェアでエミュレートする。

つまり論理的には、

```text
Tang Nano 20K                       Raspberry Pi
┌──────────────┐                   ┌──────────────────┐
│ BBC CPU      │                   │ PiTubeDirect     │
│              │ ext_tube_*        │                  │
│ bus bridge   ├──────────────────►│ Tube ULA state   │
│              │◄──────────────────┤ / registers      │
└──────────────┘                   │ / status flags   │
                                   │                  │
                                   │ selected CPU     │
                                   │ emulator         │
                                   └──────────────────┘
```

となる。

このため、

```text
FPGA Tube FIFO
```

を二重に配置する必要はない。

---

## 34. PiTubeDirect が提供する主な Co-Processor

PiTubeDirect の現在のソースでは、`copro-defs.c` に Co-Processor 選択テーブルが定義されている。

代表的なものは以下。

| No. | PiTubeDirect 表示名 | CPU / mode |
|---:|---|---|
| 0 | `65C02 (fast)` | 65C02 |
| 1 | `65C02` | 65C02 |
| 2 | `65C102 (fast)` | 65C102 |
| 3 | `65C102` | 65C102 |
| 4-7 | `Z80 (...)` | Z80 |
| 8 | `80286` | 80x86 系エミュレータ |
| 9 | `MC6809` | Motorola 6809 |
| 11 | `PDP-11` | DEC PDP-11 |
| 12 | `ARM2` | ARM2 |
| 13 | `32016` | NS32016 |
| 15 | `ARM Native` | Raspberry Pi ARM native mode |
| 16 | `LIB65C02 64K` | lib6502 based 65C02 |
| 17 | `LIB65C02 256K Turbo` | 65C02 Turbo |
| 18 | `65C816 (Dossy)` | 65C816 |
| 19 | `65C816 (ReCo)` | 65C816 |
| 20 | `OPC5LS` | OPC5LS |
| 21 | `OPC6` | OPC6 |
| 22 | `OPC7` | OPC7 |
| 24 | `65C02 (JIT)` | JIT 65C02 |
| 28 | `Ferranti F100-L` | F100-L |

さらに PiTubeDirect のビルド定義には、

```text
80186
ARM2
NS32016
Z80
6809
OPC5LS
OPC6
OPC7
F100
PDP-11
65816
ARM Native
```

などの CPU 実装が組み込まれている。

注意点として、ソース内部の実装名と画面上の表示名が完全に同じとは限らない。例えば `copro-80186` 実装を利用する選択肢が表示上 `80286` とされているため、CPU互換範囲を説明するときは実装コード側も確認する必要がある。

---

## 35. CPU を変更しても Tang Nano 20K 側 Tube インタフェースは変わらない

PiTubeDirect の重要な特徴は、Raspberry Pi 上でエミュレートする CPU を変更しても、Tang Nano 20K との物理 Tube インタフェースは共通である点である。

たとえば、

```text
65C02
Z80
MC6809
PDP-11
ARM2
NS32016
65C816
```

のどれを選択しても、Tang Nano 20K から見える外部インタフェースは、

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_nrst
ext_tube_a
ext_tube_di
ext_tube_do
```

のままである。

したがって、

```text
BBC FPGA core
      │
      ▼
External Tube bus
      │
      ▼
PiTubeDirect
      │
      ├─ 65C02 emulator
      ├─ Z80 emulator
      ├─ ARM2 emulator
      ├─ PDP-11 emulator
      └─ ...
```

という抽象化が成立する。

FPGA は選択 CPU の種類を知る必要がない。

---

## 36. 内部 Co-Processor と PiTubeDirect の比較

| 項目 | FPGA内部 CoPro | Raspberry Pi / PiTubeDirect |
|---|---|---|
| CPU実装場所 | Tang Nano 20K FPGA | Raspberry Pi |
| Tube ULA | FPGA内 `tube.v` | PiTubeDirect側 |
| Host→Parasite FIFO | FPGA内 | PiTubeDirect側で論理的に保持 |
| Parasite→Host FIFO | FPGA内 | PiTubeDirect側で論理的に保持 |
| FPGA→CoPro data | `h_data_in`→Tube内部 | `ext_tube_di` |
| CoPro→FPGA data | Tube内部→`h_data_out` | `ext_tube_do` |
| CPU変更 | FPGA再合成が基本 | PiTubeDirect設定変更 |
| CPU種類 | 実装したコアのみ | 複数エミュレータを選択可能 |
| FPGA LUT消費 | CPU + Tube分増加 | 外部bus bridgeのみ |
| 外部GPIO | 不要 | 必要 |
| Raspberry Pi | 不要 | 必要 |

---

## 37. PiTubeDirect を使う利点

Tang Nano 20K の FPGA リソースを CPU エミュレーションに使用しなくてよい。

特に、

```text
ARM2
NS32016
PDP-11
65C816
80x86
```

のような複数 CPU をすべて FPGA に実装する必要がなく、

```text
Tang Nano 20K = BBC本体
Raspberry Pi = 可変 Co-Processor
```

と役割を分離できる。

また CPU を切り替えるたびに Tang Nano 20K の bitstream を再生成する必要がない。

---

## 38. MSX-Nano + PiTubeDirect 案

同じ仕組みは MSX-Nano にも応用可能である。

概念:

```text
Tang Nano 20K
┌──────────────────────────────┐
│ MSX-Nano                     │
│                              │
│ Z80 / G80a                   │
│      │                       │
│      │ B8h-BFh               │
│      ▼                       │
│ MSX Tube host bridge         │
│      │                       │
│      │ ext_tube_*            │
└──────┼───────────────────────┘
       │ Dock GPIO
       ▼
┌──────────────────────────────┐
│ Raspberry Pi                 │
│ PiTubeDirect                 │
│                              │
│ selectable Co-Processor      │
│  65C02 / Z80 / ARM2 / ...   │
└──────────────────────────────┘
```

この構成なら MSX-Nano 側に複数の CPU コアを実装する必要がない。

---

## 39. MSX-Nano で PiTubeDirect を利用する場合の変更点

ただし PiTubeDirect は本来 BBC Micro Host 側 Tube protocol を前提としている。

そのため MSX-Nano では、Z80 I/O バスをそのまま Raspberry Pi に出すのではなく、

```text
MSX I/O B8-BF
      │
      ▼
MSX→Tube Host bus adapter
      │
      ▼
PiTubeDirect-compatible ext_tube_*
```

という変換層を FPGA に用意する。

推奨信号:

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_nrst
ext_tube_a[6:0]
ext_tube_di[7:0]
ext_tube_do[7:0]
```

物理信号名を BeebFPGA と同じにしておけば、Dock 側配線や Raspberry Pi 側 PiTubeDirect インタフェースを再利用しやすい。

---

## 40. MSX-Nano の B8-BF と PiTubeDirect の対応

MSX 側:

```text
B8 Register 0/status-control
B9 Register 1 data
BA Register 2 status
BB Register 2 data
BC Register 3 status
BD Register 3 data
BE Register 4 status
BF Register 4 data
```

これを Host Tube register address として、

```text
ext_tube_a[2:0] = bus_addr[2:0]
```

へ変換する。

BeebFPGA の `ext_tube_a` は 7 bit なので、上位アドレスについては PiTubeDirect の検出／拡張用途との互換性を考慮し、MSX版でも 7 bit の信号として保持するのが望ましい。

---

## 41. MSX-Nano + PiTubeDirect で FIFO は必要か

BeebFPGA と完全に同じ direct方式を採るなら、

```text
MSX Z80
    ↓
host bridge
    ↓
ext_tube_*
    ↓
PiTubeDirect
```

となるので、Tang Nano 20K FPGA側に追加 FIFO は基本的に不要である。

PiTubeDirect 側が Tube ULA の通信状態を管理する。

従って、

```text
MSX-Nano FPGA
  Host Tube bridge only

Raspberry Pi
  Tube ULA emulation
  +
  CPU emulation
```

という役割分担になる。

---

## 42. MSX-Nano での推奨実装モード

MSX-Nano には将来的に以下の3モードを持たせるとよい。

```text
MODE 0 : Tube disabled

MODE 1 : Internal Co-Processor
         MSX → FPGA Tube ULA → FPGA CPU

MODE 2 : External PiTubeDirect
         MSX → ext_tube_* → Raspberry Pi

MODE 3 : Buffered External
         MSX → FPGA Tube ULA
             → async transport
             → external CPU
```

選択レジスタ例:

```text
00 = Disabled
01 = Internal
10 = PiTubeDirect
11 = Buffered external
```

これにより、同じ MSX software API から複数の Co-Processor 実装を利用できる。

---

## 43. MSX-Nano + PiTubeDirect の大きな利点

この方式を採用すると、

```text
MSX本体互換CPU
      │
      ▼
Tube API
      │
      ▼
Raspberry Pi
      │
      ├─ Z80
      ├─ 65C02
      ├─ 65C816
      ├─ ARM2
      ├─ NS32016
      ├─ PDP-11
      └─ その他
```

という構成を実現できる。

特に、これまで検討している MSX-Nano 上の拡張 CPU 実験において、

- FPGA 内に新CPUを実装する方式
- Raspberry Pi で CPU をソフトウェアエミュレーションする方式

を同じ Tube Host API で比較できる。

これは CPU アーキテクチャの実験環境として非常に有用である。

---

## 44. PiTubeDirect 対応を含めた最終推奨構成

```text
                         ┌────────────────────────┐
                         │ MSX-Nano / Tang Nano20K│
                         │                        │
                         │      MSX Z80           │
                         │          │             │
                         │       B8-BF            │
                         │          │             │
                         │     Tube Host IF       │
                         └──────────┬─────────────┘
                                    │
                   ┌────────────────┴───────────────┐
                   │                                │
                   ▼                                ▼
          Internal Tube ULA                External Tube Bridge
                   │                                │
                   ▼                                │ ext_tube_*
       FPGA Co-Processor                            ▼
       Z80 / 24-bit CPU                    Raspberry Pi
                                            PiTubeDirect
                                                 │
                            ┌────────────────────┼───────────────┐
                            ▼                    ▼               ▼
                          Z80                  ARM2            65C816
                            ▼                    ▼               ▼
                         PDP-11               NS32016          etc.
```

この構成では、

**内部CPUとPiTubeDirect外部CPUを同一のMSX Tubeソフトウェアインタフェースから切り替えられる。**

Tang Nano 20K の FPGAリソースを節約したい場合は PiTubeDirect、
FPGAだけで完結させたい場合や独自24-bit CPUを実験したい場合は internal Tube、
という使い分けができる。


## 45. 結論

BeebFPGA の Tube 実装では、内部 Co-Processor と外部 Co-Processor でアーキテクチャが明確に異なる。

### 内部 Co-Processor

```text
Host CPU
   ↓
FPGA Tube ULA
   ↓
shallow FIFO
   ↓
Parasite CPU
```

Tube FIFO は FPGA 内に存在する。

### 外部 Co-Processor

```text
Host CPU
   ↓
ext_tube_* bus
   ↓
External Tube implementation
```

FPGA 側に追加 FIFO は置かない。

Tang Nano 20K から外部へのデータは、

```text
ext_tube_di[7:0]
```

外部から Tang Nano 20K へのデータは、

```text
ext_tube_do[7:0]
```

を使う。

制御信号は、

```text
ext_tube_phi2
ext_tube_r_nw
ext_tube_ntube
ext_tube_nrst
ext_tube_a[6:0]
```

である。

MSX-Nano では、まず FPGA 内 Tube ULA を B8h-BFh に接続して内部 Parasite CPU で検証する方式を推奨する。10h-17h はビルド時または設定レジスタで選べる代替ベースアドレス候補とする。

その後、

- direct external Tube bus
- FPGA Tube ULA + buffered external bridge

のどちらかを用途に応じて追加するのが良い。

特に外部 CPU が高速なリアルタイム GPIO 応答を保証できない場合は、direct external Tube より、

```text
MSX Z80
   ↓
FPGA Tube ULA
   ↓
Async FIFO / mailbox
   ↓
External Co-Processor
```

方式の方が堅牢である。


---

## 46. PiTubeDirect を含めた補足結論

Tang Nano 20K Dock ボード経由で Raspberry Pi / PiTubeDirect を利用するケースは、
BeebFPGA の外部 Co-Processor 実装を理解する上で非常に重要である。

この場合 Raspberry Pi は単なる計算用CPUではなく、

```text
External Tube interface
      +
Tube ULA state machine
      +
selected Co-Processor emulator
```

をまとめて担当する。

そのため Tang Nano 20K FPGA側では、
内部Co-Processor用の `tube.v` FIFO と PiTubeDirect用の外部FIFOを二重に持たせる必要はない。

PiTubeDirectモードでは、

```text
Tang Nano 20K:
    BBC/MSX Host bus → ext_tube_* bridge

Raspberry Pi:
    ext_tube_* → Tube ULA emulation → selected CPU emulator
```

という責任分担にするのが基準となる。


---

# 方式B追加仕様：外部Co-Processor → MSX Host IRQ

## 47. 採用方針

本仕様では、外部Co-ProcessorからMSX-Nano内のZ80/G80aへ割り込みを通知する方式として、**方式B（FPGA内部でTube状態を監視し、Host IRQを生成してMSX CPUのINT_nへ合成する方式）**を採用する。

PiTubeDirectの標準`ext_tube_*`物理インタフェースには、外部Co-ProcessorからHost CPUへ直接入る専用IRQ入力線は存在しない。そのため、Raspberry Pi / PiTubeDirect側が更新するTubeレジスタ状態またはデータ到着状態をTang Nano 20K FPGA側で検出し、`tube_host_irq_n`を内部生成する。

概念構成：

```text
Raspberry Pi / PiTubeDirect
          |
          | ext_tube_* bus
          v
Tang Nano 20K
  External Tube Bridge
          |
          +--> Tube status/data transition detect
          |
          +--> tube_host_irq_n
                    |
                    v
              MSX interrupt merge
                    |
                    v
               CPU INT_n
```

## 48. BeebFPGAにおける外部Tubeインタフェースの根拠

BeebFPGAの`bbc_micro_core.vhd`では、PiTubeDirect接続用に次の外部Tube信号が定義されている。

```vhdl
ext_tube_r_nw  : out std_logic;
ext_tube_nrst  : out std_logic;
ext_tube_ntube : out std_logic;
ext_tube_phi2  : out std_logic;
ext_tube_a     : out std_logic_vector(6 downto 0);
ext_tube_di    : out std_logic_vector(7 downto 0);
ext_tube_do    : in  std_logic_vector(7 downto 0) := x"FE";
```

この一覧には、PiTubeDirectからHost CPUへ直接入力される`IRQ`または`NMI`信号は含まれていない。

一方で、同じコアの外部1MHzバスには、

```vhdl
ext_1mhz_irq_n : in std_logic := '1';
ext_1mhz_nmi_n : in std_logic := '1';
```

が定義されており、FPGA外部デバイスからHost CPU側へ割り込み入力を取り込む構造自体はBeebFPGAでも採用されている。

したがってMSX-Nanoでは、PiTubeDirect専用物理IRQ線を追加するのではなく、Tube状態からFPGA内部でHost IRQを生成する方式を採用する。

## 49. Host IRQ生成条件

初期実装では、次のイベントをHost IRQ要求の候補とする。

1. Parasite→Host方向の受信データが新規に到着した
2. Tube R1～R4のうちHostから読み取り可能なデータ状態が「空→有効」に遷移した
3. ソフトウェアでIRQ enableが設定されている
4. 既に処理済みのイベントではない

推奨内部信号：

```verilog
wire tube_rx_event;
wire tube_irq_enable;
reg  tube_irq_pending;
wire tube_host_irq_n;

assign tube_host_irq_n = ~tube_irq_pending;
```

概念的には次のように処理する。

```verilog
always @(posedge clk_54m) begin
    if (!reset_n) begin
        tube_irq_pending <= 1'b0;
    end else begin
        if (tube_irq_enable && tube_rx_event)
            tube_irq_pending <= 1'b1;

        if (tube_irq_ack)
            tube_irq_pending <= 1'b0;
    end
end
```

`tube_irq_ack`は、対応するTubeデータレジスタ読出し、専用ACKビット書込み、または両者の組合せで生成する。

## 50. MSX CPUのINT_nへの合成

MSX側ではTube IRQを既存の割り込み源へ追加する。

```verilog
wire cpu_int_n;

assign cpu_int_n =
       vdp_int_n &
       other_int_n &
       tube_host_irq_n;
```

MSX/Z80の割り込み入力はactive-lowとし、既存のVDP等の割り込みを壊さないwired-AND相当の論理で合成する。

実際のMSX-Nanoソースでは、既存のINT合成箇所を特定したうえでそこへ`tube_host_irq_n`を追加する。

## 51. IRQ enable / status拡張

既存Tubeレジスタ互換性を壊さないため、MSX拡張機能としてHost IRQ制御を追加する場合は、未使用ビットまたは拡張制御ポートを用いる。

推奨案：

```text
B8h  R1 Status / Control
B9h  R1 Data
BAh  R2 Status
BBh  R2 Data
BCh  R3 Status
BDh  R3 Data
BEh  R4 Status
BFh  R4 Data
```

標準I/O領域はB8h～BFhとする。

追加のIRQ enableは、既存Tube互換ビットとの衝突を避けるため、実装前に`tube.v`のR1 Control semanticsを確認して割り当てる。互換性を維持できない場合は、別のMSX拡張レジスタに分離する。

## 52. ジョイスティックとの併存

Tang Nano 20K Dock Boardのジョイスティック回路は、2個の74LV165Aを用いたシリアル入力方式であり、FPGA側では3本の信号だけを使用する。

```text
Pin71  JS_Clk
Pin72  JS_Load_n
Pin76  JS_Data
```

BeebFPGAの`bbc_micro_tang20k_pitube.cst`でも、PiTube構成時にこれらのピンはジョイスティック信号としてそのまま割り当てられている。

```text
IO_LOC "js_clk"    71;
IO_LOC "js_load_n" 72;
IO_LOC "js_data"   76;
```

したがって、本仕様のPiTubeDirect機能とDock Boardジョイスティックは**物理ピン上で共存させる**。

重要点：

- `Pin71/72/76`をHost IRQ専用線へ転用しない
- Host IRQは外部ピンではなくFPGA内部生成とする
- これによりPiTubeDirect、ジョイスティック、Host IRQを同時に利用できる
- ジョイスティック読出しロジックはTubeのI/OポートB8h～BFhとは独立させる

## 53. ジョイスティック回路との関係

Dock Board回路では2個のAtari互換DB9入力が74LV165Aへ接続され、方向・Fire信号がパラレル入力された後、`JS_Data`としてシリアル出力される。

```text
Joystick ports
      |
      v
  74LV165A x2
      |
      +-- JS_Load_n
      +-- JS_Clk
      +-- JS_Data
             |
             v
      Tang Nano 20K
```

したがってTube機能追加時もこの3線を保持することを必須要件とする。

## 54. I/Oポート衝突方針

当初候補だったE0h～E7hはMIDIインタフェースとの衝突を避けるため採用しない。

標準Tube Host I/Oは、

```text
B8h～BFh
```

を第一候補とする。

代替候補として、

```text
10h～17h
```

を保持する。

HDLでは固定値直書きではなく、例えば次のようにベースアドレスを定数化する。

```verilog
localparam [7:0] TUBE_IO_BASE = 8'hB8;
```

これにより後から10h～17hへ変更可能とする。

## 55. 方式BとPiTubeDirectの役割分担

```text
                 +---------------------------+
                 | Raspberry Pi              |
                 | PiTubeDirect              |
                 | Tube ULA emulation        |
                 | CPU emulator              |
                 +-------------+-------------+
                               |
                         ext_tube_*
                               |
                 +-------------v-------------+
                 | Tang Nano 20K FPGA        |
                 | External Tube Bridge      |
                 | status/data monitor       |
                 | tube_rx_event             |
                 | tube_irq_pending          |
                 | tube_host_irq_n           |
                 +-------------+-------------+
                               |
                         MSX INT merge
                               |
                 +-------------v-------------+
                 | MSX Host CPU              |
                 | G80a / Z80                |
                 +---------------------------+

                 Joystick path (parallel)
                 Pin71 / Pin72 / Pin76
                               |
                 +-------------v-------------+
                 | Dock 74LV165A x2          |
                 | Atari-compatible DB9 x2   |
                 +---------------------------+
```

この構成ではPiTubeDirect用に新たなHost IRQ物理ピンを必要としない。

## 56. 実装時の注意

外部PiTubeDirect側の状態をどの信号・タイミングで「新規受信イベント」と判定するかは、単に`ext_tube_do`の値変化だけで決めてはならない。

`ext_tube_do`はHost read cycle時のデータ入力なので、正確なIRQ発生条件はTubeレジスタのstatus semanticsとHostアクセスシーケンスに基づいて設計する必要がある。

実装前に以下を確認する。

- PiTubeDirectが返すR1～R4 status bit
- Host-visible data-available bit
- Host readによるstatus clear条件
- R3の1-byte / 2-byte mode
- reset時のstatus
- interrupt enable semantics

そのうえで`tube_rx_event`を「データ有効状態の立上り」または「指定status条件成立」として生成する。

## 57. 互換性方針

方式BはMSX-Nano固有拡張とし、PiTubeDirect側の既存ソフトウェアには変更を要求しないことを目標とする。

つまり、

```text
PiTubeDirect側:
    既存のTubeバス動作を維持

Tang Nano 20K側:
    ext_tube_*を監視
    Host IRQを内部生成

MSX側:
    INT_nで割り込み受付
    B8h～BFhをアクセスして原因確認・データ取得
```

とする。

ポーリング方式もフォールバックとして残し、IRQ enableを無効にすれば従来どおりポーリングのみで動作できる構成を推奨する。

## 58. 引用元・参照資料

### BeebFPGA

- `hoglet67/BeebFpga`
- commit: `8423a54d13e802f0f4a032642c76c9e603175f84`
- `src/common/bbc_micro_core.vhd`
  - PiTubeDirect接続用`ext_tube_*`ポート
  - Co-Pro側`p_irq_b`, `p_nmi_b`, `p_rst_b`
  - 外部1MHz busの`ext_1mhz_irq_n`, `ext_1mhz_nmi_n`
- `src/gowin/tang20k/src/bbc_micro_tang20k_pitube.cst`
  - `js_clk` = Pin71
  - `js_load_n` = Pin72
  - `js_data` = Pin76

### Tang Nano 20K Dock Board schematic

- `tangnano20k_dock.pdf`
- Joystick sheet:
  - 74LV165A x2
  - `JS_Clk`
  - `JS_Load_n`
  - `JS_Data`
  - Atari-compatible DB9 joystick ports x2

## 59. 最終採用仕様

本仕様では次を採用する。

```text
Tube Host I/O:
    B8h～BFh

External CoProcessor:
    Raspberry Pi + PiTubeDirect

Host interrupt:
    方式B
    Tube状態をTang FPGA内で監視
    tube_host_irq_nを内部生成
    MSX CPU INT_nへ合成

Joystick:
    Pin71 = JS_Clk
    Pin72 = JS_Load_n
    Pin76 = JS_Data
    既存Dock Board回路を維持

PiTubeDirect Host IRQ専用物理線:
    追加しない

Fallback:
    IRQ disabled時はpolling動作
```

これにより、**PiTubeDirect外部Co-Processor、MSX Host IRQ、Dock Boardジョイスティックを同時使用可能な構成**を目標とする。
