--
-- Phase12 self-checking testbench: JP.M0/M1/M2 addr16/24, CALL.M0/M1
-- addr16, RET.M
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 14 "Phase 12";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md section 5 and the roadmap's
--  "CALL.MxはMSPへ4byte保存する" note)
--
-- CALL.M2 addr24 (ED 98) is DEFERRED (needs 8 MCycles, exceeding the
-- 3bit MCycle counter's max of 7 - see AVAILABLE_INSTRUCTIONS.md section
-- 14) and is NOT covered by this testbench.
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches).
-- A second parallel array (bank_mem) records A_Bank at the moment of
-- each write, same technique as tb_phase11_call_ret_l.vhd, so the
-- CALL.M0/M1 4byte return frame (MODE/PC_B/PC_H/PC_L) can be verified
-- against the exact (bank,address) pair it targeted.
--
-- Program layout (MSP24 is set to 01:E000h up front):
--   0x0000: SET_M2; LD HL,0E000h; LD A,01h; LD HL_B,A; LD24 MSP,HL
--     (MSP24 = 01:E000h).
--   0x000B: JP.M2 02:1000h (ED 95). Already in M2 (set at 0x0000), so
--     this is a trivial M2->M2 mode "switch" - but must still apply the
--     fetched bank byte and jump unconditionally (unlike JP.L, which
--     only applies the bank byte when ALREADY in M2 - JP.M2 always
--     does, which this M2->M2 case alone cannot distinguish from JP.L;
--     Test2/Test3 below additionally confirm the M0/M1 cases where the
--     difference matters).
--     Test1: lands on A=0x1000 with bank_pc=02h, mode24=M2.
--   0x1000: JP.M0 0x2000h (ED 93). Switches M2->M0; bank_pc resets to
--     00h (addr16 target = bank00h).
--     Test2: lands on A=0x2000 with bank_pc=00h, mode24=M0(00).
--   0x2000: JP.M1 0x3000h (ED 94). Switches M0->M1.
--     Test3: lands on A=0x3000 with mode24=M1(01).
--   0x3000: SET_M2 (M1->M2, resets bank_pc to 00h per Phase10's rule).
--   0x3002: CALL.M0 0x4000h (ED 96). Pushes a 4byte return frame
--     (MODE=02h[=M2],PC_B=00h,PC_H=30h,PC_L=06h - the address right
--     after this 4byte instruction, 0x3002+4=0x3006) to 01:DFFF/DFFE/
--     DFFD/DFFC, decrementing MSP24 to 01:DFFCh. Switches to M0, jumps
--     to 0x4000, bank_pc resets to 00h.
--     Test4: lands on A=0x4000 with mode24=M0(00), bank_pc=00h; push
--     frame verified.
--   0x4000: RET.M (ED 99). Pops the frame back, restoring MSP24 to
--     01:E000h, PC=0x3006, and mode24_r=M2(10) (restored from the
--     popped MODE byte, NOT hardcoded).
--     Test5: lands on A=0x3006 with mode24=M2(10), bank_pc=00h.
--   0x3006: CALL.M1 0x5000h (ED 97). Same shape as CALL.M0 above (push
--     frame at 01:DFFF/DFFE/DFFD/DFFC again, MSP24 was restored to
--     01:E000h by Test5's RET.M), switches to M1 this time.
--     Test6: lands on A=0x5000 with mode24=M1(01).
--   0x5000: RET.M (ED 99). Pops back, restoring mode24_r=M2(10) again.
--     Test7: lands on A=0x300A (0x3006+4) with mode24=M2(10).
--   0x300A: HALT - end of program.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase12_mode_control.vhd
--   ghdl -e --std=08 tb_phase12_mode_control
--   ghdl -r --std=08 tb_phase12_mode_control
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase12_mode_control is
end entity tb_phase12_mode_control;

architecture sim of tb_phase12_mode_control is

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
        16#0002# => x"21", 16#0003# => x"00", 16#0004# => x"E0",
        16#0005# => x"3E", 16#0006# => x"01",
        16#0007# => x"ED", 16#0008# => x"24",
        16#0009# => x"ED", 16#000A# => x"35",
        16#000B# => x"ED", 16#000C# => x"95", 16#000D# => x"00", 16#000E# => x"10", 16#000F# => x"02",
        16#1000# => x"ED", 16#1001# => x"93", 16#1002# => x"00", 16#1003# => x"20",
        16#2000# => x"ED", 16#2001# => x"94", 16#2002# => x"00", 16#2003# => x"30",
        16#3000# => x"ED", 16#3001# => x"92",
        16#3002# => x"ED", 16#3003# => x"96", 16#3004# => x"00", 16#3005# => x"40",
        16#4000# => x"ED", 16#4001# => x"99",
        16#3006# => x"ED", 16#3007# => x"97", 16#3008# => x"00", 16#3009# => x"50",
        16#5000# => x"ED", 16#5001# => x"99",
        16#300A# => x"76",
        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase11_call_ret_l.vhd - lets every CALL.M0/M1 push-frame byte
    -- be verified against the exact (bank,address) pair it targeted.
    signal bank_mem : mem_array := (others => x"00");

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
            if IORQ = '0' and Write = '1' then
                mem(to_integer(unsigned(A))) <= DO;
                bank_mem(to_integer(unsigned(A))) <= A_Bank;
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
        -- testbench-side delta-cycle race avoidance as all previous
        -- Phase10/11 testbenches.

        -- ---- Test1: JP.M2 addr24 (ED 95), already in M2, lands on
        -- A=0x1000 with bank_pc=02h. ----
        wait until A = x"1000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"02"
            report "Phase12: Test1 JP.M2 addr24 must land with bank_pc=02h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase12: Test1 JP.M2 addr24 must set mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test2: JP.M0 addr16 (ED 93) switches M2->M0, lands on
        -- A=0x2000 with bank_pc=00h. ----
        wait until A = x"2000" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "00"
            report "Phase12: Test2 JP.M0 addr16 must set mode24=M0(00), got " & to_hstring("00" & mode24)
            severity failure;
        assert bank_pc = x"00"
            report "Phase12: Test2 JP.M0 addr16 must reset bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test3: JP.M1 addr16 (ED 94) switches M0->M1, lands on
        -- A=0x3000 with mode24=M1. ----
        wait until A = x"3000" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "01"
            report "Phase12: Test3 JP.M1 addr16 must set mode24=M1(01), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test4: CALL.M0 addr16 (ED 96) from M2 (after the SET_M2
        -- at 0x3000) lands on A=0x4000 with mode24=M0, bank_pc=00h, and
        -- push frame verified at 01:DFFF(MODE=02h)/DFFE(PC_B=00h)/
        -- DFFD(PC_H=30h)/DFFC(PC_L=06h). ----
        wait until A = x"4000" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "00"
            report "Phase12: Test4 CALL.M0 addr16 must set mode24=M0(00), got " & to_hstring("00" & mode24)
            severity failure;
        assert bank_pc = x"00"
            report "Phase12: Test4 CALL.M0 addr16 must reset bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mem(16#DFFF#) = x"02" and bank_mem(16#DFFF#) = x"01"
            report "Phase12: Test4 CALL.M0 return-frame MODE byte mismatch at 01:DFFF, got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFE#) = x"00" and bank_mem(16#DFFE#) = x"01"
            report "Phase12: Test4 CALL.M0 return-frame PC_B byte mismatch at 01:DFFE, got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFD#) = x"30" and bank_mem(16#DFFD#) = x"01"
            report "Phase12: Test4 CALL.M0 return-frame PC_H byte mismatch at 01:DFFD, got " & to_hstring(mem(16#DFFD#))
            severity failure;
        assert mem(16#DFFC#) = x"06" and bank_mem(16#DFFC#) = x"01"
            report "Phase12: Test4 CALL.M0 return-frame PC_L byte mismatch at 01:DFFC, got " & to_hstring(mem(16#DFFC#))
            severity failure;

        -- ---- Test5: RET.M (ED 99) pops the frame, restoring A=0x3006
        -- with mode24=M2(10) (restored from the popped MODE byte) and
        -- bank_pc=00h. ----
        wait until A = x"3006" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "10"
            report "Phase12: Test5 RET.M must restore mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert bank_pc = x"00"
            report "Phase12: Test5 RET.M must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test6: CALL.M1 addr16 (ED 97) lands on A=0x5000 with
        -- mode24=M1. ----
        wait until A = x"5000" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "01"
            report "Phase12: Test6 CALL.M1 addr16 must set mode24=M1(01), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test7: RET.M pops the second frame, restoring A=0x300A
        -- with mode24=M2(10) again. ----
        wait until A = x"300A" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "10"
            report "Phase12: Test7 RET.M must restore mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        report "Phase12 mode-control (JP.Mx/CALL.M0/M1/RET.M) testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
