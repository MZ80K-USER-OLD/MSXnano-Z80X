--
-- Phase10 self-checking testbench: M2 basic operation (PC24 instruction
-- fetch, SET_M2 PC_B reset-only-from-M0/M1, MSP24 as the M2 active stack
-- pointer for plain PUSH qq/POP qq)
-- (doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 12 "Phase 10";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md, sections 2 "MODE" and
--  9 "Stack")
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small hand
-- assembled program (generated with a small Python helper to keep byte
-- offsets correct; see header comment for the full story) through a flat
-- 64KB combinational memory model (no MMU/banking - same limitation as
-- all previous phase testbenches; a second parallel array records
-- A_Bank/bank_pc/bank_msp at the moment of each write/fetch so the
-- bank-aware behaviour can still be verified).
--
-- Program layout (see gen_phase10.py for the generator):
--   0x0000: ED92 (SET_M2) - executed TWICE across the test's lifetime:
--     1st time (reset, M0->M2): Test1 - bank_pc must become 00h.
--     2nd time (after the 0xFFFF->0x0000 PC wrap below, already in M2
--     with bank_pc=01h from the crossing): Test3 - bank_pc must STAY 01h
--     ("M2->M2ではPC_B保持").
--   0x0002: Test4 - MSP24 active stack pointer for plain PUSH BC / POP DE
--     (2 bytes only, bank_msp_r provides the physical bank; the real Z80
--     SP register, read via the standard "LD HL,0;ADD HL,SP" trick, is
--     dumped before and after to confirm it is completely untouched).
--   0xFFF4-0xFFFF: 12 NOPs. After the 12th NOP's fetch+auto-increment, PC
--     wraps 0xFFFF->0x0000 and bank_pc must carry 00h->01h (Test2). The
--     very next fetch (address 0x0000) re-executes the SAME SET_M2 bytes
--     as a redundant M2->M2 call (Test3, see above).
--
-- NOT covered by this testbench (deferred per the project's Phase10/11/13
-- scope split - see AVAILABLE_INSTRUCTIONS.md): JR/DJNZ/JP/CALL/RET/RST
-- target-address bank-byte handling beyond the already-existing "16bit
-- immediate target = bank00h" rule (JP/CALL/RST/JumpXY targets already
-- reset bank_pc_r to 0 here, matching that rule, but none of their OWN
-- PC-modifying arithmetic has been made 24bit-aware - that is Phase11's
-- "M2制御フロー" scope, including the new JP.L/CALL.L/RET.L opcodes), and
-- M2 interrupt vectoring via IBR with its 4-byte MSP frame is outside this
-- Phase10 testbench; see tb_v161_interrupt.vhd for current coverage.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase10_m2_basic.vhd
--   ghdl -e --std=08 tb_phase10_m2_basic
--   ghdl -r --std=08 tb_phase10_m2_basic
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase10_m2_basic is
end entity tb_phase10_m2_basic;

