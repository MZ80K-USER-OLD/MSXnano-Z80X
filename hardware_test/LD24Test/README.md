# Z80X24 Phase7 LD24レジスタ転送 実機検証テスト (LD24TEST.COM)

> **現行RTLでは実行禁止（旧命令の履歴用）**。
> Test6の旧ED9B LD24 IVR,HLは廃止され、現在はJP.M2である。
> 既存COMも再ビルドした同ソースも新RTLと非互換。
> 通常の`make`は明示エラーで停止する。旧RTLでの履歴再現に限り
> `make LEGACY_OPCODES=1`を使用する。
> [V16.1移行記録](../../verification_data/v161_rst_l/README.md)を参照。

MSXnano-Z80X ([msxnano-24bit](../..) リポジトリ、24bit CPU拡張 "Z80X24") の
**Phase7「LD24系命令」**の旧仕様に基づくレジスタ間24bit転送命令
(HL24 hub / MSP24 / IVR24 / NVR24)を検証した履歴用テストプログラムです。

対応するGHDLテストベンチも旧命令仕様の履歴として
`fpga/G80A/test/tb_phase7_ld24.vhd` に保持しています。どちらも現行RTLの
検証には使用しません。

## 必要な環境

- Windows
- Z88DK (`D:\Tool\z88dk` にインストールされている想定)
- `z88dk-z80asm` / `z88dk-appmake`
- `make` (GnuWin32 make等)
- 実行環境としてZ80X24拡張済みMSXnano実機、またはMSX-DOS(2)が動くMSXエミュレータ

PowerShellで現在のターミナルだけPATHへ追加する場合:

```powershell
$env:Path += ";D:\Tool\z88dk\bin"
```

コマンドが見つかることを確認します。

```powershell
Get-Command z88dk-z80asm
Get-Command z88dk-appmake
```

## ビルド

`LD24Test` フォルダで実行します。

```powershell
make
```

`bin\ld24test.com` が生成されます。中間ファイルは `obj` と `BINZ80` フォルダに
生成されます。`make clean` で中間ファイルを削除できます。ビルドはこの環境で
実際に実行し、エラー・警告なくアセンブルできることを確認済みです。

`build.bat` は `z80asm` を直接呼び出す簡易スクリプトです(Z88DK同梱の
旧来の `z80asm` 用で、環境によっては使えない場合があります)。標準の
ビルド手順は `make` です。

## MSX上での実行

`bin\ld24test.com` をMSXまたはエミュレータのディスクイメージ(または実SDカード)
へコピーし、MSX-DOSから実行します。

```text
A>LD24TEST
```

## テスト内容

`ld24_test.asm` は以下の8つのテストを順に実行し、各テストの結果と
最後に合計PASS/FAIL数を画面へ表示します。本増分で実装した10個のLD24系命令
(`ED06`/`0E`/`16`/`1E`/`35`/`36`/`9B`/`9C`/`9E`/`9F`)すべてを少なくとも
1回ずつ実行します。

| # | 内容 |
|---|---|
| Test1a/1b | `ED06 LD24 HL,BC`(HL24←BC24)。宛先HL24の値と、ソースBC24が不変であることを確認 |
| Test2a/2b | `ED0E LD24 BC,HL`(BC24←HL24)。宛先BC24の値と、ソースHL24が不変であることを確認 |
| Test3a/3b | `ED16 LD24 HL,DE`(HL24←DE24)。宛先HL24の値と、ソースDE24が不変であることを確認 |
| Test4a/4b | `ED1E LD24 DE,HL`(DE24←HL24)。宛先DE24の値と、ソースHL24が不変であることを確認 |
| Test5 | `ED35`/`ED36` MSP24往復試験。HL24→MSP24→(HL24破壊)→HL24の順で元の値に戻ることを確認 |
| Test6 | `ED9B`/`ED9C` IVR24往復試験。同上の手順でIVR24を検証 |
| Test7 | `ED9E`/`ED9F` NVR24往復試験。同上の手順でNVR24を検証 |
| Test8 | いずれか1つのLD24命令の前後でF(フラグ)レジスタが変化しないことを確認(仕様上「F不変」) |

