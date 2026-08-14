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
    output wire        Data_Reverse
);

    wire [15:0] cpu_addr;

    assign A = {8'b0, cpu_addr};

    G80a  #(
        .Mode    (Mode),  // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        //.T2Write (0),     //0 => WR_n active in T3, /=0 => WR_n active in T2
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
        .mode24       (mode24),
        .Data_Reverse (Data_Reverse)
    );

endmodule
