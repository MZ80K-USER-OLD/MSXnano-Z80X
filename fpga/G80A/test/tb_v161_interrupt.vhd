library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_v161_interrupt is
    generic (
        Cpu_Mode : natural range 0 to 1 := 0;
        Mode_Value : natural range 0 to 2 := 2;
        Initial_IM : natural range 0 to 2 := 2;
        IBR_Value : natural range 0 to 2 := 1;
        NMI_Test : boolean := false;
        Enabled : boolean := true;
        Boundary : boolean := false;
        With_Wait : boolean := false;
        Table_Case : natural range 0 to 3 := 0;
        Trace : boolean := false;
        Syscall_Test : boolean := false
    );
end;

architecture sim of tb_v161_interrupt is
    type memory_t is array (0 to 196607) of std_logic_vector(7 downto 0);
    function code_bank return natural is
    begin
        if Mode_Value /= 2 then return 0;
        elsif IBR_Value = 1 then return 2; else return 1; end if;
    end;
    function target_bank return natural is
    begin
        if Mode_Value = 2 then return IBR_Value; else return 0; end if;
    end;
    function stack_top return natural is
        variable b : natural := IBR_Value;
    begin
        if b = 0 then b := 2; end if;
        if Boundary and (Initial_IM = 2 or Syscall_Test) and not NMI_Test and Table_Case = 2 then
            -- Keep the frame from legitimately overwriting either table byte.
            if IBR_Value = 1 then return 16#010000#;
            elsif IBR_Value = 2 then return 16#010002#; end if;
        end if;
        if Boundary then return b * 65536 + 2; else return b * 65536 + 16#E000#; end if;
    end;
    function frame_top return natural is
    begin
        if Mode_Value = 2 then return stack_top; else return 16#D000#; end if;
    end;
    function frame_width return natural is
    begin
        if Syscall_Test then return 3;
        elsif Mode_Value = 2 then return 4; else return 2; end if;
    end;
    function return_address return natural is
    begin
        if Syscall_Test then return 16#1003#; else return 16#1002#; end if;
    end;
    function table_address return natural is
    begin
        case Table_Case is
            when 0 => return 16#40CF#;
            when 1 => return 16#40FE#;
            when 2 => return 16#FFFF#;
            when others => return 16#4000#;
        end case;
    end;
    function handler_address return natural is
    begin
        if Syscall_Test then return 16#1234#;
        elsif NMI_Test then return 16#66#;
        elsif Initial_IM = 2 then return 16#1234#;
        elsif Initial_IM = 0 and Mode_Value /= 2 then return 8;
        else return 16#38#; end if;
    end;
    function program return memory_t is
        variable m : memory_t := (others => x"00");
        variable p : natural := 16#100#;
        procedure emit(b : natural) is
        begin m(p) := std_logic_vector(to_unsigned(b, 8)); p := p + 1; end;
        procedure word(w : natural) is
        begin emit(w mod 256); emit(w / 256); end;
        procedure ed(b : natural) is
        begin emit(16#ED#); emit(b); end;
    begin
        m(0) := x"C3"; m(1) := x"00"; m(2) := x"01";
        emit(16#31#); word(16#D000#);
        emit(16#3E#); emit(stack_top / 65536); ed(16#24#);
        emit(16#21#); word(stack_top mod 65536); ed(16#35#);
        emit(16#3E#); emit(IBR_Value); ed(16#3A#);
        if target_bank = 0 and Table_Case = 2 then
            emit(16#3E#); emit(16#12#); emit(16#32#); word(0);
        end if;
        emit(16#3E#); emit(table_address / 256); ed(16#47#);
        if Initial_IM = 0 then ed(16#46#);
        elsif Initial_IM = 1 then ed(16#56#);
        else ed(16#5E#); end if;
        emit(16#01#); word(16#00D7#); emit(16#C5#); emit(16#F1#);
        if Enabled then emit(16#FB#); else emit(16#F3#); end if;
        if Mode_Value = 2 then
            ed(16#9B#); word(16#1000#); emit(code_bank);
        else
            ed(16#90# + Mode_Value); emit(16#C3#); word(16#1000#);
        end if;
        p := code_bank * 65536 + 16#1000#;
        if Syscall_Test then
            ed(16#C6#);
            if Mode_Value = 2 then emit(table_address mod 256);
            else
                emit(16#3E#); emit(16#A6#);
                emit(16#32#); word(16#5008#);
            end if;
        else
            emit(0); emit(16#76#); -- Interrupt returns to 1002 after HALT.
        end if;
        emit(16#F5#); emit(16#C1#);
        ed(16#43#); word(16#5000#);
        ed(16#73#); word(16#5002#);
        ed(16#36#); emit(16#22#); word(16#5004#);
        ed(16#2C#); emit(16#32#); word(16#5006#);
        ed(16#EF#); emit(16#32#); word(16#5007#);
        emit(16#76#);
        p := target_bank * 65536 + handler_address;
        if Mode_Value = 2 then
            if Syscall_Test then ed(16#C9#);
            elsif NMI_Test then ed(16#8C#); else ed(16#F3#); end if;
        else
            if NMI_Test then ed(16#45#); else ed(16#4D#); end if;
        end if;
        m(target_bank * 65536 + table_address) := x"34";
        m(target_bank * 65536 + ((table_address + 1) mod 65536)) := x"12";
        if target_bank = 0 and Table_Case = 2 then m(0) := x"C3"; end if;
        return m;
    end;
    signal mem : memory_t := program;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal a : std_logic_vector(15 downto 0);
    signal bank, live, din, dout, pc_bank, msp_bank, ibr : std_logic_vector(7 downto 0);
    signal ts, mc : std_logic_vector(2 downto 0);
    signal writing, io_cycle, halt_n, wait_n, m1_n, int_e, int_cycle_n : std_logic;
    signal int_n, nmi_n : std_logic := '1';
    signal mode24 : std_logic_vector(1 downto 0);
    signal ticks, frame_writes, table_reads : natural := 0;
    signal trigger_tick : natural := 0;
    signal triggered, entered, returned : boolean := false;
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;
    wait_n <= '0' when With_Wait and ticks mod 5 < 2 else '1';
    cpu : entity work.T80
        generic map (Mode => Cpu_Mode, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => wait_n,
            INT_n => int_n, NMI_n => nmi_n, BUSRQ_n => '1',
            M1_n => m1_n, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => halt_n, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => mode24, A_Bank => bank, MC => mc, TS => ts,
            IntCycle_n => int_cycle_n, IntE => int_e, Stop => open,
            bank_bc => open, bank_de => open, bank_hl => open,
            bank_ix => open, bank_iy => open, bank_pc => pc_bank,
            bank_msp => msp_bank, bank_int => open, bank_nvr => open, bank_rst => ibr);
    process(all)
    begin
        live <= x"00";
        if int_cycle_n = '0' and mc = "001" then
            live <= std_logic_vector(to_unsigned(table_address mod 256, 8));
        elsif unsigned(bank) < 3 then
            live <= mem(to_integer(unsigned(bank)) * 65536 + to_integer(unsigned(a)));
        end if;
    end process;
    process(clk)
        variable address : natural;
        variable expected : natural;
    begin
        if rising_edge(clk) then
            ticks <= ticks + 1;
            if ts = "010" and wait_n = '1' then din <= live; end if;
            if reset_n = '1' then
                assert unsigned(bank) < 3 report "Access outside three physical banks" severity failure;
                address := to_integer(unsigned(bank)) * 65536 + to_integer(unsigned(a));
                if Syscall_Test and m1_n = '0' and a = x"1000" and ts = "010" and wait_n = '1' then
                    triggered <= true;
                end if;
                if Syscall_Test and Mode_Value /= 2 and halt_n = '0' then
                    assert mem(16#5008#) = x"A6" and frame_writes = 0 and table_reads = 0
                        report "M0/M1 SYSCALL must be two-byte NOP followed by LD A,A6" severity failure;
                    assert (int_e = '1') = Enabled and
                           to_integer(unsigned(msp_bank)) = stack_top / 65536 and
                           to_integer(unsigned(mem(16#5004#))) = stack_top mod 256 and
                           to_integer(unsigned(mem(16#5005#))) = (stack_top / 256) mod 256 and
                           mem(16#5000#) = x"D7" and mem(16#5002#) = x"00" and mem(16#5003#) = x"D0" and
                           mode24 = std_logic_vector(to_unsigned(Mode_Value, 2)) and
                           to_integer(unsigned(mem(16#5007#))) = IBR_Value
                        report "M0/M1 NOP altered IFF/MSP" severity failure;
                    report "PASS: V16.1 SYSCALL outside M2 two-byte NOP";
                    stop;
                end if;
                if Trace and triggered and ticks < 1000 and ts = "010" and wait_n = '1' then
                    report "bus " & to_hstring(bank) & ":" & to_hstring(a) &
                           " mc=" & to_hstring(mc) & " DI=" & to_hstring(live) &
                           " W=" & std_logic'image(writing) & " M1=" & std_logic'image(m1_n);
                end if;
                if not Syscall_Test and halt_n = '0' and not triggered then
                    triggered <= true;
                    trigger_tick <= ticks;
                    if NMI_Test then nmi_n <= '0'; else int_n <= '0'; end if;
                end if;
                if int_cycle_n = '0' then int_n <= '1'; end if;
                if not Syscall_Test and triggered and not NMI_Test and not Enabled and ticks = trigger_tick + 100 then
                    assert int_cycle_n = '1' and frame_writes = 0 and table_reads = 0 and
                           not entered and not returned and int_e = '0' and
                           mode24 = std_logic_vector(to_unsigned(Mode_Value, 2)) and
                           to_integer(unsigned(pc_bank)) = code_bank and
                           to_integer(unsigned(ibr)) = IBR_Value
                        report "DI failed to block IRQ without side effects" severity failure;
                    report "PASS: V16.1 IBR interrupt disabled IRQ held";
                    stop;
                end if;
                if triggered and writing = '1' and io_cycle = '0' and ts = "010" and wait_n = '1' then
                    mem(address) <= dout;
                    if not entered and not (Syscall_Test and Mode_Value /= 2) then
                        assert frame_writes < frame_width and address = frame_top - 1 - frame_writes
                            report "Wrong interrupt frame address/width" severity failure;
                        if Syscall_Test then
                            case frame_writes is
                                when 0 => expected := code_bank;
                                when 1 => expected := 16#10#;
                                when others => expected := 3;
                            end case;
                        elsif Mode_Value = 2 then
                            case frame_writes is
                                when 0 => expected := 2;
                                when 1 => expected := code_bank;
                                when 2 => expected := 16#10#;
                                when others => expected := 2;
                            end case;
                        elsif frame_writes = 0 then expected := 16#10#;
                        else expected := 2; end if;
                        assert to_integer(unsigned(dout)) = expected
                            report "Wrong interrupt frame byte " & integer'image(frame_writes) &
                                   " got=" & to_hstring(dout) severity failure;
                        frame_writes <= frame_writes + 1;
                    end if;
                elsif writing = '1' and io_cycle = '0' and ts = "010" and wait_n = '1' then
                    mem(address) <= dout;
                end if;
                if (int_cycle_n = '0' or (Syscall_Test and Mode_Value = 2 and triggered and not entered)) and
                   ((Mode_Value = 2 and (mc = "110" or mc = "111")) or
                    (Mode_Value /= 2 and Initial_IM = 2 and (mc = "100" or mc = "101"))) and
                   ts = "010" and wait_n = '1' then
                    assert (Initial_IM = 2 or Syscall_Test) and not NMI_Test report "Unexpected table read" severity failure;
                    assert address = target_bank * 65536 + ((table_address + table_reads) mod 65536)
                        report "Wrong IM2 physical table address " & to_hstring(bank) & ":" & to_hstring(a)
                        severity failure;
                    assert frame_writes = frame_width report "Table read before complete frame" severity failure;
                    table_reads <= table_reads + 1;
                end if;
                if triggered and not entered and m1_n = '0' and int_cycle_n = '1' and ts = "001" and
                   to_integer(unsigned(a)) = handler_address then
                    assert to_integer(unsigned(bank)) = target_bank and frame_writes = frame_width
                        report "Wrong interrupt handler bank/frame" severity failure;
                    assert (int_e = '1') = (Syscall_Test and Enabled) and
                           mode24 = std_logic_vector(to_unsigned(Mode_Value, 2))
                        report "Entry IFF/MODE incorrect" severity failure;
                    entered <= true;
                    nmi_n <= '1';
                end if;
                if entered and not returned and m1_n = '0' and ts = "001" and
                   to_integer(unsigned(a)) = return_address then
                    assert to_integer(unsigned(bank)) = code_bank and
                           mode24 = std_logic_vector(to_unsigned(Mode_Value, 2))
                        report "Wrong physical return PC/MODE" severity failure;
                    assert (int_e = '1') = ((NMI_Test or Syscall_Test) and Enabled)
                        report "RETI.L/RETN.L IFF restoration incorrect" severity failure;
                    returned <= true;
                end if;
                if returned and halt_n = '0' then
                    assert frame_writes = frame_width report "Wrong frame count" severity failure;
                    if (Initial_IM = 2 or Syscall_Test) and not NMI_Test then
                        assert table_reads = 2 report "Missing IM2 reads" severity failure;
                    else
                        assert table_reads = 0 report "Unexpected IM2 reads" severity failure;
                    end if;
                    assert mem(16#5000#) = x"D7" report "Flags modified" severity failure;
                    assert mem(16#5002#) = x"00" and mem(16#5003#) = x"D0" report "SP modified" severity failure;
                    assert to_integer(unsigned(mem(16#5004#))) = stack_top mod 256 and
                           to_integer(unsigned(mem(16#5005#))) = (stack_top / 256) mod 256 and
                           to_integer(unsigned(msp_bank)) = stack_top / 65536 and
                           to_integer(unsigned(mem(16#5006#))) = stack_top / 65536
                        report "MSP not restored" severity failure;
                    assert to_integer(unsigned(ibr)) = IBR_Value and
                           to_integer(unsigned(mem(16#5007#))) = IBR_Value and
                           to_integer(unsigned(pc_bank)) = code_bank
                        report "IBR/PC bank modified" severity failure;
                    if Syscall_Test then
                        report "PASS: V16.1 SYSCALL physical frame, table wrap and RET.L";
                    else
                        report "PASS: V16.1 IBR interrupt, physical frame, IM2 wrap and return";
                    end if;
                    stop;
                end if;
            end if;
        end if;
    end process;
    process
    begin
        wait for 200 us;
        assert false report "Interrupt timeout" severity failure;
    end process;
end;
