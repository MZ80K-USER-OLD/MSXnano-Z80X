--
-- Phase5 self-checking testbench: MMU real-mapping scenarios
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 7 "Phase 5")
--
-- NOTE: MMU24 is an OPTIONAL add-on, not instantiated by the default
-- top.v build (see mmu24.vhd's header comment and
-- MSX_T80_24bit化_CPU仕様書_V8 section 14.1). The default build instead
-- uses a straight-through logical->physical bank mapping, so the
-- F0h/F1h-driven remapping/aliasing scenarios below only apply when MMU24
-- has been re-enabled. This testbench still exercises the standalone
-- mmu24.vhd module (wired to the real T80 core) directly and remains
-- valid/passing regardless of whether top.v currently instantiates it.
--
-- Drives the real T80 CPU core together with the real MMU24 translation
-- table (both already unit/Phase-tested individually in tb_phase3_m1_data
-- and tb_phase4_mmu24) through the exact scenarios Phase5 describes:
--
--   - place a distinct pattern per physical bank (01->11h, 02->22h,
--     03->33h) and confirm the CPU sees the right value after mapping
--     each logical bank onto the matching physical bank via F0h/F1h
--   - alias test: remap logical bank 01h and 02h to the *same* physical
--     bank (05h) and confirm both now read the one shared pattern
--   - MMU_DATA[n]=00h alias test: confirm an explicit 00h mapping still
--     resolves to the plain MSX-compatible 64KB space (not some stray
--     extended-memory location)
--
-- This does not model memory_ctrl/SD-RAM itself (Verilog, no local
-- simulator available); it proves the CPU A_Bank -> MMU24 Logical_Bank ->
-- Physical_Bank chain that feeds fpga/top.v's cpu_sdram_* wiring is
-- correct. Confirming real SD-RAM content on Tang Nano hardware is the
-- literal "実機検証" part of Phase5 and is out of scope for GHDL.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd ../mmu24.vhd tb_phase5_mmu_mapping.vhd
--   ghdl -e --std=08 tb_phase5_mmu_mapping
--   ghdl -r --std=08 tb_phase5_mmu_mapping
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase5_mmu_mapping is
end entity tb_phase5_mmu_mapping;

