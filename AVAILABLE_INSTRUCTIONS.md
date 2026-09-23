# 使用可能な命令一覧

この一覧は、MSX T80 24bit 拡張仕様書に基づく、現在の構成で使用可能または想定される 24bit 拡張命令のまとめです。

> 参考: [README.md](README.md) からリンクされています。
> 実装状態は、以下の基準で整理しています。
> - 実装済み: 現在のプロジェクト内で対応が確認できている命令
> - 未実装: 仕様上はあるが、現時点で未対応の命令
> - 仕様のみ: 設計書に定義があるが、実装または検証が未完了の命令

---

## 1. モード切替 / バンク制御

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 90` | `SET_M0` | 完全 Z80 互換モードへ移行 | 仕様のみ |
| `ED 91` | `SET_M1` | データアクセス拡張モードへ移行 | 仕様のみ |
| `ED 92` | `SET_M2` | 24bit ネイティブ動作モードへ移行 | 仕様のみ |
| `ED 04` | `LD BC_B, A` | BC バンクレジスタへ書き込み | 未実装 |
| `ED 14` | `LD DE_B, A` | DE バンクレジスタへ書き込み | 未実装 |
| `ED 24` | `LD HL_B, A` | HL バンクレジスタへ書き込み | 未実装 |
| `ED 34` | `LD INT_B, A` | 割り込みバンク設定 | 未実装 |
| `ED 35` | `LD MSP_B, A` | MSP バンク設定 | 未実装 |
| `ED 0C` | `LD A, BC_B` | BC バンクレジスタ読み出し | 未実装 |
| `ED 1C` | `LD A, DE_B` | DE バンクレジスタ読み出し | 未実装 |
| `ED 2C` | `LD A, HL_B` | HL バンクレジスタ読み出し | 未実装 |

---

## 2. 24bit 演算 / データロード

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 03` | `INC XBC` | XBC を 24bit で +1 | 未実装 |
| `ED 13` | `INC XDE` | XDE を 24bit で +1 | 未実装 |
| `ED 23` | `INC XHL` | XHL を 24bit で +1 | 未実装 |
| `ED 33` | `INC XSP` | XSP を 24bit で +1 | 未実装 |
| `ED 0B` | `DEC XBC` | XBC を 24bit で -1 | 未実装 |
| `ED 1B` | `DEC XDE` | XDE を 24bit で -1 | 未実装 |
| `ED 2B` | `DEC XHL` | XHL を 24bit で -1 | 未実装 |
| `ED 3B` | `DEC XSP` | XSP を 24bit で -1 | 未実装 |
| `ED 3D` | `CP XHL, XDE` | 24bit 比較 | 未実装 |
| `ED 09` | `ADD XHL, XBC` | 24bit 加算 | 未実装 |
| `ED 19` | `ADD XHL, XDE` | 24bit 加算 | 未実装 |
| `ED 29` | `ADD XHL, XHL` | 24bit 2倍 | 未実装 |
| `ED 39` | `ADD XHL, XSP` | 24bit 加算 | 未実装 |
| `ED 0A` | `SUB XHL, XBC` | 24bit 減算 | 未実装 |
| `ED 1A` | `SUB XHL, XDE` | 24bit 減算 | 未実装 |
| `ED 31` | `LD XSP, ext24` | 24bit スタック設定 | 未実装 |
| `ED 32` | `LD XHL, ext24` | 24bit 即値ロード | 未実装 |
| `ED 2A` | `LD XHL, (ext24)` | 24bit 直接ロード | 未実装 |
| `ED 22` | `LD (ext24), XHL` | 24bit 直接保存 | 未実装 |
| `ED 4F` | `LD XBC, (XHL)` | 間接 24bit ロード | 未実装 |
| `ED 5F` | `LD XDE, (XHL)` | 間接 24bit ロード | 未実装 |
| `ED 47` | `LD (XHL), XBC` | 間接 24bit 保存 | 未実装 |
| `ED 57` | `LD (XHL), XDE` | 間接 24bit 保存 | 未実装 |
| `ED 6F` | `LDIR24` | 24bit ブロック転送 | 未実装 |

---

