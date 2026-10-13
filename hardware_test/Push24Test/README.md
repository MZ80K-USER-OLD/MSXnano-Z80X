# Z80X24 Phase9 PUSH24/POP24 実機検証テスト (P24TEST.COM)

MSXnano-Z80X ([msxnano-24bit](../..) リポジトリ、24bit CPU拡張 "Z80X24") の
**Phase9「PUSH24/POP24」**を、実機(Tang Nano)またはMSXエミュレータ上の
MSX-DOS(2)から起動して確認するための、Z80アセンブリ製テストプログラムです。

同じシナリオを検証するGHDLシミュレーション版テストベンチが
`msxnano-24bit/fpga/G80A/test/tb_phase9_push24_pop24.vhd` にあります。本プログラム
はそれを実機上で再現します。

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

`Push24Test` フォルダで実行します。

```powershell
make
```

`bin\p24test.com` が生成されます。中間ファイルは `obj` と `BINZ80` フォルダに
生成されます。`make clean` で中間ファイルを削除できます。ビルドはこの環境で
実際に実行し、エラー・警告なくアセンブルできることを確認済みです。

`build.bat` は `z80asm` を直接呼び出す簡易スクリプトです(Z88DK同梱の
旧来の `z80asm` 用で、環境によっては使えない場合があります)。標準の
ビルド手順は `make` です。

## MSX上での実行

`bin\p24test.com` をMSXまたはエミュレータのディスクイメージ(または実SDカード)
へコピーし、MSX-DOSから実行します。

```text
A>P24TEST
```

実行ファイル名はMSX-DOSの8.3形式(ファイル名最大8文字＋拡張子3文字)に
合わせて `P24TEST.COM` としています(`PUSH24TEST` は10文字でファイル名の
8文字制限を超えるため短縮しました)。

## テスト内容

`push24_test.asm` は以下の6つのテストを順に実行し、各テストの結果と
最後に合計PASS/FAIL数を画面へ表示します。本増分で実装した6個のPUSH24/POP24系
命令(`ED C5`/`C1`/`D5`/`D1`/`E5`/`E1`)すべてを少なくとも1回ずつ実行します。

| # | 内容 |
|---|---|
| Test1 | `ED C5`/`C1` PUSH24/POP24 BC 往復試験。BC24をPUSH24→破壊→POP24した後、元の値に戻ることを確認 |
| Test2 | PUSH24 BC → POP24 DE のレジスタをまたいだ往復試験。データが実際にメモリ経由で転送されていること（単なるレジスタ別名化ではないこと）を確認 |
| Test3 | `ED D5`/`D1` PUSH24/POP24 DE 往復試験 |
| Test4 | `ED E5`/`E1` PUSH24/POP24 HL 往復試験 |
| Test5 | LIFO（後入れ先出し）順序試験。BC/DE/HLの順でPUSH24し、BC/DE/HLの順でPOP24すると、最後にPUSHしたHLの値がBCへ、DEの値がDEへ、最初にPUSHしたBCの値がHLへという「逆順」で復元されることを確認 |
| Test6 | いずれか1つのPUSH24/POP24命令の前後でF（フラグ）レジスタが変化しないことを確認（仕様上「F不変」、Z80標準のPUSH/POPと同様） |

全テストがPASSすれば、Phase9で実装したPUSH24/POP24命令群が、仕様書
([MSX_T80_24bit化_CPU仕様書_V8](../../doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md)
セクション9「Stack」)どおりに動作していることが実機で確認できます。
**Test1〜Test6(LIFO順序試験の5a/5b/5cを含む、合計8件のチェック)は
2026年10月に実機(Tang Nano)で全PASS・MSX-DOSへの正常復帰を確認済みです
(`PASS=08 FAIL=00`)。**

## 本増分の対象範囲

Phase9で仕様上定義されている命令のうち、本プログラムが検証するのは
**BC24/DE24/HL24のPUSH24/POP24のみ**です。以下は別増分で対応予定のため、
本プログラムの対象外です。

