# I24M2.COM実行回帰

M2での24bit indexed LD実機用COMをT80で実行した記録。
入力命令列と期待値は[共通本体](../../hardware_test/Index16Test/index16_test.asm)の
M2TEST・INDEX24定義時、入口は[index24_m2.asm](../../hardware_test/Index24Test/index24_m2.asm)。

- `fault-false.log`: 通常24判定。期待値`PASS=18 FAIL=00`。
- `fault-true.log`: bank01:FFFF読出しを00に置換。期待値`PASS=00 FAIL=18`。
- `summary.json`: 実行日時、GHDL版、モード、入力COMとソースのSHA-256。

```powershell
& .\fpga\G80A\test\run_index16_com.ps1 -Transfer24 -M2
```

検証条件・限界・記録の確認方法は[16bit版](../index16_m2_com/README.md)と共通。
上記ログ・サマリーはシミュレーションの記録であり、以下の実機報告とは区別する。

## 実機結果（ユーザー報告）

2026-10-24、I24M2.COMで`PASS=18 FAIL=00`（全24判定PASS）の報告あり。
生ログ・ビットストリームのハッシュは未取得、DOS復帰は明示報告なし。
試験対象はDI/M2・bank00コードでのindexed LDと状態保持に限る。
