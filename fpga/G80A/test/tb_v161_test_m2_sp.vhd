-- Verify all TEST/TEST24 register forms and M2 active-SP instructions.
-- Run from fpga/G80A:
--   ghdl -a --std=08 t80_pack.vhd t80_mcode.vhd t80_alu.vhd t80_reg.vhd t80.vhd test/tb_v161_test_m2_sp.vhd
--   ghdl -e --std=08 tb_v161_test_m2_sp
--   ghdl -r --std=08 tb_v161_test_m2_sp --assert-level=error
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_v161_test_m2_sp is
end entity tb_v161_test_m2_sp;

architecture sim of tb_v161_test_m2_sp is
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
    type byte_array is array(natural range <>) of std_logic_vector(7 downto 0);

    constant program : byte_array(0 to 473) := (
        x"ED", x"91", x"01", x"B5", x"00", x"C5", x"F1", x"01",
        x"34", x"12", x"ED", x"D3", x"F5", x"C1", x"79", x"32",
        x"00", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"01",
        x"00", x"00", x"ED", x"D3", x"F5", x"C1", x"79", x"32",
        x"01", x"41", x"01", x"B5", x"00", x"C5", x"F1", x"11",
        x"45", x"23", x"ED", x"D6", x"F5", x"C1", x"79", x"32",
        x"02", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"11",
        x"00", x"00", x"ED", x"D6", x"F5", x"C1", x"79", x"32",
        x"03", x"41", x"01", x"B5", x"00", x"C5", x"F1", x"21",
        x"56", x"34", x"ED", x"D9", x"F5", x"C1", x"79", x"32",
        x"04", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"21",
        x"00", x"00", x"ED", x"D9", x"F5", x"C1", x"79", x"32",
        x"05", x"41", x"01", x"B5", x"00", x"C5", x"F1", x"DD",
        x"21", x"67", x"45", x"ED", x"DB", x"F5", x"C1", x"79",
        x"32", x"06", x"41", x"01", x"F5", x"00", x"C5", x"F1",
        x"DD", x"21", x"00", x"00", x"ED", x"DB", x"F5", x"C1",
        x"79", x"32", x"07", x"41", x"01", x"B5", x"00", x"C5",
        x"F1", x"FD", x"21", x"78", x"56", x"ED", x"DD", x"F5",
        x"C1", x"79", x"32", x"08", x"41", x"01", x"F5", x"00",
        x"C5", x"F1", x"FD", x"21", x"00", x"00", x"ED", x"DD",
        x"F5", x"C1", x"79", x"32", x"09", x"41", x"01", x"B5",
        x"00", x"C5", x"F1", x"01", x"34", x"12", x"3E", x"12",
        x"ED", x"04", x"ED", x"DE", x"F5", x"C1", x"79", x"32",
        x"0A", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"01",
        x"00", x"00", x"3E", x"00", x"ED", x"04", x"ED", x"DE",
        x"F5", x"C1", x"79", x"32", x"0B", x"41", x"01", x"B5",
        x"00", x"C5", x"F1", x"11", x"45", x"23", x"3E", x"12",
        x"ED", x"14", x"ED", x"DF", x"F5", x"C1", x"79", x"32",
        x"0C", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"11",
        x"00", x"00", x"3E", x"00", x"ED", x"14", x"ED", x"DF",
        x"F5", x"C1", x"79", x"32", x"0D", x"41", x"01", x"B5",
        x"00", x"C5", x"F1", x"21", x"56", x"34", x"3E", x"12",
        x"ED", x"24", x"ED", x"F5", x"F5", x"C1", x"79", x"32",
        x"0E", x"41", x"01", x"F5", x"00", x"C5", x"F1", x"21",
        x"00", x"00", x"3E", x"00", x"ED", x"24", x"ED", x"F5",
        x"F5", x"C1", x"79", x"32", x"0F", x"41", x"01", x"B5",
        x"00", x"C5", x"F1", x"DD", x"21", x"67", x"45", x"3E",
        x"12", x"ED", x"05", x"ED", x"F6", x"F5", x"C1", x"79",
        x"32", x"10", x"41", x"01", x"F5", x"00", x"C5", x"F1",
        x"DD", x"21", x"00", x"00", x"3E", x"00", x"ED", x"05",
        x"ED", x"F6", x"F5", x"C1", x"79", x"32", x"11", x"41",
        x"01", x"B5", x"00", x"C5", x"F1", x"FD", x"21", x"78",
        x"56", x"3E", x"12", x"ED", x"15", x"ED", x"F7", x"F5",
        x"C1", x"79", x"32", x"12", x"41", x"01", x"F5", x"00",
        x"C5", x"F1", x"FD", x"21", x"00", x"00", x"3E", x"00",
        x"ED", x"15", x"ED", x"F7", x"F5", x"C1", x"79", x"32",
        x"13", x"41", x"31", x"00", x"D0", x"ED", x"92", x"21",
        x"FF", x"FF", x"3E", x"01", x"ED", x"24", x"F9", x"33",
        x"ED", x"36", x"22", x"00", x"42", x"ED", x"2C", x"32",
        x"02", x"42", x"3B", x"ED", x"36", x"22", x"03", x"42",
        x"ED", x"2C", x"32", x"05", x"42", x"21", x"00", x"00",
        x"3E", x"00", x"ED", x"24", x"F9", x"3B", x"ED", x"36",
        x"22", x"06", x"42", x"ED", x"2C", x"32", x"08", x"42",
        x"33", x"ED", x"36", x"22", x"09", x"42", x"ED", x"2C",
        x"32", x"0B", x"42", x"21", x"34", x"12", x"3E", x"56",
        x"ED", x"24", x"F9", x"ED", x"36", x"22", x"0C", x"42",
        x"ED", x"2C", x"32", x"0E", x"42", x"DD", x"21", x"CD",
        x"AB", x"3E", x"78", x"ED", x"05", x"DD", x"F9", x"ED",
        x"36", x"22", x"0F", x"42", x"ED", x"2C", x"32", x"11",
        x"42", x"76");

    function init_mem return mem_array is
        variable result : mem_array := (others => x"00");
    begin
        for i in program'range loop
            result(i) := program(i);
        end loop;
        return result;
    end function;

    signal mem : mem_array := init_mem;
