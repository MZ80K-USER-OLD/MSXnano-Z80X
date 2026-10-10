--
-- MMU24 : Phase4 "MMU_DATA" logical->physical bank translation, plus
-- Phase6 "MMU_ATTR.W" write-protection attribute
-- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, sections 6 "Phase 4" and
-- 8 "Phase 6")
--
-- OPTIONAL ADD-ON, NOT INSTANTIATED BY DEFAULT: this module is kept in the
-- repository fully implemented and GHDL-verified (see
-- fpga/G80A/test/tb_phase4_mmu24.vhd, tb_phase5_mmu_mapping.vhd,
-- tb_phase6_mmu_attr.vhd), but is disabled in
-- fpga/MSXNanoTang20K_Z80X24.gprj (enable="0") and not instantiated by
-- fpga/top.v. The default Z80X24 build instead uses a straight-through
-- logical->physical bank mapping (mmu_physical_bank = cpu_addr24[23:16]
-- directly, no translation table, no write protection) - see the
-- "Z80X24 base spec (no MMU)" comment block in top.v for the rationale
-- (on this project's current FPGA floorplan, all on-chip BSRAM is already
-- consumed by other IP, so this module's 256-entry tables fell back to
-- expensive LUT-based distributed RAM, costing ~12-13 percentage points
-- of Logic/Register utilization project-wide).
--
-- To re-enable this module in a build with spare BSRAM: set
-- enable="1" for its <File> entry in MSXNanoTang20K_Z80X24.gprj, then in
-- top.v replace the "assign mmu_physical_bank = cpu_addr24[23:16];" line
-- with an MMU24 instance (Logical_Bank => cpu_addr24[23:16],
-- Physical_Bank => mmu_physical_bank), wire D_Out/D_OutEn into the
-- cpu_din read-mux, and gate cpu_sdram_write with Write_Allow - exactly as
-- it was wired prior to the MMU removal.
--
-- A 256x8 LUT/distributed-memory translation table, indexed by the 8bit
-- logical bank byte (A23:A16, i.e. CPU core's A_Bank from Phase3), that
-- produces the physical bank byte used for the actual memory access. The
-- lookup itself (Logical_Bank -> Physical_Bank) is purely combinational
-- ("非同期lookup"): it never adds a WAIT/T-state of its own.
--
-- A second, independent 256x8 table (only bit5 meaningful) holds a
-- per-bank write-enable attribute (MMU_ATTR.W), looked up the same way.
-- MMU_DATA and MMU_ATTR are two separate arrays (rather than one combined
-- array) since measurement showed no synthesis benefit to combining them
-- when BSRAM is unavailable, and two separate 256x8 arrays map more
-- directly to the F0h/F1h/F2h port spec below.
--
-- Z80 I/O ports (decoded by the caller and passed in via Port_Addr):
--   F0h : MMU_INDEX - 8bit index register (which table entry F1h/F2h target)
--   F1h : MMU_DATA  - read/write MMU_DATA[MMU_INDEX]
--   F2h : MMU_ATTR  - read/write MMU_ATTR[MMU_INDEX] (bit5=W, others RESERVED)
--
-- MMU_INDEX only ever changes via an explicit F0h write; F1h/F2h accesses
-- (read or write) never auto-increment it in this implementation.
--
-- MMU_DATA[00h] is fixed at 00h: logical bank 00h always aliases the
-- existing MSX-compatible 64KB space, and writes targeting index 00h are
-- ignored (per Phase4: "MMU_DATA[00]=00h固定...bank00への書込みは無視する").
-- Reset clears the whole MMU_DATA table to 00h, so every logical bank
-- defaults to physical bank 00h (safe MSX-compatible alias) until software
-- configures MMU_DATA explicitly.
--
-- MMU_ATTR.W (bit5) defaults to '1' (write allowed) for every entry after
-- reset (reset value 20h = 0010_0000b, per Phase6: "Reset値は20hとする"),
-- so until software explicitly locks a bank down, existing 24bit-aware
-- code sees no behavioural change from before Phase6 was added. W=0 makes
-- Write_Allow deasserted for that logical bank: the caller must then
-- suppress the physical write strobe (Write Enable) while still letting
-- the CPU instruction complete normally - no exception/trap, and the
-- write is simply dropped (real memory content unchanged). Like
-- MMU_DATA[00h], MMU_ATTR[00h] is exempt: writes targeting index 00h are
-- ignored and Write_Allow always reads '1' for logical bank 00h regardless
-- of table contents, since logical bank 00h bypasses the MMU-translated
-- SD-RAM path entirely (in a build that instantiates this module, the
-- caller only asserts its SD-RAM request for a non-zero MMU-translated
-- physical bank) and always goes through the existing MSX-compatible
-- slot/mapper write path instead, which is unaffected by MMU_ATTR.
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
        Physical_Bank : out std_logic_vector(7 downto 0);

        -- Phase6: per-bank write-enable attribute (combinational), looked
        -- up from the same Logical_Bank. '1' = write allowed, '0' = the
        -- caller must not assert its physical Write Enable for this access.
        Write_Allow   : out std_logic
    );
