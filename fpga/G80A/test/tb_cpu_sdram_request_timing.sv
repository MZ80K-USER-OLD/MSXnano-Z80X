`timescale 1ns/1ps
module tb_cpu_sdram_request_timing;
    reg clk = 0;
    always #10 clk = ~clk;
    reg reset_n = 0;
    reg update_addr = 0;
    reg active = 0;
    reg mreq_only = 0;
    reg falling = 0;
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
        .clk_falling_3m6_54(falling),
        .mmu_physical_bank(8'h01), .extended_addr(24'h019000),
        .extended_mreq_n(~(active || mreq_only)), .bus_rd_n(~(active && !is_write)),
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
            mreq_only = 0;
            falling = 0;
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

    task pulse_falling;
        begin
            repeat (6) @(negedge clk);
            falling = 1;
            @(negedge clk);
            falling = 0;
        end
    endtask

    // Internal (NoRead) M-cycles and interrupt acknowledge never assert
    // MREQ, even when the PC bank is non-zero in M2.
    task check_internal_cycle;
        begin
            reset_and_arm;
            pulse_falling;
            pulse_falling;
            @(negedge clk);
            if (frontend.cpu_sdram_wait_n !== 0)
                $fatal(1, "Internal cycle released before the third falling edge");
            pulse_falling;
            repeat (2) @(negedge clk);
            if (frontend.cpu_sdram_wait_n !== 1 || frontend.wait_state !== 0 || req !== 0)
                $fatal(1, "Internal cycle deadlocked: wait_n=%b state=%0d req=%b",
                       frontend.cpu_sdram_wait_n, frontend.wait_state, req);
            repeat (12) begin
                @(negedge clk);
                if (req !== 0 || memory.sdram_seq != 0)
                    $fatal(1, "Internal cycle issued an SDRAM request");
            end
            $display("PASS: internal M-cycle releases WAIT after three falling edges");
        end
    endtask

    // A write cycle asserts MREQ at the first falling edge but WR only at
    // the second; MREQ must keep WAIT armed until the request is serviced.
    task check_late_write;
        begin
            is_write = 1;
            reset_and_arm;
            pulse_falling;
            mreq_only = 1;
            pulse_falling;
            pulse_falling;
            pulse_falling;
            @(negedge clk);
            if (frontend.cpu_sdram_wait_n !== 0 || frontend.wait_state !== 1)
                $fatal(1, "Memory cycle with MREQ was released as internal");
            active = 1;
            while (!done) @(negedge clk);
            @(negedge clk);
            if (frontend.cpu_sdram_wait_n !== 1 || memory.sdram_addr !== 23'h659000)
                $fatal(1, "Late write was not serviced");
            active = 0;
            mreq_only = 0;
            $display("PASS: MREQ-held write is serviced after late WR");
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
        check_internal_cycle;
        check_late_write;
        $display("PASS: 20 request timing regression cases (fixed RTL)");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout");
    end
endmodule
