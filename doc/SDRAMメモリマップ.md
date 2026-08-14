
SD-RAMメモリマップ



　MSXnano（移植元である [jabadiagm/MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauld_tn20k) および [RetroSilicon/MSXnano](https://github.com/RetroSilicon/MSXnano) コア）における、Tang Nano 20K内蔵 8MB SD-RAM（16ビット幅＝計4Mワード空間）への具体的な物理アドレスマッピング（定数定義・デコードロジック）を解説します。 [1] 
MSXnanoの最上位階層（emsx_top.vhd や sdram_vldm.v）では、32MB用だったonechipMSXのアドレスデコード（24bit/25bit長）を、8MB空間（22bitワードアドレス、または23bitバイトアドレス）に合わせてコンパクトに詰め直しています。

回路記述（VHDL/Verilog）の最上位レイイルで定義されている、SD-RAM側から見た「物理アドレス（ワード表現 / バイト表現）」の割り当てマップは以下の通りです。

## 1. MSXnano SD-RAM 物理アドレス配置表
8MBの空間は、アドレスの上位ビット（MemAdr）のデコードロジックによって、綺麗に以下のように切り分けられています。
※ ワードアドレス（16bit単位） と、Z80側から見た バイトアドレス（8bit単位） の両方で表記します。

| 領域名（機能） | ワードアドレス（16bit幅） | バイトアドレス（8bit換算） | 容量 | 回路上の主な判定条件（上位ビット） |
|---|---|---|---|---|
| Memory Mapper (メインRAM) | 000000h 〜 1FFFFFh | 000000h 〜 3FFFFFh | 4MB | MemAdr(21) = '0' |
| MegaRAM / MegaROM (SCC) | 200000h 〜 2FFFFFh | 400000h 〜 5FFFFFh | 2MB | MemAdr(21 downto 20) = "10" |
| VRAM (V9958用ビデオメモリ) | 300000h 〜 31FFFFh | 600000h 〜 63FFFFh | 256KB | MemAdr(21 downto 17) = "11000" |
| 【空き領域】 | 320000h 〜 37FFFFh | 640000h 〜 6FFFFFh | 約768KB | 予約・未使用エリア |
| MAIN-ROM / SUB-ROM | 380000h 〜 3BFFFFh | 700000h 〜 77FFFFh | 512KB | MemAdr(21 downto 18) = "1110" |
| NEXTOR / DISK-BIOS | 3C0000h 〜 3DFFFFh | 780000h 〜 7BFFFFh | 256KB | MemAdr(21 downto 17) = "11110" |
| KANJI / OPLL (内蔵ROM等) | 3E0000h 〜 3FFFFFh | 7C0000h 〜 7FFFFFh | 256KB | MemAdr(21 downto 17) = "11111" |

------------------------------
## 2. ソースコード（定数定義・接続ロジック）の解説
onechipMSXからMSXnanoへ移植される際、各内部デバイス（Mapper、VRAM、各ROMスロット）が要求する「デバイス側アドレス」を、SD-RAMコントローラへ引き渡す直前で以下のように結合（マッピング）しています。
## ① メインRAM（Memory Mapper）の結合
MSXnanoのMemory Mapperは、最大4MBまでサポートします（MapAdr(21 downto 0)）。 [2, 3] 



* 回路上のマッピング処理:

-- メインRAM要求時、SD-RAMアドレスの最上位(21)を '0' に固定して下位21bitをそのまま割り当てる
pMemAdr <= "0" & MapAdr(21 downto 1); -- ワードアドレス化

これにより、8MB全体の「前半4MB」が丸ごとマッパーRAMとして排他的に確保されます。



## ② MegaRAM / MegaROM の結合
SoRunなどでゲームを読み込むために使われる2MBのMegaRAM領域 は、マッパーの直後（4MB目〜6MB目の間）に配置されます。 [3] 



* 回路上のマッピング処理:

-- MegaRAM要求時、上位2bitを "10"（4MBオフセット）にする
pMemAdr <= "10" & MegaRamAdr(19 downto 1); 



## ③ VRAMおよび各種内蔵ROMの結合
残りの2MB（400000h〜）の後半エリアに、VRAMとシステムROM類が集中的にマッピングされます。
onechipMSXでは、VRAMは 080000h 付近、ROMは 100000h 付近というように32MB空間に広く分散していましたが、MSXnanoでは以下のように空きを詰め、上位ビットを「11...」に固定したエリアに押し込まれています。



* VRAM（256KB分）: 300000h（バイト換算 600000h）から配置。

* MAIN/SUB BIOS（512KB分）: 380000h（バイト換算 700000h）から配置。SDカード上の OCM-BIOS.DAT からIPL（初期ローダー）によって起動時にこの番地へ書き込まれます。

  

------------------------------
## 3. onechipMSXとの最大の違い
onechipMSX（DE1版など）では、MegaROMシミュレータ等のために 200000h（2MBワード＝4MBバイト）〜 FFFFFFh（16MBワード＝32MBバイト）の広大なエリアが割り当てられていましたが、MSXnanoでは物理上限が8MB（ワードアドレスで 3FFFFFh まで）であるため、これ以上の番地を指定するとアドレスがラップアラウンド（一巡）してメモリ内容が破壊されます。
そのため、MSXnano向けにBIOSをカスタマイズしたり、FPGAのロジックを改造して別のデバイス（追加のサウンドROMなど）をSD-RAM上に載せたい場合は、未使用（予約）領域となっている 320000h 〜 37FFFFh（バイト換算 640000h 〜 6FFFFFh の約768KB）をターゲットにしてデコード定数を定義するのが安全です。
もし、特定のデバイス（例：OPLL ROMや漢字ROMデータ）がソースコード内のどのファイル・何行目の定数で定義されているかをピンポイントで追跡したい場合は、対象としたいソースファイル名や機能を指定していただければ、さらに詳しくコードを読み解きます。

[1] [https://github.com](https://github.com/jabadiagm/MSXgoauld_tn20k)
[2] [https://github.com](https://github.com/mist-devel/MSX_MiST/blob/master/esemsx3/src/emsx_top.vhd.msx2)
[3] [https://qiita.com](https://qiita.com/kazueda/items/6da6a342ece202f66462)

SDRAM物理アドレスマッピング一覧物理

| アドレス範囲（16進数） | 割り当てサイズ | 主な用途・機能                                               |
| ---------------------- | -------------- | ------------------------------------------------------------ |
| 0x000000 〜 0x3FFFFF   | 4MB            | メインRAM（Memory Mapper）Nextor OSや通常のMSX2+ソフトが使用する広大なRAM空間 |
| 0x400000 〜 0x5FFFFF   | 2MB            | MegaRAM / SCC拡張RAM大容量ROMゲーム（コナミのSCC音源入りゲームなど）の読み込み・実行用 |
| 0x600000 〜 0x7FFFFF   | 2MB            | 未使用 または 将来の拡張用（VRAM領域など）現状は余裕を持たせている空き空間 |


​			
​			


VDP VRAM:
    論理アドレス  0x00000 ～ 0x1FFFF
    容量          128 KiB
    SD-RAM bank   3