architecture sim of tb_phase5_mmu_mapping is

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

    -- MMU24 bus
    signal mmu_d_out   : std_logic_vector(7 downto 0);
    signal mmu_d_outen : std_logic;
    signal physical_bank : std_logic_vector(7 downto 0);

    -- IORQ_n/RD_n/WR_n/M1_n (active-low) derived from T80's active-high
    -- IORQ/Write/M1_n(already active-low) outputs, matching how g80a.vhd
    -- derives the external bus from the same core signals.
    signal iorq_n_s : std_logic;
    signal rd_n_s   : std_logic;
    signal wr_n_s   : std_logic;

    type legacy_mem_t is array(0 to 65535) of std_logic_vector(7 downto 0);
    type ext_mem_t is array(0 to 8 * 65536 - 1) of std_logic_vector(7 downto 0);

    -- Legacy MSX-compatible 64KB space (physical bank 00h): program code,
    -- a scratch write area at 2000h-2006h, and a marker byte at 3000h used
    -- by the MMU[n]=00h alias scenario.
    signal legacy_mem : legacy_mem_t := (
        -- Program: see header comment for the full scenario story.
        16#0000# => x"3E", 16#0001# => x"01",             -- LD A,01h
        16#0002# => x"D3", 16#0003# => x"F0",             -- OUT (F0h),A   ; MMU_INDEX=01h
        16#0004# => x"D3", 16#0005# => x"F1",             -- OUT (F1h),A   ; MMU_DATA[01]=01h
        16#0006# => x"3E", 16#0007# => x"02",             -- LD A,02h
        16#0008# => x"D3", 16#0009# => x"F0",             -- OUT (F0h),A
        16#000A# => x"D3", 16#000B# => x"F1",             -- MMU_DATA[02]=02h
        16#000C# => x"3E", 16#000D# => x"03",             -- LD A,03h
        16#000E# => x"D3", 16#000F# => x"F0",             -- OUT (F0h),A
        16#0010# => x"D3", 16#0011# => x"F1",             -- MMU_DATA[03]=03h
        16#0012# => x"ED", 16#0013# => x"91",             -- SET_M1
        16#0014# => x"3E", 16#0015# => x"01",             -- LD A,01h
        16#0016# => x"ED", 16#0017# => x"24",             -- LD HL_B,A     ; bank_hl=01h
        16#0018# => x"21", 16#0019# => x"00", 16#001A# => x"00", -- LD HL,0000h
        16#001B# => x"7E",                                 -- LD A,(HL)     ; logical1->physical1, expect 11h
        16#001C# => x"32", 16#001D# => x"00", 16#001E# => x"20", -- LD (2000h),A
        16#001F# => x"3E", 16#0020# => x"02",             -- LD A,02h
        16#0021# => x"ED", 16#0022# => x"24",             -- LD HL_B,A     ; bank_hl=02h
        16#0023# => x"7E",                                 -- LD A,(HL)     ; logical2->physical2, expect 22h
        16#0024# => x"32", 16#0025# => x"01", 16#0026# => x"20", -- LD (2001h),A
        16#0027# => x"3E", 16#0028# => x"03",             -- LD A,03h
        16#0029# => x"ED", 16#002A# => x"24",             -- LD HL_B,A     ; bank_hl=03h
        16#002B# => x"7E",                                 -- LD A,(HL)     ; logical3->physical3, expect 33h
        16#002C# => x"32", 16#002D# => x"02", 16#002E# => x"20", -- LD (2002h),A
        -- Alias scenario: remap logical 01h/02h both onto physical 05h.
        16#002F# => x"3E", 16#0030# => x"01",             -- LD A,01h
        16#0031# => x"D3", 16#0032# => x"F0",             -- OUT (F0h),A   ; MMU_INDEX=01h
        16#0033# => x"3E", 16#0034# => x"05",             -- LD A,05h
        16#0035# => x"D3", 16#0036# => x"F1",             -- MMU_DATA[01]=05h
        16#0037# => x"3E", 16#0038# => x"02",             -- LD A,02h
        16#0039# => x"D3", 16#003A# => x"F0",             -- OUT (F0h),A   ; MMU_INDEX=02h
        16#003B# => x"3E", 16#003C# => x"05",             -- LD A,05h
        16#003D# => x"D3", 16#003E# => x"F1",             -- MMU_DATA[02]=05h
        16#003F# => x"3E", 16#0040# => x"01",             -- LD A,01h
        16#0041# => x"ED", 16#0042# => x"24",             -- LD HL_B,A     ; bank_hl=01h (-> physical 05h now)
        16#0043# => x"7E",                                 -- LD A,(HL)     ; expect 99h
        16#0044# => x"32", 16#0045# => x"03", 16#0046# => x"20", -- LD (2003h),A
        16#0047# => x"3E", 16#0048# => x"02",             -- LD A,02h
        16#0049# => x"ED", 16#004A# => x"24",             -- LD HL_B,A     ; bank_hl=02h (-> physical 05h now)
        16#004B# => x"7E",                                 -- LD A,(HL)     ; expect 99h
        16#004C# => x"32", 16#004D# => x"04", 16#004E# => x"20", -- LD (2004h),A
        -- MMU_DATA[04]=00h alias scenario: logical bank 04h explicitly
        -- mapped to physical 00h must still read the plain legacy space.
        16#004F# => x"3E", 16#0050# => x"04",             -- LD A,04h
        16#0051# => x"D3", 16#0052# => x"F0",             -- OUT (F0h),A   ; MMU_INDEX=04h
        16#0053# => x"3E", 16#0054# => x"00",             -- LD A,00h
        16#0055# => x"D3", 16#0056# => x"F1",             -- MMU_DATA[04]=00h (explicit)
        16#0057# => x"3E", 16#0058# => x"04",             -- LD A,04h
        16#0059# => x"ED", 16#005A# => x"24",             -- LD HL_B,A     ; bank_hl=04h (-> physical 00h, alias)
        16#005B# => x"21", 16#005C# => x"00", 16#005D# => x"30", -- LD HL,3000h
        16#005E# => x"7E",                                 -- LD A,(HL)     ; expect legacy_mem[3000h] = 55h
        16#005F# => x"32", 16#0060# => x"05", 16#0061# => x"20", -- LD (2005h),A
        16#0062# => x"76",                                 -- HALT

        16#3000# => x"55",  -- legacy marker read back through the MMU[04]=00h alias
        others => x"00");

    -- Extended flat memory (physical banks 00h-07h; bank 00h slot unused
    -- since physical bank 00h always routes to legacy_mem instead).
    signal ext_mem : ext_mem_t := (
        1 * 65536 + 0 => x"11",   -- physical bank 01h, offset 0000h
        2 * 65536 + 0 => x"22",   -- physical bank 02h, offset 0000h
        3 * 65536 + 0 => x"33",   -- physical bank 03h, offset 0000h
        5 * 65536 + 0 => x"99",   -- physical bank 05h, offset 0000h (alias target)
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

    mmu : entity work.MMU24
        port map(
            RESET_n => RESET_n,
            CLK => CLK_n,
            IORQ_n => iorq_n_s,
            M1_n => M1_n,
            RD_n => rd_n_s,
            WR_n => wr_n_s,
            Port_Addr => A(7 downto 0),
            D_In => DO,
            D_Out => mmu_d_out,
            D_OutEn => mmu_d_outen,
            Logical_Bank => A_Bank,
            Physical_Bank => physical_bank);

    -- Derive the external-style active-low strobes this testbench needs
    -- (mirrors how g80a.vhd builds MREQ_n/IORQ_n/RD_n/WR_n from the same
    -- core signals; HALT_n/BUSAK_n/RESET_n gating omitted for brevity
    -- since this testbench never halts mid-access or requests the bus).
    iorq_n_s <= not IORQ;
    rd_n_s   <= '0' when NoRead = '0' and Write = '0' else '1';
    wr_n_s   <= '0' when Write = '1' else '1';

    -- Flat read-side memory model: I/O reads come from MMU24, memory
    -- reads come from legacy_mem (physical bank 00h) or ext_mem (banks
    -- 01h-07h) depending on the MMU-translated Physical_Bank.
    DI_live <= mmu_d_out when IORQ = '1' and mmu_d_outen = '1' else
               legacy_mem(to_integer(unsigned(A))) when IORQ = '0' and physical_bank = x"00" else
               ext_mem(to_integer(unsigned(physical_bank)) * 65536 + to_integer(unsigned(A))) when IORQ = '0' else
               x"FF";
    DInst <= legacy_mem(to_integer(unsigned(A)));

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
        end if;
    end process;

    -- Memory write-back for the scratch "LD (nnnn),A" instructions.
    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if IORQ = '0' and Write = '1' and physical_bank = x"00" then
                legacy_mem(to_integer(unsigned(A))) <= DO;
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
        wait until HALT_n = '0';
        wait for 200 ns;

        assert legacy_mem(16#2000#) = x"11"
            report "Phase5: logical bank 01h->physical 01h must read 11h, got " & to_hstring(legacy_mem(16#2000#))
            severity failure;
        assert legacy_mem(16#2001#) = x"22"
            report "Phase5: logical bank 02h->physical 02h must read 22h, got " & to_hstring(legacy_mem(16#2001#))
            severity failure;
        assert legacy_mem(16#2002#) = x"33"
            report "Phase5: logical bank 03h->physical 03h must read 33h, got " & to_hstring(legacy_mem(16#2002#))
            severity failure;
        assert legacy_mem(16#2003#) = x"99"
            report "Phase5: alias - logical bank 01h remapped to physical 05h must read 99h, got " & to_hstring(legacy_mem(16#2003#))
            severity failure;
        assert legacy_mem(16#2004#) = x"99"
            report "Phase5: alias - logical bank 02h remapped to physical 05h must read 99h, got " & to_hstring(legacy_mem(16#2004#))
            severity failure;
        assert legacy_mem(16#2005#) = x"55"
            report "Phase5: MMU_DATA[04h]=00h must alias the legacy 64KB space, got " & to_hstring(legacy_mem(16#2005#))
            severity failure;

        report "Phase5 MMU mapping testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
