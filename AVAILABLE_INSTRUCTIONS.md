# 使用可能な命令一覧

この一覧は、MSX T80 24bit 拡張仕様書に基づく、現在の構成で使用可能または想定される 24bit 拡張命令のまとめです。

> 参考: [README.md](README.md) からリンクされています。
> 本一覧は [MSX_T80_24bit化_CPU仕様書_V8](doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md) と
> [MSX_T80_24bit化_命令一覧_V7](doc/jpn/MSX_T80_24bit化_命令一覧_V7_2026-10-05.csv)（いずれもopcode確定・TBDなし）を正としています。旧V5仕様に基づく暫定opcodeの記載は廃止しました。
> 実装状態は、以下の基準で整理しています。
> - 実装済み: 現在のプロジェクト内（[t80.vhd](fpga/G80A/t80.vhd)）で対応が確認できている命令
> - 未実装: V8/V7で確定しているが、現時点で未対応の命令

---

## 1. モード制御

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 90` | `SET_M0` | 完全 Z80 互換モードへ移行 | 実装済み（mode24_rのみ切替、PC/SPアドレス生成とは未連動） |
| `ED 91` | `SET_M1` | データアクセス拡張モードへ移行 | 実装済み（mode24_rのみ切替、PC/SPアドレス生成とは未連動） |
| `ED 92` | `SET_M2` | 24bit ネイティブ動作モードへ移行 | 実装済み（mode24_rのみ切替、PC/SPアドレス生成とは未連動） |
| `ED 93` | `JP.M0 addr16` | M0へモード遷移ジャンプ | 未実装 |
| `ED 94` | `JP.M1 addr16` | M1へモード遷移ジャンプ | 未実装 |
| `ED 95` | `JP.M2 addr24` | M2へモード遷移ジャンプ | 未実装 |
| `ED 96` | `CALL.M0 addr16` | M0へモード遷移コール | 未実装 |
| `ED 97` | `CALL.M1 addr16` | M1へモード遷移コール | 未実装 |
| `ED 98` | `CALL.M2 addr24` | M2へモード遷移コール | 未実装 |
| `ED 99` | `RET.M` | モード遷移フレームからの復帰 | 未実装 |

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
| `ED 3A` | `LD RST_B, A` | RST.L用バンクレジスタへ書き込み | 実装済み |
| `ED 3E` | `LD A, RST_B` | RST.L用バンクレジスタ読み出し | 実装済み |

> `MSP24`/`IVR24`/`NVR24`は単純な8bit bankレジスタではなく、最初からフル24bitレジスタとして定義されており、上記のような単独`_B`直接LD命令は存在しません（下記「3. 24bit転送」「4. 割込ベクタ」参照）。`PC_B`も直接LDする命令は無く、`SET_M2`/`CALL.M2`等のモード遷移命令が自動的に設定します。

---

## 3. 24bit転送（HL24 hub / MSP）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 06` | `LD24 HL, BC` | full 24bit、F不変 | 未実装 |
| `ED 0E` | `LD24 BC, HL` | full 24bit、F不変 | 未実装 |
| `ED 16` | `LD24 HL, DE` | full 24bit、F不変 | 未実装 |
| `ED 1E` | `LD24 DE, HL` | full 24bit、F不変 | 未実装 |
| `DD ED 26` | `LD24 HL, IX` | full 24bit、F不変 | 未実装 |
| `DD ED 2E` | `LD24 IX, HL` | full 24bit、F不変 | 未実装 |
| `FD ED 26` | `LD24 HL, IY` | full 24bit、F不変 | 未実装 |
| `FD ED 2E` | `LD24 IY, HL` | full 24bit、F不変 | 未実装 |
| `ED 34 bl bh bn` | `LD24 MSP, imm24` | F不変 | 未実装 |
| `ED 35` | `LD24 MSP, HL` | full 24bit、F不変 | 未実装 |
| `ED 36` | `LD24 HL, MSP` | full 24bit、F不変 | 未実装 |

---

## 4. 割込ベクタ（IVR24 / NVR24）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 9A bl bh bn` | `LD24 IVR, imm24` | F不変 | 未実装 |
| `ED 9B` | `LD24 IVR, HL` | F不変 | 未実装 |
| `ED 9C` | `LD24 HL, IVR` | F不変 | 未実装 |
| `ED 9D bl bh bn` | `LD24 NVR, imm24` | F不変 | 未実装 |
| `ED 9E` | `LD24 NVR, HL` | F不変 | 未実装 |
| `ED 9F` | `LD24 HL, NVR` | F不変 | 未実装 |

---

## 5. 24bit ALU

