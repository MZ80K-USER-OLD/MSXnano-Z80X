To Do リストを更新しました

CPU から見える 24-bit アドレス空間に限定し、`bus_addr` の生成から Mapper／MegaRAM／MegaROM／VRAM／SDRAM への変換を追います。まずアドレス幅、ページ境界、各デバイスの選択条件を近い実装だけで突き合わせ、24-bit として成立している部分と、実際には 22／25-bit に制限される部分を切り分けます。

Search complete: 24ビットアドレス経路を調査

Searched for files matching `**/fpga/top.v`, 1 match

Searched for files matching `**/fpga/memory_ctrl.v`, no matches

Searched for files matching `**/fpga/megaram_scc.v`, no matches

Searched for files matching `**/fpga/flash.v`, no matches

Searched for regex `bus_addr|CPU.*address|24-bit.*address|address.*24` (`**/fpga/**`), 395 results

Searched for regex `MSX.*64KB|Mapper.*4MB|MegaRAM.*2MB|MegaROM.*Flash|SDRAM|VDP.*VRAM` (`**/fpga/**`), 892 results

Searched for regex `address.*convert|addr.*map|bank.*select|bank.*switch` (`**/fpga/**`), 23 results

Searched for files matching `**/fpga/*.v`, 2 matches

Read , lines 1 to 260

Read , lines 1 to 260

Read , lines 1 to 260

Read , lines 700 to 920

Read , lines 1 to 260

Read 

Read 

Read , lines 1 to 260

Read , lines 1 to 260

Read , lines 700 to 920

Read , lines 240 to 320

Read , lines 1 to 260

調査結果から、CPU の物理アドレス線自体は 16-bit で、24-bit を一度に CPU が出す設計ではありません。現在の 24-bit 相当は「16-bit CPU アドレス + Mapper レジスタ」で実現するバンク方式なので、次に `memory_ctrl` と `megaram_scc` の実装を確認して、上位ビットが SDRAM へどう届くかを確定します。

Read , lines 1 to 220

