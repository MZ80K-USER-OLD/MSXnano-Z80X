--
-- Hardware-timing-fidelity testbench: PUSH24/POP24 bank-boundary-crossing
-- reproduction attempt for hardware_test/Push24Test's persistent Test7
-- FAILure (see doc/jpn/PUSH24_POP24_bank境界またぎバグ_調査レポート.md).
--
-- Unlike tb_phase9_push24_pop24.vhd (which instantiates the bare T80 core
-- with CEN/WAIT_n tied to a constant '1' and a zero-latency combinational
-- memory model - i.e. it validates the CORE's own PUSH24/POP24 logic, but
-- says NOTHING about the real hardware's asynchronous g80a.vhd wrapper,
-- its ~3.6MHz virtual-clock-gated WAIT_n/DI sampling, or the
-- fpga/src/memory.v SD-RAM arbitration state machine that actually
-- generates that WAIT_n with real, variable, multi-cycle latency), THIS
-- testbench reproduces the full real hardware timing chain at much
-- higher fidelity:
--
--   - g80a.vhd (the actual asynchronous CPU wrapper used by fpga/top.v,
--     completely unmodified, instantiated directly here - NOT the bare
--     T80 core)
--   - the real clk_108m/clk_54m 2:1 clock relationship, and the real
--     108MHz/30 3.6MHz virtual-clock divider + PINFILTER debounce +
--     clk_enable_3m6_54/clk_falling_3m6_54 edge detectors, ported
--     line-for-line from fpga/top.v
--   - the real (current, v4-fixed) cpu_sdram_req/cpu_sdram_addr/
--     cpu_sdram_write/cpu_sdram_wait_n generation logic, ported
--     line-for-line from fpga/top.v
--   - the real (current, v4-fixed) memory_ctrl sdram_seq arbitration
--     state machine (states 0-4), ported line-for-line from
--     fpga/src/memory.v, including the registered cpu_din priority mux
--   - a free-running, intentionally-unsynchronized "video bandwidth
--     arbitration window" generator standing in for the real VDP's
--     video_dlclk/video_dhclk signals, to inject realistic variable
--     multi-cycle latency into the SD-RAM arbitration (states 0 and 2)
--
-- Deliberately OUT OF SCOPE (candidate 3 in the investigation report):
-- the actual 108MHz SDRAM physical command/row-activate/data-latency
-- pipeline (memory.v's ff_sdr_seq/SdrCmd/SdrAdr/SdrDat machinery) is
-- replaced with an idealized, zero-added-latency backing store (3
-- dedicated registers for the only 3 physical addresses this test's
-- bank-boundary-crossing PUSH24/POP24 ever touches). This isolates
-- candidates 1 ("CPUのWAIT/CEN状態とPOP24状態遷移の不整合") and 2
-- ("SDRAM読み出し完了通知とCPUデータ取得の位相ずれ") from candidate 3.
--
-- Reproduces hardware_test/Push24Test/push24_test.asm's Test7 exactly:
-- MSP24=02:0001h, PUSH24 HL (HL24=05:99AAh) crossing the bank boundary
-- downward (02:0001->02:0000->01:FFFF(borrow)->01:FFFE), then POP24 HL
-- crossing the same boundary upward (01:FFFE->01:FFFF->02:0000->
-- 02:0001). The real hardware test expects HL24=05:99AAh and
-- MSP24=02:0001h after POP24; if this testbench's self-check instead
-- reports the SAME corruption pattern observed on real hardware
-- (HL24 garbage with a correct BANK byte but wrong HIGH/LOW bytes, and
-- MSP24 stuck at its pre-POP24 value of 01:FFFEh), this confirms
-- candidates 1/2 as the root cause without requiring another real-
-- hardware synthesize/flash/test cycle.
--
-- Run with GHDL:
--   ghdl -a --std=08 ../t80_pack.vhd ../t80_mcode.vhd ../t80_alu.vhd ../t80_reg.vhd ../t80.vhd ../g80a.vhd tb_hw_push24_bank_boundary_timing.vhd
--   ghdl -e --std=08 tb_hw_push24_bank_boundary_timing
--   ghdl -r --std=08 tb_hw_push24_bank_boundary_timing
--
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_hw_push24_bank_boundary_timing is
end entity tb_hw_push24_bank_boundary_timing;

architecture sim of tb_hw_push24_bank_boundary_timing is

    ------------------------------------------------------------------
    -- Clock generation: CLK108 (108MHz stand-in) and CLK54, matching
    -- fpga/top.v's Gowin_CLKDIV2 exact divide-by-2 relationship (only
    -- the 2:1 ratio/edge alignment matters for logic-level fidelity,
    -- not the absolute frequency).
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
           bank_msp, bank_int, bank_rst : std_logic_vector(7 downto 0);
    signal Data_Reverse : std_logic;

    ------------------------------------------------------------------
    -- fpga/top.v's cpu_sdram_* request/address-latch/WAIT generation.
    --
    -- v5 FIX (2026-10-17, see doc/jpn/PUSH24_POP24_bank境界またぎバグ_
    -- 調査レポート.md "追記4"): v1-v4 all left a single root-cause race
    -- undiagnosed. g80a.vhd's WAIT_n observation (Wait_s, sampled only
    -- once per ~15-30 real clk_54m-cycle virtual-clock period, on its
    -- own clk_falling tick) and the T80 core's own bus-cycle-ending
    -- MREQ_n/RD_n/WR_n deassertion (driven by g80a.vhd on the SAME slow
    -- virtual clock) can both occur WITHOUT the core ever actually
    -- observing a WAIT request that genuinely occurred in between two
    -- of its own sampling ticks - a classic "fast pulse missed by a
    -- slow sampler" hazard. Direct simulation tracing (this file's
    -- diagnostic trace process) proved this is EXACTLY what happens:
    -- cpu_sdram_wait_n correctly drops low for PUSH24/POP24's extended
    -- accesses, but g80a.vhd's core_WAIT_n (Wait_s) sometimes only
    -- observes the drop AFTER the bus cycle has already completed and
    -- MREQ_n/WR_n have already gone inactive - by which point the CPU
    -- has already moved on to the NEXT M-cycle, re-triggering the
    -- SAME single-register cpu_sdram_addr_r/cpu_sdram_write_r latch
    -- before memory_ctrl ever got to consume the PREVIOUS value -
    -- silently losing/aliasing that access.
    --
    -- v1-v4 never actually eliminated this: they all still asserted
    -- cpu_sdram_wait_n reactively (gated behind cpu_sdram_req_r's own
    -- 1-cycle registration delay) and relied on it being observed
    -- "soon enough" - with no GUARANTEE it could not be missed
    -- entirely if its whole assert/release window happened to fall
    -- between two consecutive clk_falling ticks.
    --
    -- v5 attempted the textbook fix for "a fast-domain pulse that a
    -- slow sampler must never miss": assert cpu_sdram_wait_n
    -- COMBINATIONALLY off cpu_sdram_active (no extra register delay
    -- before the WAIT decision), and hold it low for a fixed MINIMUM
    -- real-clk_54m-cycle duration before allowing release. Empirically
    -- sweeping that duration (40/80/100/150/200 cycles) gave
    -- NON-monotonic results (some values "fixed" it, others didn't) -
    -- a clear sign that guessing a cycle COUNT is the wrong model:
    -- changing the hold duration also shifts the phase of ALL
    -- subsequent accesses relative to the free-running video-window
    -- generator, so a longer hold is not reliably "safer", just
    -- "different".
    --
    -- v6 fix (this version): tie the guarantee directly to the EXACT
    -- signal g80a.vhd itself uses to sample WAIT_n (clk_falling_3m6_54)
    -- instead of a guessed cycle count - the textbook-correct technique
    -- for this class of "slow domain must observe a fast domain's
    -- signal" hazard. Hold cpu_sdram_wait_n low until AT LEAST
    -- WAIT_MIN_FALLING_PULSES genuine clk_falling_3m6_54 pulses have
    -- occurred since it was asserted (regardless of how many real
    -- clk_54m cycles that takes), GUARANTEEING g80a.vhd's own Wait_s
    -- sampling has a confirmed opportunity to observe the request -
    -- AND, independently, still requires the real busy/seen_busy
    -- data-ready handshake (unchanged from v2-v4) before releasing.
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

    ------------------------------------------------------------------
    -- v7 fix (2026-10-17, see the WAIT-generator process below for the
    -- full rationale, and doc/jpn/PUSH24_POP24_bank境界またぎバグ_
    -- 調査レポート.md "追記5"). Direct cycle-by-cycle tracing proved
    -- v5/v6 both still failed because of a DEEPER, structural hazard
    -- that no amount of "hold WAIT longer afterward" can fix: g80a.vhd
    -- asserts MREQ_n/RD_n/WR_n for a NEW M-cycle AND samples WAIT_n
    -- into its internal Wait_s on the EXACT SAME clk_falling edge (both
    -- are g80a.vhd processes triggered by that one edge). Since
    -- cpu_sdram_wait_n can only react to MREQ_n becoming active AFTER
    -- that same edge (ordinary synchronous-logic causality - a
    -- register cannot see another register's output change that is
    -- itself a RESULT of the very same clock edge), WAIT is
    -- STRUCTURALLY, unavoidably missed for this specific M-cycle if it
    -- is asserted reactively off MREQ_n/RD_n/WR_n, no matter how fast
    -- or how long it is subsequently held.
    --
    -- The fix is to assert cpu_sdram_wait_n EARLY, off a signal that is
    -- ALREADY settled before that same edge: T80's own "update_addr"
    -- output (exposed as a G80a port, wired straight through from
    -- t80.vhd) pulses for exactly one clk_enable-gated cycle at T_Res
    -- of EVERY M-cycle - the SAME moment A_Bank_r (hence
    -- mmu_physical_bank) is set up for the UPCOMING M-cycle, one full
    -- clk_enable-to-clk_falling gap BEFORE that upcoming M-cycle's own
    -- MREQ_n/RD_n/WR_n actually assert. Sampling mmu_physical_bank ONE
    -- real clk_54m cycle after update_addr pulses (to let A_Bank_r
    -- settle) and asserting WAIT immediately if it is non-zero gives a
    -- full inter-M-cycle gap of lead time - no same-edge race.
    --
    -- IMPORTANT (discovered via a SEPARATE deadlock this fix initially
    -- introduced, root-caused by direct tracing): update_addr is NOT a
    -- narrow single-real-cycle pulse. Its assignment in t80.vhd's main
    -- process is only evaluated on CEN(clk_enable)-gated edges (same
    -- virtual-clock granularity as everything else inside T80), so once
    -- set to '1' it HOLDS that value, unchanged, across EVERY real
    -- clk_54m cycle until the NEXT clk_enable tick - i.e. for up to a
    -- FULL virtual-clock period (~15-30 real cycles), not just one. A
    -- naive single-register "update_addr_prev='1'" check (true for that
    -- ENTIRE held-high window) spuriously re-triggers WS_IDLE->WS_ARMED
    -- repeatedly on EVERY real cycle while wait_state happens to cycle
    -- back through WS_IDLE during that SAME window - even though it is
    -- still the SAME T_Res event, not a new one - re-arming WAIT for an
    -- M-cycle that has not actually advanced, before memory_ctrl's
    -- sdram_seq (parked in state "100", itself waiting for
    -- cpu_sdram_req to genuinely drop once the CPU truly moves on) ever
    -- gets a chance to return to idle - the exact same class of
    -- deadlock as the original v5 bug, just via update_addr instead of
    -- cpu_sdram_active. The fix is a GENUINE 2-stage edge detector
    -- (update_addr_prev/update_addr_prev2 below), which only fires once
    -- per real 0->1 transition of update_addr, no matter how long it
    -- then stays high.
    signal update_addr_prev  : std_logic := '0';
    signal update_addr_prev2 : std_logic := '0';

    type wait_state_t is (WS_IDLE, WS_ARMED, WS_WAITING_DONE);
    signal wait_state : wait_state_t := WS_IDLE;
    signal wait_armed_falls : natural range 0 to 3 := 0;

    -- Unambiguous, single-cycle "this specific cpu-owned access's data
    -- has just been committed" pulse - fixes a SEPARATE bug also found
    -- via tracing: cpu_sdram_busy mirrors cpu_sdram_req from the moment
    -- a request is merely PENDING in sdram_seq state "000" (not yet
    -- admitted), so "busy was seen high" (v2-v4's seen_busy condition)
    -- could already be satisfied almost instantly, well before
    -- memory_ctrl had actually serviced anything - letting WAIT release
    -- (and the CPU complete/abandon its bus cycle) while the access was
    -- STILL stuck in state "000" waiting for a video-arbitration
    -- window, silently losing it entirely. sdram_seq="011" (with
    -- sdram_owner_cpu='1') is the exact, unambiguous cycle
    -- cpu_sdram_dout actually receives RamDbi - not reachable except by
    -- genuinely passing through admission (state "001") first.
    signal cpu_sdram_done_pulse : std_logic;

    ------------------------------------------------------------------
    -- fpga/src/memory.v's sdram_seq arbitration (current, v4-fixed
    -- version), ported line-for-line. mapper_req/megaram_req are
    -- permanently '0' in this scoped testbench (no legacy-mapper/
    -- megaram client is modeled - see header comment), so their
    -- branches are dead code here but kept for 1:1 structural fidelity
    -- with the real source (state encoding: "000".."100" = 3'd0..3'd4).
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
    -- the real VDP's video_dlclk/video_dhclk (see header comment).
    -- Deliberately NOT synchronized to the 3.6MHz virtual clock's own
    -- period/phase, so the whole simulation naturally sweeps through
    -- many different relative phase offsets between the two, the same
    -- way the real VDP and CPU timing are mutually asynchronous.
    --
    -- These particular values (a very short 1-cycle admission window
    -- followed by a long 29-cycle closed/busy dwell) were found by a
    -- parameter sweep to reliably reproduce the bug: a wide range of
    -- (OPEN=1, CLOSED=15..60) and even (OPEN=2, CLOSED=29) all
    -- reproduced data corruption of the same shape as real hardware
    -- (correct BANK byte, wrong HIGH and/or LOW byte, substituted with
    -- the backing store's uninitialized 00h rather than the real
    -- pushed value) - see doc/jpn/PUSH24_POP24_bank境界またぎバグ_
    -- 調査レポート.md "追記3" for the full sweep results and analysis.
    -- Symmetric or OPEN-dominant ratios (OPEN>=CLOSED, e.g. 8/8, 13/3,
    -- 29/1, 50/1) did NOT reproduce the bug in this sweep - the
    -- defect specifically needs a SHORT admission window paired with
    -- a LONG completion dwell.
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
    -- Hand assembled program (mirrors hardware_test/Push24Test/
    -- push24_test.asm's Test7 sequence exactly, minus the VDP marker
    -- OUTs and BDOS calls, which are presentation-only and irrelevant
    -- here):
    --   0000: 21 01 00        LD   HL,0001h
    --   0003: 3E 02           LD   A,02h
    --   0005: ED 24           LD   HL_B,A          ; MSP setup: bank=02h
    --   0007: ED 35           LD24 MSP,HL          ; MSP24 = 02:0001h
    --   0009: 21 AA 99        LD   HL,99AAh
    --   000C: 3E 05           LD   A,05h
    --   000E: ED 24           LD   HL_B,A          ; HL24 = 05:99AAh
    --   0010: ED E5           PUSH24 HL            ; ** test: bank-crossing push **
    --   0012: 21 00 00        LD   HL,0000h
    --   0015: AF              XOR  A
    --   0016: ED 24           LD   HL_B,A          ; clobber HL24 = 00:0000h
    --   0018: ED E1           POP24 HL             ; ** test: bank-crossing pop **
    --   001A: 22 00 40        LD   (4000h),HL       ; dump HL24 low word
    --   001D: ED 2C           LD   A,HL_B
    --   001F: 32 02 40        LD   (4002h),A        ; dump HL24 bank
    --   0022: ED 36           LD24 HL,MSP
    --   0024: 22 03 40        LD   (4003h),HL       ; dump MSP24 low word
    --   0027: ED 2C           LD   A,HL_B
    --   0029: 32 05 40        LD   (4005h),A        ; dump MSP24 bank
    --   002C: 76              HALT
    ------------------------------------------------------------------
    type mem_array is array(0 to 65535) of std_logic_vector(7 downto 0);
    signal mem00 : mem_array := (
        16#0000# => x"21", 16#0001# => x"01", 16#0002# => x"00",
        16#0003# => x"3E", 16#0004# => x"02",
        16#0005# => x"ED", 16#0006# => x"24",
        16#0007# => x"ED", 16#0008# => x"35",
        16#0009# => x"21", 16#000A# => x"AA", 16#000B# => x"99",
        16#000C# => x"3E", 16#000D# => x"05",
        16#000E# => x"ED", 16#000F# => x"24",
        16#0010# => x"ED", 16#0011# => x"E5",
        16#0012# => x"21", 16#0013# => x"00", 16#0014# => x"00",
        16#0015# => x"AF",
        16#0016# => x"ED", 16#0017# => x"24",
        16#0018# => x"ED", 16#0019# => x"E1",
        16#001A# => x"22", 16#001B# => x"00", 16#001C# => x"40",
        16#001D# => x"ED", 16#001E# => x"2C",
        16#001F# => x"32", 16#0020# => x"02", 16#0021# => x"40",
        16#0022# => x"ED", 16#0023# => x"36",
        16#0024# => x"22", 16#0025# => x"03", 16#0026# => x"40",
        16#0027# => x"ED", 16#0028# => x"2C",
        16#0029# => x"32", 16#002A# => x"05", 16#002B# => x"40",
        -- ---- Test8-equivalent (new): isolated (BC)-indirect writes
        -- (SET_M1, same proven-safe mechanism as the real hardware
        -- test's own "peek" diagnostic) followed by a SET_M0 and a
        -- STANDALONE POP24 (MSP24 set directly via LD24 MSP,HL, NOT
        -- preceded by a PUSH24 in the same burst) - added after real
        -- hardware reported this exact sequence (hardware_test/
        -- Push24Test/push24_test.asm's Test8) freezing the whole
        -- system (keyboard unresponsive) after v8's fix was flashed,
        -- even though Test7's own PUSH24-then-POP24 burst completed
        -- normally (with wrong data, but no freeze). Mirrors Test8's
        -- exact instruction sequence to attempt a from-scratch GHDL
        -- reproduction of this NEW regression. ----
        16#002C# => x"ED", 16#002D# => x"91",                       -- SET_M1
        16#002E# => x"01", 16#002F# => x"FE", 16#0030# => x"FF",    -- LD BC,0FFFEh
        16#0031# => x"3E", 16#0032# => x"01",                       -- LD A,01h
        16#0033# => x"ED", 16#0034# => x"04",                       -- LD BC_B,A
        16#0035# => x"3E", 16#0036# => x"AA",                       -- LD A,0AAh
        16#0037# => x"02",                                          -- LD (BC),A
        16#0038# => x"01", 16#0039# => x"FF", 16#003A# => x"FF",    -- LD BC,0FFFFh
        16#003B# => x"3E", 16#003C# => x"01",                       -- LD A,01h
        16#003D# => x"ED", 16#003E# => x"04",                       -- LD BC_B,A
        16#003F# => x"3E", 16#0040# => x"99",                       -- LD A,99h
        16#0041# => x"02",                                          -- LD (BC),A
        16#0042# => x"01", 16#0043# => x"00", 16#0044# => x"00",    -- LD BC,0000h
        16#0045# => x"3E", 16#0046# => x"02",                       -- LD A,02h
        16#0047# => x"ED", 16#0048# => x"04",                       -- LD BC_B,A
        16#0049# => x"3E", 16#004A# => x"05",                       -- LD A,05h
        16#004B# => x"02",                                          -- LD (BC),A
        16#004C# => x"ED", 16#004D# => x"90",                       -- SET_M0
        16#004E# => x"21", 16#004F# => x"FE", 16#0050# => x"FF",    -- LD HL,0FFFEh
        16#0051# => x"3E", 16#0052# => x"01",                       -- LD A,01h
        16#0053# => x"ED", 16#0054# => x"24",                       -- LD HL_B,A
        16#0055# => x"ED", 16#0056# => x"35",                       -- LD24 MSP,HL (MSP24=01:FFFEh)
        16#0057# => x"21", 16#0058# => x"00", 16#0059# => x"00",    -- LD HL,0000h
        16#005A# => x"AF",                                          -- XOR A
        16#005B# => x"ED", 16#005C# => x"24",                       -- LD HL_B,A (clobber)
        16#005D# => x"ED", 16#005E# => x"E1",                       -- POP24 HL ** test: standalone POP24, no preceding PUSH24 **
        16#005F# => x"22", 16#0060# => x"10", 16#0061# => x"40",    -- LD (4010h),HL
        16#0062# => x"ED", 16#0063# => x"2C",                       -- LD A,HL_B
        16#0064# => x"32", 16#0065# => x"12", 16#0066# => x"40",    -- LD (4012h),A
        16#0067# => x"ED", 16#0068# => x"36",                       -- LD24 HL,MSP
        16#0069# => x"22", 16#006A# => x"13", 16#006B# => x"40",    -- LD (4013h),HL
        16#006C# => x"ED", 16#006D# => x"2C",                       -- LD A,HL_B
        16#006E# => x"32", 16#006F# => x"15", 16#0070# => x"40",    -- LD (4015h),A
        16#0071# => x"76",
        others => x"00");

    ------------------------------------------------------------------
    -- Idealized, zero-added-latency backing store for the ONLY 3
    -- physical (CPU_SDRAM_BASE-relative) addresses this test's
    -- bank-boundary-crossing PUSH24/POP24 ever touches - see header
    -- comment for why candidate 3 (real SDRAM row/column timing) is
    -- deliberately out of scope here.
    ------------------------------------------------------------------
    signal fake_sdram_bank_byte : std_logic_vector(7 downto 0) := (others => '0'); -- phys 660000h
    signal fake_sdram_high_byte : std_logic_vector(7 downto 0) := (others => '0'); -- phys 65FFFFh
    signal fake_sdram_low_byte  : std_logic_vector(7 downto 0) := (others => '0'); -- phys 65FFFEh

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

    -- PINFILTER dn1 (clk=clk_54m, din=ex_bus_clk_3m6, dout=bus_clk_3m6),
    -- ported with the same same-cycle semantics as
    -- fpga/tn_vdp_v3_v9958/src/pinfilter.v's blocking-assignment idiom
    -- (two consecutive agreeing samples update the output this same
    -- cycle; a disagreement holds the previous output - see the
    -- investigation report's derivation of this module's behavior).
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
            bank_rst => bank_rst,
            Data_Reverse => Data_Reverse);

    DI <= cpu_din;
    mmu_physical_bank <= A_Bank;

    ------------------------------------------------------------------
    -- fpga/top.v: cpu_sdram_active/cpu_sdram_bank_in_range.
    -- cpu_sdram_active is now PURELY combinational (v5 fix - see the
    -- declaration comment above for why the register that used to sit
    -- here, cpu_sdram_req_r, is removed: every cycle of delay here
    -- narrows the margin before g80a.vhd's slow virtual-clock sampling
    -- must catch the resulting WAIT).
    ------------------------------------------------------------------
    cpu_sdram_bank_in_range <= '1' when (mmu_physical_bank /= x"00" and
                                          unsigned(mmu_physical_bank) <= CPU_SDRAM_BANK_MAX)
                               else '0';

    cpu_sdram_active <= '1' when (cpu_sdram_bank_in_range = '1' and MREQ_n = '0' and
                                   (RD_n = '0' or WR_n = '0') and RFSH_n = '1')
                        else '0';
    cpu_sdram_req   <= cpu_sdram_active when wait_state = WS_WAITING_DONE else '0';
    cpu_sdram_write <= cpu_sdram_req and cpu_sdram_write_r;
    cpu_sdram_addr  <= cpu_sdram_addr_r;

    ------------------------------------------------------------------
    -- fpga/top.v: WAIT_n generator with v9 internal-cycle release (see
    -- the declaration comment above for the full rationale). A small
    -- 3-state machine:
    --
    --   WS_IDLE  : wait_n='1'. The moment update_addr pulses (one
    --              real clk_54m cycle earlier is when we actually
    --              check mmu_physical_bank, to let A_Bank_r settle -
    --              see below), if the UPCOMING M-cycle's bank is
    --              non-zero, assert wait_n immediately and move to
    --              WS_ARMED - well BEFORE that M-cycle's own MREQ_n/
    --              RD_n/WR_n ever assert.
    --   WS_ARMED : wait_n stays '0'. Once the REAL bus request for
    --              THIS M-cycle is seen (cpu_sdram_active's rising
    --              edge - now safely observed by g80a.vhd's Wait_s,
    --              since wait_n has already been low for a while),
    --              latch the address/write-flag and move to
    --              WS_WAITING_DONE.
    --   WS_WAITING_DONE: wait_n stays '0' until cpu_sdram_done_pulse
    --              (the unambiguous "data genuinely committed" signal
    --              - see declaration comment) fires, then release
    --              (wait_n<='1') and return to WS_IDLE. The NEXT
    --              update_addr pulse (which cannot occur until T80
    --              has genuinely advanced past THIS M-cycle) is what
    --              re-arms - so, unlike v5's level-triggered
    --              "wait_n=1 => new access" check, there is no risk of
    --              re-triggering before the CPU has actually moved on.
    ------------------------------------------------------------------
    cpu_sdram_done_pulse <= '1' when (sdram_seq = "011" and sdram_owner_cpu = '1') else '0';

    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if RESET_n = '0' then
                cpu_sdram_wait_n <= '1';
                wait_state <= WS_IDLE;
                wait_armed_falls <= 0;
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
                            -- update_addr had a GENUINE 0->1 transition
                            -- one real clk_54m cycle ago (checked via
                            -- the 2-stage update_addr_prev/
                            -- update_addr_prev2 edge detector - see the
                            -- declaration comment for why a single-
                            -- stage check is NOT sufficient here, unlike
                            -- cpu_sdram_active's own edge detector
                            -- below, since update_addr can legitimately
                            -- stay high for many cycles) giving
                            -- A_Bank_r/mmu_physical_bank a full cycle to
                            -- settle to the NEW M-cycle's bank before we
                            -- read it, and that upcoming M-cycle needs
                            -- the extended SD-RAM window - assert WAIT
                            -- now, well ahead of this M-cycle's own bus
                            -- signals.
                            cpu_sdram_wait_n <= '0';
                            wait_armed_falls <= 0;
                            wait_state <= WS_ARMED;
                        end if;

                    when WS_ARMED =>
                        if clk_falling_3m6_54 = '1' and wait_armed_falls /= 3 then
                            wait_armed_falls <= wait_armed_falls + 1;
                        end if;
                        if cpu_sdram_active = '1' then
                            -- The real bus request for THIS M-cycle has
                            -- now genuinely asserted (MREQ_n/RD_n/WR_n)
                            -- - latch its address/write-flag (same
                            -- rationale as v3/v5's latch: protect
                            -- against mmu_physical_bank drifting later)
                            -- and move on to waiting for genuine
                            -- completion.
                            cpu_sdram_addr_r <= std_logic_vector(CPU_SDRAM_BASE +
                                (unsigned(mmu_physical_bank) & unsigned(A)));
                            cpu_sdram_write_r <= not WR_n;
                            wait_state <= WS_WAITING_DONE;
                        elsif wait_armed_falls = 3 and MREQ_n = '1' then
                            cpu_sdram_wait_n <= '1';
                            wait_state <= WS_IDLE;
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
    -- v4-fixed: sdram_owner_cpu/sdram_owner_mapper latched in state
    -- "001", used - NOT the live request wires - in state "011"'s
    -- data-routing decision). Ported line-for-line; mapper_req/
    -- megaram_req are tied to '0' (see declaration comment above).
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
                            -- Idealized zero-latency SD-RAM write commit
                            -- (candidate 3 out of scope - see header
                            -- comment): writes to the fake backing store
                            -- commit immediately here instead of via the
                            -- real clk_108m SdrCmd/SdrAdr/SdrDat pipeline.
                            -- Harmless for THIS test since PUSH24's writes
                            -- are independently known-correct (verified by
                            -- the real hardware test's own SET_M1+(BC)
                            -- "peek" diagnostic) - only POP24's READ timing
                            -- is under test here.
                            if cpu_sdram_write = '1' then
                                case cpu_sdram_addr is
                                    when x"660000" => fake_sdram_bank_byte <= DO;
                                    when x"65FFFF" => fake_sdram_high_byte <= DO;
                                    when x"65FFFE" => fake_sdram_low_byte  <= DO;
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
                        -- (sdram_owner_mapper branch omitted: dead code in
                        -- this scoped testbench, mapper_req is tied to '0'.)
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
    -- of the 3 known physical addresses sdram_addr (latched in state
    -- "001") currently holds.
    RamDbi <= fake_sdram_bank_byte when sdram_addr = x"660000" else
              fake_sdram_high_byte when sdram_addr = x"65FFFF" else
              fake_sdram_low_byte  when sdram_addr = x"65FFFE" else
              x"00";

    ------------------------------------------------------------------
    -- fpga/top.v: registered cpu_din priority mux (ported; only the
    -- cpu_sdram_req/legacy-bank00 branches are relevant here, since no
    -- other client (mapper/BIOS/VDP/...) is modeled in this scoped
    -- testbench).
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if cpu_sdram_active = '1' then
                cpu_din <= cpu_sdram_dout;
            else
                cpu_din <= mem00(to_integer(unsigned(A)));
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Legacy bank00 memory write-back (program + result-dump area;
    -- never routed through cpu_sdram_*, matching real hardware's
    -- bank00 = ordinary Memory Mapper RAM path).
    ------------------------------------------------------------------
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if A_Bank = x"00" and MREQ_n = '0' and WR_n = '0' then
                mem00(to_integer(unsigned(A))) <= DO;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- DIAGNOSTIC (temporary): cycle-by-cycle trace of every extended-
    -- memory transaction, including hierarchical probes of the T80
    -- core's internal MSP/bank_msp_r registers, to directly observe
    -- whether MSP24 actually gets corrupted INSIDE the core (not just
    -- in the LD24 HL,MSP dump readout) during a reproducing run.
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
                    " MSP=" & to_hstring(std_logic_vector(<<signal u_cpu.u0.MSP : unsigned(15 downto 0)>>)) &
                    " bank_msp_r=" & to_hstring(<<signal u_cpu.u0.bank_msp_r : std_logic_vector(7 downto 0)>>) &
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
    -- Self-check: wait for HALT, then verify HL24/MSP24 against the
    -- real hardware test's expected ("want") values. Uses "severity
    -- error" (not "failure") so BOTH checks always run and the final
    -- summary report always prints, regardless of outcome.
    ------------------------------------------------------------------
    process
    begin
        wait until HALT_n = '0';
        wait for 5 us; -- drain trailing HALT refetch cycles

        assert mem00(16#4000#) = x"AA" and mem00(16#4001#) = x"99" and mem00(16#4002#) = x"05"
            report "HW-timing repro: POP24 HL mismatch, got lo=" & to_hstring(mem00(16#4000#)) &
                " hi=" & to_hstring(mem00(16#4001#)) & " bank=" & to_hstring(mem00(16#4002#)) &
                ", want lo=AAh hi=99h bank=05h " &
                "(compare against real hardware's got=0502A6h/want=0599AAh)"
            severity error;

        assert mem00(16#4003#) = x"01" and mem00(16#4004#) = x"00" and mem00(16#4005#) = x"02"
            report "HW-timing repro: MSP24 restore mismatch, got lo=" & to_hstring(mem00(16#4003#)) &
                " hi=" & to_hstring(mem00(16#4004#)) & " bank=" & to_hstring(mem00(16#4005#)) &
                ", want lo=01h hi=00h bank=02h " &
                "(compare against real hardware's got=01FFFEh/want=020001h)"
            severity error;

        -- Test8-equivalent self-check (see mem00's init comment above
        -- for the instruction sequence this mirrors) - added to
        -- reproduce the NEW real-hardware freeze (keyboard-unresponsive
        -- hang, NOT just wrong data) reported after v8's fix was
        -- flashed, specifically for this standalone-POP24 (no preceding
        -- PUSH24 in the same burst) pattern.
        assert mem00(16#4010#) = x"AA" and mem00(16#4011#) = x"99" and mem00(16#4012#) = x"05"
            report "HW-timing repro: Test8-equivalent standalone POP24 HL mismatch, got lo=" &
                to_hstring(mem00(16#4010#)) & " hi=" & to_hstring(mem00(16#4011#)) &
                " bank=" & to_hstring(mem00(16#4012#)) & ", want lo=AAh hi=99h bank=05h"
            severity error;

        assert mem00(16#4013#) = x"01" and mem00(16#4014#) = x"00" and mem00(16#4015#) = x"02"
            report "HW-timing repro: Test8-equivalent MSP24 restore mismatch, got lo=" &
                to_hstring(mem00(16#4013#)) & " hi=" & to_hstring(mem00(16#4014#)) &
                " bank=" & to_hstring(mem00(16#4015#)) & ", want lo=01h hi=00h bank=02h"
            severity error;

        report "HW-timing repro testbench: self-check complete. An 'error' " &
            "severity assertion above means the bug WAS reproduced in " &
            "simulation (confirming candidates 1/2 - WAIT/CEN state and " &
            "SD-RAM completion-notice timing); no assertion failure above " &
            "means candidates 1/2 are NOT sufficient on their own and " &
            "candidate 3 (real 108MHz SD-RAM physical-layer timing) should " &
            "be investigated next."
            severity note;

        std.env.stop;
    end process;

end architecture sim;
