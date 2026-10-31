--
-- Phase11 self-checking testbench: JR.L e16 / JR.L cc,e16
-- (doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 13 "Phase 11";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md section 5 and the roadmap's
--  "JR.LはM2ではPC24全体にsigned 16bit displacementを加算しbank境界を
--  跨ぐ" note)
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches;
-- only bank_pc/mode24 - not the physical byte actually fetched -
-- distinguish "jumped across a bank boundary" from "jumped to the same
-- address within the same bank").
--
-- Program layout (addresses chosen so no two logically-distinct test
-- steps ever reuse the same physical 16bit address, since the flat
-- model has no real per-bank storage):
--   0x0000: SET_M2; JP.L 00:FFF0h (jumps to the near-top-of-bank JR.L
--     below; 0x0007 is intentionally skipped here and revisited later
--     via an explicit jump for Test5, never by fall-through).
--   0xFFF0: JR.L +001Ah (unconditional). PC after fetching this 4byte
--     instruction is 0xFFF4; +0x001A overflows 16bit, carrying bank
--     00h->01h (Addr24_AddDisp16(00h,0xFFF4,001Ah) = 01:000Eh).
--     Test1: lands on A=0x000E with bank_pc=01h.
--   0x000E: XOR A (Z=1, needed for the cc tests below).
--   0x000F: JR.L Z,+0010h (condition TRUE). PC after=0x0013; +0x10=
--     0x0023, no bank crossing (stays bank01h).
--     Test2: lands on A=0x0023 with bank_pc STILL 01h.
--   0x0023: JR.L NZ,+0010h (condition FALSE, Z=1 so NZ is false). Must
--     NOT jump; both displacement bytes are still consumed (matching
--     real Z80 JR cc,e's variable-length timing), falling through to
--     0x0027.
--     Test3: lands on A=0x0027 with bank_pc STILL 01h (unaffected).
--   0x0027: SET_M0 (leave M2).
--   0x0029: JR.L +0010h, now in M0. PC after=0x002D; +0x10=0x003D -
--     M0 keeps a plain 16bit wrap (CPU仕様書V8/roadmap Phase11 implies
--     M0/M1 do NOT bank-cross, mirroring JP.L's own M0/M1 treatment).
--     Test4: lands on A=0x003D with mode24=M0(00) and bank_pc STILL
--     01h (M0's JumpEL branch never touches bank_pc_r at all).
--   0x003D: SET_M2 (M0->M2, resets bank_pc to 00h per Phase10's rule).
--   0x003F: JP.L 00:0007h (sets up Test5 at a low address so a
--     backward/negative displacement can actually underflow below
--     0x0000).
--   0x0007: JR.L -0010h. PC after fetching this 4byte instruction is
--     0x000B; -0x10 underflows below 0, borrowing bank 00h->FFh
--     (Addr24_AddDisp16(00h,0x000B,FFF0h) = FF:FFFBh) - this ALSO
--     exercises the 8bit bank byte's own wraparound (00h-1=FFh).
--     Test5: lands on A=0xFFFB with bank_pc=FFh.
--   0xFFFB: HALT - end of program.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase11_jrl.vhd
--   ghdl -e --std=08 tb_phase11_jrl
--   ghdl -r --std=08 tb_phase11_jrl
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase11_jrl is
end entity tb_phase11_jrl;

architecture sim of tb_phase11_jrl is

    signal RESET_n  : std_logic := '0';
    signal CLK_n    : std_logic := '0';
    signal CEN      : std_logic := '1';
    signal WAIT_n   : std_logic := '1';
    signal INT_n    : std_logic := '1';
    signal NMI_n    : std_logic := '1';
    signal BUSRQ_n  : std_logic := '1';
    signal M1_n     : std_logic;
    signal IORQ     : std_logic;
    signal NoRead   : std_logic;
    signal Write    : std_logic;
    signal RFSH_n   : std_logic;
    signal HALT_n   : std_logic;
    signal BUSAK_n  : std_logic;
    signal A        : std_logic_vector(15 downto 0);
    signal update_addr : std_logic;
    signal DInst    : std_logic_vector(7 downto 0);
    signal DI       : std_logic_vector(7 downto 0);
    signal DI_live  : std_logic_vector(7 downto 0);
    signal DO       : std_logic_vector(7 downto 0);
    signal mode24   : std_logic_vector(1 downto 0);
    signal bank_bc  : std_logic_vector(7 downto 0);
    signal bank_de  : std_logic_vector(7 downto 0);
    signal bank_hl  : std_logic_vector(7 downto 0);
    signal bank_ix  : std_logic_vector(7 downto 0);
    signal bank_iy  : std_logic_vector(7 downto 0);
    signal bank_pc  : std_logic_vector(7 downto 0);
    signal bank_msp : std_logic_vector(7 downto 0);
    signal bank_int : std_logic_vector(7 downto 0);
    signal bank_rst : std_logic_vector(7 downto 0);
    signal A_Bank   : std_logic_vector(7 downto 0);
    signal MC       : std_logic_vector(2 downto 0);
    signal TS       : std_logic_vector(2 downto 0);
    signal IntCycle_n : std_logic;
    signal IntE     : std_logic;
    signal Stop     : std_logic;

    type mem_array is array(0 to 65535) of std_logic_vector(7 downto 0);

    signal mem : mem_array := (
        16#0000# => x"ED", 16#0001# => x"92",
        16#0002# => x"ED", 16#0003# => x"C3", 16#0004# => x"F0", 16#0005# => x"FF", 16#0006# => x"00",
        16#0007# => x"ED", 16#0008# => x"18", 16#0009# => x"F0", 16#000A# => x"FF",
        16#000E# => x"AF",
        16#000F# => x"ED", 16#0010# => x"28", 16#0011# => x"10", 16#0012# => x"00",
        16#0023# => x"ED", 16#0024# => x"20", 16#0025# => x"10", 16#0026# => x"00",
        16#0027# => x"ED", 16#0028# => x"90",
        16#0029# => x"ED", 16#002A# => x"18", 16#002B# => x"10", 16#002C# => x"00",
        16#003D# => x"ED", 16#003E# => x"92",
        16#003F# => x"ED", 16#0040# => x"C3", 16#0041# => x"07", 16#0042# => x"00", 16#0043# => x"00",
        16#FFF0# => x"ED", 16#FFF1# => x"18", 16#FFF2# => x"1A", 16#FFF3# => x"00",
        16#FFFB# => x"76",
        others => x"00");

begin

    u0 : T80
        generic map(
            Mode => 0,
            IOWait => 0)
        port map(
            RESET_n => RESET_n,
            CLK_n => CLK_n,
            CEN => CEN,
            WAIT_n => WAIT_n,
            INT_n => INT_n,
            NMI_n => NMI_n,
            BUSRQ_n => BUSRQ_n,
            M1_n => M1_n,
            IORQ => IORQ,
            NoRead => NoRead,
            Write => Write,
            RFSH_n => RFSH_n,
            HALT_n => HALT_n,
            BUSAK_n => BUSAK_n,
            A => A,
            update_addr => update_addr,
            DInst => DInst,
            DI => DI,
            DO => DO,
            mode24 => mode24,
            bank_bc => bank_bc,
            bank_de => bank_de,
            bank_hl => bank_hl,
            bank_ix => bank_ix,
            bank_iy => bank_iy,
            bank_pc => bank_pc,
            bank_msp => bank_msp,
            bank_int => bank_int,
            bank_rst => bank_rst,
            A_Bank => A_Bank,
            MC => MC,
            TS => TS,
            IntCycle_n => IntCycle_n,
            IntE => IntE,
            Stop => Stop);

    -- Flat combinational memory model (M0-style, no MMU): see
    -- tb_phase3_m1_data.vhd for the detailed rationale behind the
    -- DI_live/DInst/DI split.
    DI_live <= mem(to_integer(unsigned(A)));
    DInst <= DI_live;

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
        end if;
    end process;

    CLK_n <= not CLK_n after 10 ns;

    process
    begin
        RESET_n <= '0';
        wait for 45 ns;
        RESET_n <= '1';
        wait;
    end process;

    process
    begin
        -- A small settle wait after each "wait until A=...,M1_n=..."
        -- condition lets mode24/bank_pc (continuous assignments derived
        -- from internal registers, one delta cycle behind A/M1_n's own
        -- process) finish propagating before being sampled - same
        -- testbench-side delta-cycle race avoidance as
        -- tb_phase10_m2_basic.vhd / tb_phase11_jpl.vhd / tb_phase11_call_ret_l.vhd.

        -- ---- Test1: JR.L e16 (ED 18) unconditional forward bank
        -- crossing must land on A=0x000E with bank_pc=01h. ----
        wait until A = x"000E" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"01"
            report "Phase11: Test1 JR.L e16 forward crossing must land with bank_pc=01h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase11: Test1 JR.L e16 must not disturb mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test2: JR.L Z,e16 (ED 28) with condition TRUE (Z=1 after
        -- XOR A) must be taken: lands on A=0x0023 with bank_pc STILL
        -- 01h (no crossing this time). ----
        wait until A = x"0023" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"01"
            report "Phase11: Test2 JR.L Z,e16 (condition true) must be taken with bank_pc=01h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test3: JR.L NZ,e16 (ED 20) with condition FALSE (Z=1, so
        -- NZ is false) must NOT be taken: falls through to A=0x0027,
        -- bank_pc STAYS 01h (unaffected by the non-taken jump). ----
        wait until A = x"0027" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"01"
            report "Phase11: Test3 JR.L NZ,e16 (condition false) must not touch bank_pc, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test4: JR.L e16 executed in M0 (after SET_M0) must keep
        -- a plain 16bit wrap: lands on A=0x003D with mode24 STILL M0
        -- and bank_pc untouched (still 01h - M0's JumpEL branch never
        -- writes bank_pc_r at all). ----
        wait until A = x"003D" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "00"
            report "Phase11: Test4 expected mode24=M0(00) before the following SET_M2, got " & to_hstring("00" & mode24)
            severity failure;
        assert bank_pc = x"01"
            report "Phase11: Test4 JR.L e16 in M0 must not touch bank_pc, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test5: JR.L -0010h (back in M2 after the SET_M2 at
        -- 0x003D, which resets bank_pc to 00h) with a negative
        -- displacement that underflows below 0x0000 must borrow into
        -- bank FFh (0x00-1=0xFFh, exercising the bank byte's own 8bit
        -- wraparound too): lands on A=0xFFFB with bank_pc=FFh. ----
        wait until A = x"FFFB" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"FF"
            report "Phase11: Test5 JR.L e16 backward crossing must borrow to bank_pc=FFh, got " & to_hstring(bank_pc)
            severity failure;

        report "Phase11 JR.L testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
