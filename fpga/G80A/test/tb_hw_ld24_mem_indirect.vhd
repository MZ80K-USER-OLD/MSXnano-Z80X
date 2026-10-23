--
-- Hardware-timing-fidelity testbench: ED00/01/03/08 (LD24 mem-indirect)
-- reproduction attempt for hardware_test/Ld24MemIndirectTest's real
-- hardware FAILure (see doc/jpn/PUSH24_POP24_bank境界またぎバグ_
-- 調査レポート.md "追記6"). This is the aXfer-path sibling of
-- tb_hw_push24_bank_boundary_timing.vhd (the aMSP-path testbench).
--
-- MOTIVATION: tb_ld24_mem_indirect.vhd (the bare-core testbench used to
-- validate ED00/01/03/08's RTL design) ties WAIT_n to a constant '1' and
-- never toggles it - EXACTLY the same blind spot that let the original
-- PUSH24/POP24 bank-boundary bug go completely undetected by GHDL for a
-- long time (see the investigation report's "追記2": "決定的な発見:
-- GHDLテストベンチは候補1/2の対象機構を一切検証していなかった"). Real
-- hardware testing of ED00/01/03/08 (2026-10-20) found EVERY test
-- (including non-boundary-crossing Test1-4) failing with symptoms
-- consistent with a WAIT-state/SD-RAM-arbitration interaction bug - read
-- results showing all-zero (as if the memory read never genuinely
-- completed before being sampled) and write results showing
-- unpredictable, run-to-run-varying garbage (as if writes never
-- genuinely committed) - plus an outright freeze shortly after Test4.
-- This testbench reproduces the REAL g80a.vhd/top.v/memory.v WAIT/SD-RAM
-- arbitration timing chain (identical scaffolding to
-- tb_hw_push24_bank_boundary_timing.vhd, see that file's header comment
-- for the detailed v1-v8 derivation of this exact mechanism) to see
-- whether the SAME class of hazard also afflicts the NEW aXfer address
-- source (TmpAddr/TmpBank-based sequential 3byte access), independently
-- of MSP24/aMSP/bank_msp_r.
--
-- Reproduces hardware_test/Ld24MemIndirectTest/ld24_mem_indirect_test.asm's
-- Test1-6 (BDOS/VDP-marker calls stripped, since this is a closed-world
-- GHDL simulation): Test1 (ED00, normal read), Test2 (ED01, normal read),
-- Test3 (ED03, normal write), Test4 (ED08, normal write), Test5 (ED00,
-- 64KB bank-boundary-crossing read, 01:FFFE->02:0000), Test6 (ED03, same
-- boundary-crossing write).
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd ../g80a.vhd tb_hw_ld24_mem_indirect.vhd
--   ghdl -e --std=08 tb_hw_ld24_mem_indirect
--   ghdl -r --std=08 tb_hw_ld24_mem_indirect
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_hw_ld24_mem_indirect is
end entity tb_hw_ld24_mem_indirect;

architecture sim of tb_hw_ld24_mem_indirect is

    ------------------------------------------------------------------
    -- Clock generation: CLK108 (108MHz stand-in) and CLK54, matching
    -- fpga/top.v's Gowin_CLKDIV2 exact divide-by-2 relationship (only
    -- the 2:1 ratio/edge alignment matters for logic-level fidelity,
    -- not the absolute frequency). Identical to
    -- tb_hw_push24_bank_boundary_timing.vhd.
    ------------------------------------------------------------------
    signal CLK108  : std_logic := '0';
    signal CLK54   : std_logic := '0';
    signal RESET_n : std_logic := '0';

    ------------------------------------------------------------------
    -- 3.6MHz virtual-clock chain, ported line-for-line from fpga/top.v
    -- (div30_cnt/clk_3m6_internal, the PINFILTER debounce "dn1", and
    -- the clk_enable_3m6_54/clk_falling_3m6_54 edge detectors).
    ------------------------------------------------------------------
    signal div30_cnt        : unsigned(4 downto 0) := (others => '0');
    signal clk_3m6_internal : std_logic := '0';

    signal pf_dpipe    : std_logic_vector(1 downto 0) := "00";
    signal bus_clk_3m6 : std_logic := '0';

    signal bus_clk_3m6_54      : std_logic := '0';
    signal bus_clk_3m6_prev_54 : std_logic := '0';
    signal clk_enable_3m6_54   : std_logic;
    signal clk_falling_3m6_54  : std_logic;

    ------------------------------------------------------------------
    -- G80a (the real async CPU wrapper, unmodified) port signals.
    ------------------------------------------------------------------
    signal WAIT_n    : std_logic := '1';
    signal INT_n     : std_logic := '1';
    signal NMI_n     : std_logic := '1';
    signal BUSRQ_n   : std_logic := '1';
    signal M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n : std_logic;
    signal A            : std_logic_vector(15 downto 0);
    signal update_addr  : std_logic;
    signal A_Bank       : std_logic_vector(7 downto 0);
    signal DI, DO       : std_logic_vector(7 downto 0);
    signal mode24       : std_logic_vector(1 downto 0);
    signal bank_bc, bank_de, bank_hl, bank_ix, bank_iy, bank_pc,
           bank_msp, bank_int, bank_nvr, bank_rst : std_logic_vector(7 downto 0);
    signal Data_Reverse : std_logic;

    ------------------------------------------------------------------
    -- fpga/top.v's cpu_sdram_* request/address-latch/WAIT generation
    -- (v8-fixed, current version), ported line-for-line, identical to
    -- tb_hw_push24_bank_boundary_timing.vhd - see that file's extensive
    -- header comment for the full v1-v8 derivation of this exact
    -- 3-state (WS_IDLE/WS_ARMED/WS_WAITING_DONE) mechanism.
    ------------------------------------------------------------------
    constant CPU_SDRAM_BASE     : unsigned(23 downto 0) := x"640000";
    constant CPU_SDRAM_BANK_MAX : unsigned(7 downto 0)  := x"1B";

    signal mmu_physical_bank : std_logic_vector(7 downto 0);

    signal cpu_sdram_active        : std_logic;
    signal cpu_sdram_req           : std_logic;
    signal cpu_sdram_addr_r        : std_logic_vector(23 downto 0) := (others => '0');
    signal cpu_sdram_write_r       : std_logic := '0';
    signal cpu_sdram_write         : std_logic;
    signal cpu_sdram_addr          : std_logic_vector(23 downto 0);
    signal cpu_sdram_dout          : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_sdram_bank_in_range : std_logic;

    signal cpu_sdram_busy      : std_logic := '0';
    signal cpu_sdram_wait_n    : std_logic := '1';

    signal update_addr_prev  : std_logic := '0';
    signal update_addr_prev2 : std_logic := '0';

    type wait_state_t is (WS_IDLE, WS_ARMED, WS_WAITING_DONE);
    signal wait_state : wait_state_t := WS_IDLE;

    signal cpu_sdram_done_pulse : std_logic;

    ------------------------------------------------------------------
    -- fpga/src/memory.v's sdram_seq arbitration (current, v4-fixed
    -- version), ported line-for-line. mapper_req/megaram_req are
    -- permanently '0' in this scoped testbench (no legacy-mapper/
    -- megaram client is modeled).
    ------------------------------------------------------------------
    constant mapper_req    : std_logic := '0';
    constant megaram_req   : std_logic := '0';

    signal sdram_seq          : std_logic_vector(2 downto 0) := "000";
    signal sdram_addr         : unsigned(22 downto 0) := (others => '0');
    signal sdram_write        : std_logic := '0';
    signal sdram_owner_cpu    : std_logic := '0';
    signal sdram_owner_mapper : std_logic := '0';
    signal RamDbi             : std_logic_vector(7 downto 0) := (others => '0');

    ------------------------------------------------------------------
    -- Free-running "video bandwidth arbitration window" stand-in for
    -- the real VDP's video_dlclk/video_dhclk - identical
    -- (OPEN=1,CLOSED=29) parameters to tb_hw_push24_bank_boundary_
    -- timing.vhd's own reproducing configuration (see that file's
    -- header comment for the sweep results this was chosen from).
    ------------------------------------------------------------------
    constant VIDEO_WINDOW_OPEN_CYCLES   : natural := 1;
    constant VIDEO_WINDOW_CLOSED_CYCLES : natural := 29;
    constant VIDEO_WINDOW_PERIOD        : natural := VIDEO_WINDOW_OPEN_CYCLES + VIDEO_WINDOW_CLOSED_CYCLES;
    signal video_window_cnt  : integer range 0 to VIDEO_WINDOW_PERIOD - 1 := 0;
    signal video_window_open : std_logic := '1';
    signal video_dlclk, video_dhclk : std_logic;

    ------------------------------------------------------------------
    -- "Legacy" bank00 memory (program + result-dump area) - plain,
    -- zero-wait, matching the real hardware's bank00 = ordinary MSX
    -- Memory Mapper RAM path (never routed through cpu_sdram_*).
    --
    -- Hand assembled program (mirrors hardware_test/Ld24MemIndirectTest/
    -- ld24_mem_indirect_test.asm's Test1-6, BDOS/VDP-marker calls
    -- stripped - generated with a throwaway Python helper, same style
    -- precedent as tb_phase9_push24_pop24.vhd/tb_ld24_mem_indirect.vhd):
    --
    --   Test1: ED00 LD24 BC,(HL), HL24=01:9000h (normal, no boundary)
    --   Test2: ED01 LD24 DE,(HL), HL24=01:9010h (normal, no boundary)
    --   Test3: ED03 LD24 (HL),BC, HL24=01:9020h (normal, no boundary)
    --   Test4: ED08 LD24 (HL),DE, HL24=01:9030h (normal, no boundary)
    --   Test5: ED00 LD24 BC,(HL), HL24=01:FFFEh (64KB boundary crossing,
    --          3rd byte carries into bank 02h address 0000h)
    --   Test6: ED03 LD24 (HL),BC, HL24=01:FFFEh (same boundary crossing)
    --
    -- Dump area layout (bank00, all offsets from 4000h):
    --   4000-4002: Test1 BC24 result (lo,hi,bank)
    --   4003-4005: Test1 HL24 readback (lo,hi,bank - must stay 01:9000h)
    --   4006-4008: Test2 DE24 result (lo,hi,bank)
    --   4009-400B: Test2 HL24 readback (lo,hi,bank - must stay 01:9010h)
    --   400C-400E: Test3 (BC)-peek readback of the 3 written bytes
    --   400F-4011: Test4 (BC)-peek readback of the 3 written bytes
    --   4012-4014: Test5 BC24 result (lo,hi,bank - must be 07:ABCDh)
    --   4015-4017: Test5 HL24 readback (lo,hi,bank - must stay 01:FFFEh)
    --   4018-401A: Test6 (BC)-peek readback of the 3 written bytes
    ------------------------------------------------------------------
    type mem_array is array(0 to 65535) of std_logic_vector(7 downto 0);
    signal mem00 : mem_array := (
        16#0000# => x"ED", 16#0001# => x"91", 16#0002# => x"01", 16#0003# => x"00",
        16#0004# => x"90", 16#0005# => x"3E", 16#0006# => x"01", 16#0007# => x"ED",
        16#0008# => x"04", 16#0009# => x"3E", 16#000A# => x"AA", 16#000B# => x"02",
        16#000C# => x"01", 16#000D# => x"01", 16#000E# => x"90", 16#000F# => x"3E",
        16#0010# => x"01", 16#0011# => x"ED", 16#0012# => x"04", 16#0013# => x"3E",
        16#0014# => x"99", 16#0015# => x"02", 16#0016# => x"01", 16#0017# => x"02",
        16#0018# => x"90", 16#0019# => x"3E", 16#001A# => x"01", 16#001B# => x"ED",
        16#001C# => x"04", 16#001D# => x"3E", 16#001E# => x"05", 16#001F# => x"02",
        16#0020# => x"21", 16#0021# => x"00", 16#0022# => x"90", 16#0023# => x"3E",
        16#0024# => x"01", 16#0025# => x"ED", 16#0026# => x"24", 16#0027# => x"01",
        16#0028# => x"00", 16#0029# => x"00", 16#002A# => x"AF", 16#002B# => x"ED",
        16#002C# => x"04", 16#002D# => x"ED", 16#002E# => x"00", 16#002F# => x"ED",
        16#0030# => x"43", 16#0031# => x"00", 16#0032# => x"40", 16#0033# => x"ED",
        16#0034# => x"0C", 16#0035# => x"32", 16#0036# => x"02", 16#0037# => x"40",
        16#0038# => x"22", 16#0039# => x"03", 16#003A# => x"40", 16#003B# => x"ED",
        16#003C# => x"2C", 16#003D# => x"32", 16#003E# => x"05", 16#003F# => x"40",
        16#0040# => x"01", 16#0041# => x"10", 16#0042# => x"90", 16#0043# => x"3E",
        16#0044# => x"01", 16#0045# => x"ED", 16#0046# => x"04", 16#0047# => x"3E",
        16#0048# => x"11", 16#0049# => x"02", 16#004A# => x"01", 16#004B# => x"11",
        16#004C# => x"90", 16#004D# => x"3E", 16#004E# => x"01", 16#004F# => x"ED",
        16#0050# => x"04", 16#0051# => x"3E", 16#0052# => x"22", 16#0053# => x"02",
        16#0054# => x"01", 16#0055# => x"12", 16#0056# => x"90", 16#0057# => x"3E",
        16#0058# => x"01", 16#0059# => x"ED", 16#005A# => x"04", 16#005B# => x"3E",
        16#005C# => x"33", 16#005D# => x"02", 16#005E# => x"21", 16#005F# => x"10",
        16#0060# => x"90", 16#0061# => x"3E", 16#0062# => x"01", 16#0063# => x"ED",
        16#0064# => x"24", 16#0065# => x"11", 16#0066# => x"00", 16#0067# => x"00",
        16#0068# => x"AF", 16#0069# => x"ED", 16#006A# => x"14", 16#006B# => x"ED",
        16#006C# => x"01", 16#006D# => x"ED", 16#006E# => x"53", 16#006F# => x"06",
        16#0070# => x"40", 16#0071# => x"ED", 16#0072# => x"1C", 16#0073# => x"32",
        16#0074# => x"08", 16#0075# => x"40", 16#0076# => x"22", 16#0077# => x"09",
        16#0078# => x"40", 16#0079# => x"ED", 16#007A# => x"2C", 16#007B# => x"32",
        16#007C# => x"0B", 16#007D# => x"40", 16#007E# => x"21", 16#007F# => x"20",
        16#0080# => x"90", 16#0081# => x"3E", 16#0082# => x"01", 16#0083# => x"ED",
        16#0084# => x"24", 16#0085# => x"01", 16#0086# => x"34", 16#0087# => x"12",
        16#0088# => x"3E", 16#0089# => x"EE", 16#008A# => x"ED", 16#008B# => x"04",
        16#008C# => x"ED", 16#008D# => x"03", 16#008E# => x"01", 16#008F# => x"20",
        16#0090# => x"90", 16#0091# => x"3E", 16#0092# => x"01", 16#0093# => x"ED",
        16#0094# => x"04", 16#0095# => x"0A", 16#0096# => x"32", 16#0097# => x"0C",
        16#0098# => x"40", 16#0099# => x"01", 16#009A# => x"21", 16#009B# => x"90",
        16#009C# => x"3E", 16#009D# => x"01", 16#009E# => x"ED", 16#009F# => x"04",
        16#00A0# => x"0A", 16#00A1# => x"32", 16#00A2# => x"0D", 16#00A3# => x"40",
        16#00A4# => x"01", 16#00A5# => x"22", 16#00A6# => x"90", 16#00A7# => x"3E",
        16#00A8# => x"01", 16#00A9# => x"ED", 16#00AA# => x"04", 16#00AB# => x"0A",
        16#00AC# => x"32", 16#00AD# => x"0E", 16#00AE# => x"40", 16#00AF# => x"21",
        16#00B0# => x"30", 16#00B1# => x"90", 16#00B2# => x"3E", 16#00B3# => x"01",
        16#00B4# => x"ED", 16#00B5# => x"24", 16#00B6# => x"11", 16#00B7# => x"78",
        16#00B8# => x"56", 16#00B9# => x"3E", 16#00BA# => x"9A", 16#00BB# => x"ED",
        16#00BC# => x"14", 16#00BD# => x"ED", 16#00BE# => x"08", 16#00BF# => x"01",
        16#00C0# => x"30", 16#00C1# => x"90", 16#00C2# => x"3E", 16#00C3# => x"01",
        16#00C4# => x"ED", 16#00C5# => x"04", 16#00C6# => x"0A", 16#00C7# => x"32",
        16#00C8# => x"0F", 16#00C9# => x"40", 16#00CA# => x"01", 16#00CB# => x"31",
        16#00CC# => x"90", 16#00CD# => x"3E", 16#00CE# => x"01", 16#00CF# => x"ED",
        16#00D0# => x"04", 16#00D1# => x"0A", 16#00D2# => x"32", 16#00D3# => x"10",
        16#00D4# => x"40", 16#00D5# => x"01", 16#00D6# => x"32", 16#00D7# => x"90",
        16#00D8# => x"3E", 16#00D9# => x"01", 16#00DA# => x"ED", 16#00DB# => x"04",
        16#00DC# => x"0A", 16#00DD# => x"32", 16#00DE# => x"11", 16#00DF# => x"40",
        16#00E0# => x"01", 16#00E1# => x"FE", 16#00E2# => x"FF", 16#00E3# => x"3E",
        16#00E4# => x"01", 16#00E5# => x"ED", 16#00E6# => x"04", 16#00E7# => x"3E",
        16#00E8# => x"CD", 16#00E9# => x"02", 16#00EA# => x"01", 16#00EB# => x"FF",
        16#00EC# => x"FF", 16#00ED# => x"3E", 16#00EE# => x"01", 16#00EF# => x"ED",
        16#00F0# => x"04", 16#00F1# => x"3E", 16#00F2# => x"AB", 16#00F3# => x"02",
        16#00F4# => x"01", 16#00F5# => x"00", 16#00F6# => x"00", 16#00F7# => x"3E",
        16#00F8# => x"02", 16#00F9# => x"ED", 16#00FA# => x"04", 16#00FB# => x"3E",
        16#00FC# => x"07", 16#00FD# => x"02", 16#00FE# => x"21", 16#00FF# => x"FE",
        16#0100# => x"FF", 16#0101# => x"3E", 16#0102# => x"01", 16#0103# => x"ED",
        16#0104# => x"24", 16#0105# => x"01", 16#0106# => x"00", 16#0107# => x"00",
        16#0108# => x"AF", 16#0109# => x"ED", 16#010A# => x"04", 16#010B# => x"ED",
        16#010C# => x"00", 16#010D# => x"ED", 16#010E# => x"43", 16#010F# => x"12",
        16#0110# => x"40", 16#0111# => x"ED", 16#0112# => x"0C", 16#0113# => x"32",
        16#0114# => x"14", 16#0115# => x"40", 16#0116# => x"22", 16#0117# => x"15",
        16#0118# => x"40", 16#0119# => x"ED", 16#011A# => x"2C", 16#011B# => x"32",
        16#011C# => x"17", 16#011D# => x"40", 16#011E# => x"21", 16#011F# => x"FE",
        16#0120# => x"FF", 16#0121# => x"3E", 16#0122# => x"01", 16#0123# => x"ED",
        16#0124# => x"24", 16#0125# => x"01", 16#0126# => x"EF", 16#0127# => x"BE",
        16#0128# => x"3E", 16#0129# => x"42", 16#012A# => x"ED", 16#012B# => x"04",
        16#012C# => x"ED", 16#012D# => x"03", 16#012E# => x"01", 16#012F# => x"FE",
        16#0130# => x"FF", 16#0131# => x"3E", 16#0132# => x"01", 16#0133# => x"ED",
        16#0134# => x"04", 16#0135# => x"0A", 16#0136# => x"32", 16#0137# => x"18",
        16#0138# => x"40", 16#0139# => x"01", 16#013A# => x"FF", 16#013B# => x"FF",
        16#013C# => x"3E", 16#013D# => x"01", 16#013E# => x"ED", 16#013F# => x"04",
        16#0140# => x"0A", 16#0141# => x"32", 16#0142# => x"19", 16#0143# => x"40",
        16#0144# => x"01", 16#0145# => x"00", 16#0146# => x"00", 16#0147# => x"3E",
        16#0148# => x"02", 16#0149# => x"ED", 16#014A# => x"04", 16#014B# => x"0A",
        16#014C# => x"32", 16#014D# => x"1A", 16#014E# => x"40", 16#014F# => x"76",
        others => x"00");

    ------------------------------------------------------------------
    -- Idealized, zero-added-latency backing store, one register per
    -- physical address this test's Test1-6 ever touch (candidate 3 -
    -- real 108MHz SD-RAM physical-layer timing - deliberately stays out
    -- of scope here, same as tb_hw_push24_bank_boundary_timing.vhd).
    -- Physical address = CPU_SDRAM_BASE(640000h) + bank*10000h + addr.
    ------------------------------------------------------------------
    signal fake_659000 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9000h (Test1 LOW src)
    signal fake_659001 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9001h (Test1 HIGH src)
    signal fake_659002 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9002h (Test1 BANK src)
    signal fake_659010 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9010h (Test2 LOW src)
    signal fake_659011 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9011h (Test2 HIGH src)
    signal fake_659012 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9012h (Test2 BANK src)
    signal fake_659020 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9020h (Test3 LOW dst)
    signal fake_659021 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9021h (Test3 HIGH dst)
    signal fake_659022 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9022h (Test3 BANK dst)
    signal fake_659030 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9030h (Test4 LOW dst)
    signal fake_659031 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9031h (Test4 HIGH dst)
    signal fake_659032 : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:9032h (Test4 BANK dst)
    signal fake_65FFFE : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:FFFEh (Test5/6 LOW)
    signal fake_65FFFF : std_logic_vector(7 downto 0) := (others => '0'); -- bank01:FFFFh (Test5/6 HIGH)
    signal fake_660000 : std_logic_vector(7 downto 0) := (others => '0'); -- bank02:0000h (Test5/6 BANK, crosses the boundary)

    signal cpu_din : std_logic_vector(7 downto 0) := (others => '0');

