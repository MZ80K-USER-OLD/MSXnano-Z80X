-- Self-checking regression for M1/M2 boundary flags and the newly added
-- DD/FD+ED index-target operations. Covers WTOC, MSP immediate load,
-- representative IX/IY 24bit arithmetic, and IX/IY PUSH24/POP24.
-- Run from fpga/G80A:
--   ghdl -a --std=08 t80_pack.vhd t80_mcode.vhd t80_alu.vhd t80_reg.vhd t80.vhd test/tb_v161_opcode_extensions.vhd
--   ghdl -e --std=08 tb_v161_opcode_extensions
--   ghdl -r --std=08 tb_v161_opcode_extensions --assert-level=error
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity tb_v161_opcode_extensions is
end entity tb_v161_opcode_extensions;

architecture sim of tb_v161_opcode_extensions is
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

    constant program : byte_array(0 to 310) := (
        x"31", x"00", x"E0", x"ED", x"91", x"01", x"FF", x"FF",
        x"03", x"F5", x"C1", x"79", x"32", x"10", x"40", x"01",
        x"01", x"00", x"03", x"F5", x"C1", x"79", x"32", x"11",
        x"40", x"11", x"00", x"00", x"1B", x"F5", x"C1", x"79",
        x"32", x"12", x"40", x"21", x"FF", x"FF", x"23", x"F5",
        x"C1", x"79", x"32", x"13", x"40", x"DD", x"21", x"FF",
        x"FF", x"3E", x"12", x"ED", x"05", x"DD", x"23", x"F5",
        x"C1", x"79", x"32", x"14", x"40", x"FD", x"21", x"00",
        x"00", x"3E", x"34", x"ED", x"15", x"FD", x"2B", x"F5",
        x"C1", x"79", x"32", x"15", x"40", x"ED", x"FE", x"F5",
        x"C1", x"79", x"32", x"16", x"40", x"01", x"00", x"00",
        x"03", x"ED", x"FE", x"F5", x"C1", x"79", x"32", x"17",
        x"40", x"DD", x"21", x"FF", x"FF", x"3E", x"12", x"ED",
        x"05", x"01", x"01", x"00", x"3E", x"00", x"ED", x"04",
        x"DD", x"ED", x"09", x"DD", x"22", x"20", x"40", x"ED",
        x"0D", x"32", x"22", x"40", x"DD", x"ED", x"23", x"DD",
        x"22", x"23", x"40", x"ED", x"0D", x"32", x"25", x"40",
        x"FD", x"21", x"00", x"00", x"3E", x"00", x"ED", x"15",
        x"11", x"01", x"00", x"3E", x"00", x"ED", x"14", x"AF",
        x"FD", x"ED", x"1F", x"FD", x"22", x"30", x"40", x"ED",
        x"1D", x"32", x"32", x"40", x"FD", x"ED", x"19", x"FD",
        x"22", x"33", x"40", x"ED", x"1D", x"32", x"35", x"40",
        x"FD", x"21", x"00", x"00", x"3E", x"00", x"ED", x"15",
        x"FD", x"ED", x"2B", x"FD", x"22", x"36", x"40", x"ED",
        x"1D", x"32", x"38", x"40", x"ED", x"34", x"34", x"12",
        x"01", x"ED", x"36", x"22", x"40", x"40", x"ED", x"2C",
        x"32", x"42", x"40", x"ED", x"92", x"ED", x"34", x"00",
        x"10",
        x"00", x"DD", x"ED", x"E5", x"DD", x"21", x"00", x"00",
        x"3E", x"00", x"ED", x"05", x"DD", x"ED", x"E1", x"DD",
        x"22", x"50", x"40", x"ED", x"0D", x"32", x"52", x"40",
        x"3A", x"FD", x"0F", x"32", x"90", x"40", x"3A", x"FE",
        x"0F", x"32", x"91", x"40", x"3A", x"FF", x"0F", x"32",
        x"92", x"40", x"ED", x"36", x"22", x"60", x"40", x"ED",
        x"2C", x"32", x"62", x"40", x"FD", x"21", x"CD", x"AB",
        x"3E", x"56", x"ED",
        x"15", x"FD", x"ED", x"E5", x"FD", x"21", x"00", x"00",
        x"3E", x"00", x"ED", x"15", x"FD", x"ED", x"E1", x"FD",
        x"22", x"70", x"40", x"ED", x"1D", x"32", x"72", x"40",
        x"ED", x"36", x"22", x"80", x"40", x"ED", x"2C", x"32",
        x"82", x"40", x"76");

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
    begin
        wait until HALT_n = '0';
        wait for 200 ns;

        assert mem(16#4010#)(5) = '1' and mem(16#4011#)(5) = '0'
            report "W flag INC BC wrap/no-wrap mismatch" severity failure;
        assert mem(16#4012#)(5) = '1' and mem(16#4013#)(5) = '1'
            report "W flag DEC DE/INC HL wrap mismatch" severity failure;
        assert mem(16#4014#)(5) = '1' and mem(16#4015#)(5) = '1'
            report "W flag DD/FD INC/DEC index mismatch" severity failure;
        assert mem(16#4016#)(0) = '1' and mem(16#4017#)(0) = '0'
            report "WTOC must copy Y to C for set and clear cases" severity failure;

        assert mem(16#4020#) = x"00" and mem(16#4021#) = x"00" and mem(16#4022#) = x"13"
            report "DD ED 09 ADD24 IX,BC result mismatch" severity failure;
        assert mem(16#4023#) = x"01" and mem(16#4024#) = x"00" and mem(16#4025#) = x"13"
            report "DD ED 23 INC24 IX result mismatch" severity failure;
        assert mem(16#4030#) = x"FF" and mem(16#4031#) = x"FF" and mem(16#4032#) = x"FF"
            report "FD ED 1F SBC24 IY,DE result mismatch" severity failure;
        assert mem(16#4033#) = x"00" and mem(16#4034#) = x"00" and mem(16#4035#) = x"00"
            report "FD ED 19 ADD24 IY,DE result mismatch" severity failure;
        assert mem(16#4036#) = x"FF" and mem(16#4037#) = x"FF" and mem(16#4038#) = x"FF"
            report "FD ED 2B DEC24 IY result mismatch" severity failure;

        assert mem(16#4040#) = x"34" and mem(16#4041#) = x"12" and mem(16#4042#) = x"01"
            report "ED 34 LD24 MSP,imm24 result mismatch: " &
                to_hstring(mem(16#4042#)) & ":" & to_hstring(mem(16#4041#)) & to_hstring(mem(16#4040#))
            severity failure;
        assert mem(16#4050#) = x"01" and mem(16#4051#) = x"00" and mem(16#4052#) = x"13"
            report "DD ED E1 POP24 IX result mismatch" severity failure;
        assert mem(16#4090#) = x"01" and mem(16#4091#) = x"00" and mem(16#4092#) = x"13"
            report "DD ED E5 PUSH24 IX byte order/value mismatch: " &
                to_hstring(mem(16#4092#)) & to_hstring(mem(16#4091#)) & to_hstring(mem(16#4090#))
            severity failure;
        assert mem(16#0FFD#) = x"CD" and mem(16#0FFE#) = x"AB" and mem(16#0FFF#) = x"56"
            report "FD ED E5 PUSH24 IY byte order/value mismatch" severity failure;
        assert mem(16#4060#) = x"00" and mem(16#4061#) = x"10" and mem(16#4062#) = x"00"
            report "MSP24 did not return to 00:1000 after IX push/pop" severity failure;
        assert mem(16#4070#) = x"CD" and mem(16#4071#) = x"AB" and mem(16#4072#) = x"56"
            report "FD ED E1 POP24 IY result mismatch" severity failure;
        assert mem(16#4080#) = x"00" and mem(16#4081#) = x"10" and mem(16#4082#) = x"00"
            report "MSP24 did not return to 00:1000 after IY push/pop" severity failure;

        report "V16.1 opcode extension testbench: all assertions passed" severity note;
        std.env.stop;
    end process;

    process
    begin
        wait for 1 ms;
        assert HALT_n = '0' report "V16.1 extension program did not reach HALT" severity failure;
        wait;
    end process;
end architecture sim;
