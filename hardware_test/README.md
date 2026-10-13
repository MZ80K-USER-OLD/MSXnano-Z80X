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

## テストプログラム一覧

| フォルダ | 対象Phase | 検証内容 | 実機検証状況 |
|---|---|---|---|
| [LD24Test](LD24Test) | Phase7 (LD24系命令) | HL24 hub / MSP24 / IVR24 / NVR24 のレジスタ間24bit転送 | 未実行(ビルド確認のみ。実機実行はまだ行われていない) |
| [MMUTest](MMUTest) | Phase4/5/6 (MMU) | MMU_DATA/MMU_ATTR.W、論理→物理bank変換・write protection | 実機検証済み(MMU有効時点、全8テストPASS) |
| [Push24Test](Push24Test) | Phase9 (PUSH24/POP24) | MSP24への3byte push/pop、bank境界またぎの既知の問題を含む | 実機検証済み(bank境界またぎを除く) |
| [P12Test](P12Test) | Phase12 (モード間制御) | `JP.M0/M1/M2`/`CALL.M0/M1/M2`/`RET.M` | 実機検証済み(全8チェックPASS) |
| [P1314Test](P1314Test) | Phase13(M2割込み)/Phase14(RST.L) | `RST.L`、M2のIRQ→`IVR24`→`RETI.L`(実機の本物の非同期VDP割込みを使用) | 実機検証済み(全7チェックPASS、`PASS=07 FAIL=00`) |

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