No matches found. Your search pattern might be excluded completely by either the search.exclude settings or .*ignore files.
If you believe that it should have results, you can check into the .*ignore files and the exclude setting (here are some excluded patterns for reference:[**/node_modules,**/bower_components,**/*.code-search]).
Then if you want to include those files you can call the tool again by setting "includeIgnoredFiles" to true.

Searched for regex `mapper_addr|mapper_reg|megaram_addr|assign megaram|wire \[21:0\]|wire \[20:0\]|bus_addr` (`**/fpga/top.v`), 113 results

No matches found. Your search pattern might be excluded completely by either the search.exclude settings or .*ignore files.
If you believe that it should have results, you can check into the .*ignore files and the exclude setting (here are some excluded patterns for reference:[**/node_modules,**/bower_components,**/*.code-search]).
Then if you want to include those files you can call the tool again by setting "includeIgnoredFiles" to true.

Searched for regex `assign mapper_addr|megaram_addr|input wire \[21:0\]|input wire \[20:0\]` (`**/fpga/**`), 34 results

`memory_ctrl` まで追うと、Mapper は 22-bit、MegaRAM は 21-bit、VDP VRAM は 17-bit で、SDRAM 側はさらに Mapper に 0 を前置し、MegaRAM に `10`／`010` の領域タグを付けています。つまり 24-bit の線形アドレスではなく、デバイスごとに別々のアドレス空間へ割り当てる方式です。残る `megaram.v` の変換式と合成ログの警告を確認して、評価を確定します。

Read , lines 1 to 140

Read , lines 1 to 125

Read , lines 1045 to 1145

Read , lines 100 to 135

## 結論

現在の設計は、CPU から 24-bit の線形アドレスを直接出す構成ではありません。

`G80a` の CPU アドレスバスは 16-bit です。

```verilog
wire [15:0] bus_addr;
```

`top.v:380-384`

したがって CPU が直接指定できる範囲は `0000h` から `FFFFh` までです。4 MB Mapper や 2 MB MegaRAM は、MSX 標準のバンク切り替え方式により、

```text
CPU 16-bit アドレス
    +
バンクレジスタ
    =
SDRAM 側の 21～22-bit アドレス
```

として実現されています。

## Mapper: 実質 22-bit、最大 4 MB

Mapper の CPU 側ウィンドウは 16 KB 単位です。

```verilog
assign mapper_addr =
    (bus_addr[15:14] == 2'b00) ? { mapper_reg0, bus_addr[13:0] } :
    (bus_addr[15:14] == 2'b01) ? { mapper_reg1, bus_addr[13:0] } :
    (bus_addr[15:14] == 2'b10) ? { mapper_reg2, bus_addr[13:0] } :
                                  { mapper_reg3, bus_addr[13:0] };
```

`top.v:1060-1070`

アドレス構成は次の通りです。

```text
mapper_reg[7:0] + bus_addr[13:0]
       8 bit          14 bit
             合計 22 bit
```

つまり、

```text
256 バンク × 16 KB = 4 MB
```

です。

CPU からは以下のように見えます。

| CPU アドレス | 使用レジスタ | SDRAM 側アドレス |
|---|---:|---:|
| `0000h-3FFFh` | `mapper_reg0` | `{reg0, 0000h-3FFFh}` |
| `4000h-7FFFh` | `mapper_reg1` | `{reg1, 0000h-3FFFh}` |
| `8000h-BFFFh` | `mapper_reg2` | `{reg2, 0000h-3FFFh}` |
| `C000h-FFFFh` | `mapper_reg3` | `{reg3, 0000h-3FFFh}` |

Mapper レジスタは `FC00h` から `FC03h` ではなく、I/O 空間の `FCh` から `FFh` に対する書き込みとして扱われています。

```verilog
assign mapper_reg_write =
    (bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)
    && (bus_addr[7:2] == 6'b111111);
```

`top.v:1077-1099`

`SDRAM_32` が有効なため、Mapper レジスタは 8-bit 全体を使用します。従って現在の Mapper は、実質的には 22-bit アドレス、4 MB です。

## SDRAM 上の Mapper 配置

`memory_ctrl` では Mapper アドレスに 0 を前置しています。

```verilog
sdram_addr <= { 1'b0, mapper_addr[21:0] };
```

`memory.v:88-103`

したがって SDRAM 内ではおおむね、

```text
Mapper: 0x000000 - 0x3FFFFF
```

に配置されます。

24-bit のアドレス表記に換算すると、Mapper の最大アドレスは `0x3FFFFF` です。`0x400000` 以上は Mapper 用には使われません。

## MegaRAM: 実質 21-bit、最大 2 MB

MegaRAM のアドレス出力は 21-bit です。

```verilog
output wire [20:0] megaram_addr
```

`megaram.v:1-18`

通常のバンク方式では、8-bit バンクレジスタと CPU アドレス下位 13-bit を結合します。

```verilog
assign megaram_addr =
    (bus_addr[14:13] == 2'b10) ? { megaram_reg0, bus_addr[12:0] } :
    (bus_addr[14:13] == 2'b11) ? { megaram_reg1, bus_addr[12:0] } :
    (bus_addr[14:13] == 2'b00) ? { megaram_reg2, bus_addr[12:0] } :
                                  { megaram_reg3, bus_addr[12:0] };
```

`megaram.v:56-62`

構成は、

```text
8 bit バンク番号 + 13 bit オフセット = 21 bit
```

です。

```text
256 バンク × 8 KB = 2 MB
```

MegaRAM は `megaram_scc` のアクセス条件により、CPU 空間の複数領域からアクセスされます。

- `4000h-5FFFh`
- `6000h-7FFFh`
- `8000h-9FFFh`
- `A000h-BFFFh`
- `C000h-FFFFh`

実際に有効な窓は `megaram_mode_a`、`megaram_mode_b`、`map_sel` で変化します。`megaram.v:22-55`

## SDRAM 上の MegaRAM 配置

`memory_ctrl` は MegaRAM に以下のタグを付けています。

```verilog
sdram_addr <= { 3'b10, megaram_addr[20:0] };
```

`memory.v:94-103`

24-bit アドレスとして見ると、

```text
MegaRAM: 0x400000 - 0x5FFFFF
```

です。

したがって、現在の SDRAM 内部配置は概ね次のようになります。

```text
0x000000 - 0x3FFFFF : Mapper 4 MB
0x400000 - 0x5FFFFF : MegaRAM 2 MB
```

Mapper と MegaRAM はアドレス範囲が重ならないように分離されています。

## MegaROM / Flash: 24-bit ではなくページ方式

MegaROM のアドレスは次の式で生成されています。

```verilog
assign megarom_addr =
    { 8'b00001000, megarom_page, bus_addr[13:0] };
```

`top.v:1523-1533`

構成は、

```text
8 bit 固定値 + 3 bit ページ + 14 bit CPU オフセット
```

ですが、`8'b00001000` は Flash 側のアドレス上位部として使われ、CPU が指定するアドレスそのものではありません。

CPU 側では `6000h` への書き込みで `megarom_page` を変更します。

```verilog
megarom_page_req <=
    bus_addr == 16'h6000;
```

ページレジスタは 3-bit なので、現在の実装で選択できるのは 8 ページです。

```text
8 ページ × 16 KB = 128 KB
```

ただし `megarom_addr` 自体は 25-bit です。

```text
8 bit 固定部 + 3 bit ページ + 14 bit オフセット = 25 bit
```

Flash 読み出し開始位置は `0x100000` です。

```verilog
ff_flash_addr <= 24'h100000;
```

`top.v:1550-1618`

ただし、Flash 側の `ff_flash_addr` は 24-bit ですが、CPU が 24-bit アドレスを直接指定しているわけではありません。CPU は、

1. ページレジスタへページ番号を書く
2. `6000h` 以降の窓を読む

という間接方式です。

## VDP VRAM: 17-bit

V9958 の VRAM アドレスは次の幅です。

```verilog
input wire [16:0] vram_addr
```

`memory.v:8-18`

トップ側からは `VdpAdr` が接続されています。

```verilog
.vram_addr(VdpAdr)
```

`top.v:1123-1141`

したがって VDP VRAM は最大 128 KB の論理アドレス空間であり、CPU の 24-bit アドレス空間とは別です。CPU は VDP ポート `98h-9Bh` を通して VDP 内部の VRAM アドレスレジスタを操作します。

## 24-bit アドレスとしての現在の評価

24-bit の線形メモリマップとして評価すると、現在の設計は次の状態です。

| デバイス | 有効アドレス幅 | 容量 | SDRAM／Flash上の位置 |
|---|---:|---:|---:|
| Mapper | 22-bit | 4 MB | `0x000000-0x3FFFFF` |
| MegaRAM | 21-bit | 2 MB | `0x400000-0x5FFFFF` |
| VDP VRAM | 17-bit | 最大 128 KB | VDP専用 |
| MegaROM | ページ方式 | 現状8ページ相当 | Flash `0x100000` 起点 |
| SD sector RAM | 9-bit | 512 byte | CPU窓 `7C00h-7DFFh` |

従って、

```text
CPUから24-bitアドレスを直接指定できる
```

とは評価できません。

正確には、

```text
CPUの16-bitアドレス空間
+ Mapper／MegaRAM／MegaROMのバンクレジスタ
```

で、内部メモリの 21～25-bit 相当のアドレスを生成しています。

## 重要な実装上の問題

### 1. `megaram_addr` の暗黙宣言

`top.v` では `memory_ctrl` のインスタンス接続時点で `megaram_addr` が宣言されておらず、後から宣言されています。

```verilog
.megraram_addr(megaram_addr)
```

付近で暗黙 wire として扱われた後、後方で次が出現します。

```verilog
wire [20:0] megaram_addr;
```

合成ログにも次の警告があります。

```text
Undeclared symbol 'megaram_addr', assumed default net type 'wire'
'megaram_addr' is already implicitly declared
```

このため、24-bit／21-bit のアドレス幅評価を曖昧にする要因になっています。アドレス信号は `memory_ctrl` のインスタンスより前で明示的に宣言すべきです。

### 2. Mapper レジスタが二重に存在する

`top.v` には次の2種類の Mapper レジスタがあります。

```verilog
mapper_reg_fc
mapper_reg_fd
mapper_reg_fe
mapper_reg_ff
```

`top.v:555-585`

と、

```verilog
mapper_reg0
mapper_reg1
mapper_reg2
mapper_reg3
```

`top.v:1060-1099`

実際の `mapper_addr` 生成に使用されるのは後者です。前者は読み出し用の `mapper_read_data` に使われていますが、両者は同じ書き込みアクセスに反応します。

そのため、Mapper レジスタの読み戻し値と、実際のメモリバンク選択値が一致しない可能性があります。24-bit 相当のアドレス指定を正確に評価するうえで、これは明確な不整合候補です。

### 3. MegaRAM の線形モードは 2 MB 全体を CPU から直接見せない

`map_linear` が有効な場合でも、式は次の通りです。

```verilog
{ 5'b00000, bus_addr }
```

`megaram.v:56-57`

これは CPU の 16-bit アドレスを 21-bit にゼロ拡張しているだけです。したがって線形モードでも一度に見えるのは 64 KB であり、2 MB 全体を 24-bit 空間として直接見せるものではありません。

## 最終判定

現在のアドレス設計は、MSX としては妥当なバンク切り替え方式です。

- CPU アドレス: 16-bit
- Mapper: 4 MB を 16 KB 窓で切り替え
- MegaRAM: 2 MB を 8 KB 窓で切り替え
- MegaROM: ページレジスタによる Flash 窓
- SDRAM: デバイスごとに固定領域へ配置

ただし、「CPU から 24-bit アドレス指定できるか」という観点では **できません**。24-bit 相当のアドレスは内部で生成されますが、CPU が持つのは 16-bit アドレスとバンク切り替え用 I/O だけです。

特に修正・確認優先度が高いのは、次の2点です。

1. `megaram_addr` をインスタンスより前で明示宣言する  
2. `mapper_reg_fc..ff` と `mapper_reg0..3` の二重管理を整理する

To Do 項目が 2 件作成されました