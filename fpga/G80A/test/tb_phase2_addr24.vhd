--
-- Phase2 self-checking testbench: 24bit address generator
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 4 "Phase 2")
--
-- Exercises Addr24_Inc/Addr24_Dec/Addr24_AddDisp8/Addr24_AddDisp16 from
-- T80_Pack (fpga/G80A/t80_pack.vhd) in isolation, covering:
--   - full 24bit wraparound (FFFFFF+1=000000, 000000-1=FFFFFF)
--   - 64KB bank boundary carry/borrow
--   - IX/IY+d signed 8bit displacement crossing a bank boundary
--   - 16bit displacement (JR.L building block) crossing a bank boundary
--   - MSP24 increment/decrement crossing a bank boundary
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd tb_phase2_addr24.vhd
--   ghdl -e --std=08 tb_phase2_addr24
--   ghdl -r --std=08 tb_phase2_addr24
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase2_addr24 is
end entity tb_phase2_addr24;

architecture sim of tb_phase2_addr24 is
begin

    process
        variable r : std_logic_vector(23 downto 0);
    begin
        -- Full 24bit modulo wraparound
        r := Addr24_Inc(x"FF", x"FFFF");
        assert r = x"000000" report "Addr24_Inc FFFFFF+1 failed: got " & to_hstring(r) severity failure;

        r := Addr24_Dec(x"00", x"0000");
        assert r = x"FFFFFF" report "Addr24_Dec 000000-1 failed: got " & to_hstring(r) severity failure;

        -- 64KB bank boundary carry/borrow
        r := Addr24_Inc(x"00", x"FFFF");
        assert r = x"010000" report "Addr24_Inc bank carry failed: got " & to_hstring(r) severity failure;

        r := Addr24_Dec(x"01", x"0000");
        assert r = x"00FFFF" report "Addr24_Dec bank borrow failed: got " & to_hstring(r) severity failure;

        -- Mid-range: no bank change
        r := Addr24_Inc(x"12", x"3456");
        assert r = x"123457" report "Addr24_Inc no-carry failed: got " & to_hstring(r) severity failure;

        r := Addr24_Dec(x"12", x"3456");
        assert r = x"123455" report "Addr24_Dec no-borrow failed: got " & to_hstring(r) severity failure;

        -- IX/IY+d signed 8bit displacement crossing a bank boundary (M1/M2)
        r := Addr24_AddDisp8(x"00", x"FFFE", x"05"); -- +5
        assert r = x"010003" report "Addr24_AddDisp8 +d carry failed: got " & to_hstring(r) severity failure;

        r := Addr24_AddDisp8(x"01", x"0003", x"F8"); -- -8
        assert r = x"00FFFB" report "Addr24_AddDisp8 -d borrow failed: got " & to_hstring(r) severity failure;

        r := Addr24_AddDisp8(x"7F", x"8000", x"00"); -- d=0, unchanged
        assert r = x"7F8000" report "Addr24_AddDisp8 d=0 failed: got " & to_hstring(r) severity failure;

        -- 16bit displacement (JR.L building block) crossing a bank boundary
        r := Addr24_AddDisp16(x"00", x"FFF0", x"0020"); -- +32
        assert r = x"010010" report "Addr24_AddDisp16 +e16 carry failed: got " & to_hstring(r) severity failure;

        r := Addr24_AddDisp16(x"01", x"0010", x"FFE0"); -- -32
        assert r = x"00FFF0" report "Addr24_AddDisp16 -e16 borrow failed: got " & to_hstring(r) severity failure;

        -- MSP24 increment/decrement crossing a bank boundary (Phase9 prep)
        r := Addr24_Inc(x"12", x"FFFF");
        assert r = x"130000" report "Addr24_Inc MSP24 carry failed: got " & to_hstring(r) severity failure;

        r := Addr24_Dec(x"13", x"0000");
        assert r = x"12FFFF" report "Addr24_Dec MSP24 borrow failed: got " & to_hstring(r) severity failure;

        report "Phase2 Addr24 testbench: all assertions passed" severity note;
        wait;
    end process;

end architecture sim;
