// Standard (non-24bit) CPU wrapper, used only by the MSXNanoTang20K_Std.gprj
// project (see doc/jpn/Std_T80ビルド構成.md). This wraps the pristine,
// unmodified G80A/T80 core (fpga/G80A_Std/, byte-identical to the
// pre-Z80X24 baseline at commit 1ea61d1) instead of the 24bit-extended
// core used by MSXnano_CPU_Wrapper24.v / fpga/G80A/.
//
// The module name and the entire port list are kept IDENTICAL to
// MSXnano_CPU_Wrapper24.v on purpose, so that top.v can be shared,
// unmodified, by both projects: whichever .gprj's file list is active
// simply determines which implementation of this module gets
// synthesized. The 24bit-only outputs (mode24/bank_*) are tied to
// constant 0 here since the pristine core has no such signals, which
// matches their always-00h/M0 value in the Z80X24 build whenever 24bit
// mode is never engaged.
module MSXnano_CPU_Wrapper24 #(
    parameter integer Mode,
    parameter integer IOWait
)(
    input  wire        RESET_n,
    input  wire        CLK_n,
    input  wire        clk_enable,
    input  wire        clk_falling,
    input  wire        WAIT_n,
    input  wire        INT_n,
    input  wire        NMI_n,
    input  wire        BUSRQ_n,
    output wire        M1_n,
    output wire        MREQ_n,
    output wire        IORQ_n,
    output wire        RD_n,
    output wire        WR_n,
    output wire        RFSH_n,
    output wire        HALT_n,
    output wire        BUSAK_n,
    output wire [23:0] A,
    output wire        update_addr,
    input  wire [7:0]  DI,
    output wire [7:0]  DO,
    output wire [1:0]  mode24,
    output wire [7:0]  bank_bc,
    output wire [7:0]  bank_de,
    output wire [7:0]  bank_hl,
    output wire [7:0]  bank_ix,
    output wire [7:0]  bank_iy,
    output wire [7:0]  bank_pc,
    output wire [7:0]  bank_msp,
    output wire [7:0]  bank_int,
    output wire [7:0]  bank_nvr,
    output wire [7:0]  bank_rst,
    output wire        Data_Reverse
);

    wire [15:0] cpu_addr;

    // The pristine G80A has no A_Bank output; the 24bit address bus is
    // simply the plain 16bit address zero-extended, exactly matching the
    // Z80X24 build's behaviour whenever mode24=M0 (A_Bank always 00h).
    assign A = {8'h00, cpu_addr};

    assign mode24   = 2'b00;
    assign bank_bc  = 8'h00;
    assign bank_de  = 8'h00;
    assign bank_hl  = 8'h00;
    assign bank_ix  = 8'h00;
    assign bank_iy  = 8'h00;
    assign bank_pc  = 8'h00;
    assign bank_msp = 8'h00;
    assign bank_int = 8'h00;
    assign bank_nvr = 8'h00;
    assign bank_rst = 8'h00;

    G80a  #(
        .Mode    (Mode),  // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        .IOWait   (IOWait) // 0 => Single I/O cycle, 1 => Std I/O cycle
    ) cpu1 (
        .RESET_n      (RESET_n),
        .CLK_n        (CLK_n),
        .clk_enable   (clk_enable),
        .clk_falling  (clk_falling),
        .WAIT_n       (WAIT_n),
        .INT_n        (INT_n),
        .NMI_n        (NMI_n),
        .BUSRQ_n      (BUSRQ_n),
        .M1_n         (M1_n),
        .MREQ_n       (MREQ_n),
        .IORQ_n       (IORQ_n),
        .RD_n         (RD_n),
        .WR_n         (WR_n),
        .RFSH_n       (RFSH_n),
        .HALT_n       (HALT_n),
        .BUSAK_n      (BUSAK_n),
        .A            (cpu_addr),
        .update_addr  (update_addr),
        .DI           (DI),
        .DO           (DO),
        .Data_Reverse (Data_Reverse)
    );

endmodule
