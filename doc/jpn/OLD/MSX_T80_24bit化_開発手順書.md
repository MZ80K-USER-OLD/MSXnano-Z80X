# MSXnano T80 24bit化 開発手順書

**対象:** MSXnano T80ベース 24bit CPU拡張  
**対象FPGA:** Tang Nano 20Kを主対象とする  
**開発方式:** 既存T80をベースにしたRTL（Verilog）による拡張  
**基本方針:** 初期開発ではマイクロコード方式を採用せず、命令デコーダ・ステートマシン・既存データパスを拡張する

---

## 1. 開発目標

MSXnanoの既存Z80互換動作を維持したまま、CPUのアドレス空間を24bit（16MB）へ拡張する。

最終的には以下の3モードを持つCPUを構成する。

| モード | 内容 |
|---|---|
| M0 | 完全Z80/MSX互換 |
| M1 | PC/SPは16bit、データアクセスのみ24bit拡張 |
| M2 | PC/SP/データアクセスを24bit化したネイティブモード |

24bit化によって、MSXの既存BIOS/DOS/ソフトウェアをM0で動作させつつ、M2では24bitアプリケーション、拡張メモリ、24bit BIOSを実行できる構成を目標とする。

---

# 2. 開発上の最重要原則

## 2.1 M0を壊さない

最初の実装段階では、M0の既存T80動作を可能な限り変更しない。

特に以下を維持する。

- Z80命令セット
- Z80フラグ動作
- PCの16bit動作
- USPを使用した16bitスタック
- MSX BIOS/DOSから見た従来のメモリ空間
- I/Oアクセス
- 割り込み
- Rレジスタ等の既存T80互換動作

24bit拡張は、M0に影響しない追加経路として実装する。

---

## 2.2 M[1:0]を最上位の動作モード選択にする

CPU内部に2bitのモード状態 `M[1:0]` を設ける。

### M0

- PC: bank 00
- SP: USP
- データアクセス: bank 00
- 完全Z80/MSX互換

### M1

- PC: bank 00
- SP: USP
- HL/BC/DE/IX/IY等のバンクレジスタを使用したデータアクセスが可能
- プログラム実行自体は16bit空間

### M2

- PC: PC_B:PC
- SP: MSP_B:MSP
- データアクセス: 各レジスタのバンクを使用
- 24bitプログラム実行

モード切替時にCPU内部で自動的に別コンテキストへ移行する仕組みは設けない。

M0/M1/M2の切替は命令によって明示的に行う。

---

# 3. CPU内部レジスタ拡張

以下のバンクレジスタを追加する。

| レジスタ | 用途 |
|---|---|
| `BC_B` | BCの上位8bit |
| `DE_B` | DEの上位8bit |
| `HL_B` | HLの上位8bit |
| `IX_B` | IXの上位8bit |
| `IY_B` | IYの上位8bit |
| `PC_B` | PCの上位8bit |
| `MSP_B` | MSPの上位8bit |
| `INT_B` | M2割り込み先の上位8bit |

スタックは2系統とする。

- `USP`: 従来の16bitスタック
- `MSP_B:MSP`: 24bitスタック

リセット時は以下を0に初期化する。

- 全バンクレジスタ
- `PC_B`
- `MSP_B`
- `INT_B`
- `M[1:0]`

---

# 4. 開発フェーズ全体

開発は次の順序で進める。

```text
Phase 0  現行T80の固定
   ↓
Phase 1  24bitレジスタ追加
   ↓
Phase 2  24bitアドレス生成
   ↓
Phase 3  M0/M1/M2制御
   ↓
Phase 4  24bitロード/ストア
   ↓
Phase 5  24bit演算
   ↓
Phase 6  24bit PUSH/POP
   ↓
Phase 7  JP/CALL/RET/JR
   ↓
Phase 8  割り込み/RETI
   ↓
Phase 9  PEA/LEA
   ↓
Phase 10 LDIR24等のブロック命令
   ↓
Phase 11 M2 BIOS / ソフトウェア環境
   ↓
Phase 12 MSXnano実機統合
   ↓
Phase 13 FPGAリソース/Fmax最適化
```

