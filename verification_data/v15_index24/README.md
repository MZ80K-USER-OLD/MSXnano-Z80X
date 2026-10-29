# V15 24bit indexed LD 検証データ

[16bit版と同じJSON Lines形式](../v15_index16/README.md)で、入力・期待値を
`cases.jsonl`、実測・合否を`results.jsonl`、日時・ソースハッシュ・完了状態を
`summary.json`へ保存する。Fuse互換のファイル構文ではない。

## 再実行

リポジトリルート、GHDLが必要:

```powershell
& .\fpga\G80A\test\run_v15_index16.ps1 -Transfer24
```

16bit版と同じテストベンチ・ランナーを使用するが、出力先は分離する。
3データファイルは上書きする。`summary.complete=true`、528件の合格、
開始・完了日時とソースハッシュが揃っていることを確認する。

## 対象

| コード | 操作 |
|---|---|
| DD/FD 08 d | BC24へ読出し |
| DD/FD 10 d | DE24へ読出し |
| DD/FD 18 d | HL24へ読出し |
| DD/FD 20 d | BC24を書込み |
| DD/FD 28 d | DE24を書込み |
| DD/FD 30 d | HL24を書込み |

- M1/M2: CPU通常/Fast × MODE × IX/IY × BC/DE/HL × 読書き
  × 5アドレス条件 × WAIT有無 = 480ケース。
- M0: CPU通常/Fast × IX/IY × 6コード × WAIT有無 = 48ケース。
  元のZ80命令（EX AF,AF'、DJNZ、JR、JR cc）と比較する。
  EX AF,AF'の次のINC Aが変位として消費されないことも確認する。
- 合計528ケース。メモリモデルはbank00/01/02の3バンクのみ。

アドレス条件は以下のとおり:

| indexの初期値 | 変位 | 転送開始 |
|---|---|---|
| 01:FFFF | 00 | 01:FFFF（2byte目からbank02） |
| 01:0000 | FF(-1) | 00:FFFF（borrowとbank00→01） |
| 01:8080 | 80(-128) | 01:8000 |
| 01:FF80 | 7F(+127) | 01:FFFF |
| 01:FFFE | 00 | 01:FFFE（3byte目からbank02） |

## 値とチェック

読出しは宛先の初期値67:1234をA5:BEEFへ変更する。
書込みは67:BEEFをEF BE 67の順で転送する。
読出しメモリはEF BE A5、通常の初期メモリは00、
bank00:FFFFはEF。命令列でレジスタを準備し、内部レジスタへ直接代入しない。

対象ペア以外のBC/DE/HLと各バンク、indexとそのバンク01、F=D7を保持する。
書込みは各物理アドレス・各データ・回数3、読出しは対象への書込み0を確認する。
WAITの規則、クロック・リセット、`program_hex`、実測レコードの意味は16bit版と共通。
`actual.pair`は下位16bitで、上位8bitは対応する`bc_bank/de_bank/hl_bank`に記録する。

M0の参照は同じCPUでのプレフィクスなし実行であり、独立した外部オラクルではない。
全レジスタダンプ、厳密なクロック数、物理SDRAM、実機のWAIT調停を保証する試験ではない。
実機COMの記録は[別フォルダ](../index24_com/README.md)へ分離する。

## 論理合成

2026-10-24、Gowin V1.9.11.03 EducationのZ80X24プロジェクトで`run syn`成功。
生成された合成レポートのLogic集計は
`17433 (15425 LUT, 1630 ALU, 63 RAM16) / 20736`、ツール表示85%。
これはRAM等の換算を含むLogic集計であり、LUT単体の使用数とは区別する。
CPU追加前後の同条件比較は未取得のため、この数値から増分を断定しない。
ユーザー報告の従来86%と集計段階・条件が同一とは確認できていない。
配置配線・STAは未実施で、実機用ビットストリームの生成もこの検証には含めない。

2026-10-24、24bit indexed LD追加後のLUT使用量について、ユーザーから86%との報告あり。
従来の報告値と整数パーセント表示では同じ。使用数の実数値・丸め方・
レポートの集計段階は未取得のため、「LUT増分ゼロ」とは判断しない。
上記の合成Logic表示85%とは別の報告として記録する。タイミング結果は未報告。

## 2026-10-24の検証結果

- 本試験528ケースすべてPASS。入力/結果IDの対応・件数・実測値・ソースハッシュも照合済み。
- ユーザーからINDEX24.COMのM1実機結果`PASS=18 FAIL=00`（全24判定PASS）の報告あり。
  詳細は[実機結果の記録](../index24_com/README.md)を参照。
- M2実機もI16M2.COM・I24M2.COMの両方で`PASS=18 FAIL=00`とのユーザー報告あり。
  [16bit版記録](../index16_m2_com/README.md)・[24bit版記録](../index24_m2_com/README.md)を参照。
- 共通経路の16bit版432ケースもすべてPASSし、記録を更新。
- INDEX24.COMとINDEX16.COMはそれぞれ通常`PASS=18 FAIL=00`、
  故障注入`PASS=00 FAIL=18`で終了。ログは各COMフォルダへ保存。
- 既存LD24MIは通常`PASS=13 FAIL=00`、故障注入`PASS=10 FAIL=03`。
- 関連8本のGHDL回帰もPASS:
  `tb_ld24_mem_indirect`、`tb_phase7_ld24`、`tb_phase9_push24_pop24`、
  `tb_hw_push24_bank_boundary_timing`、`tb_phase3_m1_data`、
  `tb_phase10_m2_basic`、`tb_phase11_jrl`、`tb_lea_l`。

既存回帰は対象テストベンチをGHDLで解析し`--assert-level=error`で実行したもの。
境界タイミング試験ではCPU本体に加えて`g80a.vhd`を解析する。
