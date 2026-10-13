# Z80X24 Phase5 MMU 実機検証テスト (MMUTEST.COM)

> **【重要・仕様変更に関する注記】** このテストはPhase4〜6で実装したMMU
> (`MMU24`、`F0h`/`F1h`/`F2h` I/Oポート)を前提に作成されました。その後、
> Tang Nano 20KでのFPGA資源（BSRAM）逼迫を理由に、MMUはデフォルトビルドの
> 標準仕様から外され、straight-through（論理bank＝物理bank、変換なし）
> マッピングが新しい標準仕様になりました。MMU自体は
> `msxnano-24bit/fpga/G80A/mmu24.vhd`としてオプション機能の形で
> リポジトリに残されており、デフォルトでは無効（`top.v`からインスタンス化
> されない、`MSXNanoTang20K_Z80X24.gprj`でも`enable="0"`）です。
>
> そのため、**このテストプログラムを現在のデフォルトビルドに対してそのまま
> 実行すると、`F0h`/`F1h`ポートが存在しないため全テストがFAIL**します。
> MMUを再度有効化したビルド（詳細は
> [CPU仕様書V8](../../doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md)14.1章参照）に対してのみ、本来の意味でPASSします。
> デフォルトビルド（straight-throughマッピング）の動作確認には、本プログラム
> の`MMU_DATA`書込み(`OUT (F1),A`)部分を使わず、`MMU_DATA[n]=n`相当の
> アクセス（＝各論理bankがそのまま同じ物理bankになる）として読み替えれば
> 同様のテスト目的に流用できます。

MSXnano-Z80X ([msxnano-24bit](../..) リポジトリ、24bit CPU拡張 "Z80X24") の
**Phase5「MMU実機検証」**を、実機(Tang Nano)またはMSXエミュレータ上の
MSX-DOS(2)から起動して確認するための、Z80アセンブリ製テストプログラムです。

同じシナリオを検証するGHDLシミュレーション版テストベンチが
`msxnano-24bit/fpga/G80A/test/tb_phase5_mmu_mapping.vhd` にあります。本プログラム
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

`MMUTest` フォルダで実行します。

```powershell
make
```

`bin\mmutest.com` が生成されます。中間ファイルは `obj` と `BINZ80` フォルダに
生成されます。`make clean` で中間ファイルを削除できます。

`build.bat` は `z80asm` を直接呼び出す簡易スクリプトです(Z88DK同梱の
旧来の `z80asm` 用で、環境によっては使えない場合があります)。標準の
ビルド手順は `make` です。

## MSX上での実行

`bin\mmutest.com` をMSXまたはエミュレータのディスクイメージ(または実SDカード)
へコピーし、MSX-DOSから実行します。

```text
A>MMUTEST
```

## テスト内容

`mmu_test.asm` は以下の8つのテストを順に実行し、各テストの結果と
最後に合計PASS/FAIL数を画面へ表示します。

| # | 内容 |
|---|---|
| Test1 | 論理bank01h→物理bank01hへマッピングし、パターン11hの書込み/読出しを確認 |
| Test2 | 論理bank02h→物理bank02hへマッピングし、パターン22hの書込み/読出しを確認 |
| Test3 | 論理bank03h→物理bank03hへマッピングし、パターン33hの書込み/読出しを確認 |
| Test4-6 | Test1-3で書いた値をまとめて再読出しし、他バンクへの書込みで値が壊れていないか確認 |
| Test7 | エイリアス試験。論理bank01h/02hを同じ物理bank05hへ再マッピングし、どちらからも同じ値が読めることを確認 |
| Test8 | `MMU_DATA[04h]=00h` エイリアス試験。論理bank04hを明示的に物理00h(既存のMSX互換64KB空間)へマッピングし、通常のM0アクセスと一致することを確認 |

全テストがPASSすれば、Phase5で実装したMMU24(F0h/F1h)と
[fpga/top.v](../../fpga/top.v)のSD-RAM配線
(`cpu_sdram_req`/`cpu_sdram_addr`)が、仕様書どおりに動作していることが
実機で確認できます。

