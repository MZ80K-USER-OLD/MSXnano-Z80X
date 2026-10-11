library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 512 x 8 true dual-port RAM: bank 0 even, bank 1 odd.
-- Both ports use the same clock. Read address is registered,
-- matching the original RAM entity's read latency.
entity sprite_linebuf_dp is
  port (
    clk    : in  std_logic;
    a_addr : in  std_logic_vector(8 downto 0);
    a_we   : in  std_logic;
    a_din  : in  std_logic_vector(7 downto 0);
    a_dout : out std_logic_vector(7 downto 0);
    b_addr : in  std_logic_vector(8 downto 0);
    b_we   : in  std_logic;
    b_din  : in  std_logic_vector(7 downto 0);
    b_dout : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of sprite_linebuf_dp is
  type ram_t is array (0 to 511) of std_logic_vector(7 downto 0);
  -- Single driver (one process) -- avoids the simulation resolution
  -- conflict that occurs when two separate processes each drive their
  -- own view of the whole array signal.
  signal mem : ram_t := (others => (others => '0'));
  -- NOTE: read and write MUST use structurally distinct address
  -- signals per port. When read and write share the exact same
  -- address net, Gowin's BSRAM mapper always infers a transparent
  -- (write-first) WRITE_MODE encoding (2'b10), which the GW2AR-18C
  -- DPB primitive rejects for this depth/width -- independent of
  -- process count or statement order. Registering the read address
  -- one cycle behind the write address (exactly like the original
  -- single-port RAM entity: immediate "adr" for writes, delayed
  -- "iadr" for reads) makes the two address nets genuinely distinct
  -- and lets Gowin map this to the supported "normal" mode.
  signal a_rdaddr, b_rdaddr : std_logic_vector(8 downto 0);
begin
  -- Each port addresses a different bank during normal operation.
  -- Never write the same address through both ports on one clock edge.
  process(clk)
  begin
    if rising_edge(clk) then
      if a_we = '1' then
        mem(to_integer(unsigned(a_addr))) <= a_din;
      end if;
      a_rdaddr <= a_addr;

      if b_we = '1' then
        mem(to_integer(unsigned(b_addr))) <= b_din;
      end if;
      b_rdaddr <= b_addr;
    end if;
  end process;

  a_dout <= mem(to_integer(unsigned(a_rdaddr)));
  b_dout <= mem(to_integer(unsigned(b_rdaddr)));
end architecture;
