# I161TEST.COM: V16.1 M2 VDP IRQ / IBR / RETI.L

最新のSYSCALL追加後RTL専用。旧FPGAと旧P1314T.COMでは代用できない。
CPUコアの命令処理ではなく、[top.v](../../fpga/top.v)の拡張SDRAM WAIT制御を
修正したFPGAビットストリームで、下記の実機PASSを確認済み。

M0/M1/M2でHALTを使ったIRQ待ちを比較する独立試験は
[H161TEST.COM](../V161HALTTest/README.md)を使用する。
本COMの有限ループ試験とは別に実行できる。

## 実機での実行

[bin/i161test.com](bin/i161test.com)をディスクへコピーし、MSX-DOSから実行する。

```text
A>I161TEST
```

通常の4ケースに入る前に、IRQ受付設定を行わないタイムアウト予備試験を実行する。
`No-handler timeout: PASS (VRAM TM1abc2345OK)`が表示されてからCase 00へ進むこと。
この予備試験ではDIのままVDP IRQを無効化し、IM/IBR/MSP/ベクタ/ハンドラを設定せずに
M2へ移行する。M2上ではDEの有限カウンタとVDP出力だけを使い、bank00上の状態変数は
読み書きしない。有限待ちを完了してM0へ戻れたときだけPASSを表示し、
完了できなければ後続ケースも開始しない。

4ケースの前に`Arming case 00`～`03`を表示する。
正常時の最終期待値:

```text
PASS=04 FAIL=00
```

測定中はBDOSを呼ばず、VRAM上の文字で停止段階を示す。
割込みが来ない場合は有限ループでタイムアウトしてFAILにする。
分岐・復帰自体が故障している場合には表示まで戻れないため、
停止時は最後のArming/Case表示を記録しリセットすること。

## 実機確認結果（2026-10-29）

ユーザー報告:

```text
PASS=04 FAIL=00
ABCDVHDVHM
```

IM1/IM2とMSP24バンク境界条件を組み合わせた全4ケースがPASS。
修正前のM2有限ループ中の停止は解消した。
タイムアウト予備試験を通過しなければ後続ケースを開始しない構成なので、
今回の最終PASSは予備試験の完了も示す。ただし、予備試験の
`TM1abc2345OK`全文は今回の報告には含まれない。
同時に実行した[H161TEST.COM](../V161HALTTest/README.md)も`PASS=03 FAIL=00`。

## ケースと確認項目

| Case | 割込みモード | 初期MSP24 | IRQの4byte frame |
|---|---|---|---|
| 00 | IM1 | 02:E000 | 02:DFFC～DFFF |
| 01 | IM1 | 02:0000 | 01:FFFC～FFFF |
| 02 | IM2、I=FF | 02:E000 | 02:DFFC～DFFF |
| 03 | IM2、I=FF | 02:0000 | 01:FFFC～FFFF |

コードは01:8000、IBR=02、ハンドラは02:8181。
IM1は02:0038のJP.Lからハンドラへ移る。
IM2は02:FF00～FFFFと02:0000の257byteを81で埋め、
任意のvector8でも8181に解決する安全な表を用意する。
現基板の割込み応答データは[top.v](../../fpga/top.v)の未選択バス値FFを想定するため、
通常は02:FFFF→02:0000を読む。
COM自身ではvector8を直接記録しないので、実機PASSだけで
応答値FFやFFFFラップを独立に証明するものではない。
実行シミュレーションではFFを駆動し、両物理読出しアドレスを直接照合する。

各ケースの一連の検証:

1. DI下でコード・表・MSP・IBR・IMを設定し、VDP R#1 bit5を有効にする。
2. M2でEIしてVDP IRQを待つ。ハンドラで入場時MSPと4byte frameを記録し、
   VDP status port 99hを読んで要因をACK、回数を加算してED F3のRETI.Lで戻る。
3. IFF2=0を確認し、EIせず65,535回の待ちループを実行する。
   この間の回数が1のままであることを確認する。
4. 再びEIして2回目のIRQを受理すること、RETI.L後もIFF2=0であることを確認する。
5. M0に戻り、回数=2、保持期間の回数=1、MSP24/通常SP/IBR保持、
   最終frameのPCB=01・MODE=02・PCH=80・PCLが2回目の待ちループ内であること、
   handler入場時MSP=初期MSP-4、タイムアウトなし、handlerマーカー5Aを比較する。

ハンドラはEX AF,AF' / EXXで待ちループのレジスタを退避し、
PUSH/POP/CALLを使わずに処理する。IFF2を読むメイン側のPUSH/POPは
RETI.L復帰後であり、記録済みframeの上書きを検査に使わない。
このCOMは全Fビット保持の独立した検証ではない。

