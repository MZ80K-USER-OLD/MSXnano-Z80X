--
-- LEA.L self-checking testbench (doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_2026-10-11.md
-- section 21.2 "LEA.L追加、PEA.L不採用")
--
-- DD/FD ED 68 d  -> LEA.L HL,(IX/IY+d)
-- DD/FD ED 69 d  -> LEA.L DE,(IX/IY+d)
--
-- This is the FIRST DD/FD+ED combinable instruction in this project (all
-- prior Z80X24 extensions were single-ED-prefix only, or DD/FD+CB via the
-- pre-existing (IX/IY+d) mechanism). A new, deliberately ISOLATED signal
-- (LeaXY, t80.vhd) remembers "was this ED immediately preceded by DD/FD"
-- without touching XY_State's own reset-on-ED behaviour (which every
-- other ED-prefixed opcode, and the RegAddrA_r/RegAddrB_r "H/L -> IX/IY"
-- redirect mechanism, still relies on - see t80.vhd's LeaXY comment for
-- the full rationale). ED 68/69 are reused Z80 opcode slots (bare
-- "ED 68"/"ED 69" = standard IN L,(C)/OUT (C),L); this testbench verifies
-- BOTH that LEA.L works correctly (M0 bank-forcing, M1/M2 bank carry/
-- borrow, full 24bit wraparound, flag/IX/IY preservation) AND that the
-- pre-existing IN r,(C)/OUT (C),r instructions remain completely
-- unaffected when NOT preceded by DD/FD.
--
-- Instantiates the real T80 core (fpga/G80A/t80.vhd) and runs a small
-- hand assembled program through a flat 64KB combinational memory model
-- (no MMU/banking - same limitation as all previous phase testbenches).
-- Unlike most other testbenches, the memory-write process here does NOT
-- filter on IORQ - "OUT (C),L"'s I/O write and ordinary memory writes
-- both land in the same flat array, which is exactly what Test2 needs to
-- verify OUT (C),r's effect.
--
-- Program layout (see the Python script used to generate the exact byte
-- offsets; labels below match that script's output):
--   0x0000 TEST1: LD BC,0100h; IN L,(C) (bare ED 68, LeaXY="00" since no
--     preceding DD/FD); copies L to RESULT1. mem(0100h) is preloaded
--     with 77h, so RESULT1 must read back 77h - confirms IN r,(C) is
--     completely unaffected by the new LeaXY mechanism.
--   0x0009 TEST2: LD BC,0200h; LD L,55h; OUT (C),L (bare ED 69); reads
--     mem(0200h) back into RESULT2 - confirms OUT (C),r is unaffected.
--   0x0016 TEST3: LD IX,1234h; sets IX_B=99h (deliberately non-zero,
--     while still in M0) via the mode-independent "LD IX_B,A"; then
--     LEA.L HL,(IX+10h). Expect HL=1244h (1234h+10h) and, critically,
--     HL_B=00h (M0 forces bank00h here, NOT a raw copy of IX_B=99h - see
--     t80.vhd's TmpBank comment for why this needed explicit handling
--     beyond reusing the (IX+d) mechanism's own M0 behaviour). IX itself
--     (RESULT3_IX) must stay 1234h (LEA.L must not disturb IX/IY).
--   0x002E TEST4: LD IY,2000h; LEA.L DE,(IY-128) (d=80h, signed -128).
--     Expect DE=1F80h (2000h-128), DE_B=00h (M0).
--   0x003F TEST5: SET_M1; LD IX,0FFF0h; IX_B=01h (IX24=01:FFF0h); LEA.L
--     HL,(IX+20h). Expect a bank CARRY: 01:FFF0h+20h = 02:0010h (matches
--     the same Addr24_AddDisp8 carry behaviour already verified for
--     (IX+d) in tb_phase2_addr24.vhd/tb_phase3_m1_data.vhd).
--   0x0055 TEST6: SET_M2; LD IY,0010h; IY_B=02h (IY24=02:0010h); LEA.L
--     DE,(IY-32h) (d=E0h, signed -32). Expect a bank BORROW:
--     02:0010h-20h = 01:FFF0h.
--   0x006C TEST7: LD IX,0FFFFh; IX_B=FFh (IX24=FF:FFFFh, still M2); LEA.L
--     HL,(IX+1). Expect full 24bit wraparound: FF:FFFFh+1 = 00:0000h.
--   0x0080 TEST8: SCF (arbitrary known flag state) -> F_BEFORE; LEA.L
--     HL,(IX+5) (IX/IX_B irrelevant to this check); -> F_AFTER. Expect
--     F_BEFORE = F_AFTER (LEA.L must not touch any flag).
--   0x0095 DONE: HALT.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd tb_lea_l.vhd
--   ghdl -e --std=08 tb_lea_l
--   ghdl -r --std=08 tb_lea_l
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_lea_l is
end entity tb_lea_l;

architecture sim of tb_lea_l is

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
        16#0000# => x"01", 16#0001# => x"00", 16#0002# => x"01", 16#0003# => x"ED",
        16#0004# => x"68", 16#0005# => x"7D", 16#0006# => x"32", 16#0007# => x"00",
        16#0008# => x"03", 16#0009# => x"01", 16#000A# => x"00", 16#000B# => x"02",
        16#000C# => x"2E", 16#000D# => x"55", 16#000E# => x"ED", 16#000F# => x"69",
        16#0010# => x"3A", 16#0011# => x"00", 16#0012# => x"02", 16#0013# => x"32",
        16#0014# => x"01", 16#0015# => x"03", 16#0016# => x"DD", 16#0017# => x"21",
        16#0018# => x"34", 16#0019# => x"12", 16#001A# => x"3E", 16#001B# => x"99",
        16#001C# => x"ED", 16#001D# => x"05", 16#001E# => x"DD", 16#001F# => x"ED",
        16#0020# => x"68", 16#0021# => x"10", 16#0022# => x"22", 16#0023# => x"02",
        16#0024# => x"03", 16#0025# => x"ED", 16#0026# => x"2C", 16#0027# => x"32",
        16#0028# => x"04", 16#0029# => x"03", 16#002A# => x"DD", 16#002B# => x"22",
        16#002C# => x"05", 16#002D# => x"03", 16#002E# => x"FD", 16#002F# => x"21",
        16#0030# => x"00", 16#0031# => x"20", 16#0032# => x"FD", 16#0033# => x"ED",
        16#0034# => x"69", 16#0035# => x"80", 16#0036# => x"ED", 16#0037# => x"53",
        16#0038# => x"07", 16#0039# => x"03", 16#003A# => x"ED", 16#003B# => x"1C",
        16#003C# => x"32", 16#003D# => x"09", 16#003E# => x"03", 16#003F# => x"ED",
        16#0040# => x"91", 16#0041# => x"DD", 16#0042# => x"21", 16#0043# => x"F0",
        16#0044# => x"FF", 16#0045# => x"3E", 16#0046# => x"01", 16#0047# => x"ED",
        16#0048# => x"05", 16#0049# => x"DD", 16#004A# => x"ED", 16#004B# => x"68",
        16#004C# => x"20", 16#004D# => x"22", 16#004E# => x"0A", 16#004F# => x"03",
        16#0050# => x"ED", 16#0051# => x"2C", 16#0052# => x"32", 16#0053# => x"0C",
        16#0054# => x"03", 16#0055# => x"ED", 16#0056# => x"92", 16#0057# => x"FD",
        16#0058# => x"21", 16#0059# => x"10", 16#005A# => x"00", 16#005B# => x"3E",
        16#005C# => x"02", 16#005D# => x"ED", 16#005E# => x"15", 16#005F# => x"FD",
        16#0060# => x"ED", 16#0061# => x"69", 16#0062# => x"E0", 16#0063# => x"ED",
        16#0064# => x"53", 16#0065# => x"0D", 16#0066# => x"03", 16#0067# => x"ED",
        16#0068# => x"1C", 16#0069# => x"32", 16#006A# => x"0F", 16#006B# => x"03",
        16#006C# => x"DD", 16#006D# => x"21", 16#006E# => x"FF", 16#006F# => x"FF",
        16#0070# => x"3E", 16#0071# => x"FF", 16#0072# => x"ED", 16#0073# => x"05",
        16#0074# => x"DD", 16#0075# => x"ED", 16#0076# => x"68", 16#0077# => x"01",
        16#0078# => x"22", 16#0079# => x"10", 16#007A# => x"03", 16#007B# => x"ED",
        16#007C# => x"2C", 16#007D# => x"32", 16#007E# => x"12", 16#007F# => x"03",
        16#0080# => x"37", 16#0081# => x"F5", 16#0082# => x"C1", 16#0083# => x"79",
        16#0084# => x"32", 16#0085# => x"13", 16#0086# => x"03", 16#0087# => x"DD",
        16#0088# => x"21", 16#0089# => x"00", 16#008A# => x"30", 16#008B# => x"DD",
        16#008C# => x"ED", 16#008D# => x"68", 16#008E# => x"05", 16#008F# => x"F5",
        16#0090# => x"C1", 16#0091# => x"79", 16#0092# => x"32", 16#0093# => x"14",
        16#0094# => x"03", 16#0095# => x"76",
        -- Test1's IN L,(C) source byte (BC=0100h points here)
        16#0100# => x"77",
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
            bank_rst => bank_rst,
            A_Bank => A_Bank,
            MC => MC,
            TS => TS,
            IntCycle_n => IntCycle_n,
            IntE => IntE,
            Stop => Stop);

    -- Flat combinational memory model (M0-style, no MMU): see
    -- tb_phase3_m1_data.vhd for the detailed rationale behind the
    -- DI_live/DInst/DI split. Unlike most other testbenches, the write
    -- capture below does NOT filter on IORQ - "OUT (C),L"'s I/O write
    -- must land in this same flat array for Test2 to verify it.
    DI_live <= mem(to_integer(unsigned(A)));
    DInst <= DI_live;

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
            if Write = '1' then
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
        -- Single checkpoint at the very end (A=0x0095, the HALT opcode):
        -- every test's result has already been copied into its own
        -- RESULT* memory location by this point, matching the established
        -- settle-wait convention (small delay to let continuous
        -- assignments finish propagating).
        wait until A = x"0095" and M1_n = '0';
        wait for 1 ns;

        -- ---- Test1: bare ED 68 (IN L,(C)) must be unaffected - L must
        -- read back the preloaded mem(0100h)=77h via BC-addressed I/O. ----
        assert mem(16#0300#) = x"77"
            report "LEA.L: Test1 bare IN L,(C) must read 77h via BC=0100h, got " & to_hstring(mem(16#0300#))
            severity failure;

        -- ---- Test2: bare ED 69 (OUT (C),L) must be unaffected - L=55h
        -- must be written to mem(0200h) via BC-addressed I/O. ----
        assert mem(16#0301#) = x"55"
            report "LEA.L: Test2 bare OUT (C),L must write 55h to BC=0200h, got " & to_hstring(mem(16#0301#))
            severity failure;

        -- ---- Test3: LEA.L HL,(IX+10h), M0. HL=1244h, HL_B FORCED to 00h
        -- (despite IX_B=99h - M0 must not leak a raw bank byte), IX
        -- itself unchanged (1234h). ----
        assert mem(16#0302#) = x"44" and mem(16#0303#) = x"12"
            report "LEA.L: Test3 HL must be 1244h, got " & to_hstring(mem(16#0303#)) & to_hstring(mem(16#0302#))
            severity failure;
        assert mem(16#0304#) = x"00"
            report "LEA.L: Test3 HL_B must be forced to 00h in M0 (despite IX_B=99h), got " & to_hstring(mem(16#0304#))
            severity failure;
        assert mem(16#0305#) = x"34" and mem(16#0306#) = x"12"
            report "LEA.L: Test3 IX must stay unchanged at 1234h, got " & to_hstring(mem(16#0306#)) & to_hstring(mem(16#0305#))
            severity failure;

        -- ---- Test4: LEA.L DE,(IY-128), M0. DE=1F80h, DE_B=00h. ----
        assert mem(16#0307#) = x"80" and mem(16#0308#) = x"1F"
            report "LEA.L: Test4 DE must be 1F80h, got " & to_hstring(mem(16#0308#)) & to_hstring(mem(16#0307#))
            severity failure;
        assert mem(16#0309#) = x"00"
            report "LEA.L: Test4 DE_B must be 00h, got " & to_hstring(mem(16#0309#))
            severity failure;

        -- ---- Test5: LEA.L HL,(IX+20h), M1, bank CARRY: 01:FFF0h+20h ->
        -- 02:0010h. ----
        assert mem(16#030A#) = x"10" and mem(16#030B#) = x"00"
            report "LEA.L: Test5 HL must be 0010h (bank carry), got " & to_hstring(mem(16#030B#)) & to_hstring(mem(16#030A#))
            severity failure;
        assert mem(16#030C#) = x"02"
            report "LEA.L: Test5 HL_B must carry to 02h, got " & to_hstring(mem(16#030C#))
            severity failure;

        -- ---- Test6: LEA.L DE,(IY-20h), M2, bank BORROW: 02:0010h-20h ->
        -- 01:FFF0h. ----
        assert mem(16#030D#) = x"F0" and mem(16#030E#) = x"FF"
            report "LEA.L: Test6 DE must be FFF0h (bank borrow), got " & to_hstring(mem(16#030E#)) & to_hstring(mem(16#030D#))
            severity failure;
        assert mem(16#030F#) = x"01"
            report "LEA.L: Test6 DE_B must borrow to 01h, got " & to_hstring(mem(16#030F#))
            severity failure;

        -- ---- Test7: LEA.L HL,(IX+1), M2, full 24bit wraparound:
        -- FF:FFFFh+1 -> 00:0000h. ----
        assert mem(16#0310#) = x"00" and mem(16#0311#) = x"00"
            report "LEA.L: Test7 HL must wrap to 0000h, got " & to_hstring(mem(16#0311#)) & to_hstring(mem(16#0310#))
            severity failure;
        assert mem(16#0312#) = x"00"
            report "LEA.L: Test7 HL_B must wrap to 00h, got " & to_hstring(mem(16#0312#))
            severity failure;

        -- ---- Test8: F register unchanged by LEA.L. ----
        assert mem(16#0313#) = mem(16#0314#)
            report "LEA.L: Test8 F must be unchanged by LEA.L, before=" & to_hstring(mem(16#0313#)) &
                " after=" & to_hstring(mem(16#0314#))
            severity failure;

        report "LEA.L testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

end architecture sim;
