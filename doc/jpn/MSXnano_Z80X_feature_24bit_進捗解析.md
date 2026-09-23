# MSXnano-Z80X `feature/24bit` 進捗解析

解析対象: `fpga.zip`

## 1. 結論

このソースは、24bit化の**土台部分まで実装され、Tang Nano 20K向けに合成・配置配線・bitstream生成まで到達している**。

ただし、現在の24bit拡張仕様で必要な「24bitアドレスを実際のメモリバスへ出す」「M1/M2でバンクをアドレス生成へ反映する」「24bit PC/SPを動作させる」「24bit命令群を実装する」という中核部分は、まだ実装されていない。

特に重要なのは、`MSXnano_CPU_Wrapper24.v` が24bit出力を持っているものの、

```verilog
assign A = {8'b0, cpu_addr};
```

となっており、`G80a` 内部のCPUアドレス `A_i[15:0]` をゼロ拡張しているだけである。

さらに `top.v` では、

```verilog
wire [15:0] bus_addr;
```

としてCPUアドレスバス自体が16bitのままで、`bank_*` および `mode24` は接続されていない。

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

## 3. 一部実装済みのバンクレジスタ

現在確認できる書込みは、

```vhdl
ED 04 -> bank_bc_r <= ACC
ED 14 -> bank_de_r <= ACC
ED 24 -> bank_hl_r <= ACC
ED 34 -> bank_int_r <= ACC
ED 35 -> bank_msp_r <= ACC
```

読出しは、

```vhdl
ED 0C -> ACC <= bank_bc_r
ED 1C -> ACC <= bank_de_r
ED 2C -> ACC <= bank_hl_r
```

まで。

つまり、

- BC bank: 一部あり
- DE bank: 一部あり
- HL bank: 一部あり
- INT bank: 書込みのみ
- MSP bank: 書込みのみ
- IX bank: 未実装
- IY bank: 未実装
- PC bank: 未実装

という状態。

また、これらはCPU内部の24bitアドレス生成に使用されていない。

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

しかし、

```verilog
wire [15:0] bus_addr;
```

であり、Wrapperの24bit `A` の上位8bitを利用していない。

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

は `top.v` から接続されていない。

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

# 12. 現在の開発フェーズへの対応

| 開発フェーズ | 状態 | 判定 |
|---|---|---|
| Phase 0 既存T80動作確認 | 実装済み | ○ |
| Phase 1 Bank Register | RTL実装済み（MSP本体を追加）、シミュレーション未実施 | △ |
| Phase 2 24bit Address Generator | 未実装 | × |
| Phase 3 SET_M0/M1/M2 | 命令・レジスタ状態のみ実装 | △ |
| Phase 4 Bank Register操作 | BC/DE/HL等の一部のみ | △ |
| Phase 5 24bit Load/Store | 未実装 | × |
| Phase 6 24bit ALU | 未実装 | × |
| Phase 7 24bit PUSH/POP | 未実装 | × |
| Phase 8 24bit JP/CALL/RET/JR | 未実装 | × |
| Phase 9 24bit Interrupt/RETI.L | 未実装 | × |
| Phase 10 PEA/LEA | 未実装 | × |
| Phase 11 LDIR24 | 未実装 | × |
| Phase 12 M2 BIOS | 未実装 | × |
| Phase 13 Resource/Hardware optimization | PnR済みだが24bit機能評価前 | △ |

---

# 13. 実際の進捗を一言で表すと

```text
既存T80
  │
  ├─ 24bit用モードレジスタ       ○
  ├─ 一部Bank Register           △
  ├─ SET_M0/M1/M2                ○
  │
  ├─ 24bit Address Generator     ×
  ├─ 24bit PC                    ×
  ├─ 24bit SP/MSP                ×
  ├─ 24bit Memory Access         ×
  ├─ 24bit ALU                  ×
  ├─ 24bit Control Flow         ×
  ├─ 24bit Interrupt             ×
  ├─ PEA/LEA                    ×
  └─ LDIR24                     ×
```

つまり、**「24bit化の制御レジスタをT80へ埋め込み、24bit対応Wrapperと実機ビルドまで作った段階」**であり、CPUコアとしての24bit実行機能はこれから実装する段階。

---

# 14. 次に着手すべき箇所

現在のソース構造からは、いきなり24bit命令を大量追加するより、まず以下を完成させるのが自然。

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