## FAIL表示

最初の不一致を`offset=xx got=xx want=xx`で表示する。

| Offset（16進） | 意味 |
|---|---|
| 00 | 受理したIRQ回数、期待02 |
| 01 | EIしない待機後のIRQ回数、期待01 |
| 02/03 | 1/2回目のRETI.L後のIFF2（P/V bit）、期待00 |
| 04～06 | 復帰後MSPのL/H/B |
| 07 | IBR、期待02 |
| 08/09 | 通常SPのL/H |
| 0A～0D | 記録frameのPCL/PCH/PCB/MODE |
| 0E～10 | handler入場時MSPのL/H/B |
| 11 | タイムアウト、期待00 |
| 12 | 最終frameのPCL範囲検査、期待01 |
| 13 | handlerマーカー、期待5A |

## 環境・復元・制約

- MSX-DOSの通常のVDP環境を前提とする。他ソフトがVDPを並行操作しない状態で実行する。
- 直接I/OでVDPを操作する。BIOS ROMへの直接CALLは行わない。
  R#1はBIOSシャドウRG1SAV（F3E0h）を保存して使い、各ケース終了時に復元する。
  VRAM先頭のマーカー文字をテスト中に一時上書きする。画面モードは変更しない。
  VDP status selectorはS#0を明示指定する。
- 各ケース終了時にM0・IM1・開始時I・R#1へ戻し、バンクを00にしてからEI/BDOSへ進む。
  終了時には開始時IBR/MSPも復元する。
  開始時IMは読み出せないためIM1へ戻す（通常MSX-DOS環境を前提）。
- bank00は通常のCOM/DOS領域、bank01/02は上記コード・ベクタ・表・frameに使用する。
  これらの拡張領域は上書きする。bank03以上は使わず、frameと表は重ならない。
- 待機中はVDPの通常OS割込み処理を呼ばないため、測定中は時計・キー走査等が一時停止する。
  外付けデバイス等、VDP以外のIRQ源は本テストではサービスしない。
- 本物のNMI/RETN.L、IM0からM2への遷移、ネストIRQ、
  ハンドラ内PUSH/POP/CALL、RETI外部通知は対象外。
  NMI入力は現基板でソフトウェアから起動できない。
- WAITモデルやCPUコアの試験結果は実SDRAM・MSX-DOSそのものの検証の代用ではない。
- MSX-DOS BDOSやBIOS呼出しは、呼出し前がDIでも復帰時に割込みを許可する場合がある。
  このCOMの表示用BDOS関数09h/02hの直後は明示的にDIする。
  M2 IRQを有効にする測定区間は、M0へ戻るまでBDOS/BIOSを一切呼ばない。
  シミュレーション用BDOS stubも復帰前にEIし、この性質を含めてテストする。

### Case 00停止時のVRAM診断マーカー

テスト開始直後の予備試験は、VRAM先頭に段階マーカーを出す。ループ内ではVDP出力を
せず、最初の命令境界とカウンタの節目だけを記録する。正常なトレースは
`TM1abc2345OK`。

| マーカー | 意味 |
|---|---|
| `T` | M2移行前 |
| `M` | M2到達 |
| `1` | DE=0100hを設定し、最初の減算を開始 |
| `a` | 最初の`DEC DE`完了 |
| `b` | 最初の`LD A,D / OR E`によるゼロ判定完了 |
| `c` | 最初の`JR Z`が非ゼロ側へ進んだ |
| `2` / `3` / `4` / `5` | DEがそれぞれ00C0h / 0080h / 0040h / 0001hに到達 |
| `O` | カウンタ0を検出 |
| `K` | M2内の完了マーカー出力まで到達 |

この段階はIRQ handlerを登録せずにタイムアウト経路を実機確認する。
予備試験の待ち回数はIRQ本試験より短い固定256回。最後に表示された文字で停止位置を絞る。
`K`まで表示された後にDOS上のPASSが出なければ、M2からM0への復帰経路を次に調べる。

各ケース開始時にVRAM先頭の12文字を消去する。進行文字は連続して書く:

| 画面表示 | 到達段階 |
|---|---|
| `A` | JP.M2直前。`B`が出なければM2遷移先未到達 |
| `ABC` | M2到達・EI実行後。IRQ受付待ち |
| `ABC1` | 最初のIRQ待ちループを完走。IRQを受理していない |
| `ABC12` | IRQなしで割込み禁止保持期間のループも完走 |
| `ABCV` | 割込み受付後、IBRのIM1/IM2ベクタ先頭へ到達 |
| `ABCVH` | ベクタからIBR割込みハンドラへ到達 |
| `ABCVHD` | 最初の割込みからRETI.Lで戻り、IFF禁止保持期間を通過 |
| `ABCVHDVHM` | 2回のIRQ・RETI.Lを経てM0へ復帰 |

