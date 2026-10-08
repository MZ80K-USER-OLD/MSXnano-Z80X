# MSXnano-Z80X `feature/24bit` 進捗解析

解析対象: `fpga.zip`

> **更新 (2026-10-03・1回目):** `MSX_T80_24bit化_CPU仕様案_V5_2026-10-02.md` / `MSX_T80_24bit化_命令一覧_V5_2026-10-02.csv` / `MSX_T80_24bit化_実装工程表_2026-10-03.md` の追加に伴い、本解析の進捗フェーズ対応表（第12章）を新工程表のPhase 0〜16へ更新した。
>
> **更新 (2026-10-03・2回目):** Phase1の残作業のうち、`bank_ix_r`/`bank_iy_r`/`bank_pc_r`への書込み命令、および`bank_int_r`(IVR)/`bank_msp_r`(MSP)の読出し命令、新規`bank_nvr_r`(NVR)レジスタを`t80.vhd`/`g80a.vhd`/`t80_pack.vhd`/`MSXnano_CPU_Wrapper24.v`へ実装した（第3章・第12章Phase1行・第13章・第14章Step0を更新）。MSP24/IVR24/NVR24の24bit本体統合、JP.Mx/CALL.Mx/RET.Mは引き続き未着手。

## 1. 結論

このソースは、24bit化の**土台部分まで実装され、Tang Nano 20K向けに合成・配置配線・bitstream生成まで到達している**。

ただし、現在の24bit拡張仕様で必要な「24bitアドレスを実際のメモリバスへ出す」「M1/M2でバンクをアドレス生成へ反映する」「24bit PC/SPを動作させる」「24bit命令群を実装する」という中核部分は、まだ実装されていない。

特に重要なのは、`MSXnano_CPU_Wrapper24.v` が24bit出力を持っているものの、

```verilog
assign A = {8'b0, cpu_addr};
```

となっており、`G80a` 内部のCPUアドレス `A_i[15:0]` をゼロ拡張しているだけである。

さらに `top.v` では既存MSX周辺回路用の

```verilog
wire [15:0] bus_addr;
```

を維持している。Wrapperの24bit `A` は `cpu_addr24` で受け、下位16bitを既存周辺回路へ接続する。また、`bank_*` と `mode24` もトップ内wireへ接続するが、アドレス生成・メモリ変換にはまだ使用していない。

したがって、**現状は「24bit CPUの実装」ではなく、「24bit拡張用レジスタと命令デコーダ入口を追加した16bit T80」が実際の状態**と判断できる。

---

## 2. 実装済み

### 2.1 24bitモードレジスタ

`fpga/G80A/t80.vhd` に以下が存在する。

- `mode24_r`
- `bank_bc_r`
- `bank_de_r`
- `bank_hl_r`
- `bank_ix_r`
- `bank_iy_r`
- `bank_pc_r`
- `bank_msp_r`
- `bank_int_r`

リセット時には全て0に初期化されている。

### 2.2 SET_M0/M1/M2

`T_Res` 時の ED 拡張処理として、

```vhdl
when x"90" => mode24_r <= "00";
when x"91" => mode24_r <= "01";
when x"92" => mode24_r <= "10";
```

が実装されている。

したがって、現在の仕様の

- `ED 90` = SET_M0
- `ED 91` = SET_M1
- `ED 92` = SET_M2

はソース上で確認できる。

ただし、`mode24_r` は現状ほぼ状態表示用であり、**PC/SP/アドレス生成ロジックを切り替えていない**。

---

## 3. バンクレジスタ（2026-10-03 更新：Phase1残作業を実装）

現在確認できる書込みは、

```vhdl
ED 04 -> bank_bc_r  <= ACC   -- BC_B
ED 14 -> bank_de_r  <= ACC   -- DE_B
ED 24 -> bank_hl_r  <= ACC   -- HL_B
ED 34 -> bank_int_r <= ACC   -- IVR_B（provisional opcode）
ED 35 -> bank_msp_r <= ACC   -- MSP_B（provisional opcode）
ED 36 -> bank_ix_r  <= ACC   -- IX_B（provisional opcode・新規実装）
ED 37 -> bank_iy_r  <= ACC   -- IY_B（provisional opcode・新規実装）
ED 38 -> bank_pc_r  <= ACC   -- PC_B（provisional opcode・新規実装）
ED 3A -> bank_nvr_r <= ACC   -- NVR_B（provisional opcode・新規実装）
```

