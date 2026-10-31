library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Real G80a + fpga/top.v extended-SDRAM WAIT FSM, executing code from
-- bank01 in M2. JR/DJNZ/ADD HL contain internal (NoRead) M-cycles and the
-- IRQ acknowledge cycle has no MREQ; all of them start with update_addr and
-- the non-zero PC bank, which used to leave WAIT armed forever.
entity tb_hw_m2_internal_cycle_wait is
    generic (Release_Internal : boolean := true; Trace : boolean := false);
end entity;

architecture sim of tb_hw_m2_internal_cycle_wait is
    constant CPU_SDRAM_BASE     : unsigned(23 downto 0) := x"640000";
    constant CPU_SDRAM_BANK_MAX : unsigned(7 downto 0)  := x"1B";

    signal CLK108, CLK54, RESET_n : std_logic := '0';
    signal div30_cnt : unsigned(4 downto 0) := (others => '0');
    signal clk_3m6_internal, bus_clk_3m6 : std_logic := '0';
    signal pf_dpipe : std_logic_vector(1 downto 0) := "00";
    signal bus_clk_3m6_54, bus_clk_3m6_prev_54 : std_logic := '0';
    signal clk_enable_3m6_54, clk_falling_3m6_54 : std_logic;

    signal WAIT_n, INT_n : std_logic := '1';
    signal M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n : std_logic;
    signal A : std_logic_vector(15 downto 0);
    signal update_addr : std_logic;
    signal A_Bank, DI, DO : std_logic_vector(7 downto 0);
    signal mode24 : std_logic_vector(1 downto 0);
    signal Data_Reverse : std_logic;

    signal cpu_sdram_active, cpu_sdram_req, cpu_sdram_done : std_logic;
    signal cpu_sdram_addr_r : std_logic_vector(23 downto 0) := (others => '0');
    signal cpu_sdram_dout, cpu_din : std_logic_vector(7 downto 0) := (others => '0');
    signal cpu_sdram_wait_n : std_logic := '1';
    signal update_addr_prev, update_addr_prev2 : std_logic := '0';
    type wait_state_t is (WS_IDLE, WS_ARMED, WS_WAITING_DONE);
    signal wait_state : wait_state_t := WS_IDLE;
    signal wait_armed_falls : natural range 0 to 3 := 0;
    signal internal_releases : natural := 0;

    signal sdram_seq : natural range 0 to 4 := 0;
    signal sdram_addr : std_logic_vector(23 downto 0) := (others => '0');
    signal video_cnt : natural range 0 to 29 := 0;
    signal video_open : std_logic := '1';

    type mem_array is array(0 to 65535) of std_logic_vector(7 downto 0);
    signal mem00 : mem_array := (
        16#0000# => x"31", 16#0001# => x"00", 16#0002# => x"F0",       -- LD SP,F000h
        16#0003# => x"ED", 16#0004# => x"9B", 16#0005# => x"00",
        16#0006# => x"00", 16#0007# => x"01",                          -- enter M2 at 01:0000
        16#0010# => x"22", 16#0011# => x"00", 16#0012# => x"40",       -- LD (4000h),HL
        16#0013# => x"3E", 16#0014# => x"5A",                          -- LD A,5Ah
        16#0015# => x"32", 16#0016# => x"02", 16#0017# => x"40",       -- LD (4002h),A
        16#0018# => x"76",                                             -- HALT
        16#0038# => x"3E", 16#0039# => x"A5",                          -- IRQ: LD A,0A5h
        16#003A# => x"32", 16#003B# => x"03", 16#003C# => x"40",       -- LD (4003h),A
        16#003D# => x"ED", 16#003E# => x"93", 16#003F# => x"10", 16#0040# => x"00", -- M0 0010h
        others => x"00");
    constant mem01 : mem_array := (
        16#0000# => x"06", 16#0001# => x"05",                          -- LD B,5
        16#0002# => x"10", 16#0003# => x"FE",                          -- DJNZ $
        16#0004# => x"3E", 16#0005# => x"03",                          -- LD A,3
        16#0006# => x"3D",                                             -- DEC A
        16#0007# => x"20", 16#0008# => x"FD",                          -- JR NZ,0006h
        16#0009# => x"21", 16#000A# => x"34", 16#000B# => x"12",       -- LD HL,1234h
        16#000C# => x"29",                                             -- ADD HL,HL
        16#000D# => x"ED", 16#000E# => x"56",                          -- IM 1
        16#000F# => x"FB",                                             -- EI
        16#0010# => x"76",                                             -- HALT
        others => x"00");

    signal irq_acked : boolean := false;