## 3. PUSH / POP（M2 用拡張スタック）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED C5` | `PUSH XBC` | XBC を退避 | 未実装 |
| `ED D5` | `PUSH XDE` | XDE を退避 | 未実装 |
| `ED E5` | `PUSH XHL` | XHL を退避 | 未実装 |
| `ED F5` | `PUSH XAF` | AF と実行バンクを退避 | 未実装 |
| `ED C1` | `POP XBC` | XBC を復元 | 未実装 |
| `ED D1` | `POP XDE` | XDE を復元 | 未実装 |
| `ED E1` | `POP XHL` | XHL を復元 | 未実装 |
| `ED F1` | `POP XAF` | AF と実行バンクを復元 | 未実装 |

---

## 4. 分岐 / 呼び出し / 復帰

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED C3` | `JP.L ext24` | 24bit 無条件ジャンプ | 未実装 |
| `ED C2` / `CA` | `JP.L NZ / Z, ext24` | 条件付き 24bit ジャンプ | 未実装 |
| `ED D2` / `DA` | `JP.L NC / C, ext24` | 条件付き 24bit ジャンプ | 未実装 |
| `ED E2` / `EA` | `JP.L PO / PE, ext24` | 条件付き 24bit ジャンプ | 未実装 |
| `ED F2` / `FA` | `JP.L P / M, ext24` | 条件付き 24bit ジャンプ | 未実装 |
| `ED 18` | `JR.L offset16` | 16bit 相対ジャンプ | 未実装 |
| `ED 20` / `28` | `JR.L NZ / Z, offset16` | 条件付き 16bit 相対ジャンプ | 未実装 |
| `ED 30` / `38` | `JR.L NC / C, offset16` | 条件付き 16bit 相対ジャンプ | 未実装 |
| `ED C7` / `D7` | `JR.L PO / PE, offset16` | 条件付き 16bit 相対ジャンプ | 未実装 |
| `ED E7` / `F7` | `JR.L P / M, offset16` | 条件付き 16bit 相対ジャンプ | 未実装 |
| `ED CD` | `CALL.L ext24` | 24bit コール | 未実装 |
| `ED C4` / `CC` | `CALL.L NZ / Z, ext24` | 条件付き 24bit コール | 未実装 |
| `ED D4` / `DC` | `CALL.L NC / C, ext24` | 条件付き 24bit コール | 未実装 |
| `ED E4` / `EC` | `CALL.L PO / PE, ext24` | 条件付き 24bit コール | 未実装 |
| `ED F4` / `FC` | `CALL.L P / M, ext24` | 条件付き 24bit コール | 未実装 |
| `ED C9` | `RET.L` | 24bit リターン | 未実装 |
| `ED C0` / `C8` | `RET.L NZ / Z` | 条件付き 24bit リターン | 未実装 |
| `ED D0` / `D8` | `RET.L NC / C` | 条件付き 24bit リターン | 未実装 |
| `ED E0` / `E8` | `RET.L PO / PE` | 条件付き 24bit リターン | 未実装 |
| `ED F0` / `F8` | `RET.L P / M` | 条件付き 24bit リターン | 未実装 |
| `ED 4E` | `RETI.L` | M2 用 24bit 割り込み復帰 | 未実装 |

---

## 5. インデックス付き 24bit アドレス計算

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `DD ED 68 d` | `LEA.L XHL, (XIX+d)` | IX から 24bit アドレス計算 | 未実装 |
| `FD ED 68 d` | `LEA.L XHL, (XIY+d)` | IY から 24bit アドレス計算 | 未実装 |
| `DD ED 69 d` | `LEA.L XDE, (XIX+d)` | IX から 24bit アドレス計算 | 未実装 |
| `DD ED 6A d` | `PEA.L (XIX+d)` | IX 付きアドレスをスタックへ保存 | 未実装 |
| `FD ED 6A d` | `PEA.L (XIY+d)` | IY 付きアドレスをスタックへ保存 | 未実装 |

---

## 6. 標準 Z80 ブロック転送 / I/O

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

必要に応じて次に、これを README に埋め込む短い「使用可能命令一覧」セクションにも展開できます。
