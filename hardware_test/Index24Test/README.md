# INDEX24.COM: V15 24bit indexed LD 実機テスト

**今回追加した24bit indexed LD対応RTLでFPGAを再ビルド・書込みしてから実行する。**
INDEX16だけ対応した旧ビットストリームでは実行しない。
旧命令コード移設、IBR/RST変更は含まない。
2026-10-24、ユーザーから実機で`PASS=18 FAIL=00`（全24判定PASS）の報告あり。
DOS復帰は明示報告なし。M2版の結果は下記I24M2.COMの節を参照。

MSX-DOSから`INDEX24`を実行する。期待する集計は:

```text
PASS=18 FAIL=00
```

18は16進数で24判定。DOSへの復帰も確認する。

## 内容

M1のIX/IY × BC/DE/HL × 読書き12命令を、以下の2条件で実行する。

| ケース | index＋変位 | 3byteの転送アドレス |
|---|---|---|
| 00〜0B | 01:FFFF＋00 | 01:FFFF、02:0000、02:0001 |
| 0C〜17 | 02:0000＋FF(-1) | 01:FFFF、02:0000、02:0001 |

各12件は読出し6件、書込み6件。BC、DE、HLの順に、それぞれIX、IYを実行する。
対象コードは読出しDD/FD 08/10/18 d、書込みDD/FD 20/28/30 d。
読出しは67:1234からA5:BEEFへ変更する。
書込みはメモリの34 12 98をEF BE 67へ変更する。
IX/IY、他のペアと各バンク、F=D7、転送メモリを比較する。

比較は[INDEX16](../Index16Test/README.md)と共通のoffset00〜11に、
offset12（02:0001、3byte目）を追加した19byte。
読出し時は対象ペアのバンクがA5、それ以外のペアバンクは67。
書込み時はすべてのペアバンク67を保持する。

測定はDI/M1、表示はM0へ戻して各バンクをクリアし、EI後に行う。
テスト用に触るメモリはbank00/01/02のみ。
M2・WAIT・3byte目だけが境界をまたぐ場合は[RTL試験](../../verification_data/v15_index24/README.md)が対象で、
このCOMの実機試験範囲には含まない。

## ビルドとシミュレーション

z88dk-z80asmとmakeがPATHにあるWindows環境で、このフォルダから`make`。
`bin\index24.com`を生成する。
ソースはINDEX24定義付きでINDEX16の共通テスト本体を取り込む。

リポジトリルートからCOM実行回帰:

```powershell
& .\fpga\G80A\test\run_index16_com.ps1 -Transfer24
```

通常実行とbank01:FFFFの読出しを00にする故障注入を行う。
正常時PASS=18/FAIL=00、故障注入ではPASS=00/FAIL=18を期待する。
実際のCOMをT80で動かし、比較・表示・BDOS・DI・割込み・終了も確認する。
物理SDRAMや実際のDOS/BIOSを再現するものではない。
[ログとハッシュ](../../verification_data/index24_com/README.md)を保存する。

## M2実機用 I24M2.COM

同じ`make`で`bin\i24m2.com`も生成する。
MSX-DOSから`I24M2`を実行し、`PASS=18 FAIL=00`（24判定）とDOS復帰を確認する。
今回のindexed LD対応FPGAを使う。CPU RTLの追加変更は不要。
2026-10-24、ユーザーからI24M2.COMの実機結果`PASS=18 FAIL=00`（全24判定PASS）の報告あり。
DOS復帰は明示報告なし。対象外の非ゼロPCバンク等まで確認したものではない。

M1版と同じ転送をDI/M2で行う。コードと専用32byteスタックはbank00のCOM内に置く。
MSP24初期化、SP/MSP24保持、M0復帰と表示、試験範囲の制限は
[I16M2](../Index16Test/README.md#m2実機用-i16m2com)と同じ。
従来19byteに5byteを追加して比較し、
FAIL offset13/14/15はMSP24低・高・バンク、16/17は通常SP低・高（16進数）。
MSP24は試験用の値のまま終了する。

```powershell
& .\fpga\G80A\test\run_index16_com.ps1 -Transfer24 -M2
```

通常・故障注入のログは[M2専用フォルダ](../../verification_data/index24_m2_com/README.md)へ保存。
