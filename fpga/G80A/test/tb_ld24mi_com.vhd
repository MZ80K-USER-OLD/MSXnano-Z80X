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
        Legacy_Slot_Alias : boolean := false;
        Index16_Test : boolean := false;
        Index24_Test : boolean := false;
        M2_Test : boolean := false;
        V161_Control_Test : boolean := false;
        V161_IRQ_Test : boolean := false;
        HALT_IRQ_Test : boolean := false;
        Suppress_VDP_IRQ : boolean := false;
        Suppress_HALT_Mode : natural range 0 to 2 := 0;
        Cpu_Mode : natural range 0 to 1 := 0;
        Wait_Enabled : boolean := false
    );
end entity;

architecture sim of tb_ld24mi_com is
    type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
    type vdp_marker_array_t is array (0 to 15) of std_logic_vector(7 downto 0);
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
            x"21", x"34", x"12", x"AF", x"FB", x"C9");
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
    signal halt_n : std_logic;
    signal mc : std_logic_vector(2 downto 0);
    signal vdp_r1 : std_logic_vector(7 downto 0) := x"20";
    signal vdp_r7 : std_logic_vector(7 downto 0) := x"F4";
    signal vdp_status_index : std_logic_vector(2 downto 0) := "000";
    signal vdp_markers : vdp_marker_array_t := (others => x"00");
    signal timeout_probe_passed : boolean := false;
    signal timeout_probe_dots : natural := 0;
    signal m2_irq_count, im2_table_reads, irq_frame_writes : natural := 0;
    signal bdos_calls, irq_count : natural := 0;
    signal finished : boolean := false;
    signal wait_n : std_logic := '1';
    signal wait_ticks : natural := 0;
    signal expanded_slot : std_logic_vector(7 downto 0) := x"00";
