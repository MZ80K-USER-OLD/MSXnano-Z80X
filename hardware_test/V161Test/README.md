# V161TEST.COM: RST.L / IBR / SYSCALL

V16.1の新命令配置を使うMSX-DOS用の実機テスト。
**最新のSYSCALL追加後RTLを書き込んだFPGA専用。旧FPGAでは実行しないこと。**
CPU RTLの変更は不要で、今回追加したのはテストプログラムと実行検証である。

## 実行

[bin/v161test.com](bin/v161test.com)を実機のディスクへコピーし、MSX-DOSから実行:

```text
A>V161TEST
```

Case 00～19（16進）を表示し、正常時の最終結果は:

```text
PASS=1A FAIL=00
```

1Aは16進で26判定。FAIL時は最初の不一致のoffset/got/wantを16進で表示する。
フリーズした場合は最後に表示されたCaseも記録すること。
命令未対応や分岐先・復帰の故障では、FAIL表示に到達できない可能性がある。
2026-10-25、ユーザー報告で実機 `PASS=1A FAIL=00`（全26判定PASS）を確認。
FPGAビットストリームのハッシュは未取得。IRQ/NMIは下記のとおり対象外。

2026-10-29、拡張SDRAM WAIT制御の内部サイクル停止対策後の実機再試験でも、
ユーザー報告で`PASS=1A FAIL=00`（全26判定PASS）を確認。
新RST.L全8入口、SYSCALL、IBR、通常/境界MSP、M0/M1のNOP動作の回帰確認が完了。
この報告にはDOS復帰の明示確認と書込み済みFPGAイメージのハッシュは含まれない。

## 26判定

| Case（16進） | 内容 |
|---|---|
| 00/01～0E/0F | RST.L 00/08/10/18/20/28/30/38をそれぞれ通常MSP・境界MSPで試験（16判定） |
| 10/11 | SYSCALL CF、I=40、通常MSP・境界MSP |
| 12/13 | SYSCALL FE、I=40、通常MSP・境界MSP |
| 14/15 | SYSCALL FF、I=FF、テーブルFFFF→0000の同一IBRラップ |
| 16/17 | SYSCALL 00、I=40、通常MSP・境界MSP |
| 18/19 | M0/M1で新RST.L全8コードがNOP、ED C6だけが2byte NOPになり、続く3E A6がLD A,A6として実行されること |

主試験はcode=01:8000、IBR=02、handler=02:8100を使う。
RST.Lの各ベクタには同じバンクのhandlerへ移るJP.Lを置く。
異なるcode/handlerバンク間をRET.Lで戻り、マーカー5Aを確認する。

- 通常MSP=02:E000、frame=02:DFFD～DFFF。
- 境界MSP=02:0000、frame=01:FFFD～FFFF。
  バンクborrowを含むpushと、bank01→02のcarryを含むpopを確認。
- テーブルは02:40CF/40D0、40FE/40FF、FFFF/0000、4000/4001。
  frameとテーブルは重ならない。nの×2やbit0マスクは行わない。
- 各試験でマーカー、F=D7、IFF2=0、IBR=02、復帰後MSP24、
  frameのPCL/PCH/PCB、通常SP保持を比較する。
  Case18/19はマーカーA6、frame未書込み（初期値00）を比較する。
- M0へ戻してから通常SPでAFを保存し、MSP上の戻りframeを検査前に壊さない。

比較offsetは0=マーカー、1=F、2=IFF2のP/V bit、3=IBR、
4～6=MSPのL/H/B、7～9=frameのPCL/PCH/PCB、0A～0B=通常SPのL/H。

## 安全範囲と対象外

測定・準備中はDI、表示はM0・バンク初期化後にEIしてBDOSを呼ぶ。
終了時に開始時のI・IBR・MSPを復元し、ペア/IX/IYバンクを00へ戻す。
物理bank00は通常のCOM/DOS領域、拡張bank01/02は試験用として使う。
拡張バンク内の上記コード・ベクタ・テーブル・frame領域は上書きする。
bank03以上へのアクセスは行わない。

M2 IRQ/NMI、IM0→IM1変換、IFF有効時のSYSCALL、ネスト、命令フェッチの64KB境界、
全256個のnは本COMの対象外。旧P1314T/LD24TESTの代わりに
新IRQ/NMIを網羅する試験ではない。M2で割込みは有効にしない。

## ビルドと実行シミュレーション

PowerShellでZ88DKをPATHに入れ、このフォルダで:

```powershell
$env:Path = "D:\Tool\z88dk\bin;" + $env:Path
make
```

リポジトリルートから:

```powershell
& .\fpga\G80A\test\run_v161_com.ps1
```

アセンブルしたCOMそのものを、既存の3物理バンク/BDOSスタブ付き
[テストベンチ](../../fpga/G80A/test/tb_ld24mi_com.vhd)で実行する。
Normal/Fast × WAIT無/有 × 故障注入無/有の8実行を検証。

- 通常4実行: 各`PASS=1A FAIL=00`。
- 故障注入4実行: handlerのLD A,5AをLD A,A5に変え、
  Case00～17がすべて`FAIL offset=00 got=A5 want=5A`、
  Case18/19はPASS、合計`PASS=02 FAIL=18`になることを検証。
- BDOSがレジスタ・Fを破壊するスタブでも比較・出力が正しいこと、
  M0での非同期IRQ、M1/M2でのDI、M0でのみBDOSを呼ぶことも検査。

ログとソース/COM/ログのSHA256は
[verification_data/v161_com](../../verification_data/v161_com)に保存。
実SDRAMやMSX-DOSそのもののシミュレーションではなく、実機PASSの代用ではない。