architecture sim of tb_phase10_m2_basic is

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

    -- Hand assembled test program (generated with a small Python helper;
    -- see header comment). Only the populated low block and the
    -- near-boundary NOP run are listed explicitly; everything else
    -- defaults to x"00" (NOP), which is never actually fetched by this
    -- program.
    signal mem : mem_array := (
        16#0000# => x"ED", 16#0001# => x"92", 16#0002# => x"21", 16#0003# => x"00",
        16#0004# => x"00", 16#0005# => x"39", 16#0006# => x"22", 16#0007# => x"35",
        16#0008# => x"00", 16#0009# => x"21", 16#000A# => x"00", 16#000B# => x"E0",
        16#000C# => x"3E", 16#000D# => x"01", 16#000E# => x"ED", 16#000F# => x"24",
        16#0010# => x"ED", 16#0011# => x"35", 16#0012# => x"01", 16#0013# => x"34",
        16#0014# => x"12", 16#0015# => x"C5", 16#0016# => x"11", 16#0017# => x"00",
        16#0018# => x"00", 16#0019# => x"D1", 16#001A# => x"ED", 16#001B# => x"53",
        16#001C# => x"37", 16#001D# => x"00", 16#001E# => x"21", 16#001F# => x"00",
        16#0020# => x"00", 16#0021# => x"ED", 16#0022# => x"36", 16#0023# => x"22",
        16#0024# => x"39", 16#0025# => x"00", 16#0026# => x"ED", 16#0027# => x"2C",
        16#0028# => x"32", 16#0029# => x"3B", 16#002A# => x"00", 16#002B# => x"21",
        16#002C# => x"00", 16#002D# => x"00", 16#002E# => x"39", 16#002F# => x"22",
        16#0030# => x"3C", 16#0031# => x"00", 16#0032# => x"C3", 16#0033# => x"F4",
        16#0034# => x"FF",
        16#FFF4# => x"00", 16#FFF5# => x"00", 16#FFF6# => x"00", 16#FFF7# => x"00",
        16#FFF8# => x"00", 16#FFF9# => x"00", 16#FFFA# => x"00", 16#FFFB# => x"00",
        16#FFFC# => x"00", 16#FFFD# => x"00", 16#FFFE# => x"00", 16#FFFF# => x"00",
        others => x"00");

    -- Records A_Bank at the moment of each write, same 16bit indexing as
    -- 'mem' above - lets the PUSH BC write be verified against the exact
    -- (bank,address) pair it targeted (same technique as tb_phase9).
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
            -- Memory write-back for PUSH BC's 2 bytes and the
            -- "LD (nnnn),HL/DE/A" instructions used to dump SP/MSP24/DE
            -- for verification. bank_mem records A_Bank alongside the
            -- data byte so PUSH BC's writes can be verified against the
            -- exact (bank,address) pair they targeted.
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
        -- ---- Test1: SET_M2 (M0->M2, the very first instruction at
        -- reset) must reset bank_pc to 00h. Sampled at the next opcode
        -- fetch (address 0x0002, "LD HL,0000h"). A small settle wait
        -- after each "wait until A=...,M1_n=..." condition lets mode24/
        -- bank_pc (continuous assignments derived from internal
        -- registers, one delta cycle behind A/M1_n's own process) finish
        -- propagating before being sampled - otherwise this testbench
        -- process can race ahead of them within the same simulation time
        -- step (a testbench-side delta-cycle race, not an RTL bug).
        wait until A = x"0002" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"00"
            report "Phase10: Test1 SET_M2 (M0->M2) must reset bank_pc to 00h, got " & to_hstring(bank_pc)
            severity failure;
        assert mode24 = "10"
            report "Phase10: Test1 SET_M2 must set mode24=M2(10), got " & to_hstring("00" & mode24)
            severity failure;

        -- ---- Test4: MSP24 active stack pointer for plain PUSH BC / POP
        -- DE in M2 (2 bytes only). Sampled at the JP instruction's own
        -- fetch (address 0x0032), by which point the whole push+pop
        -- round trip and all memory dumps have completed. ----
        wait until A = x"0032" and M1_n = '0';
        wait for 1 ns;

        -- PUSH BC (BC=1234h) must write HIGH byte first at MSP24-1 =
        -- 01:DFFF, then LOW byte at MSP24-2 (final) = 01:DFFE - exactly
        -- like a plain Z80 PUSH qq, just tagged with bank_msp_r=01h
        -- instead of bank00h.
        assert mem(16#DFFF#) = x"12" and bank_mem(16#DFFF#) = x"01"
            report "Phase10: M2 PUSH BC HIGH-byte write mismatch, got data=" & to_hstring(mem(16#DFFF#)) &
                " bank=" & to_hstring(bank_mem(16#DFFF#)) & ", expected data=12h bank=01h"
            severity failure;
        assert mem(16#DFFE#) = x"34" and bank_mem(16#DFFE#) = x"01"
            report "Phase10: M2 PUSH BC LOW-byte write mismatch, got data=" & to_hstring(mem(16#DFFE#)) &
                " bank=" & to_hstring(bank_mem(16#DFFE#)) & ", expected data=34h bank=01h"
            severity failure;

        -- POP DE must reconstruct the exact same 1234h that PUSH BC wrote.
        assert mem(16#0037#) = x"34" and mem(16#0038#) = x"12"
            report "Phase10: M2 POP DE must reconstruct 1234h, got lo=" & to_hstring(mem(16#0037#)) &
                " hi=" & to_hstring(mem(16#0038#))
            severity failure;

        -- MSP24 must be back to its original 01:E000h after the matching
        -- push+pop pair (only 2 bytes moved per op, unlike PUSH24/POP24's
        -- 3 - MSP24's bank_msp_r itself is NOT transferred as data here).
        assert mem(16#0039#) = x"00" and mem(16#003A#) = x"E0" and mem(16#003B#) = x"01"
            report "Phase10: M2 PUSH BC/POP DE must restore MSP24=01:E000h, got lo=" & to_hstring(mem(16#0039#)) &
                " hi=" & to_hstring(mem(16#003A#)) & " bank=" & to_hstring(mem(16#003B#))
            severity failure;

        -- The REAL Z80 SP register must be completely untouched by the
        -- M2 PUSH BC/POP DE pair (M2's active stack is MSP24, not SP).
        assert mem(16#0035#) = mem(16#003C#) and mem(16#0036#) = mem(16#003D#)
            report "Phase10: M2 PUSH BC/POP DE must not touch the real Z80 SP register, SP_before=" &
                to_hstring(mem(16#0036#)) & to_hstring(mem(16#0035#)) & " SP_after=" &
                to_hstring(mem(16#003D#)) & to_hstring(mem(16#003C#))
            severity failure;

        -- ---- Test2: PC24 sequential fetch must carry bank_pc 00h->01h
        -- when PC wraps 0xFFFF->0x0000 during ordinary execution in M2.
        -- Confirmed by waiting for the fetch at 0xFFFF (the last of the
        -- 12 NOPs), then the very next opcode fetch (the wrapped address
        -- 0x0000). ----
        wait until A = x"FFFF" and M1_n = '0';
        wait until M1_n = '1';
        wait until M1_n = '0';
        wait for 1 ns;
        assert A = x"0000"
            report "Phase10: Test2 expected the next fetch after 0xFFFF to wrap to 0x0000, got " & to_hstring(A)
            severity failure;
        assert bank_pc = x"01"
            report "Phase10: Test2 PC24 wrap must carry bank_pc 00h->01h, got " & to_hstring(bank_pc)
            severity failure;

        -- ---- Test3: the redundant SET_M2 re-executed here (same ED92
        -- bytes as Test1, now reached via the wrap instead of reset)
        -- must PRESERVE bank_pc (M2->M2), not reset it. Sampled at the
        -- next opcode fetch (address 0x0002 again). ----
        wait until A = x"0002" and M1_n = '0';
        wait for 1 ns;
        assert bank_pc = x"01"
            report "Phase10: Test3 redundant SET_M2 (M2->M2) must preserve bank_pc=01h, got " & to_hstring(bank_pc)
            severity failure;

        report "Phase10 M2 basic operation testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