全テストがPASSすれば、Phase7で実装したレジスタ間24bit転送命令群が、仕様書
([MSX_T80_24bit化_CPU仕様書_V8](../../doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md)
セクション7「HL24 hub / MSP / vector」)どおりに動作していることが実機で
確認できます。

## 本増分の対象範囲

Phase7で仕様上定義されている命令のうち、本プログラムが検証するのは
**単一のEDプレフィクスで完結するレジスタ間24bitコピー命令のみ**です。
以下は別増分で対応予定のため、本プログラムの対象外です。

- `DD ED 26`/`2E`, `FD ED 26`/`2E`(HL24⇔IX24/IY24 hub転送。DD/ED二重
  プレフィクスの命令デコード拡張が必要）
- `ED 34`/`9A`/`9D`(MSP24/IVR24/NVR24への24bit即値ロード。3byte即値
  フェッチのMCycleシーケンス拡張が必要）
- `DD/FD ED 80`〜`8B`(インデックス付きLD16/LD24。メモリバスシーケンスと
  MMU対応アドレス生成の拡張が必要）

詳細は[AVAILABLE_INSTRUCTIONS.md](../../AVAILABLE_INSTRUCTIONS.md)
セクション3・4を参照してください。

## 安全上の注意

- 本増分のLD24命令はすべて単純なレジスタ間24bitコピーであり、モード切替
  (M1/M2)やメモリ/MMUアクセスを一切伴いません。そのため
  [MMUTest](../MMUTest)のテストプログラムとは異なり、本プログラムは常時
  M0(通常のMSX互換モード)のまま動作します。DI/EIによる割り込み抑止や
  物理bank割当への配慮は不要です。
- HL/BC/DEのバンクバイト(`HL_B`/`BC_B`/`DE_B`)は、Phase1で実装済みの
  `ED 04/0C/14/1C/24/2C LD xx_B,A / LD A,xx_B` を用いて設定・読出しします。
- プログラム終了前に、使用したBC/DE/HLバンクレジスタを0クリアしてから
  MSX-DOSへ復帰します(`SAFE_RESET`)。
- Z80X24拡張が入っていない通常のMSX実機/エミュレータ上で実行すると、
  `ED 04/0C/14/1C/24/2C` や `ED 06/0E/16/1E/35/36/9B/9C/9E/9F` は未定義命令
  (多くの実装ではNOP相当)として扱われます。この場合、HL/BC/DEの値が
  期待通りに変化せず全テストがFAILと表示されますが、これは異常ではなく
  「拡張機能が存在しない」ことを意味します。

## 実装上の注意点(テストプログラム自体のバグ修正)

本プログラムの初版では、BDOS呼出し(`CALL BDOS`)の前後でレジスタやフラグの
値が保存される前提のコードになっており、実機で不正な判定結果になる恐れが
ありました(BDOSはレジスタ・フラグの保存を一般に保証しません)。
[MMUTest](../MMUTest)の`CHECK_AND_PRINT`と同じ安全策に倣い、比較に必要な
値は最初にすべて固定メモリ変数(`CHK_EXP_*`/`CHK_ACT_*`)へ退避してから
比較するよう修正済みです。同様に、フラグ比較(Test8)も`CP`命令の直後に
分岐するよう修正し、間にBDOS呼出しを挟まない構成にしています。

## ファイル構成

- `ld24_test.asm` — テスト本体
- `makefile` — `z88dk-z80asm` + `z88dk-appmake` によるビルド
- `build.bat` — 旧来の `z80asm` を直接呼び出す簡易スクリプト
- `bin/` — ビルド成果物 (`ld24test.com`)
- `obj/`, `BINZ80/` — 中間ファイル・リストファイル
