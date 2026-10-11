--
-- Z80 compatible microprocessor core
--
-- Version : 0250_T80 (+k04)
--
-- Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org)
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.
--
-- The latest version of this file can be found at:
--  http://www.opencores.org/cvsweb.shtml/t80/
--
-- Limitations :
--
-- File history :
--
--  0208 : First complete release
--  0210 : Fixed wait and halt
--  0211 : Fixed Refresh addition and IM 1
--  0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
--  0232 : Removed refresh address output for Mode > 1 and added DJNZ M1_n fix by Mike Johnson
--  0235 : Added clock enable and IM 2 fix by Mike Johnson
--  0237 : Changed 8080 I/O address output, added IntE output
--  0238 : Fixed (IX/IY+d) timing and 16 bit ADC and SBC zero flag
--  0240 : Added interrupt ack fix by Mike Johnson, changed (IX/IY+d) timing and changed flags in GB mode
--  0242 : Added I/O wait, fixed refresh address, moved some registers to RAM
--  0247 : Fixed bus req/ack cycle
--  0248 : Added undocumented DDCB and FDCB opcodes by TobiFlex 2010.04.20
--  0249 : Added undocumented XY-Flags for CPI/CPD by TobiFlex 2012.07.22
--  0250 : Added R800 Multiplier by TobiFlex 2017.10.15
--
--  +k01 : Version alignment by KdL 2010.10.25
--  +k02 : Added R800_mode signal by KdL 2018.05.14
--  +k03 : Version alignment by KdL 2019.05.20
--  +k04 : Separation of T800 from T80 by KdL 2021.02.01
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.T80_Pack.all;

entity T80 is
    generic(
        Mode        : integer := 0;  -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        IOWait      : integer := 0;  -- 0 => Single I/O cycle, 1 => Std I/O cycle
        Flag_C      : integer := 0;
        Flag_N      : integer := 1;
        Flag_P      : integer := 2;
        Flag_X      : integer := 3;
        Flag_H      : integer := 4;
        Flag_Y      : integer := 5;
        Flag_Z      : integer := 6;
        Flag_S      : integer := 7
    );
    port(
        RESET_n     : in std_logic;
        CLK_n       : in std_logic;
        CEN         : in std_logic;
        WAIT_n      : in std_logic;
        INT_n       : in std_logic;
        NMI_n       : in std_logic;
        BUSRQ_n     : in std_logic;
        M1_n        : out std_logic;
        IORQ        : out std_logic;
        NoRead      : out std_logic;
        Write       : out std_logic;
        RFSH_n      : out std_logic;
        HALT_n      : out std_logic;
        BUSAK_n     : out std_logic;
        A           : out std_logic_vector(15 downto 0);
		update_addr	: out std_logic;
        -- Phase3: 24bit logical address bank byte for the current data bus
        -- cycle (paired with A to form A_Bank & A). Valid (non-zero capable)
        -- only for register-indirect data accesses (HL/BC/DE/(IX+d)/(IY+d))
        -- while mode24 /= M0. PC fetch, SP/stack and 16bit direct (nn)
        -- addressing stay at 00h in Phase3 (PC remains 16bit; see Phase 3
        -- "最小M1" in MSX_T80_24bit化_実装手順_V2_2026-10-05.md).
        A_Bank      : out std_logic_vector(7 downto 0);
        DInst       : in std_logic_vector(7 downto 0);
        DI          : in std_logic_vector(7 downto 0);
        DO          : out std_logic_vector(7 downto 0);
        mode24      : out std_logic_vector(1 downto 0);
        bank_bc     : out std_logic_vector(7 downto 0);
        bank_de     : out std_logic_vector(7 downto 0);
        bank_hl     : out std_logic_vector(7 downto 0);
        bank_ix     : out std_logic_vector(7 downto 0);
        bank_iy     : out std_logic_vector(7 downto 0);
        bank_pc     : out std_logic_vector(7 downto 0);
        bank_msp    : out std_logic_vector(7 downto 0);
        bank_int    : out std_logic_vector(7 downto 0);
        bank_nvr    : out std_logic_vector(7 downto 0);
        bank_rst    : out std_logic_vector(7 downto 0);
        MC          : out std_logic_vector(2 downto 0);
        TS          : out std_logic_vector(2 downto 0);
        IntCycle_n  : out std_logic;
        IntE        : out std_logic;
        Stop        : out std_logic
    );
end T80;

