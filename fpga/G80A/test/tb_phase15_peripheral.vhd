--
-- Phase15 self-checking testbench: "peripheral CPU operation" audit
-- (MSX_T80_24bit化_実装手順_V4_2026-10-11.md section17 "Phase 15 - 周辺
--  CPU動作"; CPU仕様書V10 section13 "HALT/WAIT/BUSREQ/BUSACK、DI/EI、
--  interrupt timingはZ80/T80を敷衍する").
--
-- Phase15 adds NO new opcodes - its scope is auditing that EXISTING
-- (inherited, unmodified-by-this-project) Z80/T80 peripheral mechanisms
-- - HALT, WAIT, BUSREQ/BUSACK, the R register, IRQ/NMI acceptance
-- timing, prefix fetch, and refresh - keep working correctly once
-- mode24_r/bank_pc_r/MSP24 are involved, using the same category of
-- "does an existing T80 branch ignore mode24_r/Wait_n" check that
-- uncovered real bugs in Phase11 (MCycle=110/111) and Phase13 (M0/M1
-- NMI/IM2 branches). A code review (see AVAILABLE_INSTRUCTIONS.md
-- section "周辺CPU動作（Phase15）監査メモ") found:
--   - HALT: already correctly guarded (the same Halt_FF/Halt check that
--     suppresses PC+1 wraps BOTH the M0/M1 and M2 Addr24_Inc branches),
--     and M2 interrupt dispatch (the mode24_r="10" IR-forcing branch)
--     is checked BEFORE Halt_FF, so it fires identically whether or not
--     the CPU is currently halted - but this exact HALT+M2-interrupt
--     combination had never been exercised by any existing testbench.
--   - WAIT: every 24bit MSP24/PC24 decrement/increment added since
--     Phase9 already reuses the SAME "TState=2 and Wait_n='1'" trigger
--     the rest of the (unmodified) T80 state machine uses to gate its
--     own TState advancement (real wait-state insertion only ever
--     happens by holding at TState=2 - see the "if TState=2 and
--     Wait_n='0' then" freeze in the main state machine), so a wait
--     state inserted during any M2 push/pop sequence should simply
--     delay - never duplicate or corrupt - the eventual decrement/
--     write. This had also never been exercised with WAIT_n actually
--     toggled by any existing testbench (every prior testbench drives
--     WAIT_n as a constant '1').
--   - BUSREQ/BUSACK: confirmed inert in this project's actual build
--     (fpga/top.v hardwires BUSRQ_n=1 permanently; BUSAK_n is
--     unconnected) - the underlying T80 BUSREQ/BUSACK logic is
--     unmodified from stock T80 and never touches mode24_r/bank
--     registers, so there is nothing 24bit-specific to test here.
--   - R register: refresh-counter increment is gated only by the
--     (unrelated, pre-existing) "Mode<2" T80 generic, not mode24_r;
--     unaffected by this project's changes.
--   - prefix fetch: the DD/FD+CB continuation's MCycle=110/111 class of
--     bug was already found and fixed in Phase11 (see the dedicated T80
--     bug report). New DD/FD+ED combinations beyond LEA.L remain
--     intentionally unimplemented (fall through to NOP, matching
--     roadmap principle 7) - a scope gap, not a Phase15 defect.
--   - refresh operation: the refresh cycle's address-bus override (A_
--     Bank_r forced to 00h for one T-state, pre-existing/unmodified)
--     is confirmed harmless - fpga/top.v already gates BOTH the legacy
--     MSX bus arbiter (mapper_req/megarom_req, via bus_rfsh_n) AND the
--     new extended-memory SD-RAM request (cpu_sdram_req, via
--     bus_rfsh_n) so neither ever acts on an address asserted during a
--     refresh cycle.
--
-- This testbench exercises the two genuinely-new, previously-untested
-- combinations identified above (HALT+M2 interrupt, WAIT during an M2
-- push sequence); the other five items are covered by the code-review
-- findings above (recorded in AVAILABLE_INSTRUCTIONS.md) rather than a
-- new simulation, since they are either provably unaffected or already
-- covered by a prior phase's testbench.
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches).
-- A second parallel array (bank_mem) records A_Bank at the moment of
-- each write, same technique as tb_phase9/11/12/13/tb_rst_l.
--
-- Program layout:
--   0x0000: SET_M2; MSP24=01:E000h; IVR24=02:3000h; EI.
--   0x0015 (HALT_INSTR): HALT. The testbench waits for HALT_n='0'
--     (confirming the CPU has actually entered the halted state, re-
--     fetching NOP in place) before pulsing INT_n='0'.
--     Test1: maskable IRQ while halted must still dispatch through the
--     SAME M2 path as a non-halted IRQ (Phase13's IVR24 mechanism),
--     pushing a 4byte frame whose PC_L is 0x16 - the address right
--     AFTER the 1byte HALT opcode (proving HALT's own fetch already
--     advanced PC before the halt loop began re-fetching in place,
--     exactly like real Z80/non-24bit T80).
--   0x3000 (IVR_HANDLER): INC (HL) at mem(0x0300) (IRQ_COUNT++); RETI.L.
--     Test1b: RETI.L resumes at A=0x0016 with bank_pc/mode24 restored
--     and HALT_n='1' (confirms the CPU is no longer halted).
--   0x0016: LD A,09h; LD RST_B,A (RST_B=09h, precondition for Test2).
--   0x001A: RST.L 38H (ED FF). The testbench injects a 2-cycle WAIT
--     (WAIT_n='0' for 2 CLK periods) at the FIRST wait-sampling point
--     (TState=2) of this instruction's own M1 - the exact same
--     sampling point the rest of the (unmodified) T80 state machine
--     uses - to verify the M2 3byte push-frame (bank_pc_r/PC_H/PC_L to
--     MSP24, same shape as PUSH24 - see t80_mcode.vhd) lands with
--     EXACTLY the same content as an unwaited run, merely delayed in
--     time.
--     Test2: lands on bank09:0038h with bank_pc=09h; push frame
--     (BANK=00h/HIGH=00h/LOW=1Ch, since the return address right after
--     this 2byte RST.L is 0x001C) verified despite the injected wait.
--   0x0038 (bank09h): RET.L - pops the frame back, returning to
--     A=0x001C with bank_pc=00h.
--     Test2b: lands on A=0x001C with bank_pc=00h, mode24=M2.
--   0x001C: HALT - end of program.
--     Test3 (final check): mem(0x0300)=01h (IRQ_COUNT unaffected by
--     Test2's WAIT-laden RST.L/RET.L round trip).
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase15_peripheral.vhd
--   ghdl -e --std=08 tb_phase15_peripheral
--   ghdl -r --std=08 tb_phase15_peripheral
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase15_peripheral is
end entity tb_phase15_peripheral;

architecture sim of tb_phase15_peripheral is

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
        16#000B# => x"21", 16#000C# => x"00", 16#000D# => x"30",
        16#000E# => x"3E", 16#000F# => x"02",
        16#0010# => x"ED", 16#0011# => x"24",
        16#0012# => x"ED", 16#0013# => x"9B",
        16#0014# => x"FB",
        16#0015# => x"76",
        16#0016# => x"3E", 16#0017# => x"09",
        16#0018# => x"ED", 16#0019# => x"3A",
        16#001A# => x"ED", 16#001B# => x"FF",
        16#001C# => x"76",
        16#0038# => x"ED", 16#0039# => x"C9",
        16#3000# => x"21", 16#3001# => x"00", 16#3002# => x"03",
        16#3003# => x"34",
        16#3004# => x"ED", 16#3005# => x"4E",
        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase9/11/12/13/tb_rst_l - lets every M2 push-frame byte be
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
    -- DI_live/DInst/DI split. Note DI is only latched when WAIT_n='1'
    -- at TS="010" - exactly the behaviour Test2 below exercises.
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
        -- phase testbenches.

        -- ---- Test1: HALT, then a maskable IRQ while genuinely halted
        -- (HALT_n='0' confirms the CPU is actually in the halt loop,
        -- not merely fetching the HALT opcode) must dispatch through
        -- the SAME M2 IVR24 path as a non-halted IRQ. ----
        wait until HALT_n = '0';
        wait for 1 ns;
        assert mode24 = "10"
            report "Phase15: Test1 CPU must be halted while still in mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        INT_n <= '0';

        wait until A = x"3000" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '1';
        assert bank_pc = x"02"
            report "Phase15: Test1 IRQ-while-halted must land on IVR24 with bank_pc=02h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase15: Test1 IRQ-while-halted must stay in mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFC#) = x"16" and bank_mem(16#DFFC#) = x"01"
            report "Phase15: Test1 interrupt-frame PC_L byte must be 0x16 (right after the 1byte HALT), got data=" &
                to_hstring(mem(16#DFFC#)) & " bank=" & to_hstring(bank_mem(16#DFFC#))
            severity failure;
        assert mem(16#DFFD#) = x"00" and bank_mem(16#DFFD#) = x"01"
            report "Phase15: Test1 interrupt-frame PC_H byte mismatch at 01:DFFD, got " & to_hstring(mem(16#DFFD#))
            severity failure;

        -- ---- Test1b: RETI.L resumes right after HALT (A=0x0016), with
        -- bank_pc/mode24 restored and the CPU no longer halted. ----
        wait until A = x"0016" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase15: Test1b RETI.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase15: Test1b RETI.L must restore mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert HALT_n = '1'
            report "Phase15: Test1b CPU must no longer be halted after RETI.L resumes"
            severity failure;

        -- ---- Test2: RST.L 38H (ED FF) with a 2-cycle WAIT injected at
        -- the FIRST wait-sampling point (TState=2) of its own M1 - the
        -- same sampling point the rest of the (unmodified) T80 state
        -- machine uses. The M2 3byte push-frame must land with exactly
        -- the same content as an unwaited run (see tb_rst_l.vhd's own
        -- Test1 for the baseline/unwaited reference shape), merely
        -- delayed in time. ----
        wait until A = x"001A" and M1_n = '0';
        wait until TS = "010";
        wait for 1 ns;
        WAIT_n <= '0';
        wait for 40 ns;  -- hold through 2 extra CLK periods (2 Tw wait states)
        WAIT_n <= '1';

        wait until A = x"0038" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"09"
            report "Phase15: Test2 RST.L 38H (with injected WAIT) must land with bank_pc=09h (=RST_B), got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase15: Test2 must not disturb mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFF#) = x"00" and bank_mem(16#DFFF#) = x"01"
            report "Phase15: Test2 return-frame BANK byte mismatch at 01:DFFF (WAIT must not corrupt the push), got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFE#) = x"00" and bank_mem(16#DFFE#) = x"01"
            report "Phase15: Test2 return-frame HIGH byte mismatch at 01:DFFE (WAIT must not corrupt the push), got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFD#) = x"1C" and bank_mem(16#DFFD#) = x"01"
            report "Phase15: Test2 return-frame LOW byte mismatch at 01:DFFD (WAIT must not corrupt the push), got data=" &
                to_hstring(mem(16#DFFD#)) & " bank=" & to_hstring(bank_mem(16#DFFD#))
            severity failure;

        -- ---- Test2b: RET.L (at bank09:0038h) pops the frame back and
        -- returns to A=0x001C with bank_pc=00h. ----
        wait until A = x"001C" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase15: Test2b RET.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase15: Test2b must still be in M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test3 (final check): IRQ_COUNT must still be 1 (Test2's
        -- WAIT-laden RST.L/RET.L round trip must not have re-triggered
        -- or otherwise disturbed the IVR24 handler). ----
        wait until HALT_n = '0';
        wait for 1 ns;
        assert mem(16#0300#) = x"01"
            report "Phase15: Test3 IRQ_COUNT must still be 01h after Test2, got " & to_hstring(mem(16#0300#))
            severity failure;

        report "Phase15 peripheral testbench: all assertions passed";
        std.env.stop;
        wait;
    end process;

    -- Watchdog: fail loudly instead of hanging forever if the program
    -- never reaches the final HALT (e.g. a jump went somewhere
    -- unintended, or the injected WAIT desynchronized the testbench's
    -- own stimulus timing).
    process
    begin
        wait for 50 us;
        assert false
            report "Phase15: testbench watchdog timeout - program never reached the final HALT"
            severity failure;
    end process;

end architecture sim;
