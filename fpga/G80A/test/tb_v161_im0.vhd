library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_v161_im0 is
    generic (
        Entry_Path : natural range 0 to 8 := 0;
        Initial_IM : natural range 0 to 2 := 0;
        Mirror : natural range 0 to 4 := 0;
        Enabled : boolean := false
    );
end;

architecture sim of tb_v161_im0 is
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    function program return memory_t is
        variable m : memory_t := (others => x"00");
        variable p : natural := 16#100#;
        procedure emit(b : natural) is
        begin m(p) := std_logic_vector(to_unsigned(b, 8)); p := p + 1; end;
        procedure ed(b : natural) is
        begin emit(16#ED#); emit(b); end;
    begin
        emit(16#31#); emit(0); emit(16#90#);
        emit(16#21#); emit(0); emit(16#80#); ed(16#35#);
        emit(16#3E#); emit(16#40#); ed(16#47#); -- I=40
        if Initial_IM = 0 then ed(16#46#);
        elsif Initial_IM = 1 then ed(16#56#);
        else ed(16#5E#); end if;
        if Entry_Path = 1 then ed(16#91#); end if;
        emit(16#01#); emit(16#D7#); emit(0); emit(16#C5#); emit(16#F1#);
        if Enabled then emit(16#FB#); else emit(16#F3#); end if;
        emit(0);
        case Entry_Path is
            when 0 | 1 => ed(16#92#); emit(16#C3#); emit(0); emit(2);
            when 2 => ed(16#9B#); emit(0); emit(2); emit(0); -- V16.1 JP.M2
            when 3 => ed(16#98#); emit(0); emit(2); emit(0);
            when 4 => ed(16#99#);
            when 5 => ed(16#F3#);
            when 6 => ed(16#8C#);
            when 7 | 8 =>
                if Entry_Path = 8 then ed(16#91#); end if;
                emit(16#C3#); emit(0); emit(2);
        end case;
        m(16#8000#) := x"00"; m(16#8001#) := x"02";
        m(16#8002#) := x"00"; m(16#8003#) := x"02";
        p := 16#200#;
        if Mirror /= 0 then
            case Mirror is
                when 1 => ed(16#46#);
                when 2 => ed(16#4E#);
                when 3 => ed(16#66#);
                when others => ed(16#6E#);
            end case;
        end if;
        ed(16#92#); -- Repeat SET_M2 to check preservation of IM2.
        if Entry_Path >= 7 then m(p - 1) := x"91"; end if;
        emit(16#F5#); emit(16#C1#);
        ed(16#43#); emit(0); emit(16#50#); -- Saved F, A
        emit(16#3E#); emit(16#A5#); emit(16#32#); emit(2); emit(16#50#);
        ed(16#90#);
        emit(16#FB#); emit(16#76#); -- IRQ after return to M0.
        m(16#40CF#) := x"34"; m(16#40D0#) := x"12";
        return m;
    end;
    signal mem : memory_t := program;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal a : std_logic_vector(15 downto 0);
    signal bank, live, din, dout : std_logic_vector(7 downto 0);
    signal ts, mc : std_logic_vector(2 downto 0);
    signal writing, io_cycle, halt_n, int_cycle_n, int_e, m1_n : std_logic;
    signal mode24 : std_logic_vector(1 downto 0);
    signal int_n : std_logic := '1';
    signal seen_irq : boolean := false;
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;
    live <= x"CF" when int_cycle_n = '0' and mc = "001" else mem(to_integer(unsigned(a)));
    cpu : entity work.T80
        generic map (Mode => 0, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => '1',
            INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
            M1_n => m1_n, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => halt_n, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => mode24, A_Bank => bank, MC => mc, TS => ts,
            IntCycle_n => int_cycle_n, IntE => int_e, Stop => open,
            bank_bc => open, bank_de => open, bank_hl => open,
            bank_ix => open, bank_iy => open, bank_pc => open,
            bank_msp => open, bank_int => open, bank_rst => open);
    process(clk)
        variable expected_im : natural;
        variable target : natural;
    begin
        if rising_edge(clk) and reset_n = '1' then
            assert bank = x"00" report "Unexpected bank" severity failure;
            if ts = "010" then din <= live; end if;
            if writing = '1' and io_cycle = '0' and ts = "010" then
                mem(to_integer(unsigned(a))) <= dout;
                if a = x"5002" then
                    if Entry_Path < 7 then
                        assert mode24 = "10" report "Missing M2 entry" severity failure;
                    else
                        assert mode24 = "01" report "Control mode mismatch" severity failure;
                    end if;
                    assert (int_e = '1') = Enabled report "IFF changed" severity failure;
                    assert mem(16#5000#) = x"D7" report "Flags changed" severity failure;
                end if;
            end if;
            if halt_n = '0' then int_n <= '0'; end if;
            if int_cycle_n = '0' then seen_irq <= true; int_n <= '1'; end if;
            if seen_irq and int_cycle_n = '1' and m1_n = '0' and ts = "001" then
                expected_im := Initial_IM;
                if Entry_Path < 7 then
                    if Initial_IM = 0 or Mirror /= 0 then expected_im := 1; end if;
                elsif Mirror /= 0 then expected_im := 0;
                end if;
                case expected_im is
                    when 0 => target := 8; -- Supplied RST 08h.
                    when 1 => target := 16#38#;
                    when others => target := 16#1234#;
                end case;
                assert unsigned(a) = target
                    report "Wrong interrupt mode target: " & to_hstring(a) severity failure;
                assert mem(16#5002#) = x"A5" report "Measurement not reached" severity failure;
                report "PASS: V16.1 IM0 transition and IRQ target";
                stop;
            end if;
        end if;
    end process;
    process
    begin
        wait for 100 us;
        assert false report "Timeout" severity failure;
    end process;
end;