begin
    CLK108 <= not CLK108 after 5 ns;

    process (CLK108)
    begin
        if rising_edge(CLK108) then
            CLK54 <= not CLK54;
            if RESET_n = '0' then
                div30_cnt <= (others => '0');
                clk_3m6_internal <= '0';
            elsif div30_cnt = 14 then
                clk_3m6_internal <= not clk_3m6_internal;
                div30_cnt <= (others => '0');
            else
                div30_cnt <= div30_cnt + 1;
            end if;
        end if;
    end process;

    RESET_n <= '1' after 300 ns;

    process (CLK54)
        variable dpipe : std_logic_vector(1 downto 0);
    begin
        if rising_edge(CLK54) then
            dpipe := pf_dpipe(0) & clk_3m6_internal;
            if dpipe = "00" then
                bus_clk_3m6 <= '0';
            elsif dpipe = "11" then
                bus_clk_3m6 <= '1';
            end if;
            pf_dpipe <= dpipe;
            bus_clk_3m6_54 <= bus_clk_3m6;
            bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
            if video_cnt = 29 then
                video_cnt <= 0;
            else
                video_cnt <= video_cnt + 1;
            end if;
            if video_cnt = 0 then
                video_open <= '1';
            else
                video_open <= '0';
            end if;
        end if;
    end process;
    clk_enable_3m6_54  <= '1' when bus_clk_3m6_prev_54 = '0' and bus_clk_3m6_54 = '1' else '0';
    clk_falling_3m6_54 <= '1' when bus_clk_3m6_prev_54 = '1' and bus_clk_3m6_54 = '0' else '0';

    u_cpu : entity work.G80a
        generic map(Mode => 0, IOWait => 1)
        port map(
            RESET_n => RESET_n, CLK_n => CLK54,
            clk_enable => clk_enable_3m6_54, clk_falling => clk_falling_3m6_54,
            WAIT_n => WAIT_n, INT_n => INT_n, NMI_n => '1', BUSRQ_n => '1',
            M1_n => M1_n, MREQ_n => MREQ_n, IORQ_n => IORQ_n, RD_n => RD_n,
            WR_n => WR_n, RFSH_n => RFSH_n, HALT_n => HALT_n, BUSAK_n => BUSAK_n,
            A => A, update_addr => update_addr, A_Bank => A_Bank,
            DI => DI, DO => DO, mode24 => mode24,
            bank_bc => open, bank_de => open, bank_hl => open, bank_ix => open,
            bank_iy => open, bank_pc => open, bank_msp => open, bank_int => open,
            bank_rst => open, Data_Reverse => Data_Reverse);

    DI <= cpu_din;
    WAIT_n <= cpu_sdram_wait_n;

    cpu_sdram_active <= '1' when A_Bank /= x"00" and unsigned(A_Bank) <= CPU_SDRAM_BANK_MAX and
                                 MREQ_n = '0' and (RD_n = '0' or WR_n = '0') and RFSH_n = '1'
                        else '0';
    cpu_sdram_req <= cpu_sdram_active when wait_state = WS_WAITING_DONE else '0';
    cpu_sdram_done <= '1' when sdram_seq = 3 else '0';

    -- fpga/top.v WAIT FSM (v9).
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if RESET_n = '0' then
                cpu_sdram_wait_n <= '1';
                wait_state <= WS_IDLE;
                wait_armed_falls <= 0;
                update_addr_prev <= '0';
                update_addr_prev2 <= '0';
            else
                update_addr_prev <= update_addr;
                update_addr_prev2 <= update_addr_prev;
                case wait_state is
                    when WS_IDLE =>
                        if update_addr_prev = '1' and update_addr_prev2 = '0' and
                           A_Bank /= x"00" and unsigned(A_Bank) <= CPU_SDRAM_BANK_MAX then
                            cpu_sdram_wait_n <= '0';
                            wait_armed_falls <= 0;
                            wait_state <= WS_ARMED;
                        end if;
                    when WS_ARMED =>
                        if clk_falling_3m6_54 = '1' and wait_armed_falls /= 3 then
                            wait_armed_falls <= wait_armed_falls + 1;
                        end if;
                        if cpu_sdram_active = '1' then
                            cpu_sdram_addr_r <= std_logic_vector(CPU_SDRAM_BASE + unsigned(std_logic_vector'(A_Bank & A)));
                            wait_state <= WS_WAITING_DONE;
                        elsif Release_Internal and wait_armed_falls = 3 and MREQ_n = '1' then
                            cpu_sdram_wait_n <= '1';
                            internal_releases <= internal_releases + 1;
                            wait_state <= WS_IDLE;
                        end if;
                    when WS_WAITING_DONE =>
                        if cpu_sdram_done = '1' then
                            cpu_sdram_wait_n <= '1';
                            wait_state <= WS_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Simplified fpga/src/memory.v CPU path: admission waits for the
    -- free-running video window, then data is committed in state 3.
    process (CLK54)
    begin
        if rising_edge(CLK54) then
            case sdram_seq is
                when 0 =>
                    if cpu_sdram_req = '1' and video_open = '1' then
                        sdram_seq <= 1;
                    end if;
                when 1 =>
                    sdram_addr <= cpu_sdram_addr_r;
                    sdram_seq <= 2;
                when 2 =>
                    if video_open = '0' then
                        sdram_seq <= 3;
                    end if;
                when 3 =>
                    if sdram_addr(23 downto 16) = x"65" then
                        cpu_sdram_dout <= mem01(to_integer(unsigned(sdram_addr(15 downto 0))));
                    else
                        cpu_sdram_dout <= x"00";
                    end if;
                    sdram_seq <= 4;
                when 4 =>
                    if cpu_sdram_req = '0' then
                        sdram_seq <= 0;
                    end if;
            end case;
        end if;
    end process;

    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if A_Bank /= x"00" and MREQ_n = '0' and RFSH_n = '1' then
                cpu_din <= cpu_sdram_dout;
            elsif IORQ_n = '0' and M1_n = '0' then
                cpu_din <= x"FF";
            else
                cpu_din <= mem00(to_integer(unsigned(A)));
            end if;
            if A_Bank = x"00" and MREQ_n = '0' and WR_n = '0' then
                mem00(to_integer(unsigned(A))) <= DO;
            end if;
        end if;
    end process;

    process (CLK54)
    begin
        if rising_edge(CLK54) then
            if <<signal u_cpu.u0.IntCycle : std_logic>> = '1' then
                irq_acked <= true;
            end if;
        end if;
    end process;

    -- Raise one IRQ once the CPU is halted in bank01 with IFF enabled.
    process
    begin
        wait until HALT_n = '0' and mode24 = "10";
        wait for 3 us;
        INT_n <= '0';
        wait until irq_acked for 50 us;
        INT_n <= '1';
        wait;
    end process;

    process (RD_n)
    begin
        if Trace and falling_edge(RD_n) and M1_n = '0' then
            report "M1 fetch " & to_hstring(std_logic_vector'(A_Bank & A)) &
                " mode24=" & to_hstring(mode24) & " wait_state=" & wait_state_t'image(wait_state);
        end if;
    end process;

    process
    begin
        wait until mem00(16#4002#) = x"5A" for 2 ms;
        if mem00(16#4002#) /= x"5A" then
            report "FAIL: M2 bank01 internal-cycle program did not finish; wait_state=" &
                wait_state_t'image(wait_state) & " wait_n=" & std_logic'image(cpu_sdram_wait_n) &
                " A=" & to_hstring(std_logic_vector'(A_Bank & A)) & " HALT_n=" & std_logic'image(HALT_n) &
                " MC=" & to_hstring(<<signal u_cpu.u0.MCycle : std_logic_vector(3 downto 0)>>) &
                " TS=" & integer'image(to_integer(<<signal u_cpu.u0.TState : unsigned(2 downto 0)>>)) &
                " IR=" & to_hstring(<<signal u_cpu.u0.IR : std_logic_vector(7 downto 0)>>)
                severity failure;
        end if;
        assert mem00(16#4000#) = x"68" and mem00(16#4001#) = x"24"
            report "FAIL: ADD HL,HL result " & to_hstring(std_logic_vector'(mem00(16#4001#) & mem00(16#4000#))) & ", want 2468h"
            severity failure;
        assert irq_acked and mem00(16#4003#) = x"A5"
            report "FAIL: M2 HALT IRQ from bank01 was not serviced; acked=" & boolean'image(irq_acked) &
                " marker=" & to_hstring(mem00(16#4003#)) severity failure;
        assert internal_releases >= 8
            report "FAIL: only " & integer'image(internal_releases) & " internal-cycle WAIT releases"
            severity failure;
        report "PASS: M2 bank01 DJNZ/JR/ADD HL internal cycles and HALT IRQ acknowledge; releases=" &
            integer'image(internal_releases) severity note;
        std.env.finish;
    end process;
end architecture;