読出しは、

```vhdl
ED 0C -> ACC <= bank_bc_r    -- BC_B
ED 1C -> ACC <= bank_de_r    -- DE_B
ED 2C -> ACC <= bank_hl_r    -- HL_B
ED 05 -> ACC <= bank_msp_r   -- MSP_B（provisional opcode・新規実装）
ED 06 -> ACC <= bank_nvr_r   -- NVR_B（provisional opcode・新規実装）
ED 07 -> ACC <= bank_pc_r    -- PC_B（provisional opcode・新規実装）
ED 3C -> ACC <= bank_int_r   -- IVR_B（provisional opcode・新規実装）
ED 3E -> ACC <= bank_ix_r    -- IX_B（provisional opcode・新規実装）
ED 3F -> ACC <= bank_iy_r    -- IY_B（provisional opcode・新規実装）
```

まで実装済み。

つまり、

- BC bank: 読み書き両対応
- DE bank: 読み書き両対応
- HL bank: 読み書き両対応
- IVR bank（旧INT bank）: 読み書き両対応
- MSP bank: 読み書き両対応
- NVR bank: 読み書き両対応（新規追加レジスタ `bank_nvr_r`）
- IX bank: 読み書き両対応（新規実装）
- IY bank: 読み書き両対応（新規実装）
- PC bank: 読み書き両対応（新規実装）

という状態。BC_B/DE_B/HL_B/IX_B/IY_B/PC_B/MSP_B/IVR_B/NVR_Bの全バンクレジスタが読み書き可能になり、V5仕様 第3章で定義された24bitレジスタの「bankバイト」部分はPhase1完了条件（全レジスタを正常に保持・更新可能）を満たした。

ただし以下は引き続き未解決：

- 上記opcode（`ED 05/06/07/34/35/36/37/38/3A/3C/3E/3F`）はすべて**暫定割当**。V5仕様の命令一覧CSVでは対応命令（`LD24 MSP/IVR/NVR,imm24`等）のopcodeは「TBD」のままであり、正式確定時に置き換えが必要。
- `MSP`本体は引き続き16bit幅（`signal MSP : unsigned(15 downto 0)`）のまま。`bank_msp_r`は後付けの8bit拡張レジスタであり、MSP24としての24bit一体演算（±1でのbank跨ぎ等）には未統合（Phase4の範囲）。
- `IVR24`/`NVR24`は仕様上「24bit専用ベクタレジスタ」だが、現状は8bitの`bank_int_r`/`bank_nvr_r`のみで、16bit側のベクタ本体（ジャンプ先アドレス）は未実装。
- `PC_B`は直接書込み命令を用意したが、本来の更新経路である`JP.M2`/`CALL.M2`/`RET.M`（Phase2、`ED 93〜99`）とはまだ連動していない。
- シミュレーション/テストベンチによる動作検証は未実施。
- これらのバンクレジスタはCPU内部の24bitアドレス生成には依然として使用されていない（Phase4/Phase5が未着手のため）。

---

## 4. まだ16bitのままになっている箇所


`T80` 内部：

```vhdl
signal SP, PC : unsigned(15 downto 0);
```

であり、PC/SPそのものは16bit。

アドレス出力も、

```vhdl
A <= ...
```

の16bit。

`G80a` も、

```vhdl
A : out std_logic_vector(15 downto 0);
```

となっている。

そして `MSXnano_CPU_Wrapper24.v` で初めて24bit化しているが、

```verilog
wire [15:0] cpu_addr;
assign A = {8'b0, cpu_addr};
```

なので、上位8bitは常に0。

したがって現在の実効アドレス空間は16bit = 64KiB。

---

