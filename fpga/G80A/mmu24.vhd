--
-- MMU24 : Phase4 "MMU_DATA" logical->physical bank translation
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 6 "Phase 4")
--
-- A 256x8 LUT/distributed-memory translation table, indexed by the 8bit
-- logical bank byte (A23:A16, i.e. CPU core's A_Bank from Phase3), that
-- produces the physical bank byte used for the actual memory access. The
-- lookup itself (Logical_Bank -> Physical_Bank) is purely combinational
-- ("非同期lookup"): it never adds a WAIT/T-state of its own.
--
-- Z80 I/O ports (decoded by the caller and passed in via Port_Sel):
--   F0h : MMU_INDEX - 8bit index register (which table entry F1h targets)
--   F1h : MMU_DATA  - read/write MMU_DATA[MMU_INDEX]
--
-- MMU_DATA[00h] is fixed at 00h: logical bank 00h always aliases the
-- existing MSX-compatible 64KB space, and writes targeting index 00h are
-- ignored (per Phase4: "MMU_DATA[00]=00h固定...bank00への書込みは無視する").
-- Reset clears the whole table to 00h, so every logical bank defaults to
-- physical bank 00h (safe MSX-compatible alias) until software configures
-- MMU_DATA explicitly.
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity MMU24 is
    port(
        RESET_n       : in  std_logic;
        CLK           : in  std_logic;

        -- Z80 I/O bus (already address/port decoded by the caller)
        IORQ_n        : in  std_logic;
        M1_n          : in  std_logic;   -- '1' outside an opcode-fetch/intack cycle
        RD_n          : in  std_logic;
        WR_n          : in  std_logic;
        Port_Addr     : in  std_logic_vector(7 downto 0);  -- A7:A0 of the I/O address
        D_In          : in  std_logic_vector(7 downto 0);  -- CPU -> MMU (OUT data)
        D_Out         : out std_logic_vector(7 downto 0);  -- MMU -> CPU (IN data)
        D_OutEn       : out std_logic;                     -- '1' while this device drives D_Out

        -- 24bit logical->physical bank translation (combinational)
        Logical_Bank  : in  std_logic_vector(7 downto 0);
        Physical_Bank : out std_logic_vector(7 downto 0)
    );
end entity MMU24;

architecture rtl of MMU24 is

    constant PORT_MMU_INDEX : std_logic_vector(7 downto 0) := x"F0";
    constant PORT_MMU_DATA  : std_logic_vector(7 downto 0) := x"F1";

    type mmu_table_t is array(0 to 255) of std_logic_vector(7 downto 0);

    signal mmu_index : std_logic_vector(7 downto 0);
    signal mmu_table : mmu_table_t;

    signal io_sel     : std_logic;  -- valid I/O access cycle to this device's ports
    signal index_sel  : std_logic;
    signal data_sel   : std_logic;

begin

    io_sel    <= '1' when IORQ_n = '0' and M1_n = '1' else '0';
    index_sel <= '1' when io_sel = '1' and Port_Addr = PORT_MMU_INDEX else '0';
    data_sel  <= '1' when io_sel = '1' and Port_Addr = PORT_MMU_DATA else '0';

    process (RESET_n, CLK)
    begin
        if RESET_n = '0' then
            mmu_index <= (others => '0');
            mmu_table <= (others => (others => '0'));
        elsif CLK'event and CLK = '1' then
            if WR_n = '0' then
                if index_sel = '1' then
                    mmu_index <= D_In;
                end if;
                if data_sel = '1' and mmu_index /= x"00" then
                    mmu_table(to_integer(unsigned(mmu_index))) <= D_In;
                end if;
            end if;
        end if;
    end process;

    D_Out <= mmu_index when index_sel = '1' and RD_n = '0' else
             mmu_table(to_integer(unsigned(mmu_index))) when data_sel = '1' and RD_n = '0' else
             (others => '0');
    D_OutEn <= '1' when (index_sel = '1' or data_sel = '1') and RD_n = '0' else '0';

    -- Logical bank 00h always aliases the plain MSX-compatible 64KB space,
    -- regardless of table contents (writes to index 00h are blocked above,
    -- but this forces the invariant even before any such write is attempted).
    Physical_Bank <= x"00" when Logical_Bank = x"00" else
                     mmu_table(to_integer(unsigned(Logical_Bank)));

end architecture rtl;