## バスアービタの優先順位について(実機検証で発見・修正済み)

Phase5の実機検証初回では、Test1-7が全て読出し値00hでFAILし、Test8のみ
PASSするという症状が発生しました。原因は、SD-RAMコントローラ
([fpga/src/memory.v](../../fpga/src/memory.v))の
物理メモリ調停器(アービタ)が、新設した`cpu_sdram_req`(24bit拡張メモリ)より
既存の`mapper_req`(Memory Mapper)を**常に優先**する実装になっていたためです。

MSX-DOS2は多くの構成でTPA(実行中プログラムの領域)自体をMemory Mapper RAM上に
置くため、本テストプログラムが`(HL)`でアクセスする16bitアドレス(0000h等)は、
拡張メモリアクセスの意図とは無関係に、既存のMemory Mapperデコード条件も
**ほぼ毎回**同時に満たしてしまいます。優先順位が逆だった当初実装では、拡張
メモリへの書込みは実際にはMemory Mapper RAM側へ書き込まれ、読出しは一度も
更新されない`cpu_sdram_dout`(リセット後の初期値=00h)を返していました。

修正として、`memory.v`のアービタで`cpu_sdram_req`を`mapper_req`/
`megaram_req`より**常に優先**するよう変更しました。`cpu_sdram_req`はmode24=M0
の通常MSXソフトでは常に0のため、この優先順位変更は既存のMSX互換動作には
一切影響しません(詳細は
[SDRAMメモリマップ.md](../../doc/jpn/SDRAMメモリマップ.md)2.2章、
[MSX_T80_24bit化_CPU仕様書_V8](../../doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md)14章を参照)。

同様の物理メモリ調停器を持つ実装へZ80X24を移植する場合は、**拡張メモリ用の
バス要求を、既存クライアント(Memory Mapper等)の要求より必ず優先させる**
必要がある点に注意してください。

## 安全上の注意

- 本プログラムが使用する物理bankは **01h, 02h, 03h, 05h のみ**です。これは
  `fpga/top.v` の `CPU_SDRAM_BASE`(0x640000)経由で、既存のMemory Mapper
  (0x000000-)やMegaRAM(0x400000-)とは重ならない安全な領域
  (0x650000-0x7FFFFF、詳細は `doc/jpn/SDRAMメモリマップ.md` 2.2章)に
  収まります。
- M1モード(`ED 91`)でバンクレジスタを設定した状態のままBIOS/DOSコールを
  行うと、BIOS/DOS側が内部で使う `(HL)` 等のアクセスまで拡張メモリへ
  リダイレクトされる危険があるため、本プログラムは「`DI`→M1へ切替→
  メモリアクセス1回→M0へ戻す→`EI`」という最小区間だけ拡張アドレッシング
  を使い、画面出力やBDOS呼出しは必ずM0へ戻してから行います。
- プログラム終了前に、必ずM0へ戻し全バンクレジスタを0クリアしてから
  MSX-DOSへ復帰します(`SAFE_RESET`)。
- Z80X24拡張が入っていない通常のMSX実機/エミュレータ上で実行すると、
  `ED 90`〜`ED 92` や `ED 04/0C/14/1C/24/2C/05/0D/15/1D` は未定義命令
  (多くの実装ではNOP相当)として扱われ、`F0h`/`F1h`ポートも存在しないため
  `IN`は`FFh`を返す想定です。この場合、全テストがFAILと表示されますが、
  これは異常ではなく「拡張機能が存在しない」ことを意味します。

## ファイル構成

- `mmu_test.asm` — テスト本体
- `makefile` — `z88dk-z80asm` + `z88dk-appmake` によるビルド
- `build.bat` — 旧来の `z80asm` を直接呼び出す簡易スクリプト
- `bin/` — ビルド成果物 (`mmutest.com`)
- `obj/`, `BINZ80/` — 中間ファイル・リストファイル
