// 信号の宣言（未宣言の場合）
wire       vga_g, vga_b_n, vga_vs, vga_hs, vga_r_n, vga_b, vga_g_n, vga_r;
wire [7:0] ext_tube_di; // 元のバス信号

// 代入文
assign vga_g   = ext_tube_di[7];
assign vga_b_n = ext_tube_di[6];
assign vga_vs  = ext_tube_di[5];
assign vga_hs  = ext_tube_di[4];
assign vga_r_n = ext_tube_di[3];
assign vga_b   = ext_tube_di[2];
assign vga_g_n = ext_tube_di[1];
assign vga_r   = ext_tube_di[0];



ピンアサイン

// Tube DATA
// VGA
IO_LOC "vga_r" 27;
IO_PORT "vga_r" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_r_n" 28;
IO_PORT "vga_r_n" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_g" 25;
IO_PORT "vga_g" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_g_n" 26;
IO_PORT "vga_g_n" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_b" 29;
IO_PORT "vga_b" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_b_n" 30;
IO_PORT "vga_b_n" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_vs" 31;
IO_PORT "vga_vs" IO_TYPE=LVCMOS33 DRIVE=12;
IO_LOC "vga_hs" 77;
IO_PORT "vga_hs" IO_TYPE=LVCMOS33 DRIVE=12;