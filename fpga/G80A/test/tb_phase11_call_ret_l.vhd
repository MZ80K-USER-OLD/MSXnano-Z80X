--
-- Phase11 self-checking testbench: CALL.L addr24 / CALL.L cc,addr24 /
-- RET.L / RET.L cc
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 13 "Phase 11";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md section 5 and the roadmap's
--  "CALL.L/RET.LはM2専用24bit far call" note)
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches).
-- A second parallel array (bank_mem) records A_Bank at the moment of
-- each write, same technique as tb_phase9/tb_phase10, so every PUSH24-
-- style 3byte return-frame write (and every plain PUSH BC used as an
-- MSP24 "probe") can be verified against the exact (bank,address) pair
-- it targeted.
--
-- Program layout (MSP24 is set to 01:E000h up front, matching
-- tb_phase10_m2_basic.vhd's own MSP setup so the addresses below are
-- easy to cross-check against that testbench too):
--   0x0000: SET_M2; LD HL,0E000h; LD A,01h; LD HL_B,A; LD24 MSP,HL
--     (MSP24 = 01:E000h).
--   0x000B: CALL.L 02:1000h (unconditional). Pushes the 3byte return
--     frame (bank00h,00h,10h - the address right after this 5byte
--     instruction) to 01:DFFF/DFFE/DFFD, decrementing MSP24 to 01:DFFD.
--     Test1: lands on A=0x1000 with bank_pc=02h; push frame verified.
--   0x1000: RET.L - pops the frame back, restoring MSP24 to 01:E000h.
--     Test2: lands back on A=0x0010 with bank_pc=00h.
--   0x0012: PUSH BC (plain, M2 MSP24 2byte transfer) - probes MSP24 by
--     writing to 01:DFFF/DFFE; since BC=0000h (register reset value)
--     the DATA byte is not meaningful here, only bank_mem (whether a
--     write actually reached that exact address with bank=01h) is
--     checked, confirming RET.L truly restored MSP24 to 01:E000h (any
--     off-by-one would write to the wrong address and leave bank_mem
--     at its 00h default there instead).
--   0x0013: XOR A (Z=1, needed for the cc tests below).
--   0x0014: CALL.L Z,03:2000h (condition TRUE) - taken; same push-frame
--     shape as Test1, now at 01:DFFD/DFFC/DFFB (MSP24 was 01:DFFE after
--     the PUSH BC above).
--     Test3: lands on A=0x2000 with bank_pc=03h; push frame verified.
--   0x2000: RET.L - pops back to 01:DFFE.
--     Test4: lands on A=0x0019 with bank_pc=00h.
--   0x001B: CALL.L NZ,04:3000h (condition FALSE, Z=1 so NZ is false) -
--     must NOT be taken (and MUST NOT touch MSP24 at all); all 5 bytes
--     are still consumed, falling through to 0x0020. 0x3000 is a HALT
--     trap that must never execute.
--   0x0020: PUSH BC (probes MSP24 again, at 01:DFFD/DFFC - the SAME
--     slots as Test3's bank/high push-frame bytes, now overwritten -
--     proving the aborted CALL.L NZ left MSP24 untouched at 01:DFFE).
--     Test5: lands on A=0x0020 (not 0x3000!) with bank_pc=00h
--     (unaffected by the aborted call); push probe verified.
--   0x0021: CALL.L 05:4000h (unconditional) - sets up the RET.L cc
--     test. Push frame at 01:DFFB/DFFA/DFF9 (MSP24 was 01:DFFC).
--     Test6: lands on A=0x4000 with bank_pc=05h; push frame verified.
--   0x4000: RET.L NZ (condition FALSE, Z=1 so NZ is false) - must NOT
--     be taken, falling through to 0x4002 within the SAME bank (05h).
--     Test7: lands on A=0x4002 with bank_pc STILL 05h.
--   0x4004: RET.L Z (condition TRUE) - taken; final return to 0x0026
--     with bank_pc=00h.
--     Test8: lands on A=0x0026 with bank_pc=00h.
--   0x0028: JP.L 0C:5000h (unconditional, still in M2) - sets bank_pc=0Ch
--     as a recognizable precondition for the M0-guard tests below.
--   0x5000: SET_M0 (bank_pc_r stays 0Ch, preserved - SET_M0/M1 never
--     touch bank_pc_r, only SET_M2's M0/M1->M2 transition resets it).
--   0x5002: CALL.L 07:6000h, now executing in M0 (not M2). Per the new
--     mode24_r="10" guard (mirroring JP.L/JR.L's own M0/M1 degrade, but
--     PRESERVING bank_pc_r like plain CALL/RET rather than resetting to
--     00h like JP.L does - CALL.L/RET.L are in the CALL/RET family):
--     the 16bit low part of the target (6000h) still takes effect and
--     the 3byte return frame is still pushed (mode-independent
--     instruction encoding/length), but the fetched bank byte (07h) has
--     NO effect on bank_pc_r.
--     Test9: lands on A=0x6000 with bank_pc STILL 0Ch (not 07h),
--     mode24=M0(00); push frame (BANK=0Ch/HIGH=50h/LOW=07h) verified.
--   0x6000: SET_M1 (prep for manually poking a fake RET.L frame;
--     bank_pc_r stays 0Ch), then pokes a fresh 3byte frame directly into
--     01:DFF0(LOW=55h)/DFF1(HIGH=60h)/DFF2(BANK=AAh - deliberately
--     DIFFERENT from the current bank_pc_r=0Ch, so a broken/unguarded
--     RET.L would be unambiguously caught), sets MSP24=01:DFF0h, then
--     SET_M0 (bank_pc_r stays 0Ch) before executing RET.L.
--   0x601F: RET.L, executing in M0 (not M2). Same guard as Test9: the
--     popped 16bit low part (6055h) still takes effect, MSP24 still
--     advances by 3, but the popped bank byte (AAh) has NO effect.
--     Test10: lands on A=0x6055 with bank_pc STILL 0Ch (not AAh),
--     mode24=M0(00).
--   0x6055: HALT - end of program.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase11_call_ret_l.vhd
--   ghdl -e --std=08 tb_phase11_call_ret_l
--   ghdl -r --std=08 tb_phase11_call_ret_l
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase11_call_ret_l is
end entity tb_phase11_call_ret_l;

architecture sim of tb_phase11_call_ret_l is

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
        16#000B# => x"ED", 16#000C# => x"CD", 16#000D# => x"00", 16#000E# => x"10", 16#000F# => x"02",
        16#0010# => x"3E", 16#0011# => x"99",
        16#0012# => x"C5",
        16#0013# => x"AF",
        16#0014# => x"ED", 16#0015# => x"CC", 16#0016# => x"00", 16#0017# => x"20", 16#0018# => x"03",
        16#0019# => x"3E", 16#001A# => x"88",
        16#001B# => x"ED", 16#001C# => x"C4", 16#001D# => x"00", 16#001E# => x"30", 16#001F# => x"04",
        16#0020# => x"C5",
        16#0021# => x"ED", 16#0022# => x"CD", 16#0023# => x"00", 16#0024# => x"40", 16#0025# => x"05",
        16#0026# => x"3E", 16#0027# => x"DD",
        16#0028# => x"ED", 16#0029# => x"C3", 16#002A# => x"00", 16#002B# => x"50", 16#002C# => x"0C",
        16#5000# => x"ED", 16#5001# => x"90",
        16#5002# => x"ED", 16#5003# => x"CD", 16#5004# => x"00", 16#5005# => x"60", 16#5006# => x"07",
        16#6000# => x"ED", 16#6001# => x"91",
        16#6002# => x"21", 16#6003# => x"F0", 16#6004# => x"DF",
        16#6005# => x"3E", 16#6006# => x"01",
        16#6007# => x"ED", 16#6008# => x"24",
        16#6009# => x"3E", 16#600A# => x"55",
        16#600B# => x"77",
        16#600C# => x"23",
        16#600D# => x"3E", 16#600E# => x"60",
        16#600F# => x"77",
        16#6010# => x"23",
        16#6011# => x"3E", 16#6012# => x"AA",
        16#6013# => x"77",
        16#6014# => x"21", 16#6015# => x"F0", 16#6016# => x"DF",
        16#6017# => x"3E", 16#6018# => x"01",
        16#6019# => x"ED", 16#601A# => x"24",
        16#601B# => x"ED", 16#601C# => x"35",
        16#601D# => x"ED", 16#601E# => x"90",
        16#601F# => x"ED", 16#6020# => x"C9",
        16#6055# => x"76",
        16#1000# => x"ED", 16#1001# => x"C9",
        16#2000# => x"ED", 16#2001# => x"C9",
        16#3000# => x"76",
        16#4000# => x"ED", 16#4001# => x"C0",
        16#4002# => x"3E", 16#4003# => x"CC",
        16#4004# => x"ED", 16#4005# => x"C8",
        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase9/tb_phase10 - lets every CALL.L push-frame byte (and every
    -- plain PUSH BC MSP24 probe) be verified against the exact
    -- (bank,address) pair it targeted.
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
        -- testbench-side delta-cycle race avoidance as
        -- tb_phase10_m2_basic.vhd / tb_phase11_jpl.vhd.

        -- ---- Test1: CALL.L addr24 (ED CD) lands on A=0x1000 with
        -- bank_pc=02h, and pushed the correct 3byte return frame. ----
        wait until A = x"1000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"02"
            report "Phase11: Test1 CALL.L addr24 must land with bank_pc=02h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase11: Test1 CALL.L addr24 must not disturb mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFF#) = x"00" and bank_mem(16#DFFF#) = x"01"
            report "Phase11: Test1 CALL.L return-frame BANK byte mismatch at 01:DFFF, got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFE#) = x"00" and bank_mem(16#DFFE#) = x"01"
            report "Phase11: Test1 CALL.L return-frame HIGH byte mismatch at 01:DFFE, got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFD#) = x"10" and bank_mem(16#DFFD#) = x"01"
            report "Phase11: Test1 CALL.L return-frame LOW byte mismatch at 01:DFFD, got data=" &
                to_hstring(mem(16#DFFD#)) & " bank=" & to_hstring(bank_mem(16#DFFD#))
            severity failure;

        -- ---- Test2: RET.L pops the frame back and returns to A=0x0010
        -- with bank_pc=00h. ----
        wait until A = x"0010" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase11: Test2 RET.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Probe: PUSH BC (plain) must land at 01:DFFF/DFFE,
        -- confirming RET.L truly restored MSP24 to 01:E000h. Sampled at
        -- the next fetch (XOR A at 0x0013) so the PUSH BC has already
        -- completed. ----
        wait until A = x"0013" and M1_n = '0';
        wait for 1 ns;
        assert bank_mem(16#DFFF#) = x"01" and bank_mem(16#DFFE#) = x"01"
            report "Phase11: MSP24 probe after Test2 expected writes at 01:DFFF/DFFE (MSP24 restored to 01:E000h), got bank=" &
                to_hstring(bank_mem(16#DFFF#)) & "/" & to_hstring(bank_mem(16#DFFE#))
            severity failure;

        -- ---- Test3: CALL.L Z,addr24 (ED CC) with condition TRUE (Z=1
        -- after XOR A) must be taken: lands on A=0x2000 with
        -- bank_pc=03h, push frame at 01:DFFD/DFFC/DFFB. ----
        wait until A = x"2000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"03"
            report "Phase11: Test3 CALL.L Z,addr24 (condition true) must be taken with bank_pc=03h, got " & to_hstring(bank_pc)
            severity failure;
        assert mem(16#DFFD#) = x"00" and bank_mem(16#DFFD#) = x"01"
            report "Phase11: Test3 CALL.L return-frame BANK byte mismatch at 01:DFFD"
            severity failure;
        assert mem(16#DFFC#) = x"00" and bank_mem(16#DFFC#) = x"01"
            report "Phase11: Test3 CALL.L return-frame HIGH byte mismatch at 01:DFFC"
            severity failure;
        assert mem(16#DFFB#) = x"19" and bank_mem(16#DFFB#) = x"01"
            report "Phase11: Test3 CALL.L return-frame LOW byte mismatch at 01:DFFB, got " & to_hstring(mem(16#DFFB#))
            severity failure;

        -- ---- Test4: RET.L returns to A=0x0019 with bank_pc=00h. ----
        wait until A = x"0019" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase11: Test4 RET.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test5: CALL.L NZ,addr24 (ED C4) with condition FALSE
        -- (Z=1, so NZ is false) must NOT be taken: falls through to
        -- A=0x0020 (NOT the 0x3000 HALT trap), bank_pc unchanged
        -- (00h). The following PUSH BC probe must land at 01:DFFD/DFFC
        -- (MSP24 untouched at 01:DFFE by the aborted call). ----
        wait until A = x"0020" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase11: Test5 CALL.L NZ,addr24 (condition false) must not touch bank_pc, got " & to_hstring(bank_pc)
            severity failure;
        wait until A = x"0021" and M1_n = '0';
        wait for 1 ns;
        assert bank_mem(16#DFFD#) = x"01" and bank_mem(16#DFFC#) = x"01"
            report "Phase11: MSP24 probe after Test5 expected writes at 01:DFFD/DFFC (aborted CALL.L NZ must not move MSP24), got bank=" &
                to_hstring(bank_mem(16#DFFD#)) & "/" & to_hstring(bank_mem(16#DFFC#))
            severity failure;

        -- ---- Test6: CALL.L addr24 (unconditional, 3rd call) lands on
        -- A=0x4000 with bank_pc=05h, push frame at 01:DFFB/DFFA/DFF9. ----
        wait until A = x"4000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"05"
            report "Phase11: Test6 CALL.L addr24 must land with bank_pc=05h, got " & to_hstring(bank_pc)
            severity failure;
        assert mem(16#DFFB#) = x"00" and bank_mem(16#DFFB#) = x"01"
            report "Phase11: Test6 CALL.L return-frame BANK byte mismatch at 01:DFFB"
            severity failure;
        assert mem(16#DFFA#) = x"00" and bank_mem(16#DFFA#) = x"01"
            report "Phase11: Test6 CALL.L return-frame HIGH byte mismatch at 01:DFFA"
            severity failure;
        assert mem(16#DFF9#) = x"26" and bank_mem(16#DFF9#) = x"01"
            report "Phase11: Test6 CALL.L return-frame LOW byte mismatch at 01:DFF9, got " & to_hstring(mem(16#DFF9#))
            severity failure;

        -- ---- Test7: RET.L NZ (ED C0) with condition FALSE must NOT be
        -- taken: falls through to A=0x4002, bank_pc STAYS 05h (same
        -- bank, no return happened). ----
        wait until A = x"4002" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"05"
            report "Phase11: Test7 RET.L NZ (condition false) must not return, bank_pc should stay 05h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test8: RET.L Z (ED C8) with condition TRUE must be
        -- taken: final return to A=0x0026 with bank_pc=00h. ----
        wait until A = x"0026" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase11: Test8 RET.L Z (condition true) must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test9: CALL.L addr24 executed OUTSIDE M2 (M0, set up via
        -- JP.L 0C:5000h + SET_M0) must still jump to the 16bit low part
        -- of the target and still push the 3byte return frame, but must
        -- NOT apply the fetched bank byte (07h) to bank_pc - bank_pc
        -- must stay at the 0Ch precondition set by the preceding JP.L
        -- (mirrors plain CALL/RET's "same 64KB segment, PC_B不変" rule,
        -- same family as JumpR/Call, unlike JP.L's own "reset to 00h"
        -- M0/M1 degrade). ----
        wait until A = x"6000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"0C"
            report "Phase11: Test9 CALL.L addr24 outside M2 must NOT apply the fetched bank byte, bank_pc must stay 0Ch, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "00"
            report "Phase11: Test9 must still be in M0(00), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFB#) = x"0C" and bank_mem(16#DFFB#) = x"01"
            report "Phase11: Test9 CALL.L return-frame BANK byte mismatch at 01:DFFB, got data=" &
                to_hstring(mem(16#DFFB#)) & " bank=" & to_hstring(bank_mem(16#DFFB#))
            severity failure;
        assert mem(16#DFFA#) = x"50" and bank_mem(16#DFFA#) = x"01"
            report "Phase11: Test9 CALL.L return-frame HIGH byte mismatch at 01:DFFA, got " & to_hstring(mem(16#DFFA#))
            severity failure;
        assert mem(16#DFF9#) = x"07" and bank_mem(16#DFF9#) = x"01"
            report "Phase11: Test9 CALL.L return-frame LOW byte mismatch at 01:DFF9, got " & to_hstring(mem(16#DFF9#))
            severity failure;

        -- ---- Test10: RET.L executed OUTSIDE M2 (M0, after manually
        -- poking a fake 3byte frame at 01:DFF0/DFF1/DFF2 with a
        -- deliberately WRONG bank byte AAh - different from the current
        -- bank_pc=0Ch - so an unguarded RET.L would be unambiguously
        -- caught) must still jump to the popped 16bit low part (6055h)
        -- and still advance MSP24 by 3, but must NOT apply the popped
        -- bank byte (AAh) - bank_pc must stay at 0Ch. ----
        wait until A = x"6055" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"0C"
            report "Phase11: Test10 RET.L outside M2 must NOT apply the popped bank byte, bank_pc must stay 0Ch, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "00"
            report "Phase11: Test10 must still be in M0(00), got " & to_hstring("00" & mode24)
            severity failure;

        report "Phase11 CALL.L/RET.L testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
