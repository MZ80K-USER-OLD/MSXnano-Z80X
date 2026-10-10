--
-- Phase6 self-checking testbench: MMU_ATTR.W write-protection attribute
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 8 "Phase 6")
--
-- NOTE: MMU24 is an OPTIONAL add-on, not instantiated by the default
-- top.v build (see mmu24.vhd's header comment and
-- MSX_T80_24bit化_CPU仕様書_V8 section 14.1). The default build instead
-- uses a straight-through logical->physical bank mapping with no
-- per-bank write protection. This testbench still exercises the
-- standalone mmu24.vhd module directly and remains valid/passing
-- regardless of whether top.v currently instantiates it.
--
-- Exercises MMU24 (fpga/G80A/mmu24.vhd) in isolation via simple I/O-port
-- level read/write stimulus (no CPU core involved), covering:
--   - reset state: every logical bank defaults to Write_Allow='1' (W=1,
--     reset value 20h), so existing 24bit-aware code sees no behavioural
--     change until software explicitly locks a bank down
--   - F2h write+readback of an arbitrary MMU_ATTR entry
--   - W=0 (bit5 cleared) deasserts Write_Allow for that logical bank only;
--     other banks are unaffected
--   - async lookup: Write_Allow follows Logical_Bank combinationally, with
--     no extra clock needed once the table is programmed (same contract
--     as Physical_Bank in Phase4/tb_phase4_mmu24.vhd)
--   - F2h access does not disturb MMU_INDEX (confirmed via a subsequent
--     F1h access still targeting the index set by the last F0h write)
--   - F1h/F0h behaviour (Phase4) is unaffected by the Phase6 addition
--   - logical bank 00h is exempt from MMU_ATTR.W (mirrors the Phase4
--     MMU_DATA[00h] exemption): a write targeting MMU_ATTR[00h] is
--     ignored, and Write_Allow for logical bank 00h always reads '1'
--     regardless of table contents
--
-- Run with GHDL:
--   ghdl -a --std=08 ../mmu24.vhd tb_phase6_mmu_attr.vhd
--   ghdl -e --std=08 tb_phase6_mmu_attr
--   ghdl -r --std=08 tb_phase6_mmu_attr
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_phase6_mmu_attr is
end entity tb_phase6_mmu_attr;