begin

    ------------------------------------------------------------------
    -- Clocks
    ------------------------------------------------------------------
    CLK108 <= not CLK108 after 5 ns;

    process (CLK108)
    begin
        if rising_edge(CLK108) then
            CLK54 <= not CLK54;
        end if;
    end process;

    process
    begin
        RESET_n <= '0';
        wait for 300 ns;
        RESET_n <= '1';
        wait;
    end process;

    ------------------------------------------------------------------
    -- 3.6MHz virtual clock chain (fpga/top.v's div30_cnt/
    -- clk_3m6_internal, PINFILTER "dn1", clk_enable_3m6_54/
    -- clk_falling_3m6_54)
    ------------------------------------------------------------------
    process (CLK108)
    begin
        if rising_edge(CLK108) then
            if RESET_n = '0' then
                div30_cnt <= (others => '0');
                clk_3m6_internal <= '0';
            else
                if div30_cnt = 14 then
                    clk_3m6_internal <= not clk_3m6_internal;
                    div30_cnt <= (others => '0');
                else
                    div30_cnt <= div30_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    process (CLK54)
        variable dpipe : std_logic_vector(1 downto 0);
    begin
        if rising_edge(CLK54) then
            dpipe(1) := pf_dpipe(0);
            dpipe(0) := clk_3m6_internal;
            if dpipe = "00" then
                bus_clk_3m6 <= '0';
            elsif dpipe = "11" then
                bus_clk_3m6 <= '1';
            end if;
            pf_dpipe <= dpipe;
        end if;
    end process;

    process (CLK54)
    begin
        if rising_edge(CLK54) then
            bus_clk_3m6_54 <= bus_clk_3m6;
            bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
        end if;
    end process;
    clk_enable_3m6_54  <= '1' when (bus_clk_3m6_prev_54 = '0' and bus_clk_3m6_54 = '1') else '0';
    clk_falling_3m6_54 <= '1' when (bus_clk_3m6_prev_54 = '1' and bus_clk_3m6_54 = '0') else '0';

    ------------------------------------------------------------------
    -- Free-running video arbitration window (see header comment)
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if video_window_cnt = VIDEO_WINDOW_PERIOD - 1 then
                video_window_cnt <= 0;
            else
                video_window_cnt <= video_window_cnt + 1;
            end if;
            if video_window_cnt < VIDEO_WINDOW_OPEN_CYCLES then
                video_window_open <= '1';
            else
                video_window_open <= '0';
            end if;
        end if;
    end process;
    video_dlclk <= video_window_open;
    video_dhclk <= video_window_open;

    ------------------------------------------------------------------
    -- G80a: the REAL async CPU wrapper (fpga/G80A/g80a.vhd),
    -- unmodified, instantiated directly.
    ------------------------------------------------------------------
    u_cpu : entity work.G80a
        generic map(
            Mode => 0,
            IOWait => 1)
        port map(
            RESET_n => RESET_n,
            CLK_n => CLK54,
            clk_enable => clk_enable_3m6_54,
            clk_falling => clk_falling_3m6_54,
            WAIT_n => WAIT_n,
            INT_n => INT_n,
            NMI_n => NMI_n,
            BUSRQ_n => BUSRQ_n,
            M1_n => M1_n,
            MREQ_n => MREQ_n,
            IORQ_n => IORQ_n,
            RD_n => RD_n,
            WR_n => WR_n,
            RFSH_n => RFSH_n,
            HALT_n => HALT_n,
            BUSAK_n => BUSAK_n,
            A => A,
            update_addr => update_addr,
            A_Bank => A_Bank,
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
            Data_Reverse => Data_Reverse);

    DI <= cpu_din;
    mmu_physical_bank <= A_Bank;

    ------------------------------------------------------------------
    -- fpga/top.v: cpu_sdram_active/cpu_sdram_bank_in_range.
    ------------------------------------------------------------------
    cpu_sdram_bank_in_range <= '1' when (mmu_physical_bank /= x"00" and
                                          unsigned(mmu_physical_bank) <= CPU_SDRAM_BANK_MAX)
                               else '0';

    cpu_sdram_active <= '1' when (cpu_sdram_bank_in_range = '1' and MREQ_n = '0' and
                                   (RD_n = '0' or WR_n = '0') and RFSH_n = '1')
                        else '0';
    cpu_sdram_req   <= cpu_sdram_active;
    cpu_sdram_write <= cpu_sdram_req and cpu_sdram_write_r;
    cpu_sdram_addr  <= cpu_sdram_addr_r;

    ------------------------------------------------------------------
    -- fpga/top.v: cpu_sdram_busy-based WAIT_n generator (v8-fixed,
    -- current version) - identical to tb_hw_push24_bank_boundary_
    -- timing.vhd, see that file's declaration comment for the full
    -- v1-v8 rationale.
    ------------------------------------------------------------------
    cpu_sdram_done_pulse <= '1' when (sdram_seq = "011" and sdram_owner_cpu = '1') else '0';

    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if RESET_n = '0' then
                cpu_sdram_wait_n <= '1';
                wait_state <= WS_IDLE;
                update_addr_prev <= '0';
                update_addr_prev2 <= '0';
                cpu_sdram_addr_r <= (others => '0');
                cpu_sdram_write_r <= '0';
            else
                update_addr_prev <= update_addr;
                update_addr_prev2 <= update_addr_prev;

                case wait_state is
                    when WS_IDLE =>
                        if update_addr_prev = '1' and update_addr_prev2 = '0' and
                           mmu_physical_bank /= x"00" and
                           unsigned(mmu_physical_bank) <= CPU_SDRAM_BANK_MAX then
                            cpu_sdram_wait_n <= '0';
                            wait_state <= WS_ARMED;
                        end if;

                    when WS_ARMED =>
                        if cpu_sdram_active = '1' then
                            cpu_sdram_addr_r <= std_logic_vector(CPU_SDRAM_BASE +
                                (unsigned(mmu_physical_bank) & unsigned(A)));
                            cpu_sdram_write_r <= not WR_n;
                            wait_state <= WS_WAITING_DONE;
                        end if;

                    when WS_WAITING_DONE =>
                        if cpu_sdram_done_pulse = '1' then
                            cpu_sdram_wait_n <= '1';
                            wait_state <= WS_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    WAIT_n <= cpu_sdram_wait_n;

    ------------------------------------------------------------------
    -- fpga/src/memory.v: sdram_seq arbitration state machine (current,
    -- v4-fixed version), ported line-for-line. Write commit to the
    -- (now 15-address) fake backing store happens in state "001", same
    -- as tb_hw_push24_bank_boundary_timing.vhd.
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if RESET_n = '0' then
                sdram_seq <= "000";
                sdram_addr <= (others => '0');
                sdram_write <= '0';
                cpu_sdram_busy <= '0';
                sdram_owner_cpu <= '0';
                sdram_owner_mapper <= '0';
            else
                case sdram_seq is
                    when "000" =>
                        sdram_write <= '0';
                        if (mapper_req = '1' or megaram_req = '1' or cpu_sdram_req = '1') and
                           (video_dlclk = '1' and video_dhclk = '1') then
                            sdram_seq <= "001";
                        end if;
                        cpu_sdram_busy <= cpu_sdram_req;

                    when "001" =>
                        if cpu_sdram_req = '1' then
                            sdram_addr <= unsigned(cpu_sdram_addr(22 downto 0));
                            sdram_write <= cpu_sdram_write;
                            sdram_owner_cpu <= '1';
                            sdram_owner_mapper <= '0';
                            if cpu_sdram_write = '1' then
                                case cpu_sdram_addr is
                                    when x"659000" => fake_659000 <= DO;
                                    when x"659001" => fake_659001 <= DO;
                                    when x"659002" => fake_659002 <= DO;
                                    when x"659010" => fake_659010 <= DO;
                                    when x"659011" => fake_659011 <= DO;
                                    when x"659012" => fake_659012 <= DO;
                                    when x"659020" => fake_659020 <= DO;
                                    when x"659021" => fake_659021 <= DO;
                                    when x"659022" => fake_659022 <= DO;
                                    when x"659030" => fake_659030 <= DO;
                                    when x"659031" => fake_659031 <= DO;
                                    when x"659032" => fake_659032 <= DO;
                                    when x"65FFFE" => fake_65FFFE <= DO;
                                    when x"65FFFF" => fake_65FFFF <= DO;
                                    when x"660000" => fake_660000 <= DO;
                                    when others => null;
                                end case;
                            end if;
                        else
                            sdram_write <= '0';
                            sdram_owner_cpu <= '0';
                            sdram_owner_mapper <= '0';
                        end if;
                        sdram_seq <= "010";
                        cpu_sdram_busy <= cpu_sdram_req;

                    when "010" =>
                        if video_dlclk = '0' and video_dhclk = '0' then
                            sdram_write <= '0';
                            sdram_seq <= "011";
                        end if;
                        cpu_sdram_busy <= sdram_owner_cpu;

                    when "011" =>
                        sdram_write <= '0';
                        if sdram_owner_cpu = '1' then
                            cpu_sdram_dout <= RamDbi;
                        end if;
                        sdram_seq <= "100";
                        cpu_sdram_busy <= '0';

                    when "100" =>
                        if mapper_req = '0' and megaram_req = '0' and cpu_sdram_req = '0' then
                            sdram_seq <= "000";
                        end if;

                    when others =>
                        sdram_seq <= "000";
                end case;
            end if;
        end if;
    end process;

    -- Idealized zero-latency SD-RAM read data (candidate 3 out of
    -- scope - see header comment): combinationally reflects whichever
    -- of the 15 known physical addresses sdram_addr (latched in state
    -- "001") currently holds.
    RamDbi <= fake_659000 when sdram_addr = x"659000" else
              fake_659001 when sdram_addr = x"659001" else
              fake_659002 when sdram_addr = x"659002" else
              fake_659010 when sdram_addr = x"659010" else
              fake_659011 when sdram_addr = x"659011" else
              fake_659012 when sdram_addr = x"659012" else
              fake_659020 when sdram_addr = x"659020" else
              fake_659021 when sdram_addr = x"659021" else
              fake_659022 when sdram_addr = x"659022" else
              fake_659030 when sdram_addr = x"659030" else
              fake_659031 when sdram_addr = x"659031" else
              fake_659032 when sdram_addr = x"659032" else
              fake_65FFFE when sdram_addr = x"65FFFE" else
              fake_65FFFF when sdram_addr = x"65FFFF" else
              fake_660000 when sdram_addr = x"660000" else
              x"00";

    ------------------------------------------------------------------
    -- fpga/top.v: registered cpu_din priority mux (ported; only the
    -- cpu_sdram_req/legacy-bank00 branches are relevant here).
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if cpu_sdram_req = '1' then
                cpu_din <= cpu_sdram_dout;
            else
                cpu_din <= mem00(to_integer(unsigned(A)));
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Legacy bank00 memory write-back (program + result-dump area;
    -- never routed through cpu_sdram_*).
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if cpu_sdram_req = '0' and MREQ_n = '0' and WR_n = '0' then
                mem00(to_integer(unsigned(A))) <= DO;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- DIAGNOSTIC (temporary): cycle-by-cycle trace of every extended-
    -- memory transaction, including hierarchical probes of the T80
    -- core's internal TmpAddr/TmpBank registers (the aXfer-path
    -- counterpart to tb_hw_push24_bank_boundary_timing.vhd's MSP/
    -- bank_msp_r probes), to directly observe whether the xfer pointer
    -- gets corrupted INSIDE the core during a reproducing run.
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if cpu_sdram_req = '1' or sdram_seq /= "000" or cpu_sdram_wait_n = '0' then
                report "t=" & time'image(now) &
                    " IR=" & to_hstring(<<signal u_cpu.u0.IR : std_logic_vector(7 downto 0)>>) &
                    " ISet=" & to_hstring(<<signal u_cpu.u0.ISet : std_logic_vector(1 downto 0)>>) &
                    " MC=" & to_hstring(<<signal u_cpu.u0.MCycle : std_logic_vector(3 downto 0)>>) &
                    " TS=" & integer'image(to_integer(<<signal u_cpu.u0.TState : unsigned(2 downto 0)>>)) &
                    " A=" & to_hstring(A) & " A_Bank=" & to_hstring(A_Bank) &
                    " MREQ_n=" & std_logic'image(MREQ_n) & " RD_n=" & std_logic'image(RD_n) &
                    " WR_n=" & std_logic'image(WR_n) &
                    " req=" & std_logic'image(cpu_sdram_req) &
                    " wait_n=" & std_logic'image(cpu_sdram_wait_n) &
                    " busy=" & std_logic'image(cpu_sdram_busy) &
                    " seq=" & to_hstring(sdram_seq) &
                    " core_WAIT_n=" & std_logic'image(<<signal u_cpu.u0.WAIT_n : std_logic>>) &
                    " TmpAddr=" & to_hstring(<<signal u_cpu.u0.TmpAddr : std_logic_vector(15 downto 0)>>) &
                    " TmpBank=" & to_hstring(<<signal u_cpu.u0.TmpBank : std_logic_vector(7 downto 0)>>) &
                    " DI_Reg=" & to_hstring(<<signal u_cpu.DI_Reg : std_logic_vector(7 downto 0)>>) &
                    " sdram_dout=" & to_hstring(cpu_sdram_dout) &
                    " cpu_din=" & to_hstring(cpu_din) &
                    " cpu_sdram_addr_r=" & to_hstring(cpu_sdram_addr_r) &
                    " sdram_addr=" & to_hstring(std_logic_vector(sdram_addr)) &
                    " sdram_owner_cpu=" & std_logic'image(sdram_owner_cpu) &
                    " active=" & std_logic'image(cpu_sdram_active) &
                    " update_addr=" & std_logic'image(update_addr) &
                    " update_addr_prev=" & std_logic'image(update_addr_prev) &
                    " wait_state=" & wait_state_t'image(wait_state) &
                    " done_pulse=" & std_logic'image(cpu_sdram_done_pulse) &
                    " clk_falling=" & std_logic'image(clk_falling_3m6_54)
                    severity note;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Self-check: wait for HALT, then verify Test1-6 against the real
    -- hardware test's expected ("want") values. Uses "severity error"
    -- (not "failure") so ALL checks always run and the final summary
    -- report always prints, regardless of outcome.
    ------------------------------------------------------------------
    process
        variable timeout_hit : boolean := false;
    begin
        wait until HALT_n = '0' for 5 ms;
        if HALT_n = '1' then
            timeout_hit := true;
            report "HW-timing repro (LD24 mem-indirect): TIMEOUT waiting for HALT " &
                "(5ms elapsed without the program reaching its final HALT - this " &
                "would correspond to a FREEZE/hang on real hardware, matching the " &
                "observed real-hardware symptom of the program stopping shortly " &
                "after Test4)."
                severity error;
        else
            wait for 5 us; -- drain trailing HALT refetch cycles
        end if;

        if not timeout_hit then
            assert mem00(16#4000#) = x"AA" and mem00(16#4001#) = x"99" and mem00(16#4002#) = x"05"
                report "Test1: ED00 LD24 BC,(HL) normal read mismatch, got lo=" &
                    to_hstring(mem00(16#4000#)) & " hi=" & to_hstring(mem00(16#4001#)) &
                    " bank=" & to_hstring(mem00(16#4002#)) & ", want lo=AAh hi=99h bank=05h"
                severity error;
            assert mem00(16#4003#) = x"00" and mem00(16#4004#) = x"90" and mem00(16#4005#) = x"01"
                report "Test1: HL24 must stay unchanged (01:9000h), got lo=" &
                    to_hstring(mem00(16#4003#)) & " hi=" & to_hstring(mem00(16#4004#)) &
                    " bank=" & to_hstring(mem00(16#4005#))
                severity error;

            assert mem00(16#4006#) = x"11" and mem00(16#4007#) = x"22" and mem00(16#4008#) = x"33"
                report "Test2: ED01 LD24 DE,(HL) normal read mismatch, got lo=" &
                    to_hstring(mem00(16#4006#)) & " hi=" & to_hstring(mem00(16#4007#)) &
                    " bank=" & to_hstring(mem00(16#4008#)) & ", want lo=11h hi=22h bank=33h"
                severity error;
            assert mem00(16#4009#) = x"10" and mem00(16#400A#) = x"90" and mem00(16#400B#) = x"01"
                report "Test2: HL24 must stay unchanged (01:9010h), got lo=" &
                    to_hstring(mem00(16#4009#)) & " hi=" & to_hstring(mem00(16#400A#)) &
                    " bank=" & to_hstring(mem00(16#400B#))
                severity error;

            assert mem00(16#400C#) = x"34" and mem00(16#400D#) = x"12" and mem00(16#400E#) = x"EE"
                report "Test3: ED03 LD24 (HL),BC normal write mismatch, got lo=" &
                    to_hstring(mem00(16#400C#)) & " hi=" & to_hstring(mem00(16#400D#)) &
                    " bank=" & to_hstring(mem00(16#400E#)) & ", want lo=34h hi=12h bank=EEh"
                severity error;

            assert mem00(16#400F#) = x"78" and mem00(16#4010#) = x"56" and mem00(16#4011#) = x"9A"
                report "Test4: ED08 LD24 (HL),DE normal write mismatch, got lo=" &
                    to_hstring(mem00(16#400F#)) & " hi=" & to_hstring(mem00(16#4010#)) &
                    " bank=" & to_hstring(mem00(16#4011#)) & ", want lo=78h hi=56h bank=9Ah"
                severity error;

            assert mem00(16#4012#) = x"CD" and mem00(16#4013#) = x"AB" and mem00(16#4014#) = x"07"
                report "Test5: ED00 boundary-crossing read mismatch, got lo=" &
                    to_hstring(mem00(16#4012#)) & " hi=" & to_hstring(mem00(16#4013#)) &
                    " bank=" & to_hstring(mem00(16#4014#)) & ", want lo=CDh hi=ABh bank=07h"
                severity error;
            assert mem00(16#4015#) = x"FE" and mem00(16#4016#) = x"FF" and mem00(16#4017#) = x"01"
                report "Test5: HL24 must stay unchanged (01:FFFEh, not carried), got lo=" &
                    to_hstring(mem00(16#4015#)) & " hi=" & to_hstring(mem00(16#4016#)) &
                    " bank=" & to_hstring(mem00(16#4017#))
                severity error;

            assert mem00(16#4018#) = x"EF" and mem00(16#4019#) = x"BE" and mem00(16#401A#) = x"42"
                report "Test6: ED03 boundary-crossing write mismatch, got lo=" &
                    to_hstring(mem00(16#4018#)) & " hi=" & to_hstring(mem00(16#4019#)) &
                    " bank=" & to_hstring(mem00(16#401A#)) & ", want lo=EFh hi=BEh bank=42h"
                severity error;
        end if;

        report "HW-timing repro (LD24 mem-indirect) testbench: self-check " &
            "complete. An 'error' severity assertion above means the real-" &
            "hardware ED00/01/03/08 corruption/freeze WAS reproduced in " &
            "simulation (confirming the aXfer path shares the same WAIT/SD-" &
            "RAM-arbitration-timing class of bug as PUSH24/POP24's aMSP " &
            "path); no assertion failure above means this specific WAIT/CEN " &
            "mechanism is NOT sufficient to explain the real-hardware " &
            "failure, and a different, aXfer-specific defect should be " &
            "investigated next."
            severity note;

        std.env.stop;
    end process;

end architecture sim;