IRQのタイムアウトでは`!`と2文字の診断値を追加する。1文字目はS#0 bit7で、
`P`はVDP IRQ pending、`N`はpendingなし。2文字目はLD A,Iが示すIFF2で、`E`は有効、`D`は無効。

| 表示例 | 意味 |
|---|---|
| `ABC12!NE` | IRQ pendingなし、IFF2有効。VDP IRQ生成/enableまたは配線を調べる |
| `ABC12!PE` | IRQ pendingだがIFF2有効。CPUのIRQ受付経路を調べる |
| `ABC12!PD` | IRQ pending、IFF2無効。CPU受付後のベクタ処理を調べる |
| `ABCV!PD` | ベクタ入口後、ハンドラへ分岐できていない疑い |
| `ABCVH`で停止 | ハンドラのstatus read、frame処理、RETI.Lを調べる |
| `ABCVHD!NE` | 1回目は復帰したが2回目のIRQが発生していない |

`ABC`の後に`1`も出ない場合はIRQとは別にM2上の命令進行・メモリアクセス・WAIT停止を疑う。
`ABC1`で止まる場合は保持ループの進行を調べる。`ABC12!NE`まで出ればCPUは有限待ちを完走しており、
VDP IRQ pendingがない原因に絞れる。

MSX-DOSのテキスト画面（SCREEN 0）を前提とする。VRAM先頭のネームテーブルに書くため、
先頭行の文字を一時的に上書きする。BIOS/BDOSは呼ばず、VDPポート99hで先頭アドレスを
設定し、98hへ診断文字を連続出力する。IRQ有効化前にstatus selectorをS#0にする。

## ビルド・実行シミュレーション

このフォルダで:

```powershell
$env:Path = "D:\Tool\z88dk\bin;" + $env:Path
make
```

リポジトリルートから:

```powershell
& .\fpga\G80A\test\run_v161_irq_com.ps1
& .\fpga\G80A\test\run_v161_irq_com.ps1 -NoInterrupt
& .\fpga\G80A\test\run_v161_irq_com.ps1 -Smoke
```

ランナーはGHDL用の一時COMを`SIMULATION`定義で組み立てる。
ハードウェア用の`bin\i161test.com`は全長の16bit待ちカウントを維持し、変更しない。
シミュレーション用だけ各待ちを4096反復へ短縮し、同じ割込み・状態検査の経路を保ったまま
長いbusy-waitのGHDL実行時間を抑える。一時COMのSHA256は実行記録に保存される。

COMそのものを[共有BDOSベンチ](../../fpga/G80A/test/tb_ld24mi_com.vhd)で実行する。
VDPは周期的なlevel IRQ、R#1書込み、status読出しによるACKの最小モデル。
M2のIRQは割込み応答だけでは解除しない。

通常行列はNormal/Fast × WAIT無/有 × handler故障注入無/有の8実行。
故障注入ではhandlerのマーカー5AをA5に変え、
各ケースが`FAIL offset=13 got=A5 want=5A`、合計`PASS=00 FAIL=04`になることを検査する。
さらにM2 IRQを発生させない負例を1実行し、有限待機後に全4ケースで回数不足を報告することを検査する。
正常実行ではM2 IRQ受理8回・frame書込み32byte・IM2表読出し8byteを直接検査する。

通常4実行はすべて`PASS=04 FAIL=00`、
故障注入4実行はすべて`PASS=00 FAIL=04`で期待どおり完了した。
IRQなし負例も全4ケースの回数不足を報告し、DOS終了まで完走した。
負例専用のベンチ条件修正後、正例1実行も再確認済み。
既存V161TESTの8実行とindexed COM4種類の通常/故障注入回帰も通過した。

結果・COM/ソース/ログSHA256は
[通常行列](../../verification_data/v161_irq_com/summary.json)と
[IRQなし負例](../../verification_data/v161_irq_com_no_irq/summary.json)に保存する。
`-Smoke`はNormal/WAITなし/故障なしの1実行を
[専用記録](../../verification_data/v161_irq_com_smoke/summary.json)へ保存し、
全8実行の記録を上書きしない。長い実機用待機ループをCOMそのままで実行するため、
シミュレーションには時間がかかる。
