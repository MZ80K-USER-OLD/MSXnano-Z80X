# V16.1 SYSCALL

## 実装範囲

`ED C6 n`はM2専用の3byte命令。
即値nをそのまま使い、`{IBR,I,n}`からlittle-endian target16を読み、
`{IBR,target16}`へ分岐する。nの×2やbit0マスクは行わない。
`IBR:FFFF`の次は同じ`IBR:0000`へラップし、IBRにはcarryしない。

MSP24には戻りPC24の3byteを保存する。書込み順はPC_B,PC_H,PC_L、
メモリの昇順配置はPC_L,PC_H,PC_B。RET.Lで復帰する。
MODE、IBR、F、IFFを変更しない。IRQ/NMIの4byte frameとは異なる。

M0/M1はユーザー確認済み方針に従い、従来と同じくED C6の2byteだけをNOPとする。
n相当の次byteは通常命令として実行する。3byte NOPにはしない。

IM2とテーブルアドレス設定・下位16bitインクリメントの経路を共用する。
operand読出し後の3byte pushを追加し、return PCを変更せずに2byteテーブルを読む。
Fastコアはoperandサイクルが3Tなので最初のMSP decrementをT2/WAIT解除時に行い、
Normalは4Tに延長したoperandサイクルのT3で行う。
これはNormalで更新後MSPを使える一方、Fastでは同一エッジに更新前MSPを読まないための調整。

## 再実行

リポジトリルートのPowerShell:

```powershell
& .\fpga\G80A\test\run_v161_interrupt.ps1 -Syscall
& .\fpga\G80A\test\run_v161_interrupt.ps1
```

- [共有テストベンチ](../../fpga/G80A/test/tb_v161_interrupt.vhd)
- [実行ランナー](../../fpga/G80A/test/run_v161_interrupt.ps1)
- [条件・出力・合否](results.jsonl)
- [件数・日時・GHDL版・ソース/結果SHA256](summary.json)

208条件すべてPASS:

- M2: 192条件。Normal/Fast × IBR=00/01/02 × n=CF/FE/FF/00 ×
  MSP通常/境界 × WAIT有無 × IFF無効/有効。
  n=FFではI=FFを使いテーブルFFFFの同一バンクラップを検査。
  その他はI=40とし、奇数・偶数・ゼロをそのまま使うことを検査する。
- M0/M1: 各8条件。Normal/Fast × WAIT有無 × IFF無効/有効。
  `ED C6 3E A6`がNOPの後に`LD A,A6`として実行されることをメモリへ保存して照合する。
  MODE/IBR/F/IFF/通常SP/MSP保持、テーブル読出しがないことも検査する。

独立した物理bank00/01/02の3バンクのみを使用する。
コードとIBRは異なるバンク。MSPの境界・テーブルの配置は
[IBR割込み検証](../v161_interrupt/README.md#物理メモリと境界配置)と同じ衝突回避規則を使う。
M2のreturn PCは元のコードバンクの1003であり、各frame書込みの物理アドレスと値を直接検査する。
RET.Lの復帰バンク、MODE、SP/MSP、IBR、F=D7、IFF有効/無効保持を検査する。
初期IMは2。本SYSCALL試験自体はIRQ/NMIを発生させない。

IM0/1/2 IRQ・NMIの512条件は別途共用経路の回帰として再実行する。
新RST.L/通常RST/IM0の各行列、indexed COM4種類の通常・故障注入、
モード制御/M2基本/CALL-RET.L/PUSH24-POP24も回帰対象。

## 回帰・合成結果

- SYSCALL: 208/208 PASS（M0=8、M1=8、M2=192）。
  M2のテーブル開始アドレス4種は各48条件、FFFFラップも48条件。
- IRQ/NMI: 512/512 PASS。
- RST.L: 160/160 PASS、通常RST: 96/96 PASS、IM0: 270/270 PASS。
- indexed COM4種類: 通常は各`PASS=18 FAIL=00`、
  故障注入は各`PASS=00 FAIL=18`（期待どおり）。
- モード制御/M2基本/CALL-RET.L/PUSH24-POP24: 各PASS。

Gowin合成完了: Logic **17,777 / 20,736（表示86%）**。
Logic欄の内訳は15,768 LUT、1,631 ALU、63 RAM16。
前回IBR割込み実装の17,692から+85。
これは合成レポートのLogic使用量であり、純LUT数や配置配線後の使用率とは区別する。
ソースSHA256と合成レポートSHA256は[synthesis.json](synthesis.json)に記録。

## 制限・互換性

命令フェッチ自身の64KB境界越え、ネストしたSYSCALL、
SYSCALL実行中に到来するIRQ/NMI、BUSRQ、全n=256通り、実SDRAM、
RETI外部通知は本試験の対象外。
M2で割込みを有効にする場合は、IBRに4byte frame対応IRQ/NMIハンドラも必要。
SYSCALLの3byte frameをRETI.L/RETN.Lで戻してはならない。

旧P1314T/LD24TESTは引き続き新RTLと非互換であり実行しない。
後続で[RST.L/IBR/SYSCALL用V161TEST.COM](../../hardware_test/V161Test/README.md)を作成した。
COMそのものの実行シミュレーションに加え、2026-10-25にユーザー報告で
実機 `PASS=1A FAIL=00`（全26判定PASS）を確認した。IRQ/NMIはCOMの対象外。
本記録の合成実行では配置配線・STA・ビットストリーム生成を行っていない。
ユーザー実機のビットストリームハッシュは未取得。
