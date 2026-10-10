# Gowin IDE プロジェクト設定メモ（手動設定が必要・.gprjに永続化されない項目）

更新日: 2026-10-11

## 背景

[fpga/MSXNanoTang20K_Z80X24.gprj](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj) と
[fpga/MSXNanoTang20K_Z80X24.gprj.user](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj.user) の
git履歴を本プロジェクト最初期のコミットまで遡って確認したが、以下の設定項目はどのコミットにも一度も記録されていない。すなわちこれらはGowin
IDEのプロジェクトファイルには永続化されず、**IDEのローカル状態としてのみ保持される**（何らかの理由でIDE側の状態がリセットされると消える）。再発時にすぐ復元できるよう、正しい設定値を本ドキュメントに記録しておく。

設定場所はいずれも Gowin IDE メニューの **Project → Configuration** ダイアログ。

## 1. Dual-Purpose Pin（Place & Route タブ）

**設定箇所:** Project → Configuration → Place & Route → Dual-Purpose Pin

**正しい設定値:** 以下の2つをGPIOとして使う設定（チェックを入れる）。

- Use MSPI as GPIO
- Use SSPI as GPIO

他の項目（READY/DONE/RECONFIG_N/I2C/MODE等）はチェックなし（デフォルトのまま）。

Tang Nano 20K基板はSD-RAM/SDカード/HDMI等、設定用ピン(SSPI/MSPI)と衝突する配線を使っているため、この2つをGPIOへ転用する設定が必須。この設定が外れていると、該当ピンに接続されたSD-RAM/SDカード等が動作しない、または配置配線（PnR）がピン衝突でエラーになる。

## 2. Verilog言語仕様（Synthesize タブ）

**設定箇所:** Project → Configuration → Synthesize → Verilog Language

**正しい設定値:** `System Verilog 2017`（内部オプション名: `sysv2017` / `sysv-2017`）

この設定が外れている（デフォルトのVerilog 2001等に戻っている）と、`.sv`拡張子のファイル（[fpga/tn_vdp_v3_v9958/src/hdmi/](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/tn_vdp_v3_v9958/src/hdmi) 以下のHDMI関連モジュール等）やパラメータなし宣言を含むモジュールの解析でEX3863/EX3444/EX3183等の大量のパースエラーが発生し、あたかも重大なソースコードバグがあるかのように見える（実際にはただのツール設定の問題）。

参考: ヘッドレス（`gw_sh` Tcl経由）で合成する場合は、Tclスクリプト内で毎回明示的に

```tcl
set_option -verilog_std sysv2017
```

を実行する必要がある（`save_option`に相当するコマンドは見つかっておらず、`.gprj`には保存されない）。

## 3. Topモジュール（Synthesize タブ / File List）

**設定箇所:** Project → Configuration → Synthesize → Top Module、または File List 上でのトップモジュール指定

**正しい設定値:**
- モジュール名: `top`
- ソースファイルパス: `fpga/top.v`（プロジェクトルートからの相対パスは `top.v`、[fpga/MSXNanoTang20K_Z80X24.gprj](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj) の `<File path="top.v" .../>` エントリに対応）

Gowin IDEの自動トップモジュール検出は、ヘッドレス（`gw_sh`）実行時に誤ったサブモジュール（例: `VENCODE`）を選んでしまうことがあり、その場合エラーは出ないがごく小さい・無意味なリソースレポートが生成される。ヘッドレスでは必ず

```tcl
set_option -top_module top
```

を明示する。IDE（GUI）側でもTop Moduleがずれていないか確認すること。

## まとめ：ヘッドレス合成用Tclスクリプトの定型

上記2・3の設定は`.gprj`に保存されないため、`gw_sh`でのヘッドレス合成を行う際は、毎回以下を含むTclスクリプトを使う（Dual-Purpose
PinはIDEのGUI設定であり、`run syn`のみを行うヘッドレス合成には影響しないため、Tcl側での設定は通常不要。配置配線まで行う場合は別途`set_option`での指定を要確認）。

```tcl
open_project MSXNanoTang20K_Z80X24.gprj
set_option -verilog_std sysv2017
set_option -top_module top
run syn
```

実行後は `fpga/impl`（gitignore対象）を削除し、Gowinが書き換える
[fpga/MSXNanoTang20K_Z80X24.gprj.user](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/MSXNanoTang20K_Z80X24.gprj.user)
（UI状態がトラッキング対象ファイルに書き込まれてしまう）を `git checkout --` で元に戻すこと。
