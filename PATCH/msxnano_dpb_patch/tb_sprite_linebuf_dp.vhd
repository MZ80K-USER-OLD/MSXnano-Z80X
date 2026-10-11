-- Testbench for sprite_linebuf_dp.vhd (standalone functional simulation).
-- Validates:
--   1) 1-cycle registered read latency on both ports (matches original
--      single-port RAM entity used for U_EVEN_LINE_BUF/U_ODD_LINE_BUF).
--   2) Port A and Port B operate on independent banks (address bit 8
--      selects bank) without cross-talk, emulating the even/odd line
--      buffer swap driven by DOTCOUNTERYP(0) in vdp_sprite.vhd.
--   3) Simultaneous writes to different banks via both ports in the same
--      clock do not corrupt each other (the actual VDP_SPRITE usage
--      pattern: port A clears/reads the display bank while port B reads
--      modifies/writes the draw bank).
--   4) Values written through one port are correctly observed through the
--      other port once the two banks swap roles (display/draw swap each
--      scanline), matching the real usage in vdp_sprite.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sprite_linebuf_dp is
end entity;

architecture sim of tb_sprite_linebuf_dp is
    component sprite_linebuf_dp
        port (
            clk    : in  std_logic;
            a_addr : in  std_logic_vector(8 downto 0);
            a_we   : in  std_logic;
            a_din  : in  std_logic_vector(7 downto 0);
            a_dout : out std_logic_vector(7 downto 0);
            b_addr : in  std_logic_vector(8 downto 0);
            b_we   : in  std_logic;
            b_din  : in  std_logic_vector(7 downto 0);
            b_dout : out std_logic_vector(7 downto 0)
        );
    end component;

    signal clk    : std_logic := '0';
    signal a_addr : std_logic_vector(8 downto 0) := (others => '0');
    signal a_we   : std_logic := '0';
    signal a_din  : std_logic_vector(7 downto 0) := (others => '0');
    signal a_dout : std_logic_vector(7 downto 0);
    signal b_addr : std_logic_vector(8 downto 0) := (others => '0');
    signal b_we   : std_logic := '0';
    signal b_din  : std_logic_vector(7 downto 0) := (others => '0');
    signal b_dout : std_logic_vector(7 downto 0);

    signal errors : integer := 0;

    procedure check(cond : boolean; msg : string; signal err_cnt : inout integer) is
    begin
        if not cond then
            report "FAIL: " & msg severity error;
            err_cnt <= err_cnt + 1;
        else
            report "PASS: " & msg severity note;
        end if;
    end procedure;
begin
    -- 100ns period clock, matches a generic single clock-domain BSRAM model.
    clk <= not clk after 5 ns;

    stim: process
    begin
        wait until rising_edge(clk);

        ---------------------------------------------------------------
        -- Test 1: write via port A to bank0 addr 0x10, read back.
        ---------------------------------------------------------------
        a_addr <= '0' & x"10";
        a_din  <= x"A5";
        a_we   <= '1';
        wait until rising_edge(clk);
        a_we   <= '0';
        a_din  <= (others => '0');
        a_addr <= '0' & x"10";   -- present read address
        wait until rising_edge(clk);   -- address registered this edge
        wait for 1 ns;                  -- allow registered dout to settle
        check(a_dout = x"A5", "port A read-back of bank0 addr0x10 = 0xA5", errors);

        ---------------------------------------------------------------
        -- Test 2: write via port B to bank1 addr 0x10 (same sub-address,
        -- different bank) with a different value; bank0 (port A) must be
        -- unaffected.
        ---------------------------------------------------------------
        b_addr <= '1' & x"10";
        b_din  <= x"5A";
        b_we   <= '1';
        wait until rising_edge(clk);
        b_we   <= '0';
        b_din  <= (others => '0');
        b_addr <= '1' & x"10";
        a_addr <= '0' & x"10";
        wait until rising_edge(clk);
        wait for 1 ns;
        check(b_dout = x"5A", "port B read-back of bank1 addr0x10 = 0x5A", errors);
        check(a_dout = x"A5", "bank0 addr0x10 unaffected by bank1 write (no cross-talk)", errors);

        ---------------------------------------------------------------
        -- Test 3: simultaneous writes to different banks on the same
        -- clock edge (real usage: display bank cleared via port A while
        -- draw bank is written via port B at the same time).
        ---------------------------------------------------------------
        a_addr <= '0' & x"20";
        a_din  <= x"11";
        a_we   <= '1';
        b_addr <= '1' & x"20";
        b_din  <= x"22";
        b_we   <= '1';
        wait until rising_edge(clk);
        a_we <= '0'; b_we <= '0';
        a_addr <= '0' & x"20";
        b_addr <= '1' & x"20";
        wait until rising_edge(clk);
        wait for 1 ns;
        check(a_dout = x"11", "simultaneous write: bank0 addr0x20 = 0x11", errors);
        check(b_dout = x"22", "simultaneous write: bank1 addr0x20 = 0x22", errors);

        ---------------------------------------------------------------
        -- Test 4: emulate the scanline bank swap performed in
        -- vdp_sprite.vhd: port A becomes bank1 and port B becomes bank0,
        -- using the values written in Test 3. Confirms the role-swap
        -- (DOTCOUNTERYP(0) toggling) sees consistent shared storage.
        ---------------------------------------------------------------
        a_addr <= '1' & x"20";
        b_addr <= '0' & x"20";
        wait until rising_edge(clk);
        wait for 1 ns;
        check(a_dout = x"22", "after bank swap: port A sees bank1 addr0x20 = 0x22", errors);
        check(b_dout = x"11", "after bank swap: port B sees bank0 addr0x20 = 0x11", errors);

        ---------------------------------------------------------------
        -- Test 5: read-modify-write on the same port (draw port pattern):
        -- write then immediately re-read same address through same port.
        ---------------------------------------------------------------
        b_addr <= '0' & x"30";
        b_din  <= x"7E";
        b_we   <= '1';
        wait until rising_edge(clk);
        b_we <= '0';
        b_addr <= '0' & x"30";
        wait until rising_edge(clk);
        wait for 1 ns;
        check(b_dout = x"7E", "read-after-write same port/addr = 0x7E", errors);

        wait for 20 ns;

        if errors = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(errors) & " TEST(S) FAILED" severity error;
        end if;

        std.env.stop;
    end process;

    dut: sprite_linebuf_dp
    port map (
        clk    => clk,
        a_addr => a_addr,
        a_we   => a_we,
        a_din  => a_din,
        a_dout => a_dout,
        b_addr => b_addr,
        b_we   => b_we,
        b_din  => b_din,
        b_dout => b_dout
    );
end architecture;
