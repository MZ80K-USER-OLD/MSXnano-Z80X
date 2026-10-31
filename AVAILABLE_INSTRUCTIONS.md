# 使用可能な命令一覧

この一覧は、MSX T80 24bit 拡張仕様書に基づく、現在の構成で使用可能または想定される 24bit 拡張命令のまとめです。

> **V16.1段階移行中**: 新RST.LとJP.M2移設、IBRの読書きまで反映済み。
> IRQ/NMIのIBR統合、IM2テーブル読出し、SYSCALLも反映済み。
> 新RTLの配置配線・実機再確認は未実施です。M2割込みにはIBR内の4byteフレーム対応ハンドラが必要です。
> `ED9B LD24 IVR,HL`と旧RST.Lは廃止。旧IRQ/NMI試験と旧COMの互換性について
> [移行検証記録](verification_data/v161_rst_l/README.md)を参照してください。以下のPhase13記録は旧版の履歴です。
>
> 新RST.L/IBR/SYSCALLは[V161TEST](hardware_test/V161Test/README.md)で
> 2026-10-25に実機 `PASS=1A FAIL=00`（ユーザー報告）。
> 新M2 IRQ/RETI.L用は[I161TEST](hardware_test/V161IRQTest/README.md)を使用し、
> 実機結果はまだ未取得です。NMI・RETI外部通知は同COMの対象外です。
> TEST/TEST24、IX/IY 24bit演算・PUSH24/POP24、WTOCラップ検出、M2のMSP24スタック命令は[M2SPTEST](hardware_test/M2SPTest/README.md)で実機確認できます。
> 現時点ではCOMシミュレーションPASS、実機結果は未取得です。

> 参考: [README.md](README.md) からリンクされています。
> 現行仕様は [MSX_T80_24bit化_CPU統合仕様書_V17](doc/jpn/MSX_T80_24bit化_CPU統合仕様書_V17.md) を参照してください。
> V17はIX/IY実効アドレス共有化と実機検証結果を反映し、opcode割り当ては変更しません。
> 命令一覧CSVは [MSX_T80_24bit化_拡張命令一覧_V17](doc/jpn/MSX_T80_24bit化_拡張命令一覧_V17.csv) を参照してください。V16.1のopcode割り当てを継承しています。旧V5仕様に基づく暫定opcodeの記載は廃止しました。
> 実装状態は、以下の基準で整理しています。
> - 実装済み: 現在のプロジェクト内（[t80.vhd](fpga/G80A/t80.vhd)）で対応が確認できている命令
> - 未実装: V8/V7で確定しているが、現時点で未対応の命令

---

## 1. モード制御

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 90` | `SET_M0` | 完全 Z80 互換モードへ移行 | 実装済み（HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成と連動。PC/SPアドレス生成はM0では元々plain 16bitのまま） |
| `ED 91` | `SET_M1` | データアクセス拡張モードへ移行 | 実装済み（HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成と連動。PC/SPアドレス生成はM1では元々plain 16bitのまま、CPU仕様書V8どおり） |
| `ED 92` | `SET_M2` | 24bit ネイティブ動作モードへ移行 | 実装済み（Phase10。HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成に加え、PC24命令フェッチとMSP24アクティブスタックポインタとも連動。M0/M1→M2遷移時は`PC_B`(`bank_pc_r`)を00hへリセットし、M2→M2（再実行）では保持。詳細は下記「8. M2基本動作」参照） |
| `ED 93` | `JP.M0 addr16` | M0へモード遷移ジャンプ | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |
| `ED 94` | `JP.M1 addr16` | M1へモード遷移ジャンプ | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |
| `ED 9B` | `JP.M2 addr24` | M2へモード遷移ジャンプ | V16.1へ移設済み。2026-10-24、新P12TESTも実機PASS=08 FAIL=00（ユーザー報告） |
| `ED 96` | `CALL.M0 addr16` | M0へモード遷移コール | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |
| `ED 97` | `CALL.M1 addr16` | M1へモード遷移コール | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |
| `ED 98` | `CALL.M2 addr24` | M2へモード遷移コール | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |
| `ED 99` | `RET.M` | モード遷移フレームからの復帰 | 実装済み（Phase12。詳細は下記「10. モード間制御」参照） |

---

## 2. バンクレジスタ

既存16bitレジスタに付随する単純な8bit bankバイト。全モードで直接LD可能（F不変）。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 04` | `LD BC_B, A` | BC バンクレジスタへ書き込み | 実装済み |
| `ED 0C` | `LD A, BC_B` | BC バンクレジスタ読み出し | 実装済み |
| `ED 14` | `LD DE_B, A` | DE バンクレジスタへ書き込み | 実装済み |
| `ED 1C` | `LD A, DE_B` | DE バンクレジスタ読み出し | 実装済み |
| `ED 24` | `LD HL_B, A` | HL バンクレジスタへ書き込み | 実装済み |
| `ED 2C` | `LD A, HL_B` | HL バンクレジスタ読み出し | 実装済み |
| `ED 05` | `LD IX_B, A` | IX バンクレジスタへ書き込み | 実装済み |
| `ED 0D` | `LD A, IX_B` | IX バンクレジスタ読み出し | 実装済み |
| `ED 15` | `LD IY_B, A` | IY バンクレジスタへ書き込み | 実装済み |
| `ED 1D` | `LD A, IY_B` | IY バンクレジスタ読み出し | 実装済み |
| `ED 3A` | `LD IBR, A` | RST.L・M2 IRQ/NMI・SYSCALL共通のバンク設定 | 実装済み |
| `ED EF` | `LD A, IBR` | IBR読み出し | 実装済み。旧ED 3EはNOP |

> `MSP24`/`IVR24`は単純な8bit bankレジスタではなく、フル24bitレジスタとして定義されています（下記「3. 24bit転送」「4. 割込ベクタ」参照）。NVR24はV16.1で廃止しました。`PC_B`も直接LDする命令は無く、`SET_M2`/`CALL.M2`等のモード遷移命令が自動的に設定します。

---

## 3. 24bit転送（HL24 hub / MSP）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 06` | `LD24 HL, BC` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 0E` | `LD24 BC, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 16` | `LD24 HL, DE` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 1E` | `LD24 DE, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `DD ED 26` | `LD24 HL, IX` | full 24bit、F不変 | 未実装（DD/ED二重プレフィクスの命令デコード拡張が必要、次増分予定） |
| `DD ED 2E` | `LD24 IX, HL` | full 24bit、F不変 | 未実装（同上） |
| `FD ED 26` | `LD24 HL, IY` | full 24bit、F不変 | 未実装（同上） |
| `FD ED 2E` | `LD24 IY, HL` | full 24bit、F不変 | 未実装（同上） |
| `ED 34 bl bh bn` | `LD24 MSP, imm24` | F/W不変 | 実装済み（M1/M2、M0では1byte NOP。GHDL検証済み、実機未検証） |
| `ED 35` | `LD24 MSP, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 36` | `LD24 HL, MSP` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |

> Phase7（[MSX_T80_24bit化_実装手順_V2](doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md)セクション9）のうち、上記テーブルで「実装済み」の6命令（HL24⇔BC24/DE24、HL24⇔MSP24）は、単一ED prefixで完結するレジスタ間24bitコピー命令として実装済みです。[t80.vhd](fpga/G80A/t80.vhd)内の既存のパイプライン化されたレジスタアドレス生成機構（`RegAddrA_r`/`RegAddrB_r`）への条件追加のみで実装しており、t80_mcode.vhdやレジスタファイルの共有多分岐ロジックへの変更は一切ありません。GHDLテストベンチ（[tb_phase7_ld24.vhd](fpga/G80A/test/tb_phase7_ld24.vhd)）で、宛先の24bit値・ソース不変・F不変を検証済みです。
> IX/IY hub転送（DD/FD ED26/2E）とIVR即値ロード（ED9A/9D）は未実装です。MSP即値ロード（ED34）は実装済みです。

---

## 4. 割込ベクタ（IVR24）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 9A bl bh bn` | `LD24 IVR, imm24` | F不変 | 未実装（3byte即値フェッチのMCycleシーケンス拡張が必要、次増分予定） |
| 旧`ED 9B` | `LD24 IVR, HL` | 廃止 | 現在はJP.M2。旧バイナリを実行しない |
| `ED 9C` | `LD24 HL, IVR` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 9E/9F` | RESERVED | NVR廃止により転送命令を削除 | NOP扱い |

> `IVR`の16bit低位ワードは、Phase7実装に伴い追加した[t80.vhd](fpga/G80A/t80.vhd)内部レジスタです。NVR24および`bank_nvr_r`は削除しました。MSP24/IVR24のリセット値は`000000h`です。

---

## 5. 24bit ALU

専用24bit ALUを使用。DD/FDプレフィクスでHL targetをIX/IYへ置換。SUB24は設けずC=0のSBC24を使う。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 23` / `DD/FD ED 23` | `INC24 HL/IX/IY` | 24bitで+1 | 実装済み（GHDL検証済み） |
| `ED 2B` / `DD/FD ED 2B` | `DEC24 HL/IX/IY` | 24bitで-1 | 実装済み（GHDL検証済み） |
| `ED 09/19/29/39` / `DD/FD ED`同opcode | `ADD24 HL/IX/IY, BC/DE/HL(or IX/IY)/SP` | 24bit加算 | 実装済み（SP operandはMSP24） |
| `ED 07/17/27/37` / `DD/FD ED`同opcode | `ADC24 HL/IX/IY, BC/DE/HL(or IX/IY)/SP` | 24bit桁上げ加算 | 実装済み |
| `ED 0F/1F/2F/3F` / `DD/FD ED`同opcode | `SBC24 HL/IX/IY, BC/DE/HL(or IX/IY)/SP` | 24bit桁借り減算 | 実装済み。SUB24はC=0のSBC24で実行 |
| `ED 3D` | `CP24 HL, DE` | 24bit比較（writebackなし） | 実装済み（HL targetのみ） |

