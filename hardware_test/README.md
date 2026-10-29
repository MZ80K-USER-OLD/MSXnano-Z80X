# 実機検証用テストプログラム (hardware_test/)

MSXnano-Z80X ([msxnano-24bit](..)) の24bit CPU拡張 "Z80X24" について、各
Phaseの実装内容を実機(Tang Nano)またはMSXエミュレータ上のMSX-DOS(2)から
起動して確認するための、Z80アセンブリ製テストプログラム群です。

各GHDLシミュレーション用テストベンチ([fpga/G80A/test/](../fpga/G80A/test))
が実装の正しさを机上で検証するのに対し、ここに置くテストプログラムは、
実機固有の非同期割込みタイミング・実際のSDRAM/メモリ配置・MSX-DOSの実行
環境など、シミュレーションでは再現しきれない要素を含めて実地で検証します。

## ビルドに必要な環境(全テストプログラム共通)

- Windows
- Z88DK (`D:\Tool\z88dk` にインストールされている想定)。`z88dk-z80asm` /
  `z88dk-appmake` を使用。
- `make` (GnuWin32 make等)
- 実行環境としてZ80X24拡張済みMSXnano実機、またはMSX-DOS(2)が動く
  MSXエミュレータ

各テストプログラムのフォルダで`make`を実行すると、`bin/`配下に実行形式の
`.COM`ファイルが生成されます。中間ファイル(`obj/`、`BINZ80/`、`bin/`)は
本リポジトリには含めていません([.gitignore](.gitignore)で除外、ソースから
いつでも再生成可能なため)。

## WAIT修正後の実機回帰結果（2026-10-29）

拡張SDRAM WAIT制御の内部サイクル停止対策後、ユーザーから以下の実機PASSが
報告された。今回選定した既存COMの機能回帰8本と、IRQ/HALT専用2本はすべて合格。

