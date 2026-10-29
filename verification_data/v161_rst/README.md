# V16.1 通常RSTの同一バンク分岐

通常の非ED前置RSTだけを対象に、M2の分岐先を現在のPC_B内へ修正した。
PC16の2byte保存、通常RETによる復帰、M0/M1の動作は維持する。
本フォルダは通常RSTの検証記録。後続の新RST.L/JP.M2移設版RTLでも再実行する。
新RST.Lの範囲と互換性制限は[移行記録](../v161_rst_l/README.md)を参照。

## 再実行

リポジトリルートのPowerShellから:

```powershell
& .\fpga\G80A\test\run_v161_rst.ps1
```

- [テストベンチ](../../fpga/G80A/test/tb_v161_rst.vhd)
- [実行スクリプト](../../fpga/G80A/test/run_v161_rst.ps1)
- [条件別の実行結果](results.jsonl)
- [実行日時・ソースSHA256](summary.json)

96条件、各8ベクタ、合計768回の通常RSTがPASS。
MODE 0/1/2 × Normal/Fastコア × コードbank01/02指定 ×
通常/境界MSP × WAIT有無 × IFF無効/有効。
M0/M1ではコードはbank00、MSP境界指定は非適用の対照条件となる。

メモリはbank00/01/02の物理アドレスを独立した3バンクで保持する。
M2のコードとMSPを異なる非ゼロバンクに置き、境界条件ではMSPの初期値を
`01:0001`または`02:0001`として、2回の書込みを別バンクへ分離する。
RST_Bにもコードバンクとは異なる値を設定し、命令フェッチ時のバンクを直接照合する。
各RSTの書込み先とPC_H/PC_Lを実行中に検査し、8ベクタ順序・RETでの復帰・
2byteフレーム・MSP/SP復元・MODE/PC_B/RST_B・F=D7・IFF保持を検査する。
コード末尾でPUSH AF/POP BCを行うため、監視するスタック書込み総数は16+2回。
DIとEIの両設定を検査するが、実際の割込み受付試験は本ベンチの対象外。
命令フェッチ自体の64KB境界越えも本試験の対象外。

通常RST初回修正時の既存7試験もPASS（旧RST.L/JP.M2コード版）:
mode control、M2 interrupt、peripheral、nested stack、M2 basic、
CALL/RET.L、旧RST.L。

通常RST初回修正時にGowinのZ80X24プロジェクトで合成成功。
合成のLogic集計は17,697 / 20,736（86%表示）、
内訳は15,688 LUT、1,631 ALU、63 RAM16。
直前のIM0段階の17,644から集計値で53増加した。
このLogic値はLUT単体の使用数ではなく、配置配線後の使用率とも区別する。

FPGAの配置配線・タイミング解析・ビットストリーム生成・実機試験は未実施。
過去の実機PASSを本変更の実機検証結果とは扱わない。