## 5. top.vへの接続状態

`top.v` では、

```verilog
MSXnano_CPU_Wrapper24
```

を実際にCPUとして使用している。

したがって、今回のブランチでは24bit対応版Wrapperが実機用トップへ組み込まれている。

ただし、

```verilog
wire [15:0] bus_addr;
```

は既存周辺回路向けの16bitバスであり、Wrapperの24bit `A` は別wire `cpu_addr24` で受けている。現在は下位16bitのみを `bus_addr` として使用し、上位8bitをアドレスデコードやメモリ変換には使用していない。

また、

- `mode24`
- `bank_bc`
- `bank_de`
- `bank_hl`
- `bank_ix`
- `bank_iy`
- `bank_pc`
- `bank_msp`
- `bank_int`
- `bank_nvr`

と `mode24` は `top.v` の対応wireに接続されているが、現時点では値をアドレス生成・メモリ制御へ反映していない。

このため、**FPGA外部のメモリ系へ24bitアドレスを伝える経路はまだ存在しない**。

---

## 6. 24bit命令の実装状況

### SET_M0/M1/M2

実装済み。

### 24bit LD

現在のソースからは、仕様で予定している

- `LD.L BC,ext24`
- `LD.L DE,ext24`
- `LD.L HL,ext24`
- `(XHL)` を使う3byte load/store

などの実装は確認できない。

既存T80の標準ED命令処理が中心で、ED空間の大部分は従来の

```vhdl
null; -- NOP, undocumented
```

として扱われている。

### JP.L / CALL.L / RET.L

現在の `t80_mcode.vhd` と `t80.vhd` から、仕様で定義した

- `ED C3`
- `ED CD`
- `ED C9`

による24bit PC制御は確認できない。

既存の `Jump` / `Call` / `PC` は16bitのまま。

### JR.L

24bit PC自体がまだないため未実装。

### PUSH/POP Xレジスタ

24bit SP/MSPを使用する処理は未実装。

### RETI.L

未実装。

### PEA/LEA

未実装。

### LDIR24

未実装。

---

## 7. 24bit ALU

`T80_ALU` は基本的に既存の8bit ALUで、`Arith16` 等によってZ80の16bit演算を実現している。

24bit専用の

```text
下位16bit演算
    ↓
bank byte + carry
```

という2段階処理はまだ確認できない。

したがって、24bit ADD/SUB/INC/DEC/比較などは未実装。

---

## 8. 割り込み

既存T80の割り込み処理は存在する。

しかし、現在確認できる実装では、

- M0/M1でUSPを使用
- M2でMSPを使用
- 24bit PCをpush
- `INT_B:0038`へジャンプ

という新仕様にはなっていない。

`PC` と `SP` が16bitなので、割り込みも従来の16bitT80方式。

`bank_int_r` と `bank_msp_r` のレジスタ自体は追加されているが、割り込みアドレス生成への接続はまだない。

---

## 9. μIR / microcodeについて

このブランチは、現在の開発手順で採用している「RTL decoder/state machine/datapathへ移行した構成」ではない。

既存T80の

```text
T80
 ├─ T80_MCode
 ├─ T80_ALU
 └─ T80_Reg
```

というマイクロコード方式をそのまま使用している。

24bit関連の追加処理は主に `t80.vhd` の

```vhdl
if T_Res = '1' then
    if ISet = "10" then
        case IR is
```

の中へ直接追加されている。

したがって、現在のブランチは

**「既存T80 microcode + t80.vhdへの24bit拡張ロジック追加」**

という実装方式。

これは、現在の24bit化開発手順で決めている「microcodeを新規実装せずRTLで進める」という方針とは異なる。

ただし、24bit拡張部分については、既存microcodeを大規模に書き換えるところまでは進んでいない。

---

## 10. ビルド状態

今回のZIPにはTang Nano 20K向けの合成・PnR生成物が含まれている。

確認できるもの：

- Gowin synthesis log
- synthesis netlist
- synthesis resource report
- PnR report
- timing paths
- bitstream `.bin`
- `.fs`

