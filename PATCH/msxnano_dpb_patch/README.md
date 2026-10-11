# MSXnano Sprite Line Buffer DPB統合パッチ

GHDLシミュレーション・Gowin EDA実合成・実機(Tang Nano 20K)での検証済み。詳細は下記
「GHDLシミュレーションによる検証」「Gowin EDAによる実合成検証」「実機検証」を参照。

## 内容
- `sprite_linebuf_dp.vhd`: 512×8bit、2ポート読み書き可能なRAM。
- `vdp_sprite.vhd`: 元の `U_EVEN_LINE_BUF` / `U_ODD_LINE_BUF` を `U_SHARED_LINE_BUF` に置換。
- `tb_sprite_linebuf_dp.vhd`: `sprite_linebuf_dp` 単体の機能検証用GHDLテストベンチ。
- `gowin_synthesis_evidence/`: Gowin実合成の結果レポート(baseline/適用後)と合成ログ。

## 適用
1. 元の `fpga/tn_vdp_v3_v9958/src/vdp/vdp_sprite.vhd` をバックアップし、本パッチの同名ファイルで置換する。
2. `sprite_linebuf_dp.vhd` を同じVHDLソース群 (`fpga/tn_vdp_v3_v9958/src/vdp/`) へ追加する。
3. Gowinプロジェクトに新規ファイルを登録する: GUI用の `fpga/MSXNanoTang20K.gprj` と
   `fpga/tn_vdp_v3_v9958/tn_vdp_v3_v9958.gprj`、およびコマンドラインビルド用 `fpga/build.tcl` の
   いずれにも `sprite_linebuf_dp.vhd` の `add_file`/`<File>` エントリを追加する（3箇所とも登録が必要）。
4. 既存のDOCK用top.vなどは変更しない。

## 注意
- 2ポート同一アドレスへの書き込みは、表示バンクと描画バンクが異なる前提で起きない。
- 元の `RAM` の初期値と合わせてゼロ初期化を記述。
- 本パッチはBSRAM統合だけを対象とし、Sprite Mode 3は未実装。

## GHDLシミュレーションによる検証（実施済み）

GHDL 6.0.0 (mcode) を用いて以下を検証した。

### 1. RTLコンパイル確認
`vdp_package.vhd` → `ram.vhd` → `vdp_spinforam.vhd` → `sprite_linebuf_dp.vhd` → `vdp_sprite.vhd` の順に
`ghdl -a -C -fsynopsys -fexplicit --std=93` でエラーなく解析でき、`ghdl -e --std=93 VDP_SPRITE` でも
エラーなくエラボレーションできることを確認した（`VDP_SPINFORAM` 用の component も含め、default binding に関する
`[-Wbinding]` 警告は本パッチ適用前の既存コードでも同様に出るため、本パッチ起因の問題ではない）。

### 2. 発見・修正したバグ（GHDLシミュレーションで発見）
検証の過程で2件の実バグを発見し修正済み（`sprite_linebuf_dp.vhd` / `vdp_sprite.vhd` は修正後の内容）。

1. **VHDL-93でのポートマップ実引数エラー**: `A_ADDR => DOTCOUNTERYP(0) & SPLINEBUFDISPX` のような非静的な連結式を
   ポートマップの実引数へ直接書くことは、VHDL-2008以前（本プロジェクトが前提とするVHDL-93）では
   「globally static expression」でなければならないという規則に反し、GHDLがエラーにする。
   → `SPLINEBUF_A_ADDR` / `SPLINEBUF_B_ADDR` という中間信号を追加し、一旦信号へ代入してからポートマップへ渡す形に修正。
2. **2ポートRAMのシミュレーション上のデータ破損（実バグ）**: `mem` をsignal配列にして2つの独立クロックプロセス
   （Aポート用・Bポート用）から書き込むと、各プロセスがそれぞれ配列全体の「別ドライバ」になり、
   一方のプロセスが更新していないインデックスはそのプロセス内で古い値（初期値）のまま残る。これと
   もう一方のプロセスが新しく書いた値とを `std_logic` の解決関数で合成しようとして `'X'`（不定値）になる。
   実機合成では物理的に単一のBRAMセルとして推論されるため問題にならないが、シミュレータ上は明確なデータ破損となる。
   → 2つのポートを**1つのクロックプロセスにまとめ**、`mem` のドライバを1つだけにして解決（Gowin/Xilinx/Intel
   各社が推奨する「True Dual Port RAM推論」の標準的な書き方）。

### 3. 発見・修正したバグ（Gowin EDA実合成で発見）
GHDLでは検出できない、Gowin特有の合成時エラーも1件発見・修正済み。

3. **Gowin DPBプリミティブのWRITE_MODE非対応エラー**: `PA2122 : Not support 'mem_mem_0_0_s'(DPB) WRITE_MODE0 = 2'b10`。
   各ポートの読み出しアドレスと書き込みアドレスに**文字通り同一の信号**（`a_addr`／`b_addr`）を使うと、
   VHDLの記述順序（read-before-write / write-first）やプロセス構成（1プロセスか2プロセスか）に関わらず、
   Gowinの合成ツールは「透過（write-first）」モード（`2'b10`）を要求してしまい、GW2AR-18CのDPBプリミティブは
   この深さ・幅の構成ではこのモードを**サポートしない**。
   → 元の単一ポート `RAM` エンティティ（書き込みは直接 `adr`、読み出しは1クロック遅延させた `iadr` 経由）と
   同じ考え方に戻し、各ポートの読み出しアドレスを**書き込みアドレスとは別の信号**（`a_rdaddr`/`b_rdaddr`、
   書き込みアドレスを1クロック遅延させたレジスタ）として実装。読み出し・書き込みが構造的に別アドレス線になる
   ことで、Gowinが対応する「normal」モード（`2'b00`）にマッピングされるようになった。

