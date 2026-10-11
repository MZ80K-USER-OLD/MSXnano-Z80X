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
--  0250 : Version alignment by KdL 2017.10.23
--
--  +k01 : Version alignment by KdL 2010.10.25
--  +k02 : Added R800_mode signal by KdL 2018.05.14
--  +k03 : Version alignment by KdL 2019.05.20
--  +k04 : Separation of T800 from T80 by KdL 2021.02.01
--

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package T80_Pack is

    -- Phase2: 24bit address generator.
    --
    -- All functions compute (Bank & Low16) + signed(Disp), modulo 2^24, and
    -- return the concatenated 24bit result (bits 23:16 = new bank byte,
    -- bits 15:0 = new 16bit word). Carry/borrow between Low16 and Bank
    -- happens naturally through the fixed-width 24bit addition, e.g.
    -- Addr24_Inc(x"FF", x"FFFF") = x"000000" and
    -- Addr24_Dec(x"00", x"0000") = x"FFFFFF".
    --
    -- Used for IX24/IY24 (+d) effective address generation in M1/M2 (Phase3),
    -- and reusable for JR.L 16bit displacement (Phase11) and MSP24
    -- increment/decrement (Phase9). M0 must not call these: M0 keeps the
    -- existing plain 16bit wrap behaviour untouched.
    function Addr24_AddDisp16(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0); Disp16 : std_logic_vector(15 downto 0)) return std_logic_vector;
    function Addr24_AddDisp8(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0); Disp8 : std_logic_vector(7 downto 0)) return std_logic_vector;
    function Addr24_Inc(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0)) return std_logic_vector;
    function Addr24_Dec(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0)) return std_logic_vector;

    -- Phase8: dedicated 24bit ALU add/subtract (MSX_T80_24bit化_実装手順_V2
    -- section 10 "Phase 8", CPU仕様書V8 section 6 "24bit ALU"). Deliberately
    -- separate from the shared 8bit ALU (t80_alu.vhd) so INC24/DEC24/
    -- ADD24/ADC24/SBC24/CP24 add zero risk of regressing existing Z80 ALU
    -- behaviour. Uses the same two's-complement "add NOT(B) plus inverted
    -- carry-in" technique as t80_alu.vhd's internal AddSub procedure, split
    -- into a low 23bit chunk and the top bit so the carry-into-bit23 can be
    -- captured for signed-overflow detection (P/V = carry-out-of-bit23 XOR
    -- carry-into-bit23, mirroring t80_alu.vhd's OverFlow_v computation).
    --
    -- Sub='0' computes A+B+Carry_In (ADD/ADC/INC24 use this, with
    -- Carry_In='0' for ADD/INC24 and Carry_In=F(Flag_C) for ADC24).
    -- Sub='1' computes A+NOT(B)+Carry_In, the standard two's-complement
    -- subtraction form (DEC24/CP24/SBC24 use this, with Carry_In='1' for
    -- DEC24/CP24 - the fixed "+1" that has no real borrow-in - and
    -- Carry_In=not F(Flag_C) for SBC24, i.e. the existing borrow inverted;
    -- there
    -- is no dedicated SUB24 opcode, matching the spec's "SUB24は設けずC=0の
    -- SBC24を使う").
    --
    -- Returns a 26bit vector: bit25=Overflow (P/V), bit24=raw adder
    -- carry-out of bit23 (the caller must invert this for Sub='1' to get
    -- the Z80-convention C flag, exactly as t80_alu.vhd does for SUB/SBC/
    -- CP: "not Carry_v"), bits 23 downto 0 = 24bit result. H (half-carry)
    -- is intentionally NOT computed/returned: per spec, H is preserved
    -- (left untouched by the caller) for this whole 24bit ALU group.
    function Alu24_AddSub(A : std_logic_vector(23 downto 0); B : std_logic_vector(23 downto 0); Sub : std_logic; Carry_In : std_logic) return std_logic_vector;

    component T80
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
    end component;

    component T80_Reg
    port(
        Clk         : in std_logic;
        CEN         : in std_logic;
        WEH         : in std_logic;
        WEL         : in std_logic;
        AddrA       : in std_logic_vector(2 downto 0);
        AddrB       : in std_logic_vector(2 downto 0);
        AddrC       : in std_logic_vector(2 downto 0);
        DIH         : in std_logic_vector(7 downto 0);
        DIL         : in std_logic_vector(7 downto 0);
        DOAH        : out std_logic_vector(7 downto 0);
        DOAL        : out std_logic_vector(7 downto 0);
        DOBH        : out std_logic_vector(7 downto 0);
        DOBL        : out std_logic_vector(7 downto 0);
        DOCH        : out std_logic_vector(7 downto 0);
        DOCL        : out std_logic_vector(7 downto 0)
    );
    end component;

    component T80_MCode
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
        MCycle      : in std_logic_vector(2 downto 0);
        F           : in std_logic_vector(7 downto 0);
        NMICycle    : in std_logic;
        IntCycle    : in std_logic;
        XY_State    : in  std_logic_vector(1 downto 0);
        MCycles     : out std_logic_vector(2 downto 0);
        TStates     : out std_logic_vector(2 downto 0);
        Prefix      : out std_logic_vector(1 downto 0); -- None,BC,ED,DD/FD
        Inc_PC      : out std_logic;
        Inc_WZ      : out std_logic;
        IncDec_16   : out std_logic_vector(3 downto 0); -- BC,DE,HL,SP   0 is inc
        Read_To_Reg : out std_logic;
        Read_To_Acc : out std_logic;
        Set_BusA_To : out std_logic_vector(3 downto 0); -- B,C,D,E,H,L,DI/DB,A,SP(L),SP(M),0,F
        Set_BusB_To : out std_logic_vector(3 downto 0); -- B,C,D,E,H,L,DI,A,SP(L),SP(M),1,F,PC(L),PC(M),0
        ALU_Op      : out std_logic_vector(3 downto 0);
            -- ADD, ADC, SUB, SBC, AND, XOR, OR, CP, ROT, BIT, SET, RES, DAA, RLD, RRD, None
        ALU_cpi     : out std_logic;
        Save_ALU    : out std_logic;
        PreserveC   : out std_logic;
        Arith16     : out std_logic;
        Set_Addr_To : out std_logic_vector(2 downto 0); -- aNone,aXY,aIOA,aSP,aBC,aDE,aZI
        IORQ        : out std_logic;
        Jump        : out std_logic;
        JumpL       : out std_logic;
        JumpR       : out std_logic;
        JumpE       : out std_logic;
        JumpEL      : out std_logic;
        JumpXY      : out std_logic;
        Call        : out std_logic;
        CallL       : out std_logic;
        RetL        : out std_logic;
        RstP        : out std_logic;
        LDZ         : out std_logic;
        LDW         : out std_logic;
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
    end component;

    component T80_ALU
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
        Arith16     : in std_logic;
        Z16         : in std_logic;
        ALU_cpi     : in std_logic;
        ALU_Op      : in std_logic_vector(3 downto 0);
        IR          : in std_logic_vector(5 downto 0);
        ISet        : in std_logic_vector(1 downto 0);
        BusA        : in std_logic_vector(7 downto 0);
        BusB        : in std_logic_vector(7 downto 0);
        F_In        : in std_logic_vector(7 downto 0);
        Q           : out std_logic_vector(7 downto 0);
        F_Out       : out std_logic_vector(7 downto 0)
    );
    end component;

end;

package body T80_Pack is

    function Addr24_AddDisp16(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0); Disp16 : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable Base  : unsigned(23 downto 0);
        variable Delta : unsigned(23 downto 0);
    begin
        Base  := unsigned(Bank & Low16);
        Delta := unsigned(std_logic_vector(resize(signed(Disp16), 24)));
        return std_logic_vector(Base + Delta);
    end function Addr24_AddDisp16;

    function Addr24_AddDisp8(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0); Disp8 : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        return Addr24_AddDisp16(Bank, Low16, std_logic_vector(resize(signed(Disp8), 16)));
    end function Addr24_AddDisp8;

    function Addr24_Inc(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0)) return std_logic_vector is
    begin
        return Addr24_AddDisp16(Bank, Low16, x"0001");
    end function Addr24_Inc;

    function Addr24_Dec(Bank : std_logic_vector(7 downto 0); Low16 : std_logic_vector(15 downto 0)) return std_logic_vector is
    begin
        return Addr24_AddDisp16(Bank, Low16, x"FFFF");
    end function Addr24_Dec;

    function Alu24_AddSub(A : std_logic_vector(23 downto 0); B : std_logic_vector(23 downto 0); Sub : std_logic; Carry_In : std_logic) return std_logic_vector is
        variable B_i          : unsigned(23 downto 0);
        variable Low_i        : unsigned(24 downto 0);
        variable CarryInto23  : std_logic;
        variable Top_i        : unsigned(2 downto 0);
        variable CarryOut23   : std_logic;
        variable Result       : std_logic_vector(23 downto 0);
        variable Overflow     : std_logic;
    begin
        if Sub = '1' then
            B_i := not unsigned(B);
        else
            B_i := unsigned(B);
        end if;

        -- bits 22:0, carry generated into bit23
        Low_i := unsigned("0" & A(22 downto 0) & Carry_In) + unsigned("0" & std_logic_vector(B_i(22 downto 0)) & "1");
        CarryInto23 := Low_i(24);
        Result(22 downto 0) := std_logic_vector(Low_i(23 downto 1));

        -- bit 23, carry-in from the low chunk above
        Top_i := unsigned("0" & A(23 downto 23) & CarryInto23) + unsigned("0" & std_logic_vector(B_i(23 downto 23)) & "1");
        CarryOut23 := Top_i(2);
        Result(23) := Top_i(1);

        Overflow := CarryOut23 xor CarryInto23;

        return Overflow & CarryOut23 & Result;
    end function Alu24_AddSub;

end package body T80_Pack;
