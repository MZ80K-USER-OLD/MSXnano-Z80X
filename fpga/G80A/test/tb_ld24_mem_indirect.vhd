--
-- LD24 memory-indirect self-checking testbench: ED00/01/03/08
-- (doc/jpn/24bitメモリロード追加命令案.md;
--  doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_不足転送命令追加案_2026-10-19.md;
--  doc/jpn/OLD/MSX_T80_24bit化_命令一覧_V11_拡張案_2026-10-19.csv)
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and verifies the 4
-- newly implemented ED-prefixed opcodes:
--
--   ED 00  LD24 BC,(HL)   3byte read  mem[HL24..HL24+2] -> BC24 (bank_bc_r)
--   ED 01  LD24 DE,(HL)   3byte read  mem[HL24..HL24+2] -> DE24 (bank_de_r)
--   ED 03  LD24 (HL),BC   3byte write BC24 (bank_bc_r) -> mem[HL24..HL24+2]
--   ED 08  LD24 (HL),DE   3byte write DE24 (bank_de_r) -> mem[HL24..HL24+2]
--
-- These were added specifically to help diagnose the PUSH24/POP24 bank-
-- boundary bug (see PUSH24_POP24_bank境界またぎバグ_調査レポート.md):
-- unlike PUSH24/POP24 (which route through the dedicated MSP24/aMSP
-- address source and bank_msp_r's own always-active auto-increment/
-- decrement), these 4 opcodes exercise a COMPLETELY INDEPENDENT 24bit
-- sequential-access code path (the new aXfer address source + TmpAddr/
-- TmpBank "xfer pointer", gated by mode24_r like ordinary (HL) accesses)
-- while reusing the exact same "TState=2, Wait_n=1" WAIT-sensitive
-- trigger idiom under investigation. If the real-hardware PUSH24/POP24
-- bug is actually in the SDRAM/WAIT handshake (top.v/memory.v) rather
-- than CPU-internal address-source-specific logic, these opcodes should
-- reproduce the identical data-corruption symptom on real hardware; if
-- it is specific to the MSP24/aMSP path, these should NOT reproduce it.
--
-- Like tb_phase9_push24_pop24.vhd, this uses a true (bank,address)-
-- indexed sparse memory model (banks 00h/01h/02h/FFh only - the ones this
-- test actually touches) so that reads can only reconstruct the correct
-- value if every byte genuinely used the correct physical 24bit address
-- on the bus, on both the read and the write side.
--
-- Covers, for both LOAD (ED00/01) and STORE (ED03/08):
--   - normal (non-boundary-crossing) 3byte access (T1-T4)
--   - 64KB bank-boundary crossing, 01:FFFE -> carries into 02:0000h,
--     exactly the same crossing implicated in the PUSH24/POP24 bug (T5/T6)
--   - full 24bit FFFFFFh wraparound (FFh:FFFE -> carries into 00h:0000,
--     landing on this very program's own first byte - T9)
--   - HL24 (the register the address is taken FROM) is left completely
--     unchanged by any of these opcodes (T1/T2/T5 - proves the "xfer
--     pointer" is a true temporary, never written back into HL/bank_hl_r)
--   - F (flags) register is completely unaffected (T_F)
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_ld24_mem_indirect.vhd
--   ghdl -e --std=08 tb_ld24_mem_indirect
--   ghdl -r --std=08 tb_ld24_mem_indirect
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_ld24_mem_indirect is
end entity tb_ld24_mem_indirect;

architecture sim of tb_ld24_mem_indirect is

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

    -- Hand assembled test program (generated with a small Python helper to
    -- keep byte offsets correct - see this file's header comment style
    -- precedent in tb_phase9_push24_pop24.vhd). Lives entirely in bank 00h.
    -- Program length: 196 (0x00C4) bytes, starting at 0000h. Dump area
    -- starts at 5000h (distinct from tb_phase9's 4000h area, so this
    -- testbench can never collide with that one's memval()-asserted
    -- addresses if ever combined in one simulation).
    signal mem : mem_array := (
        16#0000# => x"ED", 16#0001# => x"91", 16#0002# => x"21", 16#0003# => x"00",
        16#0004# => x"90", 16#0005# => x"3E", 16#0006# => x"01", 16#0007# => x"ED",
        16#0008# => x"24", 16#0009# => x"01", 16#000A# => x"00", 16#000B# => x"00",
        16#000C# => x"3E", 16#000D# => x"00", 16#000E# => x"ED", 16#000F# => x"04",
        16#0010# => x"ED", 16#0011# => x"00", 16#0012# => x"ED", 16#0013# => x"43",
        16#0014# => x"00", 16#0015# => x"50", 16#0016# => x"ED", 16#0017# => x"0C",
        16#0018# => x"32", 16#0019# => x"02", 16#001A# => x"50", 16#001B# => x"22",
        16#001C# => x"03", 16#001D# => x"50", 16#001E# => x"ED", 16#001F# => x"2C",
        16#0020# => x"32", 16#0021# => x"05", 16#0022# => x"50", 16#0023# => x"21",
        16#0024# => x"10", 16#0025# => x"90", 16#0026# => x"3E", 16#0027# => x"01",
        16#0028# => x"ED", 16#0029# => x"24", 16#002A# => x"11", 16#002B# => x"00",
        16#002C# => x"00", 16#002D# => x"3E", 16#002E# => x"00", 16#002F# => x"ED",
        16#0030# => x"14", 16#0031# => x"ED", 16#0032# => x"01", 16#0033# => x"ED",
        16#0034# => x"53", 16#0035# => x"10", 16#0036# => x"50", 16#0037# => x"ED",
        16#0038# => x"1C", 16#0039# => x"32", 16#003A# => x"12", 16#003B# => x"50",
        16#003C# => x"22", 16#003D# => x"13", 16#003E# => x"50", 16#003F# => x"ED",
        16#0040# => x"2C", 16#0041# => x"32", 16#0042# => x"15", 16#0043# => x"50",
        16#0044# => x"21", 16#0045# => x"20", 16#0046# => x"90", 16#0047# => x"3E",
        16#0048# => x"01", 16#0049# => x"ED", 16#004A# => x"24", 16#004B# => x"01",
        16#004C# => x"34", 16#004D# => x"12", 16#004E# => x"3E", 16#004F# => x"EE",
        16#0050# => x"ED", 16#0051# => x"04", 16#0052# => x"ED", 16#0053# => x"03",
        16#0054# => x"21", 16#0055# => x"30", 16#0056# => x"90", 16#0057# => x"3E",
        16#0058# => x"01", 16#0059# => x"ED", 16#005A# => x"24", 16#005B# => x"11",
        16#005C# => x"78", 16#005D# => x"56", 16#005E# => x"3E", 16#005F# => x"9A",
        16#0060# => x"ED", 16#0061# => x"14", 16#0062# => x"ED", 16#0063# => x"08",
        16#0064# => x"21", 16#0065# => x"FE", 16#0066# => x"FF", 16#0067# => x"3E",
        16#0068# => x"01", 16#0069# => x"ED", 16#006A# => x"24", 16#006B# => x"01",
        16#006C# => x"00", 16#006D# => x"00", 16#006E# => x"3E", 16#006F# => x"00",
        16#0070# => x"ED", 16#0071# => x"04", 16#0072# => x"ED", 16#0073# => x"00",
        16#0074# => x"ED", 16#0075# => x"43", 16#0076# => x"20", 16#0077# => x"50",
        16#0078# => x"ED", 16#0079# => x"0C", 16#007A# => x"32", 16#007B# => x"22",
        16#007C# => x"50", 16#007D# => x"22", 16#007E# => x"23", 16#007F# => x"50",
        16#0080# => x"ED", 16#0081# => x"2C", 16#0082# => x"32", 16#0083# => x"25",
        16#0084# => x"50", 16#0085# => x"21", 16#0086# => x"FE", 16#0087# => x"FF",
        16#0088# => x"3E", 16#0089# => x"01", 16#008A# => x"ED", 16#008B# => x"24",
        16#008C# => x"01", 16#008D# => x"EF", 16#008E# => x"BE", 16#008F# => x"3E",
        16#0090# => x"42", 16#0091# => x"ED", 16#0092# => x"04", 16#0093# => x"ED",
        16#0094# => x"03", 16#0095# => x"21", 16#0096# => x"FE", 16#0097# => x"FF",
        16#0098# => x"3E", 16#0099# => x"FF", 16#009A# => x"ED", 16#009B# => x"24",
        16#009C# => x"11", 16#009D# => x"00", 16#009E# => x"00", 16#009F# => x"3E",
        16#00A0# => x"00", 16#00A1# => x"ED", 16#00A2# => x"14", 16#00A3# => x"ED",
        16#00A4# => x"01", 16#00A5# => x"ED", 16#00A6# => x"53", 16#00A7# => x"30",
        16#00A8# => x"50", 16#00A9# => x"ED", 16#00AA# => x"1C", 16#00AB# => x"32",
        16#00AC# => x"32", 16#00AD# => x"50", 16#00AE# => x"F5", 16#00AF# => x"C1",
        16#00B0# => x"79", 16#00B1# => x"32", 16#00B2# => x"40", 16#00B3# => x"50",
        16#00B4# => x"21", 16#00B5# => x"00", 16#00B6# => x"90", 16#00B7# => x"3E",
        16#00B8# => x"01", 16#00B9# => x"ED", 16#00BA# => x"24", 16#00BB# => x"ED",
        16#00BC# => x"00", 16#00BD# => x"F5", 16#00BE# => x"C1", 16#00BF# => x"79",
        16#00C0# => x"32", 16#00C1# => x"41", 16#00C2# => x"50", 16#00C3# => x"76",
        others => x"00");

    -- Bank 01h: sparse 64KB array, holds the T1/T2 read source patterns
    -- (preloaded below), and receives T3/T4/T6's write results. Bank 02h:
    -- only ever receives the BANK-byte carry from T5/T6's boundary
    -- crossing at 01:FFFE. Bank FFh: holds T9's FFFFFFh-wrap read source
    -- pattern at FFFEh/FFFFh (its own BANK byte, at the wrapped-around
    -- 00h:0000h address, is this very program's own first byte - see
    -- memval()/T9's assertion below, which reads 'mem' directly instead
    -- of hardcoding a duplicate literal).
    signal mem01 : mem_array := (
        16#9000# => x"AA", 16#9001# => x"99", 16#9002# => x"05",  -- T1 source (LOW,HIGH,BANK)
        16#9010# => x"11", 16#9011# => x"22", 16#9012# => x"33",  -- T2 source
        16#FFFE# => x"CD", 16#FFFF# => x"AB",                     -- T5 source (LOW,HIGH); BANK at 02:0000 below
        others => x"00");
    signal mem02 : mem_array := (
        16#0000# => x"07",  -- T5 source BANK byte (01:FFFE carries here)
        others => x"00");
    signal memFF : mem_array := (
        16#FFFE# => x"44", 16#FFFF# => x"33",  -- T9 source (LOW,HIGH); BANK wraps to 00h:0000h (mem(0))
        others => x"00");

    impure function memval(bank : std_logic_vector(7 downto 0); addr : std_logic_vector(15 downto 0)) return std_logic_vector is
    begin
        case bank is
            when x"00" => return mem(to_integer(unsigned(addr)));
            when x"01" => return mem01(to_integer(unsigned(addr)));
            when x"02" => return mem02(to_integer(unsigned(addr)));
            when x"FF" => return memFF(to_integer(unsigned(addr)));
            when others =>
                return x"00";
        end case;
    end function;

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

    DI_live <= memval(A_Bank, A);
    DInst <= DI_live;

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
            if IORQ = '0' and Write = '1' then
                case A_Bank is
                when x"00" => mem(to_integer(unsigned(A))) <= DO;
                when x"01" => mem01(to_integer(unsigned(A))) <= DO;
                when x"02" => mem02(to_integer(unsigned(A))) <= DO;
                when x"FF" => memFF(to_integer(unsigned(A))) <= DO;
                when others =>
                    report "tb_ld24_mem_indirect: unexpected A_Bank=" & to_hstring(A_Bank) &
                        " write, not covered by the sparse memory model" severity failure;
                end case;
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

        -- ---- T1: ED00 LD24 BC,(HL), normal (no boundary crossing) ----
        -- mem01[9000h]=AAh(LOW) -> C, mem01[9001h]=99h(HIGH) -> B,
        -- mem01[9002h]=05h(BANK) -> bank_bc_r. Expect BC24=05:99AAh.
        assert memval(x"00", x"5000") = x"AA" and memval(x"00", x"5001") = x"99"
            report "T1: ED00 LD24 BC,(HL) low/high mismatch, got lo=" & to_hstring(memval(x"00", x"5000")) &
                " hi=" & to_hstring(memval(x"00", x"5001")) & ", expected lo=AAh hi=99h"
            severity failure;
        assert memval(x"00", x"5002") = x"05"
            report "T1: ED00 LD24 BC,(HL) BANK-byte mismatch, got " & to_hstring(memval(x"00", x"5002")) &
                ", expected 05h"
            severity failure;
        -- HL24 (the address source) must be completely unchanged (still 01:9000h)
        assert memval(x"00", x"5003") = x"00" and memval(x"00", x"5004") = x"90"
            report "T1: ED00 LD24 BC,(HL) must leave HL unchanged (9000h), got " &
                to_hstring(memval(x"00", x"5004")) & to_hstring(memval(x"00", x"5003"))
            severity failure;
        assert memval(x"00", x"5005") = x"01"
            report "T1: ED00 LD24 BC,(HL) must leave bank_hl_r unchanged (01h), got " &
                to_hstring(memval(x"00", x"5005"))
            severity failure;

        -- ---- T2: ED01 LD24 DE,(HL), normal (no boundary crossing) ----
        -- mem01[9010h]=11h(LOW) -> E, mem01[9011h]=22h(HIGH) -> D,
        -- mem01[9012h]=33h(BANK) -> bank_de_r. Expect DE24=33:2211h.
        assert memval(x"00", x"5010") = x"11" and memval(x"00", x"5011") = x"22"
            report "T2: ED01 LD24 DE,(HL) low/high mismatch, got lo=" & to_hstring(memval(x"00", x"5010")) &
                " hi=" & to_hstring(memval(x"00", x"5011")) & ", expected lo=11h hi=22h"
            severity failure;
        assert memval(x"00", x"5012") = x"33"
            report "T2: ED01 LD24 DE,(HL) BANK-byte mismatch, got " & to_hstring(memval(x"00", x"5012")) &
                ", expected 33h"
            severity failure;
        assert memval(x"00", x"5013") = x"10" and memval(x"00", x"5014") = x"90"
            report "T2: ED01 LD24 DE,(HL) must leave HL unchanged (9010h), got " &
                to_hstring(memval(x"00", x"5014")) & to_hstring(memval(x"00", x"5013"))
            severity failure;
        assert memval(x"00", x"5015") = x"01"
            report "T2: ED01 LD24 DE,(HL) must leave bank_hl_r unchanged (01h), got " &
                to_hstring(memval(x"00", x"5015"))
            severity failure;

        -- ---- T3: ED03 LD24 (HL),BC write, normal (no boundary crossing) ----
        -- BC24=EE:1234h (B=12h,C=34h) written to mem01[9020..9022h] as
        -- LOW(C=34h), HIGH(B=12h), BANK(EEh), in that order.
        assert memval(x"01", x"9020") = x"34"
            report "T3: ED03 LD24 (HL),BC LOW-byte write mismatch at 01:9020h, got " &
                to_hstring(memval(x"01", x"9020")) & ", expected 34h"
            severity failure;
        assert memval(x"01", x"9021") = x"12"
            report "T3: ED03 LD24 (HL),BC HIGH-byte write mismatch at 01:9021h, got " &
                to_hstring(memval(x"01", x"9021")) & ", expected 12h"
            severity failure;
        assert memval(x"01", x"9022") = x"EE"
            report "T3: ED03 LD24 (HL),BC BANK-byte write mismatch at 01:9022h, got " &
                to_hstring(memval(x"01", x"9022")) & ", expected EEh"
            severity failure;

        -- ---- T4: ED08 LD24 (HL),DE write, normal (no boundary crossing) ----
        -- DE24=9A:5678h (D=56h,E=78h) written to mem01[9030..9032h].
        assert memval(x"01", x"9030") = x"78"
            report "T4: ED08 LD24 (HL),DE LOW-byte write mismatch at 01:9030h, got " &
                to_hstring(memval(x"01", x"9030")) & ", expected 78h"
            severity failure;
        assert memval(x"01", x"9031") = x"56"
            report "T4: ED08 LD24 (HL),DE HIGH-byte write mismatch at 01:9031h, got " &
                to_hstring(memval(x"01", x"9031")) & ", expected 56h"
            severity failure;
        assert memval(x"01", x"9032") = x"9A"
            report "T4: ED08 LD24 (HL),DE BANK-byte write mismatch at 01:9032h, got " &
                to_hstring(memval(x"01", x"9032")) & ", expected 9Ah"
            severity failure;

        -- ---- T5: ED00 64KB bank-boundary crossing read ----
        -- HL24=01:FFFEh. mem01[FFFEh]=CDh(LOW), mem01[FFFFh]=ABh(HIGH),
        -- mem02[0000h]=07h(BANK, CARRIES into bank 02h!). Expect
        -- BC24=07:ABCDh. This is the EXACT SAME 64KB crossing implicated
        -- in the PUSH24/POP24 bank-boundary bug.
        assert memval(x"00", x"5020") = x"CD" and memval(x"00", x"5021") = x"AB"
            report "T5: ED00 boundary-crossing low/high mismatch, got lo=" & to_hstring(memval(x"00", x"5020")) &
                " hi=" & to_hstring(memval(x"00", x"5021")) & ", expected lo=CDh hi=ABh"
            severity failure;
        assert memval(x"00", x"5022") = x"07"
            report "T5: ED00 boundary-crossing BANK-byte mismatch (must carry to bank 02h), got " &
                to_hstring(memval(x"00", x"5022")) & ", expected 07h"
            severity failure;
        -- HL24 itself must NOT carry - it stays at 01:FFFEh exactly
        -- (proves the carry only ever happened on the temporary xfer
        -- pointer, never written back into HL/bank_hl_r).
        assert memval(x"00", x"5023") = x"FE" and memval(x"00", x"5024") = x"FF"
            report "T5: ED00 boundary-crossing must leave HL unchanged (FFFEh), got " &
                to_hstring(memval(x"00", x"5024")) & to_hstring(memval(x"00", x"5023"))
            severity failure;
        assert memval(x"00", x"5025") = x"01"
            report "T5: ED00 boundary-crossing must leave bank_hl_r unchanged (01h, NOT carried to 02h), got " &
                to_hstring(memval(x"00", x"5025"))
            severity failure;

        -- ---- T6: ED03 64KB bank-boundary crossing write ----
        -- HL24=01:FFFEh, BC24=42:BEEFh (B=BEh,C=EFh) written as
        -- LOW(EFh)@01:FFFEh, HIGH(BEh)@01:FFFFh, BANK(42h)@02:0000h
        -- (CARRIES into bank 02h!).
        assert memval(x"01", x"FFFE") = x"EF"
            report "T6: ED03 boundary-crossing LOW-byte write mismatch at 01:FFFEh, got " &
                to_hstring(memval(x"01", x"FFFE")) & ", expected EFh"
            severity failure;
        assert memval(x"01", x"FFFF") = x"BE"
            report "T6: ED03 boundary-crossing HIGH-byte write mismatch at 01:FFFFh, got " &
                to_hstring(memval(x"01", x"FFFF")) & ", expected BEh"
            severity failure;
        assert memval(x"02", x"0000") = x"42"
            report "T6: ED03 boundary-crossing BANK-byte write must carry to 02:0000h, got " &
                to_hstring(memval(x"02", x"0000")) & ", expected 42h"
            severity failure;

        -- ---- T9: ED01 full 24bit FFFFFFh wraparound read ----
        -- HL24=FFh:FFFEh. memFF[FFFEh]=44h(LOW), memFF[FFFFh]=33h(HIGH),
        -- and the 3rd byte's address itself WRAPS (FFFFFFh+1=000000h)
        -- into bank 00h address 0000h - this very program's own first
        -- byte (mem(0), compared live below rather than hardcoding a
        -- duplicate literal, so this assertion can never go stale if the
        -- program is ever edited).
        assert memval(x"00", x"5030") = x"44" and memval(x"00", x"5031") = x"33"
            report "T9: ED01 FFFFFFh-wrap low/high mismatch, got lo=" & to_hstring(memval(x"00", x"5030")) &
                " hi=" & to_hstring(memval(x"00", x"5031")) & ", expected lo=44h hi=33h"
            severity failure;
        assert memval(x"00", x"5032") = mem(0)
            report "T9: ED01 FFFFFFh-wrap BANK-byte must carry to 00h:0000h (this program's own " &
                "first byte, " & to_hstring(mem(0)) & "), got " & to_hstring(memval(x"00", x"5032"))
            severity failure;

        -- ---- T_F: F (flags) register unaffected by ED00 ----
        assert memval(x"00", x"5040") = memval(x"00", x"5041")
            report "T_F: ED00 must leave F unchanged, F_before=" & to_hstring(memval(x"00", x"5040")) &
                " F_after=" & to_hstring(memval(x"00", x"5041"))
            severity failure;

        report "LD24 memory-indirect (ED00/01/03/08) testbench: all assertions passed" severity note;

        std.env.stop;
        wait;
    end process;

end architecture sim;