| COM | 実機結果 |
|---|---|
| [V161TEST](V161Test/README.md) | `PASS=1A FAIL=00` |
| [P24TEST](Push24Test/README.md) | `PASS=0D FAIL=00` |
| [LD24MI](Ld24MemIndirectTest/README.md) | `PASS=13 FAIL=00` |
| [P12TEST](P12Test/README.md) | `PASS=08 FAIL=00` |
| [I16M2](Index16Test/README.md#m2実機用-i16m2com) | `PASS=18 FAIL=00` |
| [I24M2](Index24Test/README.md) | `PASS=18 FAIL=00` |
| [INDEX16](Index16Test/README.md) | `PASS=18 FAIL=00` |
| [INDEX24](Index24Test/README.md) | `PASS=18 FAIL=00` |
| [I161TEST](V161IRQTest/README.md) | `PASS=04 FAIL=00`、トレース`ABCDVHDVHM` |
| [H161TEST](V161HALTTest/README.md) | `PASS=03 FAIL=00` |

INDEX16に相当する報告の原表記は`INDEC16`。ここではINDEX16として整理した。
追加説明により、GowinでFPGAのSRAMへ書き込む運用で、毎回電源再投入している
ことを確認した。リセット後にもSOFARUNからスペースマンボウを起動して
プレイできたとの報告あり。電源再投入・リセット後の動作を一律に未確認とは扱わない。
同日、リセット直後にLD24MIを実行し、`PASS=13 FAIL=00`となったとの
追加報告あり。リセット後初回の拡張メモリアクセス回帰も合格。
その他のCOMが起動後最初の試験だったか、反復回数、DOS復帰の明示確認、
書込み済みFPGAイメージ/実行COMのハッシュは未記録。
長時間試験、開発側の回帰再実行は、この集計だけで完了扱いにしない。

同日、ユーザーから実機でSOFARUNを実行し、スペースマンボウを起動して
プレイできたとの報告あり。WAIT修正後の通常MSXソフトの代表的な動作回帰も確認した。
プレイ時間、音源の個別確認、全ステージや他ソフトの網羅確認は報告されていない。
原因・対策は[WAIT制御の調査メモ](../doc/jpn/M2割込みフリーズ_WAIT制御の原因とeZ80開発への教訓_2026-10-29.md)を参照。

## テストプログラム一覧

**V16.1移設の注意**: P12TESTはJP.M2=ED9Bの新COMへ再ビルドしたため旧FPGAでは実行しない。
P1314T/LD24TESTは旧命令専用で現RTLでは実行禁止、通常ビルドも停止する。
各READMEの互換性表示を優先する。2026-10-24、新JP.M2版P12TESTは
ユーザー報告で実機 `PASS=08 FAIL=00` を確認（ビットストリームのハッシュは未取得）。
新コード用のM2割込み実機COMは[I161TEST](V161IRQTest/README.md)を使い、
旧P1314Tをそのまま実行しない。

| フォルダ | 対象Phase | 検証内容 | 実機検証状況 |
|---|---|---|---|
| [V161IRQTest](V161IRQTest) | V16.1 IRQ | 実VDPのIM1/IM2 IRQ、IBR、4byte frame、RETI.Lのマスク継続/EI再武装、通常/境界MSP | 2026-10-29、WAIT修正後の実機で`PASS=04 FAIL=00`。NMI/RETI外部通知は対象外 |
| [V161HALTTest](V161HALTTest) | V16.1 HALT | M0/M1/M2で各2回のEI/HALT、IM2 IRQ、フレーム・復帰先の検査 | 2026-10-29、WAIT修正後の実機で`PASS=03 FAIL=00` |
| [V161Test](V161Test) | V16.1 | 新RST.L全8ベクタ、IBR、SYSCALL、3byte frame/RET.L、MSP境界、M0/M1 NOP | 2026-10-25、ユーザー報告で実機 `PASS=1A FAIL=00`（全26判定PASS）。Normal/Fast・WAIT・故障注入の実行シミュレーションも確認済み |
| [Index24Test](Index24Test) | V15第2段階 | M1の24bit indexed LD 12命令、3byte境界転送・負変位・ペア/バンク/F保持 | 2026-10-24 実機で全24判定PASS (`PASS=18 FAIL=00`)、ユーザー報告。COM実行回帰・故障注入も確認 |
| [Index16Test](Index16Test) | V15第1段階 | M1の16bit indexed LD 12命令、IX/IY、ペア/フラグ/バンク保持、2byteの境界またぎと負変位 | 2026-10-24 実機で全24判定PASS (`PASS=18 FAIL=00`)、ユーザー報告。COM実行回帰・故障注入も確認 |
| [I16M2 / I24M2](Index16Test/README.md#m2実機用-i16m2com) | V15 M2実機確認 | 16bit/24bit indexed LD各24判定、MSP24・通常SP保持、M0復帰 | 2026-10-24 両COMとも実機で`PASS=18 FAIL=00`、ユーザー報告。通常・故障注入シミュレーションも期待どおり |
| [LD24Test](LD24Test) | Phase7 (LD24系命令) | HL24 hub / MSP24 / IVR24 / NVR24 のレジスタ間24bit転送 | 未実行(ビルド確認のみ。実機実行はまだ行われていない) |
| [MMUTest](MMUTest) | Phase4/5/6 (MMU) | MMU_DATA/MMU_ATTR.W、論理→物理bank変換・write protection | 実機検証済み(MMU有効時点、全8テストPASS) |
| [Push24Test](Push24Test) | Phase9 (PUSH24/POP24) | MSP24への3byte push/pop、bank境界またぎ | バス分離RTLでTest7/8を含む全13判定が実機PASS (`PASS=0D FAIL=00`) |
| [P12Test](P12Test) | Phase12 (モード間制御) | `JP.M0/M1/M2`/`CALL.M0/M1/M2`/`RET.M` | 2026-10-24、新JP.M2=ED9B版も実機 `PASS=08 FAIL=00`（ユーザー報告） |
| [P1314Test](P1314Test) | Phase13(M2割込み)/Phase14(RST.L) | `RST.L`、M2のIRQ→`IVR24`→`RETI.L`(実機の本物の非同期VDP割込みを使用) | 実機検証済み(全7チェックPASS、`PASS=07 FAIL=00`) |
| [Ld24MemIndirectTest](Ld24MemIndirectTest) | 追加命令(ED00/01/03/08、2026-10-19実装) | 24bitメモリ間接転送、bank境界またぎ、複数パターン読書き | バス分離とSDRAM要求受理修正後、2026-10-23実機でリセット直後も全19判定が安定PASS (`PASS=13 FAIL=00`) |

各テストプログラムの詳細なビルド手順・テスト内容・安全上の注意・開発経緯
(実機テストで見つかった問題と対応)は、それぞれのフォルダ内の`README.md`を
参照してください。

## 実機テストで見つかった、Z80X24拡張とは独立した知見

テストプログラムの開発・実機検証を通じて、Z80X24拡張自体のバグではなく、
MSX-DOSプログラミング一般に関わる以下の知見が得られました(詳細は
[P1314Test/README.md](P1314Test/README.md)の「開発経緯2/3」参照)。

- MSX-DOSのアプリケーションからは、BIOS ROM内のルーチンを`CALL`で直接
  呼び出すことはできない(正しくは`CALSLT`(`001CH`、MAIN ROM)経由でスロット
  を指定した間接呼出しが必要)。
- MSX-DOSのBDOS(`CALL 5`)は、副作用として内部で`EI`を実行し、呼出し前の
  割込み禁止状態を保存・復元しない。`DI`/`EI`やIFF状態を跨いで観測したい
  区間の間にBDOS呼出しを挟んではならない。
