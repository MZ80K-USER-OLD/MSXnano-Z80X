;==============================================================================
; MMUTEST.ASM - Z80X24 Phase5 "MMU実機検証" 実機テストプログラム (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase5「MMU実機検証」を、実機/エミュレータ上のMSX-DOS2から起動して確認する
; ためのテストプログラムです。
;
;   doc/jpn/doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md セクション7 "Phase 5"
;   fpga/G80A/test/tb_phase5_mmu_mapping.vhd (同じシナリオのGHDLシミュレーション版)
;
; 検証内容 (tb_phase5_mmu_mapping.vhd と同じシナリオ):
;   Test1-3: 物理bank 01h/02h/03hへパターン(11h/22h/33h)を書き込み、
;            対応する論理bankからの読み出しが一致するか確認する。
;   Test4-6: Test1-3の書込み後、まとめて再読出しし、他バンクへの書込みで
;            値が壊れていないか(バンク間の取り違え/折り返しが無いか)確認する。
;   Test7  : エイリアス試験。論理bank 01h/02hを同じ物理bank 05hへ再マッピング
;            し、どちらの論理bank経由でも同じ値が読み書きできることを確認する。
;   Test8  : MMU_DATA[n]=00hエイリアス試験。論理bank 04hを明示的に物理00h
;            (= 既存のMSX互換64KB空間そのもの) へマッピングし、通常のM0同様の
;            読み書きになることを確認する。
;
; 安全設計上の注意:
;   - M1モード(ED 91)でバンクレジスタを設定した状態でBIOS/DOSコールを行うと、
;     BIOS/DOS側が内部で使う(HL)等のアクセスまで誤って拡張メモリへリダイレクト
;     されてしまう危険があるため、本プログラムは「DI→M1→1回だけメモリアクセス
;     →M0→EI」という最小区間だけ拡張アドレッシングを使い、画面出力やBDOS呼出し
;     は必ずM0に戻してから行う(EXT_WRITE/EXT_READ参照)。
;   - 拡張メモリアクセスで使用する物理bankは 01h〜03h, 05h のみ。これは
;     fpga/top.v の CPU_SDRAM_BASE(0x640000)+物理bank*64KBで、既存のMemory
;     Mapper(0x000000-)やMegaRAM(0x400000-)とは重ならない安全な領域
;     (0x650000以降)に収まる (詳細はdoc/jpn/SDRAMメモリマップ.md 2.2章)。
;   - プログラム終了前に必ずM0へ戻し、バンクレジスタも0クリアしてからDOSへ
;     復帰する(SAFE_RESET参照)。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `MMUTEST` と入力する。
;==============================================================================

	org	$0100

;------------------------------------------------------------------------------
; MSX-DOS / BDOS
;------------------------------------------------------------------------------
BDOS		EQU	0005H		; DOS function entry

;------------------------------------------------------------------------------
; Z80X24 独自オペコード (標準Z80アセンブラには無いため DEFB で直接発行する)
;------------------------------------------------------------------------------
; ED 90        SET_M0          完全Z80互換モードへ
; ED 91        SET_M1          データアクセスのみ24bit拡張モードへ
; ED 04/0C     LD BC_B,A / LD A,BC_B
; ED 14/1C     LD DE_B,A / LD A,DE_B
; ED 24/2C     LD HL_B,A / LD A,HL_B
; ED 05/0D     LD IX_B,A / LD A,IX_B
; ED 15/1D     LD IY_B,A / LD A,IY_B
;------------------------------------------------------------------------------
PORT_MMU_INDEX	EQU	0F0H		; MMU_INDEX I/Oポート
PORT_MMU_DATA	EQU	0F1H		; MMU_DATA  I/Oポート

;==============================================================================
; エントリポイント
;==============================================================================
START:
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ---- Test1: 論理bank01h -> 物理bank01h, パターン11h ----
	LD	B,1
	LD	C,1
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[01h] = 01h
	LD	A,11H
	LD	(EXT_VALUE),A
	LD	A,1
	CALL	DO_WRITE_READ_0000	; EXT_BANK=1, 0000hへ書込んで読み戻す
	LD	A,11H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T1
	CALL	CHECK_AND_PRINT

	; ---- Test2: 論理bank02h -> 物理bank02h, パターン22h ----
	LD	B,2
	LD	C,2
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[02h] = 02h
	LD	A,22H
	LD	(EXT_VALUE),A
	LD	A,2
	CALL	DO_WRITE_READ_0000
	LD	A,22H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T2
	CALL	CHECK_AND_PRINT

	; ---- Test3: 論理bank03h -> 物理bank03h, パターン33h ----
	LD	B,3
	LD	C,3
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[03h] = 03h
	LD	A,33H
	LD	(EXT_VALUE),A
	LD	A,3
	CALL	DO_WRITE_READ_0000
	LD	A,33H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T3
	CALL	CHECK_AND_PRINT

	; ---- Test4-6: 書込み後にまとめて再読出し (バンク間の取り違え/折返し確認) ----
	LD	A,1
	LD	(EXT_BANK),A
	LD	HL,0000H
	LD	(EXT_OFFSET),HL
	CALL	EXT_READ
	LD	A,11H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T4
	CALL	CHECK_AND_PRINT

	LD	A,2
	LD	(EXT_BANK),A
	CALL	EXT_READ
	LD	A,22H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T5
	CALL	CHECK_AND_PRINT

	LD	A,3
	LD	(EXT_BANK),A
	CALL	EXT_READ
	LD	A,33H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T6
	CALL	CHECK_AND_PRINT

	; ---- Test7: エイリアス試験 (論理01h/02hを同じ物理05hへ再マッピング) ----
	LD	B,1
	LD	C,5
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[01h] = 05h
	LD	B,2
	LD	C,5
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[02h] = 05h

	LD	A,1
	LD	(EXT_BANK),A
	LD	HL,0000H
	LD	(EXT_OFFSET),HL
	LD	A,99H
	LD	(EXT_VALUE),A
	CALL	EXT_WRITE		; 論理01h(=物理05h)へ書込み

	LD	A,2
	LD	(EXT_BANK),A
	CALL	EXT_READ		; 論理02h(=物理05hのはず)から読出し
	LD	A,99H
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T7
	CALL	CHECK_AND_PRINT

	; ---- Test8: MMU_DATA[04h]=00h エイリアス試験 ----
	LD	B,4
	LD	C,0
	CALL	MMU_WRITE_ENTRY		; MMU_DATA[04h] = 00h (明示的に設定)

	LD	A,4
	LD	(EXT_BANK),A
	LD	HL,LEGACY_MARKER
	LD	(EXT_OFFSET),HL
	LD	A,5AH
	LD	(EXT_VALUE),A
	CALL	EXT_WRITE		; 論理04h(=物理00h, 通常の64KB空間)へ書込み

	LD	A,(LEGACY_MARKER)	; 通常のM0相当アクセスで直接読み出す
	LD	(EXT_RESULT),A
	LD	A,5AH
	LD	(EXT_EXPECT),A
	LD	DE,MSG_T8
	CALL	CHECK_AND_PRINT

	; ---- 安全のため、終了前に必ずM0へ戻しバンクレジスタを0クリアする ----
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
; MMU_DATA設定
;   入力: B = MMU_INDEXへ設定する値 (対象の論理bank番号)
;         C = MMU_DATAへ設定する値 (対応させたい物理bank番号)
;==============================================================================
MMU_WRITE_ENTRY:
	LD	A,B
	OUT	(PORT_MMU_INDEX),A
	LD	A,C
	OUT	(PORT_MMU_DATA),A
	RET

; Test1-3共通処理。
; 入力: A = 論理bank番号, (EXT_VALUE) = 書込みたいパターン(呼出し元が設定済み)
; 動作: (EXT_BANK)=A, (EXT_OFFSET)=0000hを設定してからEXT_WRITE/EXT_READを行う
DO_WRITE_READ_0000:
	LD	(EXT_BANK),A
	LD	HL,0000H
	LD	(EXT_OFFSET),HL
	CALL	EXT_WRITE
	CALL	EXT_READ
	RET

;==============================================================================
; 拡張メモリ書込み / 読出し
;   パラメータはすべて固定メモリ変数経由で渡す。
;   DI/EIで割り込みを止め、M1へ切替えて(HL)アクセスを1回だけ行い、
;   直後にM0へ戻すことで、BIOS/DOS側コードが拡張アドレッシングの影響を
;   受けないようにする。
;==============================================================================

; 入力: (EXT_BANK)=論理bank, (EXT_OFFSET)=オフセット, (EXT_VALUE)=書込む値
EXT_WRITE:
	DI
	DEFB	0EDH,091H		; SET_M1
	LD	A,(EXT_BANK)
	DEFB	0EDH,024H		; LD HL_B,A
	LD	HL,(EXT_OFFSET)
	LD	A,(EXT_VALUE)
	LD	(HL),A
	DEFB	0EDH,090H		; SET_M0
	EI
	RET

; 入力: (EXT_BANK)=論理bank, (EXT_OFFSET)=オフセット
; 出力: (EXT_RESULT)=読み出した値
EXT_READ:
	DI
	DEFB	0EDH,091H		; SET_M1
	LD	A,(EXT_BANK)
	DEFB	0EDH,024H		; LD HL_B,A
	LD	HL,(EXT_OFFSET)
	LD	A,(HL)
	LD	(EXT_RESULT),A
	DEFB	0EDH,090H		; SET_M0
	EI
	RET

; 終了前の安全な状態復元: M0へ戻し、全バンクレジスタを0クリアする
SAFE_RESET:
	DI
	DEFB	0EDH,090H		; SET_M0
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,005H		; LD IX_B,A
	DEFB	0EDH,015H		; LD IY_B,A
	EI
	RET

;==============================================================================
; 結果判定 + 画面表示
;   入力: DE = テスト名文字列へのポインタ ($終端)
;         (EXT_RESULT) = 実際の値, (EXT_EXPECT) = 期待値
;==============================================================================
CHECK_AND_PRINT:
	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR

	LD	A,(EXT_RESULT)
	LD	HL,EXT_EXPECT
	CP	(HL)
	JR	NZ,CAP_FAIL

	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	CAP_DONE

CAP_FAIL:
	LD	DE,MSG_FAIL
	CALL	PRINT_STR
	LD	A,(EXT_RESULT)
	CALL	PRINT_HEX
	LD	DE,MSG_WANT
	CALL	PRINT_STR
	LD	A,(EXT_EXPECT)
	CALL	PRINT_HEX
	LD	E,')'
	LD	C,2
	CALL	BDOS
	LD	HL,FAIL_COUNT
	INC	(HL)

CAP_DONE:
	LD	DE,MSG_CRLF
	CALL	PRINT_STR
	RET

;==============================================================================
; 文字出力ユーティリティ
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
	DEFB	"Z80X24 Phase5 MMU hardware test",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1:	DEFB	"Test1 bank01->phys01 (11h)$"
MSG_T2:	DEFB	"Test2 bank02->phys02 (22h)$"
MSG_T3:	DEFB	"Test3 bank03->phys03 (33h)$"
MSG_T4:	DEFB	"Test4 reread bank01 (11h)$"
MSG_T5:	DEFB	"Test5 reread bank02 (22h)$"
MSG_T6:	DEFB	"Test6 reread bank03 (33h)$"
MSG_T7:	DEFB	"Test7 alias bank01/02->phys05$"
MSG_T8:	DEFB	"Test8 MMU[04]=00 legacy alias$"

MSG_COLON:	DEFB	": $"
MSG_PASS:	DEFB	"PASS$"
MSG_FAIL:	DEFB	"FAIL (got=$"
MSG_WANT:	DEFB	", want=$"
MSG_CRLF:	DEFB	13,10,"$"

MSG_DONE1:	DEFB	13,10,"PASS=$"
MSG_DONE2:	DEFB	" FAIL=$"

; --- 拡張メモリアクセス用パラメータ (EXT_WRITE/EXT_READで使用) ---
EXT_BANK:	DEFS	1
EXT_OFFSET:	DEFS	2
EXT_VALUE:	DEFS	1
EXT_RESULT:	DEFS	1
EXT_EXPECT:	DEFS	1

; --- Test8用: 本プログラム自身のデータ領域内のスクラッチ変数 ---
;     論理bank04h->物理00h(エイリアス)の書込み先として使う。
;     通常のMSX 64KB空間そのものなので、ここに書いても安全。
LEGACY_MARKER:	DEFS	1

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
