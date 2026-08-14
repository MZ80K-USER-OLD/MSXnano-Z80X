module msxnano_24bit_wrapper (
    input wire [15:0] t80_addr,
    input wire [2:0] t80_reg_pair,
    input wire t80_mreq_n,
    input wire [1:0] mode24,
    output wire [23:0] sdram_addr
);

    localparam [1:0] MODE_Z80 = 2'b00;
    localparam [1:0] MODE_REG = 2'b01;
    localparam [1:0] MODE_EXT = 2'b10;

    wire memory_access = (t80_mreq_n == 1'b0);
    reg [7:0] bank_hi;

    always @* begin
        bank_hi = 8'h00;

        if (memory_access) begin
            case (mode24)
                MODE_Z80: bank_hi = 8'h00;
                MODE_REG: bank_hi = {5'b00000, t80_reg_pair};
                MODE_EXT: bank_hi = {3'b000, mode24, t80_reg_pair};
                default:  bank_hi = 8'h00;
            endcase
        end
    end

    assign sdram_addr = {bank_hi, t80_addr};

endmodule