end entity MMU24;

architecture rtl of MMU24 is

    constant PORT_MMU_INDEX : std_logic_vector(7 downto 0) := x"F0";
    constant PORT_MMU_DATA  : std_logic_vector(7 downto 0) := x"F1";
    constant PORT_MMU_ATTR  : std_logic_vector(7 downto 0) := x"F2";

    constant ATTR_RESET_VALUE : std_logic_vector(7 downto 0) := x"20";  -- bit5=W=1 (write allowed)
    constant ATTR_W_BIT       : integer := 5;

    type mmu_table_t is array(0 to 255) of std_logic_vector(7 downto 0);

    signal mmu_index : std_logic_vector(7 downto 0);
    signal mmu_data  : mmu_table_t;
    signal mmu_attr  : mmu_table_t;

    signal io_sel     : std_logic;  -- valid I/O access cycle to this device's ports
    signal index_sel  : std_logic;
    signal data_sel   : std_logic;
    signal attr_sel   : std_logic;

begin

    io_sel    <= '1' when IORQ_n = '0' and M1_n = '1' else '0';
    index_sel <= '1' when io_sel = '1' and Port_Addr = PORT_MMU_INDEX else '0';
    data_sel  <= '1' when io_sel = '1' and Port_Addr = PORT_MMU_DATA else '0';
    attr_sel  <= '1' when io_sel = '1' and Port_Addr = PORT_MMU_ATTR else '0';

    process (RESET_n, CLK)
    begin
        if RESET_n = '0' then
            mmu_index <= (others => '0');
            mmu_data  <= (others => (others => '0'));
            mmu_attr  <= (others => ATTR_RESET_VALUE);
        elsif CLK'event and CLK = '1' then
            if WR_n = '0' then
                if index_sel = '1' then
                    mmu_index <= D_In;
                end if;
                if data_sel = '1' and mmu_index /= x"00" then
                    mmu_data(to_integer(unsigned(mmu_index))) <= D_In;
                end if;
                if attr_sel = '1' and mmu_index /= x"00" then
                    mmu_attr(to_integer(unsigned(mmu_index))) <= D_In;
                end if;
            end if;
        end if;
    end process;

    D_Out <= mmu_index when index_sel = '1' and RD_n = '0' else
             mmu_data(to_integer(unsigned(mmu_index))) when data_sel = '1' and RD_n = '0' else
             mmu_attr(to_integer(unsigned(mmu_index))) when attr_sel = '1' and RD_n = '0' else
             (others => '0');
    D_OutEn <= '1' when (index_sel = '1' or data_sel = '1' or attr_sel = '1') and RD_n = '0' else '0';

    -- Logical bank 00h always aliases the plain MSX-compatible 64KB space,
    -- regardless of table contents (writes to index 00h are blocked above,
    -- but this forces the invariant even before any such write is attempted).
    Physical_Bank <= x"00" when Logical_Bank = x"00" else
                     mmu_data(to_integer(unsigned(Logical_Bank)));

    -- Logical bank 00h is the MSX-compatible alias and is exempt from
    -- MMU_ATTR.W: it always reports Write_Allow='1' regardless of table
    -- contents, mirroring the Physical_Bank treatment above (writes to
    -- MMU_ATTR[00h] are blocked, but this forces the invariant even before
    -- any such write is attempted). Bank 00h never actually takes
    -- the MMU-translated SD-RAM path in a build that instantiates this
    -- module (see header comment), so this exception also keeps
    -- MMU_ATTR query results honest instead of reporting a W value that
    -- has no real effect.
    Write_Allow <= '1' when Logical_Bank = x"00" else
                   mmu_attr(to_integer(unsigned(Logical_Bank)))(ATTR_W_BIT);

end architecture rtl;