各Phaseで、必ず

1. RTL変更
2. 単体シミュレーション
3. 命令テスト
4. M0回帰試験
5. 合成
6. 実機確認

を行う。

---

# 5. Phase 0：現行T80を固定する

最初に改造前のT80を基準版として固定する。

## 実施内容

- 現行T80をGitでタグ付け
- FPGA合成結果を保存
- LUT/FF/BRAM/Fmaxを記録
- Z80命令テストを実行
- MSXnanoのBIOS起動を確認
- MSX-BASIC起動を確認
- Nextor/DOS等の既存環境を確認

## 保存する基準値

```text
LUT:
FF:
BRAM:
Fmax:
CPU clock:
BIOS起動:
BASIC起動:
DOS起動:
```

以後、24bit化によってM0互換性が壊れていないか、この基準と比較する。

---

# 6. Phase 1：24bitレジスタを追加

最初に命令を追加せず、レジスタだけを追加する。

## 実装

```verilog
reg [7:0] BC_B;
reg [7:0] DE_B;
reg [7:0] HL_B;
reg [7:0] IX_B;
reg [7:0] IY_B;
reg [7:0] PC_B;
reg [7:0] MSP_B;
reg [7:0] INT_B;

reg [15:0] MSP;
reg [15:0] USP;
reg [1:0]  M;
```

実際の既存T80内部構造に合わせ、重複したレジスタを作らず既存SP/PCとの接続を整理する。

## このPhaseの試験

- resetで全バンク=00
- USP/PCの既存動作確認
- レジスタ値の保持
- M0時にバンクレジスタがアドレスバスへ影響しないこと

---

# 7. Phase 2：24bitアドレス生成器を作る

24bitアドレス生成をCPU内部で一元化する。

基本形：

```text
addr[23:16] = bank
addr[15:0]  = address
```

## M0

```text
bank = 00
```

## M1

データアクセス時のみ対象レジスタのバンクを使用する。

```text
(HL_B : HL)
(BC_B : BC)
(DE_B : DE)
(IX_B : IX)
(IY_B : IY)
```

ただしPC/SPは16bit。

## M2

```text
PC = PC_B : PC
SP = MSP_B : MSP
data = 対象レジスタ_B : 対象レジスタ
```

アドレス生成器は可能な限り1箇所に集約し、命令ごとに24bitアドレス生成回路を重複させない。

---

# 8. Phase 3：SET_M0/M1/M2

確定opcode：

```text
ED 90  SET_M0
ED 91  SET_M1
ED 92  SET_M2
```

旧割り当て

```text
ED 70
ED 71
ED 72
```

は使用しない。

## 試験

```asm
SET_M1
SET_M2
SET_M0
```

を順番に実行し、

- PCバンク
- SP
- データアクセス
- 命令フェッチ

が各モードの仕様どおり切り替わることを確認する。

---

# 9. Phase 4：バンクレジスタ操作

以下を実装する。

```text
ED 04  LD BC_B,A
ED 14  LD DE_B,A
ED 24  LD HL_B,A
ED 34  LD INT_B,A
ED 35  LD MSP_B,A

ED 0C  LD A,BC_B
ED 1C  LD A,DE_B
ED 2C  LD A,HL_B
```

## テスト例

```asm
LD A,12h
ED 24

LD A,HL_B
```

などで読み書き一致を確認する。

---

# 10. Phase 5：24bitロード/ストア

まず単純なデータ転送を完成させる。

確定命令：

```text
ED 32  LD XHL,ext24
ED 2A  LD XHL,(ext24)
ED 22  LD (ext24),XHL

ED 4F  LD XBC,(XHL)
ED 5F  LD XDE,(XHL)
ED 47  LD (XHL),XBC
ED 57  LD (XHL),XDE
```