PnR reportには、

```text
Part Number: GW2AR-LV18QN88C8/I7
Tool Version: V1.9.11.03 Education
Created Time: Sat Sep 19 19:22:28 2026
```

とあり、配置配線まで完了している。

Resource Usage:

| Resource | Usage |
|---|---:|
| Logic | 14931 / 20736 (72%) |
| Register | 6935 / 15915 (44%) |
| BSRAM | 45 / 46 (98%) |
| DSP | 1.5 / 24 (7%) |
| I/O | 38 / 66 (58%) |
| CLS | 9098 / 10368 (88%) |

特にBSRAMが45/46、98%なので、今後24bit化を進める場合には、CPUだけでなく既存VDP/メモリ構成を含めたリソース管理が重要。

---

## 11. ビルドログ上の注意

合成ログには少なくとも以下の警告が確認できる。

```text
Undeclared symbol 'spi_io_dout', assumed default net type 'wire'
Undeclared symbol 'system_leds', assumed default net type 'wire'
```

その他、`pow()` の型に関する警告、SystemVerilogポート再宣言などの警告も存在する。

これらは24bit CPUそのものの未実装とは別問題だが、最終的な正式ビルドでは整理した方がよい。

---

# 12. 現在の開発フェーズへの対応（V5仕様・新工程表 Phase 0〜16 準拠）

`MSX_T80_24bit化_実装工程表_2026-10-03.md` で定義されたPhase 0〜16に対し、現ソース（`t80.vhd` / `MSXnano_CPU_Wrapper24.v` / `top.v`）の実態を照合した結果を以下に示す。

| Phase | 実装内容 | 完了条件（工程表より） | 現状 | 判定 |
|---|---|---|---|---|
| 0 | ベースライン固定 | 改造前T80でMSX/Z80が正常動作 | 既存MSXnano/T80がベースとして存在し、Tang Nano 20K実機までビルド済み | ○ |
| 1 | 24bitレジスタ | 全レジスタを正常に保持・更新可能 | 2026-10-03更新：`bank_bc_r/de_r/hl_r/ix_r/iy_r/pc_r/msp_r/int_r`に加え新規`bank_nvr_r`まで、全バンクレジスタが`ED 04/14/24/34/35/36/37/38/3A`書込み・`ED 0C/1C/2C/05/06/07/3C/3E/3F`読出しに対応。ただしopcodeは全て暫定割当（V5仕様はTBD）。`MSP`本体は16bit幅のまま、IVR24/NVR24は8bitのbankバイトのみで16bit側ベクタ本体は未実装。シミュレーション未実施 | △→○に近い△（bankバイトは全レジスタ保持・更新可能。24bit一体化・ベクタ機能・検証が残る） |
| 2 | MODE制御 | MODE切替とSP選択を確認 | `SET_M0/M1/M2`(`ED 90/91/92`)による`mode24_r`切替のみ実装。`JP.Mx/CALL.Mx/RET.M`(`ED 93〜99`)は`t80_mcode.vhd`にエントリなし。SP/MSP selectorはPC/SPアドレス生成へ未接続 | △ |
| 3 | 24bit ALU | 境界値・overflow・carryテスト合格 | `t80_alu.vhd`に24bit演算・signed overflow(P/V)・H保持ロジックなし | × |
| 4 | 24bitアドレス生成 | `xx:FFFF → xx+1:0000` 正常 | PC24/IX24/IY24/MSP24/EA24、bank跨ぎロジックともに未実装 | × |
| 5 | MMU接続 | bank境界を跨ぐread/write成功 | MMUモジュール自体がリポジトリに存在しない。`top.v`ではWrapperの`A`を24bit `cpu_addr24`で受け、`mode24/bank_*`もwireへ接続したが、まだアドレス生成・メモリ制御には使用していない。ラッパー内`assign A = {8'b0, cpu_addr};`で上位8bit固定0。既存周辺回路向け`bus_addr`は下位16bitのまま | × |
| 6 | 基本24bit命令 | BC/DE/HL/IX/IY基本命令合格 | INC24/DEC24/ADD24等、専用24bit ALUを用いる命令は未実装 | × |
| 7 | DD/FD拡張 | IX/IY 24bit ALU・bank命令合格 | `DD/FD ED`デコーダ、HL→IX/IY mirrorともに未実装 | × |
| 8 | 24bit LD | 24bit register transfer合格 | HL24ハブ転送、MSP/IVR/NVR転送とも未実装 | × |
| 9 | indexed LD | ±d、bank境界、MMU跨ぎ合格 | `DD/FD ED 80〜8B`等のindexed LDは未実装 | × |
| 10 | M2 stack | 64KB境界を跨ぐstack動作合格 | MSP24 PUSH/POP、3byte転送は未実装（MSPが16bitのため跨ぎ自体不可） | × |
| 11 | 24bit制御フロー | M2でbankを跨ぐCALL/RET成功 | `JR.L/JP.L/CALL.L/RET.L`は`t80_mcode.vhd`・`t80.vhd`に実装なし。既存Jump/Call/PCは16bitのまま | × |
| 12 | mode CALL | M0/M1/M2相互CALL/RET成功 | `SET_M0/M1/M2`のみ実装済み。`JP.Mx/CALL.Mx/RET.M`と4byte frameは未実装 | △ |
| 13 | M2 interrupt | IRQ/NMI→ISR→復帰成功 | 既存T80の16bit割込みのまま。IVR/NVR、RETI.L/RETN.L、IFF処理は未接続 | × |
| 14 | CPU統合検証 | Z80回帰＋24bitテスト全合格 | 24bit機能自体が未実装のため統合検証は未着手 | × |
| 15 | FPGA実装 | timing closure、実機起動 | Tang Nano 20K向け合成・PnR・bitstream生成済み（Resource: Logic 72%, BSRAM 98%）。ただし現状は16bit CPUとしての実機動作 | △ |
| 16 | MSX実機相当検証 | M0互換性＋M1/M2プログラム動作 | M0（既存Z80/MSX互換）動作は前提として確認済み。M1/M2の24bitプログラム動作は検証対象自体が未実装 | × |

