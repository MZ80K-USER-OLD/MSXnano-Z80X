# V16.1 IBR IRQ / NMI / IM2

## 実装

- M2 IM1 IRQ: `IBR:0038`。IM0でM2へ移行した場合もIM1として扱う。
- M2 NMI: `IBR:0066`。IMの値には依存しない。
- M2 IM2 IRQ: `{IBR,I,vector8}`からlittle-endianのtarget16を読み、
  `{IBR,target16}`へ分岐。vector8を2倍せず、bit0もマスクしない。
- テーブルは下位16bitでラップする。`IBR:FFFF`の次は同じ`IBR:0000`。
- 既存の4byte frameを維持。MODE/PC_B/PC_H/PC_Lの順にMSP24へpushし、
  メモリの昇順ではPC_L,PC_H,PC_B,MODEとなる。
- IM2だけpush完了後に2読出しサイクルを追加する。テーブル読出し中は
  復帰PCを変更せず、別のバンクへcarryさせない。
- RETI.L (ED F3)とRETN.L (ED 8C)によるPC24/MODE/MSP24復元を維持。
  IRQ受付はIFF1/IFF2をクリア、NMI受付はIFF1のみクリアし、
  RETN.LでIFF1をIFF2から復元する。RETI.L自体はIFFを変更しない。
- 旧IVR/NVRは割込み先として参照しない。旧NVRの転送など、
  本段階に関係しない旧コードの整理は実施していない。

M0/M1のIM0/IM1/IM2/NMIは従来経路のまま。
本割込み検証の初回実装時はSYSCALLが対象外だった。
後続の[SYSCALL実装](../v161_syscall/README.md)でもテーブル経路を共用し、
本512条件を再実行する。ペアバンクコードの移設とRETI外部通知の新機構は対象外。

## 再実行と記録

リポジトリルートのPowerShellから:

```powershell
& .\fpga\G80A\test\run_v161_interrupt.ps1
& .\fpga\G80A\test\run_v15_index16.ps1 -FastBoundaryOnly
& .\fpga\G80A\test\run_v15_index16.ps1 -FastBoundaryOnly -Transfer24
```

- [テストベンチ](../../fpga/G80A/test/tb_v161_interrupt.vhd)
- [ランナー](../../fpga/G80A/test/run_v161_interrupt.ps1)
- [条件・実行出力・合否](results.jsonl)
- [完了件数・日時・GHDL版・ソース/結果SHA256](summary.json)
- [合成集計とソース/レポートSHA256](synthesis.json)

期待件数512。M2は384条件、M0/M1の互換対照は各64条件。

M2:

- Normal/Fastコア、IBR=00/01/02、IM初期値0/1/2。
- IRQ/NMI、IFF有効/無効、WAIT有無、MSP通常/境界。
- IM2 IRQでは40CF（奇数）、40FE（通常偶数）、FFFF（ラップ）の3種類。
  その他の経路は40CFの1種類のみを対照に使う。
- IFF無効のIRQはHALT中に100クロック観測し、受付・フレーム書込み・
  テーブル読出しが起こらないことを検査する。
- IFF有効のIRQと、IFFの両状態でのNMIは実際の非同期入力で受理させ、
  HALTからの復帰アドレス・4byteの各書込み先と値・分岐先の物理バンクを照合する。
- RETI.L後はIFF無効、RETN.L後は元のIFF状態に復元されること、
  PCバンク/MODE/F=D7/通常SP/MSP24/IBR保持を検査する。

M0/M1:

- IBR=02を設定したまま、同じIRQ/NMI/IM/WAIT/IFFの組合せで動作させる。
  分岐先とIM2テーブルがIBRを無視してbank00となることを確認する。
- IM0には外部CF (RST 08)を供給。IM1は0038、IM2はテーブル経由1234、
  NMIは0066。通常SPに2byte frame、RETI/RETNで復帰する。
- この対照ではMSP境界条件を増やさず、MSPが不変であることを確認する。

## 物理メモリと境界配置

独立した物理bank00/01/02の3バンクのみを実装する。
M2のコードはIBRとは異なる非ゼロバンクに置く。
通常のMSP境界条件はbankの0002から4byteをpushし、書込み自体が2バンクへ分かれる。

FFFFテーブルとスタックを同じアドレスへ重ねると、正しいCPUでもpushが
テーブルを破壊する。これを避けるため、IM2/FFFFの境界ケースでは次を使う。

- IBR=00: MSP=02:0002（frameはbank01/02、tableはbank00）。
- IBR=01: MSP=01:0000（最初のdecrementでbank00へ移り、4byteともbank00）。
  この組合せはMSPのborrowを検査し、書込み同士のバンク分離は他の条件で検査する。