`ext24` は

```text
bl,bh,bn
```

の順とする。

## 境界試験

必ず以下を試す。

```text
00:0000
00:FFFF
01:0000
01:FFFF
FF:0000
FF:FFFF
```

特に16bit境界とbank境界を重点的に確認する。

---

# 11. Phase 6：24bit ALU

24bit演算は24bit幅の一発加算器を作らず、既存16bit ALUを再利用する。

## 2サイクル方式

### Cycle 1

```text
下位16bitを演算
```

結果：

```text
result[15:0]
X_Carry
```

を保存。

### Cycle 2

```text
bank + X_Carry
```

を計算し、上位8bitへ書き戻す。

## 対象命令

```text
ED 03 INC XBC
ED 13 INC XDE
ED 23 INC XHL
ED 33 INC XSP

ED 0B DEC XBC
ED 1B DEC XDE
ED 2B DEC XHL
ED 3B DEC XSP

ED 09 ADD XHL,XBC
ED 19 ADD XHL,XDE
ED 29 ADD XHL,XHL
ED 39 ADD XHL,XSP

ED 0A SUB XHL,XBC
ED 1A SUB XHL,XDE
ED 3D CP XHL,XDE
```

## 必須境界テスト

```text
00:FFFF + 1 = 01:0000
FF:FFFF + 1 = 00:0000
01:0000 - 1 = 00:FFFF
00:0000 - 1 = FF:FFFF
```

---

# 12. Phase 7：24bit PUSH/POP

確定命令：

```text
ED C5  PUSH XBC
ED D5  PUSH XDE
ED E5  PUSH XHL
ED F5  PUSH XAF

ED C1  POP XBC
ED D1  POP XDE
ED E1  POP XHL
ED F1  POP XAF
```

M2ではMSPを使用し、24bit値を退避する。

M0/M1ではUSPを使用する仕様を維持する。

## 試験

```text
PUSH → POP
```

について、

- 値
- bank
- SP
- 境界
- 連続PUSH/POP

を確認する。

---

# 13. Phase 8：24bit制御命令

Z80 opcode mirror方式を採用する。

## JP

```text
ED C3       JP.L
ED C2/CA    JP.L NZ/Z
ED D2/DA    JP.L NC/C
ED E2/EA    JP.L PO/PE
ED F2/FA    JP.L P/M
```

## JR.L

```text
ED 18       JR.L
ED 20/28    JR.L NZ/Z
ED 30/38    JR.L NC/C
ED C7/D7    JR.L PO/PE
ED E7/F7    JR.L P/M
```

`offset16 = dl,dh`

JR.Lのバンク境界越えではPC_Bを変更せず、16bit境界でラップアラウンドする仕様をテストする。

## CALL

```text
ED CD
ED C4/CC
ED D4/DC
ED E4/EC
ED F4/FC
```

M2では24bitPCをMSPへ3byte退避する。

## RET

```text
ED C9
ED C0/C8
ED D0/D8
ED E0/E8
ED F0/F8
```

## 重要な旧opcode

以下は使用しない。

```text
ED 5C  JP.L
ED 22  CALL.L
ED 6B  RET.L
ED 60～67 JR.L
```

正式opcodeは上記のZ80 mirror方式を優先する。

---

# 14. Phase 9：割り込み

割り込み受付は、その瞬間のMを直接参照する。

## M0/M1

```text
USP使用
PC下位16bitをpush
000038へジャンプ
Mは変更しない
```

## M2

```text
MSP使用
PC_B:PCの3byteをpush
INT_B:0038へジャンプ
M2を維持
```

M2のRST 38Hについても同じ24bitシステムコール動作を確認する。

## RETI.L

```text
ED 4E
```

MSPから24bitPCを復帰する。

---

# 15. Phase 10：PEA / LEA

IX/IYの24bitアドレス演算を追加する。

