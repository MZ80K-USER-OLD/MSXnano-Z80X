--
-- Phase8 self-checking testbench: dedicated 24bit ALU instructions
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 10 "Phase 8";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md, section 6 "24bit ALU")
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small hand
-- assembled program (generated with a small Python helper to keep byte
-- offsets and expected flag values correct/independently verified - the
-- helper mirrors fpga/G80A/t80_pack.vhd's Alu24_AddSub bit-for-bit) through
-- a flat 64KB combinational memory model (M0, no MMU/banking involved) to
-- verify every opcode implemented in this increment:
--
--   ED23 INC24 HL             ED2B DEC24 HL
--   ED09 ADD24 HL,BC          ED29 ADD24 HL,HL
--   ED17 ADC24 HL,DE          ED0F SBC24 HL,BC
--   ED39 ADD24 HL,SP (SP operand = MSP24, not the plain 16bit SP)
--   ED3D CP24 HL,DE (no writeback)
--
-- Each test case verifies:
--   - the 24bit result (16bit low word + 8bit bank byte) via HL24, written
--     back for every opcode except CP24
--   - CP24 leaves HL24 completely unchanged (compare-only, no writeback)
--   - S/Z/N/P(overflow)/C flags exactly match an independent two's-
--     complement/carry-chain reference computation (see the Python helper)
--   - H (half-carry) is preserved (left untouched) across the op, per
--     CPU仕様書V8 section 6 "H保持" - verified by forcing H=1 via CPL
--     immediately before each op (CPL does not touch the C flag) and then
--     checking H is still 1 afterward
--   - ADC24/SBC24 correctly consume the existing carry flag as their
--     carry-in/borrow-in (set up via SCF;CPL = C=1,H=1 beforehand)
--
-- NOT covered by this testbench (deferred, same scope limitation as
-- Phase7's LD24 HL,IX/IY - see AVAILABLE_INSTRUCTIONS.md): DD/FD IX/IY
-- target replacement for any of these opcodes.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase8_alu24.vhd
--   ghdl -e --std=08 tb_phase8_alu24
--   ghdl -r --std=08 tb_phase8_alu24
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase8_alu24 is
end entity tb_phase8_alu24;

architecture sim of tb_phase8_alu24 is

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

    -- S,Z,H,P/V,N,C only (bits 7,6,4,2,1,0); X/Y (bits 3,5, undocumented)
    -- are intentionally excluded from the flag comparisons below: CPU仕様書
    -- V8 section 6 does not define X/Y for this 24bit ALU group, so this
    -- testbench's design choice (see t80.vhd's Phase8 commit block) is to
    -- leave them untouched/preserved rather than require a specific value.
    constant F_FLAG_MASK : std_logic_vector(7 downto 0) := "11010111";

    type mem_array is array(0 to 65535) of std_logic_vector(7 downto 0);

    -- Hand assembled test program (generated with a small Python helper to
    -- keep byte offsets and expected results/flags correct; see header
    -- comment for the full story).
    -- Program length: 266 (0x010A) bytes, starting at 0000h.
    signal mem : mem_array := (
        16#0000# => x"31", 16#0001# => x"00", 16#0002# => x"E0",
        16#0003# => x"21", 16#0004# => x"FF", 16#0005# => x"FF", 16#0006# => x"3E", 16#0007# => x"FF",
        16#0008# => x"ED", 16#0009# => x"24", 16#000A# => x"2F", 16#000B# => x"ED",
        16#000C# => x"23", 16#000D# => x"22", 16#000E# => x"00", 16#000F# => x"30",
        16#0010# => x"ED", 16#0011# => x"2C", 16#0012# => x"32", 16#0013# => x"02",
        16#0014# => x"30", 16#0015# => x"F5", 16#0016# => x"C1", 16#0017# => x"79",
        16#0018# => x"32", 16#0019# => x"03", 16#001A# => x"30", 16#001B# => x"21",
        16#001C# => x"00", 16#001D# => x"00", 16#001E# => x"3E", 16#001F# => x"00",
        16#0020# => x"ED", 16#0021# => x"24", 16#0022# => x"2F", 16#0023# => x"ED",
        16#0024# => x"2B", 16#0025# => x"22", 16#0026# => x"04", 16#0027# => x"30",
        16#0028# => x"ED", 16#0029# => x"2C", 16#002A# => x"32", 16#002B# => x"06",
        16#002C# => x"30", 16#002D# => x"F5", 16#002E# => x"C1", 16#002F# => x"79",
        16#0030# => x"32", 16#0031# => x"07", 16#0032# => x"30", 16#0033# => x"21",
        16#0034# => x"00", 16#0035# => x"00", 16#0036# => x"3E", 16#0037# => x"01",
        16#0038# => x"ED", 16#0039# => x"24", 16#003A# => x"01", 16#003B# => x"FF",
        16#003C# => x"FF", 16#003D# => x"3E", 16#003E# => x"00", 16#003F# => x"ED",
        16#0040# => x"04", 16#0041# => x"2F", 16#0042# => x"ED", 16#0043# => x"09",
        16#0044# => x"22", 16#0045# => x"08", 16#0046# => x"30", 16#0047# => x"ED",
        16#0048# => x"2C", 16#0049# => x"32", 16#004A# => x"0A", 16#004B# => x"30",
        16#004C# => x"F5", 16#004D# => x"C1", 16#004E# => x"79", 16#004F# => x"32",
        16#0050# => x"0B", 16#0051# => x"30", 16#0052# => x"21", 16#0053# => x"00",
        16#0054# => x"00", 16#0055# => x"3E", 16#0056# => x"40", 16#0057# => x"ED",
        16#0058# => x"24", 16#0059# => x"2F", 16#005A# => x"ED", 16#005B# => x"29",
        16#005C# => x"22", 16#005D# => x"0C", 16#005E# => x"30", 16#005F# => x"ED",
        16#0060# => x"2C", 16#0061# => x"32", 16#0062# => x"0E", 16#0063# => x"30",
        16#0064# => x"F5", 16#0065# => x"C1", 16#0066# => x"79", 16#0067# => x"32",
        16#0068# => x"0F", 16#0069# => x"30", 16#006A# => x"21", 16#006B# => x"FF",
        16#006C# => x"FF", 16#006D# => x"3E", 16#006E# => x"7F", 16#006F# => x"ED",
        16#0070# => x"24", 16#0071# => x"11", 16#0072# => x"00", 16#0073# => x"00",
        16#0074# => x"3E", 16#0075# => x"00", 16#0076# => x"ED", 16#0077# => x"14",
        16#0078# => x"37", 16#0079# => x"2F", 16#007A# => x"ED", 16#007B# => x"17",
        16#007C# => x"22", 16#007D# => x"10", 16#007E# => x"30", 16#007F# => x"ED",
        16#0080# => x"2C", 16#0081# => x"32", 16#0082# => x"12", 16#0083# => x"30",
        16#0084# => x"F5", 16#0085# => x"C1", 16#0086# => x"79", 16#0087# => x"32",
        16#0088# => x"13", 16#0089# => x"30", 16#008A# => x"21", 16#008B# => x"00",
        16#008C# => x"00", 16#008D# => x"3E", 16#008E# => x"80", 16#008F# => x"ED",
        16#0090# => x"24", 16#0091# => x"01", 16#0092# => x"00", 16#0093# => x"00",
        16#0094# => x"3E", 16#0095# => x"00", 16#0096# => x"ED", 16#0097# => x"04",
        16#0098# => x"37", 16#0099# => x"2F", 16#009A# => x"ED", 16#009B# => x"0F",
        16#009C# => x"22", 16#009D# => x"14", 16#009E# => x"30", 16#009F# => x"ED",
        16#00A0# => x"2C", 16#00A1# => x"32", 16#00A2# => x"16", 16#00A3# => x"30",
        16#00A4# => x"F5", 16#00A5# => x"C1", 16#00A6# => x"79", 16#00A7# => x"32",
        16#00A8# => x"17", 16#00A9# => x"30", 16#00AA# => x"21", 16#00AB# => x"00",
        16#00AC# => x"20", 16#00AD# => x"3E", 16#00AE# => x"00", 16#00AF# => x"ED",
        16#00B0# => x"24", 16#00B1# => x"ED", 16#00B2# => x"35", 16#00B3# => x"21",
        16#00B4# => x"00", 16#00B5# => x"00", 16#00B6# => x"3E", 16#00B7# => x"30",
        16#00B8# => x"ED", 16#00B9# => x"24", 16#00BA# => x"2F", 16#00BB# => x"ED",
        16#00BC# => x"39", 16#00BD# => x"22", 16#00BE# => x"18", 16#00BF# => x"30",
        16#00C0# => x"ED", 16#00C1# => x"2C", 16#00C2# => x"32", 16#00C3# => x"1A",
        16#00C4# => x"30", 16#00C5# => x"F5", 16#00C6# => x"C1", 16#00C7# => x"79",
        16#00C8# => x"32", 16#00C9# => x"1B", 16#00CA# => x"30", 16#00CB# => x"21",
        16#00CC# => x"56", 16#00CD# => x"34", 16#00CE# => x"3E", 16#00CF# => x"12",
        16#00D0# => x"ED", 16#00D1# => x"24", 16#00D2# => x"11", 16#00D3# => x"56",
        16#00D4# => x"34", 16#00D5# => x"3E", 16#00D6# => x"12", 16#00D7# => x"ED",
        16#00D8# => x"14", 16#00D9# => x"2F", 16#00DA# => x"ED", 16#00DB# => x"3D",
        16#00DC# => x"22", 16#00DD# => x"1C", 16#00DE# => x"30", 16#00DF# => x"ED",
        16#00E0# => x"2C", 16#00E1# => x"32", 16#00E2# => x"1E", 16#00E3# => x"30",
        16#00E4# => x"F5", 16#00E5# => x"C1", 16#00E6# => x"79", 16#00E7# => x"32",
        16#00E8# => x"1F", 16#00E9# => x"30", 16#00EA# => x"21", 16#00EB# => x"00",
        16#00EC# => x"00", 16#00ED# => x"3E", 16#00EE# => x"00", 16#00EF# => x"ED",
        16#00F0# => x"24", 16#00F1# => x"11", 16#00F2# => x"01", 16#00F3# => x"00",
        16#00F4# => x"3E", 16#00F5# => x"00", 16#00F6# => x"ED", 16#00F7# => x"14",
        16#00F8# => x"2F", 16#00F9# => x"ED", 16#00FA# => x"3D", 16#00FB# => x"22",
        16#00FC# => x"20", 16#00FD# => x"30", 16#00FE# => x"ED", 16#00FF# => x"2C",
        16#0100# => x"32", 16#0101# => x"22", 16#0102# => x"30", 16#0103# => x"F5",
        16#0104# => x"C1", 16#0105# => x"79", 16#0106# => x"32", 16#0107# => x"23",
        16#0108# => x"30", 16#0109# => x"76",
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

    -- Flat combinational memory model (M0, no MMU): see tb_phase3_m1_data.vhd
    -- for the detailed rationale behind the DI_live/DInst/DI split.
    DI_live <= mem(to_integer(unsigned(A)));
    DInst <= DI_live;

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
            -- Memory write-back for the "LD (nnnn),HL/A" instructions used
            -- to dump register/flag values for verification.
            if IORQ = '0' and Write = '1' then
                mem(to_integer(unsigned(A))) <= DO;
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
        wait for 200 ns; -- drain a few trailing HALT refetch cycles

        -- ---- T1: ED23 INC24 HL, 0xFFFFFF -> 0x000000 ----
        assert mem(16#3000#) = x"00" and mem(16#3001#) = x"00" and mem(16#3002#) = x"00"
            report "Phase8: INC24 HL result mismatch, expected 000000h" severity failure;
        assert (mem(16#3003#) and F_FLAG_MASK) = (x"51" and F_FLAG_MASK)
            report "Phase8: INC24 HL flags mismatch, expected F=51h (masked), got " & to_hstring(mem(16#3003#))
            severity failure;

        -- ---- T2: ED2B DEC24 HL, 0x000000 -> 0xFFFFFF ----
        assert mem(16#3004#) = x"FF" and mem(16#3005#) = x"FF" and mem(16#3006#) = x"FF"
            report "Phase8: DEC24 HL result mismatch, expected FFFFFFh" severity failure;
        assert (mem(16#3007#) and F_FLAG_MASK) = (x"93" and F_FLAG_MASK)
            report "Phase8: DEC24 HL flags mismatch, expected F=93h (masked), got " & to_hstring(mem(16#3007#))
            severity failure;

        -- ---- T3: ED09 ADD24 HL,BC  0x010000+0x00FFFF=0x01FFFF ----
        assert mem(16#3008#) = x"FF" and mem(16#3009#) = x"FF" and mem(16#300A#) = x"01"
            report "Phase8: ADD24 HL,BC result mismatch, expected 01FFFFh" severity failure;
        assert (mem(16#300B#) and F_FLAG_MASK) = (x"10" and F_FLAG_MASK)
            report "Phase8: ADD24 HL,BC flags mismatch, expected F=10h (masked), got " & to_hstring(mem(16#300B#))
            severity failure;

        -- ---- T4: ED29 ADD24 HL,HL  0x400000 doubled -> 0x800000 (signed overflow) ----
        assert mem(16#300C#) = x"00" and mem(16#300D#) = x"00" and mem(16#300E#) = x"80"
            report "Phase8: ADD24 HL,HL result mismatch, expected 800000h" severity failure;
        assert (mem(16#300F#) and F_FLAG_MASK) = (x"94" and F_FLAG_MASK)
            report "Phase8: ADD24 HL,HL flags mismatch, expected F=94h (masked), got " & to_hstring(mem(16#300F#))
            severity failure;

        -- ---- T5: ED17 ADC24 HL,DE, C=1 in: 0x7FFFFF+0x000000+1=0x800000 (signed overflow) ----
        assert mem(16#3010#) = x"00" and mem(16#3011#) = x"00" and mem(16#3012#) = x"80"
            report "Phase8: ADC24 HL,DE result mismatch, expected 800000h" severity failure;
        assert (mem(16#3013#) and F_FLAG_MASK) = (x"94" and F_FLAG_MASK)
            report "Phase8: ADC24 HL,DE flags mismatch, expected F=94h (masked), got " & to_hstring(mem(16#3013#))
            severity failure;

        -- ---- T6: ED0F SBC24 HL,BC, C=1 in: 0x800000-0x000000-1=0x7FFFFF (signed overflow) ----
        assert mem(16#3014#) = x"FF" and mem(16#3015#) = x"FF" and mem(16#3016#) = x"7F"
            report "Phase8: SBC24 HL,BC result mismatch, expected 7FFFFFh" severity failure;
        assert (mem(16#3017#) and F_FLAG_MASK) = (x"16" and F_FLAG_MASK)
            report "Phase8: SBC24 HL,BC flags mismatch, expected F=16h (masked), got " & to_hstring(mem(16#3017#))
            severity failure;

        -- ---- T7: ED39 ADD24 HL,SP (SP=MSP24=0x002000), 0x300000+0x002000=0x302000 ----
        assert mem(16#3018#) = x"00" and mem(16#3019#) = x"20" and mem(16#301A#) = x"30"
            report "Phase8: ADD24 HL,SP result mismatch, expected 302000h" severity failure;
        assert (mem(16#301B#) and F_FLAG_MASK) = (x"10" and F_FLAG_MASK)
            report "Phase8: ADD24 HL,SP flags mismatch, expected F=10h (masked), got " & to_hstring(mem(16#301B#))
            severity failure;

        -- ---- T8: ED3D CP24 HL,DE equal (0x123456 cmp 0x123456): Z=1, HL unchanged ----
        assert mem(16#301C#) = x"56" and mem(16#301D#) = x"34" and mem(16#301E#) = x"12"
            report "Phase8: CP24 HL,DE (eq) must leave HL24 unchanged (123456h)" severity failure;
        assert (mem(16#301F#) and F_FLAG_MASK) = (x"52" and F_FLAG_MASK)
            report "Phase8: CP24 HL,DE (eq) flags mismatch, expected F=52h (masked), got " & to_hstring(mem(16#301F#))
            severity failure;

        -- ---- T9: ED3D CP24 HL,DE borrow (0x000000 cmp 0x000001): C=1,S=1, HL unchanged ----
        assert mem(16#3020#) = x"00" and mem(16#3021#) = x"00" and mem(16#3022#) = x"00"
            report "Phase8: CP24 HL,DE (borrow) must leave HL24 unchanged (000000h)" severity failure;
        assert (mem(16#3023#) and F_FLAG_MASK) = (x"93" and F_FLAG_MASK)
            report "Phase8: CP24 HL,DE (borrow) flags mismatch, expected F=93h (masked), got " & to_hstring(mem(16#3023#))
            severity failure;

        report "Phase8 24bit ALU testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
