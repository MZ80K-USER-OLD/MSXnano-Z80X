# 標準T80ビルド構成（MSXNanoTang20K_Std.gprj）

更新日: 2026-10-11

## 背景・目的

本リポジトリのメインプロジェクト [fpga/MSXNanoTang20K_Z80X24.gprj](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj)
は、Z80互換コアT80を24bit拡張した独自CPUコア「**Z80X24**」（[fpga/G80A/t80.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A/t80.vhd)
ほか）を使用している。設計方針として、24bit拡張機能はすべて`mode24_r`
（`SET_M0`/`SET_M1`/`SET_M2`命令でのみ変化するモードレジスタ）で分岐しており、
ソフトウェアが`ED 90/91/92`を一度も実行しなければ常にオリジナルT80と同じ
動作になる（Phase1〜10の全GHDL回帰・実機確認の前提）。

しかし、

- 24bit拡張ロジックに起因するかもしれない不具合の切り分け（オリジナルT80
  そのままなら絶対に発生し得ないことを示す比較対象）
- 24bit拡張を一切使わない用途でのFPGAリソース最小化・安全なフォールバック

といった目的のため、**オリジナルの（無改造の）T80コアを使ったビルドを
完全に独立したGowinプロジェクトとして用意**した。これが本ドキュメントが
説明する`fpga/MSXNanoTang20K_Std.gprj`である。

## 構成

| 項目 | Z80X24ビルド（メイン） | Stdビルド（本構成） |
|---|---|---|
| Gowinプロジェクトファイル | [MSXNanoTang20K_Z80X24.gprj](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj) | [MSXNanoTang20K_Std.gprj](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Std.gprj) |
| CPUコア一式 | [fpga/G80A/](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A)（t80.vhd/t80_mcode.vhd/t80_pack.vhd/g80a.vhdが24bit拡張済み） | [fpga/G80A_Std/](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A_Std)（commit `1ea61d1`＝mode24導入前のバイト完全一致コピー、無改造） |
| CPUラッパー(Verilog) | [MSXnano_CPU_Wrapper24.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXnano_CPU_Wrapper24.v) | [MSXnano_CPU_Wrapper24_std.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXnano_CPU_Wrapper24_std.v) |
| `top.v`・VDP・SD-RAM・USB等その他全ファイル | 共通（両プロジェクトで完全に同一ファイルを参照、無改造・無複製） | 同左 |

`top.v`は一切変更していない。[MSXnano_CPU_Wrapper24_std.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXnano_CPU_Wrapper24_std.v)
は`MSXnano_CPU_Wrapper24`という**同一モジュール名・同一ポートリスト**を持つ
別実装であり、内部でオリジナルの`G80a`（[fpga/G80A_Std/g80a.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A_Std/g80a.vhd)）
を呼び出し、24bit専用の出力（`mode24`/`bank_bc`等）は常に0に固定している。
`top.v`からはどちらのプロジェクトでも同じモジュール名・同じポートで
呼び出されるため、`top.v`側の改造・複製が一切不要になっている。

`fpga/G80A_Std/`内の7ファイル（t80.vhd, t80_mcode.vhd, t80_pack.vhd,
t80_alu.vhd, t80_reg.vhd, g80a.vhd, T80s.vhd）は、コミット`1ea61d1`
（24bit拡張（mode24フラグ）導入前の最後のコミット）から`git show`で
抽出した**バイト完全一致**のコピーであり、一切手を加えていない
（`git hash-object`で元のgit blobと一致することを確認済み）。

## ビルド方法

Gowin IDEで`fpga/MSXNanoTang20K_Std.gprj`を直接開いてビルドする。

**注意**: [Gowin_IDEプロジェクト設定メモ.md](Gowin_IDEプロジェクト設定メモ.md)
に記載の3設定（Verilog Language = System Verilog 2017、Top Module = `top`、
Dual-Purpose Pin = Use MSPI/SSPI as GPIO）は、本プロジェクトでも同様に
`.gprj`/`.gprj.user`へ永続化されず、プロジェクトを開くたびに手動確認・
設定が必要。

ヘッドレス（`gw_sh`）での合成確認は以下の手順で行った（エラーなしを確認済み、
2026-10-11）。

```tcl
open_project MSXNanoTang20K_Std.gprj
set_option -verilog_std sysv2017
set_option -top_module top
run syn
```

## 既知の制約

- `G80A_Std/`はオリジナルT80のバイト完全一致コピーのため、本リポジトリの
  Phase1〜10で実装した24bit拡張命令（SET_M0/M1/M2, LD24, ALU24, PUSH24/POP24,
  M2基本動作等）は一切使用できない。純粋な標準Z80互換動作のみ。
- `G80A_Std/`は独立した完全コピーであり、`G80A/`側の将来の変更（Phase11以降）
  は自動的には反映されない。意図的な設計（「完全に独立」という要求に
  基づく）であり、Z80X24側の不具合調査用リファレンスとして凍結しておく
  意味合いが強い。