```text
DD ED 68 d   LEA.L XHL,(XIX+d)
FD ED 68 d   LEA.L XHL,(XIY+d)

DD ED 69 d   LEA.L XDE,(XIX+d)

DD ED 6A d   PEA.L (XIX+d)
FD ED 6A d   PEA.L (XIY+d)
```

変位は8bit符号付き。

このアドレス演算も24bit一発加算器を作らず、既存ALUを使ったマルチサイクル処理とする。

---

# 16. Phase 11：LDIR24

```text
ED 6F  LDIR24
```

動作：

```text
(XHL) → (XDE)
XHL++
XDE++
XBC--
XBC == 0 まで繰り返す
```

16MBアドレス空間全域を扱えるよう、bank carryを含めたXHL/XDEの24bitインクリメントを使用する。

## 必須試験

- 1byte
- 256byte
- bank境界
- 64KiB境界
- 複数bank
- XBC=0
- source/destination重複

特にブロック転送を外部シミュレータの特別処理に依存させず、CPU RTL内で完結させる。

---

# 17. Phase 12：M2 BIOS

CPUハードウェアが安定した後にM2 BIOSを構築する。

基本方針：

```text
M0
 ↓
SET_M2
 ↓
M2 BIOS
 ↓
M2アプリケーション
 ↓
SET_M0
 ↓
MSX BIOS
```

既存MSX BIOSを直接24bit化するのではなく、必要に応じてM2側からM0 BIOSを呼び出すthunkを用意する。

基本形：

```asm
SET_M0
CALL    MSX_BIOS_ENTRY
SET_M2
RET.L
```

実際のABI、レジスタ保存、USP/MSP切替についてはM2 BIOS仕様として別途固定する。

---

# 18. Phase 13：アセンブラ/バイナリ生成

CPU RTLと並行して、命令バイナリ表を固定する。

最低限、以下を1つの機械可読データから生成する。

```text
opcode
mnemonic
operand
instruction length
mode
flags
description
```

特に以下を自動検査する。

- opcode重複
- 未定義opcode
- ED prefix競合
- operand長
- ext24 = bl,bh,bn
- offset16 = dl,dh
- 条件コード
- M0/M1/M2制約

命令表を手編集してRTLと別々に管理しない。

---

# 19. RTL実装構造

推奨構成：

```text
T80
 ├─ Fetch
 ├─ Decode
 │   ├─ Z80 decoder
 │   └─ ED extension decoder
 │
 ├─ Register File
 │   ├─ Z80 registers
 │   ├─ Bank registers
 │   ├─ PC_B
 │   ├─ MSP
 │   ├─ MSP_B
 │   ├─ USP
 │   └─ M
 │
 ├─ Address Generator
 │
 ├─ Existing 16bit ALU
 │
 ├─ 24bit Multi-cycle Controller
 │
 ├─ Memory Interface
 │
 └─ Interrupt Controller
```

24bit命令ごとに独立した巨大な組合せ回路を作らない。

---

# 20. ステートマシン設計

24bit命令は必要に応じて複数ステートに分割する。

例：

```text
FETCH
  ↓
DECODE
  ↓
ED_DECODE
  ↓
EXT_FETCH
  ↓
EXEC_LOW
  ↓
EXEC_BANK
  ↓
WRITEBACK
  ↓
FETCH
```

メモリ待ちが存在する場合は、

```text
MEM_REQ
MEM_WAIT
MEM_COMPLETE
```

を明確に分離する。

特にSDRAM/外部メモリを使用する場合、1サイクル完結を前提にしない。

---

# 21. シミュレーション試験の順序

## Level 1：レジスタ

```text
reset
bank register
M
USP/MSP
PC_B
```

## Level 2：アドレス

```text
bank 00
bank 01
bank FF
16bit wrap
24bit wrap
```

## Level 3：単命令

```text
LD
INC
DEC
ADD
SUB
CP
PUSH
POP
```

## Level 4：制御

```text
JP
JR
CALL
RET
RETI
```

## Level 5：割り込み

