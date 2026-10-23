// Split memory requests before any MSX slot/peripheral decoding.
// I/O controls are deliberately not routed through this memory-only boundary.
module memory_bus_router24 (
    input wire [23:0] cpu_addr,
    input wire cpu_mreq_n,
    input wire cpu_rd_n,
    input wire cpu_wr_n,
    input wire cpu_rfsh_n,
    output wire [15:0] z80_addr,
    output wire z80_mreq_n,
    output wire [23:0] extended_addr,
    output wire extended_mreq_n,
    output wire extended_access
);
    wire extended_bank = (cpu_addr[23:16] != 8'h00);

    assign z80_addr = cpu_addr[15:0];
    assign extended_addr = cpu_addr;
    assign z80_mreq_n = cpu_mreq_n | extended_bank;
    assign extended_mreq_n = cpu_mreq_n | ~extended_bank;
    assign extended_access = ~extended_mreq_n & cpu_rfsh_n &
                             (~cpu_rd_n | ~cpu_wr_n);
endmodule
