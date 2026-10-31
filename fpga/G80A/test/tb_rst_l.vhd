-- Historical pre-V16.1 fixture: old RST.L codes and M0/M1 degrade.
-- Replaced by run_v161_rst.ps1 -LongRST with independent physical banks.
--
-- RST.L self-checking testbench (next phase after Phase13, V10仕様書
-- section12 "RST.L"; roadmap Phase12 "M2 control... RST.L").
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as tb_phase11_call_ret_l.vhd and
-- earlier phase testbenches). A second parallel array (bank_mem) records
-- A_Bank at the moment of each write, same technique as tb_phase9/10/11,
-- so every M2 push-frame byte can be verified against the exact
-- (bank,address) pair it targeted.
--
-- Unlike CALL.L/RET.L (which always use MSP24 in every mode, only the
-- BANK byte's EFFECT on bank_pc differs by mode), RST.L fully degrades
-- to a plain Z80 RST in M0/M1 (different register - SP not MSP - and a
-- different byte count - 2 not 3), so this testbench covers BOTH the
-- M2 (true 24bit far call via MSP24/RST_B) and M0 (plain-RST-compatible
-- degrade via SP, RST_B ignored) paths explicitly.
--
-- To avoid any RST-vector/program collision in the flat (bank-unaware)
-- memory array, the program keeps 0x0000-0x00FF reserved exclusively
-- for RST vector targets (a cold-reset JP stub at 0x0000, plus the two
-- RST.L vectors actually exercised below: 0008h and 0020h) and places
-- all sequential "main flow" code at 0x0100+.
--
-- Program layout:
--   0x0000: JP 0100h (cold-reset stub, keeps 0x0000-0x00FF clear for
--     RST vector targets).
--   0x0008: RET (plain, 1byte) - RST.L 08H's M0-degrade target (plain
--     Z80 RST semantics: 16bit SP-based return, fixed 0008h jump).
--   0x0020: RST.L addr isn't used here directly; this is the M2 FAR
--     TARGET for RST.L 20H (bank09:0020h in the flat array - lives at
--     the SAME flat address 0x0020 as a plain-M0 RST 20H would, but
--     tagged bank=09h via A_Bank/bank_mem, and never visited in M0 by
--     this program) - just RET.L (2byte).
--   0x0100: SET_M2; LD HL,0E000h; LD A,01h; LD HL_B,A; LD24 MSP,HL
--     (MSP24 = 01:E000h, same setup convention as tb_phase10/11).
--   0x010B: LD A,09h; LD RST_B,A (RST_B=09h).
--   0x010F: RST.L 20H (ED E7, 2byte, at 0x010F-0x0110). M2 3byte PC24
--     return-frame push (bank00h/PC_H=01h/PC_L=11h, since the return
--     address right after this instruction is 0x0111) to MSP24,
--     decrementing 01:E000h -> 01:DFFD, then jumps to
--     PC24={RST_B=09h,00h,20h} = 09:0020h.
--     Test1: lands on A=0x0020 with bank_pc=09h, mode24=M2; push frame
--     at 01:DFFF(BANK=00h)/01:DFFE(HIGH=01h)/01:DFFD(LOW=11h) verified.
--   0x0020 (bank09h): RET.L - pops the frame back, restoring MSP24 to
--     01:E000h, returning to 00:0111h with bank_pc=00h.
--     Test2: lands on A=0x0111 with bank_pc=00h, mode24=M2.
--   0x0111: PUSH BC (plain, M2 MSP24 2byte transfer) - probes MSP24 by
--     writing to 01:DFFF/DFFE, confirming RET.L truly restored MSP24 to
--     01:E000h (sampled at the next fetch, 0x0112, after the PUSH BC
--     has completed - same technique as tb_phase11_call_ret_l.vhd).
--   0x0112: JP.L 0C:0130h (unconditional, still M2) - sets bank_pc=0Ch
--     as a recognizable precondition for the M0-degrade test below
--     (mirrors tb_phase11_call_ret_l.vhd's own JP.L-then-SET_M0
--     precondition technique).
--   0x0130: SET_M0 (bank_pc_r stays 0Ch, preserved - SET_M0 never
--     touches bank_pc_r, only SET_M2's M0/M1->M2 transition resets it).
--     Test3: lands on A=0x0130 with bank_pc=0Ch, mode24=M2 (sampled
--     right before SET_M0 executes, confirming the JP.L precondition).
--   0x0132: LD A,0AAh; LD RST_B,A (RST_B=AAh - deliberately DIFFERENT
--     from bank_pc_r=0Ch, so a broken/unguarded M0 RST.L that wrongly
--     consulted RST_B would be unambiguously caught).
--   0x0136: LD SP,7FFFh (explicit SP, avoids relying on the reset
--     default so the push target is unambiguous).
--   0x0139: RST.L 08H (ED CF, 2byte, at 0x0139-0x013A), now executing
--     in M0 (not M2). Per CPU仕様書V10 section12 ("M0/M1では対応する
--     通常Z80 RSTとしてSP16へ16bit return PCをpush...RST_Bは参照し
--     ない"): pushes the 16bit return address (0x013B) to the PLAIN
--     SP (not MSP24, 2 bytes not 3), jumps to the FIXED 0008h vector,
--     and RST_B is NOT consulted at all. Like plain RST/JP.L/JR.L (the
--     "16bit immediate target" family per CPU仕様書V8 section5 - as
--     opposed to CALL.L/RET.L's "same 64KB segment, PC_B不変"
--     preserving behaviour), RST.L's M0/M1 degrade also RESETS
--     bank_pc_r to 00h (mirrors RstP's own commit, reused unchanged for
--     this path - see t80.vhd).
--     Test4: lands on A=0x0008 with bank_pc RESET to 00h (neither the
--     0Ch precondition NOR the poisoned RST_B=AAh), mode24=M0(00);
--     SP-pushed frame (HIGH=01h at 7FFEh, LOW=3Bh at 7FFDh) verified.
--   0x0008: RET (plain) - pops the plain 16bit SP frame, returning to
--     0x013B.
--     Test5: lands on A=0x013B with bank_pc still 00h, mode24=M0(00).
--   0x013B: HALT - end of program.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_rst_l.vhd
--   ghdl -e --std=08 tb_rst_l
--   ghdl -r --std=08 tb_rst_l
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_rst_l is
end entity tb_rst_l;

architecture sim of tb_rst_l is

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
        16#0000# => x"C3", 16#0001# => x"00", 16#0002# => x"01",
        16#0008# => x"C9",
        16#0020# => x"ED", 16#0021# => x"C9",
        16#0100# => x"ED", 16#0101# => x"92",
        16#0102# => x"21", 16#0103# => x"00", 16#0104# => x"E0",
        16#0105# => x"3E", 16#0106# => x"01",
        16#0107# => x"ED", 16#0108# => x"24",
        16#0109# => x"ED", 16#010A# => x"35",
        16#010B# => x"3E", 16#010C# => x"09",
        16#010D# => x"ED", 16#010E# => x"3A",
        16#010F# => x"ED", 16#0110# => x"E7",
        16#0111# => x"C5",
        16#0112# => x"ED", 16#0113# => x"C3", 16#0114# => x"30", 16#0115# => x"01", 16#0116# => x"0C",
        16#0130# => x"ED", 16#0131# => x"90",
        16#0132# => x"3E", 16#0133# => x"AA",
        16#0134# => x"ED", 16#0135# => x"3A",
        16#0136# => x"31", 16#0137# => x"FF", 16#0138# => x"7F",
        16#0139# => x"ED", 16#013A# => x"CF",
        16#013B# => x"76",
        others => x"00");

    -- Records A_Bank at the moment of each write, same technique as
    -- tb_phase9/10/11 - lets every M2 push-frame byte be verified
    -- against the exact (bank,address) pair it targeted.
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
        -- testbench-side delta-cycle race avoidance as
        -- tb_phase10/11_*.vhd.

        -- ---- Test1: RST.L 20H (ED E7) in M2 lands on bank09:0020h,
        -- with the correct 3byte PC24 return-frame push to MSP24. ----
        wait until A = x"0020" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"09"
            report "RST.L: Test1 RST.L 20H must land with bank_pc=09h (=RST_B), got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "RST.L: Test1 RST.L 20H must not disturb mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#DFFF#) = x"00" and bank_mem(16#DFFF#) = x"01"
            report "RST.L: Test1 return-frame BANK byte mismatch at 01:DFFF, got data=" &
                to_hstring(mem(16#DFFF#)) & " bank=" & to_hstring(bank_mem(16#DFFF#))
            severity failure;
        assert mem(16#DFFE#) = x"01" and bank_mem(16#DFFE#) = x"01"
            report "RST.L: Test1 return-frame HIGH byte mismatch at 01:DFFE, got data=" &
                to_hstring(mem(16#DFFE#)) & " bank=" & to_hstring(bank_mem(16#DFFE#))
            severity failure;
        assert mem(16#DFFD#) = x"11" and bank_mem(16#DFFD#) = x"01"
            report "RST.L: Test1 return-frame LOW byte mismatch at 01:DFFD, got data=" &
                to_hstring(mem(16#DFFD#)) & " bank=" & to_hstring(bank_mem(16#DFFD#))
            severity failure;

        -- ---- Test2: RET.L (at bank09:0020h) pops the frame back and
        -- returns to A=0x0111 with bank_pc=00h. ----
        wait until A = x"0111" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "RST.L: Test2 RET.L must restore bank_pc=00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "RST.L: Test2 must still be in M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Probe: PUSH BC (plain) must land at 01:DFFF/DFFE,
        -- confirming RET.L truly restored MSP24 to 01:E000h. Sampled at
        -- the next fetch (JP.L at 0x0112) so the PUSH BC has already
        -- completed. ----
        wait until A = x"0112" and M1_n = '0';
        wait for 1 ns;
        assert bank_mem(16#DFFF#) = x"01" and bank_mem(16#DFFE#) = x"01"
            report "RST.L: MSP24 probe after Test2 expected writes at 01:DFFF/DFFE (MSP24 restored to 01:E000h), got bank=" &
                to_hstring(bank_mem(16#DFFF#)) & "/" & to_hstring(bank_mem(16#DFFE#))
            severity failure;

        -- ---- Test3: JP.L 0C:0130h precondition lands with bank_pc=0Ch,
        -- still in M2 (right before SET_M0). ----
        wait until A = x"0130" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"0C"
            report "RST.L: Test3 JP.L precondition must land with bank_pc=0Ch, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "RST.L: Test3 must still be in M2(10) before SET_M0, got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test4: RST.L 08H (ED CF) executed OUTSIDE M2 (M0, set up
        -- via JP.L 0C:0130h + SET_M0) must fully degrade to a plain Z80
        -- RST: 16bit SP push (not MSP24), fixed jump to 0008h, and
        -- bank_pc must RESET to 00h (same "16bit immediate target"
        -- family as plain RST/JP.L/JR.L, unlike CALL.L/RET.L's
        -- preserving behaviour) - the deliberately poisoned RST_B=AAh
        -- must have NO effect (bank_pc must be neither the 0Ch
        -- precondition NOR AAh). ----
        wait until A = x"0008" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "RST.L: Test4 RST.L 08H outside M2 must reset bank_pc to 00h (not consult RST_B/preserve the 0Ch precondition), got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "00"
            report "RST.L: Test4 must still be in M0(00), got " & to_hstring("00" & mode24)
            severity failure;
        assert mem(16#7FFE#) = x"01"
            report "RST.L: Test4 SP16 return-frame HIGH byte mismatch at 7FFEh, got " & to_hstring(mem(16#7FFE#))
            severity failure;
        assert mem(16#7FFD#) = x"3B"
            report "RST.L: Test4 SP16 return-frame LOW byte mismatch at 7FFDh, got " & to_hstring(mem(16#7FFD#))
            severity failure;

        -- ---- Test5: plain RET (at 0008h) pops the plain 16bit SP
        -- frame and returns to A=0x013B, bank_pc still 00h, mode24
        -- STILL M0(00). ----
        wait until A = x"013B" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "RST.L: Test5 plain RET must not disturb bank_pc, expected 00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "00"
            report "RST.L: Test5 must still be in M0(00), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- End of program: HALT at 0x013B. ----
        wait until HALT_n = '0';

        report "RST.L testbench: all assertions passed";
        std.env.stop;
        wait;
    end process;

    -- Watchdog: fail loudly instead of hanging forever if the program
    -- never reaches HALT (e.g. a jump went somewhere unintended).
    process
    begin
        wait for 50 us;
        assert false
            report "RST.L: testbench watchdog timeout - program never reached HALT"
            severity failure;
    end process;

end architecture sim;