- IBR=02: MSP=01:0002（frameはbank00/01、tableはbank02）。

bank00:0000がテーブル上位byteの場合、RESETのJP 0100を実行した後、
プログラム自身が0000へ12hを書き込む。次バンクの0000へaliasさせるモデルではない。
初期試験でのテーブル/フレーム重複はこの明示配置で修正した。

## 範囲と互換性

新RST.L/通常RST/IM0試験、indexed COM4種類の通常・故障注入、
モード制御/M2基本/CALL-RET.L/PUSH24-POP24を関連回帰として実行する。
各verification_dataの記録は再実行時のソースハッシュで識別する。

## FastコアのMCycle=6誤分岐

最初の全条件試験はNormalコアを通過した後、FastコアのIM2で
4byte frameが再び書き込まれる異常を検出した。
旧Fast IX/IY処理用のMCycle=6復帰条件が、実際にIX/IY処理中かどうかを確認せず、
新IM2のテーブル読出しサイクルにも発火していた。

MCycle=7の既存分岐と同様に、Fast側のMCycle=6復帰も
`XYF_Pending='1'`で限定した。これにより通常のIM2読出しはMCycle=7へ進む。
修正後のIRQ試験を全条件で再実行し、専用のFast indexed回帰も追加した。
16bit/24bitそれぞれ48条件（M1/M2 × IX/IY × BC/DE/HL × load/store × WAIT有無、
01:FFFFからの境界転送）を確認する。

この限定実行は`-FastBoundaryOnly`で選択し、
[16bitの記録](index16_fast/summary.json)と[24bitの記録](index24_fast/summary.json)へ保存する。
以前の432/528条件の全行列データを、今回の限定試験で上書きしない。

Fast indexedの16bit/24bit各48条件はPASSし、保存データのソースハッシュも照合済み。
indexed COM4種類も、それぞれ通常`PASS=18 FAIL=00`、
故障注入`PASS=00 FAIL=18`を最終RTLで確認した。
モード制御/M2基本/CALL-RET.L/PUSH24-POP24の4既存ベンチもPASS。

旧[tb_phase13_m2_interrupt](../../fpga/G80A/test/tb_phase13_m2_interrupt.vhd)、
旧周辺/ネスト試験は旧IVR/NVR意味の履歴であり、現仕様の検証には使わない。
旧[P1314T.COM](../../hardware_test/P1314Test/README.md)も現RTLでは実行しない。
後続で新コード用の[I161TEST.COM](../../hardware_test/V161IRQTest/README.md)を作成した。
実VDPによるIM1/IM2 IRQ・RETI.Lを対象とし、NMIは対象外。実機結果は未取得。
M2の割込みを有効にする前に、
IBR内に4byte frame対応ハンドラを準備する必要がある。

同時IRQ/NMIの優先順位、ネストした割込み、BUSRQ、命令フェッチ自体の64KB越え、
全リセット位相、実SDRAM、外部RETI通知は本ベンチの対象外。
NMIはRTL入力による検査のみで、実機NMI経路の実在や実機動作を示すものではない。
配置配線・STA・ビットストリーム生成・実機試験は未実施。

## 最終結果

- IRQ/NMI: **512条件すべてPASS**。M2が384、M0/M1の互換対照が各64。
  FFFFからの実テーブル読出し32条件、DIでIRQを拒否する160条件を含む。
- 新RST.L/JP.M2: 160条件PASS。通常RST: 96条件PASS。
  IM0予防措置: 270条件PASS。
- Fast indexed: 16bit/24bit各48条件PASS。
- indexed COM4種類の通常・故障注入と既存4ベンチもPASS。
- IRQ/RST.L/通常RST/IM0のJSONL件数・全件合格とソースハッシュを照合した。
  結果ハッシュを持つ記録ではJSONL自体のSHA256も照合した。
  合成JSONのソース・レポートハッシュも最終ファイルと一致。

## IBR割込み初回実装時の合成（SYSCALL追加前）

Gowin Z80X24プロジェクトの論理合成成功。
Logic集計は`17692 (15684 LUT, 1630 ALU, 63 RAM16) / 20736`、表示86%。
直前のRST.L移設版17741に対しLogic換算-49。
旧IVR/NVRを割込み先として参照しなくなったことを含む合成全体の差分であり、
新しいIM2ロジック単体のLUT増減を示す数字ではない。
この集計をLUT単体使用数や配置配線後の使用率と混同しない。
