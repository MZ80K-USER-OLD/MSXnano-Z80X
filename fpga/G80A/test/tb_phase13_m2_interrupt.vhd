--
-- Phase13 self-checking testbench: M2 interrupt entry (maskable IRQ ->
-- IVR24, NMI -> NVR24) + RETI.L (ED 4E) / RETN.L (ED 8C)
-- (MSX_T80_24bit化_CPU仕様書_V10_2026-10-11.md section13 "Interrupt")
--
-- Exercises the NEW Phase13 mechanism: in M2, both maskable IRQ and NMI
-- push an identical 4byte frame (MODE/PC_B/PC_H/PC_L, same order as
-- CALL.Mx/RET.M) to MSP24 and jump DIRECTLY to IVR24 (IRQ) or NVR24
-- (NMI), completely bypassing IStatus/IM (the program below explicitly
-- sets IM2 to prove this - if the OLD M0/M1 IM2 vector-table-read path
-- were mistakenly taken instead, it would try to read a vector pointer
-- from {I,Z} which is never set up in this test and would jump
-- somewhere wrong, failing every assertion below). RETI.L/RETN.L share
-- RET.M's exact 4byte pop/restore mechanism; the only behavioural
-- difference is that RETN.L additionally restores IFF1<-IFF2 (RETI.L
-- does not), verified via Test2 (masked) and Test4 (restored).
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches).
-- A second parallel array (bank_mem) records A_Bank at the moment of
-- each write, same technique as tb_phase12_mode_control.vhd, so the
-- 4byte interrupt frame can be verified against the exact (bank,
-- address) pair it targeted. A dedicated stimulus/assertion process
-- drives INT_n/NMI_n at precisely chosen "wait until A=...,M1_n='0'"
-- synchronization points (same technique already used throughout this
-- test suite) so interrupt acceptance timing is fully deterministic.
--
-- Program layout:
--   0x0000: SET_M2; MSP24=01:E000h; IVR24=02:3000h; NVR24=03:4000h;
--     IM 2 (deliberately set, to prove M2 ignores it); EI.
--   0x0020 (TEST1_PULSE): NOP - testbench asserts INT_n='0' here (level-
--     triggered maskable IRQ). Serviced after this NOP completes
--     (EI's own one-instruction acceptance delay was already satisfied
--     by the preceding IM2/EI sequence), pushing a 4byte frame
--     (MODE=02h,PC_B=00h,PC_H=00h,PC_L=21h - the address right after
--     this NOP) to 01:DFFF/DFFE/DFFD/DFFC and jumping to 02:3000h.
--     Test1: lands on A=0x3000 with bank_pc=02h, mode24=M2(10); push
--     frame verified. IVR_HANDLER increments IRQ_COUNT and executes
--     RETI.L (does NOT restore IFF1<-IFF2 - IFF1/IFF2 stay 0, as
--     cleared by the hardware on IRQ acceptance).
--     Test1b: RETI.L resumes at A=0x0021 (TEST1_RESUME) with bank_pc
--     restored to 00h and mode24 restored to M2(10); MSP24 restored to
--     01:E000h (probed via the SAME push-frame addresses being reused
--     identically by Test3/Test4 below).
--   0x0022 (TEST2_PULSE): NOP - testbench re-asserts INT_n='0' here.
--     Must NOT be serviced (IFF1 is still 0 - RETI.L does not restore
--     it), so execution falls straight through to 0x0024.
--     Test2: lands on A=0x0024 (TEST2_CHECK) with IRQ_COUNT STILL 1
--     (confirming the second INT_n pulse was correctly ignored).
--   0x0025: EI (re-enables IFF1/IFF2, setting up Test4's restore check).
--   0x0026 (TEST3_PULSE): NOP - testbench pulses NMI_n (falling edge).
--     NMI is never maskable, so this is always serviced regardless of
--     IFF1 - pushes a 4byte frame (PC_L=27h this time) to the SAME
--     01:DFFF-DFFC addresses (MSP24 was restored to 01:E000h by Test1's
--     RETI.L) and jumps to 03:4000h.
--     Test3: lands on A=0x4000 with bank_pc=03h, mode24=M2(10); push
--     frame verified. NVR_HANDLER increments NMI_COUNT and executes
--     RETN.L (DOES restore IFF1<-IFF2=1, since EI set IFF2=1 just
--     before this NMI and NMI acceptance only clears IFF1, leaving
--     IFF2 untouched).
--     Test3b: RETN.L resumes at A=0x0027 (TEST3_RESUME).
--   0x0028 (TEST4_PULSE): NOP - testbench asserts INT_n='0' here again.
--     Must NOW be serviced (IFF1 was restored to 1 by Test3's RETN.L) -
--     pushes a 4byte frame (PC_L=29h) and jumps to 02:3000h again.
--     Test4: lands on A=0x3000 a SECOND time; push frame verified;
--     IVR_HANDLER increments IRQ_COUNT to 2 and RETI.L resumes at
--     A=0x0029 (TEST4_RESUME).
--   0x002A: HALT - end of program. Final check: IRQ_COUNT=2,
--     NMI_COUNT=1.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase13_m2_interrupt.vhd
--   ghdl -e --std=08 tb_phase13_m2_interrupt
--   ghdl -r --std=08 tb_phase13_m2_interrupt
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase13_m2_interrupt is
end entity tb_phase13_m2_interrupt;

architecture sim of tb_phase13_m2_interrupt is

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
        -- main program
        16#0000# => x"ED", 16#0001# => x"92", 16#0002# => x"21", 16#0003# => x"00",
        16#0004# => x"E0", 16#0005# => x"3E", 16#0006# => x"01", 16#0007# => x"ED",
        16#0008# => x"24", 16#0009# => x"ED", 16#000A# => x"35", 16#000B# => x"21",
        16#000C# => x"00", 16#000D# => x"30", 16#000E# => x"3E", 16#000F# => x"02",
        16#0010# => x"ED", 16#0011# => x"24", 16#0012# => x"ED", 16#0013# => x"9B",
        16#0014# => x"21", 16#0015# => x"00", 16#0016# => x"40", 16#0017# => x"3E",
        16#0018# => x"03", 16#0019# => x"ED", 16#001A# => x"24", 16#001B# => x"ED",
        16#001C# => x"9E", 16#001D# => x"ED", 16#001E# => x"5E", 16#001F# => x"FB",
        16#0020# => x"00", 16#0021# => x"00", 16#0022# => x"00", 16#0023# => x"00",
        16#0024# => x"00", 16#0025# => x"FB", 16#0026# => x"00", 16#0027# => x"00",
        16#0028# => x"00", 16#0029# => x"00", 16#002A# => x"76",
        -- IVR24 handler
        16#3000# => x"21", 16#3001# => x"00", 16#3002# => x"03", 16#3003# => x"34",
        16#3004# => x"ED", 16#3005# => x"4E",
        -- NVR24 handler
        16#4000# => x"21", 16#4001# => x"01", 16#4002# => x"03", 16#4003# => x"34",
        16#4004# => x"ED", 16#4005# => x"8C",
        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase12_mode_control.vhd - lets every interrupt-frame byte be
    -- verified against the exact (bank,address) pair it targeted.
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
        -- Phase10/11/12 testbenches.

        -- ---- Test1: maskable IRQ in M2 (IM2 set, must be bypassed) ->
        -- IVR24. Pulse INT_n (level-triggered) right as the TEST1_PULSE
        -- NOP begins, so it is guaranteed to be recognized only after
        -- THIS NOP fully completes (deterministic return address). ----
        wait until A = x"0020" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '0';

        wait until A = x"3000" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '1';
        assert bank_pc = x"02"
            report "Phase13: Test1 IRQ must land on IVR24 with bank_pc=02h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase13: Test1 IRQ must stay in mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFF#) = x"02" and bank_mem(16#DFFF#) = x"01"
            report "Phase13: Test1 interrupt-frame MODE byte mismatch at 01:DFFF, got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFE#) = x"00" and bank_mem(16#DFFE#) = x"01"
            report "Phase13: Test1 interrupt-frame PC_B byte mismatch at 01:DFFE, got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFD#) = x"00" and bank_mem(16#DFFD#) = x"01"
            report "Phase13: Test1 interrupt-frame PC_H byte mismatch at 01:DFFD, got " & to_hstring(mem(16#DFFD#))
            severity failure;
        assert mem(16#DFFC#) = x"21" and bank_mem(16#DFFC#) = x"01"
            report "Phase13: Test1 interrupt-frame PC_L byte mismatch at 01:DFFC, got " & to_hstring(mem(16#DFFC#))
            severity failure;

        -- ---- Test1b: RETI.L resumes at A=0x0021 with bank_pc/mode24
        -- restored. ----
        wait until A = x"0021" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase13: Test1b RETI.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase13: Test1b RETI.L must restore mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test2: a second INT_n pulse right after RETI.L must NOT
        -- be serviced (RETI.L does not restore IFF1<-IFF2; IFF1 is
        -- still 0 from Test1's IRQ acceptance). ----
        wait until A = x"0022" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '0';

        wait until A = x"0024" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '1';
        assert mem(16#0300#) = x"01"
            report "Phase13: Test2 a masked INT_n pulse must NOT re-trigger the IVR24 handler (IRQ_COUNT must stay 1), got " &
                to_hstring(mem(16#0300#))
            severity failure;

        -- ---- Test3: NMI (never maskable) -> NVR24, after the EI at
        -- 0x0025 re-enabled IFF1/IFF2. ----
        wait until A = x"0026" and M1_n = '0';
        wait for 1 ns;
        NMI_n <= '0';
        wait for 30 ns;
        NMI_n <= '1';

        wait until A = x"4000" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"03"
            report "Phase13: Test3 NMI must land on NVR24 with bank_pc=03h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase13: Test3 NMI must stay in mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFF#) = x"02" and bank_mem(16#DFFF#) = x"01"
            report "Phase13: Test3 interrupt-frame MODE byte mismatch at 01:DFFF, got " & to_hstring(mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFC#) = x"27" and bank_mem(16#DFFC#) = x"01"
            report "Phase13: Test3 interrupt-frame PC_L byte mismatch at 01:DFFC, got " & to_hstring(mem(16#DFFC#))
            severity failure;

        -- ---- Test3b: RETN.L resumes at A=0x0027. ----
        wait until A = x"0027" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase13: Test3b RETN.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase13: Test3b RETN.L must restore mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test4: a THIRD INT_n pulse must NOW be serviced (RETN.L
        -- DID restore IFF1<-IFF2=1, re-enabling maskable interrupts). ----
        wait until A = x"0028" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '0';

        wait until A = x"3000" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '1';
        assert mem(16#DFFC#) = x"29"
            report "Phase13: Test4 interrupt-frame PC_L byte mismatch at 01:DFFC, got " & to_hstring(mem(16#DFFC#))
            severity failure;

        wait until A = x"0029" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase13: Test4 RETI.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Final: HALT reached, IRQ_COUNT=2 (Test1+Test4), NMI_COUNT=1 (Test3). ----
        wait until A = x"002A" and M1_n = '0';
        wait for 1 ns;
        assert mem(16#0300#) = x"02"
            report "Phase13: final IRQ_COUNT must be 02h, got " & to_hstring(mem(16#0300#))
            severity failure;
        assert mem(16#0301#) = x"01"
            report "Phase13: final NMI_COUNT must be 01h, got " & to_hstring(mem(16#0301#))
            severity failure;

        report "Phase13 M2 interrupt (IRQ->IVR24/NMI->NVR24, RETI.L/RETN.L) testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
