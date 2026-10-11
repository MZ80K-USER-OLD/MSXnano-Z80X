# MSXnano改造版: Sprite Mode 3導入前のRTL解析

解析対象: ユーザー提供 `msxnano-vdp-sprite.zip`。**RTL静的調査と既存PnRレポート確認のみ**。新規合成・実機測定・シミュレーションは未実施。

## 確認事項

|項目|値|根拠|
|---|---|---|
|入力基準|27MHz|`fpga/top.v` `ex_clk_27m`|
|PLL出力|108MHz|`fpga/top.v` `CLK_108P`|
|VDPクロック|27MHz|`fpga/top.v` `v9958_top vdp4 (.clk(clk_27m))`|
|メモリ制御入力|54MHzおよび108MHz|`fpga/top.v` `memory_ctrl mem1`|
|SDRAMクロック|108MHz|`fpga/src/memory.v` `assign O_sdram_clk = clk_108m`|
|水平クロック数 NTSC/PAL|1716/1728|`fpga/tn_vdp_v3_v9958/src/vdp/vdp_hvcounter.vhd`|
|1ライン NTSC/PAL|63.556/64.000 µs|上記÷27MHz|
|DOCKジョイスティック|`msxnano_dock_joystick`|`fpga/top.v`、`fpga/src/msxnano_dock_joystick.vhd`|
|PS/2キーボード|`ENABLE_PS2KEYBOARD`, `ps2_hid_bridge`|`fpga/top.v`|

## 既存配置配線結果

`fpga/impl/pnr/MSXnanoTANG20K.rpt.txt` (2026-10-03、GW2AR-18、Gowin 1.9.11.03 Education)

|リソース|使用量|容量|使用率|
|---|---:|---:|---:|
|Logic|14724|20736|71%|
|LUT|12594|—|—|
|CLS|9067|10368|88%|
|BSRAM|45|46|98%|
|Register|6827|15915|43%|
|PLL|2|2|100%|

レポートは同梱ビルドの値。現在のRTLと全く同じ構成で再ビルドした証明ではない。特にBSRAM・CLSが制約。

## スプライト32枚/ラインの処理下限

- 16×16、4bpp: 1枚につき1行8バイト、32枚で256バイト/ライン。
- 1ピクセル/クロックなら通常512ピクセルの描画に最低512クロック（32枚×16px）。2倍拡大時は最大1024出力ピクセル相当となる。
- SAT64枚の逐次走査: 最低64クロック。
- 256pxラインバッファを逐次クリアするなら256クロック。
- NTSC 27MHzでは1716クロック、54MHzなら3432クロック相当。
- 27MHz逐次処理で拡大なし: 1716−(512+64+256)=884クロックがSDRAMアクセス、制御、描画の追加オーバーヘッドに残る。32件の非連続アクセスに平均27.6クロック未満しか割り当てられない（理想化した上限）。
- 2倍拡大時: 1716−(1024+64+256)=372クロック、1件あたり11.6クロック未満となり、SDRAM競合を考えると厳しい。
- これは完全逐次モデルの概算であり、描画と転送のオーバーラップ、ラインバッファのクリア方式、クロック変更、外部SDRAMの競合により変化する。

## 構造上の制約

- `fpga/src/memory.v` はCPU/VDPのアクセスを `video_dlclk`, `video_dhclk` 等で時間分割しており、Sprite Mode 3専用の独立した要求/応答ポートは存在しない。
- 32スプライトのパターン行はアドレスが散在するため、単純な256バイト連続バーストとみなせない。
- BSRAM残り1ブロック。Palette、SAT、2本の8bpp Line Buffer、FIFOを新規BSRAMで全実装する方針は非現実的。
- 8bpp Line Bufferは「パレットグループ4bit＋ピクセル値4bit」を保持し、下位4bitが0なら透明とする。
- 既存PS/2およびDOCKジョイスティック接続を変更しない。

## 推奨する次の開発ステップ

1. Gowin EDAでDOCK対応現行RTLを再合成し、現行のリソース・タイミングを確定する。
2. 既存BSRAMの用途を階層別に調査し、ROM配置や既存Line Bufferの共有可能性を確認する。
3. `memory_ctrl` にMode3専用VRAM要求/応答を追加するための調停仕様を設計し、既存VDP/CPUの動作を維持する。
4. SAT走査・1行パターン読み出し・描画を独立したVHDLテストベンチで検証する。
5. 16枚、32枚、2倍拡大、最大競合、リフレッシュ時の期限超過をテストする。
6. 小型Line Buffer構成を実際に合成し、BSRAMとCLSを評価する。

## 暫定判定

**処理時間:** 32枚は並列化・54MHz等の工夫により可能性あり。ただし現行SDRAM調停では保証不可。27MHz完全逐次で2倍拡大32枚は厳しい。

**FPGAリソース:** 現行PnRでBSRAM 45/46、CLS 88%。このまま新規Sprite Engineを追加することは難しく、既存メモリ資源の再配置が優先。
