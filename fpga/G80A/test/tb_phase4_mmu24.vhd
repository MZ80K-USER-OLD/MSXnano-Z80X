--
-- Phase4 self-checking testbench: MMU_DATA (F0h/F1h) logical->physical
-- bank translation
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 6 "Phase 4")
--
-- Exercises MMU24 (fpga/G80A/mmu24.vhd) in isolation via simple I/O-port
-- level read/write stimulus (no CPU core involved), covering:
--   - reset state: every logical bank defaults to physical bank 00h
--   - F0h/F1h write+readback of an arbitrary table entry
--   - async lookup: Physical_Bank follows Logical_Bank combinationally,
--     with no extra clock needed once the table is programmed
--   - MMU_DATA[00h] is fixed at 00h and immune to writes
--   - unrelated I/O ports are ignored (D_OutEn stays low)
--
-- Run with GHDL:
--   ghdl -a --std=08 ../mmu24.vhd tb_phase4_mmu24.vhd
--   ghdl -e --std=08 tb_phase4_mmu24
--   ghdl -r --std=08 tb_phase4_mmu24
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_phase4_mmu24 is
end entity tb_phase4_mmu24;

architecture sim of tb_phase4_mmu24 is

    signal RESET_n       : std_logic := '0';
    signal CLK           : std_logic := '0';
    signal IORQ_n        : std_logic := '1';
    signal M1_n          : std_logic := '1';
    signal RD_n          : std_logic := '1';
    signal WR_n          : std_logic := '1';
    signal Port_Addr     : std_logic_vector(7 downto 0) := x"00";
    signal D_In          : std_logic_vector(7 downto 0) := x"00";
    signal D_Out         : std_logic_vector(7 downto 0);
    signal D_OutEn       : std_logic;
    signal Logical_Bank  : std_logic_vector(7 downto 0) := x"00";
    signal Physical_Bank : std_logic_vector(7 downto 0);

    -- One Z80-style OUT (port),D cycle: hold the port/data/strobes active
    -- across a rising CLK edge, then release, mirroring how top.v samples
    -- bus_iorq_n/bus_wr_n level-sensitively on its sampling clock.
    procedure io_out(signal clk_s : in std_logic;
                      signal port_s : out std_logic_vector(7 downto 0);
                      signal data_s : out std_logic_vector(7 downto 0);
                      signal iorq_s : out std_logic;
                      signal wr_s   : out std_logic;
                      constant port_v : in std_logic_vector(7 downto 0);
                      constant data_v : in std_logic_vector(7 downto 0)) is
    begin
        port_s <= port_v;
        data_s <= data_v;
        iorq_s <= '0';
        wr_s <= '0';
        wait until rising_edge(clk_s);
        wait for 1 ns;
        iorq_s <= '1';
        wr_s <= '1';
        wait for 10 ns;
    end procedure;

begin

    dut : entity work.MMU24
        port map(
            RESET_n => RESET_n,
            CLK => CLK,
            IORQ_n => IORQ_n,
            M1_n => M1_n,
            RD_n => RD_n,
            WR_n => WR_n,
            Port_Addr => Port_Addr,
            D_In => D_In,
            D_Out => D_Out,
            D_OutEn => D_OutEn,
            Logical_Bank => Logical_Bank,
            Physical_Bank => Physical_Bank);

    CLK <= not CLK after 10 ns;

    process
    begin
        RESET_n <= '0';
        wait for 45 ns;
        RESET_n <= '1';
        wait for 20 ns;

        -- Reset state: any logical bank must alias physical bank 00h.
        Logical_Bank <= x"05";
        wait for 1 ns;
        assert Physical_Bank = x"00"
            report "Phase4: post-reset logical bank 05h must alias physical 00h, got " & to_hstring(Physical_Bank)
            severity failure;

        Logical_Bank <= x"00";
        wait for 1 ns;
        assert Physical_Bank = x"00"
            report "Phase4: logical bank 00h must always alias physical 00h" severity failure;

        -- Program MMU_DATA[05h] = AAh via F0h (index) then F1h (data).
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"05");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F1", x"AA");

        -- Async lookup: changing Logical_Bank alone must reflect the new
        -- mapping immediately, no further I/O or clock edge required.
        Logical_Bank <= x"05";
        wait for 1 ns;
        assert Physical_Bank = x"AA"
            report "Phase4: logical bank 05h must map to physical AAh after F0/F1 write, got " & to_hstring(Physical_Bank)
            severity failure;

        -- A different logical bank must still be unaffected (alias 00h).
        Logical_Bank <= x"06";
        wait for 1 ns;
        assert Physical_Bank = x"00"
            report "Phase4: untouched logical bank 06h must still alias physical 00h" severity failure;

        -- Read back F0h (index) and F1h (data at that index) via the I/O bus.
        Port_Addr <= x"F0";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_OutEn = '1' report "Phase4: F0h read must assert D_OutEn" severity failure;
        assert D_Out = x"05" report "Phase4: F0h readback must return the last written index (05h), got " & to_hstring(D_Out) severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        Port_Addr <= x"F1";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_OutEn = '1' report "Phase4: F1h read must assert D_OutEn" severity failure;
        assert D_Out = x"AA" report "Phase4: F1h readback at index 05h must return AAh, got " & to_hstring(D_Out) severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        -- Attempt to overwrite MMU_DATA[00h]: must be ignored.
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"00");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F1", x"77");

        Logical_Bank <= x"00";
        wait for 1 ns;
        assert Physical_Bank = x"00"
            report "Phase4: write to MMU_DATA[00h] must be ignored, logical bank 00h still mapped to " & to_hstring(Physical_Bank)
            severity failure;

        Port_Addr <= x"F1";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_Out = x"00"
            report "Phase4: F1h readback at index 00h must still be 00h after blocked write, got " & to_hstring(D_Out)
            severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        -- Unrelated I/O ports must not be claimed by this device.
        Port_Addr <= x"A8";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_OutEn = '0' report "Phase4: unrelated port A8h must not assert D_OutEn" severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        report "Phase4 MMU_DATA testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