```text
M0 IRQ
M1 IRQ
M2 IRQ
RST 38H
```

## Level 6：複合命令

```text
LDIR24
PEA
LEA
```

## Level 7：ソフトウェア

```text
M2 BIOS
M2 monitor
24bit test program
MSX BIOS thunk
```

---

# 22. M0回帰試験

24bit拡張を1つ追加するたびに、M0の回帰試験を行う。

最低限：

```text
Z80命令セット
MSX BIOS
MSX BASIC
MSX-DOS / Nextor
VDP I/O
PSG I/O
FM音源I/O
割り込み
キーボード
ディスクアクセス
```

24bit命令を使用していないM0プログラムの結果が改造前と一致することを確認する。

---

# 23. 実機試験

RTLシミュレーションが通ったらTang Nano 20Kで実機確認する。

順序：

```text
1. reset
2. M0 BIOS起動
3. M0 BASIC
4. SET_M1
5. M1 data access
6. SET_M2
7. M2 RAM test
8. M2 arithmetic
9. M2 stack
10. M2 JP/CALL/RET
11. M2 IRQ
12. LDIR24
13. M2 BIOS
14. MSX peripheral access
```

---

# 24. FPGAリソース評価

各Phaseで合成レポートを保存する。

確認項目：

```text
LUT
FF
BSRAM
PLL
IO
Fmax
Critical Path
```

特に注意するもの：

- 24bitアドレス生成
- 24bit加算
- 条件分岐デコード
- EDデコーダ
- メモリ待ち制御
- LDIR24
- 割り込み

24bit ALUは2サイクル化してクリティカルパスを抑える。

---

# 25. デバッグ用テストプログラム

CPU開発専用に、以下のテストプログラムを用意する。

```text
T24_RESET
T24_BANK
T24_M0
T24_M1
T24_M2
T24_LOAD
T24_STORE
T24_INC
T24_DEC
T24_ADD
T24_SUB
T24_STACK
T24_JP
T24_JR
T24_CALL
T24_RET
T24_IRQ
T24_LEA
T24_PEA
T24_LDIR24
```

各テストは

```text
PASS
FAIL
```

を明確に出力できるようにする。

---

# 26. 開発を進める際の禁止事項

以下は現段階では行わない。

### 1. M0の全面書き換え

既存T80のZ80部分を24bit対応コードへ全面的に置換しない。

### 2. 24bit一発ALU

FPGAのクリティカルパスを悪化させる24bit専用一発加算器を基本構成にしない。

### 3. 命令ごとの巨大な組合せ回路

複雑な24bit命令はステートマシンで分割する。

### 4. マイクロコード化

現段階の開発ではマイクロコード方式を採用しない。

まずRTLデコーダ＋ステートマシン＋既存ALU再利用で完成させる。

### 5. Mの自動切替

CALL/RET/IRQ等の途中でCPUが勝手にM0/M2を切り替えない。

### 6. 旧opcodeの再利用

確定したopcodeを別命令に再割り当てしない。

---

# 27. 現在のopcode確定事項

特に以下は固定する。

```text
SET_M0       ED 90
SET_M1       ED 91
SET_M2       ED 92

JP.L         ED C3
CALL.L       ED CD
RET.L        ED C9
JR.L         ED 18
JR.L NZ/Z    ED 20/28
JR.L NC/C    ED 30/38

LDIR24       ED 6F
RETI.L       ED 4E
```

旧割り当て：

```text
ED 70/71/72
ED 60～67
ED 5C
ED 22 (CALL用途)
ED 6B
```

は使用しない。

---

# 28. 命令仕様書との整合性チェック

開発前に、命令仕様書と実装の間で以下を自動検査する。