---

# 13. 実際の進捗を一言で表すと

```text
既存T80
  │
  ├─ 24bit用モードレジスタ       ○
  ├─ Bank Register(BC/DE/HL/IX/IY/PC/MSP/IVR/NVR) ○（bankバイトのみ、全レジスタ読み書き対応・2026-10-03実装）
  ├─ SET_M0/M1/M2                ○
  │
  ├─ JP.Mx/CALL.Mx/RET.M         ×
  ├─ 24bit Address Generator     ×
  ├─ 24bit PC                    ×
  ├─ 24bit SP/MSP24               ×
  ├─ MMU(論理24bit→物理変換)     ×
  ├─ 24bit Memory Access         ×
  ├─ 24bit ALU                  ×
  ├─ 24bit Control Flow         ×
  ├─ 24bit Interrupt(IVR/NVRの16bitベクタ本体) ×
  ├─ PEA/LEA                    ×
  └─ LDIR24                     ×
```

つまり、**「24bit化の制御レジスタをT80へ埋め込み、全バンクレジスタの読み書きと24bit対応Wrapper・実機ビルドまで作った段階」**であり、CPUコアとしての24bit実行機能、および新仕様書で中核とされているMMU（論理24bit→FPGA物理アドレス変換層）はこれから実装する段階。

---

# 14. 次に着手すべき箇所

現在のソース構造からは、いきなり24bit命令を大量追加するより、まず以下を完成させるのが自然。新工程表（Phase 0〜16）に沿えば、着手順はPhase 1残作業→Phase 2残作業→Phase 3以降となる。

### Step 0 — Phase 1 / Phase 2 の未完了分を先に仕上げる