### 4. 機能テスト（GHDLシミュレーション）
`tb_sprite_linebuf_dp.vhd`（本フォルダに同梱、VHDL-2008の `std.env.stop` を使用するためDUT単体を
`ghdl -a/-e/-r --std=08` でビルドして実行）で以下をすべてPASS:

- Aポート書き込み→1クロック後の読み出し一致
- Bポートが別バンク(アドレスbit8)へ書いても、Aポート側の値が破壊されない（クロストーク無し）
- 同一クロックで両ポートが異なるバンクへ同時書き込みしても双方正しく保持される
  (実際の使用パターン=表示バンク/描画バンクの同時アクセスを模擬)
- `DOTCOUNTERYP(0)` 反転に相当するバンク入れ替え後も、互いに書いた値を正しく読み出せる
- 同一ポートでの read-after-write (描画側のread-modify-write相当) が正しく機能

## Gowin EDAによる実合成検証（実施済み）

`D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe` ＋ `fpga/build.tcl` で
Device `GW2AR-LV18QN88C8/I7` 向けに論理合成・配置配線・ビットストリーム生成まで実施（結果は
`gowin_synthesis_evidence/` に保存）。

**事前修正**: `fpga/build.tcl` に `src/msxnano_dock_joystick.vhd` と `src/usb/ps2_hid_bridge.vhd` が
含まれておらず単独ではビルド不能だったため追加（`.gprj` には元々登録済みだった、本パッチとは無関係の
既存の抜け漏れ）。

### 結果比較（パッチ適用前 baseline vs 適用後）

|項目|Baseline (適用前)|適用後|
|---|---:|---:|
|BSRAM 合計|45/46 (98%)|**44/46 (96%)** ← 1ブロック削減|
|  内訳 SP (single-port)|6|4|
|  内訳 SDPB|2|2|
|  内訳 DPB (dual-port)|1|2|
|Logic|14724/20736 (71%)|14646/20736 (71%)|
|CLS|9067/10368 (88%)|9066/10368 (88%)|
|Register|6827/15915 (43%)|6825/15915 (43%)|
|Setup 最悪スラック|-5.7 ns|-3.338 ns|
|Setup/Hold 違反数 (計425パス中)|316|188|

- **BSRAM削減の狙い通りの効果を実機合成で確認**: 偶数/奇数ラインバッファ用の単一ポートRAM(SP)2個が、
  1個の共有2ポートRAM(DPB)に統合され、合計で BSRAM 1ブロック分を削減できた（98%→96%）。
- **タイミング**: 本デザインはBaseline時点で既にSetup/Holdの未達（タイミング違反）を多数抱えている
  (CLS 88%・BSRAM 98%という高占有率のため)。本パッチ適用後もSetup/Hold違反は残るが、**件数・最悪値とも
  Baselineより悪化しておらず、むしろ改善している**（違反パス数 316→188、最悪スラック -5.7ns→-3.338ns）。
  タイミング違反のワーストパスは `ff_sd_sector_*` 等のSDカード関連ロジックであり、本パッチの
  `sprite_linebuf_dp`/`vdp_sprite` 関連の信号はタイミングレポート中の主要違反パスには登場しない。
  ただし、デザイン全体のタイミング違反自体は本パッチ適用前から存在する既存の問題であり、本パッチでは
  解消していない。

### 5. 未検証のまま残る事項
- Setup/Holdタイミング違反（Baseline由来、本パッチ無関係）の根本解消。
- 2ポート同一アドレスへの同時書き込み時の挙動（設計上発生しない前提だが、万一発生した場合は未定義）。

## 実機検証（Tang Nano 20K、実施済み）

Gowin EDAでビルドしたビットストリームを実機に書き込み、以下を確認した。

|ゲーム|機種|結果|
|---|---|---|
|夢幻戦士ヴァリス|MSX1|プレイ可能|
|スペースマンボウ|MSX2|プレイ可能|
|アレスタ2|MSX2|プレイ可能|
|アレスタ外伝|MSXturboR|ゲーム起動時にリセットが発生|

**「アレスタ外伝」のリセット症状はパッチ適用前（元の `U_EVEN_LINE_BUF`/`U_ODD_LINE_BUF` 2本構成）の
ビットストリームでも同様に再現することを使用者が確認済み。本パッチが原因の回帰ではなく、本パッチ適用前から
存在する既存の問題である**。加えて「アレスタ外伝」はMSXturboR専用ソフトであり、本プロジェクト
(MSXnano-Z80X) はZ80ベースのコアでturboR固有機能(R800 CPU、DRAMモード等)を前提としたソフトは本来
動作対象外と考えられる。したがって本パッチのスコープ外の問題として切り分け済み。原因調査・修正は別課題
として扱う。

### 実機検証で確認できたこと
- BSRAM 1ブロック削減後も、MSX1/MSX2の通常のスプライト表示・ゲームプレイには支障がない
  (ヴァリス/スペースマンボウ/アレスタ2で確認)。
- Gowin PnRでのタイミング違反（Setup/Hold）はBaselineから残存するが、少なくとも上記3タイトルの実プレイでは
  可視化できる不具合は発生していない。