architecture sim of tb_phase6_mmu_attr is

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
    signal Write_Allow   : std_logic;

    -- One Z80-style OUT (port),D cycle: hold the port/data/strobes active
    -- across a rising CLK edge, then release, mirroring top.v's level-
    -- sensitive sampling of bus_iorq_n/bus_wr_n.
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
            Physical_Bank => Physical_Bank,
            Write_Allow => Write_Allow);

    CLK <= not CLK after 10 ns;

    process
    begin
        RESET_n <= '0';
        wait for 45 ns;
        RESET_n <= '1';
        wait for 20 ns;

        -- Reset state: every logical bank defaults to Write_Allow='1'
        -- (ATTR reset value 20h = bit5 set), including bank 00h and an
        -- arbitrary untouched bank.
        Logical_Bank <= x"00";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: post-reset logical bank 00h must have Write_Allow=1" severity failure;

        Logical_Bank <= x"07";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: post-reset logical bank 07h must have Write_Allow=1" severity failure;

        -- Program MMU_ATTR[07h] = 00h (W=0) via F0h (index) then F2h (attr).
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"07");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"00");

        -- Async lookup: changing Logical_Bank alone must reflect the new
        -- attribute immediately, no further I/O or clock edge required.
        Logical_Bank <= x"07";
        wait for 1 ns;
        assert Write_Allow = '0'
            report "Phase6: logical bank 07h must have Write_Allow=0 after F2h write of 00h" severity failure;

        -- A different logical bank must still be unaffected (W=1).
        Logical_Bank <= x"08";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: untouched logical bank 08h must still have Write_Allow=1" severity failure;

        -- Read back F2h (attr at the index set above) via the I/O bus.
        Port_Addr <= x"F2";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_OutEn = '1' report "Phase6: F2h read must assert D_OutEn" severity failure;
        assert D_Out = x"00" report "Phase6: F2h readback at index 07h must return 00h, got " & to_hstring(D_Out) severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        -- Re-enable write for bank 07h (W=1, bit5 set, other bits left 0).
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"07");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"20");

        Logical_Bank <= x"07";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: logical bank 07h must have Write_Allow=1 after re-enabling W" severity failure;

        -- Only bit5 is meaningful: a value with bit5=1 plus other (reserved)
        -- bits set must still read Write_Allow=1 (e.g. FFh).
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"09");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"FF");
        Logical_Bank <= x"09";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: logical bank 09h with ATTR=FFh (bit5=1) must have Write_Allow=1" severity failure;

        -- And a value with bit5=0 plus other bits set must read Write_Allow=0
        -- (e.g. DFh = 1101_1111b, bit5 cleared).
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"0A");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"DF");
        Logical_Bank <= x"0A";
        wait for 1 ns;
        assert Write_Allow = '0'
            report "Phase6: logical bank 0Ah with ATTR=DFh (bit5=0) must have Write_Allow=0" severity failure;

        -- F2h access must not disturb MMU_INDEX: after the F0h/F2h pair
        -- above (last F0h write = 0Ah), reading F1h (MMU_DATA) must still
        -- target index 0Ah, not some index implicitly advanced by F2h.
        -- First program MMU_DATA[0Ah] via F0h/F1h to a known pattern, then
        -- re-point the index with a single F0h write and interleave an F2h
        -- access, confirming F1h still reads back the same entry.
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"0A");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F1", x"55");  -- MMU_DATA[0Ah] = 55h

        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"0A");  -- re-point index at 0Ah
        -- F2h write (attribute only); must leave MMU_INDEX at 0Ah.
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"20");

        Port_Addr <= x"F1";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_Out = x"55"
            report "Phase6: F2h access must not change MMU_INDEX - F1h at index 0Ah must still read 55h, got " & to_hstring(D_Out)
            severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        -- Also confirm F0h readback after the F2h access still shows 0Ah
        -- (i.e. F2h truly left MMU_INDEX untouched, not just MMU_DATA's
        -- addressing).
        Port_Addr <= x"F0";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_Out = x"0A"
            report "Phase6: MMU_INDEX must still read 0Ah after the F2h access, got " & to_hstring(D_Out)
            severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        -- Phase4 behaviour (Physical_Bank, bank00h alias) must be
        -- unaffected by the Phase6 addition.
        Logical_Bank <= x"00";
        wait for 1 ns;
        assert Physical_Bank = x"00"
            report "Phase6 regression: logical bank 00h must still alias physical 00h" severity failure;

        -- Logical bank 00h is exempt from MMU_ATTR.W, mirroring the
        -- MMU_DATA[00h] exemption: Write_Allow for bank 00h must always
        -- read '1' even if software attempts to clear W via F0h=00h/F2h=00h.
        assert Write_Allow = '1'
            report "Phase6: logical bank 00h must have Write_Allow=1 before attempting MMU_ATTR[00h] write" severity failure;

        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F0", x"00");
        io_out(CLK, Port_Addr, D_In, IORQ_n, WR_n, x"F2", x"00");  -- attempt to clear W for bank 00h

        Logical_Bank <= x"00";
        wait for 1 ns;
        assert Write_Allow = '1'
            report "Phase6: write to MMU_ATTR[00h] must be ignored, logical bank 00h Write_Allow must remain 1" severity failure;

        -- Confirm the blocked write didn't silently land anywhere else:
        -- F2h readback at index 00h must still show the reset value (20h).
        Port_Addr <= x"F2";
        IORQ_n <= '0';
        RD_n <= '0';
        wait for 1 ns;
        assert D_Out = x"20"
            report "Phase6: F2h readback at index 00h must still be 20h after blocked write, got " & to_hstring(D_Out)
            severity failure;
        IORQ_n <= '1';
        RD_n <= '1';
        wait for 10 ns;

        report "Phase6 MMU_ATTR.W testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