専用24bit ALUを使用。DD/FDプレフィクスでHL targetをIX/IYへ置換。SUB24は設けずC=0のSBC24を使う。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 23` | `INC24 HL` | 24bitで+1 | 未実装 |
| `ED 2B` | `DEC24 HL` | 24bitで-1 | 未実装 |
| `ED 09` / `19` / `29` / `39` | `ADD24 HL, BC/DE/HL/SP` | 24bit加算 | 未実装 |
| `ED 07` / `17` / `27` / `37` | `ADC24 HL, BC/DE/HL/SP` | 24bit桁上げ加算 | 未実装 |
| `ED 0F` / `1F` / `2F` / `3F` | `SBC24 HL, BC/DE/HL/SP` | 24bit桁借り減算 | 未実装 |
| `ED 3D` | `CP24 HL, DE` | 24bit比較（writebackなし） | 未実装 |

---

## 6. Indexed転送

DD/FD ED80〜8B。80〜82=LD16 load、83〜85=LD16 store、86〜88=LD24 load、89〜8B=LD24 store。M0=16bit EA、M1/M2=24bit EA。LD16はbank byte不変。

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

---

## 7. 24bit Stack（PUSH24 / POP24）

対象はBC24/DE24/HL24/IX24/IY24のみ（AFは対象外）。MSPを使用し3byte転送。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED C5` / `C1` | `PUSH24` / `POP24 BC` | 未実装 |
| `ED D5` / `D1` | `PUSH24` / `POP24 DE` | 未実装 |
| `ED E5` / `E1` | `PUSH24` / `POP24 HL` | 未実装 |
| `DD ED E5` / `E1` | `PUSH24` / `POP24 IX` | 未実装 |
| `FD ED E5` / `E1` | `PUSH24` / `POP24 IY` | 未実装 |

---

## 8. 24bit制御（JR.L / JP.L / CALL.L / RET.L）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 18` | `JR.L e16` | M2=PC24相対、M0/M1=PC16相対 | 未実装 |
| `ED 20` / `28` | `JR.L NZ/Z, e16` | 条件付き | 未実装 |
| `ED 30` / `38` | `JR.L NC/C, e16` | 条件付き | 未実装 |
| `ED A7` / `AF` | `JR.L PO/PE, e16` | 条件付き | 未実装 |
| `ED B7` / `BF` | `JR.L P/M, e16` | 条件付き | 未実装 |
| `ED C3` | `JP.L addr24` | 24bit無条件ジャンプ | 未実装 |
| `ED C2/CA/D2/DA/E2/EA/F2/FA` | `JP.L cc, addr24` | 条件付き24bitジャンプ | 未実装 |
| `ED CD` | `CALL.L addr24` | MSPへPC24を3byte保存（M2専用） | 未実装 |
| `ED C4/CC/D4/DC/E4/EC/F4/FC` | `CALL.L cc, addr24` | 条件付きfar call（M2専用） | 未実装 |
| `ED C9` | `RET.L` | MSPからPC24復元（M2専用） | 未実装 |
| `ED C0/C8/D0/D8/E0/E8/F0/F8` | `RET.L cc` | 条件付きfar return（M2専用） | 未実装 |

---

## 9. RST拡張（RST.L）

`RST_B`がRST.L用8bit bankレジスタ（上記「2. バンクレジスタ」参照）。M0/M1では対応する通常Z80 RST（return PCは16bit）、M2ではreturn PC24をMSPへ3byte pushし`PC24={RST_B,00h,vector}`。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED C7` / `CF` | `RST.L 00H` / `08H` | 未実装 |
| `ED D7` / `DF` | `RST.L 10H` / `18H` | 未実装 |
| `ED E7` / `EF` | `RST.L 20H` / `28H` | 未実装 |
| `ED F7` / `FF` | `RST.L 30H` / `38H` | 未実装 |

> 通常（ED非前置）の `RST 00H〜38H` は既存Z80標準命令として実装済みです。

---

## 10. 割り込み（M2拡張）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 4E` | `RETI.L` | M2用4byte frame復元 | 未実装 |
| `ED 8C` | `RETN.L` | M2用4byte frame復元、IFF1<-IFF2 | 未実装 |
| `ED 8D`〜`8F` | RESERVED | 未実装中はNOP | 未実装（現状は未定義opcodeとしてNOP動作） |

---

## 11. 標準 Z80 ブロック転送 / I/O

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED A0` / `A8` | `LDI` / `LDD` | ブロック転送 | 実装済み（Z80 標準） |
| `ED B0` / `B8` | `LDIR` / `LDDR` | 連続ブロック転送 | 実装済み（Z80 標準） |
| `ED 78` / `48` | `IN A, (C)` / `OUT (C), A` | I/O ポートアクセス | 実装済み（Z80 標準） |
| `ED A2` / `A3` | `INI` / `OUTI` | I/O からメモリ転送 | 実装済み（Z80 標準） |
| `ED B2` / `B3` | `INIR` / `OTIR` | 連続 I/O 転送 | 実装済み（Z80 標準） |

---

## 補足

- 24bit 拡張命令には、Z80 既存命令に `ED` を前置する「mirror 方式」を採用しています。
- `M0` の場合は従来の 64KB 空間へ戻り、互換性を維持します。
- `M1` はデータアクセスのみ 24bit 化されます。
- `M2` は 24bit ネイティブ動作としてフル拡張モードになります。
