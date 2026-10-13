;==============================================================================
; LD24TEST.ASM - Z80X24 Phase7 "LD24系命令" 実機テストプログラム (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase7「LD24系命令」のうち、本増分で実装したレジスタ間24bit転送命令
; (HL24 hub / MSP24 / IVR24 / NVR24) を、実機/エミュレータ上の
; MSX-DOS(2)から起動して確認するためのテストプログラムです。
;
;   doc/jpn/MSX_T80_24bit化_実装手順_V2_2026-10-05.md セクション9 "Phase 7"
;   doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md セクション7
;     "HL24 hub / MSP / vector"
;   fpga/G80A/test/tb_phase7_ld24.vhd (同じシナリオのGHDLシミュレーション版)
;
; 検証内容 (tb_phase7_ld24.vhd と同じシナリオ):
;   Test1: ED06 LD24 HL,BC  (HL24 <- BC24)。宛先の24bit値と、ソースBC24が
;          変化していないことを確認する。
;   Test2: ED0E LD24 BC,HL  (BC24 <- HL24)。同上、ソースHL24が不変か確認。
;   Test3: ED16 LD24 HL,DE  (HL24 <- DE24)。同上、ソースDE24が不変か確認。
;   Test4: ED1E LD24 DE,HL  (DE24 <- HL24)。同上、ソースHL24が不変か確認。
;   Test5: ED35/ED36 MSP24往復試験。HL24をMSP24へ退避→HL24を破壊→MSP24から
;          HL24へ復元し、元の値と一致するか確認する。
;   Test6: ED9B/ED9C IVR24往復試験。同上の手順でIVR24を検証する。
;   Test7: ED9E/ED9F NVR24往復試験。同上の手順でNVR24を検証する。
;   Test8: いずれか1つのLD24命令の前後でF(フラグ)レジスタが変化しないことを
;          確認する(仕様上「F不変」)。
;
; 安全設計上の注意:
;   - 本増分のLD24命令はすべて単純なレジスタ間24bitコピーであり、M1/M2
;     モードへの切替やメモリ/MMUアクセスを一切伴わない。そのため本プログラム
;     は常時M0(通常のMSX互換モード)のまま動作し、MMUTEST.COMのような
;     DI/EI・モード切替・物理bank割当の配慮は不要である。
;   - HL/BC/DEのバンクバイト(HL_B/BC_B/DE_B)はPhase1で実装済みの
;     `ED 04/0C/14/1C/24/2C LD xx_B,A / LD A,xx_B` を用いて設定・読出しする。
;   - プログラム終了前に、使用したBC/DE/HLバンクレジスタを0クリアしてから
;     MSX-DOSへ復帰する(SAFE_RESET参照)。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `LD24TEST` と入力する。
;==============================================================================

	org	$0100

;------------------------------------------------------------------------------
; MSX-DOS / BDOS
;------------------------------------------------------------------------------
BDOS		EQU	0005H		; DOS function entry

;------------------------------------------------------------------------------
; Z80X24 独自オペコード (標準Z80アセンブラには無いため DEFB で直接発行する)
;------------------------------------------------------------------------------
; ED 04/0C     LD BC_B,A / LD A,BC_B           (Phase1)
; ED 14/1C     LD DE_B,A / LD A,DE_B           (Phase1)
; ED 24/2C     LD HL_B,A / LD A,HL_B           (Phase1)
; ED 06        LD24 HL,BC                      (Phase7, 本プログラムの対象)
; ED 0E        LD24 BC,HL                      (Phase7, 本プログラムの対象)
; ED 16        LD24 HL,DE                      (Phase7, 本プログラムの対象)
; ED 1E        LD24 DE,HL                      (Phase7, 本プログラムの対象)
; ED 35        LD24 MSP,HL                     (Phase7, 本プログラムの対象)
; ED 36        LD24 HL,MSP                     (Phase7, 本プログラムの対象)
; ED 9B        LD24 IVR,HL                     (Phase7, 本プログラムの対象)
; ED 9C        LD24 HL,IVR                     (Phase7, 本プログラムの対象)
; ED 9E        LD24 NVR,HL                     (Phase7, 本プログラムの対象)
; ED 9F        LD24 HL,NVR                     (Phase7, 本プログラムの対象)
;------------------------------------------------------------------------------

;==============================================================================
; エントリポイント
;==============================================================================
START:
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ==== Test1: ED06 LD24 HL,BC (HL24 <- BC24 = 11:1122h) ====
	LD	BC,1122H
	LD	A,11H
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,006H		; LD24 HL,BC
	; 宛先HL24を回収
	CALL	SNAP_HL24
	LD	(T1_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T1_HL_BANK),A
	; ソースBC24(不変であるべき)を回収
	LD	(T1_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T1_BC_BANK),A

	LD	HL,1122H
	LD	B,11H
	LD	DE,MSG_T1A
	LD	IX,T1_HL_LO
	CALL	CHECK24_IX
	LD	HL,1122H
	LD	B,11H
	LD	DE,MSG_T1B
	LD	IX,T1_BC_LO
	CALL	CHECK24_IX

	; ==== Test2: ED0E LD24 BC,HL (BC24 <- HL24 = 33:5566h) ====
	LD	HL,5566H
	LD	A,33H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,00EH		; LD24 BC,HL
	LD	(T2_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T2_BC_BANK),A
	CALL	SNAP_HL24
	LD	(T2_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T2_HL_BANK),A

	LD	HL,5566H
	LD	B,33H
	LD	DE,MSG_T2A
	LD	IX,T2_BC_LO
	CALL	CHECK24_IX
	LD	HL,5566H
	LD	B,33H
	LD	DE,MSG_T2B
	LD	IX,T2_HL_LO
	CALL	CHECK24_IX

	; ==== Test3: ED16 LD24 HL,DE (HL24 <- DE24 = 22:3344h) ====
	LD	DE,3344H
	LD	A,22H
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,016H		; LD24 HL,DE
	CALL	SNAP_HL24
	LD	(T3_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T3_HL_BANK),A
	LD	(T3_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T3_DE_BANK),A

	LD	HL,3344H
	LD	B,22H
	LD	DE,MSG_T3A
	LD	IX,T3_HL_LO
	CALL	CHECK24_IX
	LD	HL,3344H
	LD	B,22H
	LD	DE,MSG_T3B
	LD	IX,T3_DE_LO
	CALL	CHECK24_IX

	; ==== Test4: ED1E LD24 DE,HL (DE24 <- HL24 = 33:5566h) ====
	LD	HL,5566H
	LD	A,33H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,01EH		; LD24 DE,HL
	LD	(T4_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T4_DE_BANK),A
	CALL	SNAP_HL24
	LD	(T4_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T4_HL_BANK),A

	LD	HL,5566H
	LD	B,33H
	LD	DE,MSG_T4A
	LD	IX,T4_DE_LO
	CALL	CHECK24_IX
	LD	HL,5566H
	LD	B,33H
	LD	DE,MSG_T4B
	LD	IX,T4_HL_LO
	CALL	CHECK24_IX

	; ==== Test5: ED35/ED36 MSP24 round trip (44:7788h) ====
	LD	HL,7788H
	LD	A,44H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL
	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,036H		; LD24 HL,MSP
	CALL	SNAP_HL24
	LD	(T5_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T5_HL_BANK),A

	LD	HL,7788H
	LD	B,44H
	LD	DE,MSG_T5
	LD	IX,T5_HL_LO
	CALL	CHECK24_IX

	; ==== Test6: ED9B/ED9C IVR24 round trip (55:99AAh) ====
	LD	HL,99AAH
	LD	A,55H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,09BH		; LD24 IVR,HL
	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,09CH		; LD24 HL,IVR
	CALL	SNAP_HL24
	LD	(T6_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T6_HL_BANK),A

	LD	HL,99AAH
	LD	B,55H
	LD	DE,MSG_T6
	LD	IX,T6_HL_LO
	CALL	CHECK24_IX

	; ==== Test7: ED9E/ED9F NVR24 round trip (66:BBCCh) ====
	LD	HL,0BBCCH
	LD	A,66H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,09EH		; LD24 NVR,HL
	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,09FH		; LD24 HL,NVR
	CALL	SNAP_HL24
	LD	(T7_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T7_HL_BANK),A

	LD	HL,0BBCCH
	LD	B,66H
	LD	DE,MSG_T7
	LD	IX,T7_HL_LO
	CALL	CHECK24_IX

	; ==== Test8: LD24命令の前後でFレジスタが不変であることを確認 ====
	SCF				; 既知のフラグ状態を作る
	PUSH	AF
	POP	BC			; C = F (before)
	LD	A,C
	LD	(F_BEFORE),A
	DEFB	0EDH,006H		; LD24 HL,BC (任意のLD24命令を1つ実行)
	PUSH	AF
	POP	BC			; C = F (after)
	LD	A,C
	LD	(F_AFTER),A

	LD	DE,MSG_T8
	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR
	; 比較はBDOS呼出し直後ではなく、ここで初めて行う(CALL BDOSが
	; レジスタ/フラグを破壊し得るため、CP直後のJRでしか分岐できない)。
	LD	A,(F_BEFORE)
	LD	HL,F_AFTER
	CP	(HL)
	JR	NZ,T8_FAIL
	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	T8_DONE
T8_FAIL:
	LD	DE,MSG_FAIL
	CALL	PRINT_STR
	LD	A,(F_BEFORE)
	CALL	PRINT_HEX
	LD	DE,MSG_WANT
	CALL	PRINT_STR
	LD	A,(F_AFTER)
	CALL	PRINT_HEX
	LD	E,')'
	LD	C,2
	CALL	BDOS
	LD	HL,FAIL_COUNT
	INC	(HL)
T8_DONE:
	LD	DE,MSG_CRLF
	CALL	PRINT_STR

	; ---- 安全のため、使用したバンクレジスタを0クリアする ----
	CALL	SAFE_RESET

	LD	DE,MSG_DONE1
	CALL	PRINT_STR
	LD	A,(PASS_COUNT)
	CALL	PRINT_HEX
	LD	DE,MSG_DONE2
	CALL	PRINT_STR
	LD	A,(FAIL_COUNT)
	CALL	PRINT_HEX
	LD	DE,MSG_CRLF
	CALL	PRINT_STR

	RET				; MSX-DOSへ復帰

;==============================================================================
; SNAP_HL24 : 現在のHL24(HLレジスタ+HL_Bバンクバイト)をHLとSNAP_BANKへ採取する
;   出力: HL = 現在のHLレジスタ値(呼出し前と不変)
;         (SNAP_BANK) = 現在のHL_Bバンクバイト値
;   Aレジスタは破壊する。
;==============================================================================
SNAP_HL24:
	PUSH	HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(SNAP_BANK),A
	POP	HL
	RET

;==============================================================================
; CHECK24_IX : 24bit値の一致判定 + 画面表示 (メモリ上の実測値と比較)
;   入力: HL = 期待する16bit低位ワード
;         B  = 期待するバンクバイト
;         DE = テスト名文字列へのポインタ ($終端)
;         IX = 実測値が格納された3byteの先頭アドレス (低,高,バンクの順)
;
;   BDOS(CALL BDOS)はレジスタ/フラグの保存を保証しないため、比較に必要な
;   値は最初に全てCHK_EXP_*/CHK_ACT_*のメモリ変数へ退避してから使う。
;   これ以降、HL/B/IXの値そのものには一切依存しない(mmu_test.asmの
;   CHECK_AND_PRINTと同じ安全策)。
;==============================================================================
CHECK24_IX:
	LD	(CHK_EXP_LO),HL
	LD	A,B
	LD	(CHK_EXP_BANK),A
	LD	A,(IX+0)
	LD	(CHK_ACT_LO),A
	LD	A,(IX+1)
	LD	(CHK_ACT_HI),A
	LD	A,(IX+2)
	LD	(CHK_ACT_BANK),A

	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR

	LD	A,(CHK_ACT_LO)
	LD	HL,CHK_EXP_LO
	CP	(HL)
	JR	NZ,CHECK24_FAIL
	LD	A,(CHK_ACT_HI)
	LD	HL,CHK_EXP_HI
	CP	(HL)
	JR	NZ,CHECK24_FAIL
	LD	A,(CHK_ACT_BANK)
	LD	HL,CHK_EXP_BANK
	CP	(HL)
	JR	NZ,CHECK24_FAIL

	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	CHECK24_DONE

CHECK24_FAIL:
	LD	DE,MSG_FAIL
	CALL	PRINT_STR
	LD	A,(CHK_ACT_BANK)
	CALL	PRINT_HEX
	LD	A,(CHK_ACT_HI)
	CALL	PRINT_HEX
	LD	A,(CHK_ACT_LO)
	CALL	PRINT_HEX
	LD	DE,MSG_WANT
	CALL	PRINT_STR
	LD	A,(CHK_EXP_BANK)
	CALL	PRINT_HEX
	LD	A,(CHK_EXP_HI)
	CALL	PRINT_HEX
	LD	A,(CHK_EXP_LO)
	CALL	PRINT_HEX
	LD	E,')'
	LD	C,2
	CALL	BDOS
	LD	HL,FAIL_COUNT
	INC	(HL)

CHECK24_DONE:
	LD	DE,MSG_CRLF
	CALL	PRINT_STR
	RET

; 終了前の安全な状態復元: 使用したバンクレジスタを0クリアする
SAFE_RESET:
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,024H		; LD HL_B,A
	RET

;==============================================================================
; 文字出力ユーティリティ (MMUTest/mmu_test.asm と同じ構成)
;==============================================================================

; DE = $終端文字列へのポインタ
PRINT_STR:
	LD	C,9
	CALL	BDOS
	RET

; Aレジスタの値を16進2桁で表示する
PRINT_HEX:
	PUSH	AF
	RRCA
	RRCA
	RRCA
	RRCA
	CALL	PRINT_NIBBLE
	POP	AF
PRINT_NIBBLE:
	AND	0FH
	CP	10
	JR	C,PRINT_NIBBLE_DIGIT
	ADD	A,'A'-10
	JR	PRINT_NIBBLE_OUT
PRINT_NIBBLE_DIGIT:
	ADD	A,'0'
PRINT_NIBBLE_OUT:
	LD	E,A
	LD	C,2
	CALL	BDOS
	RET

;==============================================================================
; データ領域
;==============================================================================
MSG_BANNER:
	DEFB	"Z80X24 Phase7 LD24 register-transfer test",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1A:	DEFB	"Test1a ED06 LD24 HL,BC dest HL24$"
MSG_T1B:	DEFB	"Test1b ED06 LD24 HL,BC src BC24 unchanged$"
MSG_T2A:	DEFB	"Test2a ED0E LD24 BC,HL dest BC24$"
MSG_T2B:	DEFB	"Test2b ED0E LD24 BC,HL src HL24 unchanged$"
MSG_T3A:	DEFB	"Test3a ED16 LD24 HL,DE dest HL24$"
MSG_T3B:	DEFB	"Test3b ED16 LD24 HL,DE src DE24 unchanged$"
MSG_T4A:	DEFB	"Test4a ED1E LD24 DE,HL dest DE24$"
MSG_T4B:	DEFB	"Test4b ED1E LD24 DE,HL src HL24 unchanged$"
MSG_T5:		DEFB	"Test5 ED35/36 MSP24 round trip$"
MSG_T6:		DEFB	"Test6 ED9B/9C IVR24 round trip$"
MSG_T7:		DEFB	"Test7 ED9E/9F NVR24 round trip$"
MSG_T8:		DEFB	"Test8 F register unchanged by LD24$"

MSG_COLON:	DEFB	": $"
MSG_PASS:	DEFB	"PASS$"
MSG_FAIL:	DEFB	"FAIL (got=$"
MSG_WANT:	DEFB	", want=$"
MSG_CRLF:	DEFB	13,10,"$"

MSG_DONE1:	DEFB	13,10,"PASS=$"
MSG_DONE2:	DEFB	" FAIL=$"

; --- SNAP_HL24作業領域 ---
SNAP_BANK:	DEFS	1

; --- CHECK24_IX用の退避領域 (BDOS呼出しでレジスタが破壊されても ----
; --- 安全に比較できるよう、期待値・実測値をここへ一旦コピーする) ----
CHK_EXP_LO:	DEFS	1
CHK_EXP_HI:	DEFS	1
CHK_EXP_BANK:	DEFS	1
CHK_ACT_LO:	DEFS	1
CHK_ACT_HI:	DEFS	1
CHK_ACT_BANK:	DEFS	1

; --- 各テストの実測値バッファ (低位word 2byte + バンクbyte 1byte の順) ---
T1_HL_LO:	DEFS	2
T1_HL_BANK:	DEFS	1
T1_BC_LO:	DEFS	2
T1_BC_BANK:	DEFS	1
T2_BC_LO:	DEFS	2
T2_BC_BANK:	DEFS	1
T2_HL_LO:	DEFS	2
T2_HL_BANK:	DEFS	1
T3_HL_LO:	DEFS	2
T3_HL_BANK:	DEFS	1
T3_DE_LO:	DEFS	2
T3_DE_BANK:	DEFS	1
T4_DE_LO:	DEFS	2
T4_DE_BANK:	DEFS	1
T4_HL_LO:	DEFS	2
T4_HL_BANK:	DEFS	1
T5_HL_LO:	DEFS	2
T5_HL_BANK:	DEFS	1
T6_HL_LO:	DEFS	2
T6_HL_BANK:	DEFS	1
T7_HL_LO:	DEFS	2
T7_HL_BANK:	DEFS	1

F_BEFORE:	DEFS	1
F_AFTER:	DEFS	1

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