- 実装は[t80.vhd](fpga/G80A/t80.vhd)内の専用の組合せ論理プロセスと、[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Alu24_AddSub`関数（t80_alu.vhdの既存8bit ALUとは完全に独立）で構成されており、Phase7と同様にT80コア共通部分（`t80_mcode.vhd`やレジスタファイルのメインデコード経路）には一切手を加えていません。
- フラグ: `S`=bit23、`Z`=24bit zero、`H`は変更なし（保持）、`P/V`=24bit符号付きオーバーフロー、`N`=加算系命令で0・減算系命令で1、`C`=24bit carry/borrow。未定義のX/Y（bit3/5）フラグも同様にこの命令群では変更されません（CPU仕様書V8はこれらを規定していないため、保持する設計としています）。
- `CP24`は書き込みを行わず、フラグのみを更新します（HL24は変更されません）。
- DD/FD付きではIX/IYを演算targetとし、pairコードHLも同じIX/IYを参照します。CP24は現時点でHL targetのみです。
- GHDLテストベンチ: [tb_phase8_alu24.vhd](fpga/G80A/test/tb_phase8_alu24.vhd)（全9ケース、符号付きオーバーフロー・24bit carry/borrow・H保持・MSP24オペランド・CP24の非書き込みを含めて検証済み）。
- IX/IY targetの代表命令、W境界更新/WTOC、MSP即値ロード、IX/IYのPUSH24/POP24は[V16.1 opcode regression](fpga/G80A/test/tb_v161_opcode_extensions.vhd)でGHDL検証済み（実機未検証）。

---

## 5.1 16bit 境界フラグと WTOC

M1/M2の16bit `INC/DEC BC,DE,HL,IX,IY`は、16bit境界を跨ぐときF.bit5（Y）を更新します。`WTOC`（`ED FE`）はYをCへコピーし、その他のFビットを保持します。SP/MSPとM0は対象外です。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED FE` | `WTOC` | F.YをF.Cへコピー | 実装済み（GHDL検証済み、実機未検証） |

---

## 5.2 TEST / TEST24

対象レジスタが0かを判定し、Zだけ更新します（ゼロならZ=1、非ゼロならZ=0）。その他のFビットは保持し、SP/MSPは対象外です。M1/M2で実行し、M0ではNOPとして扱います。全10 opcode形式を[`tb_v161_test_m2_sp.vhd`](fpga/G80A/test/tb_v161_test_m2_sp.vhd)でゼロ/非ゼロ双方についてGHDL検証済みです。実機では[M2SPTEST.COM](hardware_test/M2SPTest/README.md)を使用してください（期待値`PASS=2B FAIL=00`、実機結果は未取得）。

| Opcode | 命令 |
|---|---|
| `ED D3/D6/D9/DB/DD` | `TEST BC/DE/HL/IX/IY`（16bit） |
| `ED DE/DF/F5/F6/F7` | `TEST24 BC/DE/HL/IX/IY` |

---

## 6. Indexed転送

### V15第1段階: 16bit indexed LD

M1/M2で`DD/FD 07/17/27 d`がBC/DE/HLへの読出し、
`DD/FD 0F/1F/2F d`が書込み。符号付き変位をIX24/IY24へ加え、
2byteを低位から転送する。ペアのbank byte、IX/IY、Fは保持する。
M0は既存Z80のプレフィクス無視動作を維持し、変位を追加消費しない。
RTL実装とGHDL検証を追加した。2026-10-24、M1実機でINDEX16.COMの全24判定PASSを報告。
2026-10-24、M2実機でもI16M2.COMの全24判定PASS（`PASS=18 FAIL=00`）を報告。
バンク命令のコード移設・RST/IBRは今回の変更対象外。

検証データ・実測結果の形式と実行方法は
[verification_data/v15_index16](verification_data/v15_index16/README.md)を参照。

### V15第2段階: 24bit indexed LD

M1/M2で`DD/FD 08/10/18 d`がBC24/DE24/HL24への読出し、
`DD/FD 20/28/30 d`が書込み。符号付き変位をIX24/IY24へ加え、
LOW/HIGH/BANKの順に3byte転送する。IX/IY、対象外のペア、Fは保持する。
M0は元のZ80命令として動作し、indexed用の変位を追加消費しない。
16bit版の経路を再利用し、3byte目のバンク転送とポインタ更新を追加した。
2026-10-24、M1実機でINDEX24.COMの全24判定PASS（`PASS=18 FAIL=00`）を報告。
2026-10-24、M2実機でもI24M2.COMの全24判定PASS（`PASS=18 FAIL=00`）を報告。

[RTL検証データ](verification_data/v15_index24/README.md)、
[実機用INDEX24.COM](hardware_test/Index24Test/README.md)を参照。

以下の表は旧版の割当て案であり、V15の現行indexed LDとは別である。
旧`DD/FD ED80〜8B`を互換別名として実装したものではない。

| オペコード | 命令 | 状態 |
|---|---|---|
| `DD/FD ED 80` | `LD16 BC, (IX/IY+d)` | 未実装 |
| `DD/FD ED 81` | `LD16 DE, (IX/IY+d)` | 未実装 |
| `DD/FD ED 82` | `LD16 HL, (IX/IY+d)` | 未実装 |
| `DD/FD ED 83` | `LD16 (IX/IY+d), BC` | 未実装 |
| `DD/FD ED 84` | `LD16 (IX/IY+d), DE` | 未実装 |
| `DD/FD ED 85` | `LD16 (IX/IY+d), HL` | 未実装 |
| `DD/FD ED 86` | `LD24 BC, (IX/IY+d)` | 未実装 |
| `DD/FD ED 87` | `LD24 DE, (IX/IY+d)` | 未実装 |
| `DD/FD ED 88` | `LD24 HL, (IX/IY+d)` | 未実装 |
| `DD/FD ED 89` | `LD24 (IX/IY+d), BC` | 未実装 |
| `DD/FD ED 8A` | `LD24 (IX/IY+d), DE` | 未実装 |
| `DD/FD ED 8B` | `LD24 (IX/IY+d), HL` | 未実装 |

### 6.1 LEA.L（V4仕様書21.2で新規追加、PEA.Lは不採用）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `DD/FD ED 68 d` | `LEA.L HL,(IX/IY+d)` | 実効アドレスをHL24へロード（メモリアクセス無し） | 実装済み（GHDL検証済み、実機未検証） |
| `DD/FD ED 69 d` | `LEA.L DE,(IX/IY+d)` | 実効アドレスをDE24へロード（メモリアクセス無し） | 実装済み（GHDL検証済み、実機未検証） |
| `DD/FD ED 6A d` | (PEA.L、不採用) | デコードしない | 未定義命令としてNOP扱い（意図的） |

`IX/IY + sign_extend(d)`を計算し、結果をHL24/DE24の全24bitへロードする
（実効アドレスへの実際のメモリアクセスは発生しない）。M0では16bit wrap
かつbankは強制的に00h、M1/M2では24bit wrap（bank境界のcarry/borrowを
含む）。F・IX/IY・SP/MSPは不変。

`LeaXY`はLEA.Lで導入したDD/FD+ED二重プレフィクス用のラッチで、現在は
24bit ALUとPUSH24/POP24 IX/IYにも利用する。`DD/FD ED 26/2E`
（IX/IY hub転送）は引き続き未実装。

- **実装方式**: 既存の`XY_State`（DD/FD+CB用）とは完全に独立した新規
  ラッチ信号`LeaXY`（[t80.vhd](fpga/G80A/t80.vhd)）を新設。EDプレフィクス
  認識時、`XY_State`自体は**従来どおり**無条件に`"00"`へリセットする
  （この挙動を変更すると、既存の全ED系拡張命令が暗黙に依存している
  `XY_State="00"`ガード、および`RegAddrA_r`/`RegAddrB_r`の
  "H/L→IX/IY"リダイレクト機構と衝突するリスクがあったため、Phase8の
  コメントで既に指摘されていたこのリスクを避けるため、既存シグナルには
  触れず新規シグナルを追加する設計とした）。`LeaXY`はリセット**直前**の
  `XY_State`値を捕捉するため、DD/FDが直前にあったかどうかを安全に後から
  判定できる。
- **オペコード再利用**: `ED 68`/`ED 69`は元々標準Z80の`IN L,(C)`/
  `OUT (C),L`。`LeaXY/="00"`（DD/FD直後）のときだけLEA.Lとして分岐し、
  `LeaXY="00"`（DD/FD無し、単独ED）のときは従来どおり`IN r,(C)`/
  `OUT (C),r`として動作する（[t80_mcode.vhd](fpga/G80A/t80_mcode.vhd)の
  該当ディスパッチ内でif分岐、既存のIN/OUT処理コード自体は無変更）。
- **3 MCycle構成**: M1(opcode、DD/FD+ED+68/69)、M2(変位dフェッチ+実効
  アドレス計算、既存の(IX+d)と同じ`Addr24_AddDisp8`関数を再利用)、
  M3(HL24/DE24・bankバイトへの書込み、Phase7のHL24 hub転送と同じ
  `RegAddrA_r`/`RegWEH`/`RegWEL`/`RegDIH`/`RegDIL`機構を再利用)。
- GHDLテストベンチ: [tb_lea_l.vhd](fpga/G80A/test/tb_lea_l.vhd)（M0での
  bank強制00h、M1/M2でのbank carry/borrow、FFFFFF+1の24bit全体wrap、
  d=±128相当の極値、IX/IY・F不変、および**裸の`ED 68`/`ED 69`
  （`IN r,(C)`/`OUT (C),r`）が一切影響を受けないことの回帰確認**を含め
  全8ケース検証済み）。

---

## 7. 24bit Stack（PUSH24 / POP24）

対象はBC24/DE24/HL24/IX24/IY24のみ（AFは対象外）。MSPを使用し3byte転送。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED C5` / `C1` | `PUSH24` / `POP24 BC` | 実装済み（GHDL検証済み、実機確認済み。ただし単一物理bank内でのみ。下記「既知の問題」参照） |
| `ED D5` / `D1` | `PUSH24` / `POP24 DE` | 実装済み（同上） |
| `ED E5` / `E1` | `PUSH24` / `POP24 HL` | 実装済み（同上） |
| `DD ED E5` / `E1` | `PUSH24` / `POP24 IX` | 実装済み（GHDL検証済み。M2、F/W不変） |
| `FD ED E5` / `E1` | `PUSH24` / `POP24 IY` | 実装済み（同上） |

- PUSH24はMSP24（`bank_msp_r`+`MSP`、Phase7で新設）を1ずつ3回デクリメントしながらBANK→HIGH→LOWの順でメモリへ書き込み、POP24は逆にLOW→HIGH→BANKの順で読み出しながら1ずつ3回インクリメントします。最終的なMSP24はPUSH24で-3、POP24で+3となり、互いに逆操作として往復が可能です。
- バンクバイトとの繰り上がり/繰り下がりは[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Dec`/`Addr24_Inc`（Phase2で追加、Phase9向けに既に用意されていたもの）を使って計算されるため、16bitワードの境界（0000h⇔FFFFh）をまたぐ際にバンクバイトも正しく繰り上がり/繰り下がりします。
- LOW/HIGH byteの読み書きは、既存のBC/DE/HLレジスタファイル書き込み機構（`Read_To_Reg`/`Set_BusA_To`、`Set_BusB_To`経由のBusB staging）をそのまま再利用しており、通常のPUSH qq/POP qqと全く同じ仕組みです。BANK byteのみ、レジスタファイル外の`bank_bc_r`/`bank_de_r`/`bank_hl_r`信号を対象とするため、[t80.vhd](fpga/G80A/t80.vhd)内で直接の書き込み（PUSH側はDOへの直接上書き、POP側は`DI_Reg`からの直接キャプチャ）として実装されています。アドレス生成には新規の`Set_Addr_To`値`aMSP`（従来未使用だった`"011"`を割り当て）を追加しましたが、既存の`aSP`/`aBC`/`aDE`等の経路には一切手を加えていません。
- フラグ（F）は変更されません（Z80標準のPUSH/POPと同様）。
- GHDLテストベンチ: [tb_phase9_push24_pop24.vhd](fpga/G80A/test/tb_phase9_push24_pop24.vhd)（PUSH24→POP24の往復、バンク境界またぎ時の繰り下がり、F不変を含めて検証済み）。

### 既知の問題: bank境界をまたぐPUSH24/POP24で実機フリーズを確認（未解決）

1回のPUSH24/POP24呼出しの中で物理bankが変化するシナリオ（例:
MSP24=02:0001hからPUSH24を実行し、3回のデクリメントで
02:0001→02:0000→01:FFFF（bank繰り下がり）→01:FFFEとbankをまたぐ）を
[hardware_test/Push24Test](hardware_test/Push24Test)で実機検証したところ、
**先行するTest5完了直後にシステムがフリーズする現象を確認しました**
（画面にプログラム起動時のバナーが再表示された後、応答不能に。PCが暴走し
プログラム先頭付近へ飛んだ可能性が高い）。GHDLシミュレーション
（`tb_phase9_push24_pop24.vhd`）では同じシナリオが問題なくPASSしているため、
実機固有の問題と判断されます。

原因として、1命令内で連続する3回のメモリアクセス（BANK/HIGH/LOW
byte）がそれぞれ異なる物理bankへルーティングされる経路が、Phase3/5で
検証済みの既存拡張メモリアクセス（`(HL)`/`(BC)`/`(DE)`/`(IX+d)`。いずれも
1命令につき拡張アクセスは1回のみ）では一度も検証されていなかったこと、
および本プロジェクトのSD-RAMコントローラ（[memory.v](fpga/src/memory.v)・
sdram.v）にはCPU側へのWAIT状態生成機構が存在しない（[top.v](fpga/top.v)の
`ex_bus_wait_n`は常時`1'b1`固定）ため、bank切替にコントローラ側の処理が
間に合わずアドレス生成が一時的に乱れ、意図しない領域（bank00h＝実行中
プログラム自身の空間や、BIOS/割込みベクタ等）を破壊した可能性が疑われます。

根本原因の特定には[memory.v](fpga/src/memory.v)・sdram.vのSD-RAMタイミング
のより詳細な調査が必要で、**現時点では未解決**です。[hardware_test/Push24Test](hardware_test/Push24Test)
の実機テストプログラムは、この問題が判明した時点でbank境界をまたぐ
シナリオを削除し、常に単一物理bank内で完結するテストのみに修正済みです。
PUSH24/POP24を単一物理bank内で使う限りは実機で正常動作を確認済みですが、
bank境界をまたぐ使用は本問題が解決されるまで避けてください。

---

## 8. M2基本動作（PC24フェッチ / MSPアクティブスタック）

CPU仕様書V8セクション2「MODE」が定義するM2モード（`PC: 24bit`、`Active stack: MSP24`）の基本動作。新規opcodeの追加ではなく、既存のT80共有機構（PC自動インクリメント、`aSP`アドレス生成、SP用`IncDec_16`機構）がM2実行時にのみ条件分岐で経路を切り替える形で実装されています。

| 項目 | 内容 | 状態 |
|---|---|---|
| PC24命令フェッチ | M2では`PC24={bank_pc_r,PC}`として、通常の命令フェッチ（オペコードbyte・オペランドbyteの自動インクリメント）が[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Inc`経由で24bit演算になり、PCが0xFFFF→0x0000をまたぐ際に`bank_pc_r`が正しく繰り上がる | 実装済み（GHDL検証済み、実機未検証） |
| `SET_M2`のPC_B挙動 | M0/M1→M2遷移時は`bank_pc_r`を00hへリセットし、M2→M2（既にM2の状態での再実行）では`bank_pc_r`を保持（CPU仕様書V8「SET_M2はM0/M1→M2でPC_B<-00h、M2→M2ではPC_B保持」） | 実装済み（GHDL検証済み、実機未検証） |
| MSP24アクティブスタック | M2では、既存のZ80標準`PUSH qq`/`POP qq`/`EX (SP),HL/IX/IY`/`CALL`/`CALL cc`/`RET`/`RET cc`/`RST p`が、通常のSPではなくMSP24（`bank_msp_r`+`MSP`）を使うようになる。転送byte数は2byteのまま（bank byte自体はPUSH24/POP24と異なりdataとして転送されない）で、MSP24自体は[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Dec`/`Addr24_Inc`で64KB境界をまたいで正しく繰り上がり/繰り下がりする | 実装済み（GHDL検証済み、実機未検証） |
| `INC SP`/`DEC SP` | M2ではSP16を変更せず、MSP24を24bitで増減する。M0/M1ではSP16を従来どおり変更する | 実装済み（新規テストで境界またぎをGHDL検証、実機未検証） |
| `LD SP,HL`/`LD SP,IX/IY` | M2ではソースの24bit値（word+bank）をMSP24へ転送する。M0/M1ではSP16へwordを転送する | 実装済み（新規テストでHL/IXのbank転送をGHDL検証、実機未検証） |

- `INC SP`/`DEC SP`は既存のSP用`IncDec_16(2 downto 0)="111"`経路でM2時にMSP24を更新します。スタックメモリアクセスは`aSP`経路を使い、MSP24を参照します。`LD SP,HL/IX/IY`もM2時にMSPのwordとbankを書き換えます。
- 既存のZ80標準`SP`レジスタ自体はM2実行中も一切変更されません（GHDLテストベンチで`ADD HL,SP`トリックを使い、M2でのPUSH/POP前後でSPが完全に不変であることを確認済み）。
- 以下はPhase10時点の制約ではなく、後続変更も含めて命令別に参照してください。特に通常CALL/RETおよびV16.1の通常RSTはM2でPC_Bを維持します。通常RSTの最新検証は[通常RST検証記録](verification_data/v161_rst/README.md)を参照してください。
- 新規追加した割込み関連opcode(`DD/FD ED26/2E`相当の二重プレフィクス、JP.L/CALL.L/RET.L等)は本フェーズの対象外です。M2割込み（IRQ/NMIともIBRを使用、4byte MSP frame）はPhase13の範囲です。
- GHDLテストベンチ: [tb_phase10_m2_basic.vhd](fpga/G80A/test/tb_phase10_m2_basic.vhd)（SET_M2のPC_Bリセット/保持、PC24の64KB境界またぎ時の繰り上がり、MSP24を使った通常PUSH/POPの2byte転送とSP不変を検証済み）。

---

## 9. 24bit制御（JR.L / JP.L / CALL.L / RET.L）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 18` | `JR.L e16` | M2=PC24相対、M0/M1=PC16相対 | 実装済み（GHDL検証済み。詳細は下記「9.3 JR.L」参照） |
| `ED 20` / `28` | `JR.L NZ/Z, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED 30` / `38` | `JR.L NC/C, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED A7` / `AF` | `JR.L PO/PE, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED B7` / `BF` | `JR.L P/M, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED C3` | `JP.L addr24` | 24bit無条件ジャンプ | 実装済み（GHDL検証済み。M2ではbank_pcへ即値のbankバイトを反映、M0/M1では3byte目は読み捨てbank00h扱い。詳細は下記「9.1 JP.L」参照） |
| `ED C2/CA/D2/DA/E2/EA/F2/FA` | `JP.L cc, addr24` | 条件付き24bitジャンプ | 実装済み（GHDL検証済み。条件不成立時も3byteのアドレスは読み飛ばし、bank_pcは変化しない） |
| `ED CD` | `CALL.L addr24` | MSPへPC24を3byte保存（M2専用） | 実装済み（GHDL検証済み。M2ではbank_pcへ即値のbankバイトを反映、M0/M1では3byte目は読み捨てbank_pc不変。詳細は下記「9.2 CALL.L/RET.L」参照） |
| `ED C4/CC/D4/DC/E4/EC/F4/FC` | `CALL.L cc, addr24` | 条件付きfar call（M2専用） | 実装済み（GHDL検証済み。M0/M1での挙動はCALL.L addr24と同じ） |
| `ED C9` | `RET.L` | MSPからPC24復元（M2専用） | 実装済み（GHDL検証済み。M2ではbank_pcへpopしたbankバイトを反映、M0/M1ではpopしたbankバイトを読み捨てbank_pc不変。詳細は下記「9.2 CALL.L/RET.L」参照） |
| `ED C0/C8/D0/D8/E0/E8/F0/F8` | `RET.L cc` | 条件付きfar return（M2専用） | 実装済み（GHDL検証済み。M0/M1での挙動はRET.Lと同じ） |

### 9.1 JP.L / JP.L cc 実装メモ（Phase11着手）

`JP.L`/`JP.L cc`は、Phase11「M2制御フロー」のうちスタック(MSP)を使わない
最もシンプルな部分として先行実装した。

- 命令長はED prefix込みで5byte固定（`ED xx + lo + hi + bank`）。条件が
  不成立の場合も、実機Z80の`JP cc,nn`と同様に3byteのアドレスは最後まで
  読み進める（ジャンプしないだけで命令長は変わらない）。
- `ED C3`は、このプロジェクトでは常にMode=0（Z80相当）固定でビルドして
  おりR800拡張（MULUW/MULUB）には到達しないため、元々未使用だった
  R800 MULUWのopcodeスロットを転用した（`ED F3`はMULUWプレースホルダの
  ままで変更していない）。
- **M2でのみ本来の24bitジャンプとして機能する**: `mode24=M2`のとき、
  読み込んだ3byte目（bankバイト）がそのまま`bank_pc`（PC24の物理バンク
  レジスタ）に反映され、真の24bit far jumpとして動作する。
- **M0/M1では3byte目は読み捨てられ、常にbank00h扱いになる**（CALL.L/
  RET.LのM2専用制限と同じ考え方）。これは意図的な設計判断であり、
  Phase10で`bank_pc`はM2のときしか命令フェッチに参照されないため、
  M0/M1でbank_pcへ非ゼロ値を書き込んでも「ジャンプ直後の1回だけ正しい
  バンクが見えて、以降のフェッチでは静かにbank00hへ戻ってしまう」
  という不整合（"zombie bank_pc"）を避けるため。
- GHDLテストベンチ: [tb_phase11_jpl.vhd](fpga/G80A/test/tb_phase11_jpl.vhd)
  （M2での無条件/条件付き（成立・不成立）ジャンプ、M0でのbankバイト
  読み捨てを検証済み）。
- 未実装: `JR.L`（相対ジャンプ、PC24全体にsigned変位を加算）は、本
  セクション表のとおり引き続きPhase11のTODOとして残っている。

### 9.2 CALL.L / RET.L 実装メモ（Phase11）

`CALL.L addr24`/`CALL.L cc,addr24`/`RET.L`/`RET.L cc`は、Phase9の
PUSH24/POP24と同じ「MSP24へ3byte転送」の仕組みを流用し、PC24の
far call/returnとして実装した。

- **フレーム構成**: `CALL.L`はMSP24へ`bank_pc_r`(戻り先bank)→`PC_H`→
  `PC_L`の順に3byte push（decrementしながら書き込み、最終的にMSP24は
  LOWバイトを指す）。`RET.L`はLOW→HIGH→BANKの順に3byte pop（incrementし
  ながら読み込み）し、`PC24={BANK,HIGH,LOW}`へジャンプする。書き込み/
  読み込み順序・MSP24の増減タイミングはPhase9のPUSH24/POP24と完全に
  同じパターン（decrement-before-write / increment-after-read）。
- **条件付き版の中断動作**: `CALL.L cc`は条件不成立時、実機Z80の
  `CALL cc,nn`と同様に3byteのアドレスは最後まで読み進めるが、MSP24へは
  一切触れない（push phaseへ進まない）。`RET.L cc`は条件不成立時、
  即座に中断し（opcodeフェッチのみ）、MSP24は一切変化しない。
- **M2専用ガード（追補）**: 当初実装では`CALL.L`/`RET.L`はモードに
  関わらず常に読み込んだ/popしたbankバイトを`bank_pc`へ適用していたが、
  これは`JP.L`/`JR.L`が共にM2のときだけ本来の24bit動作をする（M0/M1
  では"degrade"する）という設計方針と食い違っていたため、追補修正した。
  現在は`JP.L`/`JR.L`と同じく`mode24=M2`のときだけ`bank_pc`へ適用し、
  M0/M1では3byte目（CALL.L側）/popしたbankバイト（RET.L側）を読み
  飛ばす/消費するだけで`bank_pc`は変更しない。ただし「M0/M1での
  degrade後の挙動」は`JP.L`とは異なる: `JP.L`は（普通の`JP nn`と同じ
  「16bit即値→bank00h」ルールに合わせ）bank00hへリセットするのに対し、
  `CALL.L`/`RET.L`はCALL/RETファミリーに属するため、ロードマップの
  「通常CALL/RETは同一64KB segment内用、PC_B=不変」ルール（`Call`/
  `JumpR`分岐と同じ）に合わせ、`bank_pc`を**変更せず保持**する（`JR.L`
  のM0/M1 elseブランチと同じ"preserve"パターン）。3byteの読み込み/
  push・popそのものは常に変わらず行われる（mode非依存の命令長・
  タイミング）。
  [tb_phase11_call_ret_l.vhd](fpga/G80A/test/tb_phase11_call_ret_l.vhd)
  のTest9/Test10で、M0から`CALL.L`/`RET.L`を実行してもbank_pcが変化
  しないこと（わざと異なるbankバイトをpopさせても無視されること）を
  検証済み。
- **既存のED CD/C9 opcodeスロットについて**: `ED CD`は元々未使用
  （NOP扱い）だったスロットを使用。`ED C9`は、JP.Lと同様にこのプロジェ
  クトでは到達しないR800 MULUBのopcodeスロット（`ED D9`とペア）を
  転用し、`ED D9`はMULUBプレースホルダのまま変更していない。
- **通常CALL/RETのbank_pc挙動もPhase11で修正**: ロードマップPhase11の
  「通常CALL/RETは同一64KB segment内用、PC_B=不変」との規定に合わせ、
  既存の（ED prefixを使わない）プレーンな`CALL`/`CALL cc`/`RET`/
  `RET cc`命令についても、M2実行時に`bank_pc`をbank00hへリセットして
  いた旧Phase10の挙動を「`bank_pc`を変更せず保持する」よう修正した
  （RET側は新設の`JumpR`信号で`Jump`と区別し、CALL側は既存の`Call`
  信号のbank_pc_rリセットを単純に削除）。JP/JR/RST等、16bit即値ターゲ
  ットを生成する他の命令は引き続きbank00hへリセットする（CPU仕様書V8
  section 5のルールのまま）。

#### T80コア側で発見・修正した前提条件（既存バグ、Phase11で表面化）

**詳細な技術レポート**:
[T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/doc/jpn/T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md)
（発見経緯・根本原因・修正箇所5箇所の詳細、Phase12で発覚した
`MCycle`幅そのものの上限についてもまとめてある。T80コア保守担当者向け）。

CALL.L/RET.Lの実装過程で、T80コア本体（`fpga/G80A/t80.vhd`・
`fpga/G80A/t80_mcode.vhd`）に存在していた、**DD/FD+CBの二重prefix
継続処理専用のはずのロジックが、`MCycle`の値（110/111=6/7）だけで無条件
に発火してしまう**という前提条件がいくつか見つかった。これらは今まで
「どの命令のMCyclesも6/7に到達しない」という暗黙の前提の上でのみ安全
だった潜在バグで、CALL.L（7 MCycles必要）の追加で初めて表面化した。
すべて`XY_State /= "00"`（DD/FD prefix実行中かどうか）によるガード条件
追加で最小限に修正した（DD/FD+CB自体の動作は変更なし、GHDL回帰
Phase2〜11で確認済み）。

- `t80.vhd`のメイン状態機械: `MCycle="111"`に達すると常に
  `Pre_XY_F_M`から復元する処理が無条件発火 → 新規1bitフラグ
  `XYF_Pending`を追加し、`NextIs_XY_Fetch`経由で来た場合のみ有効化。
- `t80_mcode.vhd`末尾の共通ブロック: `MCycle="110"/"111"`で
  `Inc_PC`/`Set_Addr_To`/`TStates`等を無条件に上書き。
- `t80.vhd`の(IX/IY+d)実効アドレス計算: `TState=3 and MCycle="110"`で
  `TmpAddr`/`TmpBank`を無条件に上書き。
- `t80.vhd`の`XY_Ind`セット、`RegAddrC`選択: いずれも`MCycle="110"`の
  単独条件で無条件発火。
- さらに、CALL.L cc自身の実装バグとして、条件不成立時にも「push phase
  手前の最初のMSP24デクリメント」だけは発火してしまう問題を発見・
  修正（`Set_Addr_To=aMSP`であることを追加の条件としてガード）。

GHDLテストベンチ:
[tb_phase11_call_ret_l.vhd](fpga/G80A/test/tb_phase11_call_ret_l.vhd)
（無条件/条件成立/条件不成立のCALL.L・RET.L双方、複数回の呼び出し
ネストを経てもMSP24が正しく復元されることを検証済み）。

### 9.3 JR.L / JR.L cc 実装メモ（Phase11完了）

`JR.L`/`JR.L cc`は、Phase11「M2制御フロー」の最後のピースとして実装し、
これでPhase11は完了した。

- **16bit符号付き変位**: 実機Z80の`JR e`/`JR cc,e`は8bit符号付き変位
  だが、`JR.L`はED prefix込みで4byte固定（`ED xx + lo + hi`）、16bit
  符号付き変位を使う。M2ではPC24全体（`bank_pc`+PC）に対して
  `Addr24_AddDisp16`（t80_pack.vhd、Phase2から用意されていた関数）で
  24bit演算し、bank境界を正しく跨ぐ（繰り上がり・繰り下がり両方、
  8bitのbankバイト自体の折り返しも含めて検証済み）。
- **M0/M1では従来どおりの16bit wrap**（JP.L同様、bank_pcはM0/M1の
  フェッチで参照されないため、ここでは一切変更しない）。
- **2種類のopcode/条件エンコーディングが混在**: `ED 18/20/28/30/38`は
  実機Z80の`JR e`/`JR NZ,Z,NC,C,e`と全く同じopcodeバイトをそのまま
  ED prefix付きで再利用（条件は実機JRと同じ2bitエンコーディング）。
  `ED A7/AF/B7/BF`は実機JRには存在しないPO/PE/P/M条件用で、偶然にも
  JP.L/CALL.L等と同じ3bit cc（`IR(5:3)`）エンコーディングに一致する
  オペコードバイトが空いていたため採用した。
- **条件不成立時**: 実機Z80の`JR cc,e`と同様、2byteの変位は最後まで
  読み進めるが、ジャンプはしない（タイミングも可変長）。
- GHDLテストベンチ: [tb_phase11_jrl.vhd](fpga/G80A/test/tb_phase11_jrl.vhd)
  （M2での無条件/条件成立/条件不成立、前方/後方双方のbank境界またぎ
  （bankバイト自体の折り返しを含む）、M0での16bit wrap退化を検証済み）。

**Phase11はこれで完了**（JR.L / JP.L / CALL.L / RET.L すべて実装済み）。

---

## 10. モード間制御（JP.Mx / CALL.Mx / RET.M）

Phase12「モード間制御」。`JP.Mx`/`CALL.Mx`は、通常のJP/CALLとは異なり
ジャンプ/コールと同時にモード（M0/M1/M2）自体を切り替える専用命令。
`RET.M`はその対になる復帰命令で、戻り先のモードもフレームから復元する。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 93` | `JP.M0 addr16` | M0へ切替えて16bit addrへジャンプ | 実装済み（GHDL検証済み・実機確認済み） |
| `ED 94` | `JP.M1 addr16` | M1へ切替えて16bit addrへジャンプ | 実装済み（GHDL検証済み・実機確認済み） |
| `ED 9B` | `JP.M2 addr24` | M2へ切替えて24bit addrへジャンプ | V16.1コードへ移設。旧ED 95はRST.L 10H |
| `ED 96` | `CALL.M0 addr16` | M0へ切替えてcall（MSPへ4byte frame保存） | 実装済み（GHDL検証済み・実機確認済み） |
| `ED 97` | `CALL.M1 addr16` | M1へ切替えてcall（MSPへ4byte frame保存） | 実装済み（GHDL検証済み・実機確認済み） |
| `ED 98` | `CALL.M2 addr24` | M2へ切替えてcall（MSPへ4byte frame保存） | 実装済み（GHDL検証済み・実機確認済み。Phase12-2参照） |
| `ED 99` | `RET.M` | MSPから4byte frameを復元しPC24・モード両方を復帰 | 実装済み（GHDL検証済み・実機確認済み） |

### 10.1 実装メモ

- **JP.Mx**: `JP.M0`/`JP.M1`はaddr16（2byte）、`JP.M2`はaddr24（3byte、
  bankバイト込み）をジャンプ先として読み込み、同時に`mode24`
  （モードレジスタ）を強制的に切り替える。`JP.L`と異なり、現在の
  モードに関わらず常にモード切替え・bankバイト適用を行う（`JP.L`は
  既にM2のときだけbankバイトを反映し、モード自体は変更しない）。
  addr16ターゲット（JP.M0/M1）は常にbank00h扱い。
- **CALL.Mx**: ジャンプ先読み込みは`JP.Mx`と同じだが、戻り先として
  MSPへ4byte（`MSP+0=PC_L, MSP+1=PC_H, MSP+2=PC_B, MSP+3=MODE`、
  decrementしながら書き込み）を保存してからモードを切り替える。
  write順序・MSP24増減タイミングはPhase11のCALL.L（3byte版）に
  「MODEバイトを先頭に追加」した形でそのまま拡張。`CALL.M2`は
  addr24（3byteフェッチ）な分だけ全体が1 mcycle後ろへシフトし、
  合計8 MCycleを要する（下記10.2参照）。
- **RET.M**: 4byte（LOW→HIGH→BANK→MODEの順、incrementしながら読み込み）
  をpopし、PC24とモード両方を復元する。他のPhase12命令（JP.Mx/CALL.Mx）
  がモードを固定値へ切り替えるのに対し、RET.Mだけはpopした値から
  モードを復元する点が異なる。CALL.M0/M1/M2のどれが積んだフレームでも
  同じ構造（LOW/HIGH/BANK/MODE）なので、RET.M側に変更は不要。
- GHDLテストベンチ:
  [tb_phase12_mode_control.vhd](fpga/G80A/test/tb_phase12_mode_control.vhd)
  （JP.M0/M1/M2、CALL.M0/M1/M2→RET.Mの往復3回を検証済み。4byte frame
  の内容・MSP24の正しい復元も確認済み）。
- **実機検証済み**: [hardware_test/P12Test](hardware_test/P12Test)のMSX-DOS(2)用
  テストプログラム`P12TEST.COM`で、JP.M0/M1/M2（bank02hへの実行マーカー
  方式を含む）・CALL.M0/M1/M2（RET.Mとの往復、bank02hへの往復を含む）の
  全8チェックが実機（Tang Nano）で2026年10月にPASSしました
  （`PASS=08 FAIL=00`）。これにより、MCycle幅拡張（3bit→4bit）で
  追加実装した`CALL.M2`も含め、Phase12のモード間制御命令群すべてが
  実機で動作することが確認できました。

### 10.2 CALL.M2 addr24の実装（MCycle幅拡張による解決）

**詳細な技術レポート**:
[T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/doc/jpn/T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md)
（「さらに別種の制約」章に経緯の詳細、および追記した解決内容を参照）。

`CALL.M2 addr24`は、addr24ターゲットの読み込み（3byte）と4byte frame
の書き込みを合わせて「1(opcode) + 3(fetch) + 4(push) = 8 MCycles」が
必要だが、当初T80コアの`MCycle`信号は3bit幅（表現できる最大値は7）
だったため実装できず、保留としていた。

その後、ユーザーとの相談の結果、**`MCycle`/`MCycles`信号を3bit→4bit
へ拡張**する方針で解決した。既存の3bitビットリテラル比較・代入
（t80.vhd/t80_mcode.vhdあわせて約150箇所）を機械的に`"0"`始まりの
4bit表記へ置換（VHDLの固定長ビット文字列は長さ不一致があれば
コンパイルエラーになるため、置換漏れは確実に検出できる）。外部
デバッグ監視用の`MC`ポート（3bit、`g80a.vhd`/`T80s.vhd`が参照）は
互換性のため変更せず、`MCycle`下位3bitを切り出して出力する形にした。

この拡張により、CALL.M0/M1と全く同じ構造（decrement-before-write、
MODEバイトをbank_pc_rと同様の直接DOオーバーライドで書き込み）を
1 mcycle後ろへシフトするだけでCALL.M2を実装できた。既存Phase2〜12の
GHDL回帰テストは全てこの拡張後も変更なくパスしており、Gowin合成も
クリーン（BSRAM使用率45/46=98%は変化なし）。

`JP.M2`/`CALL.M0`/`CALL.M1`/`RET.M`はこの拡張以前から実装・検証済み
だったが、拡張後も挙動に変化はない。

---

## 11. RST拡張（RST.L）

`IBR`がRST.L用8bit bankレジスタ（ED 3A書込み、ED EF読出し、RESET=00h）。
M2専用で、return PC24をMSPへ3byte pushし`PC24={IBR,00h,vector}`へ分岐、
RET.Lで復帰する。M0/M1では2byte NOP。MODE、IBR、F、IFFは不変。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED 85` / `8D` | `RST.L 00H` / `08H` | V16.1コードへ移設済み。実機未検証 |
| `ED 95` / `9D` | `RST.L 10H` / `18H` | 同上 |
| `ED A5` / `AD` | `RST.L 20H` / `28H` | 同上 |
| `ED B5` / `BD` | `RST.L 30H` / `38H` | 同上 |

> 通常（ED非前置）の `RST 00H〜38H` はV16.1のM2同一PCバンク分岐へ修正済みです。
> M2ではMSP24にPC16の2byteのみを保存し、通常RETで復帰します。M0/M1は従来どおりです。
> 3バンク分離・96条件/768回の検証は[通常RST検証記録](verification_data/v161_rst/README.md)を参照。
> 旧ED C7/CF/D7/DF/E7/EF/F7/FFはRST.Lとしては廃止。ED EFはIBR読出しです。
> ED E7のDE_B転送への再割当は別段階で、現RTLではNOPです。

### 11.1 実装メモ

- `RstL`は通常RSTと同じ`IR(5:3)`ベクタ計算と既存3byteスタック経路を再利用する。
- M0/M1では分岐もSP/MSP変更も行わない。旧版の通常RSTへのdegradeは廃止した。
- 内部信号名`bank_rst_r`と外部デバッグポート`bank_rst`は互換性のため保持し、現在はIBR値を表す。
- [物理3バンクの新検証](verification_data/v161_rst_l/README.md)が現行版の根拠。
  旧[tb_rst_l.vhd](fpga/G80A/test/tb_rst_l.vhd)と
  [P1314Test](hardware_test/P1314Test)のPASSは旧コード版の履歴であり、現行版の実機検証ではない。

---

## 12. 割り込み（M2拡張）

V16.1の分岐先はすべてIBRを使用する。NVR24は削除済みで、M2 NMIは`{IBR,0066h}`へ分岐する。
M0/M1のIM0/IM1/IM2/NMIは従来経路を維持する。
512条件の物理3バンク検証は[IBR割込み記録](verification_data/v161_interrupt/README.md)を参照。

| 経路 | M2の分岐先・動作 |
|---|---|
| IM1 IRQ | `{IBR,0038h}` |
| IM2 IRQ | `{IBR,I,vector8}`からtarget16を読み、`{IBR,target16}`へ分岐 |
| NMI | `{IBR,0066h}` |
| SYSCALL n | ED C6 n。`{IBR,I,n}`からtarget16を読み、`{IBR,target16}`へ分岐。3byte frame、RET.L復帰 |
| IRQ/NMI frame | MSP24へMODE/PC_B/PC_H/PC_Lの4byte push。下位からPC_L,PC_H,PC_B,MODE |
| RETI.L / RETN.L | ED F3 / ED 8C。4byte復元、RETI.LはIFF不変、RETN.LはIFF1←IFF2 |

IM2はvector8を×2せず、bit0もマスクしない。テーブルの2byteは下位16bitで
ラップし、`IBR:FFFF`の次は同じ`IBR:0000`となる。
IRQはIFF1が有効な場合だけ受付、受付時にIFF1/IFF2をクリアする。
NMIはIFF1だけクリアし、RETN.LでIFF2から復元する。
RETI外部通知の新機構は今回追加・検証していない。
配置配線・実機確認は未実施。旧P1314T/LD24TESTは現RTLと非互換のまま。

SYSCALLはM2専用で、MODE/IBR/IFF/Fは不変。nは×2もbit0マスクもせず使用する。
M0/M1ではユーザー確定方針どおりED C6の2byteだけをNOPとし、次のbyteを通常命令として実行する。
3byteの戻りPC24をMSP24へ保存し、テーブルはIM2と同じ下位16bitラップ規則を使う。
[SYSCALL検証](verification_data/v161_syscall/README.md)を参照。

### 12.0 旧Phase13の履歴（以下の旧分岐先・実機PASSは現行仕様ではない）

Phase13「M2割り込み拡張」（[MSX_T80_24bit化_CPU仕様書_V10](doc/jpn/OLD/MSX_T80_24bit化_CPU仕様書_V10_2026-10-11.md)
section13 "Interrupt"）。M2では、マスク可能割込み（IRQ）・NMIともに
**IStatus（IM0/1/2の設定）に一切関係なく**、それぞれ専用の24bitベクタ
レジスタ（IVR24/NVR24、Phase7で既存）へ直接分岐する。M0/M1は既存の
Z80標準割込み処理（IM0/1/2・固定アドレス0066h）のまま変更なし。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| (opcode無し) | M2 IRQ受付 | IStatusに関係なくIVR24へ直接分岐 | 実装済み（GHDL検証済み、実機検証済み） |
| (opcode無し) | M2 NMI受付 | NVR24へ直接分岐 | 実装済み（GHDL検証済み、実機未検証—実機にはソフトウェアから起動可能なNMIトリガが無いため） |
| `ED F3` | `RETI.L` | M2用4byte frame復元（IFF1/IFF2は変更しない） | V16.1コードへ移設。旧ED 4E版の実機結果は新コードの実機検証とは区別 |
| `ED 8C` | `RETN.L` | M2用4byte frame復元、復元後IFF1←IFF2 | 実装済み（GHDL検証済み。実機では手動構築フレームによる復元スモークテストのみ実施—IFF1←IFF2復元自体はNMI同様の理由で実機未検証） |
| `ED 8E`〜`8F` | RESERVED | NOP | ED 8Dは現在RST.L 08H |

### 12.1 旧実装メモ（履歴）

- **割込みframe構成**: M2での割込み受付時、MSP24を4回decrementしながら
  `MSP+3=MODE, MSP+2=PC_B, MSP+1=PC_H, MSP+0=PC_L`の順（Phase12の
  `CALL.M0/M1/M2`と全く同じ構成・書き込み順序）で4byteを保存する。IRQ
  とNMIで差分はなく、唯一の違いは分岐先（IRQ→IVR24、NMI→NVR24）と、
  受付時のIFF操作（IRQはIFF1=0,IFF2=0。NMIはIFF2のみ維持されIFF1=0に
  なる、既存のZ80標準割込み受付ロジックをそのまま流用）。
- **IStatus非依存の実現方法**: 割込み受付シーケンスの最初（IRを
  強制的に`00000000`へ固定する箇所）で、`mode24_r="10"`（M2）のときは
  IStatus（IM0/1/2）の値を一切参照せず常に同じ分岐へ進むよう、既存の
  `IStatus="01"`（IM1→RST38h相当）判定より手前に新しいガードを追加した。
  これにより、M2中にIM2を設定していても（M0/M1用のベクタテーブル読み
  出し手順を経由せず）IVR24へ直接分岐することを保証している。
- **RETI.L/RETN.L**: いずれもPhase12の`RET.M`（ED 99）と全く同じ
  4byte pop + PC24/モード復元の仕組みをそのまま共用する（ハードウェア
  的には同一のメカニズム、唯一の違いはRETN.Lだけが最終サイクルで
  `IFF1←IFF2`を行う点、既存の標準RETN/RETIミラー群が使う`I_RETN`機構を
  そのまま流用）。
- **V16.1のIM0予防措置**: M0/M1→M2の全MODE変更経路でIM0をIM1へ変換する。
  SET_M2、現行コードのJP.M2/CALL.M2、RET.M/RETI.L/RETN.Lによる復元を含む。
  IM1/IM2は保持し、F/W・IFFはMODE変換処理では変更しない
  （RETN.L自身のIFF復元は従来どおり）。
  M2のIM0命令（ED 46/4E/66/6E）もIM1を設定し、M0/M1へ戻ってもIM1を保持する。
  このためRETI.LをED F3へ移設し、ED 4EはIM0ミラーへ戻した。
  RST.L/JP.M2の移設とIBR割込み統合は後続段階で反映した（上記参照）。
  [専用検証](verification_data/v161_im0/README.md)を参照。
- GHDLテストベンチ:
  [tb_phase13_m2_interrupt.vhd](fpga/G80A/test/tb_phase13_m2_interrupt.vhd)
  （IM2を明示的に設定した状態でのM2 IRQ→IVR24バイパス確認、4byte frame
  の内容・MSP24の正しい復元、RETI.LがIFFを変更しないこと（直後の割込み
  がマスクされたままであること）、RETN.Lが`IFF1←IFF2`を正しく復元する
  こと（直後の割込みが再度受理されること）をEnd-to-endで検証済み）。
- **実機検証済み**: [hardware_test/P1314Test](hardware_test/P1314Test)のMSX-DOS(2)用
  テストプログラム`P1314T.COM`で、実機のVDPフレーム割込み（垂直帰線
  割込み）という本物の非同期ハードウェア割込みを使い、M2のIRQが
  `IVR24`へ直接分岐すること・`RETI.L`がIFF1を復元しないこと（直後の
  割込みがマスクされたままであること）・明示的な`EI`で割込みが再び
  受理されることを含む7チェックが、実機（Tang Nano）で2026年10月に
  PASSしました（`PASS=07 FAIL=00`）。RST.L・M2割込みともに、本物の
  非同期割込みタイミングで実機検証された初めてのケースです。この
  実機検証の過程で、Z80X24拡張とは独立したMSX-DOSプログラミング一般の
  既知の注意点（BIOS ROM内ルーチンはCALSLT経由でなければ直接CALL
  できない、BDOSは副作用として内部でEIを実行し呼出し前の割込み禁止
  状態を保存・復元しない）も発見しており、詳細は
  [hardware_test/P1314Test/README.md](hardware_test/P1314Test/README.md)の
  「開発経緯2/3」を参照のこと。NMI受付とRETN.LのIFF1←IFF2復元自体は、
  実機にソフトウェアから起動可能なNMIトリガが存在しないため、実機
  検証の対象外（GHDL側で厳密に検証済み）。

### 12.2 T80コア側で発見・修正した前提条件（既存バグ、Phase13で表面化）

**詳細な技術レポート**:
[T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/doc/jpn/T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md)
（Phase13分の追記を参照）。

Phase13の実装過程で、T80コア本体（`fpga/G80A/t80.vhd`）の**既存の**
M0/M1向け割込み処理ロジック（IM2のベクタテーブル読み出し、NMIの固定
アドレス0066hジャンプ）が、いずれも`mode24_r`（現在のモード）を一切
確認せず`MCycle`の値だけで無条件に発火する実装になっていたことが
判明した。これはPhase11で発見した「DD/FD+CB専用のはずのMCycle=110/111
無条件発火バグ」と全く同じ種類の前提条件違反で、「M0/M1の割込み処理は
最大5 MCycleしか使わない」という暗黙の前提の上に成り立っていたが、
Phase13の新しいM2割込みエントリ処理（同じく5 MCycle、ただし全く別の
意味）がこれと衝突し、GHDLテストベンチ（あえてIM2を設定してM2の
バイパスを確認する設計にしていた）がこれを検出した。`mode24_r /= "10"`
ガードを2箇所に追加して修正済み（M0/M1自体の動作には影響なし、GHDL
回帰で確認済み）。

---

## 13. 標準 Z80 ブロック転送 / I/O

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED A0` / `A8` | `LDI` / `LDD` | ブロック転送 | 実装済み（Z80 標準） |
| `ED B0` / `B8` | `LDIR` / `LDDR` | 連続ブロック転送 | 実装済み（Z80 標準） |
| `ED 78` / `48` | `IN A, (C)` / `OUT (C), A` | I/O ポートアクセス | 実装済み（Z80 標準） |
| `ED A2` / `A3` | `INI` / `OUTI` | I/O からメモリ転送 | 実装済み（Z80 標準） |
| `ED B2` / `B3` | `INIR` / `OTIR` | 連続 I/O 転送 | 実装済み（Z80 標準） |

---

## 14. バンクマッピング / MMU I/O ポート

**デフォルトビルドの標準仕様（MMUなし）:** 24bit論理アドレスのバンクバイト（A23:A16、`A_Bank`/`cpu_addr24[23:16]`）は、変換テーブルを介さず**そのまま**物理バンクバイトとして使われます（straight-through mapping、[top.v](fpga/top.v)の`assign mmu_physical_bank = cpu_addr24[23:16];`）。論理bank00h（Z80互換空間）は例外的に既存のMSX互換スロット/BIOS/マッパー経路をそのまま使い、常に読み書き可能です。それ以外の論理bank（01h〜1Bh、27バンク）はそのまま同じ値の物理bankとしてSD-RAM拡張メモリ領域（詳細は[SDRAMメモリマップ.md](doc/jpn/SDRAMメモリマップ.md)2.2章）へ直結され、write protectionなしで常に読み書き可能です。F0h/F1h/F2h等のMMU I/Oポートはデフォルトビルドには存在しません。

### 14.1 オプション機能：MMU（論理→物理バンク変換・write protection）

24bit論理アドレスのバンクバイトを物理バンクへ変換するLUT（[mmu24.vhd](fpga/G80A/mmu24.vhd)）を、オプションの追加機能として用意しています。変換そのものは非同期lookupで、追加のWAIT/T-stateは発生しません。**本リポジトリに実装・GHDL検証済みの状態で同梱されていますが、デフォルトビルドの`top.v`からは呼び出されておらず（`MSXNanoTang20K_Z80X24.gprj`でも`enable="0"`）、合成結果には含まれません。** これは、Tang Nano 20K上の現在のFPGA面積配分ではブートROM等の既存IPがBSRAMを全消費しており、MMUの256エントリテーブルがLUTベースの distributed RAMへfallbackしてLUT/Register使用率をそれぞれ約12〜13ポイント押し上げていたためです。BSRAMに余裕のある構成では、`mmu24.vhd`冒頭コメントおよび[top.v](fpga/top.v)の該当コメントの手順に従って再度有効化できます。

| ポート | 名称 | 内容 | 状態 |
|---|---|---|---|
| `F0h` | `MMU_INDEX` | `MMU_DATA`/`MMU_ATTR` が参照するテーブル index（8bit）の読み書き | 実装済み・実機確認済み（有効化していた時点で[top.v](fpga/top.v)にF0h/F1h/F2h I/Oポートとして配線・動作確認。現在はデフォルトビルドでは無効） |
| `F1h` | `MMU_DATA` | `MMU_DATA[MMU_INDEX]`（論理bank→物理bankの変換テーブル1エントリ）の読み書き | 実装済み・実機確認済み（index=00hへの書込みは無視され常に00h固定） |
| `F2h` | `MMU_ATTR` | `MMU_ATTR[MMU_INDEX]`（bit5=W：書込み許可属性。他bitはRESERVED）の読み書き | 実装済み（GHDLシミュレーション確認済み、[tb_phase6_mmu_attr.vhd](fpga/G80A/test/tb_phase6_mmu_attr.vhd)参照。実機未確認） |

- Reset時は全`MMU_DATA`=00hで、論理bank00hは常に物理bank00h（既存MSX互換64KB）へaliasします。`MMU_DATA[00]`は固定で書込みを無視します。
- Reset時は全`MMU_ATTR`=20h（bit5=W=1、書込み許可）です。ソフトウェアが明示的にW=0へ設定するまで、既存の24bit対応コードの挙動は変わりません。
- `F0h`（`MMU_INDEX`）はF0hへの明示的な書込みでのみ変化します。`F1h`/`F2h`へのアクセス（読み書きいずれも）はindexを自動incrementしません。
- `MMU_ATTR`のW=0は、対応する論理bankへの実際の書込み（Write Enable）のみを抑止します。CPU命令自体は正常完了し、例外/trapは発生しません（有効化した場合、`top.v`で`Write_Allow`が`cpu_sdram_write`をゲートします）。
- 論理bank00h（Z80/MSX互換64KB空間）は`MMU_DATA`と同様に`MMU_ATTR`でも例外扱いです。`MMU_ATTR[00h]`への書込みは無視され、bank00hの`Write_Allow`は常に`1`（書込み許可）として扱われます。bank00hは拡張SD-RAM経路自体を使わず既存のMSX互換スロット/マッパー経由でアクセスされるため、常に読み書き可能という不変条件が保たれます。
- 変換結果（物理bank）は有効化した場合、[top.v](fpga/top.v)で実SD-RAM経路（`memory_ctrl`の`cpu_sdram_req`/`cpu_sdram_addr`）に配線されます。ただし物理bank **01h〜1Bh（27バンク、約1.6875MB）のみ**対応しており、これを超える物理bankは未接続（読出しは0xFF、書込みは無視）です。詳細な物理アドレス割り当ては[SDRAMメモリマップ.md](doc/jpn/SDRAMメモリマップ.md)の2.2章を参照してください。
- **Phase5「MMU実機検証」は、MMUが有効だった時点で実機（Tang Nano）で確認済みです**（[hardware_test/MMUTest](hardware_test/MMUTest)のMSX-DOS(2)用テストプログラム`MMUTEST.COM`で、物理bank間の独立性・エイリアス・MMU_DATA[n]=00hの64KB互換aliasを含む全8テストがPASS）。Phase6（`MMU_ATTR.W`）はGHDLシミュレーションで確認済みですが、実機検証は未実施です。MMUTestはMMU_DATA[n]=n（straight-through）設定で動かせば、現在のデフォルト仕様の動作確認にもそのまま使えます。

---

## 15. 回路規模調査：24bitアダー類のGowin合成時共用状況

Phase13完了後、回路規模（LUT/ALU）削減の余地を探るため、[t80.vhd](fpga/G80A/t80.vhd)内に複数箇所存在する24bitアドレス加算（`Addr24_Inc`/`Addr24_Dec`/`Addr24_AddDisp8`/`Addr24_AddDisp16`/`Alu24_AddSub`、[t80_pack.vhd](fpga/G80A/t80_pack.vhd)定義）が、Gowin合成時に自動的に共用化（重複排除）されているかを調査しました。

### 調査手法

合成後のnetlist（`.vg`）は暗号化されており直接解析できず、リソースレポート（`_syn_resource.html`）もサブモジュール単位の粗い集計のみで式単位の内訳が得られないため、**差分実験**で間接的に検証しました。特定の加算呼び出し箇所を一時的に「素通し代入（`bank_x_r & std_logic_vector(X)`、加算なし）」に置き換え、Gowin合成後のLUT/ALU使用量の増減を測定する方法です（実験後は都度元のコードへ復元）。

| 実験 | 対象 | 置換前ベースライン | 置換後 | 差分 | 解釈 |
|---|---|---|---|---|---|
| ① | PC逐次加算（`Addr24_Inc(bank_pc_r, PC)`、命令フェッチ用とオペランドフェッチ用の同一式が2箇所） | 15022 LUT / 1630 ALU | 15073 LUT / 1631 ALU | LUT +51 / ALU +1（≒誤差範囲） | 片方を無効化しても回路規模が減らない → **既に1つの加算器に統合済み**と推定 |
| ② | JR.L相対分岐加算（`Addr24_AddDisp16`、PCの逐次加算とは異なる式） | 同上 | 15157 LUT / 1607 ALU | LUT +135 / ALU **-23** | ALUが明確に減少 → **PC逐次加算とは別の専用回路**であり、共用されていない |
| ③ | MSP24増減算（`Addr24_Dec`×6箇所＋`Addr24_Inc`×4箇所、CALL.Mx/RET.M/割込み等に分散、計10箇所） | 同上 | 14744 LUT / 1631 ALU | LUT **-278** / ALU ±0 | 10箇所の呼び出しを全廃止してもLUT減少はわずかでALUは不変 → 全箇所が既に**Dec用1回路・Inc用1回路（計2回路程度）へ統合済み**と推定（Dec/Inc間の統合はされていない） |

### 結論（ユーザー提起の5項目への回答）

1. **PC24更新**（`Addr24_Inc` vs `Addr24_AddDisp16`）: 同一関数・同一引数の複数呼び出し（フェッチ用逐次加算）はGowinの共通部分式除去（CSE）により**既に自動統合済み**。ただしJR.L用の`Addr24_AddDisp16`は構造が異なる別関数のため**共用されていない**。
2. **MSP24更新**: 通常/拡張スタックの各分岐に散らばる`Addr24_Dec`/`Addr24_Inc`呼び出しは、引数が同一式である限りGowinが自動的に統合済み（実質Dec用・Inc用の2回路）。ただしDecとIncを1つの±1加算器へ統合する、という一段深い手動最適化は行われていない。
3. **24bit ALU**（`Alu24_AddSub`）: 呼び出し箇所は既存セッションで1箇所に手動集約済みのため対象外。
4. **24bitアドレス生成**（IX/IY+d・JR.L・PC・MSP）: これらは関数自体が異なるため、実行タイミングが重ならなくてもGowinは自動共用しない（実験②で確認）。**唯一、手動RTL書き換え（排他的制御による汎用加算器＋オペランド選択セレクタ化）で回路を共用化できる余地がある領域**。なお`Addr24_AddDisp8`（IX/IY+d）は`LEA.L`実装とまったく同一の呼び出し式が2箇所あるため、これも既に自動統合されている可能性が高い。
5. **レジスタ書込み経路**: `RegDIH`/`RegDIL`へのHL24/DE24/LEA.L/ALU24書込みは、単一プロセス内のif/elsif分岐として最初から1系統のみ実装されており、そもそも重複回路が存在しない（整理の余地なし）。

### 今後の方針

上記4.のみ手動統合の余地が残っているが、タイミング・パス再検証（セレクタのmux段が加算のクリティカルパスに乗る可能性）を伴う相応の実装コストがあるため、**本調査では実装は見送り、知見の記録のみとする**（2026年時点の判断）。

### IX/IY実効アドレス加算器の共有化（2026-10-31）

[t80.vhd](fpga/G80A/t80.vhd)の`(IX/IY+d)`と`LEA.L`は、IX/IYのバンクを先に選択し、共通の`RegBusC`下位16bitと合わせて、1個の24bitアドレス加算器へ入力する構成に変更した。
通常のインデックスアクセスでは`XY_State`、`LEA.L`ではEDプリフェクス前の選択を保存した`LeaXY`を使用する。
`d`は符号付き8bit（-128～+127）として既存の`Addr24_AddDisp8`で24bitへ符号拡張する。
下位16bitとバンクは同じ加算結果から取得し、M1/M2のバンクcarry/borrowと24bit wrapを維持する。
M0では従来どおり下位16bitでwrapし、`LEA.L`の結果バンクは00hとする。命令タイミング、フラグ、IX/IY本体の更新有無は変更しない。

Gowin V1.9.12.04の合成後ネットリストで、IX/IY別々の24段ALUチェーンが`index_addr24`の1本へ統合されたことを確認した。
CPU単体の合成集計は4251→4278 LUT（+27）、192→152 ALU（-40）。
全体の配置配線後は17983→17970 Logic（-13）、15759→15789 LUT（+30）、1870→1827 ALU（-43）で、Logic表示は87%のまま。
CLSは9817→9725（95%→94%）。LUT単独の削減ではなく、Logic総数の小幅削減となった。
配置配線・ビットストリーム生成は成功し、`clock_54m`のActual Fmaxは60.920MHz（制約54MHz）。
ただし設計全体のタイミングレポートにはsetup/hold違反が残っており、全パスのタイミング達成を意味しない。
GHDLのPhase2アドレス演算、Phase3実効アドレス、LEA.Lと、M2SPTEST COMのCPUモード×WAIT有無4条件はPASS。実機未検証。
indexed16/indexed24回帰も全960条件PASS（IX/IY、M0/M1/M2、通常/Fast Z80、読出し/書込み、符号付き変位、WAIT有無）。

---

## 16. 周辺CPU動作（Phase15）監査メモ

[実装手順V4](doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_2026-10-11.md)section17「Phase 15 — 周辺CPU動作」、および[CPU仕様書V10](doc/jpn/OLD/MSX_T80_24bit化_CPU仕様書_V10_2026-10-11.md)section13の「HALT/WAIT/BUSREQ/BUSACK、DI/EI、interrupt timingはZ80/T80を敷衍する」に基づく監査。**新規opcodeの追加はありません。** 既存（T80コアから継承・未改変）の周辺機構が、`mode24_r`/`bank_pc_r`/`MSP24`が絡んでも壊れていないかを、Phase11（DD/FD+CB専用のはずのMCycle=110/111が無条件発火）・Phase13（M0/M1専用割込み処理がmode24_rを見ずに発火）で見つけたのと同じ観点で監査しました。

| 項目 | 監査結果 | 根拠 |
|---|---|---|
| HALT | 既に正しくガード済み。PC+1抑制（`Halt_FF`/`Halt`チェック）はM0/M1・M2のAddr24_Inc分岐を両方とも包含しており、M2割込みのIR強制分岐は`Halt_FF`判定より手前にあるため、HALT中でも非HALT時と全く同じ経路でM2割込みが発火する。ただし「HALT中にM2割込みを受ける」組合せはどのテストベンチも検証していなかったため、新規テストで実証（下記参照） | [t80.vhd](fpga/G80A/t80.vhd)のPC自動インクリメントガード、IR強制分岐の判定順序 |
| WAIT | 全ての24bit MSP24/PC24増減算は、既存（未改変）T80ステートマシン自身がTState進行をゲートするのと**全く同じ**`TState=2 and Wait_n='1'`条件を再利用している。WAIT挿入は常にTState=2での保持という単一の仕組みで実現されるため、M2の複数byte push/popシーケンス中にWAITが入っても、増減算が二重発火・早期発火することは構造的にあり得ない。ただし実際にWAIT_nをトグルするテストベンチはこれまで1つも無かったため、新規テストで実証（下記参照） | [t80.vhd](fpga/G80A/t80.vhd)メインステートマシンの`if TState=2 and Wait_n='0' then`（TState凍結）と、各MSP24増減算ブロックの`TState=2 and Wait_n='1'`条件 |
| BUSREQ/BUSACK | 本プロジェクトの実機ビルドでは不使用（[top.v](fpga/top.v)で`BUSRQ_n`を定数1に固定配線、`BUSAK_n`は未接続）。T80コア内のBUSREQ/BUSACK自体のロジックも無改変で、`mode24_r`やbankレジスタを一切参照しない。24bit固有の懸念なし | [top.v](fpga/top.v)の`BUSRQ_n(1)`/`BUSAK_n( )`配線 |
| R register | リフレッシュカウンタのインクリメントは、本プロジェクトの新機能とは無関係な（既存の）T80 `Mode`ジェネリック（`Mode<2`）でのみゲートされており、`mode24_r`は一切関与しない。影響なし | [t80.vhd](fpga/G80A/t80.vhd)のリフレッシュ処理ブロック（`if Mode < 2 then ... R(6 downto 0) <= R(6 downto 0) + 1;`） |
| IRQ/NMI受付タイミング | `NMICycle`/`IntCycle`の確定はNMI_s/INT_s/IntE_FF1/Prefixのみで決まり`mode24_r`やHalt_FFには依存しないため、HALT中・非HALT中を問わず同一の受付タイミングでPhase13のM2割込み機構へ正しく到達する | [t80.vhd](fpga/G80A/t80.vhd)メインステートマシンのNMICycle/IntCycle確定ロジック |
| prefix fetch | DD/FD+CB継続のMCycle=110/111バグは既にPhase11で発見・修正済み（[T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md](doc/jpn/T80コア内部に残っていた潜在バグ_Phase11-12での発見と修正.md)参照）。DD/FD+EDはLEA.L、24bit ALU、PUSH24/POP24 IX/IYを実装済み。未実装opcodeはNOP扱い（ロードマップ原則7）で、Phase15監査のスコープ外。 | 上記T80バグレポート、本一覧3章/5章/6章 |
| refresh動作 | リフレッシュサイクル中の`A_Bank_r`強制00hリセット（既存・無改変コード）は、[top.v](fpga/top.v)側で旧来のMSXバス調停（`mapper_req`/`megarom_req`、`bus_rfsh_n`でゲート）・新設の拡張メモリSD-RAM要求（`cpu_sdram_req`、同じく`bus_rfsh_n`でゲート）の両方が、リフレッシュサイクル中のアドレスには一切反応しないことを確認したため無害 | [top.v](fpga/top.v)の`cpu_sdram_req_r <= (... && bus_rfsh_n == 1) ...`、既存`mapper_req3`等の同様のゲート |

### 新規検証

コードレビューで「これまで未検証」と判明した2つの組合せ（HALT中のM2割込み、M2 push系列中へのWAIT挿入）を、新規GHDLテストベンチ [tb_phase15_peripheral.vhd](fpga/G80A/test/tb_phase15_peripheral.vhd) でEnd-to-endに実証しました。

- **Test1/1b**: HALT実行後（`HALT_n='0'`を確認してから）IRQを発生させ、非HALT時と全く同じIVR24分岐（4byte frame）・RETI.Lでの復帰を検証。push frameのPC_Lが「HALT命令直後のアドレス」（HALTの1byte分だけ進んだ値）になっていること、すなわちHALT自身のフェッチは通常通りPCを進めており、HALT中の内部NOP再フェッチだけがPCを止めていることも確認。
- **Test2/2b**: `RST.L 38H`のM1の最初のwaitサンプリングポイント（TState=2）で2クロック分`WAIT_n='0'`を注入し、MSP24への3byte push frameが非WAIT時と完全に同一の内容で（ただし時間的に遅延して）書き込まれることを検証。
- **Test3**: Test2のWAIT付きRST.L/RET.L往復後も、Test1のIRQカウンタが変化していない（意図しない再トリガや破壊が起きていない）ことを確認。

全17本（既存16本＋本テスト）のGHDL回帰は全てPASSしています。本Phaseはコードレビューと新規テストの両方で既存機構の正当性を確認する監査であり、t80.vhd/t80_mcode.vhdへの変更は一切ありません（Gowin合成リソースへの影響なし）。

---

## 17. Phase16「総合検証」

[実装手順V4](doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_2026-10-11.md)section18「Phase 16 — 総合検証」（M0: MSX互換性・MMU bypass・Z80命令回帰、M1: 16bit code+24bit data・MMU mapping・bank境界アクセス、M2: PC24・MSP24・near/far call・24bit ALU・PUSH24/POP24・interrupt、MMU: alias・mapping変更・W protect・bank boundary・M0 bypass）に基づく、ロードマップ最終Phaseの統合検証。**新規opcodeの追加はありません。** Phase0〜15で実装したM0/M1/M2全体を対象に、GHDL統合回帰・Gowin合成リソース・Place&Routeタイミング（Fmax）の3点を確認しました。

### 17.1 GHDL統合回帰

Phase2〜15で作成した全18本のGHDLテストベンチ（`tb_phase2_addr24`〜`tb_phase9_push24_pop24`、`tb_lea_l`、`tb_phase10_m2_basic`〜`tb_phase13_m2_interrupt`、`tb_rst_l`、`tb_phase15_peripheral`、`tb_m2_nested_stack`）を、コンパイル順序（`t80_pack.vhd t80_alu.vhd t80_mcode.vhd t80_reg.vhd t80.vhd mmu24.vhd`）を揃えた単一のビルドから続けて実行し、**全18本PASS**を確認しました。個々のテスト内容・対象PhaseはAVAILABLE_INSTRUCTIONS.mdの各セクション（3〜12、15〜16）を参照してください。

### 17.2 Gowin合成 + Place&Route（P&R）リソース使用率

デフォルトビルド（MMU無効、`MSXNanoTang20K_Z80X24.gprj`、Tang Nano 20K / GW2AR-18C）で、論理合成に加えて配置配線（Place&Route）まで実行し、ビットストリーム生成までエラーなく完走することを確認しました。

| リソース | 使用量 | 使用率 |
|---|---|---|
| Logic（LUT, ALU, ROM16） | 16987（15117 LUT, 1870 ALU, 0 ROM16） | 84% |
| Register | 7171 / 15915 | 46% |
| CLS | 9587 / 10368 | 93% |
| BSRAM | 45 / 46 | 98% |
| DSP | 1.5 / 24 | 7% |

P&R後のリソース数値は、論理合成段階（synthesis-only）の報告値（例: Phase15完了時点でLogic 83%・BSRAM 45/46=98%）と近い傾向にありますが、ALU使用数（1870、synthesis段階の1630台より増加）はP&R時の追加的な論理パッキング最適化による差分で、機能面への影響はありません。BSRAM使用率98%（45/46）は既存の制約（MMU無効化の理由、セクション14.1参照）のまま変化なしです。

### 17.3 タイミング解析（Fmax）

Place&Route後のSTA（Static Timing Analysis）レポートで、CPU本体が使うメインクロック`clock_54m`（54MHz）のタイミングクロージャを確認しました。

- **Max Frequency Summaryの表記上の注意**: Gowinのサマリーレポートは`clock_54m`のActual Fmaxを48.581MHz（制約54MHzに対し赤字で未達表示）と報告しますが、これは[tang20k.sdc](fpga/tang20k.sdc)で明示的に設定済みのmulticycle path例外（`set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/cpu1_0/...}] -setup -end 2`等、T80コアの一部内部パスに2サイクル分の猶予を与える既存の制約）を考慮しない単純な reciprocal 換算値であり、実際のタイミング合否を正しく反映していません。
- **実際の合否（Setup/Hold Paths Table、例外適用済み）**: `report_timing`による実際のパス解析（SDCのmulticycle例外を正しく適用）では、`clock_54m`→`clock_54m`（CPU内部、同一クロックドメイン）のsetupパスは全17件が正のスラックで収まっており（最小でも+0.116ns、`cpu1/cpu1_0/u0/IStatus_0_s15`からレジスタ書込み系統へのパスが最も厳しい）、holdパスもワースト25件（グローバル）の中に`cpu1`関連のパスは一切含まれません。**すなわちCPU本体は54MHzのタイミング制約を、既存のmulticycle設計を前提として満たしています。**
- **CPUと無関係な負スラックパス**: Setup Paths Tableの上位（最も厳しい）約200件は、いずれも`ex_bus_reset_n`（リセット信号が疑似クロックとして誤認識されたことによるPnRの警告、`WARN (TA1132)`参照）・SDカードコントローラ・VDPオーディオクロック・既存のFPGAコンパニオンMCUなど、**Z80X24 CPU拡張（t80.vhd等）とは無関係な、本プロジェクトのベース部分に既存のクロックドメインクロッシング**に起因するものです。本増分でのCPU拡張作業によって新たに生じたものではありません。

### 17.4 実機（Tang Nano）統合確認

M0/M1/M2それぞれの実機動作は、[hardware_test/](hardware_test)配下の各テストプログラムで個別に実機検証済みです（詳細は[hardware_test/README.md](hardware_test/README.md)の一覧参照）。

- M0互換性: [hardware_test/P12Test](hardware_test/P12Test)・[hardware_test/P1314Test](hardware_test/P1314Test)の各安全策（M0へ戻してからBDOS呼出し）が実機で問題なく機能し、既存MSX-DOS環境との共存を確認。
- MMU: [hardware_test/MMUTest](hardware_test/MMUTest)で全8テストPASS（MMU有効時点）。
- M2（PC24/MSP24/near・far call/interrupt）: [hardware_test/P12Test](hardware_test/P12Test)（モード間制御、全8チェックPASS）・[hardware_test/P1314Test](hardware_test/P1314Test)（RST.L・M2割込み、全7チェックPASS、実機の本物の非同期VDPフレーム割込みを使用）で確認。
- PUSH24/POP24: [hardware_test/Push24Test](hardware_test/Push24Test)で確認（bank境界をまたぐケースを除く、既知の制限はセクション7参照）。

### 17.5 まとめ

GHDL統合回帰（全18本PASS）・Gowin合成+P&R（エラーなし、ビットストリーム生成成功）・タイミングクロージャ（CPU本体のclock_54mは既存のmulticycle設計で54MHz達成）・実機統合確認（M0/M1/M2の主要機構をhardware_test/配下の各プログラムで実地検証済み）の4点から、ロードマップのMilestone G「M0/M1/M2総合統合」相当の内容を満たしていることを確認しました。これによりPhase0〜16、ロードマップに記載された全Phaseの実装・検証作業が完了しました。

---

## 18. 24bitメモリ間接転送 追加命令（ED00/01/03/08、2026-10-19実装）

[24bitメモリロード追加命令案.md](doc/jpn/24bitメモリロード追加命令案.md)・
[MSX_T80_24bit化_実装手順_V4_不足転送命令追加案_2026-10-19.md](doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_不足転送命令追加案_2026-10-19.md)・
[MSX_T80_24bit化_命令一覧_V13_予約維持_2026-10-19.csv](doc/jpn/OLD/MSX_T80_24bit化_命令一覧_V13_予約維持_2026-10-19.csv)
で提案された追加命令のうち、以下4命令をRTL実装しました。CPU仕様書V10の確定命令ではなく、
**本プロジェクト独自の追加提案**という位置付けです（正式採用はまだ未決定）。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 00` | `LD24 BC,(HL)` | HL24の指すアドレスからLOW/HIGH/BANKの3byteをBC24へロード。HL24は不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 01` | `LD24 DE,(HL)` | 同上、DE24へロード | 実装済み（GHDL検証済み、実機未検証） |
| `ED 03` | `LD24 (HL),BC` | BC24をHL24の指すアドレスへLOW/HIGH/BANKの3byte書込。HL24/BC24は不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 08` | `LD24 (HL),DE` | 同上、DE24を書込 | 実装済み（GHDL検証済み、実機未検証） |

