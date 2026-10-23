`timescale 1ns/1ps
module tb_cpu_sdram_request_timing;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_n = 0;
    reg update_addr = 0;
    reg active = 0;
    reg mapper_req = 0;
    reg is_write = 1;
    reg video = 0;
    integer phase = 0;
    always @(negedge clk) begin
        phase = phase + 1;
        video = (phase % 8) < 4;
    end
    wire req, writing;
    wire [23:0] address;
    wire done;

    cpu_request_frontend frontend (
        .clk_54m(clk), .bus_reset_n(reset_n), .update_addr(update_addr),
        .mmu_physical_bank(8'h01), .extended_addr(24'h019000),
        .extended_mreq_n(~active), .bus_rd_n(~(active && !is_write)),
        .bus_wr_n(~(active && is_write)), .bus_rfsh_n(1'b1),
        .cpu_sdram_done(done), .request(req), .writing(writing),
        .address(address)
    );

    memory_ctrl memory (
        .clk_27m(clk), .clk_108m(clk), .bus_reset_n(reset_n),
        .video_dhclk(video), .video_dlclk(video),
        .cpu_sdram_req(req), .cpu_sdram_write(writing),
        .cpu_sdram_addr(address), .mapper_din(8'h00),
        .mapper_req(mapper_req), .mapper_write(1'b0),
        .megaram_req(1'b0), .megaram_write(1'b0),
        .mapper_addr(22'h001000), .megaram_addr(21'h0),
        .vram_din(8'h00), .vram_write(1'b0), .vram_addr(17'h0),
        .bus_rfsh_n(1'b1), .cpu_sdram_done(done)
    );

    task reset_and_arm;
        begin
            @(negedge clk);
            reset_n = 0;
            active = 0;
            mapper_req = 0;
            update_addr = 0;
            repeat (3) @(negedge clk);
            reset_n = 1;
            update_addr = 1;
            repeat (4) @(negedge clk);
            if (frontend.wait_state !== 1)
                $fatal(1, "Frontend did not reach WS_ARMED");
        end
    endtask

    task check_request(input integer delay_cycles);
        begin
            reset_and_arm;
            if (delay_cycles >= 0) begin
                mapper_req = 1;
                while (memory.sdram_seq !== 1) @(negedge clk);
                repeat (delay_cycles) @(negedge clk);
            end
            active = 1;
            #1;
            if (req !== 0)
                $fatal(1, "Request published before address/write latch");
            @(negedge clk);
            mapper_req = 0;
            while (!(memory.sdram_seq == 2 && memory.sdram_owner_cpu))
                @(negedge clk);
            if (memory.sdram_addr !== 23'h659000 ||
                memory.sdram_write !== is_write)
                $fatal(1, "Stale capture: address=%h write=%b expected write=%b",
                       memory.sdram_addr, memory.sdram_write, is_write);
            if (frontend.cpu_sdram_wait_n !== 0)
                $fatal(1, "CPU released before completion");
            while (!done) @(negedge clk);
            @(negedge clk);
            if (frontend.cpu_sdram_wait_n !== 1 || req !== 0)
                $fatal(1, "Completion did not release CPU/retire request");
            // Keep the bus active after completion: it must not be resubmitted.
            repeat (12) begin
                @(negedge clk);
                if (req !== 0 || memory.sdram_seq == 1)
                    $fatal(1, "Duplicate request after completion");
            end
            active = 0;
            $display("PASS: write=%b legacy-delay=%0d address=659000 completion/retirement",
                     is_write, delay_cycles);
        end
    endtask

    integer delay_cycles;
    integer operation;
    initial begin
        for (operation = 0; operation < 2; operation = operation + 1) begin
            is_write = operation;
            for (delay_cycles = -1; delay_cycles < 8; delay_cycles = delay_cycles + 1)
                check_request(delay_cycles);
        end
        $display("PASS: 18 request timing regression cases (fixed RTL)");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout");
    end
endmodule
