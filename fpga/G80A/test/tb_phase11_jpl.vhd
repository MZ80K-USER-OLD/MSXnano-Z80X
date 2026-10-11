--
-- Phase11 self-checking testbench: JP.L addr24 / JP.L cc,addr24
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 13 "Phase 11";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md, section 5. Note: JP.L
--  itself is listed in AVAILABLE_INSTRUCTIONS.md section 9 "24bit制御"
--  alongside JR.L/CALL.L/RET.L, but unlike those it needs no stack frame,
--  so it was implemented first as the simplest piece of Phase11's scope.)
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches;
-- the physical byte at a given 16bit address is identical regardless of
-- the declared bank, so only the bank_pc/mode24/A_Bank signals -- not the
-- opcode bytes actually fetched -- distinguish "jumped to a different
-- bank" from "jumped to the same address in bank00h").
--
-- Program layout:
--   0x0000: ED92 (SET_M2) - enter M2 so JP.L has full 24bit effect.
--   0x0002: ED C3 10 00 01 - JP.L 01:0010h (unconditional far jump).
--     Test1: next fetch must be at A=0x0010 with bank_pc=01h.
--   0x0010: AF (XOR A) - sets Z=1 (and A=0), needed for the cc tests.
--   0x0011: ED CA 20 00 02 - JP.L Z,02:0020h (condition TRUE, Z=1).
--     Test2: condition-true jump must be taken (A=0x0020, bank_pc=02h).
--   0x0020: ED C2 30 00 03 - JP.L NZ,03:0030h (condition FALSE, Z=1 so
--     NZ is false). Must NOT jump; all 5 bytes are still consumed
--     (matching real Z80 JP cc,nn timing), falling through to 0x0025.
--   0x0025: 3E AA (LD A,AAh) - marker instruction.
--     Test3: fall-through fetch at A=0x0025 with bank_pc UNCHANGED
--     (still 02h from Test2 - a non-taken JP.L cc must not touch
--     bank_pc_r at all).
--   0x0027: ED90 (SET_M0) - leave M2.
--   0x0029: ED C3 40 00 05 - JP.L 05:0040h, now in M0.
--     Test4: M0/M1 must still take the jump (A=0x0040) but DISCARD the
--     bank byte (bank_pc=00h, not 05h) - see the design-rationale
--     comment on the JumpL branch in t80.vhd for why this is safer than
--     propagating a bank_pc_r value that M0/M1 fetch logic never
--     consults anyway ("zombie bank_pc_r").
--   0x0040: 76 (HALT) - end of program.
--
-- NOT covered by this testbench (deferred, same Phase11 scope split as
-- documented in AVAILABLE_INSTRUCTIONS.md): CALL.L/RET.L (MSP stack
-- frame) and JR.L (PC24-relative displacement) - both still TODO within
-- Phase11.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase11_jpl.vhd
--   ghdl -e --std=08 tb_phase11_jpl
--   ghdl -r --std=08 tb_phase11_jpl
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase11_jpl is
end entity tb_phase11_jpl;

architecture sim of tb_phase11_jpl is

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
    signal bank_nvr : std_logic_vector(7 downto 0);
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
        16#0002# => x"ED", 16#0003# => x"C3", 16#0004# => x"10", 16#0005# => x"00", 16#0006# => x"01",
        16#0010# => x"AF",
        16#0011# => x"ED", 16#0012# => x"CA", 16#0013# => x"20", 16#0014# => x"00", 16#0015# => x"02",
        16#0020# => x"ED", 16#0021# => x"C2", 16#0022# => x"30", 16#0023# => x"00", 16#0024# => x"03",
        16#0025# => x"3E", 16#0026# => x"AA",
        16#0027# => x"ED", 16#0028# => x"90",
        16#0029# => x"ED", 16#002A# => x"C3", 16#002B# => x"40", 16#002C# => x"00", 16#002D# => x"05",
        16#0040# => x"76",
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
            bank_nvr => bank_nvr,
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
        -- ---- Test1: JP.L addr24 (ED C3) unconditional far jump in M2
        -- must land on A=0x0010 with bank_pc=01h. A small settle wait
        -- after each "wait until A=...,M1_n=..." condition lets mode24/
        -- bank_pc (continuous assignments derived from internal
        -- registers, one delta cycle behind A/M1_n's own process)
        -- finish propagating before being sampled - same testbench-side
        -- delta-cycle race avoidance as tb_phase10_m2_basic.vhd. ----
        wait until A = x"0010" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"01"
            report "Phase11: Test1 JP.L addr24 must land with bank_pc=01h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase11: Test1 JP.L addr24 must not disturb mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test2: JP.L Z,addr24 (ED CA) with condition TRUE (Z=1
        -- after the preceding XOR A) must be taken: lands on A=0x0020
        -- with bank_pc=02h. ----
        wait until A = x"0020" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"02"
            report "Phase11: Test2 JP.L Z,addr24 (condition true) must be taken with bank_pc=02h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test3: JP.L NZ,addr24 (ED C2) with condition FALSE (Z=1,
        -- so NZ is false) must NOT be taken: all 5 bytes are still
        -- consumed (matching real Z80 JP cc,nn timing), falling through
        -- to the very next instruction at A=0x0025. bank_pc must stay
        -- at 02h (unchanged from Test2 - a non-taken JP.L cc must not
        -- touch bank_pc_r at all). ----
        wait until A = x"0025" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"02"
            report "Phase11: Test3 JP.L NZ,addr24 (condition false) must not touch bank_pc, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test4: JP.L addr24 executed in M0 (after SET_M0) must
        -- still take the jump (A=0x0040) but DISCARD the bank byte
        -- (bank_pc stays 00h, NOT 05h) - M0/M1 fetch logic never
        -- consults bank_pc_r regardless (Phase10 gating), so applying
        -- the fetched bank byte there would create a "zombie bank_pc_r"
        -- that silently has no further effect. ----
        wait until A = x"0040" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase11: Test4 JP.L addr24 in M0 must discard the bank byte (bank_pc=00h), got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "00"
            report "Phase11: Test4 expected mode24=M0(00) after SET_M0, got " & to_hstring("00" & mode24)
            severity failure;

        report "Phase11 JP.L testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
