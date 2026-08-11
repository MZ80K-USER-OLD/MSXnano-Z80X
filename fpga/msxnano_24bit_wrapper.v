module msxnano_24bit_wrapper (
    input wire clk,
    input wire rst_n,
    input wire [15:0] t80_addr,
    input wire [7:0] t80_data_out,
    input wire t80_mreq_n,
    input wire t80_iorq_n,
    input wire t80_rd_n,
    input wire t80_wr_n,
    output wire [23:0] sdram_addr
);

    // 24bit拡張用バンクレジスタ
    reg [7:0] HL_B;
    reg [7:0] BC_B;
    reg [7:0] DE_B;
    reg [7:0] IX_B;
    reg [7:0] IY_B;
    reg [7:0] PC_B;
    reg [7:0] MSP_B;
    reg [7:0] INT_B;

    // 2ビットモードフラグ: 00=M0, 01=M1, 10=M2
    reg [1:0] M;

    wire memory_access = (t80_mreq_n == 1'b0);
    wire io_write = (t80_iorq_n == 1'b0 && t80_wr_n == 1'b0);

    // 簡易判定フラグ: 実際のT80命令フェッチ判定には M1_n 等の追加信号が必要です。
    wire is_fetch = memory_access && (t80_addr[15:12] <= 4'h7); // 仮条件
    wire is_stack = memory_access && (t80_addr[15:12] == 4'hF); // 仮条件
    wire is_data_access = memory_access && !is_fetch && !is_stack;

    // データアクセス種別のスケルトン判定
    wire is_data_bc = is_data_access && (t80_addr[15:8] == 8'h01); // 仮条件
    wire is_data_de = is_data_access && (t80_addr[15:8] == 8'h02); // 仮条件
    wire is_data_ix = is_data_access && (t80_addr[15:8] == 8'h03); // 仮条件
    wire is_data_iy = is_data_access && (t80_addr[15:8] == 8'h04); // 仮条件
    wire is_data_hl = is_data_access && !(is_data_bc || is_data_de || is_data_ix || is_data_iy);

    wire [7:0] data_bank = is_data_bc ? BC_B :
                          is_data_de ? DE_B :
                          is_data_ix ? IX_B :
                          is_data_iy ? IY_B :
                          HL_B;

    wire [7:0] bank_hi = (M == 2'b00) ? 8'h00 :
                         (M == 2'b01) ? ((is_fetch || is_stack) ? 8'h00 : data_bank) :
                         (M == 2'b10) ? (is_fetch ? PC_B : (is_stack ? MSP_B : data_bank)) :
                         8'h00;

    assign sdram_addr = {bank_hi, t80_addr};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            HL_B <= 8'h00;
            BC_B <= 8'h00;
            DE_B <= 8'h00;
            IX_B <= 8'h00;
            IY_B <= 8'h00;
            PC_B <= 8'h00;
            MSP_B <= 8'h00;
            INT_B <= 8'h00;
            M <= 2'b00;
        end else begin
            if (io_write) begin
                case (t80_addr[7:0])
                    8'h70: M <= 2'b00; // SET_M0
                    8'h80: M <= 2'b01; // SET_M1
                    8'h90: M <= 2'b10; // SET_M2
                    8'h74: BC_B <= t80_data_out;
                    8'h84: DE_B <= t80_data_out;
                    8'h94: HL_B <= t80_data_out;
                    8'hA4: INT_B <= t80_data_out;
                    8'hB5: MSP_B <= t80_data_out;
                    8'hC4: PC_B <= t80_data_out;
                    8'hD4: IX_B <= t80_data_out;
                    8'hE4: IY_B <= t80_data_out;
                    default: begin end
                endcase
            end
        end
    end

endmodule