### 18.1 実装の動機：PUSH24/POP24バンク境界またぎバグの切り分け

この4命令は、[PUSH24_POP24_bank境界またぎバグ_調査レポート.md](doc/jpn/PUSH24_POP24_bank境界またぎバグ_調査レポート.md)で継続中のPUSH24/POP24バグ調査のために、**MSP24の専用ハードウェア機構(`bank_msp_r`の自動増減ロジック)を一切経由しない、独立した3byteシーケンシャルアクセス経路**として新規実装しました。もし実機検証でこの4命令がPUSH24/POP24と同様のバンク境界またぎデータ破損を再現すれば、バグの所在はMSP24固有のロジックではなくCPU/SDRAMコントローラのより一般的な部分にあることが強く示唆されます。逆に再現しなければ、MSP24の`aMSP`アドレス生成経路・`bank_msp_r`増減ロジック自体に問題が局在している可能性が高まります。

### 18.2 実装の概要

- **新規アドレスソース`aXfer`**: `Set_Addr_To`バス(`t80_pack.vhd`/`t80_mcode.vhd`/`t80.vhd`)を3bitから4bitへ拡張し、新たに追加。既存の8個のエンコード値(`aNone`/`aBC`/`aDE`/`aXY`/`aIOA`/`aSP`/`aZI`/`aMSP`)は全て上位ビットを0埋めするだけで変更なく動作する。
- **`TmpAddr`/`TmpBank`の再利用**: (IX/IY+d)の実効アドレス計算に使われている既存の一時レジスタを、この4命令の「2byte目・3byte目のアドレス自動繰上げ」にも再利用（他の全ての既存用途とはopcodeが重複しないため、競合なし）。1byte目のアドレス自体はHL24(`aXY`、既存の(HL)間接アクセス経路)をそのまま使う。
- **MCycle構成**: PUSH24/POP24の実装パターンを踏襲（`MCycles<="0100"`、M1=opcode fetch、M2/M3/M4=各1byteの読み書き）。ただしPUSH24がBANK→HIGH→LOW(decrement-before)の順で書くのに対し、この4命令はLOW→HIGH→BANK(increment-after)の順方向アクセスのため、BANKバイトのDO上書き/DI取込みタイミングがPUSH24/POP24とは異なるMCycleに配置されている。
- **M0での挙動**: `(HL)`等の既存のregister-indirectアクセスと同じ“bank bypassルール”(`mode24_r="00"`の間はバンクバイトをアドレスへ適用しない)にそのまま従う。設計案自体は「M0動作は未確定」としていたが、既存の一貫性を優先しこの規約を採用した。
- **GHDLテストベンチ**: [tb_ld24_mem_indirect.vhd](fpga/G80A/test/tb_ld24_mem_indirect.vhd)を新規作成。通常アクセス・64KBバンク境界またぎ(01:FFFE→02:0000、PUSH24/POP24と同じ境界)・24bit全体のFFFFFFhラップアラウンド・HL24/F不変、を含む全アサーション合格を確認。
- **回帰確認**: 既存のGHDLテストベンチ19本（Phase2〜16相当+hw-timing repro）全てPASS、Gowinヘッドレス合成（`run syn`）もエラーなしを確認済み。

