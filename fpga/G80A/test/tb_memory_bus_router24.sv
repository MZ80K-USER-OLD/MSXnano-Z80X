`timescale 1ns/1ps

module tb_memory_bus_router24;
    reg [23:0] cpu_addr = 0;
    reg cpu_mreq_n = 1, cpu_rd_n = 1, cpu_wr_n = 1, cpu_rfsh_n = 1;
    reg cpu_iorq_n = 1;
    wire [15:0] bus_addr;
    wire [23:0] extended_addr;
    wire bus_mreq_n, extended_mreq_n, extended_access;
    reg [7:0] expanded_slot = 8'h00;
    reg sd_enabled = 0;
    integer bank, address_index, controls;
    reg [15:0] addresses [0:7];
    integer checks = 0;

    memory_bus_router24 dut (
        .cpu_addr(cpu_addr), .cpu_mreq_n(cpu_mreq_n),
        .cpu_rd_n(cpu_rd_n), .cpu_wr_n(cpu_wr_n), .cpu_rfsh_n(cpu_rfsh_n),
        .z80_addr(bus_addr), .z80_mreq_n(bus_mreq_n),
        .extended_addr(extended_addr), .extended_mreq_n(extended_mreq_n),
        .extended_access(extended_access)
    );

    // All primary/subslot selections enabled: worst case for legacy aliases.
    wire slot_write = !bus_mreq_n && !cpu_wr_n && bus_addr == 16'hffff;
    wire slot_read = !bus_mreq_n && !cpu_rd_n && bus_addr == 16'hffff;
    wire mapper_req = !bus_mreq_n && cpu_rfsh_n && (!cpu_rd_n || !cpu_wr_n);
    wire scc_write = !bus_mreq_n && !cpu_wr_n && bus_addr[15:11] == 5'b10010;
    wire rom_page_write = !bus_mreq_n && !cpu_wr_n && bus_addr == 16'h6000;
    wire sd_enable_write = !bus_mreq_n && !cpu_wr_n && cpu_iorq_n &&
                           bus_addr == 16'h7e00;
    wire vdp_write = !cpu_iorq_n && !cpu_wr_n && bus_addr[7:2] == 6'b100110;
    wire external_mreq_n = bus_mreq_n;

    task check_write;
        input [23:0] address;
        input [7:0] data;
        begin
            cpu_addr = address;
            cpu_mreq_n = 0; cpu_wr_n = 0; cpu_rd_n = 1;
            cpu_rfsh_n = 1; cpu_iorq_n = 1;
            #1;
            if (slot_write) expanded_slot = data;
            if (sd_enable_write) sd_enabled = data[0];
            #1;
            cpu_mreq_n = 1; cpu_wr_n = 1;
            #1;
        end
    endtask

    initial begin
        addresses[0] = 16'h0000; addresses[1] = 16'h6000;
        addresses[2] = 16'h7c00; addresses[3] = 16'h7e00;
        addresses[4] = 16'h9000; addresses[5] = 16'h9800;
        addresses[6] = 16'hfffe; addresses[7] = 16'hffff;
        // Exhaust all banks (including unsupported banks) and control patterns.
        for (bank = 0; bank < 256; bank = bank + 1)
            for (address_index = 0; address_index < 8; address_index = address_index + 1)
                for (controls = 0; controls < 32; controls = controls + 1) begin
                    cpu_addr = {bank[7:0], addresses[address_index]};
                    {cpu_iorq_n, cpu_rfsh_n, cpu_wr_n, cpu_rd_n, cpu_mreq_n} = controls[4:0];
                    #1;
                    if (bus_addr !== cpu_addr[15:0] || extended_addr !== cpu_addr)
                        $fatal(1, "Address changed");
                    if (bus_mreq_n !== (cpu_mreq_n | (bank != 0)))
                        $fatal(1, "Legacy routing mismatch");
                    if (extended_mreq_n !== (cpu_mreq_n | (bank == 0)))
                        $fatal(1, "Extended routing mismatch");
                    if (extended_access !== ((bank != 0) && !cpu_mreq_n &&
                        cpu_rfsh_n && (!cpu_rd_n || !cpu_wr_n)))
                        $fatal(1, "Extended access qualification mismatch");
                    if (!bus_mreq_n && !extended_mreq_n)
                        $fatal(1, "Both buses active");
                    if (bank != 0 && (slot_write || slot_read || mapper_req ||
                        scc_write || rom_page_write || sd_enable_write || !external_mreq_n))
                        $fatal(1, "Nonzero bank leaked into legacy device");
                    checks = checks + 1;
                end

        // The actual boundary preparation sequence must not change slot state.
        check_write(24'h01fffe, 8'hcd);
        check_write(24'h01ffff, 8'hab);
        check_write(24'h020000, 8'h07);
        if (expanded_slot !== 8'h00) $fatal(1, "Boundary write changed slot");
        check_write(24'h017e00, 8'h01);
        check_write(24'hff7e00, 8'h01);
        if (sd_enabled !== 0) $fatal(1, "Extended write enabled SD");
        check_write(24'h00ffff, 8'hab);
        if (expanded_slot !== 8'hab) $fatal(1, "Legacy slot write broken");
        check_write(24'h007e00, 8'h01);
        if (sd_enabled !== 1) $fatal(1, "Legacy SD enable broken");

        // I/O remains independent of memory banks.
        for (bank = 0; bank < 256; bank = bank + 1) begin
            cpu_addr = {bank[7:0], 16'h0099};
            cpu_mreq_n = 1; cpu_iorq_n = 0; cpu_wr_n = 0; cpu_rd_n = 1;
            #1;
            if (!vdp_write || !bus_mreq_n || !extended_mreq_n || extended_access)
                $fatal(1, "VDP I/O affected by memory bank");
        end
        $display("PASS: %0d routing cases, boundary/slot/SD isolation and 256 I/O banks", checks);
        $finish;
    end
endmodule
