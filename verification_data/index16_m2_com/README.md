# I16M2.COM実行回帰

M2での16bit indexed LD実機用COMをT80で実行した記録。
入力命令列と期待値は[共通本体](../../hardware_test/Index16Test/index16_test.asm)の
M2TEST定義時、入口は[index16_m2.asm](../../hardware_test/Index16Test/index16_m2.asm)。

- `fault-false.log`: 通常24判定。期待値`PASS=18 FAIL=00`。
- `fault-true.log`: bank01:FFFF読出しを00に置換。期待値`PASS=00 FAIL=18`。
- `summary.json`: 実行日時、GHDL版、モード、入力COMとソースのSHA-256。

```powershell
& .\fpga\G80A\test\run_index16_com.ps1 -M2
```

ログは再実行で上書きする。完了状態、日時、ソースハッシュを照合する。
モデルはbank00/01/02のみ。全24回のM2移行、測定中DI、M0でのBDOS、
周期的IM1割込みと正常終了をアサートする。
COM自身は転送状態に加えMSP24と通常SPの保持も比較する。
物理SDRAM・実際のDOS/BIOS・WAIT調停を再現するものではない。
M2コードはbank00で実行するため、非ゼロPCバンクや命令フェッチ境界の試験ではない。
上記ログ・サマリーはシミュレーションの記録であり、以下の実機報告とは区別する。

## 実機結果（ユーザー報告）

2026-10-24、I16M2.COMで`PASS=18 FAIL=00`（全24判定PASS）の報告あり。
ユーザー入力の「i16M2.con」は文脈上I16M2.COMの結果として記録。
生ログ・ビットストリームのハッシュは未取得、DOS復帰は明示報告なし。
試験対象は上記のDI/M2・bank00コードでのindexed LDと状態保持に限る。