### 18.3 未実施の検証

- 実機（Tang Nano）での動作確認は本増分ではまだ実施していません。次のステップとして、この4命令を使った実機テストプログラムの追加が必要です。
- `ED02`/`ED12`/`ED13`/`ED1A`/`ED1B`/`ED21`（addr24絶対アドレス形式）、`ED22`/`ED25`/`ED26`/`ED2D`/`ED2E`（imm24即値ロード）、`ED32`/`ED33`（BC⇄DE転送）、`ED2A`/`ED31`/`ED3B`/`ED3C`/`ED82`/`ED83`（16bit版absolute）は、設計案には含まれているがRTL実装は未着手です。


- 24bit 拡張命令には、Z80 既存命令に `ED` を前置する「mirror 方式」を採用しています。
- `M0` の場合は従来の 64KB 空間へ戻り、互換性を維持します。
- `M1` はデータアクセスのみ 24bit 化されます。(Phase3時点では `(HL)` / `(BC)` / `(DE)` / `(IX+d)` / `(IY+d)` の間接アクセスが対象。SP経由のスタックアクセスとPC相対の命令フェッチ・直接16bitアドレス指定は未対応で、`M0`/`M1`/`M2` のいずれでも常に16bit扱いです。)
- `M2` は 24bit ネイティブ動作としてフル拡張モードになります。
