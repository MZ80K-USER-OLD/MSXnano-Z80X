# V16.1 IM0予防措置のRTL検証

## 実装範囲

- M0/M1→M2のMODE更新を共通の次状態変数に集約し、同じエッジでIM0をIM1へ変換。
- IM1/IM2とM2→M2ではIM設定を保持。M0/M1へ戻ってもIM1を保持。
- ED 46/4E/66/6EはM0/M1でIM0、M2でIM1を設定。
- ED 4EをIM0へ戻すためRETI.LをED F3へ移設。旧コードとの別名互換はなし。
- 後続のRST.L移設に合わせ、JP.M2の試験コードをED 9Bへ更新し再実行した。
  新RST.L/IBR読書きの範囲は[移行記録](../v161_rst_l/README.md)を参照。
  IRQ/NMIとIM2はさらに後続の[IBR試験](../v161_interrupt/README.md)で反映し、
  本270条件も再実行する。[SYSCALL](../v161_syscall/README.md)も後続で反映した。
- RETN.L自身のIFF復元など既存命令の意味は維持。MODE変換でF/W・IFFは変更しない。

## 実行

```powershell
& .\fpga\G80A\test\run_v161_im0.ps1
```

入力は[テストベンチ](../../fpga/G80A/test/tb_v161_im0.vhd)の生成命令列と以下のgeneric。
内部IStatusを直接読むのではなく、M0へ戻ってからIRQを発生させ、
IM0の外部RST 08h、IM1の0038h、IM2の1234hの分岐先で設定を識別する。
割込み応答の最初のサイクルだけCFhを供給し、IM2のテーブル読出しはメモリを使用する。

| Entry_Path | 経路 |
|---|---|
| 0 | M0→SET_M2 |
| 1 | M1→SET_M2 |
| 2 | M0→JP.M2（ED 9B） |
| 3 | M0→CALL.M2 |
| 4 | M0→RET.MでM2復帰 |
| 5 | M0→RETI.LでM2復帰（手動フレーム） |
| 6 | M0→RETN.LでM2復帰（手動フレーム） |
| 7 | M0でIMミラー実行、M1へ移行 |
| 8 | M1でIMミラー実行 |

各経路 × 初期IM0/1/2 × IM命令なし/4ミラー × IFF無効/有効 = 270ケース。
M2ケースはIM命令の後にSET_M2を再実行し、IM2が保持されることも確認する。
F=D7保持、IFF維持、測定コード到達とMODEをチェックする。
MODE復元ケースは実割込みの受付ではなく、準備した4byteフレームを使用する。

メモリはbank00の1バンク。3バンク上限以内。
非ゼロPCバンク、WAIT変動、全フレーム境界、物理SDRAM、外部RETI通知の新規検証は対象外。
RETI.Lの外部通知機構自体は今回追加していない。

## 記録

- `results.jsonl`: generic入力・GHDL出力・各ケースの合否。
- `summary.json`: 270件の完了状態、日時、GHDL版、ソースSHA-256。

再実行は上書き。中断した一部記録を成功と解釈せず、日時・件数・ハッシュを照合する。
Fuse互換形式ではない。実機は未検証。

IM0初回実装時の関連回帰（旧RST.L/JP.M2コード版）: モード制御、IRQ/NMI、周辺、ネストスタック、M2基本、
CALL/RET.L、旧RST.Lの7本がPASS。indexed COM4本も通常・故障注入とも期待どおり。
当時P1314T.COMをED F3へビルドしたが、後続のRST.L移設版RTLとは非互換。
現行回帰・COM制限は[移行記録](../v161_rst_l/README.md)を参照。

IM0初回実装時のGowin Z80X24論理合成成功。Logic集計
`17644 (15636 LUT, 1630 ALU, 63 RAM16) / 20736`、ツール表示86%。
直前の同プロジェクト合成集計17433に対しLogic換算+211。
配置配線・STA・ビットストリーム生成は未実施で、実機の使用率とは区別する。
