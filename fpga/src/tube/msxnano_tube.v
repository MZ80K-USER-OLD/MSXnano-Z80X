`timescale 1ns / 1ps

// ============================================================
// msxnano_tube.v
//
// MSXnano Z80 I/O bus <-> BeebFPGA Acorn Tube ULA
//
// The actual Tube protocol/FIFO/IRQ/NMI implementation is
// provided by hoglet67/BeebFpga src/common/Tube/tube.v.
//
// MSX side:
//   io_addr[2:0] : Tube register number
//   io_cs        : active high
//   io_rd        : active high
//   io_wr        : active high
//   io_wdata     : Z80 output data
//   io_rdata     : Z80 input data
//
// Tube Host side:
//   h_addr
//   h_cs_b
//   h_data_in
//   h_data_out
//   h_phi2
//   h_rdnw
//   h_rst_b
//   h_irq_b
//
// Tube Parasite side is exported to the DOCK/external CPU.
//
// ============================================================

module msxnano_tube (

    input  wire        reset_n,

    // --------------------------------------------------------
    // MSX/Z80 I/O bus
    // --------------------------------------------------------
    input  wire [7:0]  io_addr,
    input  wire        io_iorq_n,
    input  wire        io_m1_n,
    input  wire        io_rd_n,
    input  wire        io_wr_n,
    input  wire [7:0]  io_wdata,

    output reg  [7:0]  io_rdata,

    // --------------------------------------------------------
    // Z80 clock / PHI2 equivalent
    //
    // For MSXnano this should normally be the 3.6MHz bus
    // clock, not the 54MHz internal FPGA clock.
    // --------------------------------------------------------
    input  wire        phi2,

    // --------------------------------------------------------
    // Interrupt to MSX Z80
    // Active low
    // --------------------------------------------------------
    output wire        irq_n,

    // Host-side signals exposed for the external control bus.
    output wire [2:0]  host_addr,
    output wire        host_cs_n,
    output wire        host_rnw,

    // --------------------------------------------------------
    // Tube parasite interface
    //
    // These signals are the interface to the external
    // Tube coprocessor / DOCK.
    // --------------------------------------------------------
    output wire [2:0]  tube_p_addr,
    output wire        tube_p_cs_n,
    inout  wire [7:0]  ext_tube_data,
    output wire        tube_p_rdnw,

    output wire        tube_p_phi2,

    output wire        tube_p_reset_n,
    output wire        tube_p_nmi_n,
    output wire        tube_p_irq_n
);

    wire [7:0] tube_p_data_in;
    wire [7:0] tube_p_data_out;

    assign tube_p_data_in = ext_tube_data;
    assign ext_tube_data = (tube_p_rdnw && !tube_p_cs_n)
                       ? tube_p_data_out
                       : 8'bz;

    // ========================================================
    // MSX I/O cycle detection
    // ========================================================
  
    wire tube_io_cycle;

    assign tube_io_cycle =
        (io_iorq_n == 1'b0) &&
        (io_m1_n   == 1'b1) &&
        (io_addr[7:3] == 5'b00000);

    wire tube_io_read;
    wire tube_io_write;

    assign tube_io_read =
        tube_io_cycle &&
        (io_rd_n == 1'b0);

    assign tube_io_write =
        tube_io_cycle &&
        (io_wr_n == 1'b0);

    // --------------------------------------------------------
    // Tube Parasite
    // --------------------------------------------------------
    assign tube_p_addr = io_addr[2:0];
    assign tube_p_cs_n = ~tube_io_cycle;
    assign tube_p_rdnw = tube_io_read;
    assign tube_p_phi2 = phi2;

    // --------------------------------------------------------
    // Tube register address
    // --------------------------------------------------------

    wire [2:0] tube_reg_addr;

    assign tube_reg_addr = io_addr[2:0];

    // ========================================================
    // Host side of Acorn Tube
    // ========================================================
    wire tube_h_cs_n;

    wire [7:0] h_data_out;
    wire       h_irq_n;

    wire [7:0] h_data_in;

    assign h_data_in = io_wdata;

    // Tube host chip select is active low.
    assign tube_h_cs_n = ~tube_io_cycle;

    // Tube uses RDNW:
    //
    //   1 = read
    //   0 = write
    //
    wire h_rdnw;

    assign h_rdnw = tube_io_read;

    assign host_addr = tube_reg_addr;
    assign host_cs_n = tube_h_cs_n;
    assign host_rnw  = h_rdnw;

    // ========================================================
    // Read data back to Z80
    // ========================================================

    always @(*) begin
        io_rdata = 8'hFF;

        if (tube_io_read)
            io_rdata = h_data_out;
    end

    // ========================================================
    // Tube host side
    // ========================================================

    tube tube_core (

        // ----------------------------------------------------
        // HOST SIDE
        // ----------------------------------------------------

        .h_addr     (tube_reg_addr),
        .h_cs_b     (tube_h_cs_n),

        .h_data_in  (h_data_in),
        .h_data_out (h_data_out),

        .h_phi2     (phi2),
        .h_rdnw     (h_rdnw),
        .h_rst_b    (reset_n),

        .h_irq_b    (h_irq_n),

        // ----------------------------------------------------
        // PARASITE SIDE
        // ----------------------------------------------------

        .p_addr     (tube_p_addr),
        .p_cs_b     (tube_p_cs_n),

        .p_data_in  (tube_p_data_in),
        .p_data_out (tube_p_data_out),

        .p_rdnw     (tube_p_rdnw),
        .p_phi2     (tube_p_phi2),

        .p_rst_b    (tube_p_reset_n),
        .p_nmi_b    (tube_p_nmi_n),
        .p_irq_b    (tube_p_irq_n)

    );

    assign irq_n = h_irq_n;

endmodule