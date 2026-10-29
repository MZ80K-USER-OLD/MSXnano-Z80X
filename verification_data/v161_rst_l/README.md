# V16.1 RST.L / JP.M2 opcode migration

## 実装範囲

- `RST.L 00/08/10/18/20/28/30/38h`: `ED 85/8D/95/9D/A5/AD/B5/BD`。
  M2専用、MSP24へPC_B/PC_H/PC_Lの順に3byteをpushし、
  `{IBR,vector16}`へ分岐する。RET.LでPC24/MSP24を復元する。
- M0/M1での新RST.Lは2byte NOP。旧版の通常RSTへのdegradeは廃止。
- `JP.M2 al ah ab`: `ED 95`から`ED 9B`へ移設。
  ユーザー承認に従い、競合する旧`LD24 IVR,HL`は別名を残さず廃止。
- `IBR`: `ED 3A`書込み、`ED EF`読出し、RESET=00h。
  内部の`bank_rst_r`と外部デバッグ用`bank_rst`ポート名は保持。
- 旧RST.Lの`ED C7/CF/D7/DF/E7/EF/F7/FF`はRST.Lとしては廃止。
  現段階ではED EFのみIBR読出し、それ以外はNOP。
  ED E7のDE_B転送などV15/V16.1のペアバンクコード移設は別段階。
  旧IBR読出し`ED 3E`もNOP。

**本フォルダの初回実装時は割込みのIBR統合前だった。**
その時点では旧IVRを設定できずM2 IRQを使用できなかったが、
後続の[IBR割込み統合](../v161_interrupt/README.md)でIRQ/NMIとIM2を反映した。
本フォルダのRST.L/通常RST試験も統合後RTLで再実行する。
さらに後続で[SYSCALL](../v161_syscall/README.md)も反映した。配置配線・実機確認は別途必要。

## 再実行と記録

リポジトリルートのPowerShell:

```powershell
& .\fpga\G80A\test\run_v161_rst.ps1 -LongRST
& .\fpga\G80A\test\run_v161_rst.ps1
& .\fpga\G80A\test\run_v161_im0.ps1
```

- [共有テストベンチ](../../fpga/G80A/test/tb_v161_rst.vhd)
- [実行スクリプト](../../fpga/G80A/test/run_v161_rst.ps1)
- [入力条件・実行出力・合否](results.jsonl)
- [完了件数・日時・GHDL版・ソース/結果SHA256](summary.json)
- [P12のビルドハッシュ・旧COMビルド拒否の実行結果](compatibility.json)

新RST.Lは160条件。M0/M1のNOP対照64条件と、
M2の実分岐96条件（8ベクタずつ、合計768回）で構成する。
M2はNormal/Fast × コードbank01/02 × MSP通常/境界 × WAIT有無 × IFF有無 ×
JP.M2移行元MODE 0/1/2。

メモリは物理bank00/01/02を独立させた3バンクのみ。
コードbank01ならIBR=02、コードbank02ならIBR=01とする。
境界条件はMSPを`01:0001`または`02:0001`に設定し、
3byteフレームの書込み先・値をその都度照合する。
RET.Lによる物理バンクを含む復帰、SP/MSP復元、
MODE/PC_B/IBR/F=D7/IFF保持、IBRのRESET/読み戻し、
旧RST.Lコードと旧IBR読出しが分岐・pushをしないことも確認する。
JP.M2後に旧IVR書込みの副作用がないことをデバッグbank_int=00でも確認する。
M0/M1ではベクタ分岐もRST.Lによるスタック書込みも0回を要求する。
通常RSTの回帰は別の96条件/768回で記録する。

EI/DI両状態を照合するが、新RST.LベンチではINT/NMIを発生させない。
IM0予防措置の270条件はM0に戻った後のIRQで検査する。
命令フェッチ自体の64KB境界越え、実SDRAM、RETI外部通知は本検証の対象外。

## 旧試験・COMとの互換性

- [P12Test](../../hardware_test/P12Test/README.md): JP.M2をED9Bへ変更して再ビルド。
  新COMは新RTL専用。ビルド成功と命令単位のシミュレーションを確認するが、
  このCOM全体の実行シミュレーション・実機再確認は未実施。
- [P1314Test](../../hardware_test/P1314Test/README.md)と
  [LD24Test](../../hardware_test/LD24Test/README.md):
  旧ED9B IVR設定を使うため現RTLでは実行禁止。
  通常のmakeを明示エラーで止める。明示的な`LEGACY_OPCODES=1`は旧RTL専用の再現用。
  P1314TソースはED F3 RETI.L版なので、ED4Eを使うさらに古いRTLとも非互換。
- 旧ベンチ`tb_rst_l`、`tb_phase7_ld24`、`tb_phase13_m2_interrupt`、
  `tb_phase15_peripheral`、`tb_m2_nested_stack`は履歴として保持し、
  新RTLの合否判定には使用しない。旧意味の試験をNOP化してPASS扱いする変更はしない。
  新RST.Lは上記の物理3バンク試験で置換した。
  IRQ/NMIは後続の[IBR試験](../v161_interrupt/README.md)で置換する。

モード制御、M2基本、CALL/RET.L、PUSH24/POP24の4既存ベンチも回帰対象。
indexed COM4種類も通常・故障注入の両方で回帰対象。
実行結果の判定は各summaryの件数・complete・日時・ハッシュを優先する。
過去の実機PASSは今回の新コード版の結果とは扱わない。

## 合成と関連回帰の結果

- 新RST.L/JP.M2: 160条件すべてPASS（M2の実ベクタ分岐768回、M0/M1のNOP対照64条件）。
  通常RSTの回帰96条件/768回もすべてPASS。
  両JSONLの件数・全件合格・ソース/結果SHA256を実ファイルと照合した。
- IM0予防措置270条件: PASS。ED9Bへ更新したベンチを使用。
- 上記の既存4ベンチ: PASS。
- indexed COM4種類: それぞれ通常`PASS=18 FAIL=00`、
  故障注入`PASS=00 FAIL=18`。各verification_dataのログとソースハッシュを更新し照合した。
- P12TEST.COM: 919byteでビルド成功。COM全体の実行試験は未実施。
  P1314T/LD24TESTの通常makeが明示エラーで停止することも確認した。
- RST.L移設初回時のGowin Z80X24プロジェクトで論理合成成功。
  Logic集計は`17741 (15732 LUT, 1631 ALU, 63 RAM16) / 20736`、表示86%。
  直前の通常RST版17697に対してLogic換算+44。
  集計LogicをLUT単体数や配置配線後の使用率と混同しない。

配置配線・STA・ビットストリーム生成・実機試験は未実施。
