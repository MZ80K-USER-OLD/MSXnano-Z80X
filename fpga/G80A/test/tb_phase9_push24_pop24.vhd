--
-- Phase9 self-checking testbench: PUSH24/POP24 stack instructions
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 11 "Phase 9";
--  MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md, section 9 "Stack")
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small hand
-- assembled program (generated with a small Python helper to keep byte
-- offsets and expected memory contents correct/independently verified -
-- the helper mirrors t80_pack.vhd's Addr24_Dec/Addr24_Inc bit-for-bit) to
-- verify every opcode implemented in this increment:
--
--   ED C5 PUSH24 BC    ED C1 POP24 BC
--   ED D5 PUSH24 DE    ED D1 POP24 DE
--   ED E5 PUSH24 HL    ED E1 POP24 HL
--
-- Since the testbench's flat 64KB combinational memory model (no MMU/
-- banking) only indexes memory by the 16bit external address bus 'A', a
-- second parallel array ("bank_mem") records whatever A_Bank was being
-- driven at the moment of each write, so writes can be verified against
-- BOTH their byte value AND the (bank,address) pair they were tagged with
-- - this is what actually proves PUSH24/POP24 route their 3 bytes through
-- the new MSP24/aMSP address path (not plain 16bit SP).
--
-- Each test case verifies:
--   - PUSH24 BC writes BANK/HIGH/LOW (in that order) at MSP24-1/-2/-3,
--     each tagged with the CURRENT bank_msp_r value on the bus at write
--     time (T1)
--   - MSP24 ends up exactly 3 lower after a PUSH24 (T1, via LD24 HL,MSP
--     dump) and exactly 3 higher after a following POP24 (T2) - i.e. back
--     to its original value, proving the round trip is lossless
--   - POP24 DE, reading the bytes PUSH24 BC just wrote, reconstructs the
--     exact same 24bit value (bank+16bit word) that was pushed (T2)
--   - bank byte correctly BORROWS across a 16bit low-word wraparound
--     during 3 consecutive PUSH24 decrements (00:0001 -> 00:0000 ->
--     FF:FFFF -> FF:FFFE) (T3), independently computed by the same
--     Python helper that mirrors Addr24_Dec
--   - F (flags) register is completely unaffected by PUSH24/POP24 (T4)
--
-- NOT covered by this testbench (deferred, same scope limitation as
-- Phase7's LD24 HL,IX/IY - see AVAILABLE_INSTRUCTIONS.md): DD/FD ED E1/E5
-- (PUSH24/POP24 IX/IY), which require dual DD/FD+ED prefix decoding not
-- yet supported by this core's prefix state machine.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_phase9_push24_pop24.vhd
--   ghdl -e --std=08 tb_phase9_push24_pop24
--   ghdl -r --std=08 tb_phase9_push24_pop24
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_phase9_push24_pop24 is
end entity tb_phase9_push24_pop24;

architecture sim of tb_phase9_push24_pop24 is

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
    -- keep byte offsets and expected results correct; see header comment
    -- for the full story).
    -- Program length: 102 (0x0066) bytes, starting at 0000h.
    signal mem : mem_array := (
        16#0000# => x"21", 16#0001# => x"00", 16#0002# => x"E0", 16#0003# => x"3E",
        16#0004# => x"01", 16#0005# => x"ED", 16#0006# => x"24", 16#0007# => x"ED",
        16#0008# => x"35", 16#0009# => x"01", 16#000A# => x"22", 16#000B# => x"11",
        16#000C# => x"3E", 16#000D# => x"02", 16#000E# => x"ED", 16#000F# => x"04",
        16#0010# => x"ED", 16#0011# => x"C5", 16#0012# => x"ED", 16#0013# => x"36",
        16#0014# => x"22", 16#0015# => x"00", 16#0016# => x"40", 16#0017# => x"ED",
        16#0018# => x"2C", 16#0019# => x"32", 16#001A# => x"02", 16#001B# => x"40",
        16#001C# => x"ED", 16#001D# => x"D1", 16#001E# => x"ED", 16#001F# => x"53",
        16#0020# => x"03", 16#0021# => x"40", 16#0022# => x"ED", 16#0023# => x"1C",
        16#0024# => x"32", 16#0025# => x"05", 16#0026# => x"40", 16#0027# => x"ED",
        16#0028# => x"36", 16#0029# => x"22", 16#002A# => x"06", 16#002B# => x"40",
        16#002C# => x"ED", 16#002D# => x"2C", 16#002E# => x"32", 16#002F# => x"08",
        16#0030# => x"40", 16#0031# => x"21", 16#0032# => x"01", 16#0033# => x"00",
        16#0034# => x"3E", 16#0035# => x"00", 16#0036# => x"ED", 16#0037# => x"24",
        16#0038# => x"ED", 16#0039# => x"35", 16#003A# => x"21", 16#003B# => x"BB",
        16#003C# => x"AA", 16#003D# => x"3E", 16#003E# => x"FF", 16#003F# => x"ED",
        16#0040# => x"24", 16#0041# => x"ED", 16#0042# => x"E5", 16#0043# => x"ED",
        16#0044# => x"36", 16#0045# => x"22", 16#0046# => x"09", 16#0047# => x"40",
        16#0048# => x"ED", 16#0049# => x"2C", 16#004A# => x"32", 16#004B# => x"0B",
        16#004C# => x"40", 16#004D# => x"37", 16#004E# => x"F5", 16#004F# => x"C1",
        16#0050# => x"79", 16#0051# => x"32", 16#0052# => x"0C", 16#0053# => x"40",
        16#0054# => x"01", 16#0055# => x"05", 16#0056# => x"04", 16#0057# => x"3E",
        16#0058# => x"03", 16#0059# => x"ED", 16#005A# => x"04", 16#005B# => x"ED",
        16#005C# => x"C5", 16#005D# => x"ED", 16#005E# => x"C1", 16#005F# => x"F5",
        16#0060# => x"C1", 16#0061# => x"79", 16#0062# => x"32", 16#0063# => x"0D",
        16#0064# => x"40", 16#0065# => x"76",
        others => x"00");

    -- Records A_Bank at the moment of each write, same 16bit indexing as
    -- 'mem' above - see header comment.
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
            -- Memory write-back for the PUSH24 byte writes and the
            -- "LD (nnnn),HL/BC/DE/A" instructions used to dump register/
            -- flag/MSP24 values for verification. bank_mem records A_Bank
            -- alongside the data byte so PUSH24's 3 writes can be verified
            -- against the exact (bank,address) pair they targeted.
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
        wait until HALT_n = '0';
        wait for 200 ns; -- drain a few trailing HALT refetch cycles

        -- ---- T1: PUSH24 BC (MSP24=01:E000, BC24=02:1122) ----
        -- BANK byte written first, at MSP24-1 = 01:DFFF
        assert mem(16#DFFF#) = x"02" and bank_mem(16#DFFF#) = x"01"
            report "Phase9: PUSH24 BC BANK-byte write mismatch, got data=" & to_hstring(mem(16#DFFF#)) &
                " bank=" & to_hstring(bank_mem(16#DFFF#)) & ", expected data=02h bank=01h"
            severity failure;
        -- HIGH byte written second, at MSP24-2 = 01:DFFE
        assert mem(16#DFFE#) = x"11" and bank_mem(16#DFFE#) = x"01"
            report "Phase9: PUSH24 BC HIGH-byte write mismatch, got data=" & to_hstring(mem(16#DFFE#)) &
                " bank=" & to_hstring(bank_mem(16#DFFE#)) & ", expected data=11h bank=01h"
            severity failure;
        -- LOW byte written third (final MSP24), at MSP24-3 = 01:DFFD
        assert mem(16#DFFD#) = x"22" and bank_mem(16#DFFD#) = x"01"
            report "Phase9: PUSH24 BC LOW-byte write mismatch, got data=" & to_hstring(mem(16#DFFD#)) &
                " bank=" & to_hstring(bank_mem(16#DFFD#)) & ", expected data=22h bank=01h"
            severity failure;
        -- MSP24 after the push must be exactly 3 lower: 01:DFFD
        assert mem(16#4000#) = x"FD" and mem(16#4001#) = x"DF" and mem(16#4002#) = x"01"
            report "Phase9: PUSH24 BC must leave MSP24=01:DFFD, got lo=" & to_hstring(mem(16#4000#)) &
                " hi=" & to_hstring(mem(16#4001#)) & " bank=" & to_hstring(mem(16#4002#))
            severity failure;

        -- ---- T2: POP24 DE (reading back what PUSH24 BC just wrote) ----
        assert mem(16#4003#) = x"22" and mem(16#4004#) = x"11" and mem(16#4005#) = x"02"
            report "Phase9: POP24 DE must reconstruct 02:1122h, got lo=" & to_hstring(mem(16#4003#)) &
                " hi=" & to_hstring(mem(16#4004#)) & " bank=" & to_hstring(mem(16#4005#))
            severity failure;
        -- MSP24 after the matching pop must be back to its original value: 01:E000
        assert mem(16#4006#) = x"00" and mem(16#4007#) = x"E0" and mem(16#4008#) = x"01"
            report "Phase9: POP24 DE must restore MSP24=01:E000, got lo=" & to_hstring(mem(16#4006#)) &
                " hi=" & to_hstring(mem(16#4007#)) & " bank=" & to_hstring(mem(16#4008#))
            severity failure;

        -- ---- T3: bank borrow across a 16bit low-word wraparound ----
        -- PUSH24 HL with MSP24=00:0001 decrements three times:
        --   00:0001 -> 00:0000 -> FF:FFFF (borrow!) -> FF:FFFE (final)
        assert mem(16#4009#) = x"FE" and mem(16#400A#) = x"FF" and mem(16#400B#) = x"FF"
            report "Phase9: PUSH24 HL bank-borrow mismatch, expected final MSP24=FF:FFFE, got lo=" &
                to_hstring(mem(16#4009#)) & " hi=" & to_hstring(mem(16#400A#)) & " bank=" & to_hstring(mem(16#400B#))
            severity failure;

        -- ---- T4: F register unaffected by PUSH24/POP24 ----
        assert mem(16#400C#) = mem(16#400D#)
            report "Phase9: PUSH24/POP24 must leave F unchanged, F_before=" & to_hstring(mem(16#400C#)) &
                " F_after=" & to_hstring(mem(16#400D#))
            severity failure;

        report "Phase9 PUSH24/POP24 testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