- ~~`bank_ix_r` / `bank_iy_r` / `bank_pc_r` への書込み命令（IX_B/IY_B/PC_B相当のLD）を追加する。~~ → **2026-10-03実装済み**（`ED 36/37/38`書込み、`ED 3E/3F/07`読出し。暫定opcode）。新規`bank_nvr_r`（NVR24 bankバイト）も追加し、`bank_int_r`(IVR)・`bank_msp_r`(MSP)の読出し（`ED 3C/05`）も追加済み。
- `MSP` を24bit化し、`ED 34/35`の仮opcodeをV5仕様のTBD命令（`LD24 MSP,imm24` 等）確定後の正式opcodeへ置き換える。IVR24/NVR24も同様に24bit専用ベクタレジスタ（16bit側のベクタ本体を含む）として再設計する。**（未着手）**
- `JP.Mx` / `CALL.Mx` / `RET.M`（`ED 93〜99`）を`t80_mcode.vhd`に追加し、MSPへの4byte frame PUSH/POPを実装する（現状`SET_M0/M1/M2`のみでモード間CALL/RETが存在しない）。**（未着手）**

残る2項目（MSP/IVR/NVRの24bit化、JP.Mx/CALL.Mx/RET.M）はPhase 3以降（24bit ALU・アドレス生成・MMU接続）の前提となるため優先度が高い。

### Step 1 — 24bitアドレス生成器

`T80` 内部で、

```text
M0:
    {00, address16}

M1:
    register indirect:
        {BANK_X, register16}

M2:
    instruction fetch:
        {PC_B, PC16}

    stack:
        {MSP_B, MSP16}
```

を生成する専用ロジックを作る。

### Step 2 — CPU内部アドレスを24bit化

現在：

```vhdl
A : out std_logic_vector(15 downto 0);
```

を、

```vhdl
A : out std_logic_vector(23 downto 0);
```

へ変更。

`G80a` → `MSXnano_CPU_Wrapper24` → `top.v`

まで24bitを維持する。

### Step 3 — top.v / memory.vを24bit化

現在の

```verilog
wire [15:0] bus_addr;
```

を24bit化し、

```text
CPU
 ↓
24bit address
 ↓
bank / memory mapper
 ↓
16MB address space
```

の経路を確立する。

### Step 3.5 — MMU単体実装・単体テスト（新工程表Phase 5対応）

`MSX_T80_24bit化_実装工程表_2026-10-03.md`の「MMU実装詳細」に基づき、CPU統合前にMMUを単体モジュールとして実装する。

- 256個の8bit bank registerを持つMMU register file（bank 00はMSX/Z80互換用）
- I/O port `F0/F1`によるMMU registerの選択・アクセス
- 各byteごとに論理アドレス→物理アドレス変換を行う（複数byte load/storeを一括変換しない）
- MMU単体testbenchで以下を確認してからCPUの24bit ALU/EA生成回路と接続する
  - register select/write/read、bank 00互換動作、任意bankのmapping
  - SDRAM/BSRAM/MSX slot等のtarget選択
  - `xx:FFFF → xx+1:0000` 境界跨ぎ、隣接bankへの連続byte access
  - reset後のMMU状態、M0/M1/M2それぞれのaddress経路

現時点ではMMUモジュール自体がリポジトリに存在しないため、本Stepは未着手。

### Step 4 — M1のregister-indirect

最初に、

```text
LD (XHL),A
LD A,(XHL)
```

相当の最小機能を作り、

```text
HL = 1234h
HL_B = 56h

→ address = 56:1234
```

が実際にRAMへ出ることを確認する。

### Step 5 — M2 PC fetch

その後、

```text
PC_B:PC
```

から命令フェッチできるようにする。

ここが完成すれば、初めてM2が「24bitプログラム実行モード」になる。

---

# 15. 重要な注意点

今回の解析では、ZIP内の実ソースを基準に判定している。

したがって、

- 仕様書にあるがソースに存在しないもの
- 今後実装予定のもの
- 名前だけ存在するもの
- 実際のアドレス生成に接続されていないもの

を「実装済み」とは扱っていない。

特に `MSXnano_CPU_Wrapper24` の24bit `A` は、名前だけを見ると24bit化済みに見えるが、実際には上位8bitを常に0としているため、**実効的には16bitアドレスのまま**である。
