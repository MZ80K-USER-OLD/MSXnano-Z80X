# H161TEST.COM: M0 / M1 / M2 HALT and VDP IRQ

V16.1 RTL用の独立した実機試験。[I161TEST.COM](../V161IRQTest/README.md)の
有限ループ予備試験が停止していても、このCOMだけを実行できる。
実機では、[top.v](../../fpga/top.v)の拡張SDRAM WAIT制御を修正した
FPGAビットストリームで、下記のPASSを確認済み。

## 実機確認結果（2026-10-29）

ユーザー報告:

```text
PASS=03 FAIL=00
```

M0/M1/M2の全3ケースがPASS。修正前に報告された`HALT arming M02`での停止は解消した。
各行のVRAMトレース全文は今回の報告には含まれない。
同時に実行した[I161TEST.COM](../V161IRQTest/README.md)も`PASS=04 FAIL=00`。

原因となったVHDL/Verilogの関係、先行WAIT設計の意図と見落とし、修正と
eZ80開発向けの教訓は[調査メモ](../../doc/jpn/M2割込みフリーズ_WAIT制御の原因とeZ80開発への教訓_2026-10-29.md)に記録した。

## 実行

[bin/h161test.com](bin/h161test.com)をMSX-DOSディスクへコピーする。
SCREEN 0・40桁・ネームテーブル先頭0000hの環境で実行する。

```text
A>H161TEST
```

M0、M1、M2の順で、同じVDP IRQ・IM2を使って各2回の`EI / HALT`を実行する。
M0/M1は通常のSPと`RETI`、M2はbank02のMSP24と`RETI.L`を使う。
IM1のM0/M1はROMの0038hを経由するため、この比較ではRAMに専用ハンドラを置ける
IM2に揃えている。IM0/IM1、NMI、DI中のHALTはこのCOMの対象外。

正常時のDOS出力:

```text
HALT arming M00
HALT M00: PASS
HALT arming M01
HALT M01: PASS
HALT arming M02
HALT M02: PASS
PASS=03 FAIL=00
```

## VRAMトレース

ネームテーブルの0000h、0028h、0050hからそれぞれM0、M1、M2のトレースを記録する。
正常な各行の先頭13文字:

```text
0AHVSKRHVSKRM
1AHVSKRHVSKRM
2AHVSKRHVSKRM
```

| 文字 | 到達段階 |
|---|---|
| `0` / `1` / `2` | 対象モードへの移行前 |
| `A` | 対象モードのコードへ到達 |
| `H` | `EI / HALT`直前。実機ではHALT状態そのものを証明する文字ではない |
| `V` | IRQハンドラへ到達 |
| `S` | 割込みフレームの記録完了 |
| `K` | VDP status 0読出しによるACKとIRQ回数更新が完了、割込み復帰命令の前 |
| `R` | HALT直後の命令から実行再開 |
| 2組目の`HVSKR` | 再びEIして2回目のHALT待ち・IRQ・復帰 |
| 最後の`M` | M0復帰と通常SPの記録・DOS用SP復元が完了 |

`H`のままならIRQ受付からハンドラ入口まで、`V`のままならスタック記録、
`S`のままならACK・回数更新、`K`のままなら割込み復帰命令からHALT直後までを調べる。
表示が止まったときは3行の先頭文字列と最後のDOS出力を記録し、リセットする。
各文字はそのI/O書込みまで到達した証拠であり、次の文字が出ない原因を単一命令に断定はしない。

**HALT中はソフトウェアのタイムアウトも動かない。**
IRQが来なければ`H`で待ち続けるのが正常であり、自力でFAILを表示することはできない。
有限ループのタイムアウト確認は従来の[I161TEST.COM](../V161IRQTest/README.md)で行う。

## 比較する値

- IRQ受理回数が各モード2回、両方のHALT直後に到達すること。
- 各復帰後のIFF2が0であること。2回目は明示的にEIしてからHALTする。
- 通常SPがD000hへ戻ること。MSP24が02:D000hのまま、またはそこへ戻ること。
- M0/M1ハンドラのSPがCFFEh、M2ハンドラのMSP24が02:CFFChであること。
- 2回分の保存PCが、それぞれのHALTの**次の命令の正確なアドレス**であること。
- M2の両フレームのPCB=01、MODE=02であること。
- ハンドラの署名5Ahが記録されること。

コードはM0/M1では00:8000、M2では01:8000へコピーする。
専用IM2表は00:9000と02:9000から257byteを81hで埋め、
任意のvector8に対して8181hへ分岐できるようにする。
M0/M1のハンドラは00:8190、M2は02:8190、IBR=02。
通常SPは00:D000、MSP24は02:D000。これらのRAM領域は試験用に上書きする。
BIOSの通常割込みハンドラやBDOSは測定中に呼ばない。
終了時は保存したSP、MSP24、IBR、I、VDP R#1を復元し、IM1・M0・拡張bank=00に戻す。

FAILは最初の不一致を`offset=xx got=xx want=xx`で表示する。

| Offset（16進） | 意味 |
|---|---|
| 00 | IRQ回数 |
| 01 / 02 | 1回目 / 2回目の復帰後のIFF2（FのP/Vビット） |
| 03 / 04 | 1回目 / 2回目のHALT直後への到達記録 |
| 05～06 | 復帰後の通常SP |
| 07～09 | 復帰後のMSP24 |
| 0A～0C | ハンドラ入場時のSPまたはMSP24 |
| 0D～10 | 1回目のフレーム。M0/M1はPC16とゼロ埋め2byte |
| 11～14 | 2回目のフレーム。同上 |
| 15 | ハンドラ署名5Ah |

## ビルドとシミュレーション

z88dkのbinをPATHへ追加し、このディレクトリで`make`する。

リポジトリルートから:

```powershell
.\fpga\G80A\test\run_v161_halt_com.ps1
.\fpga\G80A\test\run_v161_halt_com.ps1 -NoInterrupt
```

通常試験はCPU設定0/1 × WAIT有無 × 署名故障注入有無の8条件。
正常時は`PASS=03 FAIL=00`、M2署名をA5hへ故障注入した場合は
M0/M1がPASS、M2が`offset=15 got=A5 want=5A`でFAIL、集計`PASS=02 FAIL=01`を期待する。

テストベンチは各HALT信号のアサート後32クロックまでIRQを発生させず、
実際のHALT待機を観測してからIRQを与える。各モード2回の受付・復帰、
物理フレーム書込み（M0/M1各4byte、M2は8byte）、
IM2表の読出し（各モード4byte）、順序付きVRAMトレースを検査する。
応答vector8はFFhを与え、90FFh→9100hの読出しとbank00/bank02を照合する。
VDPフレーム周期、MSX-DOS、実機SDRAM自体の再現ではない。

`-NoInterrupt`はM0、M1、M2を別々にIRQ抑止対象にする3試行。
対象より前のモードは通常実行し、対象モードで10msの監視期限までHALTを継続し、
追加IRQも復帰もないことを確認する。テストベンチの専用watchdogエラーを期待結果として
扱うものであり、実機COMにタイムアウト機能を追加するものではない。

結果とソースハッシュは[通常試験](../../verification_data/v161_halt_com/summary.json)と
[IRQ抑止試験](../../verification_data/v161_halt_com_no_irq/summary.json)に保存する。
