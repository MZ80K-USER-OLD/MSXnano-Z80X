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
--  0211 : Fixed IM 1
--  0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
--  0235 : Added IM 2 fix by Mike Johnson
--  0238 : Added NoRead signal
--  0238b: Fixed instruction timing for POP and DJNZ
--  0240 : Added (IX/IY+d) states, removed op-codes from mode 2 and added all remaining mode 3 op-codes
--  0242 : Fixed I/O instruction timing, cleanup
--  0242a: 31st of August, 2003 by Kazuhiro Tsujikawa (tujikawa@hat.hi-ho.ne.jp)
--         Fixed INI, IND, INIR, INDR, OUTI, OUTD, OTIR, OTDR instructions
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

entity T80_MCode is
        generic(
                Mode        : integer := 0;
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
                IR          : in std_logic_vector(7 downto 0);
                ISet        : in std_logic_vector(1 downto 0);
                MCycle      : in std_logic_vector(3 downto 0);
                F           : in std_logic_vector(7 downto 0);
                NMICycle    : in std_logic;
                IntCycle    : in std_logic;
                XY_State    : in std_logic_vector(1 downto 0);
                -- New (V4 21.2): captures XY_State at the moment an ED
                -- prefix is recognized (latched in t80.vhd, independent
                -- of XY_State itself which continues to reset to "00" on
                -- every ED exactly as before - see t80.vhd for the full
                -- rationale). "00" = bare ED (no preceding DD/FD); "01"/
                -- "10" = DD/FD immediately preceded this ED (IX/IY).
                -- Consulted only by the ED 68/69 (LEA.L) dispatch below;
                -- every other ED-prefixed opcode is unaffected.
                LeaXY       : in std_logic_vector(1 downto 0);
                MCycles     : out std_logic_vector(3 downto 0);
                TStates     : out std_logic_vector(2 downto 0);
                Prefix      : out std_logic_vector(1 downto 0); -- None,CB,ED,DD/FD
                Inc_PC      : out std_logic;
                Inc_WZ      : out std_logic;
                IncDec_16   : out std_logic_vector(3 downto 0); -- BC,DE,HL,SP   0 is inc
                Read_To_Reg : out std_logic;
                Read_To_Acc : out std_logic;
                Set_BusA_To : out std_logic_vector(3 downto 0); -- B,C,D,E,H,L,DI/DB,A,SP(L),SP(M),0,F
                Set_BusB_To : out std_logic_vector(3 downto 0); -- B,C,D,E,H,L,DI,A,SP(L),SP(M),1,F,PC(L),PC(M),0
                ALU_Op      : out std_logic_vector(3 downto 0);
                        -- ADD, ADC, SUB, SBC, AND, XOR, OR, CP, ROT, BIT, SET, RES, DAA, RLD, RRD, None
                ALU_cpi     : out std_logic;    --for undoc XY-Flags
                Save_ALU    : out std_logic;
                PreserveC   : out std_logic;
                Arith16     : out std_logic;
                Set_Addr_To : out std_logic_vector(2 downto 0); -- aNone,aXY,aIOA,aSP,aBC,aDE,aZI
                IORQ        : out std_logic;
                Jump        : out std_logic;
                -- Phase11: JP.L addr24 / JP.L cc,addr24 (ED C3 / ED C2/CA/
                -- D2/DA/E2/EA/F2/FA). Parallel to Jump, but the matching
                -- t80.vhd T_Res branch loads bank_pc_r from the freshly
                -- fetched 3rd (bank) operand byte instead of resetting it
                -- to 00h, giving a true 24bit far jump target.
                JumpL       : out std_logic;
                -- Phase11: plain RET/RET cc (ED-less C9 / C0/C8/D0/D8/E0/
                -- E8/F0/F8). Parallel to Jump, but PRESERVES bank_pc_r
                -- instead of resetting it (CPU仕様書V8/roadmap Phase11
                -- "通常CALL/RETは同一64KB segment内用...PC_B=不変") - RET's
                -- target is not an immediate value, so the general
                -- "16bit immediate=>bank00h" rule does not apply to it.
                JumpR       : out std_logic;
                JumpE       : out std_logic;
                -- Phase11: JR.L e16 / JR.L cc,e16 (ED 18/20/28/30/38/A7/
                -- AF/B7/BF). Parallel to JumpE (plain JR's 8bit signed
                -- displacement add), but TmpAddr holds a LATCHED 16bit
                -- signed displacement (via LDZ/LDW) instead of JumpE's
                -- direct 1-cycle DI_Reg read, and the add is a true 24bit
                -- PC24+displacement (with bank carry/borrow) in M2 rather
                -- than a plain 16bit PC+DI_Reg.
                JumpEL      : out std_logic;
                JumpXY      : out std_logic;
                Call        : out std_logic;
                -- Phase11: CALL.L addr24 / CALL.L cc,addr24 (ED CD / ED
                -- C4/CC/D4/DC/E4/EC/F4/FC). M2 24bit far call: pushes a
                -- 3byte PC24 return frame (bank_pc_r/PC_H/PC_L, same
                -- write order as Phase9's PUSH24) to MSP24, then jumps to
                -- the freshly fetched 24bit target (TmpAddr+TmpBank).
                CallL       : out std_logic;
                -- Phase11: RET.L (ED C9 / ED C0/C8/D0/D8/E0/E8/F0/F8).
                -- M2 24bit far return: pops the matching 3byte PC24 frame
                -- from MSP24 (same read order as Phase9's POP24) and
                -- jumps to it.
                RetL        : out std_logic;
                -- Phase12: JP.M0/M1 addr16 (ED 93/94). Mode-switching
                -- jump: identical fetch/trigger shape to plain 'Jump'
                -- (TmpAddr low via LDZ + DI_Reg high, no 3rd byte so no
                -- LDW needed), but ALSO unconditionally switches
                -- mode24_r to M0/M1 (distinguished by IR in t80.vhd) and
                -- resets bank_pc_r to 00h (CPU仕様書V8 roadmap Phase12
                -- "モード間制御" - addr16 targets are always bank00h).
                JumpM01     : out std_logic;
                -- Phase12: JP.M2 addr24 (ED 95). Same 3byte fetch shape
                -- as JP.L (TmpAddr low/high via LDZ/LDW + DI_Reg bank),
                -- but UNCONDITIONALLY switches mode24_r to M2 and applies
                -- the fetched bank byte (unlike JP.L, which only applies
                -- the bank byte when ALREADY in M2 and leaves mode24_r
                -- untouched).
                JumpM2      : out std_logic;
                -- Phase12: CALL.M0/M1 addr16 (ED 96/97). Same 2byte
                -- fetch shape as plain 'CALL nn' (TmpAddr low/high via
                -- LDZ/LDW), but pushes a 4byte return frame (MODE/PC_B/
                -- PC_H/PC_L, same decrement-before-write pattern as
                -- Phase11's CALL.L with MODE prepended - CPU仕様書V8
                -- roadmap Phase12 "CALL.MxはMSPへ4byte保存する") to MSP24,
                -- then switches mode24_r to M0/M1 (distinguished by IR)
                -- and resets bank_pc_r to 00h.
                CallM01     : out std_logic;
                -- Phase12: CALL.M2 addr24 (ED 98). Same 3byte fetch
                -- shape as CALL.L (TmpAddr low/high via LDZ/LDW, bank
                -- via LDB), but pushes the SAME 4byte return frame as
                -- CallM01 above (MODE/PC_B/PC_H/PC_L), one mcycle later
                -- throughout since there is one extra fetch byte. Needs
                -- 8 total MCycles (1 opcode + 3 fetch + 4 push), which
                -- only became representable once MCycle was widened from
                -- 3 to 4 bits - see the MCycle-width report referenced
                -- from AVAILABLE_INSTRUCTIONS.md section 10.2.
                CallM2      : out std_logic;
                -- Phase12: RET.M (ED 99). Pops the matching 4byte frame
                -- (LOW/HIGH/BANK/MODE, same increment-after-read pattern
                -- as Phase11's RET.L with MODE appended) from MSP24 and
                -- restores BOTH PC24 and mode24_r from the popped MODE
                -- byte (the only one of these new Phase12 opcodes that
                -- restores a previously-saved mode rather than hardcoding
                -- M0/M1/M2).
                RetM        : out std_logic;
                RstP        : out std_logic;
                LDZ         : out std_logic;
                LDW         : out std_logic;
                -- Phase11: latches the 3rd (bank) byte of a CALL.L addr24
                -- target into TmpBank (t80.vhd), mirroring LDZ/LDW's
                -- timing/mechanism but for the bank byte instead of the
                -- low/high address bytes.
                LDB         : out std_logic;
                LDSPHL      : out std_logic;
                Special_LD  : out std_logic_vector(2 downto 0); -- A,I;A,R;I,A;R,A;None
                ExchangeDH  : out std_logic;
                ExchangeRp  : out std_logic;
                ExchangeAF  : out std_logic;
                ExchangeRS  : out std_logic;
                I_DJNZ      : out std_logic;
                I_CPL       : out std_logic;
                I_CCF       : out std_logic;
                I_SCF       : out std_logic;
                I_RETN      : out std_logic;
                I_BT        : out std_logic;
                I_BC        : out std_logic;
                I_BTR       : out std_logic;
                I_RLD       : out std_logic;
                I_RRD       : out std_logic;
                I_INRC      : out std_logic;
                SetDI       : out std_logic;
                SetEI       : out std_logic;
                IMode       : out std_logic_vector(1 downto 0);
                Halt        : out std_logic;
                NoRead      : out std_logic;
                Write       : out std_logic;
                XYbit_undoc : out std_logic
        );
end T80_MCode;

architecture rtl of T80_MCode is

        constant aNone  : std_logic_vector(2 downto 0) := "111";
        constant aBC    : std_logic_vector(2 downto 0) := "000";
        constant aDE    : std_logic_vector(2 downto 0) := "001";
        constant aXY    : std_logic_vector(2 downto 0) := "010";
        constant aIOA   : std_logic_vector(2 downto 0) := "100";
        constant aSP    : std_logic_vector(2 downto 0) := "101";
        constant aZI    : std_logic_vector(2 downto 0) := "110";
        -- Phase9: MSP24 (PUSH24/POP24) address source. "011" was the only
        -- unused value among the 8 possible Set_Addr_To encodings, so it is
        -- reused here with no risk of colliding with aNone/aBC/aDE/aXY/
        -- aIOA/aSP/aZI above. See t80.vhd's matching aMSP case (in the
        -- Set_Addr_To interpretation block) for how this drives A/A_Bank.
        constant aMSP   : std_logic_vector(2 downto 0) := "011";

        function is_cc_true(
                F : std_logic_vector(7 downto 0);
                cc : bit_vector(2 downto 0)
                ) return boolean is
        begin
                if Mode = 3 then
                        case cc is
                        when "000" => return F(7) = '0'; -- NZ
                        when "001" => return F(7) = '1'; -- Z
                        when "010" => return F(4) = '0'; -- NC
                        when "011" => return F(4) = '1'; -- C
                        when "100" => return false;
                        when "101" => return false;
                        when "110" => return false;
                        when "111" => return false;
                        end case;
                else
                        case cc is
                        when "000" => return F(6) = '0'; -- NZ
                        when "001" => return F(6) = '1'; -- Z
                        when "010" => return F(0) = '0'; -- NC
                        when "011" => return F(0) = '1'; -- C
                        when "100" => return F(2) = '0'; -- PO
                        when "101" => return F(2) = '1'; -- PE
                        when "110" => return F(7) = '0'; -- P
                        when "111" => return F(7) = '1'; -- M
                        end case;
                end if;
        end;

        -- Phase11: JR.L e16 / JR.L cc,e16 condition test. ED 18/20/28/30/
        -- 38 reuse the EXACT same opcode bytes as plain JR e / JR NZ,Z,
        -- NC,C,e (real Z80's own 2bit cc encoding at IR(4:3), only 4
        -- conditions), while ED A7/AF/B7/BF (PO/PE/P/M - conditions that
        -- plain JR never had) happen to already fit the standard 3bit cc
        -- field at IR(5:3) used by JP/CALL/RET (is_cc_true above), purely
        -- by coincidence of which opcode bytes were free. This function
        -- just dispatches to whichever encoding applies.
        function is_jrl_cc_true(
                F : std_logic_vector(7 downto 0);
                IR : std_logic_vector(7 downto 0)
                ) return boolean is
        begin
                case IR is
                when "00100000" => return F(6) = '0'; -- NZ
                when "00101000" => return F(6) = '1'; -- Z
                when "00110000" => return F(0) = '0'; -- NC
                when "00111000" => return F(0) = '1'; -- C
                when others => return is_cc_true(F, to_bitvector(IR(5 downto 3))); -- PO/PE/P/M
                end case;
        end;

begin

        process (IR, ISet, MCycle, F, NMICycle, IntCycle, XY_State, LeaXY)
                variable DDD : std_logic_vector(2 downto 0);
                variable SSS : std_logic_vector(2 downto 0);
                variable DPair : std_logic_vector(1 downto 0);
                variable IRB : bit_vector(7 downto 0);
        begin
                DDD := IR(5 downto 3);
                SSS := IR(2 downto 0);
                DPair := IR(5 downto 4);
                IRB := to_bitvector(IR);

                MCycles <= "0001";
                if MCycle = "0001" then
                        TStates <= "100";
                else
                        TStates <= "011";
                end if;
                Prefix <= "00";
                Inc_PC <= '0';
                Inc_WZ <= '0';
                IncDec_16 <= "0000";
                Read_To_Acc <= '0';
                Read_To_Reg <= '0';
                Set_BusB_To <= "0000";
                Set_BusA_To <= "0000";
                ALU_Op <= "0" & IR(5 downto 3);
                ALU_cpi <= '0';
                Save_ALU <= '0';
                PreserveC <= '0';
                Arith16 <= '0';
                IORQ <= '0';
                Set_Addr_To <= aNone;
                Jump <= '0';
                JumpL <= '0';
                JumpR <= '0';
                JumpE <= '0';
                JumpEL <= '0';
                JumpXY <= '0';
                Call <= '0';
                CallL <= '0';
                RetL <= '0';
                JumpM01 <= '0';
                JumpM2 <= '0';
                CallM01 <= '0';
                CallM2 <= '0';
                RetM <= '0';
                RstP <= '0';
                LDZ <= '0';
                LDW <= '0';
                LDB <= '0';
                LDSPHL <= '0';
                Special_LD <= "000";
                ExchangeDH <= '0';
                ExchangeRp <= '0';
                ExchangeAF <= '0';
                ExchangeRS <= '0';
                I_DJNZ <= '0';
                I_CPL <= '0';
                I_CCF <= '0';
                I_SCF <= '0';
                I_RETN <= '0';
                I_BT <= '0';
                I_BC <= '0';
                I_BTR <= '0';
                I_RLD <= '0';
                I_RRD <= '0';
                I_INRC <= '0';
                SetDI <= '0';
                SetEI <= '0';
                IMode <= "11";
                Halt <= '0';
                NoRead <= '0';
                Write <= '0';
                XYbit_undoc <= '0';

                case ISet is
                when "00" =>

------------------------------------------------------------------------------
--
--      Unprefixed instructions
--
------------------------------------------------------------------------------

                case IRB is
-- 8 BIT LOAD GROUP
                when "01000000"|"01000001"|"01000010"|"01000011"|"01000100"|"01000101"|"01000111"
                        |"01001000"|"01001001"|"01001010"|"01001011"|"01001100"|"01001101"|"01001111"
                        |"01010000"|"01010001"|"01010010"|"01010011"|"01010100"|"01010101"|"01010111"
                        |"01011000"|"01011001"|"01011010"|"01011011"|"01011100"|"01011101"|"01011111"
                        |"01100000"|"01100001"|"01100010"|"01100011"|"01100100"|"01100101"|"01100111"
                        |"01101000"|"01101001"|"01101010"|"01101011"|"01101100"|"01101101"|"01101111"
                        |"01111000"|"01111001"|"01111010"|"01111011"|"01111100"|"01111101"|"01111111" =>
                        -- LD r,r'
                        Set_BusB_To(2 downto 0) <= SSS;
                        ExchangeRp <= '1';
                        Set_BusA_To(2 downto 0) <= DDD;
                        Read_To_Reg <= '1';
                when "00000110"|"00001110"|"00010110"|"00011110"|"00100110"|"00101110"|"00111110" =>
                        -- LD r,n
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                Inc_PC <= '1';
                                Set_BusA_To(2 downto 0) <= DDD;
                                Read_To_Reg <= '1';
                        when others => null;
                        end case;
                when "01000110"|"01001110"|"01010110"|"01011110"|"01100110"|"01101110"|"01111110" =>
                        -- LD r,(HL)
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aXY;
                        when 2 =>
                                Set_BusA_To(2 downto 0) <= DDD;
                                Read_To_Reg <= '1';
                        when others => null;
                        end case;
                when "01110000"|"01110001"|"01110010"|"01110011"|"01110100"|"01110101"|"01110111" =>
                        -- LD (HL),r
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aXY;
                                Set_BusB_To(2 downto 0) <= SSS;
                                Set_BusB_To(3) <= '0';
                        when 2 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "00110110" =>
                        -- LD (HL),n
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                Inc_PC <= '1';
                                Set_Addr_To <= aXY;
                                Set_BusB_To(2 downto 0) <= SSS;
                                Set_BusB_To(3) <= '0';
                        when 3 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "00001010" =>
                        -- LD A,(BC)
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aBC;
                        when 2 =>
                                Read_To_Acc <= '1';
                        when others => null;
                        end case;
                when "00011010" =>
                        -- LD A,(DE)
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aDE;
                        when 2 =>
                                Read_To_Acc <= '1';
                        when others => null;
                        end case;
                when "00111010" =>
                        if Mode = 3 then
                                -- LDD A,(HL)
                                MCycles <= "0010";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                when 2 =>
                                        Read_To_Acc <= '1';
                                        IncDec_16 <= "1110";
                                when others => null;
                                end case;
                        else
                                -- LD A,(nn)
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                when 4 =>
                                        Read_To_Acc <= '1';
                                when others => null;
                                end case;
                        end if;
                when "00000010" =>
                        -- LD (BC),A
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aBC;
                                Set_BusB_To <= "0111";
                        when 2 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "00010010" =>
                        -- LD (DE),A
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aDE;
                                Set_BusB_To <= "0111";
                        when 2 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "00110010" =>
                        if Mode = 3 then
                                -- LDD (HL),A
                                MCycles <= "0010";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                        Set_BusB_To <= "0111";
                                when 2 =>
                                        Write <= '1';
                                        IncDec_16 <= "1110";
                                when others => null;
                                end case;
                        else
                                -- LD (nn),A
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        Set_BusB_To <= "0111";
                                when 4 =>
                                        Write <= '1';
                                when others => null;
                                end case;
                        end if;

-- 16 BIT LOAD GROUP
                when "00000001"|"00010001"|"00100001"|"00110001" =>
                        -- LD dd,nn
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                Inc_PC <= '1';
                                Read_To_Reg <= '1';
                                if DPAIR = "11" then
                                        Set_BusA_To(3 downto 0) <= "1000";
                                else
                                        Set_BusA_To(2 downto 1) <= DPAIR;
                                        Set_BusA_To(0) <= '1';
                                end if;
                        when 3 =>
                                Inc_PC <= '1';
                                Read_To_Reg <= '1';
                                if DPAIR = "11" then
                                        Set_BusA_To(3 downto 0) <= "1001";
                                else
                                        Set_BusA_To(2 downto 1) <= DPAIR;
                                        Set_BusA_To(0) <= '0';
                                end if;
                        when others => null;
                        end case;
                when "00101010" =>
                        if Mode = 3 then
                                -- LDI A,(HL)
                                MCycles <= "0010";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                when 2 =>
                                        Read_To_Acc <= '1';
                                        IncDec_16 <= "0110";
                                when others => null;
                                end case;
                        else
                                -- LD HL,(nn)
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Set_BusA_To(2 downto 0) <= "101"; -- L
                                        Read_To_Reg <= '1';
                                        Inc_WZ <= '1';
                                        Set_Addr_To <= aZI;
                                when 5 =>
                                        Set_BusA_To(2 downto 0) <= "100"; -- H
                                        Read_To_Reg <= '1';
                                when others => null;
                                end case;
                        end if;
                when "00100010" =>
                        if Mode = 3 then
                                -- LDI (HL),A
                                MCycles <= "0010";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                        Set_BusB_To <= "0111";
                                when 2 =>
                                        Write <= '1';
                                        IncDec_16 <= "0110";
                                when others => null;
                                end case;
                        else
                                -- LD (nn),HL
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        Set_BusB_To <= "0101"; -- L
                                when 4 =>
                                        Inc_WZ <= '1';
                                        Set_Addr_To <= aZI;
                                        Write <= '1';
                                        Set_BusB_To <= "0100"; -- H
                                when 5 =>
                                        Write <= '1';
                                when others => null;
                                end case;
                        end if;
                when "11111001" =>
                        -- LD SP,HL
                        TStates <= "110";
                        LDSPHL <= '1';
                when "11000101"|"11010101"|"11100101"|"11110101" =>
                        -- PUSH qq
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                TStates <= "101";
                                IncDec_16 <= "1111";
                                Set_Addr_TO <= aSP;
                                if DPAIR = "11" then
                                        Set_BusB_To <= "0111";
                                else
                                        Set_BusB_To(2 downto 1) <= DPAIR;
                                        Set_BusB_To(0) <= '0';
                                        Set_BusB_To(3) <= '0';
                                end if;
                        when 2 =>
                                IncDec_16 <= "1111";
                                Set_Addr_To <= aSP;
                                if DPAIR = "11" then
                                        Set_BusB_To <= "1011";
                                else
                                        Set_BusB_To(2 downto 1) <= DPAIR;
                                        Set_BusB_To(0) <= '1';
                                        Set_BusB_To(3) <= '0';
                                end if;
                                Write <= '1';
                        when 3 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "11000001"|"11010001"|"11100001"|"11110001" =>
                        -- POP qq
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aSP;
                        when 2 =>
                                IncDec_16 <= "0111";
                                Set_Addr_To <= aSP;
                                Read_To_Reg <= '1';
                                if DPAIR = "11" then
                                        Set_BusA_To(3 downto 0) <= "1011";
                                else
                                        Set_BusA_To(2 downto 1) <= DPAIR;
                                        Set_BusA_To(0) <= '1';
                                end if;
                        when 3 =>
                                IncDec_16 <= "0111";
                                Read_To_Reg <= '1';
                                if DPAIR = "11" then
                                        Set_BusA_To(3 downto 0) <= "0111";
                                else
                                        Set_BusA_To(2 downto 1) <= DPAIR;
                                        Set_BusA_To(0) <= '0';
                                end if;
                        when others => null;
                        end case;

-- EXCHANGE, BLOCK TRANSFER AND SEARCH GROUP
                when "11101011" =>
                        if Mode /= 3 then
                                -- EX DE,HL
                                ExchangeDH <= '1';
                        end if;
                when "00001000" =>
                        if Mode = 3 then
                                -- LD (nn),SP
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        Set_BusB_To <= "1000";
                                when 4 =>
                                        Inc_WZ <= '1';
                                        Set_Addr_To <= aZI;
                                        Write <= '1';
                                        Set_BusB_To <= "1001";
                                when 5 =>
                                        Write <= '1';
                                when others => null;
                                end case;
                        elsif Mode < 2 then
                                -- EX AF,AF'
                                ExchangeAF <= '1';
                        end if;
                when "11011001" =>
                        if Mode = 3 then
                                -- RETI
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_TO <= aSP;
                                when 2 =>
                                        IncDec_16 <= "0111";
                                        Set_Addr_To <= aSP;
                                        LDZ <= '1';
                                when 3 =>
                                        Jump <= '1';
                                        IncDec_16 <= "0111";
                                        I_RETN <= '1';
                                        SetEI <= '1';
                                when others => null;
                                end case;
                        elsif Mode < 2 then
                                -- EXX
                                ExchangeRS <= '1';
                        end if;
                when "11100011" =>
                        if Mode /= 3 then
                                -- EX (SP),HL
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aSP;
                                when 2 =>
                                        Read_To_Reg <= '1';
                                        Set_BusA_To <= "0101";
                                        Set_BusB_To <= "0101";
                                        Set_Addr_To <= aSP;
                                when 3 =>
                                        IncDec_16 <= "0111";
                                        Set_Addr_To <= aSP;
                                        TStates <= "100";
                                        Write <= '1';
                                when 4 =>
                                        Read_To_Reg <= '1';
                                        Set_BusA_To <= "0100";
                                        Set_BusB_To <= "0100";
                                        Set_Addr_To <= aSP;
                                when 5 =>
                                        IncDec_16 <= "1111";
                                        TStates <= "101";
                                        Write <= '1';
                                when others => null;
                                end case;
                        end if;

-- 8 BIT ARITHMETIC AND LOGICAL GROUP
                when "10000000"|"10000001"|"10000010"|"10000011"|"10000100"|"10000101"|"10000111"
                        |"10001000"|"10001001"|"10001010"|"10001011"|"10001100"|"10001101"|"10001111"
                        |"10010000"|"10010001"|"10010010"|"10010011"|"10010100"|"10010101"|"10010111"
                        |"10011000"|"10011001"|"10011010"|"10011011"|"10011100"|"10011101"|"10011111"
                        |"10100000"|"10100001"|"10100010"|"10100011"|"10100100"|"10100101"|"10100111"
                        |"10101000"|"10101001"|"10101010"|"10101011"|"10101100"|"10101101"|"10101111"
                        |"10110000"|"10110001"|"10110010"|"10110011"|"10110100"|"10110101"|"10110111"
                        |"10111000"|"10111001"|"10111010"|"10111011"|"10111100"|"10111101"|"10111111" =>
                        -- ADD A,r
                        -- ADC A,r
                        -- SUB A,r
                        -- SBC A,r
                        -- AND A,r
                        -- OR A,r
                        -- XOR A,r
                        -- CP A,r
                        Set_BusB_To(2 downto 0) <= SSS;
                        Set_BusA_To(2 downto 0) <= "111";
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                when "10000110"|"10001110"|"10010110"|"10011110"|"10100110"|"10101110"|"10110110"|"10111110" =>
                        -- ADD A,(HL)
                        -- ADC A,(HL)
                        -- SUB A,(HL)
                        -- SBC A,(HL)
                        -- AND A,(HL)
                        -- OR A,(HL)
                        -- XOR A,(HL)
                        -- CP A,(HL)
                        MCycles <= "0010";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aXY;
                        when 2 =>
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                Set_BusB_To(2 downto 0) <= SSS;
                                Set_BusA_To(2 downto 0) <= "111";
                        when others => null;
                        end case;
                when "11000110"|"11001110"|"11010110"|"11011110"|"11100110"|"11101110"|"11110110"|"11111110" =>
                        -- ADD A,n
                        -- ADC A,n
                        -- SUB A,n
                        -- SBC A,n
                        -- AND A,n
                        -- OR A,n
                        -- XOR A,n
                        -- CP A,n
                        MCycles <= "0010";
                        if MCycle = "0010" then
                                Inc_PC <= '1';
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                Set_BusB_To(2 downto 0) <= SSS;
                                Set_BusA_To(2 downto 0) <= "111";
                        end if;
                when "00000100"|"00001100"|"00010100"|"00011100"|"00100100"|"00101100"|"00111100" =>
                        -- INC r
                        Set_BusB_To <= "1010";
                        Set_BusA_To(2 downto 0) <= DDD;
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                        PreserveC <= '1';
                        ALU_Op <= "0000";
                when "00110100" =>
                        -- INC (HL)
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aXY;
                        when 2 =>
                                TStates <= "100";
                                Set_Addr_To <= aXY;
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                PreserveC <= '1';
                                ALU_Op <= "0000";
                                Set_BusB_To <= "1010";
                                Set_BusA_To(2 downto 0) <= DDD;
                        when 3 =>
                                Write <= '1';
                        when others => null;
                        end case;
                when "00000101"|"00001101"|"00010101"|"00011101"|"00100101"|"00101101"|"00111101" =>
                        -- DEC r
                        Set_BusB_To <= "1010";
                        Set_BusA_To(2 downto 0) <= DDD;
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                        PreserveC <= '1';
                        ALU_Op <= "0010";
                when "00110101" =>
                        -- DEC (HL)
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                Set_Addr_To <= aXY;
                        when 2 =>
                                TStates <= "100";
                                Set_Addr_To <= aXY;
                                ALU_Op <= "0010";
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                PreserveC <= '1';
                                Set_BusB_To <= "1010";
                                Set_BusA_To(2 downto 0) <= DDD;
                        when 3 =>
                                Write <= '1';
                        when others => null;
                        end case;

-- GENERAL PURPOSE ARITHMETIC AND CPU CONTROL GROUPS
                when "00100111" =>
                        -- DAA
                        Set_BusA_To(2 downto 0) <= "111";
                        Read_To_Reg <= '1';
                        ALU_Op <= "1100";
                        Save_ALU <= '1';
                when "00101111" =>
                        -- CPL
                        I_CPL <= '1';
                when "00111111" =>
                        -- CCF
                        I_CCF <= '1';
                when "00110111" =>
                        -- SCF
                        I_SCF <= '1';
                when "00000000" =>
                        if NMICycle = '1' then
                                -- NMI
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        IncDec_16 <= "1111";
                                        Set_Addr_To <= aSP;
                                        Set_BusB_To <= "1101";
                                when 2 =>
                                        TStates <= "100";
                                        Write <= '1';
                                        IncDec_16 <= "1111";
                                        Set_Addr_To <= aSP;
                                        Set_BusB_To <= "1100";
                                when 3 =>
                                        TStates <= "100";
                                        Write <= '1';
                                when others => null;
                                end case;
                        elsif IntCycle = '1' then
                                -- INT (IM 2)
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        LDZ <= '1';
                                        TStates <= "101";
                                        IncDec_16 <= "1111";
                                        Set_Addr_To <= aSP;
                                        Set_BusB_To <= "1101";
                                when 2 =>
                                        TStates <= "100";
                                        Write <= '1';
                                        IncDec_16 <= "1111";
                                        Set_Addr_To <= aSP;
                                        Set_BusB_To <= "1100";
                                when 3 =>
                                        TStates <= "100";
                                        Write <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 5 =>
                                        Jump <= '1';
                                when others => null;
                                end case;
                        else
                                -- NOP
                        end if;
                when "01110110" =>
                        -- HALT
                        Halt <= '1';
                when "11110011" =>
                        -- DI
                        SetDI <= '1';
                when "11111011" =>
                        -- EI
                        SetEI <= '1';

-- 16 BIT ARITHMETIC GROUP
                when "00001001"|"00011001"|"00101001"|"00111001" =>
                        -- ADD HL,ss
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                NoRead <= '1';
                                ALU_Op <= "0000";
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                Set_BusA_To(2 downto 0) <= "101";
                                case to_integer(unsigned(IR(5 downto 4))) is
                                when 0|1|2 =>
                                        Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                        Set_BusB_To(0) <= '1';
                                when others =>
                                        Set_BusB_To <= "1000";
                                end case;
                                TStates <= "100";
                                Arith16 <= '1';
                        when 3 =>
                                NoRead <= '1';
                                Read_To_Reg <= '1';
                                Save_ALU <= '1';
                                ALU_Op <= "0001";
                                Set_BusA_To(2 downto 0) <= "100";
                                case to_integer(unsigned(IR(5 downto 4))) is
                                when 0|1|2 =>
                                        Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                when others =>
                                        Set_BusB_To <= "1001";
                                end case;
                                Arith16 <= '1';
                        when others =>
                        end case;
                when "00000011"|"00010011"|"00100011"|"00110011" =>
                        -- INC ss
                        TStates <= "110";
                        IncDec_16(3 downto 2) <= "01";
                        IncDec_16(1 downto 0) <= DPair;
                when "00001011"|"00011011"|"00101011"|"00111011" =>
                        -- DEC ss
                        TStates <= "110";
                        IncDec_16(3 downto 2) <= "11";
                        IncDec_16(1 downto 0) <= DPair;

-- ROTATE AND SHIFT GROUP
                when "00000111"
                        -- RLCA
                        |"00010111"
                        -- RLA
                        |"00001111"
                        -- RRCA
                        |"00011111" =>
                        -- RRA
                        Set_BusA_To(2 downto 0) <= "111";
                        ALU_Op <= "1000";
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';

-- JUMP GROUP
                when "11000011" =>
                        -- JP nn
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                Inc_PC <= '1';
                                LDZ <= '1';
                        when 3 =>
                                Inc_PC <= '1';
                                Jump <= '1';
                        when others => null;
                        end case;
                when "11000010"|"11001010"|"11010010"|"11011010"|"11100010"|"11101010"|"11110010"|"11111010" =>
                        if IR(5) = '1' and Mode = 3 then
                                case IRB(4 downto 3) is
                                when "00" =>
                                        -- LD ($FF00+C),A
                                        MCycles <= "0010";
                                        case to_integer(unsigned(MCycle)) is
                                        when 1 =>
                                                Set_Addr_To <= aBC;
                                                Set_BusB_To     <= "0111";
                                        when 2 =>
                                                Write <= '1';
                                                IORQ <= '1';
                                        when others =>
                                        end case;
                                when "01" =>
                                        -- LD (nn),A
                                        MCycles <= "0100";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                                LDZ <= '1';
                                        when 3 =>
                                                Set_Addr_To <= aZI;
                                                Inc_PC <= '1';
                                                Set_BusB_To <= "0111";
                                        when 4 =>
                                                Write <= '1';
                                        when others => null;
                                        end case;
                                when "10" =>
                                        -- LD A,($FF00+C)
                                        MCycles <= "0010";
                                        case to_integer(unsigned(MCycle)) is
                                        when 1 =>
                                                Set_Addr_To <= aBC;
                                        when 2 =>
                                                Read_To_Acc <= '1';
                                                IORQ <= '1';
                                        when others =>
                                        end case;
                                when "11" =>
                                        -- LD A,(nn)
                                        MCycles <= "0100";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                                LDZ <= '1';
                                        when 3 =>
                                                Set_Addr_To <= aZI;
                                                Inc_PC <= '1';
                                        when 4 =>
                                                Read_To_Acc <= '1';
                                        when others => null;
                                        end case;
                                end case;
                        else
                                -- JP cc,nn
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                Jump <= '1';
                                        end if;
                                when others => null;
                                end case;
                        end if;
                when "00011000" =>
                        if Mode /= 2 then
                                -- JR e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;
                when "00111000" =>
                        if Mode /= 2 then
                                -- JR C,e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        if F(Flag_C) = '0' then
                                                MCycles <= "0010";
                                        end if;
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;
                when "00110000" =>
                        if Mode /= 2 then
                                -- JR NC,e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        if F(Flag_C) = '1' then
                                                MCycles <= "0010";
                                        end if;
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;
                when "00101000" =>
                        if Mode /= 2 then
                                -- JR Z,e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        if F(Flag_Z) = '0' then
                                                MCycles <= "0010";
                                        end if;
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;
                when "00100000" =>
                        if Mode /= 2 then
                                -- JR NZ,e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        if F(Flag_Z) = '1' then
                                                MCycles <= "0010";
                                        end if;
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;
                when "11101001" =>
                        -- JP (HL)
                        JumpXY <= '1';
                when "00010000" =>
                        if Mode = 3 then
                                I_DJNZ <= '1';
                        elsif Mode < 2 then
                                -- DJNZ,e
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        I_DJNZ <= '1';
                                        Set_BusB_To <= "1010";
                                        Set_BusA_To(2 downto 0) <= "000";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        ALU_Op <= "0010";
                                when 2 =>
                                        I_DJNZ <= '1';
                                        Inc_PC <= '1';
                                when 3 =>
                                        NoRead <= '1';
                                        JumpE <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        end if;

-- CALL AND RETURN GROUP
                when "11001101" =>
                        -- CALL nn
                        MCycles <= "0101";
                        case to_integer(unsigned(MCycle)) is
                        when 2 =>
                                Inc_PC <= '1';
                                LDZ <= '1';
                        when 3 =>
                                IncDec_16 <= "1111";
                                Inc_PC <= '1';
                                TStates <= "100";
                                Set_Addr_To <= aSP;
                                LDW <= '1';
                                Set_BusB_To <= "1101";
                        when 4 =>
                                Write <= '1';
                                IncDec_16 <= "1111";
                                Set_Addr_To <= aSP;
                                Set_BusB_To <= "1100";
                        when 5 =>
                                Write <= '1';
                                Call <= '1';
                        when others => null;
                        end case;
                when "11000100"|"11001100"|"11010100"|"11011100"|"11100100"|"11101100"|"11110100"|"11111100" =>
                        if IR(5) = '0' or Mode /= 3 then
                                -- CALL cc,nn
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                IncDec_16 <= "1111";
                                                Set_Addr_TO <= aSP;
                                                TStates <= "100";
                                                Set_BusB_To <= "1101";
                                        else
                                                MCycles <= "0011";
                                        end if;
                                when 4 =>
                                        Write <= '1';
                                        IncDec_16 <= "1111";
                                        Set_Addr_To <= aSP;
                                        Set_BusB_To <= "1100";
                                when 5 =>
                                        Write <= '1';
                                        Call <= '1';
                                when others => null;
                                end case;
                        end if;
                when "11001001" =>
                        -- RET
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                TStates <= "101";
                                Set_Addr_TO <= aSP;
                        when 2 =>
                                IncDec_16 <= "0111";
                                Set_Addr_To <= aSP;
                                LDZ <= '1';
                        when 3 =>
                                -- Phase11: JumpR (not Jump) preserves
                                -- bank_pc_r instead of resetting it to
                                -- 00h - see the JumpR entity-port comment
                                -- and t80.vhd's matching T_Res branch.
                                JumpR <= '1';
                                IncDec_16 <= "0111";
                        when others => null;
                        end case;
                when "11000000"|"11001000"|"11010000"|"11011000"|"11100000"|"11101000"|"11110000"|"11111000" =>
                        if IR(5) = '1' and Mode = 3 then
                                case IRB(4 downto 3) is
                                when "00" =>
                                        -- LD ($FF00+nn),A
                                        MCycles <= "0011";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                                Set_Addr_To <= aIOA;
                                                Set_BusB_To     <= "0111";
                                        when 3 =>
                                                Write <= '1';
                                        when others => null;
                                        end case;
                                when "01" =>
                                        -- ADD SP,n
                                        MCycles <= "0011";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                ALU_Op <= "0000";
                                                Inc_PC <= '1';
                                                Read_To_Reg <= '1';
                                                Save_ALU <= '1';
                                                Set_BusA_To <= "1000";
                                                Set_BusB_To <= "0110";
                                        when 3 =>
                                                NoRead <= '1';
                                                Read_To_Reg <= '1';
                                                Save_ALU <= '1';
                                                ALU_Op <= "0001";
                                                Set_BusA_To <= "1001";
                                                Set_BusB_To <= "1110";  -- Incorrect unsigned !!!!!!!!!!!!!!!!!!!!!
                                        when others =>
                                        end case;
                                when "10" =>
                                        -- LD A,($FF00+nn)
                                        MCycles <= "0011";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                                Set_Addr_To <= aIOA;
                                        when 3 =>
                                                Read_To_Acc <= '1';
                                        when others => null;
                                        end case;
                                when "11" =>
                                        -- LD HL,SP+n   -- Not correct !!!!!!!!!!!!!!!!!!!
                                        MCycles <= "0101";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                                LDZ <= '1';
                                        when 3 =>
                                                Set_Addr_To <= aZI;
                                                Inc_PC <= '1';
                                                LDW <= '1';
                                        when 4 =>
                                                Set_BusA_To(2 downto 0) <= "101"; -- L
                                                Read_To_Reg <= '1';
                                                Inc_WZ <= '1';
                                                Set_Addr_To <= aZI;
                                        when 5 =>
                                                Set_BusA_To(2 downto 0) <= "100"; -- H
                                                Read_To_Reg <= '1';
                                        when others => null;
                                        end case;
                                end case;
                        else
                                -- RET cc
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                Set_Addr_TO <= aSP;
                                        else
                                                MCycles <= "0001";
                                        end if;
                                        TStates <= "101";
                                when 2 =>
                                        IncDec_16 <= "0111";
                                        Set_Addr_To <= aSP;
                                        LDZ <= '1';
                                when 3 =>
                                        -- Phase11: see JumpR comment on
                                        -- plain RET above.
                                        JumpR <= '1';
                                        IncDec_16 <= "0111";
                                when others => null;
                                end case;
                        end if;
                when "11000111"|"11001111"|"11010111"|"11011111"|"11100111"|"11101111"|"11110111"|"11111111" =>
                        -- RST p
                        MCycles <= "0011";
                        case to_integer(unsigned(MCycle)) is
                        when 1 =>
                                TStates <= "101";
                                IncDec_16 <= "1111";
                                Set_Addr_To <= aSP;
                                Set_BusB_To <= "1101";
                        when 2 =>
                                Write <= '1';
                                IncDec_16 <= "1111";
                                Set_Addr_To <= aSP;
                                Set_BusB_To <= "1100";
                        when 3 =>
                                Write <= '1';
                                RstP <= '1';
                        when others => null;
                        end case;

-- INPUT AND OUTPUT GROUP
                when "11011011" =>
                        if Mode /= 3 then
                                -- IN A,(n)
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        Set_Addr_To <= aIOA;
                                when 3 =>
                                        Read_To_Acc <= '1';
                                        IORQ <= '1';
                                when others => null;
                                end case;
                        end if;
                when "11010011" =>
                        if Mode /= 3 then
                                -- OUT (n),A
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        Set_Addr_To <= aIOA;
                                        Set_BusB_To     <= "0111";
                                when 3 =>
                                        Write <= '1';
                                        IORQ <= '1';
                                when others => null;
                                end case;
                        end if;

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- MULTIBYTE INSTRUCTIONS
------------------------------------------------------------------------------
------------------------------------------------------------------------------

                when "11001011" =>
                        if Mode /= 2 then
                                Prefix <= "01";
                        end if;

                when "11101101" =>
                        if Mode < 2 then
                                Prefix <= "10";
                        end if;

                when "11011101"|"11111101" =>
                        if Mode < 2 then
                                Prefix <= "11";
                        end if;

                end case;

                when "01" =>

------------------------------------------------------------------------------
--
--      CB prefixed instructions
--
------------------------------------------------------------------------------

            Set_BusA_To(2 downto 0) <= IR(2 downto 0);
            Set_BusB_To(2 downto 0) <= IR(2 downto 0);

            case IRB is
            when "00000000"|"00000001"|"00000010"|"00000011"|"00000100"|"00000101"|"00000111"
                |"00010000"|"00010001"|"00010010"|"00010011"|"00010100"|"00010101"|"00010111"
                |"00001000"|"00001001"|"00001010"|"00001011"|"00001100"|"00001101"|"00001111"
                |"00011000"|"00011001"|"00011010"|"00011011"|"00011100"|"00011101"|"00011111"
                |"00100000"|"00100001"|"00100010"|"00100011"|"00100100"|"00100101"|"00100111"
                |"00101000"|"00101001"|"00101010"|"00101011"|"00101100"|"00101101"|"00101111"
                |"00110000"|"00110001"|"00110010"|"00110011"|"00110100"|"00110101"|"00110111"
                |"00111000"|"00111001"|"00111010"|"00111011"|"00111100"|"00111101"|"00111111" =>
                -- RLC r
                -- RL r
                -- RRC r
                -- RR r
                -- SLA r
                -- SRA r
                -- SRL r
                -- SLL r (Undocumented) / SWAP r
                if XY_State="00" then
                    if MCycle = "0001" then
                      ALU_Op <= "1000";
                      Read_To_Reg <= '1';
                      Save_ALU <= '1';
                    end if;
                else
                -- R/S (IX+d),Reg, undocumented
                    MCycles <= "0011";
                    XYbit_undoc <= '1';
                    case to_integer(unsigned(MCycle)) is
                    when 1 | 7=>
                        Set_Addr_To <= aXY;
                    when 2 =>
                        ALU_Op <= "1000";
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                        Set_Addr_To <= aXY;
                        TStates <= "100";
                    when 3 =>
                        Write <= '1';
                    when others => null;
                    end case;
                end if;


            when "00000110"|"00010110"|"00001110"|"00011110"|"00101110"|"00111110"|"00100110"|"00110110" =>
                -- RLC (HL)
                -- RL (HL)
                -- RRC (HL)
                -- RR (HL)
                -- SRA (HL)
                -- SRL (HL)
                -- SLA (HL)
                -- SLL (HL) (Undocumented) / SWAP (HL)
                MCycles <= "0011";
                case to_integer(unsigned(MCycle)) is
                when 1 | 7 =>
                    Set_Addr_To <= aXY;
                when 2 =>
                    ALU_Op <= "1000";
                    Read_To_Reg <= '1';
                    Save_ALU <= '1';
                    Set_Addr_To <= aXY;
                    TStates <= "100";
                when 3 =>
                    Write <= '1';
                when others =>
                end case;
            when "01000000"|"01000001"|"01000010"|"01000011"|"01000100"|"01000101"|"01000111"
                |"01001000"|"01001001"|"01001010"|"01001011"|"01001100"|"01001101"|"01001111"
                |"01010000"|"01010001"|"01010010"|"01010011"|"01010100"|"01010101"|"01010111"
                |"01011000"|"01011001"|"01011010"|"01011011"|"01011100"|"01011101"|"01011111"
                |"01100000"|"01100001"|"01100010"|"01100011"|"01100100"|"01100101"|"01100111"
                |"01101000"|"01101001"|"01101010"|"01101011"|"01101100"|"01101101"|"01101111"
                |"01110000"|"01110001"|"01110010"|"01110011"|"01110100"|"01110101"|"01110111"
                |"01111000"|"01111001"|"01111010"|"01111011"|"01111100"|"01111101"|"01111111" =>
                -- BIT b,r
                if XY_State="00" then
                    if MCycle = "0001" then
                      Set_BusB_To(2 downto 0) <= IR(2 downto 0);
                      ALU_Op <= "1001";
                    end if;
                else
                -- BIT b,(IX+d), undocumented
                    MCycles <= "0010";
                    XYbit_undoc <= '1';
                    case to_integer(unsigned(MCycle)) is
                    when 1 | 7=>
                        Set_Addr_To <= aXY;
                    when 2 =>
                        ALU_Op <= "1001";
                        TStates <= "100";
                    when others => null;
                    end case;
                end if;
            when "01000110"|"01001110"|"01010110"|"01011110"|"01100110"|"01101110"|"01110110"|"01111110" =>
                -- BIT b,(HL)
                MCycles <= "0010";
                case to_integer(unsigned(MCycle)) is
                when 1 | 7=>
                    Set_Addr_To <= aXY;
                when 2 =>
                    ALU_Op <= "1001";
                    TStates <= "100";
                when others => null;
                end case;
            when "11000000"|"11000001"|"11000010"|"11000011"|"11000100"|"11000101"|"11000111"
                |"11001000"|"11001001"|"11001010"|"11001011"|"11001100"|"11001101"|"11001111"
                |"11010000"|"11010001"|"11010010"|"11010011"|"11010100"|"11010101"|"11010111"
                |"11011000"|"11011001"|"11011010"|"11011011"|"11011100"|"11011101"|"11011111"
                |"11100000"|"11100001"|"11100010"|"11100011"|"11100100"|"11100101"|"11100111"
                |"11101000"|"11101001"|"11101010"|"11101011"|"11101100"|"11101101"|"11101111"
                |"11110000"|"11110001"|"11110010"|"11110011"|"11110100"|"11110101"|"11110111"
                |"11111000"|"11111001"|"11111010"|"11111011"|"11111100"|"11111101"|"11111111" =>
                -- SET b,r
                if XY_State="00" then
                    if MCycle = "0001" then
                      ALU_Op <= "1010";
                      Read_To_Reg <= '1';
                      Save_ALU <= '1';
                    end if;
                else
                -- SET b,(IX+d),Reg, undocumented
                    MCycles <= "0011";
                    XYbit_undoc <= '1';
                    case to_integer(unsigned(MCycle)) is
                    when 1 | 7=>
                        Set_Addr_To <= aXY;
                    when 2 =>
                        ALU_Op <= "1010";
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                        Set_Addr_To <= aXY;
                        TStates <= "100";
                    when 3 =>
                        Write <= '1';
                    when others => null;
                    end case;
                end if;
            when "11000110"|"11001110"|"11010110"|"11011110"|"11100110"|"11101110"|"11110110"|"11111110" =>
                -- SET b,(HL)
                MCycles <= "0011";
                case to_integer(unsigned(MCycle)) is
                when 1 | 7=>
                    Set_Addr_To <= aXY;
                when 2 =>
                    ALU_Op <= "1010";
                    Read_To_Reg <= '1';
                    Save_ALU <= '1';
                    Set_Addr_To <= aXY;
                    TStates <= "100";
                when 3 =>
                    Write <= '1';
                when others => null;
                end case;
            when "10000000"|"10000001"|"10000010"|"10000011"|"10000100"|"10000101"|"10000111"
                |"10001000"|"10001001"|"10001010"|"10001011"|"10001100"|"10001101"|"10001111"
                |"10010000"|"10010001"|"10010010"|"10010011"|"10010100"|"10010101"|"10010111"
                |"10011000"|"10011001"|"10011010"|"10011011"|"10011100"|"10011101"|"10011111"
                |"10100000"|"10100001"|"10100010"|"10100011"|"10100100"|"10100101"|"10100111"
                |"10101000"|"10101001"|"10101010"|"10101011"|"10101100"|"10101101"|"10101111"
                |"10110000"|"10110001"|"10110010"|"10110011"|"10110100"|"10110101"|"10110111"
                |"10111000"|"10111001"|"10111010"|"10111011"|"10111100"|"10111101"|"10111111" =>
                -- RES b,r
                if XY_State="00" then
                    if MCycle = "0001" then
                      ALU_Op <= "1011";
                      Read_To_Reg <= '1';
                      Save_ALU <= '1';
                    end if;
                else
                -- RES b,(IX+d),Reg, undocumented
                    MCycles <= "0011";
                    XYbit_undoc <= '1';
                    case to_integer(unsigned(MCycle)) is
                    when 1 | 7=>
                        Set_Addr_To <= aXY;
                    when 2 =>
                        ALU_Op <= "1011";
                        Read_To_Reg <= '1';
                        Save_ALU <= '1';
                        Set_Addr_To <= aXY;
                        TStates <= "100";
                    when 3 =>
                        Write <= '1';
                    when others => null;
                    end case;
                end if;

            when "10000110"|"10001110"|"10010110"|"10011110"|"10100110"|"10101110"|"10110110"|"10111110" =>
                -- RES b,(HL)
                MCycles <= "0011";
                case to_integer(unsigned(MCycle)) is
                when 1 | 7 =>
                    Set_Addr_To <= aXY;
                when 2 =>
                    ALU_Op <= "1011";
                    Read_To_Reg <= '1';
                    Save_ALU <= '1';
                    Set_Addr_To <= aXY;
                    TStates <= "100";
                when 3 =>
                    Write <= '1';
                when others => null;
                end case;
            end case;

        when others =>

------------------------------------------------------------------------------
--
--      ED prefixed instructions
--
------------------------------------------------------------------------------

                        case IRB is
                        when "00000000"|"00000001"|"00000010"|"00000011"|"00000100"|"00000101"|"00000110"|"00000111"
                                |"00001000"|"00001001"|"00001010"|"00001011"|"00001100"|"00001101"|"00001110"|"00001111"
                                |"00010000"|"00010001"|"00010010"|"00010011"|"00010100"|"00010101"|"00010110"|"00010111"
                                |            "00011001"|"00011010"|"00011011"|"00011100"|"00011101"|"00011110"|"00011111"
                                |            "00100001"|"00100010"|"00100011"|"00100100"|"00100101"|"00100110"|"00100111"
                                |            "00101001"|"00101010"|"00101011"|"00101100"|"00101101"|"00101110"|"00101111"
                                |            "00110001"|"00110010"|"00110011"|"00110100"|"00110101"|"00110110"|"00110111"
                                |            "00111001"|"00111010"|"00111011"|"00111100"|"00111101"|"00111110"|"00111111"


                                |"10000000"|"10000001"|"10000010"|"10000011"|"10000100"|"10000101"|"10000110"|"10000111"
                                |"10001000"|"10001001"|"10001010"|"10001011"|"10001100"|"10001101"|"10001110"|"10001111"
                                |"10010000"|"10010001"|"10010010"
                                |"10011010"|"10011011"|"10011100"|"10011101"|"10011110"|"10011111"
                                |                                            "10100100"|"10100101"|"10100110"
                                |                                            "10101100"|"10101101"|"10101110"
                                |                                            "10110100"|"10110101"|"10110110"
                                |                                            "10111100"|"10111101"|"10111110"
                                |"11000110"|"11000111"
                                |"11001011"|"11001110"|"11001111"
                                |"11010011"|"11010110"|"11010111"
                                |"11011011"|"11011101"|"11011110"|"11011111"
                                |"11100011"|"11100110"|"11100111"
                                |"11101001"|"11101011"|"11101101"|"11101110"|"11101111"
                                |"11110001"|"11110101"|"11110110"|"11110111"
                                |"11111001"|"11111011"|"11111101"|"11111110"|"11111111" =>
                                null; -- NOP, undocumented
                        when "10010011" =>
                                -- Phase12: JP.M0 addr16 (ED 93). Mode-
                                -- switching jump: identical 3cycle fetch/
                                -- trigger shape to plain 'JP nn' (M2=low
                                -- byte+LDZ, M3=high byte - DI_Reg used
                                -- directly, no LDW needed since there is
                                -- no 3rd byte - +JumpM01). t80.vhd's
                                -- JumpM01 branch checks IR to decide M0 vs
                                -- M1 and always resets bank_pc_r to 00h
                                -- (addr16 target = bank00h, CPU仕様書V8's
                                -- general rule).
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        JumpM01 <= '1';
                                when others => null;
                                end case;
                        when "10010100" =>
                                -- Phase12: JP.M1 addr16 (ED 94). Same
                                -- shape as JP.M0 above; see the JumpM01
                                -- comment there and its t80.vhd branch for
                                -- how M0 vs M1 is distinguished (via IR).
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        JumpM01 <= '1';
                                when others => null;
                                end case;
                        when "10010101" =>
                                -- Phase12: JP.M2 addr24 (ED 95). Same
                                -- 3byte fetch shape as JP.L (M2=low+LDZ,
                                -- M3=high+LDW, M4=bank+JumpM2). Unlike
                                -- JP.L, JumpM2 ALWAYS switches mode24_r to
                                -- M2 and ALWAYS applies the fetched bank
                                -- byte (CPU仕様書V8 roadmap Phase12
                                -- "モード間制御" - this is an explicit
                                -- mode-switching jump, not a same-mode
                                -- far jump).
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        JumpM2 <= '1';
                                when others => null;
                                end case;
                        when "10010110" =>
                                -- Phase12: CALL.M0 addr16 (ED 96). Same
                                -- 2byte fetch shape as plain 'CALL nn'
                                -- (M2=low+LDZ, M3=high+LDW, overlapping
                                -- M3 with the first MSP24 decrement
                                -- exactly like Phase11's CALL.L does one
                                -- mcycle later for its 3byte fetch), then
                                -- pushes a 4byte return frame (MODE/PC_B/
                                -- PC_H/PC_L, same decrement-before-write
                                -- pattern as CALL.L with MODE prepended)
                                -- at M4/M5/M6/M7. t80.vhd's CallM01 branch
                                -- checks IR to decide M0 vs M1 and resets
                                -- bank_pc_r to 00h (addr16 target).
                                MCycles <= "0111";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        TStates <= "100";
                                        Set_Addr_To <= aMSP;
                                when 4 =>
                                        Set_Addr_To <= aMSP;
                                        Write <= '1';
                                when 5 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1101";
                                        Write <= '1';
                                when 6 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1100";
                                        Write <= '1';
                                when 7 =>
                                        Write <= '1';
                                        CallM01 <= '1';
                                when others => null;
                                end case;
                        when "10010111" =>
                                -- Phase12: CALL.M1 addr16 (ED 97). Same
                                -- shape as CALL.M0 above; see the
                                -- CallM01 comment there.
                                MCycles <= "0111";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        TStates <= "100";
                                        Set_Addr_To <= aMSP;
                                when 4 =>
                                        Set_Addr_To <= aMSP;
                                        Write <= '1';
                                when 5 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1101";
                                        Write <= '1';
                                when 6 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1100";
                                        Write <= '1';
                                when 7 =>
                                        Write <= '1';
                                        CallM01 <= '1';
                                when others => null;
                                end case;
                        when "10011000" =>
                                -- Phase12: CALL.M2 addr24 (ED 98). Same
                                -- 3byte fetch shape as CALL.L (M2=low+LDZ,
                                -- M3=high+LDW, M4=bank+LDB), then pushes
                                -- the SAME 4byte return frame as CALL.M0/
                                -- M1 above (MODE/PC_B/PC_H/PC_L), shifted
                                -- one mcycle later throughout (M5-M8
                                -- instead of M4-M7) since there is one
                                -- extra fetch byte. M4 kicks off the
                                -- first MSP24 decrement one cycle early
                                -- (TStates<=100, Set_Addr_To<=aMSP)
                                -- exactly like CALL.L's own M4, readying
                                -- M5's write address. Needs 8 total
                                -- MCycles - only representable now that
                                -- MCycle is 4bit wide (see the MCycle-
                                -- width report referenced from
                                -- AVAILABLE_INSTRUCTIONS.md section 10.2).
                                MCycles <= "1000";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        LDB <= '1';
                                        TStates <= "100";
                                        Set_Addr_To <= aMSP;
                                when 5 =>
                                        Set_Addr_To <= aMSP;
                                        Write <= '1';
                                when 6 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1101";
                                        Write <= '1';
                                when 7 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1100";
                                        Write <= '1';
                                when 8 =>
                                        Write <= '1';
                                        CallM2 <= '1';
                                when others => null;
                                end case;
                        when "10011001" =>
                                -- Phase12: RET.M (ED 99). Pops the
                                -- matching 4byte frame (LOW/HIGH/BANK/
                                -- MODE, same increment-after-read pattern
                                -- as Phase11's RET.L with MODE appended -
                                -- M1 mirrors RET.L's own (TStates<=101,
                                -- Set_Addr_To<=aMSP) shape) from MSP24 and
                                -- restores BOTH PC24 and mode24_r from
                                -- the popped MODE byte - the only one of
                                -- these Phase12 opcodes that restores a
                                -- previously-saved mode rather than
                                -- hardcoding M0/M1/M2.
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        Set_Addr_To <= aMSP;
                                when 2 =>
                                        Set_Addr_To <= aMSP;
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aMSP;
                                        LDW <= '1';
                                when 4 =>
                                        Set_Addr_To <= aMSP;
                                        LDB <= '1';
                                when 5 =>
                                        RetM <= '1';
                                when others => null;
                                end case;
                        when "00011000" =>
                                -- Phase11: JR.L e16 (ED 18). Unconditional
                                -- PC24-relative jump with a 16bit (not
                                -- plain JR's 8bit) signed displacement
                                -- (CPU仕様書V8/roadmap Phase11 "JR.LはM2では
                                -- PC24全体にsigned 16bit displacementを
                                -- 加算しbank境界を跨ぐ"). Reuses the exact
                                -- same opcode byte as plain 'JR e' (0x18),
                                -- just ED-prefixed. M2=low byte+LDZ,
                                -- M3=high byte+LDW (both latched into
                                -- TmpAddr, unlike plain JR which uses
                                -- DI_Reg directly since it only has 1
                                -- byte), M4=NoRead+JumpEL (the actual
                                -- PC24+displacement add, done in t80.vhd's
                                -- T_Res block - mode-dependent: plain
                                -- 16bit wrap in M0/M1, true 24bit
                                -- bank-carrying add in M2).
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        NoRead <= '1';
                                        JumpEL <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "00100000"|"00101000"|"00110000"|"00111000"
                                |"10100111"|"10101111"|"10110111"|"10111111" =>
                                -- Phase11: JR.L cc,e16 (ED 20/28/30/38 =
                                -- NZ/Z/NC/C, reusing plain JR cc's own
                                -- opcode bytes; ED A7/AF/B7/BF = PO/PE/P/M,
                                -- conditions plain JR never had - see
                                -- is_jrl_cc_true above for why these 2
                                -- different encodings can share one case
                                -- arm). Same operand shape as JR.L above;
                                -- condition test at M3 (the last fetch
                                -- cycle, mirroring JP.L cc/CALL.L cc's own
                                -- pattern) either proceeds to M4's add
                                -- (condition true) or shrinks MCycles to
                                -- abort right after the fetch (condition
                                -- false - both displacement bytes are
                                -- still consumed, matching real Z80 JR
                                -- cc,e's variable-length timing, just
                                -- generalized to 2 operand bytes).
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        if not is_jrl_cc_true(F, IR) then
                                                MCycles <= "0011";
                                        end if;
                                when 4 =>
                                        NoRead <= '1';
                                        JumpEL <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "11000011" =>
                                -- Phase11: JP.L addr24 (ED C3). M2-only
                                -- unconditional 24bit far jump (MSX_T80_
                                -- 24bit化_実装手順_V2_2026-10-05.md section
                                -- 14 "Phase 12"寄りの命令だが、スタックを
                                -- 使わない単純なジャンプなのでAVAILABLE_
                                -- INSTRUCTIONS.md 9章の並びに合わせてPhase11
                                -- の一部として先行実装。CPU仕様書V8 section
                                -- 5). Reads a 3byte little-endian 24bit
                                -- address (low/high/bank); same MCycle
                                -- shape as plain 'JP nn' (M2=low byte+LDZ,
                                -- M3=high byte - LDW is used here (unlike
                                -- plain JP nn) because one more byte
                                -- follows and TmpAddr must hold it past
                                -- M3 - M4=bank byte+JumpL). This opcode
                                -- slot was previously the unreachable
                                -- "R800 MULUW" placeholder (Mode is always
                                -- 0=Z80 in this project, so R800 opcodes
                                -- were dead code); ED F3 keeps the MULUW
                                -- placeholder. The actual PC/A/bank_pc_r
                                -- assignment for JumpL is in t80.vhd's
                                -- T_Res block, mirroring 'Jump' but loading
                                -- the bank byte from DI_Reg instead of
                                -- resetting to 00h.
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        JumpL <= '1';
                                when others => null;
                                end case;
                        when "11000010"|"11001010"|"11010010"|"11011010"|"11100010"|"11101010"|"11110010"|"11111010" =>
                                -- Phase11: JP.L cc,addr24 (ED C2/CA/D2/DA/
                                -- E2/EA/F2/FA). Same 3byte operand shape as
                                -- JP.L above; condition test mirrors plain
                                -- 'JP cc,nn' (IR(5:3) selects cc via
                                -- is_cc_true). Operand bytes are always
                                -- consumed regardless of the condition
                                -- result, matching real Z80 JP cc,nn timing.
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                JumpL <= '1';
                                        end if;
                                when others => null;
                                end case;
                        when "11001101" =>
                                -- Phase11: CALL.L addr24 (ED CD). M2 24bit
                                -- far call (CPU仕様書V8/roadmap Phase11
                                -- "CALL.L/RET.LはM2専用24bit far call").
                                -- Reads the same 3byte little-endian target
                                -- as JP.L (M2=low+LDZ, M3=high+LDW, M4=bank
                                -- +LDB - a NEW latch into TmpBank since,
                                -- unlike JP.L, the bank byte must survive 3
                                -- more cycles while the return frame is
                                -- pushed), then pushes a 3byte PC24 return
                                -- frame (bank_pc_r/PC_H/PC_L, same write
                                -- order/MSP24-decrement-before-each-write
                                -- pattern as Phase9's PUSH24 - see the
                                -- matching t80.vhd direct IR-match block)
                                -- to MSP24. M4 kicks off the first
                                -- decrement one cycle early (TStates<=100,
                                -- Set_Addr_To<=aMSP) exactly like PUSH24's
                                -- own extended MCycle=1, since Set_Addr_To
                                -- set during cycle N determines the
                                -- address bus for cycle N+1 (see t80.vhd
                                -- comment on the aMSP case). Set_BusB_To
                                -- "1101"/"1100" (PC high/low) are the exact
                                -- same encodings plain 'CALL nn' already
                                -- uses to push its own return address.
                                MCycles <= "0111";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        LDB <= '1';
                                        TStates <= "100";
                                        Set_Addr_To <= aMSP;
                                when 5 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1101";
                                        Write <= '1';
                                when 6 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1100";
                                        Write <= '1';
                                when 7 =>
                                        Write <= '1';
                                        CallL <= '1';
                                when others => null;
                                end case;
                        when "11000100"|"11001100"|"11010100"|"11011100"|"11100100"|"11101100"|"11110100"|"11111100" =>
                                -- Phase11: CALL.L cc,addr24 (ED C4/CC/D4/
                                -- DC/E4/EC/F4/FC). Same operand/push shape
                                -- as CALL.L above; condition test (at M4,
                                -- the last fetch cycle, mirroring plain
                                -- 'CALL cc,nn' testing at its own last
                                -- fetch cycle) either kicks off the push
                                -- phase (condition true) or shrinks
                                -- MCycles to abort right after the fetch
                                -- (condition false - all 3 operand bytes
                                -- are still consumed, matching real Z80
                                -- CALL cc,nn's variable-length timing).
                                MCycles <= "0111";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Inc_PC <= '1';
                                        LDB <= '1';
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                TStates <= "100";
                                                Set_Addr_To <= aMSP;
                                        else
                                                MCycles <= "0100";
                                        end if;
                                when 5 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1101";
                                        Write <= '1';
                                when 6 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To <= "1100";
                                        Write <= '1';
                                when 7 =>
                                        Write <= '1';
                                        CallL <= '1';
                                when others => null;
                                end case;
                        when "11001001" =>
                                -- Phase11: RET.L (ED C9). M2 24bit far
                                -- return; pops the matching 3byte PC24
                                -- frame pushed by CALL.L (same LOW/HIGH/
                                -- BANK read order and MSP24-increment-
                                -- after-each-read pattern as Phase9's
                                -- POP24 - see the matching t80.vhd direct
                                -- IR-match block). M1 mirrors plain RET's
                                -- own (TStates<=101, Set_Addr_To<=aSP)
                                -- shape exactly, just targeting aMSP. This
                                -- opcode slot was previously the
                                -- unreachable "R800 MULUB" placeholder
                                -- (see ED D9, which keeps that placeholder
                                -- unchanged).
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        Set_Addr_To <= aMSP;
                                when 2 =>
                                        Set_Addr_To <= aMSP;
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aMSP;
                                        LDW <= '1';
                                when 4 =>
                                        RetL <= '1';
                                when others => null;
                                end case;
                        when "11000000"|"11001000"|"11010000"|"11011000"|"11100000"|"11101000"|"11110000"|"11111000" =>
                                -- Phase11: RET.L cc (ED C0/C8/D0/D8/E0/E8/
                                -- F0/F8). Same pop shape as RET.L above;
                                -- condition test (at M1, mirroring plain
                                -- 'RET cc' testing immediately) either
                                -- continues to the pop phase (condition
                                -- true) or shrinks MCycles to abort right
                                -- after the opcode fetch (condition false,
                                -- matching real Z80 RET cc's variable-
                                -- length timing).
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        if is_cc_true(F, to_bitvector(IR(5 downto 3))) then
                                                Set_Addr_To <= aMSP;
                                        else
                                                MCycles <= "0001";
                                        end if;
                                        TStates <= "101";
                                when 2 =>
                                        Set_Addr_To <= aMSP;
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aMSP;
                                        LDW <= '1';
                                when 4 =>
                                        RetL <= '1';
                                when others => null;
                                end case;
                        when "11000101"|"11010101"|"11100101" =>
                                -- Phase9: PUSH24 BC/DE/HL (ED C5/D5/E5)
                                -- (MSX_T80_24bit化_実装手順_V2_2026-10-05.md, section 11
                                --  "Phase 9"; CPU仕様書V8 section 9 "Stack"). Writes
                                -- BANK/HIGH/LOW (in that order, decrementing MSP24
                                -- before each byte) via the new aMSP address source.
                                -- MSP24 decrement itself, and the BANK-byte DO
                                -- override, are both handled directly in t80.vhd
                                -- (keyed on IR/MCycle, mirroring the Phase7/8
                                -- direct-IR-match pattern) rather than here, since
                                -- MSP/bank_msp_r are plain signals outside both the
                                -- register file and the existing IncDec_16/Set_BusB_To
                                -- encodings. DD/FD (IX/IY) variants are deferred (same
                                -- scope limitation as Phase7's LD24 HL,IX/IY - see
                                -- AVAILABLE_INSTRUCTIONS.md) due to the existing
                                -- DD/FD+ED dual-prefix XY_State reset limitation.
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        Set_Addr_To <= aMSP;
                                when 2 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To(2 downto 1) <= DPair;
                                        Set_BusB_To(0) <= '0';  -- stage HIGH byte for MCycle3's write
                                        Set_BusB_To(3) <= '0';
                                        Write <= '1';
                                when 3 =>
                                        Set_Addr_To <= aMSP;
                                        Set_BusB_To(2 downto 1) <= DPair;
                                        Set_BusB_To(0) <= '1';  -- stage LOW byte for MCycle4's write
                                        Set_BusB_To(3) <= '0';
                                        Write <= '1';
                                when 4 =>
                                        Write <= '1';
                                when others => null;
                                end case;
                        when "11000001"|"11010001"|"11100001" =>
                                -- Phase9: POP24 BC/DE/HL (ED C1/D1/E1). Reads
                                -- LOW/HIGH/BANK (in that order, incrementing MSP24
                                -- after each byte) via the same aMSP address source.
                                -- LOW/HIGH bytes commit into the register file via
                                -- the existing generic Read_To_Reg/Set_BusA_To
                                -- mechanism (identical to plain POP qq); the BANK
                                -- byte capture and all three MSP24 increments are
                                -- handled directly in t80.vhd. DD/FD (IX/IY)
                                -- variants deferred, see the PUSH24 comment above.
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aMSP;
                                when 2 =>
                                        Set_Addr_To <= aMSP;
                                        Read_To_Reg <= '1';
                                        Set_BusA_To(2 downto 1) <= DPair;
                                        Set_BusA_To(0) <= '1';  -- LOW byte dest
                                when 3 =>
                                        Set_Addr_To <= aMSP;
                                        Read_To_Reg <= '1';
                                        Set_BusA_To(2 downto 1) <= DPair;
                                        Set_BusA_To(0) <= '0';  -- HIGH byte dest
                                when 4 =>
                                        null; -- BANK byte capture + MSP increments: see t80.vhd
                                when others => null;
                                end case;
                        when "01111110"|"01111111" =>
                                -- NOP, undocumented
                                null;
-- 8 BIT LOAD GROUP
                        when "01010111" =>
                                -- LD A,I
                                Special_LD <= "100";
                                TStates <= "101";
                        when "01011111" =>
                                -- LD A,R
                                Special_LD <= "101";
                                TStates <= "101";
                        when "01000111" =>
                                -- LD I,A
                                Special_LD <= "110";
                                TStates <= "101";
                        when "01001111" =>
                                -- LD R,A
                                Special_LD <= "111";
                                TStates <= "101";
-- 16 BIT LOAD GROUP
                        when "01001011"|"01011011"|"01101011"|"01111011" =>
                                -- LD dd,(nn)
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                when 4 =>
                                        Read_To_Reg <= '1';
                                        if IR(5 downto 4) = "11" then
                                                Set_BusA_To <= "1000";
                                        else
                                                Set_BusA_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusA_To(0) <= '1';
                                        end if;
                                        Inc_WZ <= '1';
                                        Set_Addr_To <= aZI;
                                when 5 =>
                                        Read_To_Reg <= '1';
                                        if IR(5 downto 4) = "11" then
                                                Set_BusA_To <= "1001";
                                        else
                                                Set_BusA_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusA_To(0) <= '0';
                                        end if;
                                when others => null;
                                end case;
                        when "01000011"|"01010011"|"01100011"|"01110011" =>
                                -- LD (nn),dd
                                MCycles <= "0101";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Inc_PC <= '1';
                                        LDZ <= '1';
                                when 3 =>
                                        Set_Addr_To <= aZI;
                                        Inc_PC <= '1';
                                        LDW <= '1';
                                        if IR(5 downto 4) = "11" then
                                                Set_BusB_To <= "1000";
                                        else
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusB_To(0) <= '1';
                                                Set_BusB_To(3) <= '0';
                                        end if;
                                when 4 =>
                                        Inc_WZ <= '1';
                                        Set_Addr_To <= aZI;
                                        Write <= '1';
                                        if IR(5 downto 4) = "11" then
                                                Set_BusB_To <= "1001";
                                        else
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusB_To(0) <= '0';
                                                Set_BusB_To(3) <= '0';
                                        end if;
                                when 5 =>
                                        Write <= '1';
                                when others => null;
                                end case;
                        when "10100000" | "10101000" | "10110000" | "10111000" =>
                                -- LDI, LDD, LDIR, LDDR
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                        IncDec_16 <= "1100"; -- BC
                                when 2 =>
                                        Set_BusB_To <= "0110";
                                        Set_BusA_To(2 downto 0) <= "111";
                                        ALU_Op <= "0000";
                                        Set_Addr_To <= aDE;
                                        if IR(3) = '0' then
                                                IncDec_16 <= "0110"; -- IX
                                        else
                                                IncDec_16 <= "1110";
                                        end if;
                                when 3 =>
                                        I_BT <= '1';
                                        TStates <= "101";
                                        Write <= '1';
                                        if IR(3) = '0' then
                                                IncDec_16 <= "0101"; -- DE
                                        else
                                                IncDec_16 <= "1101";
                                        end if;
                                when 4 =>
                                        NoRead <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "10100001" | "10101001" | "10110001" | "10111001" =>
                                -- CPI, CPD, CPIR, CPDR
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aXY;
                                        IncDec_16 <= "1100"; -- BC
                                when 2 =>
                                        Set_BusB_To <= "0110";
                                        Set_BusA_To(2 downto 0) <= "111";
                                        ALU_Op <= "0111";
                                        ALU_cpi <= '1';
                                        Save_ALU <= '1';
                                        PreserveC <= '1';
                                        if IR(3) = '0' then
                                                IncDec_16 <= "0110";
                                        else
                                                IncDec_16 <= "1110";
                                        end if;
                                when 3 =>
                                        NoRead <= '1';
                                        I_BC <= '1';
                                        TStates <= "101";
                                when 4 =>
                                        NoRead <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "01000100"|"01001100"|"01010100"|"01011100"|"01100100"|"01101100"|"01110100"|"01111100" =>
                                -- NEG
                                Alu_OP <= "0010";
                                Set_BusB_To <= "0111";
                                Set_BusA_To <= "1010";
                                Read_To_Acc <= '1';
                                Save_ALU <= '1';
                        when "01000110"|"01001110"|"01100110"|"01101110" =>
                                -- IM 0
                                IMode <= "00";
                        when "01010110"|"01110110" =>
                                -- IM 1
                                IMode <= "01";
                        when "01011110"|"01110111" =>
                                -- IM 2
                                IMode <= "10";
-- 16 bit arithmetic
                        when "01001010"|"01011010"|"01101010"|"01111010" =>
                                -- ADC HL,ss
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        NoRead <= '1';
                                        ALU_Op <= "0001";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        Set_BusA_To(2 downto 0) <= "101";
                                        case to_integer(unsigned(IR(5 downto 4))) is
                                        when 0|1|2 =>
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                        Set_BusB_To(0) <= '1';
                                                when others =>
                                                Set_BusB_To <= "1000";
                                        end case;
                                        TStates <= "100";
                                when 3 =>
                                        NoRead <= '1';
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        ALU_Op <= "0001";
                                        Set_BusA_To(2 downto 0) <= "100";
                                        case to_integer(unsigned(IR(5 downto 4))) is
                                        when 0|1|2 =>
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusB_To(0) <= '0';
                                        when others =>
                                                Set_BusB_To <= "1001";
                                        end case;
                                when others =>
                                end case;
                        when "01000010"|"01010010"|"01100010"|"01110010" =>
                                -- SBC HL,ss
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        NoRead <= '1';
                                        ALU_Op <= "0011";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        Set_BusA_To(2 downto 0) <= "101";
                                        case to_integer(unsigned(IR(5 downto 4))) is
                                        when 0|1|2 =>
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                                Set_BusB_To(0) <= '1';
                                        when others =>
                                                Set_BusB_To <= "1000";
                                        end case;
                                        TStates <= "100";
                                when 3 =>
                                        NoRead <= '1';
                                        ALU_Op <= "0011";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        Set_BusA_To(2 downto 0) <= "100";
                                        case to_integer(unsigned(IR(5 downto 4))) is
                                        when 0|1|2 =>
                                                Set_BusB_To(2 downto 1) <= IR(5 downto 4);
                                        when others =>
                                                        Set_BusB_To <= "1001";
                                        end case;
                                when others =>
                                end case;
                        when "01101111" =>
                                -- RLD
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        NoRead <= '1';
                                        Set_Addr_To <= aXY;
                                when 3 =>
                                        Read_To_Reg <= '1';
                                        Set_BusB_To(2 downto 0) <= "110";
                                        Set_BusA_To(2 downto 0) <= "111";
                                        ALU_Op <= "1101";
                                        TStates <= "100";
                                        Set_Addr_To <= aXY;
                                        Save_ALU <= '1';
                                when 4 =>
                                        I_RLD <= '1';
                                        Write <= '1';
                                when others =>
                                end case;
                        when "01100111" =>
                                -- RRD
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 2 =>
                                        Set_Addr_To <= aXY;
                                when 3 =>
                                        Read_To_Reg <= '1';
                                        Set_BusB_To(2 downto 0) <= "110";
                                        Set_BusA_To(2 downto 0) <= "111";
                                        ALU_Op <= "1110";
                                        TStates <= "100";
                                        Set_Addr_To <= aXY;
                                        Save_ALU <= '1';
                                when 4 =>
                                        I_RRD <= '1';
                                        Write <= '1';
                                when others =>
                                end case;
                        when "01000101"|"01001101"|"01010101"|"01011101"|"01100101"|"01101101"|"01110101"|"01111101" =>
                                -- RETI, RETN
                                MCycles <= "0011";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_TO <= aSP;
                                when 2 =>
                                        IncDec_16 <= "0111";
                                        Set_Addr_To <= aSP;
                                        LDZ <= '1';
                                when 3 =>
                                        Jump <= '1';
                                        IncDec_16 <= "0111";
                                        I_RETN <= '1';
                                when others => null;
                                end case;
                        when "01000000"|"01001000"|"01010000"|"01011000"|"01100000"|"01101000"|"01110000"|"01111000" =>
                                if IR = "01101000" and LeaXY /= "00" then
                                        -- New (V4 21.2): LEA.L HL,(IX/IY+d)
                                        -- (DD/FD ED 68 d). M1=this opcode
                                        -- byte (recognized via LeaXY,
                                        -- latched in t80.vhd when this ED
                                        -- was immediately preceded by DD/
                                        -- FD - see t80.vhd's LeaXY comment);
                                        -- M2=fetch displacement d (Inc_PC
                                        -- here, EA computed into TmpAddr/
                                        -- TmpBank at M2's T_Res directly in
                                        -- t80.vhd); M3=register-file
                                        -- writeback (also handled directly
                                        -- in t80.vhd - RegAddrA_r/RegWEH/
                                        -- RegWEL/RegDIH/RegDIL/bank_hl_r).
                                        -- No memory access at the effective
                                        -- address (LEA, not a dereference).
                                        -- Bare "ED 68" (LeaXY="00", no
                                        -- preceding DD/FD) falls through to
                                        -- the unchanged IN r,(C) path below.
                                        MCycles <= "0011";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                        when others => null;
                                        end case;
                                else
                                        -- IN r,(C)
                                        MCycles <= "0010";
                                        case to_integer(unsigned(MCycle)) is
                                        when 1 =>
                                                Set_Addr_To <= aBC;
                                        when 2 =>
                                                IORQ <= '1';
                                                if IR(5 downto 3) /= "110" then
                                                        Read_To_Reg <= '1';
                                                        Set_BusA_To(2 downto 0) <= IR(5 downto 3);
                                                end if;
                                                I_INRC <= '1';
                                        when others =>
                                        end case;
                                end if;
                        when "01000001"|"01001001"|"01010001"|"01011001"|"01100001"|"01101001"|"01110001"|"01111001" =>
                                if IR = "01101001" and LeaXY /= "00" then
                                        -- New (V4 21.2): LEA.L DE,(IX/IY+d)
                                        -- (DD/FD ED 69 d). Same shape as
                                        -- LEA.L HL above; see its comment.
                                        -- Bare "ED 69" (LeaXY="00") falls
                                        -- through to the unchanged OUT
                                        -- (C),r path below.
                                        MCycles <= "0011";
                                        case to_integer(unsigned(MCycle)) is
                                        when 2 =>
                                                Inc_PC <= '1';
                                        when others => null;
                                        end case;
                                else
                                        -- OUT (C),r
                                        -- OUT (C),0
                                        MCycles <= "0010";
                                        case to_integer(unsigned(MCycle)) is
                                        when 1 =>
                                                Set_Addr_To <= aBC;
                                                Set_BusB_To(2 downto 0) <= IR(5 downto 3);
                                                if IR(5 downto 3) = "110" then
                                                        Set_BusB_To(3) <= '1';
                                                end if;
                                        when 2 =>
                                                Write <= '1';
                                                IORQ <= '1';
                                        when others =>
                                        end case;
                                end if;
                        when "10100010" | "10101010" | "10110010" | "10111010" =>
                                -- INI, IND, INIR, INDR
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        Set_Addr_To <= aBC;
                                        Set_BusB_To <= "1010";
                                        Set_BusA_To <= "0000";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        ALU_Op <= "0010";
                                when 2 =>
                                        IORQ <= '1';
                                        Set_BusB_To <= "0110";
                                        Set_Addr_To <= aXY;
                                when 3 =>
                                        if IR(3) = '0' then
                                                IncDec_16 <= "0110";    -- 0242a
                                        else
                                                IncDec_16 <= "1110";    -- 0242a
                                        end if;
                                        TStates <= "100";
                                        Write <= '1';
                                        I_BTR <= '1';
                                when 4 =>
                                        NoRead <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "10100011" | "10101011" | "10110011" | "10111011" =>
                                -- OUTI, OUTD, OTIR, OTDR
                                MCycles <= "0100";
                                case to_integer(unsigned(MCycle)) is
                                when 1 =>
                                        TStates <= "101";
                                        Set_Addr_To <= aXY;
                                        Set_BusB_To <= "1010";
                                        Set_BusA_To <= "0000";
                                        Read_To_Reg <= '1';
                                        Save_ALU <= '1';
                                        ALU_Op <= "0010";
                                when 2 =>
                                        Set_BusB_To <= "0110";
                                        Set_Addr_To <= aBC;
                                when 3 =>
                                        if IR(3) = '0' then
                                                IncDec_16 <= "0110";    -- 0242a
                                        else
                                                IncDec_16 <= "1110";    -- 0242a
                                        end if;
                                        IORQ <= '1';
                                        Write <= '1';
                                        I_BTR <= '1';
                                when 4 =>
                                        NoRead <= '1';
                                        TStates <= "101";
                                when others => null;
                                end case;
                        when "11011001" =>
                                -- R800 MULUB. ED C9 (previously grouped
                                -- here alongside D9) is now Phase11's
                                -- RET.L below; this opcode (D9) remains the
                                -- unreachable R800 placeholder since Mode
                                -- is always 0=Z80 in this project.
                                null;
                        when "11110011" =>
                                -- R800 MULUW. ED C3 (previously grouped here)
                                -- is now Phase11's JP.L addr24 above; this
                                -- opcode (F3) remains the unreachable R800
                                -- placeholder since Mode is always 0=Z80 in
                                -- this project.
                                null;
                        end case;

                end case;

                if Mode = 1 then
                        if MCycle = "0001" then
--                              TStates <= "100";
                        else
                                TStates <= "011";
                        end if;
                end if;

                if Mode = 3 then
                        if MCycle = "0001" then
--                              TStates <= "100";
                        else
                                TStates <= "100";
                        end if;
                end if;

                if Mode < 2 then
                        -- Phase11: this block was originally unconditional
                        -- for ANY instruction reaching MCycle=110/111,
                        -- intended ONLY for the DD/FD+CB double-prefix
                        -- continuation (NextIs_XY_Fetch in t80.vhd, itself
                        -- gated on XY_State/="00"). New instructions with
                        -- their own MCycles reaching 6/7 for unrelated
                        -- reasons (e.g. CALL.L's 7-cycle fetch+push
                        -- sequence) must NOT be affected by this -
                        -- guarding on XY_State/="00" restores that
                        -- intent without touching the DD/FD+CB behaviour
                        -- itself (XY_State is always /="00" whenever this
                        -- block's MCycle=110/111 is legitimately reached
                        -- via the DD/FD+CB path).
                        if MCycle = "0110" and XY_State /= "00" then
                                Inc_PC <= '1';
                                if Mode = 1 then
                                        Set_Addr_To <= aXY;
                                        TStates <= "100";
                                        Set_BusB_To(2 downto 0) <= SSS;
                                        Set_BusB_To(3) <= '0';
                                end if;
                                if IRB = "00110110" or IRB = "11001011" then
                                        Set_Addr_To <= aNone;
                                end if;
                        end if;
                        if MCycle = "0111" and XY_State /= "00" then
                                if Mode = 0 then
                                        TStates <= "101";
                                end if;
                                if ISet /= "01" then
                                        Set_Addr_To <= aXY;
                                end if;
                                Set_BusB_To(2 downto 0) <= SSS;
                                Set_BusB_To(3) <= '0';
                                if IRB = "00110110" or ISet = "01" then
                                        -- LD (HL),n
                                        Inc_PC <= '1';
                                else
                                        NoRead <= '1';
                                end if;
                        end if;
                end if;

        end process;

end;