| 項目 | 確認 |
|---|---|
| SET_M0/M1/M2 | ED 90/91/92 |
| JP.L | ED C3 |
| CALL.L | ED CD |
| RET.L | ED C9 |
| JR.L | ED 18系 |
| LDIR24 | ED 6F |
| RETI.L | ED 4E |
| ext24 | bl,bh,bn |
| offset16 | dl,dh |
| Z80条件8種 | NZ/Z/NC/C/PO/PE/P/M |
| opcode重複 | 0件 |
| M0互換命令 | 既存動作維持 |

なお、現在の改訂版命令表には一部表記上の確認対象が残っているため、RTL固定前に「命令バイナリ一覧」と突合して確定させる。

特にI/O命令のopcode表記と、`LD XSP,ext24` のoperand表記は、命令バイナリ一覧との機械的突合を開発ゲートにする。

---

# 29. Gitブランチ運用

推奨：

```text
main
 └─ feature/t80-24bit
      ├─ phase1-register
      ├─ phase2-address
      ├─ phase3-mode
      ├─ phase4-memory
      ├─ phase5-alu
      ├─ phase6-stack
      ├─ phase7-control
      ├─ phase8-interrupt
      ├─ phase9-lea-pea
      ├─ phase10-ldir24
      └─ phase11-m2bios
```

各Phaseがシミュレーションを通過した時点でタグを付ける。

例：

```text
t80-24bit-phase1
t80-24bit-phase2
...
```

---

# 30. 各Phaseの完了条件

Phaseを完了とする条件：

1. RTLコンパイル成功
2. シミュレーション成功
3. 新規命令テスト成功
4. M0回帰試験成功
5. opcode表との一致
6. 合成成功
7. FPGAリソース確認
8. 前Phaseより重大な回帰がない

これらを満たさない場合は次Phaseへ進まない。

---

# 31. 現時点から最初に実施する作業

現在の開発状態からは、以下の順で着手する。

## Step 1

現行MSXnano T80をベースライン化する。

## Step 2

`M`、`PC_B`、`BC_B`、`DE_B`、`HL_B`、`IX_B`、`IY_B`、`MSP`、`MSP_B`、`INT_B`を追加する。

## Step 3

24bitアドレス生成器を実装する。

## Step 4

`ED 90/91/92` のM0/M1/M2切替を実装する。

## Step 5

バンクレジスタ操作命令を実装する。

## Step 6

24bitメモリロード/ストアを実装する。

## Step 7

24bit ALUを2サイクル方式で実装する。

## Step 8

24bit PUSH/POPを実装する。

## Step 9

JP/JR/CALL/RETをZ80 opcode mirror方式で実装する。

## Step 10

割り込みとRETI.Lを実装する。

## Step 11

PEA/LEAを実装する。

## Step 12

LDIR24を実装する。

## Step 13

M2 BIOSとM0 BIOS thunkを実装する。

## Step 14

MSXnano実機で総合試験する。

---

# 32. 開発完了時の構成

最終的には次の構造を目標とする。

```text
                    ┌───────────────────────┐
                    │       MSXnano T80     │
                    │                       │
 Z80/MSX program ──┤ M0                    │
                    │                       │
                    │ M1 ── 24bit data     │
                    │                       │
 M2 application ───┤ M2 ── 24bit native    │
                    │                       │
                    │ ┌─────────────────┐   │
                    │ │ Z80 ALU         │   │
                    │ │ 16bit           │   │
                    │ └───────┬─────────┘   │
                    │         │ 2 cycles    │
                    │ ┌───────▼─────────┐   │
                    │ │ 24bit extension │   │
                    │ │ state machine   │   │
                    │ └───────┬─────────┘   │
                    │         │             │
                    │ ┌───────▼─────────┐   │
                    │ │ 24bit address   │   │
                    │ │ generator       │   │
                    │ └─────────────────┘   │
                    └──────────┬────────────┘
                               │
                         24bit address
                               │
                    ┌──────────▼──────────┐
                    │   16MB memory      │
                    └─────────────────────┘
```

この構成で、M0では従来のMSX互換性を維持し、M1では24bitデータアクセス、M2では24bitネイティブ実行を段階的に追加する。
