#  CPUのターボモードの仕組み



MSXnanoを含むFPGA MSX（1チップMSX / OCM系）のカスタム機能として用意されている「Turboモード（3.58MHzを超える高速駆動）」は、FPGAの特性を最大限に活かした機能です。

この高速化を実現するため、ハードウェアの「クロックイネーブル（CLKEN）方式」と「Z80ラッパー」が密接に関わっています。その仕組みとラッパーへの具体的な影響について詳しく解説します。

## 1. Turboモードの仕組み（CLKEN方式）
FPGA内部では、処理の安定のためにシステム全体が1つの高速なベースクロック（例: 21.48MHz や 42.95MHzなど）で同期して動いています。
CPU（Z80）のクロック周波数を変更する際、ベースクロックそのものを切り替えるのではなく、「CPUに動作を許可するストロブ信号（CLKEN / クロックイネーブル）」の間隔（パルスの頻度）を変えることで擬似的に周波数を変更しています。



* ノーマルモード (3.58MHz): ベースクロックが21.48MHzの場合、6サイクルに1回だけ CLKEN を 1 にする。

* Turboモード (7.16MHz): CLKEN を3サイクルに1回（2倍の頻度） 1 にする。

* カスタムTurbo (10.74MHz以上など): CLKEN をさらに高頻度（2サイクルに1回など）で 1 にする。 [1] 

  

------------------------------
## 2. ラッパー（Wrapper）への影響
VerilogからVHDLのCPU（T80）を呼び出すラッパーにおいて、Turboモードの実装は以下の3つの要素に重大な影響を与えます。
## ① クロックイネーブル（CLKEN）の多重化・動的切り替え
ラッパーは、システム（Verilog側）のI/Oポート（例: 0x41 や 0x1e などのTurbo設定レジスタ）の状態を監視し、CPUへ渡す CLKEN を動的に切り替える必要があります。 [2] 

```
// ラッパー内部でのCLKEN制御イメージ（Verilog）
wire clken_normal; // 3.58MHzタイミング (6分周)
wire clken_turbo;  // 7.16MHzタイミング (3分周)
wire cpu_clken;

// Turboレジスタのフラグ（1でTurbo有効）に応じてCPUのイネーブルを切り替える
assign cpu_clken = (turbo_mode_reg) ? clken_turbo : clken_normal;

// VHDLのT80コアへ供給
T80se u_t80 (
    .CLK_n   ( clk_in    ), // 21.48MHzの固定高速マスタークロック
    .CLKEN   ( cpu_clken ), // 切り替わった動的イネーブル信号
    ...
);
```



## ② WAIT信号（I/Oアクセス・VDP同期）のハンドリング
CPUを2倍（7.16MHz）やそれ以上で動かしても、MSXの周辺集積回路（VDPや音源、スロットのカートリッジ）は元の3.58MHz基準でしか応答できません。
そのため、ラッパー（またはその直上のI/Oデコーダ）は以下の制御を行います。



* I/O・メモリアクセス時の自動低速化: CPUがスロットやVDPへアクセス（MREQ や IORQ がアクティブ）した瞬間をラッパー側で検知し、CPUの WAIT_n 信号を一時的に下げてCPUを待たせるか、そのアクセスサイクル中だけ cpu_clken を強制的に「ノーマル（3.58MHz）」のタイミングへ引き落とします。 [3] 

* これを怠ると、CPUだけが先走ってしまい、VDPへのデータの書き込みこぼしや読み込みエラーが発生し、画面が化けたりフリーズしたりします。

  

## ③ 双方向データバス（3ステート）のタイミングマージン逼迫
VHDLのT80は、CLKEN が 1 になった瞬間（マスタークロックの立ち上がり）にデータバスのアドレスを確定させ、データを読み込みます。



* Turboモードで周波数が上がると、「アドレスを出力してから、メモリや周辺機器がデータを返さなければならないタイムリミット（セットアップ時間）」が半分以下に激減します。

* ラッパー内でVerilogとVHDLの信号を仲介する際、少しでも無駄な論理ゲート（ディレイ）が挟まるとタイミングエラーを起こすため、ラッパー内の双方向バッファ（inout 処理）は極めてタイトに（ノンブロッキング代入 = ではなく assign やレジスタ直結で）記述される必要があります。

  

------------------------------
## まとめ：ラッパーが果たす究極の役割
Turboモード時におけるラッパーの役割は、「外の世界（3.58MHz固定の周辺機器）には何事も起きていないように見せかけつつ、内なるZ80コア（T80）の CLKEN だけを高速にパタパタと煽り、I/Oアクセスの瞬間だけブレーキをかける（WAITをかける）」という高度な交通整理です。 [3] 
もし、ご自身でMSXnanoのCPUをさらに高速化（14MHz超など）させたり、Turbo対応の自作I/OをVerilog側に追加したい場合は、「どのI/Oポートアクセス時にCPUのCLKENを減速（WAIT）させるか」のロジックをラッパー周辺へ追記することになります。
このあたりの具体的なレジスタ制御（Gowin EDAでのシンセシスエラー対策など）や実際のコード例でさらに気になる部分はありますか？

[1] [https://github.com](https://github.com/libretro/RetroArch/issues/13349)
[2] [https://docs.nvidia.com](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonOrinNanoSeriesJetsonOrinNxSeriesAndJetsonAgxOrinSeries.html)
[3] [https://www.msx.org](https://www.msx.org/forum/msx-talk/general-discussion/how-does-this-cpu-turbo-mode-537-mhz-work)
