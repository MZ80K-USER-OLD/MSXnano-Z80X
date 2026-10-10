--
-- Phase7 self-checking testbench: LD24 register-transfer instructions
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 9 "Phase 7";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md, section 7 "HL24 hub / MSP /
--  vector")
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small hand
-- assembled program through a flat 64KB combinational memory model (M0,
-- no MMU/banking involved; this increment only covers plain register<->
-- register 24bit copies) to verify, for every opcode implemented in this
-- increment:
--
--   ED06 LD24 HL,BC   ED0E LD24 BC,HL
--   ED16 LD24 HL,DE   ED1E LD24 DE,HL
--   ED35 LD24 MSP,HL  ED36 LD24 HL,MSP
--   ED9B LD24 IVR,HL  ED9C LD24 HL,IVR
--   ED9E LD24 NVR,HL  ED9F LD24 HL,NVR
--
--   - the destination register pair (16bit low word + 8bit bank byte)
--     receives the full 24bit value of the source
--   - the source register pair is left unchanged ("source/F不変" per V8
--     section 7)
--   - the F (flags) register is left unchanged across an LD24 op
--
-- NOT covered by this testbench (deferred to a follow-up Phase7 increment,
-- see AVAILABLE_INSTRUCTIONS.md): DD/FD ED26/2E (HL24<->IX24/IY24 hub),
-- ED34/9A/9D (MSP24/IVR24/NVR24 24bit immediate load), and DD/FD ED80-8B
-- (indexed LD16/LD24 via (IX/IY+d)).
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase7_ld24.vhd
--   ghdl -e --std=08 tb_phase7_ld24
--   ghdl -r --std=08 tb_phase7_ld24
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase7_ld24 is
end entity tb_phase7_ld24;

