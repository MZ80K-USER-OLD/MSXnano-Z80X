-- Runs the assembled hardware COM, including its comparison and output code.
-- The BDOS stub implements functions 0/2/9 and deliberately clobbers registers
-- and flags. This is not a simulation of MSX-DOS or the physical SDRAM.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_ld24mi_com is
    generic (
        Com_File : string := "ld24mi.com";
        Inject_Fault : boolean := false;
        Legacy_Slot_Alias : boolean := false
    );
end entity;

architecture sim of tb_ld24mi_com is
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    type binary_file_t is file of character;

    impure function load_program return memory_t is
        file source : binary_file_t open read_mode is Com_File;
        variable result : memory_t := (others => x"00");
        variable octet : character;
        variable address : natural := 16#100#;
        type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
        -- IM 1; LD SP,EFFF; JP 0100
        constant boot : bytes_t := (x"ED", x"56", x"31", x"FF", x"EF", x"C3", x"00", x"01");
        -- BDOS: functions 0/2/9; output bytes on F0, terminate on F1.
        constant bdos : bytes_t := (
            x"79", x"B7", x"20", x"03", x"D3", x"F1", x"76",
            x"FE", x"09", x"20", x"0D",
            x"1A", x"FE", x"24", x"28", x"0B",
            x"D3", x"F0", x"13", x"18", x"F6",
            x"00", x"00", x"00",
            x"7B", x"D3", x"F0",
            x"01", x"AD", x"DE", x"11", x"EF", x"BE",
            x"21", x"34", x"12", x"AF", x"C9");
        -- Preserve ordinary Z80 registers, but do not save extension banks.
        constant isr : bytes_t := (
            x"F5", x"C5", x"D5", x"E5",
            x"21", x"00", x"F4", x"34",
            x"E1", x"D1", x"C1", x"F1", x"FB", x"ED", x"4D");
    begin
        while not endfile(source) loop
            assert address < 16#E000# report "COM overlaps test stack" severity failure;
            read(source, octet);
            result(address) := std_logic_vector(to_unsigned(character'pos(octet), 8));
            address := address + 1;
        end loop;
        for i in boot'range loop
            result(16#E000# + i) := boot(i);
        end loop;
        result(0) := x"C3"; result(1) := x"00"; result(2) := x"E0";
        result(5) := x"C3"; result(6) := x"00"; result(7) := x"F0";
        for i in bdos'range loop
            result(16#F000# + i) := bdos(i);
        end loop;
        for i in isr'range loop
            result(16#38# + i) := isr(i);
        end loop;
        result(16#F3E6#) := x"F1";
        return result;
    end function;

    signal mem00 : memory_t := load_program;
    signal mem01, mem02 : memory_t := (others => x"00");
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal int_n : std_logic := '1';
    signal a : std_logic_vector(15 downto 0);
    signal bank, dout, din, live : std_logic_vector(7 downto 0);
    signal mode24 : std_logic_vector(1 downto 0);
    signal ts : std_logic_vector(2 downto 0);
    signal io_cycle, writing, int_cycle_n, int_enabled : std_logic;
    signal bdos_calls, irq_count : natural := 0;
    signal finished : boolean := false;
    signal expanded_slot : std_logic_vector(7 downto 0) := x"00";
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;

    cpu : entity work.T80
        generic map (Mode => 0, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => '1',
            INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
            M1_n => open, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => open, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => mode24, A_Bank => bank, MC => open, TS => ts,
            IntCycle_n => int_cycle_n, IntE => int_enabled, Stop => open,
            bank_bc => open, bank_de => open, bank_hl => open,
            bank_ix => open, bank_iy => open, bank_pc => open,
            bank_msp => open, bank_int => open, bank_nvr => open,
            bank_rst => open);

    process (all)
    begin
        case bank is
            when x"00" => live <= mem00(to_integer(unsigned(a)));
            when x"01" =>
                live <= mem01(to_integer(unsigned(a)));
                if Inject_Fault and a = x"9000" then
                    live <= x"00";
                end if;
            when x"02" => live <= mem02(to_integer(unsigned(a)));
            when others => live <= x"00";
        end case;
    end process;

    process (clk)
        variable address : natural;
        variable output_line : line;
        variable summary_seen : boolean := false;
        variable fault_lines : natural := 0;
        variable last_io : boolean := false;
        variable last_irq : boolean := false;
        variable ticks : natural := 0;
    begin
        if rising_edge(clk) and reset_n = '1' then
            ticks := ticks + 1;
            if ticks mod 1000 = 0 then
                int_n <= '0';
            end if;
            if int_cycle_n = '0' then
                assert mode24 = "00" report "Interrupt accepted outside M0" severity failure;
                int_n <= '1';
                if not last_irq then
                    irq_count <= irq_count + 1;
                end if;
            end if;
            last_irq := int_cycle_n = '0';
            if mode24 /= "00" then
                assert int_enabled = '0' report "M1 measurement has interrupts enabled" severity failure;
            end if;
            if ts = "010" then
                din <= live;
            end if;
            address := to_integer(unsigned(a));
            if bank = x"00" and a = x"F000" and ts = "001" then
                assert mode24 = "00" report "BDOS entered outside M0" severity failure;
                bdos_calls <= bdos_calls + 1;
            end if;
            if io_cycle = '0' and writing = '1' then
                -- Model the FFFF slot-register side effect separately from
                -- SDRAM arbitration. Assume the expanded primary slot is selected.
                if ts = "011" and a = x"FFFF" and (bank = x"00" or Legacy_Slot_Alias) then
                    expanded_slot <= dout;
                    assert bank = x"00"
                        report "Extended write corrupted expanded-slot register: bank=" &
                            to_hstring(bank) & " data=" & to_hstring(dout)
                        severity failure;
                end if;
                case bank is
                    when x"00" => mem00(address) <= dout;
                    when x"01" => mem01(address) <= dout;
                    when x"02" => mem02(address) <= dout;
                    when others => assert false report "Unexpected physical write bank" severity failure;
                end case;
            end if;
            if io_cycle = '1' and writing = '1' and ts = "011" and not last_io then
                case a(7 downto 0) is
                    when x"F0" =>
                        if dout = x"0A" then
                            if output_line /= null then
                                report output_line.all;
                                if Inject_Fault and
                                    (output_line.all = "Test1 R/W patterns 01:9000: FAIL (got=FFFF00, want=FFFFFF)" or
                                     output_line.all = "  first failing step=02" or
                                     output_line.all = "Test1 setup byte-readback: FAIL (got=059900, want=0599AA)" or
                                     output_line.all = "Test1 ED00 LD24 BC,(HL) normal read: FAIL (got=059900, want=0599AA)") then
                                    fault_lines := fault_lines + 1;
                                end if;
                                if output_line.all'length >= 5 and output_line.all(1 to 5) = "PASS=" then
                                    if Inject_Fault then
                                        assert output_line.all = "PASS=10 FAIL=03"
                                            report "Wrong fault-injected summary" severity failure;
                                    else
                                        assert output_line.all = "PASS=13 FAIL=00"
                                            report "Wrong success summary" severity failure;
                                    end if;
                                    summary_seen := true;
                                end if;
                                deallocate(output_line);
                            end if;
                        elsif dout /= x"0D" then
                            write(output_line, character'val(to_integer(unsigned(dout))));
                        end if;
                    when x"F1" =>
                        assert summary_seen report "DOS exit before expected summary" severity failure;
                        assert expanded_slot = x"00"
                            report "Expanded-slot register changed during COM" severity failure;
                        if Inject_Fault then
                            assert fault_lines = 4 report "Fault values were not reported correctly" severity failure;
                        end if;
                        assert bdos_calls > 20 and irq_count > 0
                            report "BDOS/interrupt coverage missing" severity failure;
                        finished <= true;
                    when x"99" => null;
                    when others => assert false report "Unexpected I/O port" severity failure;
                end case;
            end if;
            last_io := io_cycle = '1' and writing = '1' and ts = "011";
        end if;
    end process;

    process
    begin
        wait until finished for 10 ms;
        assert finished report "COM did not terminate" severity failure;
        report "LD24MI COM: output, M0 BDOS, M1 DI and interrupt checks passed";
        std.env.stop;
        wait;
    end process;
end architecture;
