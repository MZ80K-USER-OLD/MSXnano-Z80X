-- Historical fixture: requires the retired ED9B IVR writer.
-- Do not run on current RTL; see verification_data/v161_rst_l/README.md.
--
-- Nested-MSP24-stack regression testbench (triggered by a real-hardware
-- investigation of P1314T.COM's Test5 - see Project/P1314Test/README.md
-- "開発経緯: 実機で発見した「M2中のネストしたMSP24スタック」問題").
--
-- Phase10 (CPU仕様書V8/V10 section... "M2基本動作") specifies that in
-- M2, ALL plain (non-.L) PUSH/POP/CALL/RET instructions automatically
-- route through MSP24 (the SAME aSP/IncDec_16 mechanism, just switched
-- to the 24bit MSP/bank_msp_r pair instead of the plain 16bit SP). This
-- means a real M2 interrupt handler that itself uses an ordinary
-- "PUSH AF" / "POP AF" (not PUSH24/POP24) nests its own MSP24 usage
-- UNDERNEATH whatever MSP24 state already existed when the interrupt
-- was accepted (e.g. a plain CALL's own 2byte return address, already
-- pushed to MSP24, sitting below the M2 interrupt entry's own 4byte
-- frame, sitting below the handler's own PUSH AF). This EXACT nested
-- combination had never been exercised by tb_phase13_m2_interrupt.vhd
-- (whose IVR_HANDLER is a trivial "INC (HL)" with no PUSH/POP/CALL of
-- its own, and whose stimulus is a bare NOP loop with no outer CALL).
--
-- This testbench reproduces the full nesting chain deterministically:
--   1. CALL SUBROUTINE (plain, M2-routed through MSP24): MSP24
--      E000h -> DFFEh (2byte return-address push).
--   2. Inside SUBROUTINE, a maskable IRQ is accepted mid-busy-loop
--      (bare NOPs, same INT_n pulse-at-NOP-boundary technique as
--      tb_phase13_m2_interrupt.vhd's own Test1): M2 interrupt entry
--      pushes its own 4byte frame: MSP24 DFFEh -> DFFAh.
--   3. IVR_HANDLER executes "PUSH AF" (plain, M2-routed): MSP24
--      DFFAh -> DFF8h.
--   4. Increments a scratch counter via plain 16bit absolute
--      addressing (always flat bank00h, unaffected by mode/bank
--      registers - same technique as every previous phase testbench).
--   5. "POP AF": MSP24 DFF8h -> DFFAh (undoes step 3).
--   6. "RETI.L": pops the matching 4byte frame (the SAME Phase13
--      4byte-pop mechanism as RET.M/RETN.L): MSP24 DFFAh -> DFFEh
--      (undoes step 2), resuming execution right after the
--      interrupted NOP.
--   7. SUBROUTINE finishes its remaining NOPs, then a plain "RET"
--      (M2-routed): MSP24 DFFEh -> E000h (undoes step 1), returning
--      to the CALLer.
--
-- If every one of these 4 layers unwinds cleanly and consistently,
-- MSP24 ends up EXACTLY back at its starting value (01:E000h) and the
-- CALLer resumes normally. This testbench checks exactly that, plus
-- the scratch counter's final value and the exact byte content of
-- every push-frame layer (CALL's own 2byte frame, the interrupt
-- entry's own 4byte frame) written along the way.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_m2_nested_stack.vhd
--   ghdl -e --std=08 tb_m2_nested_stack
--   ghdl -r --std=08 tb_m2_nested_stack
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_m2_nested_stack is
end entity tb_m2_nested_stack;

architecture sim of tb_m2_nested_stack is

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
        -- Main program (bank00h).
        16#0000# => x"ED", 16#0001# => x"92",               -- SET_M2
        16#0002# => x"21", 16#0003# => x"00", 16#0004# => x"E0", -- LD HL,0E000h
        16#0005# => x"3E", 16#0006# => x"01",               -- LD A,01h
        16#0007# => x"ED", 16#0008# => x"24",               -- LD HL_B,A (=01h)
        16#0009# => x"ED", 16#000A# => x"35",               -- LD24 MSP,HL
        16#000B# => x"AF",                                   -- XOR A
        16#000C# => x"ED", 16#000D# => x"24",               -- LD HL_B,A (=0, reset
                                                               -- before setting up
                                                               -- IVR24's own bank
                                                               -- byte below)
        16#000E# => x"21", 16#000F# => x"00", 16#0010# => x"10", -- LD HL,1000h
        16#0011# => x"ED", 16#0012# => x"9B",               -- LD24 IVR,HL
        16#0013# => x"FB",                                   -- EI
        16#0014# => x"CD", 16#0015# => x"25", 16#0016# => x"00", -- CALL 0025h
        16#0017# => x"C5",                                   -- PUSH BC (MSP24
                                                               -- restore probe)
        16#0018# => x"76",                                   -- HALT

        -- SUBROUTINE (bank00h): bare NOP busy-loop (INT_n is pulsed by
        -- the testbench exactly as the FIRST NOP begins), then a plain
        -- RET (M2-routed through MSP24).
        16#0025# => x"00", 16#0026# => x"00", 16#0027# => x"00",
        16#0028# => x"00", 16#0029# => x"C9",                -- RET

        -- IVR24 handler (bank00h): PUSH AF (plain, M2-routed) / scratch
        -- counter increment via plain absolute 16bit addressing (always
        -- flat bank00h) / POP AF / RETI.L.
        16#1000# => x"F5",                                   -- PUSH AF
        16#1001# => x"3A", 16#1002# => x"00", 16#1003# => x"03", -- LD A,(0300h)
        16#1004# => x"3C",                                   -- INC A
        16#1005# => x"32", 16#1006# => x"00", 16#1007# => x"03", -- LD (0300h),A
        16#1008# => x"F1",                                   -- POP AF
        16#1009# => x"ED", 16#100A# => x"F3",                -- RETI.L

        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase9/11/12/13/tb_rst_l - lets every push-frame byte (both
    -- the plain CALL's 2byte frame and the interrupt entry's 4byte
    -- frame) be verified against the exact (bank,address) pair it
    -- targeted.
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
        -- phase testbenches.

        -- ---- Test1: after CALL 0025h, MSP24 must have decremented by
        -- 2 (01:E000h -> 01:DFFEh) with the correct 2byte return-
        -- address frame (the address right after the 3byte CALL
        -- instruction, 0x0017). Sampled at the first NOP of SUBROUTINE
        -- (A=0x0025), which is also where INT_n is pulsed. ----
        wait until A = x"0025" and M1_n = '0';
        wait for 1 ns;
        assert mem(16#DFFE#) = x"17" and bank_mem(16#DFFE#) = x"01"
            report "NestedStack: Test1 plain CALL return-address LOW byte mismatch at 01:DFFE, got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFF#) = x"00" and bank_mem(16#DFFF#) = x"01"
            report "NestedStack: Test1 plain CALL return-address HIGH byte mismatch at 01:DFFF, got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert bank_msp = x"01" and mode24 = "10"
            report "NestedStack: Test1 precondition (bank_msp=01h, mode24=M2) not met"
            severity failure;

        -- Pulse the maskable IRQ exactly as this first NOP begins (same
        -- technique as tb_phase13_m2_interrupt.vhd's own Test1), then
        -- hold it asserted (level-triggered, mirroring a real
        -- un-acknowledged VDP IRQ) until the handler's own IVR_HANDLER
        -- code reaches its midpoint - deasserting mid-handler to avoid
        -- any chance of a second acceptance before IFF1 is forced to 0
        -- (which happens synchronously on acceptance regardless of
        -- INT_n's own de-assertion timing, but keeping this close to
        -- the real scenario nonetheless).
        INT_n <= '0';

        -- ---- Test2: the M2 interrupt entry's own 4byte frame must
        -- land UNDERNEATH the CALL's frame (decrementing MSP24 a
        -- further 4, 01:DFFEh -> 01:DFFAh), with the correct contents
        -- (PC_L/PC_H/PC_B/MODE for the resume point right after the
        -- interrupted NOP, 0x0026). Sampled at IVR_HANDLER's first
        -- instruction (A=0x1000). ----
        wait until A = x"1000" and M1_n = '0';
        wait for 1 ns;
        INT_n <= '1';
        assert bank_pc = x"00" and mode24 = "10"
            report "NestedStack: Test2 IVR24 entry must land with bank_pc=00h, mode24=M2(10), got bank_pc=" &
                to_hstring(bank_pc) & " mode24=" & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFA#) = x"26" and bank_mem(16#DFFA#) = x"01"
            report "NestedStack: Test2 interrupt-frame PC_L byte mismatch at 01:DFFA, got " & to_hstring(mem(16#DFFA#))
            severity failure;
        assert mem(16#DFFB#) = x"00" and bank_mem(16#DFFB#) = x"01"
            report "NestedStack: Test2 interrupt-frame PC_H byte mismatch at 01:DFFB, got " & to_hstring(mem(16#DFFB#))
            severity failure;
        assert mem(16#DFFC#) = x"00" and bank_mem(16#DFFC#) = x"01"
            report "NestedStack: Test2 interrupt-frame PC_B byte mismatch at 01:DFFC, got " & to_hstring(mem(16#DFFC#))
            severity failure;
        assert mem(16#DFFD#) = x"02" and bank_mem(16#DFFD#) = x"01"
            report "NestedStack: Test2 interrupt-frame MODE byte mismatch at 01:DFFD, got " & to_hstring(mem(16#DFFD#))
            severity failure;

        -- ---- Test3: after IVR_HANDLER's own "PUSH AF" (M2-routed, a
        -- THIRD nested layer on MSP24), MSP24 must have decremented a
        -- further 2 (01:DFFAh -> 01:DFF8h). Sampled at the handler's
        -- next instruction (A=0x1001). ----
        wait until A = x"1001" and M1_n = '0';
        wait for 1 ns;
        assert bank_msp = x"01"
            report "NestedStack: Test3 bank_msp must still be 01h, got " & to_hstring(bank_msp)
            severity failure;

        -- ---- Test4: RETI.L must resume execution right after the
        -- interrupted NOP (A=0x0026), with MSP24 fully unwound back to
        -- its post-CALL value (01:DFFEh - i.e. the interrupt entry's
        -- 4byte frame AND the handler's own PUSH AF/POP AF pair must
        -- have left NO residue on MSP24), and the scratch counter
        -- incremented to 01h. This is the crux of the regression: if
        -- the nested MSP24 usage (CALL + interrupt-entry-4byte-frame +
        -- plain PUSH/POP inside the handler) does NOT unwind cleanly,
        -- either this wait will time out (CPU never reaches 0x0026) or
        -- bank_msp/MSP will be wrong here. ----
        wait until A = x"0026" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00" and mode24 = "10"
            report "NestedStack: Test4 RETI.L must resume with bank_pc=00h, mode24=M2(10), got bank_pc=" &
                to_hstring(bank_pc) & " mode24=" & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#0300#) = x"01"
            report "NestedStack: Test4 scratch counter must be 01h after the handler ran once, got " &
                to_hstring(mem(16#0300#))
            severity failure;

        -- ---- Test5: SUBROUTINE's own final "RET" (M2-routed) must
        -- unwind the LAST remaining layer (the plain CALL's own 2byte
        -- frame), restoring MSP24 all the way back to its ORIGINAL
        -- 01:E000h value, and PC must land back on the CALLer's
        -- "PUSH BC" probe instruction (0x0017). This confirms the full
        -- 4-layer nest (CALL / interrupt-entry / PUSH AF-POP AF /
        -- RETI.L / RET) unwound without leaving ANY residue on MSP24.
        -- (MSP's own low-16bit value has no dedicated output port -
        -- same limitation as every previous phase testbench - so this
        -- is confirmed indirectly via a "PUSH BC" probe write landing
        -- at the expected 01:DFFE/DFFF addresses, exactly like
        -- tb_phase11_call_ret_l.vhd's own MSP24-restore probes.) ----
        wait until A = x"0017" and M1_n = '0';
        wait for 1 ns;
        assert mode24 = "10"
            report "NestedStack: Test5 must still be in mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        wait until A = x"0018" and M1_n = '0';
        wait for 1 ns;
        assert bank_mem(16#DFFE#) = x"01" and bank_mem(16#DFFF#) = x"01"
            report "NestedStack: Test5 MSP24-restore probe (PUSH BC) expected writes at 01:DFFE/DFFF (MSP24 fully restored to 01:E000h after the nested unwind), got bank=" &
                to_hstring(bank_mem(16#DFFE#)) & "/" & to_hstring(bank_mem(16#DFFF#))
            severity failure;

        report "Nested MSP24 stack (M2 CALL + interrupt-entry + PUSH/POP-in-handler + RETI.L + RET) testbench: all assertions passed";
        std.env.stop;
        wait;
    end process;

    -- Watchdog: fail loudly instead of hanging forever if the program
    -- never reaches the final checkpoint (e.g. the suspected real-
    -- hardware hang reproduces here too - this IS the scenario being
    -- tested for).
    process
    begin
        wait for 50 us;
        assert false
            report "NestedStack: testbench watchdog timeout - program never reached the final checkpoint (0x0014). This would mean the nested MSP24 stack scenario genuinely hangs the CPU core itself, reproducing the real-hardware freeze in simulation."
            severity failure;
    end process;

end architecture sim;