architecture sim of tb_phase7_ld24 is

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

    -- Hand assembled test program (generated with a small Python helper to
    -- keep byte offsets correct; see header comment for the full story).
    -- Program length: 208 (0x00D0) bytes, starting at 0000h.
    signal mem : mem_array := (
        16#0000# => x"31", 16#0001# => x"00", 16#0002# => x"E0", -- LD SP,E000h
        16#0003# => x"01", 16#0004# => x"22", 16#0005# => x"11", -- LD BC,1122h
        16#0006# => x"3E", 16#0007# => x"11", -- LD A,11h
        16#0008# => x"ED", 16#0009# => x"04", -- LD BC_B,A
        16#000A# => x"11", 16#000B# => x"44", 16#000C# => x"33", -- LD DE,3344h
        16#000D# => x"3E", 16#000E# => x"22", -- LD A,22h
        16#000F# => x"ED", 16#0010# => x"14", -- LD DE_B,A
        16#0011# => x"21", 16#0012# => x"66", 16#0013# => x"55", -- LD HL,5566h
        16#0014# => x"3E", 16#0015# => x"33", -- LD A,33h
        16#0016# => x"ED", 16#0017# => x"24", -- LD HL_B,A
        16#0018# => x"ED", 16#0019# => x"06", -- LD24 HL,BC
        16#001A# => x"22", 16#001B# => x"00", 16#001C# => x"20", -- LD (2000h),HL
        16#001D# => x"ED", 16#001E# => x"2C", -- LD A,HL_B
        16#001F# => x"32", 16#0020# => x"02", 16#0021# => x"20", -- LD (2002h),A
        16#0022# => x"ED", 16#0023# => x"43", 16#0024# => x"03", 16#0025# => x"20", -- LD (2003h),BC  (src BC must be unchanged)
        16#0026# => x"ED", 16#0027# => x"0C", -- LD A,BC_B
        16#0028# => x"32", 16#0029# => x"05", 16#002A# => x"20", -- LD (2005h),A
        16#002B# => x"21", 16#002C# => x"66", 16#002D# => x"55", -- LD HL,5566h
        16#002E# => x"3E", 16#002F# => x"33", -- LD A,33h
        16#0030# => x"ED", 16#0031# => x"24", -- LD HL_B,A
        16#0032# => x"ED", 16#0033# => x"0E", -- LD24 BC,HL
        16#0034# => x"ED", 16#0035# => x"43", 16#0036# => x"06", 16#0037# => x"20", -- LD (2006h),BC
        16#0038# => x"ED", 16#0039# => x"0C", -- LD A,BC_B
        16#003A# => x"32", 16#003B# => x"08", 16#003C# => x"20", -- LD (2008h),A
        16#003D# => x"22", 16#003E# => x"09", 16#003F# => x"20", -- LD (2009h),HL  (src HL must be unchanged)
        16#0040# => x"ED", 16#0041# => x"2C", -- LD A,HL_B
        16#0042# => x"32", 16#0043# => x"0B", 16#0044# => x"20", -- LD (200Bh),A
        16#0045# => x"ED", 16#0046# => x"16", -- LD24 HL,DE
        16#0047# => x"22", 16#0048# => x"0C", 16#0049# => x"20", -- LD (200Ch),HL
        16#004A# => x"ED", 16#004B# => x"2C", -- LD A,HL_B
        16#004C# => x"32", 16#004D# => x"0E", 16#004E# => x"20", -- LD (200Eh),A
        16#004F# => x"ED", 16#0050# => x"53", 16#0051# => x"0F", 16#0052# => x"20", -- LD (200Fh),DE  (src DE must be unchanged)
        16#0053# => x"ED", 16#0054# => x"1C", -- LD A,DE_B
        16#0055# => x"32", 16#0056# => x"11", 16#0057# => x"20", -- LD (2011h),A
        16#0058# => x"21", 16#0059# => x"66", 16#005A# => x"55", -- LD HL,5566h
        16#005B# => x"3E", 16#005C# => x"33", -- LD A,33h
        16#005D# => x"ED", 16#005E# => x"24", -- LD HL_B,A
        16#005F# => x"ED", 16#0060# => x"1E", -- LD24 DE,HL
        16#0061# => x"ED", 16#0062# => x"53", 16#0063# => x"12", 16#0064# => x"20", -- LD (2012h),DE
        16#0065# => x"ED", 16#0066# => x"1C", -- LD A,DE_B
        16#0067# => x"32", 16#0068# => x"14", 16#0069# => x"20", -- LD (2014h),A
        16#006A# => x"22", 16#006B# => x"15", 16#006C# => x"20", -- LD (2015h),HL  (src HL must be unchanged)
        16#006D# => x"ED", 16#006E# => x"2C", -- LD A,HL_B
        16#006F# => x"32", 16#0070# => x"17", 16#0071# => x"20", -- LD (2017h),A
        16#0072# => x"21", 16#0073# => x"88", 16#0074# => x"77", -- LD HL,7788h
        16#0075# => x"3E", 16#0076# => x"44", -- LD A,44h
        16#0077# => x"ED", 16#0078# => x"24", -- LD HL_B,A
        16#0079# => x"ED", 16#007A# => x"35", -- LD24 MSP,HL
        16#007B# => x"21", 16#007C# => x"00", 16#007D# => x"00", -- LD HL,0000h (clobber)
        16#007E# => x"3E", 16#007F# => x"00", -- LD A,00h
        16#0080# => x"ED", 16#0081# => x"24", -- LD HL_B,A (clobber)
        16#0082# => x"ED", 16#0083# => x"36", -- LD24 HL,MSP
        16#0084# => x"22", 16#0085# => x"18", 16#0086# => x"20", -- LD (2018h),HL
        16#0087# => x"ED", 16#0088# => x"2C", -- LD A,HL_B
        16#0089# => x"32", 16#008A# => x"1A", 16#008B# => x"20", -- LD (201Ah),A
        16#008C# => x"21", 16#008D# => x"AA", 16#008E# => x"99", -- LD HL,99AAh
        16#008F# => x"3E", 16#0090# => x"55", -- LD A,55h
        16#0091# => x"ED", 16#0092# => x"24", -- LD HL_B,A
        16#0093# => x"ED", 16#0094# => x"9B", -- LD24 IVR,HL
        16#0095# => x"21", 16#0096# => x"00", 16#0097# => x"00", -- LD HL,0000h (clobber)
        16#0098# => x"3E", 16#0099# => x"00", -- LD A,00h
        16#009A# => x"ED", 16#009B# => x"24", -- LD HL_B,A (clobber)
        16#009C# => x"ED", 16#009D# => x"9C", -- LD24 HL,IVR
        16#009E# => x"22", 16#009F# => x"1B", 16#00A0# => x"20", -- LD (201Bh),HL
        16#00A1# => x"ED", 16#00A2# => x"2C", -- LD A,HL_B
        16#00A3# => x"32", 16#00A4# => x"1D", 16#00A5# => x"20", -- LD (201Dh),A
        16#00A6# => x"21", 16#00A7# => x"CC", 16#00A8# => x"BB", -- LD HL,BBCCh
        16#00A9# => x"3E", 16#00AA# => x"66", -- LD A,66h
        16#00AB# => x"ED", 16#00AC# => x"24", -- LD HL_B,A
        16#00AD# => x"ED", 16#00AE# => x"9E", -- LD24 NVR,HL
        16#00AF# => x"21", 16#00B0# => x"00", 16#00B1# => x"00", -- LD HL,0000h (clobber)
        16#00B2# => x"3E", 16#00B3# => x"00", -- LD A,00h
        16#00B4# => x"ED", 16#00B5# => x"24", -- LD HL_B,A (clobber)
        16#00B6# => x"ED", 16#00B7# => x"9F", -- LD24 HL,NVR
        16#00B8# => x"22", 16#00B9# => x"1E", 16#00BA# => x"20", -- LD (201Eh),HL
        16#00BB# => x"ED", 16#00BC# => x"2C", -- LD A,HL_B
        16#00BD# => x"32", 16#00BE# => x"20", 16#00BF# => x"20", -- LD (2020h),A
        16#00C0# => x"37", -- SCF (define a known flags state)
        16#00C1# => x"F5", -- PUSH AF
        16#00C2# => x"C1", -- POP BC  (C = F before)
        16#00C3# => x"79", -- LD A,C
        16#00C4# => x"32", 16#00C5# => x"21", 16#00C6# => x"20", -- LD (2021h),A  (F_before)
        16#00C7# => x"ED", 16#00C8# => x"06", -- LD24 HL,BC (exercise an LD24 op)
        16#00C9# => x"F5", -- PUSH AF
        16#00CA# => x"C1", -- POP BC  (C = F after)
        16#00CB# => x"79", -- LD A,C
        16#00CC# => x"32", 16#00CD# => x"22", 16#00CE# => x"20", -- LD (2022h),A  (F_after, must equal F_before)
        16#00CF# => x"76", -- HALT
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
            -- Memory write-back for the "LD (nnnn),HL/BC/DE/A" instructions
            -- used to dump register values for verification.
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

        -- ---- Test1: ED06 LD24 HL,BC (HL <- BC24 = 11:1122) ----
        assert mem(16#2000#) = x"22" and mem(16#2001#) = x"11" and mem(16#2002#) = x"11"
            report "Phase7: ED06 LD24 HL,BC dest HL24 mismatch, got lo=" & to_hstring(mem(16#2000#)) &
                " hi=" & to_hstring(mem(16#2001#)) & " bank=" & to_hstring(mem(16#2002#))
            severity failure;
        assert mem(16#2003#) = x"22" and mem(16#2004#) = x"11" and mem(16#2005#) = x"11"
            report "Phase7: ED06 LD24 HL,BC source BC24 must be unchanged (1122h/11h)" severity failure;

        -- ---- Test2: ED0E LD24 BC,HL (BC <- HL24 = 33:5566) ----
        assert mem(16#2006#) = x"66" and mem(16#2007#) = x"55" and mem(16#2008#) = x"33"
            report "Phase7: ED0E LD24 BC,HL dest BC24 mismatch" severity failure;
        assert mem(16#2009#) = x"66" and mem(16#200A#) = x"55" and mem(16#200B#) = x"33"
            report "Phase7: ED0E LD24 BC,HL source HL24 must be unchanged (5566h/33h)" severity failure;

        -- ---- Test3: ED16 LD24 HL,DE (HL <- DE24 = 22:3344) ----
        assert mem(16#200C#) = x"44" and mem(16#200D#) = x"33" and mem(16#200E#) = x"22"
            report "Phase7: ED16 LD24 HL,DE dest HL24 mismatch" severity failure;
        assert mem(16#200F#) = x"44" and mem(16#2010#) = x"33" and mem(16#2011#) = x"22"
            report "Phase7: ED16 LD24 HL,DE source DE24 must be unchanged (3344h/22h)" severity failure;

        -- ---- Test4: ED1E LD24 DE,HL (DE <- HL24 = 33:5566) ----
        assert mem(16#2012#) = x"66" and mem(16#2013#) = x"55" and mem(16#2014#) = x"33"
            report "Phase7: ED1E LD24 DE,HL dest DE24 mismatch" severity failure;
        assert mem(16#2015#) = x"66" and mem(16#2016#) = x"55" and mem(16#2017#) = x"33"
            report "Phase7: ED1E LD24 DE,HL source HL24 must be unchanged (5566h/33h)" severity failure;

        -- ---- Test5: ED35/ED36 MSP24 round trip (7788h/44h) ----
        assert mem(16#2018#) = x"88" and mem(16#2019#) = x"77" and mem(16#201A#) = x"44"
            report "Phase7: ED35/ED36 MSP24 round trip mismatch, got lo=" & to_hstring(mem(16#2018#)) &
                " hi=" & to_hstring(mem(16#2019#)) & " bank=" & to_hstring(mem(16#201A#))
            severity failure;

        -- ---- Test6: ED9B/ED9C IVR24 round trip (99AAh/55h) ----
        assert mem(16#201B#) = x"AA" and mem(16#201C#) = x"99" and mem(16#201D#) = x"55"
            report "Phase7: ED9B/ED9C IVR24 round trip mismatch" severity failure;

        -- ---- Test7: ED9E/ED9F NVR24 round trip (BBCCh/66h) ----
        assert mem(16#201E#) = x"CC" and mem(16#201F#) = x"BB" and mem(16#2020#) = x"66"
            report "Phase7: ED9E/ED9F NVR24 round trip mismatch" severity failure;

        -- ---- Test8: F register unaffected by an LD24 op ----
        assert mem(16#2021#) = mem(16#2022#)
            report "Phase7: LD24 HL,BC must leave F unchanged, F_before=" & to_hstring(mem(16#2021#)) &
                " F_after=" & to_hstring(mem(16#2022#))
            severity failure;

        report "Phase7 LD24 register-transfer testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
