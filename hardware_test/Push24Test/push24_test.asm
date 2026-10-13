;==============================================================================
; PUSH24_TEST.ASM - Z80X24 Phase9 "PUSH24/POP24" 実機テストプログラム (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase9「PUSH24/POP24」を、実機/エミュレータ上のMSX-DOS(2)から起動して
; 確認するためのテストプログラムです。
;
;   doc/jpn/MSX_T80_24bit化_実装手順_V2_2026-10-05.md セクション11 "Phase 9"
;   doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md セクション9 "Stack"
;   fpga/G80A/test/tb_phase9_push24_pop24.vhd (同じシナリオのGHDLシミュレーション版)
;
; 検証内容 (tb_phase9_push24_pop24.vhd と同じシナリオを実機向けに再構成):
;   Test1: ED C5/C1 PUSH24 BC / POP24 BC 往復試験。BC24をPUSH24→破壊→POP24
;          した後、元の値に戻ること、およびMSP24も元の値に戻ることを確認する。
;   Test2: レジスタをまたぐ往復試験。PUSH24 BC(パターンA) の直後にPOP24 DE
;          を行い、DE24がパターンAと一致することを確認する(データが実際に
;          メモリ経由で転送されていることの証明。単なるレジスタ別名化では
;          ないことを確認する)。
;   Test3: ED D5/D1 PUSH24 DE / POP24 DE 往復試験。
;   Test4: ED E5/E1 PUSH24 HL / POP24 HL 往復試験。
;   Test5: LIFO(後入れ先出し)順序試験。BC/DE/HLの順でPUSH24し、BC/DE/HLの
;          順でPOP24すると、最後にPUSHしたHLの値がBCへ、DEの値がDEへ、最初に
;          PUSHしたBCの値がHLへ、という「逆順」で復元されることを確認する。
;   Test6: いずれか1つのPUSH24/POP24命令の前後でF(フラグ)レジスタが変化
;          しないことを確認する(仕様上「F不変」、Z80標準のPUSH/POPと同様)。
;
; 【既知の問題・本プログラムの対象外】bank境界またぎPUSH24/POP24は未検証:
;   当初はMSP24=02:0001hからPUSH24 HLを実行し、3回のデクリメントで
;   02:0001->02:0000->01:FFFF(bank borrow)->01:FFFEとbankをまたぐ試験
;   (旧Test6)を含めていたが、実機検証でTest5c完了直後にシステムが
;   フリーズする現象が再現した(GHDLシミュレーション(tb_phase9_push24_
;   pop24.vhd)ではこのシナリオは問題なくPASSしていたため、これは
;   実機固有の問題と判断される)。1命令内で複数の異なる物理bankへ
;   連続して書き込む(=SD-RAMコントローラが応答する前に物理bankが
;   切り替わる)経路は、Phase3/5の既存拡張メモリアクセス(1命令につき
;   拡張アクセス1回のみ)では一度も検証されておらず、本プロジェクトの
;   SD-RAMコントローラ(fpga/src/memory.v・sdram.v)にはCPU側へのWAIT
;   状態生成機構が存在しない(fpga/top.vのex_bus_wait_nは常時'1'固定)
;   ため、bankをまたぐ書込みがコントローラの内部処理時間を超過し、
;   誤ったアドレス(bank00h=実行中プログラム自身の空間や、BIOS/割込み
;   ベクタ領域等)を破壊した可能性が疑われる。この問題は未解決であり、
;   根本原因の特定にはfpga/src/memory.v・sdram.vのSD-RAMタイミングの
;   詳細な調査が必要。したがって本プログラムはbank境界をまたぐPUSH24/
;   POP24を一切使用しない(全テストで単一物理bank内に留める)よう修正
;   済みである。詳細はAVAILABLE_INSTRUCTIONS.mdセクション7、および
;   README.mdの「既知の問題」を参照。
;
; 安全設計上の注意:
;   - PUSH24/POP24はMSP24(ED35/ED36で読み書きするPhase7由来の専用24bitポ
;     インタ)を使用し、通常のZ80 16bit SP(MSX-DOS/BIOSが使うスタック)とは
;     完全に独立している。そのためBDOS呼出しやMSX標準の割り込み処理が、
;     MSP24やPUSH24/POP24で書き込んだ拡張メモリへ誤って触れる心配はなく、
;     MMUTestのようなDI/EI・モード切替は一切不要である(mode24設定にも
;     依存しない。CPU仕様書V8のとおりM0/M1/M2いずれでも常時full 24bitで
;     動作する)。
;   - PUSH24/POP24が実際にメモリへ書き込む先は、MSP24のbankバイトが
;     指す物理バンクで決まる。本プログラムが使用する物理bankは
;     01h/02h/03h/04hのみで、これはfpga/top.vのCPU_SDRAM_BASE(0x640000)
;     経由で、既存のMemory Mapper(0x000000-)やMegaRAM(0x400000-)とは
;     重ならない安全な領域(0x650000以降)に収まる(詳細はdoc/jpn/
;     SDRAMメモリマップ.md 2.2章)。上記「既知の問題」のとおり、本
;     プログラムは1つのPUSH24/POP24呼出しの中で物理bankが変化する
;     ケースを一切作らない(常に単一のbank内で完結させる)よう設計して
;     いる。bank00hはこの経路を通らず常時安全だが、実行中のプログラム
;     自身の64KB空間そのものを指すため、誤って書き込むと致命的な
;     クラッシュを招く(本プログラムは意図的にbank00hへの書込みを
;     一切発生させない)。
;   - プログラム終了前に、使用したBC/DE/HLバンクレジスタを0クリアしてから
;     MSX-DOSへ復帰する(SAFE_RESET参照。MSP24自体はPhase7のLD24Testと
;     同様、他のMSX-DOS/BIOSコードが参照することのない専用レジスタなので
;     明示的なクリアは行わない)。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `P24TEST` と入力する。
;   (実行ファイル名はMSX-DOSの8.3形式に合わせ P24TEST.COM としている。
;    "PUSH24TEST" は10文字でMSX-DOSのファイル名8文字制限を超えるため)
;==============================================================================

	org	$0100

;------------------------------------------------------------------------------
; MSX-DOS / BDOS
;------------------------------------------------------------------------------
BDOS		EQU	0005H		; DOS function entry
BDOS_TERM0	EQU	0		; BDOS function 0: プログラム終了、MSX-DOSへ復帰

;------------------------------------------------------------------------------
; Z80X24 独自オペコード (標準Z80アセンブラには無いため DEFB で直接発行する)
;------------------------------------------------------------------------------
; ED 04/0C     LD BC_B,A / LD A,BC_B           (Phase1)
; ED 14/1C     LD DE_B,A / LD A,DE_B           (Phase1)
; ED 24/2C     LD HL_B,A / LD A,HL_B           (Phase1)
; ED 35        LD24 MSP,HL                     (Phase7, MSP24の設定に使用)
; ED 36        LD24 HL,MSP                     (Phase7, MSP24の読出しに使用)
; ED C5        PUSH24 BC                       (Phase9, 本プログラムの対象)
; ED C1        POP24 BC                        (Phase9, 本プログラムの対象)
; ED D5        PUSH24 DE                       (Phase9, 本プログラムの対象)
; ED D1        POP24 DE                        (Phase9, 本プログラムの対象)
; ED E5        PUSH24 HL                       (Phase9, 本プログラムの対象)
; ED E1        POP24 HL                        (Phase9, 本プログラムの対象)
;------------------------------------------------------------------------------

;==============================================================================
; エントリポイント
;==============================================================================
START:
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ==== 共通準備: MSP24 = 01:E000h を初期スタック位置とする ====
	LD	HL,0E000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL

	; ==== Test1: ED C5/C1 PUSH24 BC / POP24 BC 往復試験 (01:1122h) ====
	LD	BC,1122H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,0C5H		; PUSH24 BC
	LD	BC,0000H
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A (clobber)
	DEFB	0EDH,0C1H		; POP24 BC
	LD	(T1_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T1_BC_BANK),A

	LD	HL,1122H
	LD	B,01H
	LD	DE,MSG_T1
	LD	IX,T1_BC_LO
	CALL	CHECK24_IX

	; ==== Test2: PUSH24 BC(02:3344h) -> POP24 DE (レジスタをまたいだ往復) ====
	LD	BC,3344H
	LD	A,02H
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,0C5H		; PUSH24 BC
	LD	DE,0000H
	XOR	A
	DEFB	0EDH,014H		; LD DE_B,A (clobber)
	DEFB	0EDH,0D1H		; POP24 DE
	LD	(T2_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T2_DE_BANK),A

	LD	HL,3344H
	LD	B,02H
	LD	DE,MSG_T2
	LD	IX,T2_DE_LO
	CALL	CHECK24_IX

	; ==== Test3: ED D5/D1 PUSH24 DE / POP24 DE 往復試験 (03:5566h) ====
	LD	DE,5566H
	LD	A,03H
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,0D5H		; PUSH24 DE
	LD	DE,0000H
	XOR	A
	DEFB	0EDH,014H		; LD DE_B,A (clobber)
	DEFB	0EDH,0D1H		; POP24 DE
	LD	(T3_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T3_DE_BANK),A

	LD	HL,5566H
	LD	B,03H
	LD	DE,MSG_T3
	LD	IX,T3_DE_LO
	CALL	CHECK24_IX

	; ==== Test4: ED E5/E1 PUSH24 HL / POP24 HL 往復試験 (04:7788h) ====
	LD	HL,7788H
	LD	A,04H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,0E5H		; PUSH24 HL
	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,0E1H		; POP24 HL
	CALL	SNAP_HL24
	LD	(T4_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T4_HL_BANK),A

	LD	HL,7788H
	LD	B,04H
	LD	DE,MSG_T4
	LD	IX,T4_HL_LO
	CALL	CHECK24_IX

	; ==== Test5: LIFO順序試験 ====
	; PUSH24 BC(01:1111h) -> PUSH24 DE(02:2222h) -> PUSH24 HL(03:3333h)
	; POP24 BC(HLの値を得るはず) -> POP24 DE(DE自身の値を得るはず)
	; -> POP24 HL(BCの値を得るはず)
	LD	BC,1111H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,0C5H		; PUSH24 BC
	LD	DE,2222H
	LD	A,02H
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,0D5H		; PUSH24 DE
	LD	HL,3333H
	LD	A,03H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,0E5H		; PUSH24 HL

	DEFB	0EDH,0C1H		; POP24 BC  (expect 03:3333h, HLの値)
	LD	(T5_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T5_BC_BANK),A
	DEFB	0EDH,0D1H		; POP24 DE  (expect 02:2222h, DE自身の値)
	LD	(T5_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T5_DE_BANK),A
	DEFB	0EDH,0E1H		; POP24 HL  (expect 01:1111h, BCの値)
	CALL	SNAP_HL24
	LD	(T5_HL_LO),HL
	LD	A,(SNAP_BANK)
	LD	(T5_HL_BANK),A

	LD	HL,3333H
	LD	B,03H
	LD	DE,MSG_T5A
	LD	IX,T5_BC_LO
	CALL	CHECK24_IX
	LD	HL,2222H
	LD	B,02H
	LD	DE,MSG_T5B
	LD	IX,T5_DE_LO
	CALL	CHECK24_IX
	LD	HL,1111H
	LD	B,01H
	LD	DE,MSG_T5C
	LD	IX,T5_HL_LO
	CALL	CHECK24_IX

	; ==== Test6: PUSH24/POP24の前後でFレジスタが不変であることを確認 ====
	; (MSP24はTest5終了時点で01:E000hへ既に復帰しているはずだが、念のため
	;  明示的に再設定しておく)
	LD	HL,0E000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL

	SCF				; 既知のフラグ状態を作る
	PUSH	AF
	POP	BC			; C = F (before)
	LD	A,C
	LD	(F_BEFORE),A
	LD	A,07H
	DEFB	0EDH,004H		; LD BC_B,A (任意の値、PUSH24/POP24の対象として使う)
	DEFB	0EDH,0C5H		; PUSH24 BC
	DEFB	0EDH,0C1H		; POP24 BC
	PUSH	AF
	POP	BC			; C = F (after)
	LD	A,C
	LD	(F_AFTER),A

	LD	DE,MSG_T6
	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR
	LD	A,(F_BEFORE)
	LD	HL,F_AFTER
	CP	(HL)
	JR	NZ,T6_FAIL
	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	T6_DONE
T6_FAIL:
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
T6_DONE:
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

	; MSX-DOSのコマンドプロンプトへ確実に復帰する。PUSH24/POP24は専用の
	; MSP24ポインタのみを使い、通常のZ80 16bit SP(MSX-DOSが呼出し時に
	; 積んだ戻り番地)には一切触れていないため単純なRETでも正しく動作
	; するはずだが、BDOS function 0 (Program terminate)を明示的に呼ぶ
	; ことで、スタックの状態に依存せず常にMSX-DOSへ戻ることを保証する。
	LD	C,BDOS_TERM0
	CALL	BDOS

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
;   値は最初に全てCHK_EXP_*/CHK_ACT_*のメモリ変数へ退避してから使う
;   (LD24Test/ld24_test.asmのCHECK24_IXと同一のルーチン)。
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
; (MSP24自体は他のMSX-DOS/BIOSコードが参照することのない専用レジスタ
;  なので、LD24Test同様クリアしない)
SAFE_RESET:
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,024H		; LD HL_B,A
	RET

;==============================================================================
; 文字出力ユーティリティ (MMUTest/LD24Test と同じ構成)
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
	DEFB	"Z80X24 Phase9 PUSH24/POP24 test",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1:		DEFB	"Test1 ED C5/C1 PUSH24/POP24 BC round trip$"
MSG_T2:		DEFB	"Test2 PUSH24 BC -> POP24 DE cross-register$"
MSG_T3:		DEFB	"Test3 ED D5/D1 PUSH24/POP24 DE round trip$"
MSG_T4:		DEFB	"Test4 ED E5/E1 PUSH24/POP24 HL round trip$"
MSG_T5A:	DEFB	"Test5a LIFO: POP24 BC got HL's value$"
MSG_T5B:	DEFB	"Test5b LIFO: POP24 DE got DE's value$"
MSG_T5C:	DEFB	"Test5c LIFO: POP24 HL got BC's value$"
MSG_T6:		DEFB	"Test6 F register unchanged by PUSH24/POP24$"

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
T1_BC_LO:	DEFS	2
T1_BC_BANK:	DEFS	1
T2_DE_LO:	DEFS	2
T2_DE_BANK:	DEFS	1
T3_DE_LO:	DEFS	2
T3_DE_BANK:	DEFS	1
T4_HL_LO:	DEFS	2
T4_HL_BANK:	DEFS	1
T5_BC_LO:	DEFS	2
T5_BC_BANK:	DEFS	1
T5_DE_LO:	DEFS	2
T5_DE_BANK:	DEFS	1
T5_HL_LO:	DEFS	2
T5_HL_BANK:	DEFS	1

F_BEFORE:	DEFS	1
F_AFTER:	DEFS	1

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