- `DD ED E5`/`E1`, `FD ED E5`/`E1`(PUSH24/POP24 IX/IY。DD/ED二重プレフィクス
  の命令デコード拡張が必要。Phase7のLD24 HL,IX/IYと同様の理由）

詳細は[AVAILABLE_INSTRUCTIONS.md](../../AVAILABLE_INSTRUCTIONS.md)
セクション7を参照してください。

## 既知の問題: bank境界をまたぐPUSH24/POP24は実機で未検証(フリーズ再現)

本プログラムの初版では、1回のPUSH24呼出し中に物理bankが変化する試験
(MSP24=02:0001hからPUSH24 HLを実行し、3回のデクリメントで
02:0001→02:0000→01:FFFF(bank繰り下がり)→01:FFFEとbankをまたぐシナリオ)
を含めていましたが、**実機検証でTest5c完了直後にシステムがフリーズする
現象が再現しました**(画面にバナーが再表示された後、応答不能に)。

GHDLシミュレーション(`tb_phase9_push24_pop24.vhd`)ではこの同じシナリオが
問題なくPASSしていたため、これは実機固有の問題と判断されます。原因として
以下が疑われます。

- 1回のPUSH24/POP24命令の中で、連続する3回のメモリアクセス(BANK/HIGH/LOW
  byte)がそれぞれ**異なる物理bank**へルーティングされる経路は、Phase3/5
  で検証済みの既存の拡張メモリアクセス(`(HL)`/`(BC)`/`(DE)`/`(IX+d)`等。
  いずれも1命令につき拡張アクセスは1回のみ)では一度も検証されていない、
  今回のPUSH24/POP24が初めて踏んだ経路であること。
- 本プロジェクトのSD-RAMコントローラ(`fpga/src/memory.v`・`sdram.v`)には、
  拡張メモリアクセスに対してCPU側へWAIT状態を生成する機構が存在しない
  (`fpga/top.v`の`ex_bus_wait_n`は常時`1'b1`固定)。そのため、物理bankの
  切り替えにコントローラ側で想定より長い内部処理時間が必要な場合でも、
  CPUはその完了を待たずに次のバスサイクルへ進んでしまう。
- 上記により、bankをまたぐ書込みの際にアドレス生成が一時的に不正な値を
  取り、意図しない領域(bank00h=実行中プログラム自身の64KB空間や、BIOS/
  割込みベクタ等のシステム領域)を破壊した可能性が疑われる。

この問題は未解決であり、根本原因の特定には`fpga/src/memory.v`・`sdram.v`の
SD-RAMタイミングのより詳細な調査が必要です。そのため、**本プログラムは
bank境界をまたぐPUSH24/POP24を一切発生させない**(全テストで、1回の
PUSH24/POP24呼出しは常に単一の物理bank内で完結する)よう修正済みです。
bank境界をまたぐケースの安全性は、この問題が解決されるまで保留事項として
扱います。

## 安全上の注意

- PUSH24/POP24はMSP24(`ED35`/`ED36`で読み書きするPhase7由来の専用24bitポインタ)
  を使用し、通常のZ80 16bit SP(MSX-DOS/BIOSが使うスタック)とは完全に独立
  しています。そのためBDOS呼出しやMSX標準の割り込み処理が、MSP24や
  PUSH24/POP24で書き込んだ拡張メモリへ誤って触れる心配はなく、[MMUTest](../MMUTest)
  のようなDI/EI・モード切替は一切不要です(mode24設定にも依存せず、CPU仕様書V8
  のとおりM0/M1/M2いずれでも常時full 24bitで動作します)。
- 本プログラムが使用する物理bankは **01h, 02h, 03h, 04h, 05h のみ**です。これは
  `fpga/top.v` の `CPU_SDRAM_BASE`(0x640000)経由で、既存のMemory Mapper
  (0x000000-)やMegaRAM(0x400000-)とは重ならない安全な領域
  (0x650000-0x7FFFFF、詳細は `doc/jpn/SDRAMメモリマップ.md` 2.2章)に
  収まります。Test6のbank境界またぎ試験は意図的にbank01h/02hの組だけを
  使い、bank00h(実行中のプログラム自身の64KB空間そのもの)を経由しない
  よう設計しています。
- プログラム終了前に、使用したBC/DE/HLバンクレジスタを0クリアしてから
  MSX-DOSへ復帰します(`SAFE_RESET`)。MSP24自体は[LD24Test](../LD24Test)
  と同様、他のMSX-DOS/BIOSコードが参照することのない専用レジスタなので
  明示的なクリアは行いません。
- Z80X24拡張が入っていない通常のMSX実機/エミュレータ上で実行すると、
  `ED 04/0C/14/1C/24/2C` や `ED 35/36/C5/C1/D5/D1/E5/E1` は未定義命令
  (多くの実装ではNOP相当)として扱われます。この場合、全テストがFAILと
  表示されますが、これは異常ではなく「拡張機能が存在しない」ことを
  意味します。

## ファイル構成

- `push24_test.asm` — テスト本体
- `makefile` — `z88dk-z80asm` + `z88dk-appmake` によるビルド
- `build.bat` — 旧来の `z80asm` を直接呼び出す簡易スクリプト
- `bin/` — ビルド成果物 (`p24test.com`)
- `obj/`, `BINZ80/` — 中間ファイル・リストファイル