begin
    u0 : T80
        generic map(Mode => 0, IOWait => 0)
        port map(
            RESET_n => RESET_n, CLK_n => CLK_n, CEN => CEN, WAIT_n => WAIT_n,
            INT_n => INT_n, NMI_n => NMI_n, BUSRQ_n => BUSRQ_n,
            M1_n => M1_n, IORQ => IORQ, NoRead => NoRead, Write => Write,
            RFSH_n => RFSH_n, HALT_n => HALT_n, BUSAK_n => BUSAK_n,
            A => A, update_addr => update_addr, DInst => DInst, DI => DI,
            DO => DO, mode24 => mode24, bank_bc => bank_bc, bank_de => bank_de,
            bank_hl => bank_hl, bank_ix => bank_ix, bank_iy => bank_iy,
            bank_pc => bank_pc, bank_msp => bank_msp, bank_int => bank_int,
            bank_rst => bank_rst, A_Bank => A_Bank, MC => MC, TS => TS,
            IntCycle_n => IntCycle_n, IntE => IntE, Stop => Stop);

    DI_live <= mem(to_integer(unsigned(A)));
    DInst <= DI_live;

    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if TS = "010" and WAIT_n = '1' then
                DI <= DI_live;
            end if;
            if IORQ = '0' and Write = '1' then
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
        variable expected_flag : std_logic_vector(7 downto 0);
    begin
        wait until HALT_n = '0';
        wait for 200 ns;

        for i in 0 to 19 loop
            if i mod 2 = 0 then
                expected_flag := x"B5";
            else
                expected_flag := x"F5";
            end if;
            assert mem(16#4100# + i) = expected_flag
                report "TEST register-zero result/flag-preservation mismatch at case " &
                    integer'image(i) & ", got " & to_hstring(mem(16#4100# + i)) &
                    ", expected " & to_hstring(expected_flag)
                severity failure;
        end loop;

        assert mem(16#4200#) = x"00" and mem(16#4201#) = x"00" and mem(16#4202#) = x"02"
            report "INC SP in M2 did not wrap MSP24 from 01:FFFF to 02:0000" severity failure;
        assert mem(16#4203#) = x"FF" and mem(16#4204#) = x"FF" and mem(16#4205#) = x"01"
            report "DEC SP in M2 did not return MSP24 to 01:FFFF" severity failure;
        assert mem(16#4206#) = x"FF" and mem(16#4207#) = x"FF" and mem(16#4208#) = x"FF"
            report "DEC SP in M2 did not borrow across the 24bit bank boundary" severity failure;
        assert mem(16#4209#) = x"00" and mem(16#420A#) = x"00" and mem(16#420B#) = x"00"
            report "INC SP in M2 did not carry across the 24bit bank boundary" severity failure;
        assert mem(16#420C#) = x"34" and mem(16#420D#) = x"12" and mem(16#420E#) = x"56"
            report "LD SP,HL in M2 did not load the complete HL24 value into MSP24" severity failure;
        assert mem(16#420F#) = x"CD" and mem(16#4210#) = x"AB" and mem(16#4211#) = x"78"
            report "LD SP,IX in M2 did not load the complete IX24 value into MSP24" severity failure;

        report "V16.1 TEST and M2 SP testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

    process
    begin
        wait for 1 ms;
        assert HALT_n = '0' report "TEST/M2 SP test program did not reach HALT" severity failure;
        wait;
    end process;
end architecture sim;
