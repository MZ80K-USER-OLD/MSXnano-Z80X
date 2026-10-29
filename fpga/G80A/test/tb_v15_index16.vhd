library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_v15_index16 is
    generic (
        Index_IY : boolean := false;
        Pair_Number : natural range 0 to 2 := 0;
        Store_Pair : boolean := false;
        Cpu_Mode : natural range 0 to 1 := 0;
        Mode24_Value : natural range 0 to 2 := 1;
        Scenario : natural range 0 to 4 := 0;
        Transfer24 : boolean := false;
        With_Wait : boolean := false;
        Dump_Records : boolean := false
    );
end;

architecture sim of tb_v15_index16 is
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    function index_prefix return natural is
    begin
        if Index_IY then return 16#FD#; else return 16#DD#; end if;
    end;
    function base_address return natural is
    begin
        case Scenario is
            when 0 => return 16#FFFF#;
            when 1 => return 0;
            when 2 => return 16#8080#;
            when 3 => return 16#FF80#;
            when 4 => return 16#FFFE#;
        end case;
    end;
    function displacement return natural is
    begin
        case Scenario is
            when 0 => return 0;
            when 1 => return 16#FF#;
            when 2 => return 16#80#;
            when 3 => return 16#7F#;
            when 4 => return 0;
        end case;
    end;
    function target_address return natural is
    begin
        case Scenario is
            when 0 => return 16#01FFFF#;
            when 1 => return 16#00FFFF#;
            when 2 => return 16#018000#;
            when 3 => return 16#01FFFF#;
            when 4 => return 16#01FFFE#;
        end case;
    end;
    function transfer_opcode return natural is
    begin
        if Transfer24 then
            if Store_Pair then return 16#20# + Pair_Number * 8;
            else return 16#08# + Pair_Number * 8; end if;
        else
            if Store_Pair then return 16#0F# + Pair_Number * 16;
            else return 16#07# + Pair_Number * 16; end if;
        end if;
    end;
    function transfer_bytes return natural is
    begin
        if Transfer24 then return 3; else return 2; end if;
    end;
    function program return memory_t is
        variable m : memory_t := (others => x"00");
        variable p : natural := 0;
        procedure emit(b : natural) is
        begin m(p) := std_logic_vector(to_unsigned(b, 8)); p := p + 1; end;
        procedure word(w : natural) is
        begin emit(w mod 256); emit(w / 256); end;
        procedure m0_sample(prefixed : boolean; destination : natural) is
        begin
            emit(16#01#); word(16#28A5#); emit(16#C5#); emit(16#F1#); emit(16#08#);
            emit(16#01#); word(16#15D7#); emit(16#C5#); emit(16#F1#);
            emit(16#01#); word(16#BEEF#);
            emit(16#11#); word(16#BEEF#);
            emit(16#21#); word(16#BEEF#);
            if prefixed then emit(index_prefix); end if;
            emit(transfer_opcode);
            if Transfer24 and transfer_opcode = 16#08# then
                emit(16#3C#); -- INC A must not be consumed as displacement.
            else
                emit(0); -- Original JR/DJNZ displacement or a NOP.
            end if;
            emit(16#ED#); emit(16#43#); word(destination);
            emit(16#ED#); emit(16#53#); word(destination + 2);
            emit(16#22#); word(destination + 4);
            emit(16#F5#); emit(16#C1#);
            emit(16#ED#); emit(16#43#); word(destination + 6);
        end;
    begin
        emit(16#31#); word(16#E000#);
        if Mode24_Value = 0 then
            emit(index_prefix); emit(16#21#); word(base_address);
            m0_sample(false, 16#4100#);
            m0_sample(true, 16#4110#);
            emit(16#76#);
            return m;
        end if;
        emit(16#21#); word(16#E000#);
        emit(16#AF#); emit(16#ED#); emit(16#24#);
        emit(16#ED#); emit(16#35#); -- MSP = 00:E000
        emit(16#3E#); emit(1);
        emit(16#ED#);
        if Index_IY then emit(16#15#); else emit(16#05#); end if;
        emit(index_prefix); emit(16#21#); word(base_address);
        emit(16#3E#); emit(16#67#);
        emit(16#ED#); emit(16#04# + Pair_Number * 16);
        emit(16#ED#); emit(16#90# + Mode24_Value);
        emit(16#01#); word(16#00D7#); emit(16#C5#); emit(16#F1#);
        emit(16#01#); word(16#1357#);
        emit(16#11#); word(16#2468#);
        emit(16#21#); word(16#369C#);
        emit(16#01# + Pair_Number * 16);
        if Store_Pair then word(16#BEEF#); else word(16#1234#); end if;
        emit(index_prefix);
        emit(transfer_opcode);
        emit(displacement);
        if Pair_Number = 2 then emit(16#22#);
        else emit(16#ED#); emit(16#43# + Pair_Number * 16); end if;
        word(16#4000#);
        emit(16#ED#); emit(16#43#); word(16#4020#);
        emit(16#ED#); emit(16#53#); word(16#4022#);
        emit(16#22#); word(16#4024#);
        emit(index_prefix); emit(16#22#); word(16#4002#);
        emit(16#F5#); emit(16#C1#); emit(16#ED#); emit(16#43#); word(16#4004#);
        emit(16#76#);
        m(16#FFFF#) := x"EF";
        return m;
    end;
    function data_bank(number : natural) return memory_t is
        variable m : memory_t := (others => x"00");
    begin
        if not Store_Pair and Mode24_Value /= 0 then
            if target_address / 65536 = number then
                m(target_address mod 65536) := x"EF";
            end if;
            if (target_address + 1) / 65536 = number then
                m((target_address + 1) mod 65536) := x"BE";
            end if;
            if Transfer24 and (target_address + 2) / 65536 = number then
                m((target_address + 2) mod 65536) := x"A5";
            end if;
        end if;
        return m;
    end;
    signal mem00 : memory_t := program;
    signal mem01 : memory_t := data_bank(1);
    signal mem02 : memory_t := data_bank(2);
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal a : std_logic_vector(15 downto 0);
    signal bank, live, din, dout, bc_bank, de_bank, hl_bank, ix_bank, iy_bank : std_logic_vector(7 downto 0);
    signal ts : std_logic_vector(2 downto 0);
    signal writing, io_cycle, halt_n, wait_n : std_logic;
    signal ticks : natural := 0;
    signal target_writes : natural := 0;
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;
    wait_n <= '0' when With_Wait and ticks mod 5 < 2 else '1';
    cpu : entity work.T80
        generic map (Mode => Cpu_Mode, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => wait_n,
            INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
            M1_n => open, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => halt_n, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => open, A_Bank => bank, MC => open, TS => ts,
            IntCycle_n => open, IntE => open, Stop => open,
            bank_bc => bc_bank, bank_de => de_bank, bank_hl => hl_bank,
            bank_ix => ix_bank, bank_iy => iy_bank, bank_pc => open,
            bank_msp => open, bank_int => open, bank_nvr => open, bank_rst => open);

    process (all)
    begin
        case bank is
            when x"00" => live <= mem00(to_integer(unsigned(a)));
            when x"01" => live <= mem01(to_integer(unsigned(a)));
            when x"02" => live <= mem02(to_integer(unsigned(a)));
            when others => live <= x"00";
        end case;
    end process;
    process (clk)
        variable addr : natural;
    begin
        if rising_edge(clk) then
            ticks <= ticks + 1;
            if ts = "010" and wait_n = '1' then din <= live; end if;
            if reset_n = '1' and writing = '1' and io_cycle = '0' and
               ts = "010" and wait_n = '1' then
                addr := to_integer(unsigned(bank)) * 65536 + to_integer(unsigned(a));
                if addr >= target_address and addr < target_address + transfer_bytes then
                    target_writes <= target_writes + 1;
                    assert Store_Pair report "Unexpected target write" severity failure;
                    if addr = target_address then
                        assert dout = x"EF" report "Wrong low byte" severity failure;
                    elsif addr = target_address + 1 then
                        assert dout = x"BE" report "Wrong high byte" severity failure;
                    else
                        assert dout = x"67" report "Wrong bank byte" severity failure;
                    end if;
                end if;
                case bank is
                    when x"00" => mem00(to_integer(unsigned(a))) <= dout;
                    when x"01" => mem01(to_integer(unsigned(a))) <= dout;
                    when x"02" => mem02(to_integer(unsigned(a))) <= dout;
                    when others => assert false report "Unexpected write bank" severity failure;
                end case;
            end if;
        end if;
    end process;
    process
        variable image : memory_t;
        variable program_hex : string(1 to 512);
        variable reference_hex, actual_hex : string(1 to 16);
        variable expected_bank : std_logic_vector(7 downto 0);
        variable expected_word : natural;
    begin
        if Dump_Records then
            image := program;
            for i in 0 to 255 loop
                program_hex(i * 2 + 1 to i * 2 + 2) := to_hstring(image(i));
            end loop;
            report "INPUT_PROGRAM " & program_hex;
        end if;
        wait until halt_n = '0';
        wait for 100 ns;
        if Mode24_Value = 0 then
            if Dump_Records then
                for i in 0 to 7 loop
                    reference_hex(i * 2 + 1 to i * 2 + 2) := to_hstring(mem00(16#4100# + i));
                    actual_hex(i * 2 + 1 to i * 2 + 2) := to_hstring(mem00(16#4110# + i));
                end loop;
                report "RESULT_M0 reference=" & reference_hex & " actual=" & actual_hex;
            end if;
            for i in 0 to 7 loop
                assert mem00(16#4100# + i) = mem00(16#4110# + i)
                    report "M0 prefix compatibility failed at byte " & integer'image(i)
                    severity failure;
            end loop;
            assert target_writes = 0 severity failure;
            report "PASS: M0 indexed opcode remains Z80 compatible";
            stop;
            wait;
        end if;
        if Dump_Records then
            report "RESULT_M12 pair=" & to_hstring(mem00(16#4001#)) & to_hstring(mem00(16#4000#)) &
                " index=" & to_hstring(mem00(16#4003#)) & to_hstring(mem00(16#4002#)) &
                " flags=" & to_hstring(mem00(16#4004#)) &
                " bc_bank=" & to_hstring(bc_bank) & " de_bank=" & to_hstring(de_bank) &
                " hl_bank=" & to_hstring(hl_bank) & " ix_bank=" & to_hstring(ix_bank) &
                " iy_bank=" & to_hstring(iy_bank) &
                " target_writes=" & integer'image(target_writes);
        end if;
        assert mem00(16#4000#) = x"EF" and mem00(16#4001#) = x"BE"
            report "Pair transfer failed: " & to_hstring(mem00(16#4001#)) &
                   to_hstring(mem00(16#4000#)) severity failure;
        assert mem00(16#4002#) = std_logic_vector(to_unsigned(base_address mod 256, 8)) and
               mem00(16#4003#) = std_logic_vector(to_unsigned(base_address / 256, 8))
            report "Index register modified" severity failure;
        assert mem00(16#4004#) = x"D7" report "Flags modified" severity failure;
        expected_bank := x"67";
        if Transfer24 and not Store_Pair then expected_bank := x"A5"; end if;
        for pair in 0 to 2 loop
            if pair = Pair_Number then expected_word := 16#BEEF#;
            elsif pair = 0 then expected_word := 16#1357#;
            elsif pair = 1 then expected_word := 16#2468#;
            else expected_word := 16#369C#; end if;
            assert mem00(16#4020# + pair * 2) = std_logic_vector(to_unsigned(expected_word mod 256, 8)) and
                   mem00(16#4021# + pair * 2) = std_logic_vector(to_unsigned(expected_word / 256, 8))
                report "Pair preservation failed" severity failure;
        end loop;
        if Pair_Number = 0 then
            assert bc_bank = expected_bank and de_bank = x"00" and hl_bank = x"00" severity failure;
        elsif Pair_Number = 1 then
            assert de_bank = expected_bank and bc_bank = x"00" and hl_bank = x"00" severity failure;
        else
            assert hl_bank = expected_bank and bc_bank = x"00" and de_bank = x"00" severity failure;
        end if;
        if Index_IY then assert iy_bank = x"01" severity failure;
        else assert ix_bank = x"01" severity failure; end if;
        if Store_Pair then assert target_writes = transfer_bytes report "Wrong write count" severity failure;
        else assert target_writes = 0 severity failure; end if;
        report "PASS: V15 indexed pair transfer";
        stop;
        wait;
    end process;
    process
    begin
        wait for 200 us;
        assert false report "Timeout" severity failure;
    end process;
end;
