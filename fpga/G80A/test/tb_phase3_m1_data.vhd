--
-- Phase3 self-checking testbench: minimal M1 (24bit data address generation)
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 5 "Phase 3")
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small hand
-- assembled program through a flat 64KB combinational memory model to
-- verify that the new A_Bank output produces the correct 24bit logical
-- address (A_Bank & A) for register-indirect data accesses:
--
--   - (HL) while mode24 = M0  -> A_Bank must stay 00h even if HL_B <> 00h
--   - (HL) after SET_M1       -> A_Bank must follow HL_B
--   - (BC) / (DE) after M1    -> A_Bank must follow BC_B / DE_B
--   - (IX+d) after M1, crossing a 64KB bank boundary -> A_Bank must carry
--     via the Phase2 Addr24_AddDisp8 function (proves Phase2 is now wired
--     into real address generation, not just unit-tested in isolation)
--
-- PC-relative opcode fetches are expected to stay at A_Bank = 00h
-- throughout, since Phase3 keeps PC 16bit (M2 PC24 is a later phase).
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase3_m1_data.vhd
--   ghdl -e --std=08 tb_phase3_m1_data
--   ghdl -r --std=08 tb_phase3_m1_data
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase3_m1_data is
end entity tb_phase3_m1_data;

architecture sim of tb_phase3_m1_data is

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
    signal DI_live  : std_logic_vector(7 downto 0);   -- live combinational memory output (addr = A)
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

    -- Hand assembled test program, see header comment for the full story.
    signal mem : mem_array := (
        16#0000# => x"3E", 16#0001# => x"05",             -- LD A,05h
        16#0002# => x"ED", 16#0003# => x"24",             -- LD HL_B,A   (bank_hl=05h, still M0)
        16#0004# => x"21", 16#0005# => x"00", 16#0006# => x"80", -- LD HL,8000h
        16#0007# => x"7E",                                 -- LD A,(HL)   (M0: expect A_Bank=00h)
        16#0008# => x"ED", 16#0009# => x"91",             -- SET_M1
        16#000A# => x"7E",                                 -- LD A,(HL)   (M1: expect A_Bank=05h)
        16#000B# => x"3E", 16#000C# => x"07",             -- LD A,07h
        16#000D# => x"ED", 16#000E# => x"04",             -- LD BC_B,A   (bank_bc=07h)
        16#000F# => x"01", 16#0010# => x"00", 16#0011# => x"90", -- LD BC,9000h
        16#0012# => x"0A",                                 -- LD A,(BC)   (M1: expect A_Bank=07h)
        16#0013# => x"3E", 16#0014# => x"09",             -- LD A,09h
        16#0015# => x"ED", 16#0016# => x"14",             -- LD DE_B,A   (bank_de=09h)
        16#0017# => x"11", 16#0018# => x"00", 16#0019# => x"A0", -- LD DE,A000h
        16#001A# => x"1A",                                 -- LD A,(DE)   (M1: expect A_Bank=09h)
        16#001B# => x"3E", 16#001C# => x"01",             -- LD A,01h
        16#001D# => x"ED", 16#001E# => x"05",             -- LD IX_B,A   (bank_ix=01h)
        16#001F# => x"DD", 16#0020# => x"21", 16#0021# => x"F8", 16#0022# => x"FF", -- LD IX,FFF8h
        16#0023# => x"DD", 16#0024# => x"7E", 16#0025# => x"08", -- LD A,(IX+08h) (M1: carries to bank 02h/0000h)
        16#0026# => x"76",                                 -- HALT
        others => x"00");

    constant LOG_DEPTH : integer := 4096;
    type addr_log_t is array(0 to LOG_DEPTH - 1) of std_logic_vector(15 downto 0);
    type bank_log_t is array(0 to LOG_DEPTH - 1) of std_logic_vector(7 downto 0);
    signal log_addr  : addr_log_t := (others => (others => '0'));
    signal log_bank  : bank_log_t := (others => (others => '0'));
    signal log_count : integer := 0;

    impure function find_nth(target : std_logic_vector(15 downto 0); n : integer) return integer is
        variable cnt : integer := 0;
    begin
        for i in 0 to log_count - 1 loop
            if log_addr(i) = target then
                cnt := cnt + 1;
                if cnt = n then
                    return i;
                end if;
            end if;
        end loop;
        return -1;
    end function find_nth;

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

    -- Flat combinational memory model (no wait states): A always addresses
    -- the same 64KB array for both opcode fetch and data reads.
    --
    -- T80 (t80.vhd) expects two distinct external data paths, exactly like
    -- the reference T80s/G80a wrappers:
    --   - DInst: the *live* value at the current A, sampled into IR at
    --     TState=2 of an opcode fetch.
    --   - DI: a *held* value, captured once per M-cycle (here at TState=2,
    --     mirroring T80s.vhd) and kept stable even after A has already
    --     moved on to the next bus cycle's address. Operand/data write-back
    --     (e.g. ACC<=Save_Mux<=DI_Reg) happens later, at T_Res, by which
    --     time a purely combinational DI would already reflect the *next*
    --     address instead of the one that was actually read.
    -- Without this capture stage, every ED xx bank-register load instruction
    -- in this testbench would appear to load the *next* fetched opcode byte
    -- instead of the operand that was actually read from ACC.
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

    -- Clock generation
    CLK_n <= not CLK_n after 10 ns;

    process
    begin
        RESET_n <= '0';
        wait for 45 ns;
        RESET_n <= '1';
        wait;
    end process;

    -- Bus trace: log (A, A_Bank) every time the core latches a new address.
    process
    begin
        wait until rising_edge(CLK_n);
        wait for 1 ns;
        if update_addr = '1' and log_count < LOG_DEPTH then
            log_addr(log_count) <= A;
            log_bank(log_count) <= A_Bank;
            log_count <= log_count + 1;
        end if;
    end process;

    process
        variable idx : integer;
    begin
        wait until HALT_n = '0';
        wait for 200 ns; -- drain a few trailing HALT refetch cycles into the log

        idx := find_nth(x"8000", 1);
        assert idx >= 0 report "Phase3: (HL) M0 access to 8000h not found in trace" severity failure;
        assert log_bank(idx) = x"00"
            report "Phase3: (HL) M0 access must bypass bank (A_Bank=00h), got " & to_hstring(log_bank(idx)) severity failure;

        idx := find_nth(x"8000", 2);
        assert idx >= 0 report "Phase3: (HL) M1 access to 8000h not found in trace" severity failure;
        assert log_bank(idx) = x"05"
            report "Phase3: (HL) M1 access must use HL_B (05h), got " & to_hstring(log_bank(idx)) severity failure;

        idx := find_nth(x"9000", 1);
        assert idx >= 0 report "Phase3: (BC) access to 9000h not found in trace" severity failure;
        assert log_bank(idx) = x"07"
            report "Phase3: (BC) M1 access must use BC_B (07h), got " & to_hstring(log_bank(idx)) severity failure;

        idx := find_nth(x"A000", 1);
        assert idx >= 0 report "Phase3: (DE) access to A000h not found in trace" severity failure;
        assert log_bank(idx) = x"09"
            report "Phase3: (DE) M1 access must use DE_B (09h), got " & to_hstring(log_bank(idx)) severity failure;

        idx := find_nth(x"0000", 2);
        assert idx >= 0 report "Phase3: (IX+08h) bank-carry access to 0000h not found in trace" severity failure;
        assert log_bank(idx) = x"02"
            report "Phase3: (IX+08h) from IX_B=01h,IX=FFF8h must carry to bank 02h, got " & to_hstring(log_bank(idx)) severity failure;

        report "Phase3 minimal-M1 data-address testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