architecture rtl of T80 is

    constant aNone  : std_logic_vector(2 downto 0) := "111";
    constant aBC    : std_logic_vector(2 downto 0) := "000";
    constant aDE    : std_logic_vector(2 downto 0) := "001";
    constant aXY    : std_logic_vector(2 downto 0) := "010";
    constant aIOA   : std_logic_vector(2 downto 0) := "100";
    constant aSP    : std_logic_vector(2 downto 0) := "101";
    constant aZI    : std_logic_vector(2 downto 0) := "110";
    -- Phase9: MSP24 (PUSH24/POP24) address source; must match the aMSP
    -- constant added to t80_mcode.vhd.
    constant aMSP   : std_logic_vector(2 downto 0) := "011";

    -- Registers
    signal ACC, F           : std_logic_vector(7 downto 0);
    signal Ap, Fp           : std_logic_vector(7 downto 0);
    signal I                : std_logic_vector(7 downto 0);
    signal R                : unsigned(7 downto 0);
    signal SP, PC           : unsigned(15 downto 0);
    signal MSP              : unsigned(15 downto 0);
    signal IVR              : unsigned(15 downto 0);    -- Phase7: IVR24 low word (bank byte = bank_int_r)
    signal NVR              : unsigned(15 downto 0);    -- Phase7: NVR24 low word (bank byte = bank_nvr_r)
    signal RegDIH           : std_logic_vector(7 downto 0);
    signal RegDIL           : std_logic_vector(7 downto 0);
    signal RegBusA          : std_logic_vector(15 downto 0);
    signal RegBusB          : std_logic_vector(15 downto 0);
    signal RegBusC          : std_logic_vector(15 downto 0);
    signal RegAddrA_r       : std_logic_vector(2 downto 0);
    signal RegAddrA         : std_logic_vector(2 downto 0);
    signal RegAddrB_r       : std_logic_vector(2 downto 0);
    signal RegAddrB         : std_logic_vector(2 downto 0);
    signal RegAddrC         : std_logic_vector(2 downto 0);
    signal RegWEH           : std_logic;
    signal RegWEL           : std_logic;
    signal Alternate        : std_logic;

    -- Help Registers
    signal TmpAddr          : std_logic_vector(15 downto 0);    -- Temporary address register
    signal TmpBank          : std_logic_vector(7 downto 0);     -- Phase2: 24bit EA bank byte for (IX/IY+d), paired with TmpAddr
    signal A_Bank_r         : std_logic_vector(7 downto 0);     -- Phase3: registered bank byte for the current A bus cycle
    signal IR               : std_logic_vector(7 downto 0);     -- Instruction register
    signal ISet             : std_logic_vector(1 downto 0);     -- Instruction set selector
    signal RegBusA_r        : std_logic_vector(15 downto 0);

    signal ID16             : signed(15 downto 0);
    signal Save_Mux         : std_logic_vector(7 downto 0);

    signal TState           : unsigned(2 downto 0);
    signal MCycle           : std_logic_vector(3 downto 0);
    signal IntE_FF1         : std_logic;
    signal IntE_FF2         : std_logic;
    signal Halt_FF          : std_logic;
    signal BusReq_s         : std_logic;
    signal BusAck           : std_logic;
    signal ClkEn            : std_logic;
    signal NMI_s            : std_logic;
    signal INT_s            : std_logic;
    signal IStatus          : std_logic_vector(1 downto 0);
    signal mode24_r         : std_logic_vector(1 downto 0);
    signal bank_bc_r        : std_logic_vector(7 downto 0);
    signal bank_de_r        : std_logic_vector(7 downto 0);
    signal bank_hl_r        : std_logic_vector(7 downto 0);
    signal bank_ix_r        : std_logic_vector(7 downto 0);
    signal bank_iy_r        : std_logic_vector(7 downto 0);
    signal bank_pc_r        : std_logic_vector(7 downto 0);
    signal bank_msp_r       : std_logic_vector(7 downto 0);   -- MSP24 bank byte (no direct opcode per V8/V7 spec; set via Phase7 LD24 MSP)
    signal bank_int_r       : std_logic_vector(7 downto 0);   -- IVR24 bank byte (no direct opcode per V8/V7 spec; set via Phase7 LD24 IVR)
    signal bank_nvr_r       : std_logic_vector(7 downto 0);   -- NVR24 bank byte (no direct opcode per V8/V7 spec; set via Phase7 LD24 NVR)
    signal bank_rst_r       : std_logic_vector(7 downto 0);   -- RST_B (V8/V7 finalized opcode: ED3A LD RST_B,A / ED3E LD A,RST_B)

    -- Phase8: dedicated 24bit ALU (fully combinational, see the process
    -- near RegAddrA_r/RegAddrB_r below and Alu24_AddSub in t80_pack.vhd).
    -- alu24_active/alu24_writeback already fold in the XY_State="00" guard
    -- (DD/FD IX/IY target variants are deferred, same scope limitation as
    -- Phase7's LD24 HL,IX/IY - see AVAILABLE_INSTRUCTIONS.md), so T_Res
    -- commit logic only needs to check these two signals.
    signal alu24_active     : std_logic;
    signal alu24_writeback  : std_logic;
    signal alu24_sub        : std_logic;
    signal alu24_overflow   : std_logic;
    signal alu24_carry      : std_logic;
    signal alu24_result24   : std_logic_vector(23 downto 0);

    signal DI_Reg           : std_logic_vector(7 downto 0);
    signal T_Res            : std_logic;
    signal XY_State         : std_logic_vector(1 downto 0);
    signal Pre_XY_F_M       : std_logic_vector(3 downto 0);
    signal NextIs_XY_Fetch  : std_logic;
    -- Phase11: distinguishes "MCycle reached 111 because
    -- NextIs_XY_Fetch legitimately jumped here via the DD/FD+CB
    -- continuation" from "MCycle reached 111 because a NEW instruction
    -- (e.g. CALL.L) simply has 7 MCycles of its own". Only the former
    -- should trigger the Pre_XY_F_M restore below; this flag is the
    -- minimal-footprint way to keep both meanings of "MCycle=111"
    -- correctly separated without widening MCycle/MCycles (which would
    -- touch every existing instruction's cycle-matching logic).
    signal XYF_Pending      : std_logic;
    signal XY_Ind           : std_logic;
    signal No_BTR           : std_logic;
    signal BTR_r            : std_logic;
    signal Auto_Wait        : std_logic;
    signal Auto_Wait_t1     : std_logic;
    signal Auto_Wait_t2     : std_logic;
    signal IncDecZ          : std_logic;

    -- ALU signals
    signal BusB             : std_logic_vector(7 downto 0);
    signal BusA             : std_logic_vector(7 downto 0);
    signal ALU_Q            : std_logic_vector(7 downto 0);
    signal F_Out            : std_logic_vector(7 downto 0);

    -- Registered micro code outputs
    signal Read_To_Reg_r    : std_logic_vector(4 downto 0);
    signal Arith16_r        : std_logic;
    signal Z16_r            : std_logic;
    signal ALU_Op_r         : std_logic_vector(3 downto 0);
    signal ALU_cpi_r        : std_logic;
    signal Save_ALU_r       : std_logic;
    signal PreserveC_r      : std_logic;
    signal MCycles          : std_logic_vector(3 downto 0);

    -- Micro code outputs
    signal MCycles_d        : std_logic_vector(3 downto 0);
    signal TStates          : std_logic_vector(2 downto 0);
    signal IntCycle         : std_logic;
    signal NMICycle         : std_logic;
    signal Inc_PC           : std_logic;
    signal Inc_WZ           : std_logic;
    signal IncDec_16        : std_logic_vector(3 downto 0);
    signal Prefix           : std_logic_vector(1 downto 0);
    signal Read_To_Acc      : std_logic;
    signal Read_To_Reg      : std_logic;
    signal Set_BusB_To      : std_logic_vector(3 downto 0);
    signal Set_BusA_To      : std_logic_vector(3 downto 0);
    signal ALU_Op           : std_logic_vector(3 downto 0);
    signal ALU_cpi          : std_logic;
    signal Save_ALU         : std_logic;
    signal PreserveC        : std_logic;
    signal Arith16          : std_logic;
    signal Set_Addr_To      : std_logic_vector(2 downto 0);
    signal Jump             : std_logic;
    -- Phase11: see matching JumpL comment in t80_mcode.vhd's entity port.
    signal JumpL            : std_logic;
    -- Phase11: see matching JumpR comment in t80_mcode.vhd's entity port.
    signal JumpR            : std_logic;
    signal JumpE            : std_logic;
    -- Phase11: see matching JumpEL comment in t80_mcode.vhd's entity port.
    signal JumpEL           : std_logic;
    signal JumpXY           : std_logic;
    signal Call             : std_logic;
    -- Phase11: see matching CallL/RetL comments in t80_mcode.vhd's entity port.
    signal CallL            : std_logic;
    signal RetL             : std_logic;
    -- Phase12: see matching JumpM01/JumpM2/CallM01/RetM comments in
    -- t80_mcode.vhd's entity port.
    signal JumpM01          : std_logic;
    signal JumpM2           : std_logic;
    signal CallM01          : std_logic;
    signal CallM2           : std_logic;
    signal RetM             : std_logic;
    signal RstP             : std_logic;
    signal LDZ              : std_logic;
    signal LDW              : std_logic;
    -- Phase11: see matching LDB comment in t80_mcode.vhd's entity port.
    signal LDB              : std_logic;
    signal LDSPHL           : std_logic;
    signal IORQ_i           : std_logic;
    signal Special_LD       : std_logic_vector(2 downto 0);
    signal ExchangeDH       : std_logic;
    signal ExchangeRp       : std_logic;
    signal ExchangeAF       : std_logic;
    signal ExchangeRS       : std_logic;
    signal I_DJNZ           : std_logic;
    signal I_CPL            : std_logic;
    signal I_CCF            : std_logic;
    signal I_SCF            : std_logic;
    signal I_RETN           : std_logic;
    signal I_BT             : std_logic;
    signal I_BC             : std_logic;
    signal I_BTR            : std_logic;
    signal I_RLD            : std_logic;
    signal I_RRD            : std_logic;
    signal I_INRC           : std_logic;
    signal SetDI            : std_logic;
    signal SetEI            : std_logic;
    signal IMode            : std_logic_vector(1 downto 0);
    signal Halt             : std_logic;
    signal XYbit_undoc      : std_logic;

begin

    mcode : T80_MCode
        generic map(
            Mode => Mode,
            Flag_C => Flag_C,
            Flag_N => Flag_N,
            Flag_P => Flag_P,
            Flag_X => Flag_X,
            Flag_H => Flag_H,
            Flag_Y => Flag_Y,
            Flag_Z => Flag_Z,
            Flag_S => Flag_S)
        port map(
            IR => IR,
            ISet => ISet,
            MCycle => MCycle,
            F => F,
            NMICycle => NMICycle,
            IntCycle => IntCycle,
            XY_State => XY_State,
            MCycles => MCycles_d,
            TStates => TStates,
            Prefix => Prefix,
            Inc_PC => Inc_PC,
            Inc_WZ => Inc_WZ,
            IncDec_16 => IncDec_16,
            Read_To_Acc => Read_To_Acc,
            Read_To_Reg => Read_To_Reg,
            Set_BusB_To => Set_BusB_To,
            Set_BusA_To => Set_BusA_To,
            ALU_Op => ALU_Op,
            ALU_cpi => ALU_cpi,
            Save_ALU => Save_ALU,
            PreserveC => PreserveC,
            Arith16 => Arith16,
            Set_Addr_To => Set_Addr_To,
            IORQ => IORQ_i,
            Jump => Jump,
            JumpL => JumpL,
            JumpR => JumpR,
            JumpE => JumpE,
            JumpEL => JumpEL,
            JumpXY => JumpXY,
            Call => Call,
            CallL => CallL,
            RetL => RetL,
            JumpM01 => JumpM01,
            JumpM2 => JumpM2,
            CallM01 => CallM01,
            CallM2 => CallM2,
            RetM => RetM,
            RstP => RstP,
            LDZ => LDZ,
            LDW => LDW,
            LDB => LDB,
            LDSPHL => LDSPHL,
            Special_LD => Special_LD,
            ExchangeDH => ExchangeDH,
            ExchangeRp => ExchangeRp,
            ExchangeAF => ExchangeAF,
            ExchangeRS => ExchangeRS,
            I_DJNZ => I_DJNZ,
            I_CPL => I_CPL,
            I_CCF => I_CCF,
            I_SCF => I_SCF,
            I_RETN => I_RETN,
            I_BT => I_BT,
            I_BC => I_BC,
            I_BTR => I_BTR,
            I_RLD => I_RLD,
            I_RRD => I_RRD,
            I_INRC => I_INRC,
            SetDI => SetDI,
            SetEI => SetEI,
            IMode => IMode,
            Halt => Halt,
            NoRead => NoRead,
            Write => Write,
            XYbit_undoc => XYbit_undoc);

    alu : T80_ALU
        generic map(
            Mode => Mode,
            Flag_C => Flag_C,
            Flag_N => Flag_N,
            Flag_P => Flag_P,
            Flag_X => Flag_X,
            Flag_H => Flag_H,
            Flag_Y => Flag_Y,
            Flag_Z => Flag_Z,
            Flag_S => Flag_S)
        port map(
            Arith16 => Arith16_r,
            Z16 => Z16_r,
            ALU_cpi => ALU_cpi_r,
            ALU_Op => ALU_Op_r,
            IR => IR(5 downto 0),
            ISet => ISet,
            BusA => BusA,
            BusB => BusB,
            F_In => F,
            Q => ALU_Q,
            F_Out => F_Out);

    ClkEn <= CEN and not BusAck;

    T_Res <= '1' when TState = unsigned(TStates) else '0';

    NextIs_XY_Fetch <= '1' when XY_State /= "00" and XY_Ind = '0' and
                            ((Set_Addr_To = aXY) or
                            (MCycle = "0001" and IR = "11001011") or
                            (MCycle = "0001" and IR = "00110110")) else '0';

    Save_Mux <= BusB when ExchangeRp = '1' else
        DI_Reg when Save_ALU_r = '0' else
        ALU_Q;

    process (RESET_n, CLK_n)
    begin
        if RESET_n = '0' then
            PC <= (others => '0');  -- Program Counter
            A <= (others => '0');
			update_addr <= '0';
            TmpAddr <= (others => '0');
            TmpBank <= (others => '0');
            A_Bank_r <= (others => '0');
            IR <= "00000000";
            ISet <= "00";
            XY_State <= "00";
            IStatus <= "00";
            MCycles <= "0000";
            DO <= "00000000";
            mode24_r <= "00";
            bank_bc_r <= (others => '0');
            bank_de_r <= (others => '0');
            bank_hl_r <= (others => '0');
            bank_ix_r <= (others => '0');
            bank_iy_r <= (others => '0');
            bank_pc_r <= (others => '0');
            bank_msp_r <= (others => '0');
            bank_int_r <= (others => '0');
            bank_nvr_r <= (others => '0');
            bank_rst_r <= (others => '0');

            ACC <= (others => '1');
            F <= (others => '1');
            Ap <= (others => '1');
            Fp <= (others => '1');
            I <= (others => '0');
            R <= (others => '0');
            SP <= (others => '1');
            -- Phase7: MSP24/IVR24/NVR24 reset to 000000h per
            -- MSX_T80_24bit化_CPU仕様書_V8 section 2 ("RESETは...
            -- MSP24/IVR24/NVR24=000000h"). This differs from the plain Z80
            -- SP register above, which keeps the standard all-1s Z80 reset
            -- convention (MSP24 is a new Z80X24 register with its own
            -- spec'd reset value, not a Z80-compatible stack pointer).
            MSP <= (others => '0');
            IVR <= (others => '0');
            NVR <= (others => '0');
            Alternate <= '0';

            Read_To_Reg_r <= "00000";
            F <= (others => '1');
            Arith16_r <= '0';
            BTR_r <= '0';
            Z16_r <= '0';
            ALU_Op_r <= "0000";
            ALU_cpi_r <= '0';
            Save_ALU_r <= '0';
            PreserveC_r <= '0';
            XY_Ind <= '0';

        elsif CLK_n'event and CLK_n = '1' then

            if ClkEn = '1' then

			update_addr <= '0';
            ALU_Op_r <= "0000";
            ALU_cpi_r <= '0';
            Save_ALU_r <= '0';
            Read_To_Reg_r <= "00000";

            MCycles <= MCycles_d;

            if IMode /= "11" then
                IStatus <= IMode;
            end if;

            Arith16_r <= Arith16;
            PreserveC_r <= PreserveC;
            if ISet = "10" and ALU_OP(2) = '0' and ALU_OP(0) = '1' and MCycle = "0011" then
                Z16_r <= '1';
            else
                Z16_r <= '0';
            end if;

            if MCycle  = "0001" and TState(2) = '0' then
            -- MCycle = 1 and TState = 1, 2, or 3

                if TState = 2 and Wait_n = '1' then
                    if Mode < 2 then
						update_addr <= '1';
                        A(7 downto 0) <= std_logic_vector(R);
                        A(15 downto 8) <= I;
                        A_Bank_r <= (others => '0');
                        R(6 downto 0) <= R(6 downto 0) + 1;
                    end if;

                    if Jump = '0' and Call = '0' and NMICycle = '0' and IntCycle = '0' and not (Halt_FF = '1' or Halt = '1') then
                        -- Phase10: M2 PC24 fetch. In M2, PC is a true
                        -- 24bit counter (PC24={bank_pc_r,PC}); the normal
                        -- opcode-fetch auto-increment must carry/borrow
                        -- into bank_pc_r when PC wraps 0xFFFF->0x0000,
                        -- using the same Addr24_Inc function already used
                        -- by Phase9's MSP24 and Phase3's IX/IY+d (see
                        -- t80_pack.vhd). M0/M1 keep the original plain
                        -- 16bit PC+1 (bank_pc_r is simply unused for
                        -- fetch addressing in those modes - see the
                        -- Set_Addr_To "others"/aXY NextIs_XY_Fetch cases
                        -- below, which only consult bank_pc_r when
                        -- mode24_r="10").
                        if mode24_r = "10" then
                            bank_pc_r <= Addr24_Inc(bank_pc_r, std_logic_vector(PC))(23 downto 16);
                            PC <= unsigned(Addr24_Inc(bank_pc_r, std_logic_vector(PC))(15 downto 0));
                        else
                            PC <= PC + 1;
                        end if;
                    end if;

                    if IntCycle = '1' and IStatus = "01" then
                        IR <= "11111111";
                    elsif Halt_FF = '1' or (IntCycle = '1' and IStatus = "10") or NMICycle = '1' then
                        IR <= "00000000";
                    else
                        IR <= DInst;
                    end if;

                    ISet <= "00";
                    if Prefix /= "00" then
                        if Prefix = "11" then
                            if IR(5) = '1' then
                                XY_State <= "10";
                            else
                                XY_State <= "01";
                            end if;
                        else
                            if Prefix = "10" then
                                XY_State <= "00";
                                XY_Ind <= '0';
                            end if;
                            ISet <= Prefix;
                        end if;
                    else
                        XY_State <= "00";
                        XY_Ind <= '0';
                    end if;
                end if;

            else
            -- either (MCycle > 1) OR (MCycle = 1 AND TState > 3)

                if MCycle = "0110" and XY_State /= "00" then
                    XY_Ind <= '1';
                    if Prefix = "01" then
                        ISet <= "01";
                    end if;
                end if;

                if T_Res = '1' then
					update_addr <= '1';
                    -- Phase3 default: PC fetch, SP/stack and direct (nn)
                    -- addressing stay 16bit (bank byte 00h). Only the
                    -- register-indirect cases below override this for
                    -- M1/M2.
                    A_Bank_r <= (others => '0');
                    BTR_r <= (I_BT or I_BC or I_BTR) and not No_BTR;
                    if Jump = '1' then
                        A(15 downto 8) <= DI_Reg;
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        PC(15 downto 8) <= unsigned(DI_Reg);
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        -- Phase10: JP/JR cc nn and other instructions that
                        -- generate a plain 16bit immediate target always
                        -- mean bank00h, in every mode (CPU仕様書V8 section 5:
                        -- "M2で既存Z80命令が16bit即値メモリアドレスを生成する
                        -- 場合はbank00と解釈する"). bank_pc_r must be kept in
                        -- sync here (not just the A_Bank_r default above),
                        -- since the NEXT instruction's own PC24 auto-
                        -- increment reads bank_pc_r directly - leaving it
                        -- stale here would corrupt every subsequent fetch
                        -- after a jump executed in M2. JP (HL)/(IX)/(IY)
                        -- (JumpXY) and CALL/RST targets (Call/RstP) below
                        -- get the same treatment for the same reason.
                        -- JP.L (Phase11, see JumpL branch below) is a true
                        -- 24bit target and is NOT affected by this rule.
                        bank_pc_r <= (others => '0');
                    elsif JumpL = '1' then
                        -- Phase11: JP.L addr24 (ED C3) / JP.L cc,addr24
                        -- (ED C2/CA/D2/DA/E2/EA/F2/FA). True 24bit far
                        -- jump: TmpAddr holds the latched low+high bytes
                        -- (via LDZ/LDW during M2/M3), and DI_Reg holds the
                        -- freshly-fetched 3rd (bank) byte at this M4
                        -- T_Res. Unlike the plain 'Jump' branch above,
                        -- bank_pc_r/A_Bank_r take this bank byte directly
                        -- instead of resetting to 00h - this is the only
                        -- difference from 'Jump', since JP.L's target is a
                        -- true 24bit address rather than CPU仕様書V8's
                        -- "16bit immediate => bank00h" rule.
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        if mode24_r = "10" then
                            A_Bank_r <= DI_Reg;
                            bank_pc_r <= DI_Reg;
                        else
                            -- Phase11: outside M2, JP.L still reads all 3
                            -- operand bytes (for a mode-independent
                            -- instruction encoding/length) but the bank
                            -- byte has no effect - same bank00h rule as
                            -- plain JP nn ('Jump' above), since M0/M1
                            -- fetch never consults bank_pc_r regardless
                            -- (Phase10's PC24 fetch gating). This avoids a
                            -- "zombie bank_pc_r" where the jump's OWN
                            -- fetch would briefly use the new bank (A_Bank_r
                            -- set here) but every subsequent M0/M1 fetch
                            -- would silently fall back to bank00h anyway.
                            bank_pc_r <= (others => '0');
                        end if;
                    elsif JumpR = '1' then
                        -- Phase11: plain RET / RET cc (CPU仕様書V8/roadmap
                        -- Phase11 "通常CALL/RETは同一64KB segment内用...
                        -- PC_B=不変"). Address restore is otherwise
                        -- identical to 'Jump' (TmpAddr low + DI_Reg high),
                        -- but bank_pc_r/A_Bank_r are explicitly PRESERVED
                        -- (not reset to 00h) - unlike JP nn/JP cc,nn,
                        -- which DO reset to bank00h because their target
                        -- is a genuine 16bit immediate address (CPU仕様書
                        -- V8 section 5's bank00h rule). RET's target is
                        -- not an immediate value; it is whatever bank the
                        -- matching CALL was originally executing in, so
                        -- it must stay in that bank. A_Bank_r needs an
                        -- explicit override here since the top-of-block
                        -- default resets it to 00h.
                        A(15 downto 8) <= DI_Reg;
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= bank_pc_r;
                        PC(15 downto 8) <= unsigned(DI_Reg);
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        -- bank_pc_r itself is left untouched (preserved).
                    elsif JumpXY = '1' then
                        A <= RegBusC;
                        PC <= unsigned(RegBusC);
                        bank_pc_r <= (others => '0');
                    elsif Call = '1' then
                        A <= TmpAddr;
                        PC <= unsigned(TmpAddr);
                        -- Phase11: plain CALL/CALL cc target is "same
                        -- 64KB segment" per CPU仕様書V8/roadmap Phase11
                        -- ("通常CALL/RETは同一64KB segment内用...PC_B=
                        -- 不変") - bank_pc_r is intentionally left
                        -- UNTOUCHED here (preserved), unlike JP/JR/RST's
                        -- "16bit immediate=>bank00h" rule. A_Bank_r needs
                        -- an explicit override since the top-of-block
                        -- default resets it to 00h; RET's matching JumpR
                        -- branch above does the same.
                        A_Bank_r <= bank_pc_r;
                    elsif RstP = '1' then
                        A <= TmpAddr;
                        PC <= unsigned(TmpAddr);
                        bank_pc_r <= (others => '0');
                    elsif CallL = '1' then
                        -- Phase11: CALL.L addr24 / CALL.L cc,addr24 (ED
                        -- CD / ED C4/CC/D4/DC/E4/EC/F4/FC). True 24bit far
                        -- call: TmpAddr/TmpBank hold the latched 3byte
                        -- target (via LDZ/LDW/LDB during M2/M3/M4); the
                        -- 3byte PC24 return frame was already pushed to
                        -- MSP24 by the preceding write cycles (see the
                        -- direct IR-match MSP24-decrement/BANK-byte-DO
                        -- block below, mirroring Phase9's PUSH24). This is
                        -- simply JumpL's logic, reusing TmpBank (latched)
                        -- instead of DI_Reg (freshly read) for the bank
                        -- byte, since CALL.L's bank byte must survive the
                        -- 3 push cycles rather than being consumed
                        -- immediately.
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= TmpBank;
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= TmpBank;
                    elsif RetL = '1' then
                        -- Phase11: RET.L (ED C9 / ED C0/C8/D0/D8/E0/E8/F0/
                        -- F8). True 24bit far return: TmpAddr holds the
                        -- latched low+high bytes (via LDZ/LDW at MCycle
                        -- 2/3), and DI_Reg holds the freshly-read bank
                        -- byte at this MCycle=4 T_Res (mirrors JumpL's
                        -- structure, and POP24's own BANK-byte-via-DI_Reg
                        -- capture pattern).
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= DI_Reg;
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= DI_Reg;
                    elsif JumpM01 = '1' then
                        -- Phase12: JP.M0 addr16 (ED 93) / JP.M1 addr16
                        -- (ED 94). Mode-switching jump: same TmpAddr-low
                        -- + DI_Reg-high shape as plain 'Jump' above
                        -- (no 3rd byte so no bank). ALWAYS resets
                        -- bank_pc_r to 00h (addr16 target = bank00h, same
                        -- rule as plain JP/JR/CALL/RST) and ALWAYS
                        -- switches mode24_r - IR still holds the current
                        -- opcode (93 vs 94) at this T_Res, distinguishing
                        -- which target mode to switch to.
                        A(15 downto 8) <= DI_Reg;
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        PC(15 downto 8) <= unsigned(DI_Reg);
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= (others => '0');
                        if IR = x"93" then
                            mode24_r <= "00";
                        else
                            mode24_r <= "01";
                        end if;
                    elsif JumpM2 = '1' then
                        -- Phase12: JP.M2 addr24 (ED 95). Same 3byte
                        -- target shape as JP.L (TmpAddr low/high + DI_Reg
                        -- bank), but UNCONDITIONALLY switches mode24_r to
                        -- M2 and applies the fetched bank byte (unlike
                        -- JP.L, which only does so when already in M2).
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= DI_Reg;
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= DI_Reg;
                        mode24_r <= "10";
                    elsif CallM01 = '1' then
                        -- Phase12: CALL.M0 addr16 (ED 96) / CALL.M1 addr16
                        -- (ED 97). The 4byte return frame (MODE/PC_B/
                        -- PC_H/PC_L) was already pushed to MSP24 by the
                        -- preceding write cycles (see the direct IR-match
                        -- MSP24-decrement/MODE-PC_B-byte-DO block below,
                        -- mirroring Phase11's CALL.L with MODE prepended).
                        -- Target is a plain 16bit immediate (TmpAddr,
                        -- latched via LDZ/LDW) = bank00h, and mode24_r
                        -- ALWAYS switches per IR (93/94-style distinction,
                        -- here 96=M0/97=M1).
                        A <= TmpAddr;
                        PC <= unsigned(TmpAddr);
                        bank_pc_r <= (others => '0');
                        if IR = x"96" then
                            mode24_r <= "00";
                        else
                            mode24_r <= "01";
                        end if;
                    elsif CallM2 = '1' then
                        -- Phase12: CALL.M2 addr24 (ED 98). The 4byte
                        -- return frame (MODE/PC_B/PC_H/PC_L) was already
                        -- pushed to MSP24 by the preceding write cycles
                        -- (see the direct IR-match MSP24-decrement/MODE-
                        -- PC_B-byte-DO block below). Target is the
                        -- fetched addr24 (TmpAddr low/high via LDZ/LDW,
                        -- TmpBank via LDB), and mode24_r ALWAYS switches
                        -- to M2 unconditionally - like JP.M2, CALL.M2 is
                        -- an explicit mode-switching call, not a same-
                        -- mode far call (unlike CALL.L, which leaves
                        -- mode24_r untouched).
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= TmpBank;
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= TmpBank;
                        mode24_r <= "10";
                    elsif RetM = '1' then
                        -- Phase12: RET.M (ED 99). TmpAddr holds the
                        -- latched low+high bytes (via LDZ/LDW at MCycle
                        -- 2/3), TmpBank holds the latched bank byte (via
                        -- LDB at MCycle 4), and DI_Reg holds the
                        -- freshly-read MODE byte at this MCycle=5 T_Res.
                        -- Unlike every other Phase12 opcode (which
                        -- hardcode their target mode), RET.M restores
                        -- mode24_r from the POPPED value, since it is
                        -- reversing whatever CALL.Mx originally switched
                        -- away from.
                        A(15 downto 8) <= TmpAddr(15 downto 8);
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        A_Bank_r <= TmpBank;
                        PC(15 downto 8) <= unsigned(TmpAddr(15 downto 8));
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= TmpBank;
                        mode24_r <= DI_Reg(1 downto 0);
                    elsif MCycle = MCycles and NMICycle = '1' then
                        A <= "0000000001100110";
                        PC <= "0000000001100110";
                        bank_pc_r <= (others => '0');
                    elsif MCycle = "0011" and IntCycle = '1' and IStatus = "10" then
                        A(15 downto 8) <= I;
                        A(7 downto 0) <= TmpAddr(7 downto 0);
                        PC(15 downto 8) <= unsigned(I);
                        PC(7 downto 0) <= unsigned(TmpAddr(7 downto 0));
                        bank_pc_r <= (others => '0');
                    else
                        case Set_Addr_To is
                        when aXY =>
                            if XY_State = "00" then
                                A <= RegBusC;
                                -- Phase3: plain HL indirect access, 24bit
                                -- logical address is bank_hl_r & HL.
                                if mode24_r /= "00" then
                                    A_Bank_r <= bank_hl_r;
                                end if;
                            else
                                if NextIs_XY_Fetch = '1' then
                                    A <= std_logic_vector(PC);
                                    -- Phase10: fetching the DD/FD-prefixed
                                    -- opcode's own next byte is still part
                                    -- of ordinary sequential instruction
                                    -- fetch, so it needs PC24/bank_pc_r in
                                    -- M2 exactly like the generic "when
                                    -- others" fetch case below.
                                    if mode24_r = "10" then
                                        A_Bank_r <= bank_pc_r;
                                    end if;
                                else
                                    A <= TmpAddr;
                                    -- Phase3: (IX/IY+d) effective address;
                                    -- TmpBank already carries/borrows across
                                    -- the bank byte (Phase2 Addr24_AddDisp8).
                                    if mode24_r /= "00" then
                                        A_Bank_r <= TmpBank;
                                    end if;
                                end if;
                            end if;
                        when aIOA =>
                            if Mode = 3 then
                                -- Memory map I/O on GBZ80
                                A(15 downto 8) <= (others => '1');
                            elsif Mode = 2 then
                                -- Duplicate I/O address on 8080
                                A(15 downto 8) <= DI_Reg;
                            else
                                A(15 downto 8) <= ACC;
                            end if;
                            A(7 downto 0) <= DI_Reg;
                        when aSP =>
                            -- Phase10: M2 active stack pointer = MSP24
                            -- (CPU仕様書V8 section 2/9: "M2 Active stack =
                            -- MSP24"). This single case covers every
                            -- existing Z80 instruction that already goes
                            -- through aSP - PUSH/POP qq, EX (SP),HL/IX/IY,
                            -- CALL/RET/RET cc/RST p, and (incidentally,
                            -- still non-functional pending Phase13's M2
                            -- interrupt frame) NMI/INT/RETI - with zero
                            -- t80_mcode.vhd changes. Only the low 16bit
                            -- word is used as the Z80-style stack address;
                            -- the physical bank comes from bank_msp_r (see
                            -- the SP/MSP adjustment mechanism below for the
                            -- matching Addr24_Dec/Addr24_Inc carry/borrow
                            -- across 64KB, mirroring Phase9's PUSH24/POP24
                            -- but applied once per byte instead of the
                            -- bank byte also being transferred as data).
                            if mode24_r = "10" then
                                A <= std_logic_vector(MSP);
                                A_Bank_r <= bank_msp_r;
                            else
                                A <= std_logic_vector(SP);
                            end if;
                        when aMSP =>
                            -- Phase9: PUSH24/POP24 (ED C1/C5/D1/D5/E1/E5)
                            -- address source. MSP24 is always a 24bit
                            -- pointer (unlike aSP/plain SP), regardless of
                            -- mode24_r, since it is a new Z80X24-only
                            -- register with no M0 legacy meaning - see the
                            -- MSP/bank_msp_r decrement/increment logic
                            -- below for how these settle one cycle ahead
                            -- of this read.
                            A <= std_logic_vector(MSP);
                            A_Bank_r <= bank_msp_r;
                        when aBC =>
                            if Mode = 3 and IORQ_i = '1' then
                                -- Memory map I/O on GBZ80
                                A(15 downto 8) <= (others => '1');
                                A(7 downto 0) <= RegBusC(7 downto 0);
                            else
                                A <= RegBusC;
                                -- Phase3: BC indirect access (LD A,(BC) etc.)
                                if mode24_r /= "00" then
                                    A_Bank_r <= bank_bc_r;
                                end if;
                            end if;
                        when aDE =>
                            A <= RegBusC;
                            -- Phase3: DE indirect access (LD A,(DE) etc.)
                            if mode24_r /= "00" then
                                A_Bank_r <= bank_de_r;
                            end if;
                        when aZI =>
                            if Inc_WZ = '1' then
                                A <= std_logic_vector(unsigned(TmpAddr) + 1);
                            else
                                A(15 downto 8) <= DI_Reg;
                                A(7 downto 0) <= TmpAddr(7 downto 0);
                            end if;
                        when others =>
                            A <= std_logic_vector(PC);
                            -- Phase10: generic opcode-fetch / operand-byte
                            -- fetch address (M1 cycles and most multi-byte
                            -- operand reads). This is the main path that
                            -- needs PC24/bank_pc_r in M2; M0/M1 keep the
                            -- existing plain-16bit behaviour (A_Bank_r
                            -- stays at its 00h default from the top of
                            -- this block).
                            if mode24_r = "10" then
                                A_Bank_r <= bank_pc_r;
                            end if;
                        end case;
                    end if;

                    Save_ALU_r <= Save_ALU;
                    ALU_cpi_r <= ALU_cpi;
                    ALU_Op_r <= ALU_Op;

                    if I_CPL = '1' then
                        -- CPL
                        ACC <= not ACC;
                        F(Flag_Y) <= not ACC(5);
                        F(Flag_H) <= '1';
                        F(Flag_X) <= not ACC(3);
                        F(Flag_N) <= '1';
                    end if;
                    if I_CCF = '1' then
                        -- CCF
                        F(Flag_C) <= not F(Flag_C);
                        F(Flag_Y) <= ACC(5);
                        F(Flag_H) <= F(Flag_C);
                        F(Flag_X) <= ACC(3);
                        F(Flag_N) <= '0';
                    end if;
                    if I_SCF = '1' then
                        -- SCF
                        F(Flag_C) <= '1';
                        F(Flag_Y) <= ACC(5);
                        F(Flag_H) <= '0';
                        F(Flag_X) <= ACC(3);
                        F(Flag_N) <= '0';
                    end if;
                end if;

                if TState = 2 and Wait_n = '1' then
                    if ISet = "01" and MCycle = "0111" then
                        IR <= DInst;
                    end if;
                    if JumpE = '1' then
                        PC <= unsigned(signed(PC) + signed(DI_Reg));
                    elsif JumpEL = '1' then
                        -- Phase11: JR.L e16 / JR.L cc,e16 (ED 18/20/28/30/
                        -- 38/A7/AF/B7/BF). TmpAddr holds the latched
                        -- 16bit signed displacement (via LDZ/LDW at
                        -- MCycle 2/3). M0/M1 keep a plain 16bit wrap
                        -- (CPU仕様書V8/roadmap Phase11 "JR.LはM2では...
                        -- bank境界を跨ぐ" implies M0/M1 do NOT - mirrors
                        -- JP.L's own M0/M1 "degrade to plain" treatment),
                        -- M2 does a true 24bit PC24+displacement add that
                        -- carries/borrows into bank_pc_r via the existing
                        -- Addr24_AddDisp16 helper (t80_pack.vhd, already
                        -- anticipated for exactly this purpose since
                        -- Phase2).
                        if mode24_r = "10" then
                            bank_pc_r <= Addr24_AddDisp16(bank_pc_r, std_logic_vector(PC), TmpAddr)(23 downto 16);
                            PC <= unsigned(Addr24_AddDisp16(bank_pc_r, std_logic_vector(PC), TmpAddr)(15 downto 0));
                        else
                            PC <= unsigned(signed(PC) + signed(TmpAddr));
                        end if;
                    elsif Inc_PC = '1' then
                        -- Phase10: M2 PC24 fetch, same Addr24_Inc carry
                        -- treatment as the opcode-fetch auto-increment
                        -- above - this is the auto-increment used while
                        -- fetching subsequent bytes (operands, displacement,
                        -- immediate data) of the SAME instruction, equally
                        -- part of ordinary sequential instruction fetching.
                        if mode24_r = "10" then
                            bank_pc_r <= Addr24_Inc(bank_pc_r, std_logic_vector(PC))(23 downto 16);
                            PC <= unsigned(Addr24_Inc(bank_pc_r, std_logic_vector(PC))(15 downto 0));
                        else
                            PC <= PC + 1;
                        end if;
                    end if;
                    if BTR_r = '1' then
                        PC <= PC - 2;
                    end if;
                    if RstP = '1' then
                        TmpAddr <= (others =>'0');
                        TmpAddr(5 downto 3) <= IR(5 downto 3);
                    end if;
                end if;
                -- Phase11: this block was originally unconditional for
                -- ANY instruction reaching MCycle=110 at TState=3 - safe
                -- before Phase11 because MCycle only ever reached 110 via
                -- the DD/FD+CB continuation (NextIs_XY_Fetch, itself
                -- gated on XY_State/="00"). CALL.L's own 7-cycle fetch+
                -- push sequence legitimately reaches MCycle=110 too
                -- (M6), so this (IX/IY+d) effective-address computation
                -- must be guarded to not corrupt TmpAddr/TmpBank for
                -- unrelated instructions - see the matching t80_mcode.vhd
                -- guard on the same MCycle=110/111 special-casing.
                if TState = 3 and MCycle = "0110" and XY_State /= "00" then
                    TmpAddr <= std_logic_vector(signed(RegBusC) + signed(DI_Reg));
                    -- Phase2: 24bit address generator for (IX/IY+d).
                    -- M0 keeps plain 16bit wrap (bank unchanged); M1/M2 add
                    -- the signed displacement across the full 24bit IX24/IY24
                    -- value, carrying/borrowing into the bank byte.
                    if mode24_r = "00" then
                        if XY_State(1) = '0' then
                            TmpBank <= bank_ix_r;
                        else
                            TmpBank <= bank_iy_r;
                        end if;
                    else
                        if XY_State(1) = '0' then
                            TmpBank <= Addr24_AddDisp8(bank_ix_r, RegBusC, DI_Reg)(23 downto 16);
                        else
                            TmpBank <= Addr24_AddDisp8(bank_iy_r, RegBusC, DI_Reg)(23 downto 16);
                        end if;
                    end if;
                end if;

                if (TState = 2 and Wait_n = '1') or (TState = 4 and MCycle = "0001") then
                    if IncDec_16(2 downto 0) = "111" then
                        -- Phase10: M2 active stack pointer = MSP24. This
                        -- is the matching half of the aSP->MSP24 address
                        -- redirect above: every existing Z80 instruction
                        -- that increments/decrements "SP" via this shared
                        -- mechanism (PUSH/POP qq, EX (SP),HL/IX/IY, CALL/
                        -- RET/RET cc/RST p, and incidentally NMI/INT/RETI
                        -- pending Phase13) adjusts MSP24 instead when in
                        -- M2, using the same Addr24_Dec/Addr24_Inc 24bit
                        -- carry/borrow already used by Phase9's PUSH24/
                        -- POP24 - so a deep M2 stack can correctly span
                        -- multiple 64KB banks. Only bank_msp_r/MSP are
                        -- touched here (never SP), keeping M0/M1's SP
                        -- register completely untouched by M2 execution.
                        if mode24_r = "10" then
                            if IncDec_16(3) = '1' then
                                bank_msp_r <= Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                                MSP <= unsigned(Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                            else
                                bank_msp_r <= Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                                MSP <= unsigned(Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                            end if;
                        else
                            if IncDec_16(3) = '1' then
                                SP <= SP - 1;
                            else
                                SP <= SP + 1;
                            end if;
                        end if;
                    end if;
                end if;

                -- Phase9: PUSH24/POP24 (ED C1/C5/D1/D5/E1/E5) MSP24 pointer
                -- adjustment (MSX_T80_24bit化_実装手順_V2 section 11
                -- "Phase 9"; CPU仕様書V8 section 9 "Stack"). Kept entirely
                -- separate from the SP/IncDec_16 mechanism just above (MSP
                -- is a plain signal outside the register file, with its
                -- own dedicated 24bit pointer including bank_msp_r - not
                -- one of the 4 register-pairs IncDec_16 already encodes),
                -- so this cannot regress any existing 16bit inc/dec/PUSH/
                -- POP behaviour. Uses Addr24_Dec/Addr24_Inc (t80_pack.vhd,
                -- already anticipated for this exact purpose since Phase2)
                -- so the bank byte correctly carries/borrows together with
                -- the low 16bit word.
                --
                -- PUSH24 decrements BEFORE each of its 3 writes (BANK at
                -- MSP-1, HIGH at MSP-2, LOW at final MSP-3); POP24
                -- increments AFTER each of its 3 reads (LOW at MSP, HIGH at
                -- MSP+1, BANK at MSP+2, final MSP+3). Trigger timing
                -- mirrors the SP mechanism above: the first PUSH24
                -- decrement fires at TState=4 of the extended MCycle=1 (so
                -- it settles via aMSP's T_Res-triggered address readout,
                -- in time for MCycle=2's first write); all other
                -- decrements/increments fire at TState=2 of the mcycle
                -- that precedes the mcycle needing the updated address/
                -- final value.
                if ISet = "10" and XY_State = "00" then
                    case IR is
                    when x"C5" | x"D5" | x"E5" =>  -- PUSH24 BC/DE/HL
                        if (TState = 4 and MCycle = "0001") or
                           (TState = 2 and Wait_n = '1' and (MCycle = "0010" or MCycle = "0011")) then
                            bank_msp_r <= Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    when x"C1" | x"D1" | x"E1" =>  -- POP24 BC/DE/HL
                        if TState = 2 and Wait_n = '1' and
                           (MCycle = "0010" or MCycle = "0011" or MCycle = "0100") then
                            bank_msp_r <= Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    -- Phase11: CALL.L addr24 / CALL.L cc,addr24 MSP24
                    -- pointer adjustment, same pattern as PUSH24 above
                    -- but shifted 3 mcycles later (CALL.L has 3 operand-
                    -- fetch cycles - M2/M3/M4 - before its 3 write cycles
                    -- - M5/M6/M7 - whereas PUSH24 starts writing
                    -- immediately at M2). The first decrement fires at
                    -- TState=3 of M4 (which mcode extends to TStates=4
                    -- via "100", mirroring PUSH24's own extended-M1
                    -- pattern one T-state earlier since M4 is a normal
                    -- 3T-default cycle rather than M1's 4T default) so it
                    -- settles in time for M5's first write; the other two
                    -- decrements mirror PUSH24's own TState=2,Wait_n=1
                    -- pattern exactly, just on M5/M6 instead of M2/M3.
                    when x"CD" | x"C4" | x"CC" | x"D4" | x"DC" | x"E4" | x"EC" | x"F4" | x"FC" =>
                        -- Phase11: the first decrement (TState=3,
                        -- MCycle=100) must additionally check
                        -- Set_Addr_To=aMSP - M4 runs for BOTH taken and
                        -- aborted CALL.L cc (the condition test/divergence
                        -- happens INSIDE M4's own mcode body), so without
                        -- this guard an aborted (not-taken) CALL.L cc
                        -- would still silently decrement MSP24 once with
                        -- no matching write, corrupting it for every
                        -- subsequent PUSH/CALL.L/RET.L.
                        if ((TState = 3 and MCycle = "0100") or
                           (TState = 2 and Wait_n = '1' and (MCycle = "0101" or MCycle = "0110"))) and
                           Set_Addr_To = aMSP then
                            bank_msp_r <= Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    -- Phase11: RET.L / RET.L cc MSP24 pointer adjustment,
                    -- identical pattern to POP24 above (RET.L's pop phase
                    -- starts immediately at M1, same as POP24, so no
                    -- mcycle shift is needed).
                    when x"C9" | x"C0" | x"C8" | x"D0" | x"D8" | x"E0" | x"E8" | x"F0" | x"F8" =>
                        if TState = 2 and Wait_n = '1' and
                           (MCycle = "0010" or MCycle = "0011" or MCycle = "0100") then
                            bank_msp_r <= Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    -- Phase12: CALL.M0/M1 addr16 MSP24 pointer adjustment.
                    -- 4 decrements (one more than CALL.L's 3, for the
                    -- extra MODE byte): the first fires at TState=3 of M3
                    -- (M3 is this instruction's LAST fetch cycle, extended
                    -- via TStates=100 one mcycle earlier than CALL.L's
                    -- own M4, since CALL.M0/M1 only fetch 2 target bytes
                    -- not 3), readying M4's (MODE byte) write address; the
                    -- other 3 mirror CALL.L's own TState=2,Wait_n=1
                    -- pattern, just one mcycle earlier throughout (M4/M5/
                    -- M6 instead of M5/M6) since the whole push phase
                    -- starts one mcycle sooner here.
                    when x"96" | x"97" =>
                        if (TState = 3 and MCycle = "0011") or
                           (TState = 2 and Wait_n = '1' and (MCycle = "0100" or MCycle = "0101" or MCycle = "0110")) then
                            bank_msp_r <= Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    -- Phase12: CALL.M2 addr24 MSP24 pointer adjustment.
                    -- Same 4-decrement shape as CALL.M0/M1 above, but
                    -- shifted one mcycle later throughout (M4/M5/M6/M7
                    -- instead of M3/M4/M5/M6) since CALL.M2 fetches one
                    -- extra (bank) byte: the first fires at TState=3 of
                    -- M4 (this instruction's LAST fetch cycle, exactly
                    -- like CALL.L's own M4), readying M5's (MODE byte)
                    -- write address.
                    when x"98" =>
                        if (TState = 3 and MCycle = "0100") or
                           (TState = 2 and Wait_n = '1' and (MCycle = "0101" or MCycle = "0110" or MCycle = "0111")) then
                            bank_msp_r <= Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Dec(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    -- Phase12: RET.M MSP24 pointer adjustment. 4
                    -- increments (one more than RET.L's 3, for the extra
                    -- MODE byte), identical TState=2,Wait_n=1 pattern to
                    -- RET.L above just extended to MCycle=101(5) too.
                    when x"99" =>
                        if TState = 2 and Wait_n = '1' and
                           (MCycle = "0010" or MCycle = "0011" or MCycle = "0100" or MCycle = "0101") then
                            bank_msp_r <= Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(23 downto 16);
                            MSP <= unsigned(Addr24_Inc(bank_msp_r, std_logic_vector(MSP))(15 downto 0));
                        end if;
                    when others => null;
                    end case;
                end if;

                if LDSPHL = '1' then
                    SP <= unsigned(RegBusC);
                end if;
                if ExchangeAF = '1' then
                    Ap <= ACC;
                    ACC <= Ap;
                    Fp <= F;
                    F <= Fp;
                end if;
                if ExchangeRS = '1' then
                    Alternate <= not Alternate;
                end if;
            end if;

            if TState = 3 then
                if LDZ = '1' then
                    TmpAddr(7 downto 0) <= DI_Reg;
                end if;
                if LDW = '1' then
                    TmpAddr(15 downto 8) <= DI_Reg;
                end if;
                if LDB = '1' then
                    -- Phase11: latches CALL.L addr24's 3rd (bank) operand
                    -- byte, mirroring LDZ/LDW's timing. Reuses the
                    -- existing Phase2/3 TmpBank register (IX/IY+d
                    -- effective-address bank byte); safe since TmpBank is
                    -- only otherwise written by the DD/FD+XY_State-gated
                    -- (IX+d)/(IY+d) paths, which never overlap with
                    -- CALL.L's IR match.
                    TmpBank <= DI_Reg;
                end if;

                if Special_LD(2) = '1' then
                    case Special_LD(1 downto 0) is
                    when "00" =>
                        ACC <= I;
                        F(Flag_P) <= IntE_FF2;
                    when "01" =>
                        ACC <= std_logic_vector(R);
                        F(Flag_P) <= IntE_FF2;
                    when "10" =>
                        I <= ACC;
                    when others =>
                        R <= unsigned(ACC);
                    end case;
                end if;
            end if;

            if (I_DJNZ = '0' and Save_ALU_r = '1') or ALU_Op_r = "1001" then
                if Mode = 3 then
                    F(6) <= F_Out(6);
                    F(5) <= F_Out(5);
                    F(7) <= F_Out(7);
                    if PreserveC_r = '0' then
                        F(4) <= F_Out(4);
                    end if;
                else
                    F(7 downto 1) <= F_Out(7 downto 1);
                    if PreserveC_r = '0' then
                        F(Flag_C) <= F_Out(0);
                    end if;
                end if;
            end if;
            if T_Res = '1' and I_INRC = '1' then
                F(Flag_H) <= '0';
                F(Flag_N) <= '0';
                if DI_Reg(7 downto 0) = "00000000" then
                    F(Flag_Z) <= '1';
                else
                    F(Flag_Z) <= '0';
                end if;
                F(Flag_S) <= DI_Reg(7);
                F(Flag_P) <= not (DI_Reg(0) xor DI_Reg(1) xor DI_Reg(2) xor DI_Reg(3) xor
                    DI_Reg(4) xor DI_Reg(5) xor DI_Reg(6) xor DI_Reg(7));
            end if;

            if TState = 1 and Auto_Wait_t1 = '0' then
                DO <= BusB;
                if I_RLD = '1' then
                    DO(3 downto 0) <= BusA(3 downto 0);
                    DO(7 downto 4) <= BusB(3 downto 0);
                end if;
                if I_RRD = '1' then
                    DO(3 downto 0) <= BusB(7 downto 4);
                    DO(7 downto 4) <= BusA(3 downto 0);
                end if;
                -- Phase9: PUSH24 BC/DE/HL (ED C5/D5/E5) BANK-byte write
                -- override. This is the FIRST of the 3 bytes written
                -- (MCycle=2, at the MSP24 address already decremented once
                -- - see the MSP24 adjustment block below), so it bypasses
                -- the normal Set_BusB_To/BusB staging path entirely (which
                -- only knows how to source 16bit register-file pairs, not
                -- the separate 8bit bank_xx_r signals): bank_bc_r/
                -- bank_de_r/bank_hl_r are read directly here, same-cycle,
                -- with no 1-cycle staging needed (unlike the HIGH/LOW
                -- bytes in MCycle3/4, which DO go through the normal
                -- Set_BusB_To path staged one mcycle ahead by mcode).
                if ISet = "10" and MCycle = "0010" then
                    case IR is
                    when x"C5" => DO <= bank_bc_r;
                    when x"D5" => DO <= bank_de_r;
                    when x"E5" => DO <= bank_hl_r;
                    when others => null;
                    end case;
                end if;
                -- Phase11: CALL.L addr24 / CALL.L cc,addr24 (ED CD / ED
                -- C4/CC/D4/DC/E4/EC/F4/FC) BANK-byte write override. This
                -- is the FIRST of the 3 return-frame bytes written
                -- (MCycle=5, at the MSP24 address already decremented
                -- once - see the MSP24 adjustment block above), bypassing
                -- the normal Set_BusB_To/BusB staging path exactly like
                -- Phase9's PUSH24 override above, since bank_pc_r is a
                -- plain signal outside the register file. Same-cycle,
                -- mcode's own Set_BusB_To<="1101" (PC-HIGH) staged THIS
                -- cycle becomes DO at MCycle=6 via the normal pipeline.
                if ISet = "10" and MCycle = "0101" then
                    case IR is
                    when x"CD" | x"C4" | x"CC" | x"D4" | x"DC" | x"E4" | x"EC" | x"F4" | x"FC" => DO <= bank_pc_r;
                    when others => null;
                    end case;
                end if;
                -- Phase12: CALL.M0 addr16 (ED 96) / CALL.M1 addr16 (ED
                -- 97) MODE-byte write override. This is the FIRST of the
                -- 4 return-frame bytes written (MCycle=4, at the MSP24
                -- address already decremented once), bypassing the
                -- normal Set_BusB_To/BusB staging path since mode24_r is
                -- a plain 2bit signal outside the register file (zero-
                -- extended to a byte; RET.M's matching T_Res branch only
                -- reads back the low 2 bits).
                if ISet = "10" and MCycle = "0100" then
                    case IR is
                    when x"96" | x"97" => DO <= "000000" & mode24_r;
                    when others => null;
                    end case;
                end if;
                -- Phase12: CALL.M0/M1 PC_B-byte (bank_pc_r, the CURRENT
                -- bank being called FROM) write override. This is the
                -- SECOND return-frame byte written (MCycle=5), same
                -- same-cycle-override + next-cycle-stage pattern as
                -- CALL.L's own BANK-byte override above (mcode's own
                -- Set_BusB_To<="1101" staged THIS cycle becomes DO at
                -- MCycle=6 via the normal pipeline).
                if ISet = "10" and MCycle = "0101" then
                    case IR is
                    when x"96" | x"97" => DO <= bank_pc_r;
                    when others => null;
                    end case;
                end if;
                -- Phase12: CALL.M2 addr24 (ED 98) MODE-byte write
                -- override. Same role as CALL.M0/M1's own MODE-byte
                -- override above, shifted one mcycle later (MCycle=5 not
                -- 4) since CALL.M2 has one extra fetch byte (3byte addr24
                -- vs CALL.M0/M1's 2byte addr16).
                if ISet = "10" and MCycle = "0101" then
                    case IR is
                    when x"98" => DO <= "000000" & mode24_r;
                    when others => null;
                    end case;
                end if;
                -- Phase12: CALL.M2 PC_B-byte (bank_pc_r) write override.
                -- Same role as CALL.M0/M1's own PC_B-byte override above,
                -- shifted one mcycle later (MCycle=6 not 5), for the same
                -- reason as the MODE-byte override above. mcode's own
                -- Set_BusB_To<="1101" staged THIS cycle becomes DO at
                -- MCycle=7 via the normal pipeline.
                if ISet = "10" and MCycle = "0110" then
                    case IR is
                    when x"98" => DO <= bank_pc_r;
                    when others => null;
                    end case;
                end if;
            end if;

            if T_Res = '1' then
                    if ISet = "10" then
                        case IR is
                        when x"90" => mode24_r <= "00";
                        when x"91" => mode24_r <= "01";
                        when x"92" =>
                            mode24_r <= "10";
                            -- Phase10: SET_M2 (CPU仕様書V8 section 2:
                            -- "SET_M2はM0/M1→M2でPC_B<-00h、M2→M2では
                            -- PC_B保持"). mode24_r here still holds the
                            -- PRE-transition value (non-blocking read,
                            -- same cycle as the mode24_r<="10" write
                            -- above), so "/= 10" correctly distinguishes
                            -- M0/M1->M2 (reset bank_pc_r) from a redundant
                            -- M2->M2 SET_M2 (leave bank_pc_r untouched).
                            if mode24_r /= "10" then
                                bank_pc_r <= (others => '0');
                            end if;
                        when x"04" => bank_bc_r <= ACC;    -- LD BC_B,A
                        when x"14" => bank_de_r <= ACC;    -- LD DE_B,A
                        when x"24" => bank_hl_r <= ACC;    -- LD HL_B,A
                        when x"05" => bank_ix_r <= ACC;    -- LD IX_B,A
                        when x"15" => bank_iy_r <= ACC;    -- LD IY_B,A
                        when x"3A" => bank_rst_r <= ACC;   -- LD RST_B,A
                        when x"0C" => ACC <= bank_bc_r;    -- LD A,BC_B
                        when x"1C" => ACC <= bank_de_r;    -- LD A,DE_B
                        when x"2C" => ACC <= bank_hl_r;    -- LD A,HL_B
                        when x"0D" => ACC <= bank_ix_r;    -- LD A,IX_B
                        when x"1D" => ACC <= bank_iy_r;    -- LD A,IY_B
                        when x"3E" => ACC <= bank_rst_r;   -- LD A,RST_B
                        -- Phase7: HL24 hub / MSP24 / IVR24 / NVR24 transfer
                        -- (MSX_T80_24bit化_実装手順_V2 section 9 "Phase 7").
                        -- full 24bit, source and F unchanged. The 16bit
                        -- low-word copy (BC/DE/HL/MSP/IVR/NVR) is committed
                        -- via RegWEH/RegWEL/RegDIH/RegDIL below (reading
                        -- the pre-edge RegBusB, routed in one cycle ahead
                        -- via the RegAddrB_r override further below); this
                        -- block only updates the matching 8bit bank byte /
                        -- internal 16bit register at the same clock edge.
                        when x"06" => bank_hl_r <= bank_bc_r;   -- LD24 HL,BC
                        when x"0E" => bank_bc_r <= bank_hl_r;   -- LD24 BC,HL
                        when x"16" => bank_hl_r <= bank_de_r;   -- LD24 HL,DE
                        when x"1E" => bank_de_r <= bank_hl_r;   -- LD24 DE,HL
                        when x"35" => MSP <= unsigned(RegBusB); bank_msp_r <= bank_hl_r; -- LD24 MSP,HL
                        when x"36" => bank_hl_r <= bank_msp_r;  -- LD24 HL,MSP
                        when x"9B" => IVR <= unsigned(RegBusB); bank_int_r <= bank_hl_r; -- LD24 IVR,HL
                        when x"9C" => bank_hl_r <= bank_int_r;  -- LD24 HL,IVR
                        when x"9E" => NVR <= unsigned(RegBusB); bank_nvr_r <= bank_hl_r; -- LD24 NVR,HL
                        when x"9F" => bank_hl_r <= bank_nvr_r;  -- LD24 HL,NVR
                        when others => null;
                        end case;
                    end if;

                    -- Phase8: dedicated 24bit ALU writeback (bank byte) and
                    -- flags. alu24_active/alu24_writeback already fold in
                    -- the ISet="10"/XY_State="00" guard (see the Phase8
                    -- combinational process above), so no further opcode
                    -- matching is needed here. H (half-carry), X and Y
                    -- (undocumented bits 3/5) are intentionally left
                    -- untouched - per CPU仕様書V8 section 6, H is
                    -- preserved, and the spec does not define X/Y for this
                    -- new 24bit ALU group, so they default to preserved too.
                    if alu24_active = '1' then
                        if alu24_writeback = '1' then
                            bank_hl_r <= alu24_result24(23 downto 16);
                        end if;
                        F(Flag_S) <= alu24_result24(23);
                        if alu24_result24 = x"000000" then
                            F(Flag_Z) <= '1';
                        else
                            F(Flag_Z) <= '0';
                        end if;
                        F(Flag_N) <= alu24_sub;
                        F(Flag_P) <= alu24_overflow;
                        F(Flag_C) <= alu24_carry;
                    end if;

                    -- Phase9: POP24 BC/DE/HL (ED C1/D1/E1) BANK-byte read
                    -- capture. This is the LAST of the 3 bytes read
                    -- (MCycle=4); unlike the LOW/HIGH bytes (which commit
                    -- into the register file one mcycle later via the
                    -- normal Read_To_Reg_r pipeline below, exactly like
                    -- plain POP qq), bank_xx_r is a plain signal outside
                    -- the register file, so it can be captured directly,
                    -- same-cycle, straight from DI_Reg (which already holds
                    -- this mcycle's freshly read byte by T_Res, same timing
                    -- already relied on by the Phase6/Phase7 ACC-sourced
                    -- direct overrides above).
                    if ISet = "10" and MCycle = "0100" then
                        case IR is
                        when x"C1" => bank_bc_r <= DI_Reg;
                        when x"D1" => bank_de_r <= DI_Reg;
                        when x"E1" => bank_hl_r <= DI_Reg;
                        when others => null;
                        end case;
                    end if;

                Read_To_Reg_r(3 downto 0) <= Set_BusA_To;
                Read_To_Reg_r(4) <= Read_To_Reg;
                if Read_To_Acc = '1' then
                    Read_To_Reg_r(3 downto 0) <= "0111";
                    Read_To_Reg_r(4) <= '1';
                end if;
            end if;

            if TState = 1 and I_BT = '1' then
                F(Flag_X) <= ALU_Q(3);
                F(Flag_Y) <= ALU_Q(1);
                F(Flag_H) <= '0';
                F(Flag_N) <= '0';
            end if;
            if I_BC = '1' or I_BT = '1' then
                F(Flag_P) <= IncDecZ;
            end if;

            if (TState = 1 and Save_ALU_r = '0' and Auto_Wait_t1 = '0') or
                (Save_ALU_r = '1' and ALU_OP_r /= "0111") then
                case Read_To_Reg_r is
                when "10111" =>
                    ACC <= Save_Mux;
                when "10110" =>
                    DO <= Save_Mux;
                when "11000" =>
                    SP(7 downto 0) <= unsigned(Save_Mux);
                when "11001" =>
                    SP(15 downto 8) <= unsigned(Save_Mux);
                when "11011" =>
                    F <= Save_Mux;
                when others =>
                end case;
                if XYbit_undoc='1' then
                    DO <= ALU_Q;
                end if;
            end if;

        end if;

        end if;

    end process;

---------------------------------------------------------------------------
--
-- Phase8: dedicated 24bit ALU (INC24/DEC24/ADD24/ADC24/SBC24/CP24)
--
-- Fully combinational; purely a "preview" of what the T_Res (TState=4)
-- commit below should write, computed from RegBusC (destination HL's
-- current low word, read via the register file's purely-combinational 3rd
-- port, settled one cycle ahead by the RegAddrC override below - see that
-- override's comment for why RegBusA_r cannot be used here) and RegBusB
-- (source register's low word, same one-cycle-ahead mechanism already
-- used by Phase7). See Alu24_AddSub in t80_pack.vhd for the actual
-- add/subtract/carry/overflow arithmetic. HL target only; DD/FD IX/IY
-- target replacement (per CPU仕様書V8 section 6) is deferred, same scope
-- limitation as Phase7's LD24 HL,IX/IY (AVAILABLE_INSTRUCTIONS.md).
---------------------------------------------------------------------------
    process (IR, ISet, XY_State, bank_hl_r, bank_bc_r, bank_de_r, bank_msp_r,
            MSP, RegBusC, RegBusB, F)
        variable dest24  : std_logic_vector(23 downto 0);
        variable src24   : std_logic_vector(23 downto 0);
        variable sub_v   : std_logic;
        variable cin_v   : std_logic;
        variable wb_v    : std_logic;
        variable active_v: std_logic;
        variable raw     : std_logic_vector(25 downto 0);
    begin
        active_v := '0';
        wb_v     := '0';
        sub_v    := '0';
        cin_v    := '0';
        dest24   := bank_hl_r & RegBusC;
        src24    := (others => '0');

        if ISet = "10" and XY_State = "00" then
            case IR is
            when x"23" =>                          -- INC24 HL
                active_v := '1'; wb_v := '1';
                sub_v := '0'; cin_v := '0';
                src24 := x"000001";
            when x"2B" =>                          -- DEC24 HL
                active_v := '1'; wb_v := '1';
                -- Twos-complement "SUB" convention (mirrors t80_alu.vhd's
                -- AddSub Carry_In seeding for a plain SUB): Sub='1' needs
                -- Carry_In='1' (A + NOT(B) + 1), not '0' - there is no
                -- real borrow-in here, this is the fixed "+1" that turns
                -- ones' complement into twos' complement.
                sub_v := '1'; cin_v := '1';
                src24 := x"000001";
            when x"09" | x"19" | x"29" | x"39" =>   -- ADD24 HL,BC/DE/HL/SP
                active_v := '1'; wb_v := '1';
                sub_v := '0'; cin_v := '0';
                case IR(5 downto 4) is
                when "00" => src24 := bank_bc_r & RegBusB;
                when "01" => src24 := bank_de_r & RegBusB;
                when "10" => src24 := bank_hl_r & RegBusB;
                when others => src24 := bank_msp_r & std_logic_vector(MSP);
                end case;
            when x"07" | x"17" | x"27" | x"37" =>   -- ADC24 HL,BC/DE/HL/SP
                active_v := '1'; wb_v := '1';
                sub_v := '0'; cin_v := F(Flag_C);
                case IR(5 downto 4) is
                when "00" => src24 := bank_bc_r & RegBusB;
                when "01" => src24 := bank_de_r & RegBusB;
                when "10" => src24 := bank_hl_r & RegBusB;
                when others => src24 := bank_msp_r & std_logic_vector(MSP);
                end case;
            when x"0F" | x"1F" | x"2F" | x"3F" =>   -- SBC24 HL,BC/DE/HL/SP
                active_v := '1'; wb_v := '1';
                -- Carry_In = NOT F(Flag_C): A - B - borrow = A + NOT(B) +
                -- NOT(borrow), same twos-complement convention as above,
                -- now folding in the real existing-carry-flag borrow-in.
                sub_v := '1'; cin_v := not F(Flag_C);
                case IR(5 downto 4) is
                when "00" => src24 := bank_bc_r & RegBusB;
                when "01" => src24 := bank_de_r & RegBusB;
                when "10" => src24 := bank_hl_r & RegBusB;
                when others => src24 := bank_msp_r & std_logic_vector(MSP);
                end case;
            when x"3D" =>                          -- CP24 HL,DE (no writeback)
                active_v := '1'; wb_v := '0';
                sub_v := '1'; cin_v := '1';         -- same "SUB" convention as DEC24
                src24 := bank_de_r & RegBusB;
            when others => null;
            end case;
        end if;

        raw := Alu24_AddSub(dest24, src24, sub_v, cin_v);

        alu24_active    <= active_v;
        alu24_writeback <= wb_v;
        alu24_sub       <= sub_v;
        alu24_result24  <= raw(23 downto 0);
        alu24_overflow  <= raw(25);
        if sub_v = '1' then
            alu24_carry <= not raw(24);
        else
            alu24_carry <= raw(24);
        end if;
    end process;

---------------------------------------------------------------------------
--
-- BC('), DE('), HL('), IX and IY
--
---------------------------------------------------------------------------
    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if ClkEn = '1' then
                -- Bus A / Write
                RegAddrA_r <= Alternate & Set_BusA_To(2 downto 1);
                if XY_Ind = '0' and XY_State /= "00" and Set_BusA_To(2 downto 1) = "10" then
                    RegAddrA_r <= XY_State(1) & "11";
                end if;

                -- Bus B
                RegAddrB_r <= Alternate & Set_BusB_To(2 downto 1);
                if XY_Ind = '0' and XY_State /= "00" and Set_BusB_To(2 downto 1) = "10" then
                    RegAddrB_r <= XY_State(1) & "11";
                end if;

                -- Phase7: HL24 hub / MSP24 / IVR24 / NVR24 register-pair
                -- transfer (ED06/0E/16/1E/35/36/9B/9C/9E/9F). t80_mcode.vhd
                -- leaves these opcodes classified as NOP (Set_BusA_To/
                -- Set_BusB_To stay "0000"), so the pipelined register-file
                -- addresses are overridden directly here instead - the same
                -- one-cycle-ahead pipelining already used above for
                -- Set_BusA_To/Set_BusB_To, so the correct address is
                -- already in place by the time T_Res (TState=4) commits the
                -- write (see RegWEH/RegWEL and RegDIH/RegDIL below, and the
                -- bank-byte/internal-register update in the ED-prefixed
                -- case block above).
                if ISet = "10" then
                    case IR is
                    when x"06" | x"16" | x"36" | x"9C" | x"9F" =>
                        RegAddrA_r <= Alternate & "10";    -- dest HL
                    when x"0E" =>
                        RegAddrA_r <= Alternate & "00";    -- dest BC
                    when x"1E" =>
                        RegAddrA_r <= Alternate & "01";    -- dest DE
                    when others => null;
                    end case;
                    case IR is
                    when x"0E" | x"1E" | x"35" | x"9B" | x"9E" =>
                        RegAddrB_r <= Alternate & "10";    -- src HL
                    when x"06" =>
                        RegAddrB_r <= Alternate & "00";    -- src BC
                    when x"16" =>
                        RegAddrB_r <= Alternate & "01";    -- src DE
                    when others => null;
                    end case;

                    -- Phase8: dedicated 24bit ALU (ED23/2B/09/19/29/39/
                    -- 07/17/27/37/0F/1F/2F/3F/3D). HL target only (see the
                    -- Phase8 combinational process above); guarded by
                    -- XY_State="00" so a stray DD/FD-prefixed instance of
                    -- these opcode bytes (IX/IY target, deferred) falls
                    -- through to the default NOP classification instead of
                    -- picking up a wrong register address.
                    if XY_State = "00" then
                        case IR is
                        when x"23" | x"2B" | x"09" | x"19" | x"29" | x"39" |
                             x"07" | x"17" | x"27" | x"37" | x"0F" | x"1F" |
                             x"2F" | x"3F" | x"3D" =>
                            RegAddrA_r <= Alternate & "10";    -- dest HL
                        when others => null;
                        end case;
                        case IR is
                        when x"09" | x"07" | x"0F" =>
                            RegAddrB_r <= Alternate & "00";    -- src BC
                        when x"19" | x"17" | x"1F" | x"3D" =>
                            RegAddrB_r <= Alternate & "01";    -- src DE
                        when x"29" | x"27" | x"2F" =>
                            RegAddrB_r <= Alternate & "10";    -- src HL
                        when others => null;    -- SP(MSP24): no register-file read needed
                        end case;
                    end if;
                end if;


                -- Address from register
                RegAddrC <= Alternate & Set_Addr_To(1 downto 0);
                -- Jump (HL), LD SP,HL
                if (JumpXY = '1' or LDSPHL = '1') then
                    RegAddrC <= Alternate & "10";
                end if;
                if ((JumpXY = '1' or LDSPHL = '1') and XY_State /= "00") or (MCycle = "0110" and XY_State /= "00") then
                    RegAddrC <= XY_State(1) & "11";
                end if;

                -- Phase8: dedicated 24bit ALU dest (HL) read. RegBusA_r is
                -- NOT usable here: it is delayed by a full TWO cycles from
                -- when RegAddrA_r is set (one cycle for RegAddrA_r itself
                -- to reach RegAddrA/RegBusA, another for "RegBusA_r <=
                -- RegBusA" below to sample it), but an ED-prefixed opcode
                -- only has ONE cycle between ISet/IR settling (at the
                -- TState 2->3 edge of the opcode-fetch MCycle) and T_Res
                -- (TState=4) committing - RegBusA_r would still hold stale
                -- data from the *previous* instruction at that point. The
                -- purely-combinational 3rd port (RegAddrC/RegBusC, used
                -- elsewhere only for JumpXY/LDSPHL/(IX/IY+d) which are all
                -- inactive during these opcodes) has no such extra delay:
                -- once RegAddrC is set here (one cycle ahead, same as
                -- RegAddrA_r/RegAddrB_r), RegBusC reflects HL's current
                -- value immediately, in time for the Phase8 combinational
                -- ALU process to read it at T_Res.
                if ISet = "10" and XY_State = "00" then
                    case IR is
                    when x"23" | x"2B" | x"09" | x"19" | x"29" | x"39" |
                         x"07" | x"17" | x"27" | x"37" | x"0F" | x"1F" |
                         x"2F" | x"3F" | x"3D" =>
                        RegAddrC <= Alternate & "10";    -- dest/compare HL
                    when others => null;
                    end case;
                end if;

                if I_DJNZ = '1' and Save_ALU_r = '1' and Mode < 2 then
                    IncDecZ <= F_Out(Flag_Z);
                end if;
                if (TState = 2 or (TState = 3 and MCycle = "0001")) and IncDec_16(2 downto 0) = "100" then
                    if ID16 = 0 then
                        IncDecZ <= '0';
                    else
                        IncDecZ <= '1';
                    end if;
                end if;

                RegBusA_r <= RegBusA;
            end if;
        end if;
    end process;

    RegAddrA <=
            -- 16 bit increment/decrement
            Alternate & IncDec_16(1 downto 0) when (TState = 2 or
                (TState = 3 and MCycle = "0001" and IncDec_16(2) = '1')) and XY_State = "00" else
            XY_State(1) & "11" when (TState = 2 or
                (TState = 3 and MCycle = "0001" and IncDec_16(2) = '1')) and IncDec_16(1 downto 0) = "10" else
            -- EX HL,DL
            Alternate & "10" when ExchangeDH = '1' and TState = 3 else
            Alternate & "01" when ExchangeDH = '1' and TState = 4 else
            -- Bus A / Write
            RegAddrA_r;

    RegAddrB <=
            -- EX HL,DL
            Alternate & "01" when ExchangeDH = '1' and TState = 3 else
            -- Bus B
            RegAddrB_r;

    ID16 <= signed(RegBusA) - 1 when IncDec_16(3) = '1' else
            signed(RegBusA) + 1;

    process (Save_ALU_r, Auto_Wait_t1, ALU_OP_r, Read_To_Reg_r,
            ExchangeDH, IncDec_16, MCycle, TState, Wait_n, ISet, IR,
            alu24_active, alu24_writeback)
    begin
        RegWEH <= '0';
        RegWEL <= '0';
        if (TState = 1 and Save_ALU_r = '0' and Auto_Wait_t1 = '0') or
            (Save_ALU_r = '1' and ALU_OP_r /= "0111") then
            case Read_To_Reg_r is
            when "10000" | "10001" | "10010" | "10011" | "10100" | "10101" =>
                RegWEH <= not Read_To_Reg_r(0);
                RegWEL <= Read_To_Reg_r(0);
            when others =>
            end case;
        end if;

        if ExchangeDH = '1' and (TState = 3 or TState = 4) then
            RegWEH <= '1';
            RegWEL <= '1';
        end if;

        if IncDec_16(2) = '1' and ((TState = 2 and Wait_n = '1' and MCycle /= "0001") or (TState = 3 and MCycle = "0001")) then
            case IncDec_16(1 downto 0) is
            when "00" | "01" | "10" =>
                RegWEH <= '1';
                RegWEL <= '1';
            when others =>
            end case;
        end if;

        -- Phase7: HL24 hub / MSP24 / IVR24 / NVR24 register-pair writeback
        -- (ED06/0E/16/1E/36/9C/9F write BC/DE/HL; ED9A/9D immediate-load and
        -- the DD/FD ED26/2E IX/IY hub variants are not part of this
        -- increment, see AVAILABLE_INSTRUCTIONS.md). Committed at T_Res
        -- (TState=4) of the ED-prefixed opcode-fetch MCycle; the
        -- destination address is set up one cycle ahead via RegAddrA_r
        -- above.
        if ISet = "10" and MCycle = "0001" and TState = 4 then
            case IR is
            when x"06" | x"0E" | x"16" | x"1E" | x"36" | x"9C" | x"9F" =>
                RegWEH <= '1';
                RegWEL <= '1';
            when others => null;
            end case;
        end if;

        -- Phase8: dedicated 24bit ALU writeback (low 16bit word). Paired
        -- with the bank_hl_r write and flags at T_Res in the big clocked
        -- process above; alu24_active/alu24_writeback already fold in the
        -- ISet="10"/XY_State="00"/HL-target-only guard (see the Phase8
        -- combinational process), so only MCycle/TState need checking here.
        if MCycle = "0001" and TState = 4 and alu24_active = '1' and alu24_writeback = '1' then
            RegWEH <= '1';
            RegWEL <= '1';
        end if;
    end process;

    process (Save_Mux, RegBusB, RegBusA_r, ID16,
            ExchangeDH, IncDec_16, MCycle, TState, Wait_n, ISet, IR, MSP, IVR, NVR,
            alu24_active, alu24_writeback, alu24_result24)
    begin
        RegDIH <= Save_Mux;
        RegDIL <= Save_Mux;

        if ExchangeDH = '1' and TState = 3 then
            RegDIH <= RegBusB(15 downto 8);
            RegDIL <= RegBusB(7 downto 0);
        end if;
        if ExchangeDH = '1' and TState = 4 then
            RegDIH <= RegBusA_r(15 downto 8);
            RegDIL <= RegBusA_r(7 downto 0);
        end if;

        if IncDec_16(2) = '1' and ((TState = 2 and MCycle /= "0001") or (TState = 3 and MCycle = "0001")) then
            RegDIH <= std_logic_vector(ID16(15 downto 8));
            RegDIL <= std_logic_vector(ID16(7 downto 0));
        end if;

        -- Phase7: HL24 hub / MSP24 / IVR24 / NVR24 register-pair writeback
        -- data source, paired with the RegWEH/RegWEL commit above.
        if ISet = "10" and MCycle = "0001" and TState = 4 then
            case IR is
            when x"06" | x"0E" | x"16" | x"1E" =>
                RegDIH <= RegBusB(15 downto 8);
                RegDIL <= RegBusB(7 downto 0);
            when x"36" =>
                RegDIH <= std_logic_vector(MSP(15 downto 8));
                RegDIL <= std_logic_vector(MSP(7 downto 0));
            when x"9C" =>
                RegDIH <= std_logic_vector(IVR(15 downto 8));
                RegDIL <= std_logic_vector(IVR(7 downto 0));
            when x"9F" =>
                RegDIH <= std_logic_vector(NVR(15 downto 8));
                RegDIL <= std_logic_vector(NVR(7 downto 0));
            when others => null;
            end case;
        end if;

        -- Phase8: dedicated 24bit ALU writeback data source, paired with
        -- the RegWEH/RegWEL commit above.
        if MCycle = "0001" and TState = 4 and alu24_active = '1' and alu24_writeback = '1' then
            RegDIH <= alu24_result24(15 downto 8);
            RegDIL <= alu24_result24(7 downto 0);
        end if;
    end process;

    Regs : T80_Reg
        port map(
            Clk => CLK_n,
            CEN => ClkEn,
            WEH => RegWEH,
            WEL => RegWEL,
            AddrA => RegAddrA,
            AddrB => RegAddrB,
            AddrC => RegAddrC,
            DIH => RegDIH,
            DIL => RegDIL,
            DOAH => RegBusA(15 downto 8),
            DOAL => RegBusA(7 downto 0),
            DOBH => RegBusB(15 downto 8),
            DOBL => RegBusB(7 downto 0),
            DOCH => RegBusC(15 downto 8),
            DOCL => RegBusC(7 downto 0));

---------------------------------------------------------------------------
--
-- Buses
--
---------------------------------------------------------------------------
    process (CLK_n)
    begin
        if CLK_n'event and CLK_n = '1' then
            if ClkEn = '1' then
            case Set_BusB_To is
            when "0111" =>
                BusB <= ACC;
            when "0000" | "0001" | "0010" | "0011" | "0100" | "0101" =>
                if Set_BusB_To(0) = '1' then
                    BusB <= RegBusB(7 downto 0);
                else
                    BusB <= RegBusB(15 downto 8);
                end if;
            when "0110" =>
                BusB <= DI_Reg;
            when "1000" =>
                BusB <= std_logic_vector(SP(7 downto 0));
            when "1001" =>
                BusB <= std_logic_vector(SP(15 downto 8));
            when "1010" =>
                BusB <= "00000001";
            when "1011" =>
                BusB <= F;
            when "1100" =>
                BusB <= std_logic_vector(PC(7 downto 0));
            when "1101" =>
                BusB <= std_logic_vector(PC(15 downto 8));
            when "1110" =>
                BusB <= "00000000";
            when others =>
                BusB <= "--------";
            end case;

            case Set_BusA_To is
            when "0111" =>
                BusA <= ACC;
            when "0000" | "0001" | "0010" | "0011" | "0100" | "0101" =>
                if Set_BusA_To(0) = '1' then
                    BusA <= RegBusA(7 downto 0);
                else
                    BusA <= RegBusA(15 downto 8);
                end if;
            when "0110" =>
                BusA <= DI_Reg;
            when "1000" =>
                BusA <= std_logic_vector(SP(7 downto 0));
            when "1001" =>
                BusA <= std_logic_vector(SP(15 downto 8));
            when "1010" =>
                BusA <= "00000000";
            when others =>
                BusB <= "--------";
            end case;
            if XYbit_undoc='1' then
                BusA <= DI_Reg;
                BusB <= DI_Reg;
            end if;
            end if;
        end if;
    end process;

---------------------------------------------------------------------------
--
-- Generate external control signals
--
---------------------------------------------------------------------------
    process (RESET_n,CLK_n)
    begin
        if RESET_n = '0' then
            RFSH_n <= '1';
        elsif CLK_n'event and CLK_n = '1' then
            if CEN = '1' then
            if MCycle = "0001" and ((TState = 2  and Wait_n = '1') or TState = 3) then
                RFSH_n <= '0';
            else
                RFSH_n <= '1';
            end if;
            end if;
        end if;
    end process;

    -- Phase12: MCycle is now 4 bits (to allow CALL.M2's 8th cycle), but the
    -- external MC debug/monitor port stays 3 bits for compatibility with
    -- g80a.vhd/T80s.vhd (which only ever test it against "001"). Truncate.
    MC <= MCycle(2 downto 0);
    TS <= std_logic_vector(TState);
    mode24 <= mode24_r;
    A_Bank <= A_Bank_r;
    bank_bc <= bank_bc_r;
    bank_de <= bank_de_r;
    bank_hl <= bank_hl_r;
    bank_ix <= bank_ix_r;
    bank_iy <= bank_iy_r;
    bank_pc <= bank_pc_r;
    bank_msp <= bank_msp_r;
    bank_int <= bank_int_r;
    bank_nvr <= bank_nvr_r;
    bank_rst <= bank_rst_r;
    DI_Reg <= DI;
    HALT_n <= not Halt_FF;
    BUSAK_n <= not BusAck;
    IntCycle_n <= not IntCycle;
    IntE <= IntE_FF1;
    IORQ <= IORQ_i;
    Stop <= I_DJNZ;

-------------------------------------------------------------------------
--
-- Syncronise inputs
--
-------------------------------------------------------------------------
    process (RESET_n, CLK_n)
        variable OldNMI_n : std_logic;
    begin
        if RESET_n = '0' then
            BusReq_s <= '0';
            INT_s <= '0';
            NMI_s <= '0';
            OldNMI_n := '0';
        elsif CLK_n'event and CLK_n = '1' then
            if CEN = '1' then
            BusReq_s <= not BUSRQ_n;
            INT_s <= not INT_n;
            if NMICycle = '1' then
                NMI_s <= '0';
            elsif NMI_n = '0' and OldNMI_n = '1' then
                NMI_s <= '1';
            end if;
            OldNMI_n := NMI_n;
            end if;
        end if;
    end process;

-------------------------------------------------------------------------
--
-- Main state machine
--
-------------------------------------------------------------------------
    process (RESET_n, CLK_n)
    begin
        if RESET_n = '0' then
            MCycle <= "0001";
            TState <= "000";
            Pre_XY_F_M <= "0000";
            XYF_Pending <= '0';
            Halt_FF <= '0';
            BusAck <= '0';
            NMICycle <= '0';
            IntCycle <= '0';
            IntE_FF1 <= '0';
            IntE_FF2 <= '0';
            No_BTR <= '0';
            Auto_Wait_t1 <= '0';
            Auto_Wait_t2 <= '0';
            M1_n <= '1';
        elsif CLK_n'event and CLK_n = '1' then
            if CEN = '1' then
            if T_Res = '1' then
                Auto_Wait_t1 <= '0';
            else
                Auto_Wait_t1 <= Auto_Wait or IORQ_i;
            end if;
            Auto_Wait_t2 <= Auto_Wait_t1;
            No_BTR <= (I_BT and (not IR(4) or not F(Flag_P))) or
                    (I_BC and (not IR(4) or F(Flag_Z) or not F(Flag_P))) or
                    (I_BTR and (not IR(4) or F(Flag_Z)));
            if TState = 2 then
                if SetEI = '1' then
                    IntE_FF1 <= '1';
                    IntE_FF2 <= '1';
                end if;
                if I_RETN = '1' then
                    IntE_FF1 <= IntE_FF2;
                end if;
            end if;
            if TState = 3 then
                if SetDI = '1' then
                    IntE_FF1 <= '0';
                    IntE_FF2 <= '0';
                end if;
            end if;
            if IntCycle = '1' or NMICycle = '1' then
                Halt_FF <= '0';
            end if;
            if MCycle = "0001" and TState = 2 and Wait_n = '1' then
                M1_n <= '1';
            end if;
            if BusReq_s = '1' and BusAck = '1' then
            else
                BusAck <= '0';
                if TState = 2 and Wait_n = '0' then
                elsif T_Res = '1' then
                    if Halt = '1' then
                        Halt_FF <= '1';
                    end if;
                    if BusReq_s = '1' then
                        BusAck <= '1';
                    else
                        TState <= "001";
                        if NextIs_XY_Fetch = '1' then
                            MCycle <= "0110";
                            Pre_XY_F_M <= MCycle;
                            -- Phase11: mark that MCycle is about to reach
                            -- "110"/"111" via this legitimate DD/FD+CB
                            -- continuation jump, not because some OTHER
                            -- instruction (e.g. CALL.L) simply has that
                            -- many MCycles of its own. Cleared once
                            -- consumed below.
                            XYF_Pending <= '1';
                            if IR = "00110110" and Mode = 0 then
                                Pre_XY_F_M <= "0010";
                            end if;
                        elsif (MCycle = "0111" and XYF_Pending = '1') or
                            (MCycle = "0110" and Mode = 1 and ISet /= "01") then
                            MCycle <= std_logic_vector(unsigned(Pre_XY_F_M) + 1);
                            XYF_Pending <= '0';
                        elsif (MCycle = MCycles) or
                            No_BTR = '1' or
                            (MCycle = "0010" and I_DJNZ = '1' and IncDecZ = '1') then
                            M1_n <= '0';
                            MCycle <= "0001";
                            IntCycle <= '0';
                            NMICycle <= '0';
                            if NMI_s = '1' and Prefix = "00" then
                                NMICycle <= '1';
                                IntE_FF1 <= '0';
                            elsif (IntE_FF1 = '1' and INT_s = '1') and Prefix = "00" and SetEI = '0' then
                                IntCycle <= '1';
                                IntE_FF1 <= '0';
                                IntE_FF2 <= '0';
                            end if;
                        else
                            MCycle <= std_logic_vector(unsigned(MCycle) + 1);
                        end if;
                    end if;
                else
                    if (Auto_Wait = '1' and Auto_Wait_t2 = '0') nor
                        (IOWait = 1 and IORQ_i = '1' and Auto_Wait_t1 = '0') then
                        TState <= TState + 1;
                    end if;
                end if;
            end if;
            if TState = 0 then
                M1_n <= '0';
            end if;
            end if;
        end if;
    end process;

    process (IntCycle, NMICycle, MCycle)
    begin
        Auto_Wait <= '0';
        if IntCycle = '1' or NMICycle = '1' then
            if MCycle = "0001" then
                Auto_Wait <= '1';
            end if;
        end if;
    end process;

end;
