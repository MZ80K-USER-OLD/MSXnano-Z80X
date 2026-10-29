# INDEX24.COM実行回帰

[実機テスト](../../hardware_test/Index24Test/README.md)をビルドしたCOMをT80で実行する。
入力・期待値は[共通テスト本体](../../hardware_test/Index16Test/index16_test.asm)の
INDEX24定義時の処理を参照。

- `fault-false.log`: 全24判定の通常実行。期待値PASS=18 FAIL=00。
- `fault-true.log`: bank01:FFFF読出しを00にする故障注入。期待値PASS=00 FAIL=18。
- `summary.json`: GHDL版、検証日時、入力COM・ソースのSHA-256。

再実行は実機テストREADMEを参照。ログは上書きするため、
日時とハッシュを照合し、中断時の一部ログを成功結果と扱わない。
上記ファイルはシミュレーションの記録であり、以下の実機報告とは区別する。

## 実機結果（ユーザー報告）

2026-10-24、INDEX24.COMで`PASS=18 FAIL=00`（M1の全24判定PASS）との報告あり。
生ログ・ビットストリームのハッシュは未取得、DOS復帰は明示報告なし。
M2の実機確認を意味しない。
