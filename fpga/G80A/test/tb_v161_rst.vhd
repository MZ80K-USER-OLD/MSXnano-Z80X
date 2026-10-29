library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_v161_rst is
    generic (
        Mode_Value : natural range 0 to 2 := 2;
        Cpu_Mode : natural range 0 to 1 := 0;
        Code_Bank : natural range 1 to 2 := 1;
        Boundary : boolean := false;
        With_Wait : boolean := false;
        Enabled : boolean := false;
        Long_RST : boolean := false;
        Jump_Mode : natural range 0 to 2 := 0
    );
end;

architecture sim of tb_v161_rst is
    type memory_t is array (0 to 196607) of std_logic_vector(7 downto 0);
    function execution_bank return natural is
    begin
        if Mode_Value = 2 then return Code_Bank; else return 0; end if;
    end;
    function stack_top return natural is
    begin
        if Mode_Value = 2 then
            if Long_RST and Boundary then return Code_Bank * 65536 + 1;
            elsif Boundary then return (3 - Code_Bank) * 65536 + 1;
            else return (3 - Code_Bank) * 65536 + 16#E000#; end if;
        else
            return 16#00E000#;
        end if;
    end;
    function target_bank return natural is
    begin
        if Long_RST then return 3 - Code_Bank; else return execution_bank; end if;
    end;
    function frame_size return natural is
    begin
        if Long_RST then return 3; else return 2; end if;
    end;
    function rst_writes return natural is
    begin
        if Long_RST and Mode_Value /= 2 then return 0; else return frame_size * 8; end if;
    end;
    function msp_top return natural is
    begin
        if Mode_Value = 2 then return stack_top; else return 16#02E000#; end if;
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
        for bank in 0 to 2 loop
            for vector in 0 to 7 loop
                if Long_RST then
                    m(bank * 65536 + vector * 8) := x"ED";
                    m(bank * 65536 + vector * 8 + 1) := x"C9";
                else
                    m(bank * 65536 + vector * 8) := x"C9";
                end if;
            end loop;
        end loop;
        m(0) := x"C3"; m(1) := x"00"; m(2) := x"01";
        emit(16#31#); word(16#E000#);
        if Long_RST then
            ed(16#EF#); emit(16#32#); word(16#5007#); -- IBR reset value.
        end if;
        emit(16#3E#); emit(msp_top / 65536); ed(16#24#);
        emit(16#21#); word(msp_top mod 65536); ed(16#35#);
        emit(16#3E#); emit(3 - Code_Bank); ed(16#3A#); -- RST_B must not select code.
        emit(16#3E#); emit(16#C9#); emit(16#32#); word(0);
        emit(16#01#); word(16#00D7#); emit(16#C5#); emit(16#F1#);
        if Enabled then emit(16#FB#); else emit(16#F3#); end if;
        if Long_RST and Mode_Value = 2 then
            ed(16#90# + Jump_Mode);
            ed(16#9B#); word(16#1000#); emit(Code_Bank);
        elsif Mode_Value = 2 then
            ed(16#92#);
            ed(16#C3#); word(16#1000#); emit(Code_Bank);
        else
            ed(16#90# + Mode_Value);
            emit(16#C3#); word(16#1000#);
        end if;
        p := execution_bank * 65536 + 16#1000#;
        for vector in 0 to 7 loop
            if Long_RST then ed(16#85# + vector * 8);
            else emit(16#C7# + vector * 8); end if;
        end loop;
        if Long_RST then
            -- Retired RST.L encodings must no longer push or branch.
            for vector in 0 to 7 loop ed(16#C7# + vector * 8); end loop;
            ed(16#EF#); emit(16#32#); word(16#5008#);
            emit(16#3E#); emit(16#A6#); ed(16#3E#);
            emit(16#32#); word(16#5009#); -- Retired IBR read is NOP.
        end if;
        emit(16#F5#); emit(16#C1#);
        ed(16#43#); word(16#5000#);
        ed(16#73#); word(16#5002#); -- SP
        ed(16#36#); emit(16#22#); word(16#5004#); -- MSP low word
        ed(16#2C#); emit(16#32#); word(16#5006#);
        emit(16#76#);
        return m;
    end;
    signal mem : memory_t := program;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal a : std_logic_vector(15 downto 0);
    signal bank, live, din, dout, pc_bank, msp_bank, rst_bank, irq_bank : std_logic_vector(7 downto 0);
    signal ts : std_logic_vector(2 downto 0);
    signal writing, io_cycle, halt_n, wait_n, m1_n, int_e : std_logic;
    signal mode24 : std_logic_vector(1 downto 0);
    signal ticks, frame_writes, vector_fetches : natural := 0;
    signal measuring : boolean := false;
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;
    wait_n <= '0' when With_Wait and ticks mod 5 < 2 else '1';
    cpu : entity work.T80
        generic map (Mode => Cpu_Mode, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => wait_n,
            INT_n => '1', NMI_n => '1', BUSRQ_n => '1',
            M1_n => m1_n, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => halt_n, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => mode24, A_Bank => bank, MC => open, TS => ts,
            IntCycle_n => open, IntE => int_e, Stop => open,
            bank_bc => open, bank_de => open, bank_hl => open,
            bank_ix => open, bank_iy => open, bank_pc => pc_bank,
            bank_msp => msp_bank, bank_int => irq_bank, bank_nvr => open, bank_rst => rst_bank);
    process(all)
    begin
        live <= x"00";
        if unsigned(bank) < 3 then
            live <= mem(to_integer(unsigned(bank)) * 65536 + to_integer(unsigned(a)));
        end if;
    end process;
    process(clk)
        variable address, expected_address, vector : natural;
    begin
        if rising_edge(clk) then
            ticks <= ticks + 1;
            if ts = "010" and wait_n = '1' then din <= live; end if;
            if reset_n = '1' then
                assert unsigned(bank) < 3 report "Access outside three banks" severity failure;
                address := to_integer(unsigned(bank)) * 65536 + to_integer(unsigned(a));
                if m1_n = '0' and a = x"1000" and ts = "010" and wait_n = '1' then
                    measuring <= true;
                end if;
                if measuring and m1_n = '0' and unsigned(a) < 64 and
                   a(2 downto 0) = "000" and ts = "010" and wait_n = '1' then
                    assert not Long_RST or Mode_Value = 2
                        report "M0/M1 RST.L must be NOP" severity failure;
                    assert to_integer(unsigned(bank)) = target_bank
                        report "RST selected wrong code bank" severity failure;
                    assert to_integer(unsigned(a)) = vector_fetches * 8
                        report "Wrong RST vector" severity failure;
                    vector_fetches <= vector_fetches + 1;
                end if;
                if writing = '1' and io_cycle = '0' and ts = "010" and wait_n = '1' then
                    mem(address) <= dout;
                    if measuring and frame_writes < rst_writes then
                        vector := frame_writes / frame_size;
                        expected_address := stack_top - 1 - (frame_writes mod frame_size);
                        assert address = expected_address report "Wrong RST frame address" severity failure;
                        if Long_RST and frame_writes mod 3 = 0 then
                            assert to_integer(unsigned(dout)) = Code_Bank
                                report "Wrong return PC bank" severity failure;
                        elsif frame_writes mod frame_size = frame_size - 2 then
                            assert dout = x"10" report "Wrong return PC high" severity failure;
                        else
                            assert to_integer(unsigned(dout)) = (vector + 1) * (frame_size - 1)
                                report "Wrong return PC low" severity failure;
                        end if;
                        frame_writes <= frame_writes + 1;
                    elsif measuring and address >= stack_top - 2 and address < stack_top then
                        frame_writes <= frame_writes + 1; -- Final PUSH AF.
                    end if;
                end if;
            end if;
        end if;
    end process;
    process
    begin
        wait until halt_n = '0';
        wait for 100 ns;
        assert vector_fetches = rst_writes / frame_size and frame_writes = rst_writes + 2
            report "Wrong vector count or frame width" severity failure;
        assert mem(16#5000#) = x"D7" report "Flags modified" severity failure;
        assert mem(16#5002#) = x"00" and mem(16#5003#) = x"E0"
            report "SP modified" severity failure;
        assert mem(16#5004#) = std_logic_vector(to_unsigned(msp_top mod 256, 8)) and
               mem(16#5005#) = std_logic_vector(to_unsigned((msp_top / 256) mod 256, 8)) and
               to_integer(unsigned(msp_bank)) = msp_top / 65536 and
               to_integer(unsigned(mem(16#5006#))) = msp_top / 65536
            report "MSP modified" severity failure;
        assert to_integer(unsigned(pc_bank)) = execution_bank and
               mode24 = std_logic_vector(to_unsigned(Mode_Value, 2))
            report "PC bank or MODE modified" severity failure;
        assert to_integer(unsigned(rst_bank)) = 3 - Code_Bank
            report "RST bank register modified" severity failure;
        assert (int_e = '1') = Enabled report "IFF modified" severity failure;
        if Long_RST then
            assert irq_bank = x"00" report "JP.M2 retained obsolete IVR write side effect" severity failure;
            assert mem(16#5007#) = x"00" and
                   to_integer(unsigned(mem(16#5008#))) = 3 - Code_Bank and mem(16#5009#) = x"A6"
                report "IBR reset/readback or retired read failed" severity failure;
            report "PASS: V16.1 RST.L vectors, frames, RET.L, JP.M2, IBR and retired opcodes";
        else
            report "PASS: eight ordinary RST vectors, two-byte frames, RET, banks, F and IFF";
        end if;
        stop;
        wait;
    end process;
    process
    begin
        wait for 200 us;
        assert false report "Timeout" severity failure;
    end process;
end;