begin
    clk <= not clk after 10 ns;
    reset_n <= '1' after 45 ns;
    wait_n <= '0' when Wait_Enabled and wait_ticks mod 5 < 2 else '1';
    process (clk)
    begin
        if rising_edge(clk) then
            wait_ticks <= wait_ticks + 1;
        end if;
    end process;

    cpu : entity work.T80
        generic map (Mode => Cpu_Mode, IOWait => 0)
        port map (
            RESET_n => reset_n, CLK_n => clk, CEN => '1', WAIT_n => wait_n,
            INT_n => int_n, NMI_n => '1', BUSRQ_n => '1',
            M1_n => open, IORQ => io_cycle, NoRead => open, Write => writing,
            RFSH_n => open, HALT_n => halt_n, BUSAK_n => open,
            A => a, update_addr => open, DInst => live, DI => din, DO => dout,
            mode24 => mode24, A_Bank => bank, MC => mc, TS => ts,
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
                if Inject_Fault and not (V161_Control_Test or V161_IRQ_Test or HALT_IRQ_Test) and
                   ((not (Index16_Test or Index24_Test) and a = x"9000") or
                    ((Index16_Test or Index24_Test) and a = x"FFFF")) then
                    live <= x"00";
                end if;
            when x"02" =>
                live <= mem02(to_integer(unsigned(a)));
                if Inject_Fault and V161_Control_Test and a = x"8101" then
                    live <= x"A5";
                end if;
                if Inject_Fault and (V161_IRQ_Test or HALT_IRQ_Test) and a = x"8192" then
                    live <= x"A5";
                end if;
            when others => live <= x"00";
        end case;
        if V161_IRQ_Test or HALT_IRQ_Test then
            if int_cycle_n = '0' and mc = "001" then
                live <= x"FF";
            elsif io_cycle = '1' and writing = '0' and a(7 downto 0) = x"99" then
                if vdp_status_index = "000" and
                   (not Suppress_VDP_IRQ or (HALT_IRQ_Test and
                    mode24 /= std_logic_vector(to_unsigned(Suppress_HALT_Mode, 2)))) then
                    live <= x"80";
                else
                    live <= x"00";
                end if;
            end if;
        end if;
    end process;

    process (clk)
        variable address : natural;
        variable output_line : line;
        variable summary_seen : boolean := false;
        variable fault_lines : natural := 0;
        variable last_io : boolean := false;
        variable last_irq : boolean := false;
        variable ticks : natural := 0;
        variable previous_mode : std_logic_vector(1 downto 0) := "00";
        variable m2_entries : natural := 0;
        variable vdp_latch : std_logic_vector(7 downto 0) := x"00";
        variable vdp_second : boolean := false;
        variable vdp_address : natural range 0 to 16#3FFF# := 0;
        variable vdp_vram_write : boolean := false;
        type coverage_t is array (0 to 2) of natural;
        variable halt_irqs, halt_frames, halt_vectors, halt_returns : coverage_t := (others => 0);
        variable halt_ticks : natural := 0;
        variable halted_mode : natural range 0 to 2 := 0;
        variable halt_resume_pending : boolean := false;
        variable halt_trace_cases : natural := 0;
    begin
        if rising_edge(clk) and reset_n = '1' then
            ticks := ticks + 1;
            if M2_Test then
                assert mode24 /= "01" report "M2 test entered M1 instead" severity failure;
            end if;
            if M2_Test or V161_Control_Test or V161_IRQ_Test then
                if mode24 = "10" and previous_mode /= "10" then
                    m2_entries := m2_entries + 1;
                end if;
            end if;
            previous_mode := mode24;
            if V161_IRQ_Test or HALT_IRQ_Test then
                if HALT_IRQ_Test then
                    if halt_n = '0' then
                        halt_ticks := halt_ticks + 1;
                        if halt_ticks = 32 then
                            assert int_enabled = '1' and vdp_r1(5) = '1'
                                report "HALT entered without EI or VDP IRQ enable" severity failure;
                            halted_mode := to_integer(unsigned(mode24));
                            if not Suppress_VDP_IRQ or halted_mode /= Suppress_HALT_Mode then
                                int_n <= '0';
                            end if;
                        end if;
                    else
                        halt_ticks := 0;
                    end if;
                elsif ticks mod 5000 = 0 and vdp_r1(5) = '1' and
                   (mode24 = "00" or not Suppress_VDP_IRQ) then
                    int_n <= '0';
                end if;
                if V161_IRQ_Test and Suppress_VDP_IRQ and mode24 = "10" then int_n <= '1'; end if;
                if io_cycle = '1' and writing = '0' and a(7 downto 0) = x"99" and
                   ts = "010" and wait_n = '1' then
                    vdp_second := false;
                    if vdp_status_index = "000" then int_n <= '1'; end if;
                end if;
            elsif ticks mod 1000 = 0 then
                int_n <= '0';
            end if;
            if int_cycle_n = '0' then
                assert mode24 = "00" or V161_IRQ_Test or HALT_IRQ_Test
                    report "Interrupt accepted outside M0" severity failure;
                if not HALT_IRQ_Test and (mode24 = "00" or not V161_IRQ_Test) then
                    int_n <= '1';
                end if;
                if not last_irq then
                    irq_count <= irq_count + 1;
                    if mode24 = "10" then m2_irq_count <= m2_irq_count + 1; end if;
                    if HALT_IRQ_Test then
                        assert halt_ticks >= 32
                            report "IRQ accepted before observed HALT dwell" severity failure;
                        halt_irqs(halted_mode) := halt_irqs(halted_mode) + 1;
                        halt_resume_pending := true;
                    end if;
                end if;
                if HALT_IRQ_Test and ts = "010" and wait_n = '1' then
                    if writing = '1' then
                        halt_frames(halted_mode) := halt_frames(halted_mode) + 1;
                        if halted_mode = 2 then
                            assert bank = x"02" and unsigned(a) >= x"CFFC" and unsigned(a) <= x"CFFF"
                                report "HALT M2 IRQ frame outside MSP bank02" severity failure;
                        else
                            assert bank = x"00" and (a = x"CFFE" or a = x"CFFF")
                                report "HALT legacy IRQ frame outside SP bank00" severity failure;
                        end if;
                    elsif (halted_mode = 2 and (mc = "110" or mc = "111")) or
                          (halted_mode /= 2 and (mc = "100" or mc = "101")) then
                        assert ((halted_mode = 2 and bank = x"02") or
                                (halted_mode /= 2 and bank = x"00")) and
                               (((mc = "110" or mc = "100") and a = x"90FF") or
                                ((mc = "111" or mc = "101") and a = x"9100"))
                            report "HALT IM2 vector bank/address incorrect" severity failure;
                        halt_vectors(halted_mode) := halt_vectors(halted_mode) + 1;
                    end if;
                end if;
                if V161_IRQ_Test and mode24 = "10" and
                   ts = "010" and wait_n = '1' then
                    if writing = '1' then
                        irq_frame_writes <= irq_frame_writes + 1;
                    elsif mc = "110" or mc = "111" then
                        assert bank = x"02" and
                               ((mc = "110" and a = x"FFFF") or
                                (mc = "111" and a = x"0000"))
                            report "IM2 table did not wrap inside IBR" severity failure;
                        im2_table_reads <= im2_table_reads + 1;
                    end if;
                end if;
            end if;
            last_irq := int_cycle_n = '0';
            if mode24 /= "00" and not (V161_IRQ_Test or HALT_IRQ_Test) then
                assert int_enabled = '0' report "Measurement has interrupts enabled" severity failure;
            end if;
            if ts = "010" and wait_n = '1' then
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
                                    if V161_IRQ_Test then
                                        if Inject_Fault or Suppress_VDP_IRQ then
                                            assert output_line.all = "PASS=00 FAIL=04"
                                                report "Wrong IRQ negative-control summary" severity failure;
                                        else
                                            assert output_line.all = "PASS=04 FAIL=00"
                                                report "Wrong IRQ summary" severity failure;
                                        end if;
                                    elsif HALT_IRQ_Test then
                                        if Inject_Fault then
                                            assert output_line.all = "PASS=02 FAIL=01"
                                                report "Wrong HALT fault summary" severity failure;
                                        else
                                            assert output_line.all = "PASS=03 FAIL=00"
                                                report "Wrong HALT summary" severity failure;
                                        end if;
                                    elsif V161_Control_Test then
                                        if Inject_Fault then
                                            assert output_line.all = "PASS=02 FAIL=18"
                                                report "Wrong V16.1 fault summary" severity failure;
                                        else
                                            assert output_line.all = "PASS=1A FAIL=00"
                                                report "Wrong V16.1 summary" severity failure;
                                        end if;
                                    elsif Index16_Test or Index24_Test then
                                        if Inject_Fault then
                                            assert output_line.all = "PASS=00 FAIL=18"
                                                report "Wrong indexed fault summary" severity failure;
                                        else
                                            assert output_line.all = "PASS=18 FAIL=00"
                                                report "Wrong indexed summary" severity failure;
                                        end if;
                                    elsif Inject_Fault then
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
                        if HALT_IRQ_Test then
                            assert halt_irqs = (2, 2, 2) and halt_returns = (2, 2, 2)
                                report "Missing HALT IRQ/return mode coverage" severity failure;
                            for mode in 0 to 2 loop
                                report "HALT M" & integer'image(mode) & " IRQ=" & integer'image(halt_irqs(mode)) &
                                    " return=" & integer'image(halt_returns(mode)) &
                                    " frame-bytes=" & integer'image(halt_frames(mode)) &
                                    " vector-bytes=" & integer'image(halt_vectors(mode));
                            end loop;
                            assert halt_frames = (4, 4, 8)
                                report "Missing HALT frame byte coverage" severity failure;
                            assert halt_vectors = (4, 4, 4)
                                report "Missing HALT IM2 vector coverage" severity failure;
                            assert halt_trace_cases = 3 and not halt_resume_pending
                                report "Missing HALT ordered trace coverage" severity failure;
                        end if;
                        if M2_Test or V161_Control_Test then
                            assert m2_entries = 24 report "Missing M2 case coverage" severity failure;
                        end if;
                        if V161_IRQ_Test then
                            assert m2_entries = 5 report "Missing no-handler timeout or IRQ cases" severity failure;
                            assert timeout_probe_passed
                                report "No-handler M2 timeout probe did not complete as VRAM TM1abc2345OK"
                                severity failure;
                            if Suppress_VDP_IRQ then
                                assert vdp_markers(0 to 11) =
                                    (x"41", x"42", x"43", x"31", x"32", x"21", x"4E", x"45",
                                     x"21", x"4E", x"45", x"4D")
                                    report "Missing VRAM timeout/status markers ABC12!NE!NEM" severity failure;
                                assert m2_irq_count = 0 and irq_frame_writes = 0 and
                                       im2_table_reads = 0
                                    report "Suppressed VDP still interrupted M2" severity failure;
                            else
                                assert vdp_markers(0 to 8) =
                                    (x"41", x"42", x"43", x"56", x"48", x"44", x"56", x"48", x"4D")
                                    report "Missing ordered VRAM progress markers ABCVHDVHM; got " &
                                        to_hstring(vdp_markers(0)) & to_hstring(vdp_markers(1)) &
                                        to_hstring(vdp_markers(2)) & to_hstring(vdp_markers(3)) &
                                        to_hstring(vdp_markers(4)) & to_hstring(vdp_markers(5)) &
                                        to_hstring(vdp_markers(6)) & to_hstring(vdp_markers(7)) &
                                        to_hstring(vdp_markers(8))
                                    severity failure;
                                assert m2_irq_count = 8 and irq_frame_writes = 32 and
                                       im2_table_reads = 8
                                    report "Missing IRQ/frame/IM2 coverage" severity failure;
                            end if;
                        end if;
                        assert expanded_slot = x"00"
                            report "Expanded-slot register changed during COM" severity failure;
                        if Inject_Fault and not (Index16_Test or Index24_Test or V161_Control_Test or V161_IRQ_Test or HALT_IRQ_Test) then
                            assert fault_lines = 4 report "Fault values were not reported correctly" severity failure;
                        end if;
                        assert bdos_calls > 20 and
                               (irq_count > 0 or (V161_IRQ_Test and Suppress_VDP_IRQ))
                            report "BDOS/interrupt coverage missing" severity failure;
                        finished <= true;
                    when x"99" =>
                        if V161_IRQ_Test or HALT_IRQ_Test then
                            if vdp_second then
                                if dout(7) = '1' then
                                    case dout is
                                        when x"81" => vdp_r1 <= vdp_latch;
                                        when x"87" => vdp_r7 <= vdp_latch;
                                        when x"8F" =>
                                            vdp_status_index <= vdp_latch(2 downto 0);
                                        when others =>
                                            assert false report "Unexpected VDP register write" severity failure;
                                    end case;
                                    vdp_second := false;
                                else
                                    vdp_address := to_integer(unsigned(dout(5 downto 0))) * 256 +
                                                   to_integer(unsigned(vdp_latch));
                                    vdp_vram_write := dout(6) = '1';
                                    vdp_second := false;
                                end if;
                            else
                                vdp_latch := dout;
                                vdp_second := true;
                            end if;
                        end if;
                    when x"98" =>
                        if V161_IRQ_Test or HALT_IRQ_Test then
                            assert vdp_vram_write report "VDP data write without VRAM write address" severity failure;
                            if HALT_IRQ_Test and dout = x"52" then
                                assert halt_resume_pending and mode24 = std_logic_vector(to_unsigned(halted_mode, 2))
                                    report "HALT resumed in wrong mode" severity failure;
                                halt_returns(halted_mode) := halt_returns(halted_mode) + 1;
                                halt_resume_pending := false;
                            end if;
                            if HALT_IRQ_Test and vdp_address = halt_trace_cases * 40 + 12 and dout = x"4D" then
                                assert vdp_markers(0) = std_logic_vector(to_unsigned(16#30# + halt_trace_cases, 8)) and
                                       vdp_markers(1 to 11) =
                                           (x"41", x"48", x"56", x"53", x"4B", x"52",
                                            x"48", x"56", x"53", x"4B", x"52")
                                    report "Wrong ordered HALT mode trace nAHVSKRHVSKRM" severity failure;
                                halt_trace_cases := halt_trace_cases + 1;
                            end if;
                            if vdp_address = 11 and dout = x"4B" then
                                assert vdp_markers(0 to 10) =
                                    (x"54", x"4D", x"31", x"61", x"62", x"63", x"32",
                                     x"33", x"34", x"35", x"4F")
                                    report "No-handler timeout probe did not complete the ordered TM1abc2345O trace"
                                    severity failure;
                                assert timeout_probe_dots = 0
                                    report "No-handler timeout probe unexpectedly emitted loop dots"
                                    severity failure;
                                timeout_probe_passed <= true;
                            end if;
                            if vdp_address >= 3 and dout = x"2E" then
                                timeout_probe_dots <= timeout_probe_dots + 1;
                            end if;
                            if HALT_IRQ_Test and vdp_address mod 40 <= 15 then
                                vdp_markers(vdp_address mod 40) <= dout;
                            elsif vdp_address <= 15 then
                                vdp_markers(vdp_address) <= dout;
                            end if;
                            vdp_address := (vdp_address + 1) mod 16#4000#;
                        end if;
                    when others => assert false report "Unexpected I/O port" severity failure;
                end case;
            end if;
            last_io := io_cycle = '1' and writing = '1' and ts = "011";
        end if;
    end process;

    process
    begin
        if V161_IRQ_Test then
            wait until finished for 1 sec;
        else
            wait until finished for 10 ms;
        end if;
        if HALT_IRQ_Test and Suppress_VDP_IRQ then
            assert not finished and halt_n = '0' and
                   mode24 = std_logic_vector(to_unsigned(Suppress_HALT_Mode, 2)) and
                   irq_count = Suppress_HALT_Mode * 2 and
                   vdp_markers(0) = std_logic_vector(to_unsigned(16#30# + Suppress_HALT_Mode, 8)) and
                   vdp_markers(1 to 2) = (x"41", x"48")
                report "HALT no-IRQ control did not stay at the selected mode HALT" severity failure;
            assert false report "HALT no-IRQ control: held in M" & integer'image(Suppress_HALT_Mode) &
                " HALT without handler or resume"
                severity failure;
        end if;
        assert finished report "COM did not terminate" severity failure;
        report "COM: output, M0 BDOS, measurement DI and interrupt checks passed";
        std.env.stop;
        wait;
    end process;
end architecture;
