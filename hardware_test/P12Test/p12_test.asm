;==============================================================================
; P12_TEST.ASM - Z80X24 Phase12 "モード間制御" 実機テストプログラム (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase12「モード間制御」(JP.M0/M1/M2, CALL.M0/M1/M2, RET.M) を、実機/
; エミュレータ上のMSX-DOS(2)から起動して確認するためのテストプログラムです。
;
;   doc/jpn/doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md セクション14 "Phase 12"
;   AVAILABLE_INSTRUCTIONS.md セクション10 "モード間制御"
;   fpga/G80A/test/tb_phase12_mode_control.vhd (同じ対象命令のGHDLシミュレーション版)
;
; 検証内容:
;   Test1a/1b: JP.M0 addr16 (ED 93)。M1からM0へ切替わることを、切替え直後に
;              行う(HL)書込みが拡張bankを無視した"flat"な書込みになる
;              (=bank01hへは書かれず、bank00hへ書かれる)ことで確認する。
;              (mode24自体を直接読み出す命令は存在しないため、アドレッシング
;              挙動の違いを通じた間接的な確認方法を用いる。)
;   Test2a/2b: JP.M1 addr16 (ED 94)。M0からM1へ切替わることを、Test1と逆方向
;              の書込み挙動(bank01hへ"bank対応"書込みされる)で確認する。
;   Test3    : JP.M2 addr24 (ED 9B)。物理bank02hへ実際にコードを書き込み
;              (bank-aware (HL)書込みで1byteずつコピー)、そこへJP.M2で
;              ジャンプして実行させ、専用のマーカー変数が書き換わることで
;              「正しい物理bankへジャンプして実行した」ことを確認する
;              (実行マーカー方式)。コピー先の物理bankコードは、最後に
;              JP.M1で安全にbank00hの続きへ戻ってくる。
;   Test4    : CALL.M0 addr16 (ED 96) + RET.M (ED 99)。bank00h内で完結する
;              呼出し/復帰往復試験。呼び出し先がマーカー変数を書き換え、
;              RET.Mで正しく復帰することを確認する。
;   Test5    : CALL.M1 addr16 (ED 97) + RET.M。Test4と同じ形だがCALL.M1版。
;   Test6    : CALL.M2 addr24 (ED 98) + RET.M。物理bank02hへコードをコピー
;              し、CALL.M2で呼び出し、呼び出し先がRET.Mで復帰することを
;              確認する(実行マーカー方式 + 往復)。CALL.M2はPhase12の中でも
;              最後に実装された命令で(1opcode+3byte addr24フェッチ+4byte
;              戻りフレームpush=8 MCycle必要、MCycleを3bit→4bitへ拡張して
;              実装。詳細はdoc/jpn/T80コア内部に残っていた潜在バグ_Phase11-
;              12での発見と修正.md参照)、本テストでそれを実機初検証する。
;
; 安全設計上の注意 (MMUTestの先例に厳密に従う):
;   - M1/M2モードでバンクレジスタを設定した状態のままBIOS/DOSコールを行うと、
;     BIOS/DOS側が内部で使う(HL)等のアクセスまで拡張メモリへ誤ってリダイレクト
;     される危険がある。さらにPhase13(M2割込み拡張)は未実装のため、M2で
;     PCが拡張bankを指している間に割込みが入ると、割込みベクタ取得の24bit
;     対応が無く未定義動作になる恐れがある。そのため本プログラムは、
;     「DI→SET_M1/M2→(モード切替命令本体のテスト、BDOS呼出しは一切行わない)
;     →SET_M0→EI」という区間だけ拡張アドレッシング/M1/M2モードを使い、
;     画面出力やBDOS呼出しは必ずM0へ戻してEIした後に行う。
;   - JP.M2/CALL.M2で実際にジャンプ・コールする先の物理bank02hのコードは、
;     本プログラム自身の(bank00hの)データ領域内に用意したテンプレート
;     バイト列を、bank-aware (HL)書込みで1byteずつコピーしたものであり、
;     コピー先アドレス(TARGET_CODE=8000h)はbank02hという本プログラムの
;     64KB空間と重ならない物理bankの中の未使用オフセットなので、本プログラム
;     自身やBIOS/DOSの既存コードを破壊する心配はない。
;   - 拡張メモリアクセスで使用する物理bankは01h(MSP24スタック/スクラッチ)・
;     02h(JP.M2/CALL.M2コピー先コード)のみ。これはfpga/top.vの
;     CPU_SDRAM_BASE(0x640000)経由で、既存のMemory Mapper(0x000000-)や
;     MegaRAM(0x400000-)とは重ならない安全な領域(0x650000以降、詳細は
;     doc/jpn/SDRAMメモリマップ.md 2.2章)に収まる。
;   - CALL.M0/M1/M2・RET.Mが使うMSP24は01:E000hに設定する(Push24Test等と
;     同じ安全な初期値)。PUSH24/POP24と異なりCALL.Mxの4byte戻りフレーム
;     pushは単一物理bank内で完結する(MSP24がE000hからDFFChまでしか動かず、
;     bank境界をまたがない)ため、Push24Test README記載の「bank境界またぎ
;     PUSH24/POP24で実機フリーズ」という既知の問題には抵触しない設計。
;   - プログラム終了前に、必ずM0へ戻し使用したバンクレジスタを0クリア
;     してからMSX-DOSへ復帰する(SAFE_RESET参照)。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `P12TEST` と入力する。
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
; ED 90        SET_M0                          完全Z80互換モードへ
; ED 91        SET_M1                          データアクセスのみ24bit拡張モードへ
; ED 92        SET_M2                          24bitネイティブモードへ
; ED 24/2C     LD HL_B,A / LD A,HL_B           (Phase1, HLバンクレジスタ)
; ED 35        LD24 MSP,HL                     (Phase7, MSP24の設定に使用)
; ED 93        JP.M0 addr16                    (Phase12, 本プログラムの対象)
; ED 94        JP.M1 addr16                    (Phase12, 本プログラムの対象)
; ED 9B        JP.M2 addr24                    (V16.1, 本プログラムの対象)
; ED 96        CALL.M0 addr16                  (Phase12, 本プログラムの対象)
; ED 97        CALL.M1 addr16                  (Phase12, 本プログラムの対象)
; ED 98        CALL.M2 addr24                  (Phase12, 本プログラムの対象)
; ED 99        RET.M                           (Phase12, 本プログラムの対象)
;------------------------------------------------------------------------------
TARGET_CODE	EQU	08000H		; JP.M2/CALL.M2コピー先 (物理bank02h内オフセット)

;==============================================================================
; エントリポイント
;==============================================================================
START:
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ==== 共通準備: MSP24 = 01:E000h (単純なレジスタ転送、メモリアクセス
	;      を伴わないためDI保護は不要。Push24Test/LD24Testと同じ初期値) ====
	LD	HL,0E000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL

	;==========================================================
	; Test1: JP.M0 addr16 (M1->M0)
	;==========================================================
	DI
	DEFB	0EDH,091H		; SET_M1 (前提条件: M1から開始)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0)
	LD	HL,SCRATCH1
	LD	(HL),A			; bank00h:SCRATCH1 = 00h
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	HL,SCRATCH1
	XOR	A
	LD	(HL),A			; bank01h:SCRATCH1 = 00h
					; (HL_B=01h, HL=SCRATCH1を維持したまま)
	DEFB	0EDH,093H		; JP.M0 T1_CONT  ** テスト対象 **
	DEFW	T1_CONT
T1_CONT:
	LD	A,11H
	LD	(HL),A			; M0になっていればflat書込み(bank00hへ)
	DEFB	0EDH,091H		; SET_M1 (両bankを読み戻すため一時的に)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0)
	LD	HL,SCRATCH1
	LD	A,(HL)
	LD	(T1_B00),A
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	HL,SCRATCH1
	LD	A,(HL)
	LD	(T1_B01),A
	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(T1_B00)
	LD	B,11H
	LD	DE,MSG_T1A
	CALL	CHECK_BYTE
	LD	A,(T1_B01)
	LD	B,00H
	LD	DE,MSG_T1B
	CALL	CHECK_BYTE

	;==========================================================
	; Test2: JP.M1 addr16 (M0->M1)
	;==========================================================
	DI
	DEFB	0EDH,090H		; SET_M0 (前提条件: M0から開始)
	DEFB	0EDH,091H		; SET_M1 (スクラッチクリアのため一時的に)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0)
	LD	HL,SCRATCH2
	LD	(HL),A			; bank00h:SCRATCH2 = 00h
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	HL,SCRATCH2
	XOR	A
	LD	(HL),A			; bank01h:SCRATCH2 = 00h
	DEFB	0EDH,090H		; SET_M0 (前提条件のM0へ戻す)
					; (HL_B=01h, HL=SCRATCH2を維持したまま)
	DEFB	0EDH,094H		; JP.M1 T2_CONT  ** テスト対象 **
	DEFW	T2_CONT
T2_CONT:
	LD	A,22H
	LD	(HL),A			; M1になっていればbank-aware書込み(bank01hへ)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0)
	LD	HL,SCRATCH2
	LD	A,(HL)
	LD	(T2_B00),A
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	HL,SCRATCH2
	LD	A,(HL)
	LD	(T2_B01),A
	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(T2_B00)
	LD	B,00H
	LD	DE,MSG_T2A
	CALL	CHECK_BYTE
	LD	A,(T2_B01)
	LD	B,22H
	LD	DE,MSG_T2B
	CALL	CHECK_BYTE

	;==========================================================
	; Test3: JP.M2 addr24 (bankをまたぐジャンプ、実行マーカー方式)
	;==========================================================
	DI
	DEFB	0EDH,091H		; SET_M1 (コピーのため前提条件)
	XOR	A
	LD	(MARKER3),A		; マーカーをクリア (絶対アドレッシングは
					; 常にflat=bank00hなのでDI外でも安全だが
					; DI区間内にまとめておく)

	LD	A,02H
	DEFB	0EDH,024H		; LD HL_B,A (=02h, コピー先物理bank)
	LD	IX,SUB_FOR_JPM2		; コピー元 (bank00h内, IX_Bは既定の00h)
	LD	HL,TARGET_CODE		; コピー先 (bank02h内オフセット)
	LD	B,9			; SUB_FOR_JPM2の総バイト数 (下記参照)
	CALL	COPY_TO_BANK2

	DEFB	0EDH,09BH		; JP.M2 02:TARGET_CODE (V16.1)
	DEFW	TARGET_CODE
	DEFB	02H
	; (この直後には戻ってこない。bank02hへコピーしたSUB_FOR_JPM2が実行
	;  され、マーカーを書き換えた後、自らJP.M1でT3_CONTへ戻ってくる)
T3_CONT:
	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(MARKER3)
	LD	B,33H
	LD	DE,MSG_T3
	CALL	CHECK_BYTE

	;==========================================================
	; Test4: CALL.M0 addr16 (ED 96) + RET.M
	;==========================================================
	DI
	DEFB	0EDH,092H		; SET_M2 (前提条件: M1/M0とは違うモードから)
	XOR	A
	LD	(MARKER4),A

	DEFB	0EDH,096H		; CALL.M0 SUB_FOR_CALLM0  ** テスト対象 **
	DEFW	SUB_FOR_CALLM0
	; (SUB_FOR_CALLM0がマーカーを書き換えRET.Mで戻ってくる。RET.Mは
	;  呼出し前のモード(M2)へ復帰させるはずだが、本テストではマーカー
	;  実行の確認のみ行う。モード復元自体の確認はTest1/2で検証済みの
	;  「bank-aware書込み挙動」という同じ手法が転用できるが、GHDL
	;  テストベンチ(tb_phase12_mode_control.vhd)で既にbit単位の厳密な
	;  復元を検証済みのため、実機テストではここまでで十分とする)

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(MARKER4)
	LD	B,44H
	LD	DE,MSG_T4
	CALL	CHECK_BYTE

	;==========================================================
	; Test5: CALL.M1 addr16 (ED 97) + RET.M
	;==========================================================
	DI
	DEFB	0EDH,092H		; SET_M2 (前提条件)
	XOR	A
	LD	(MARKER5),A

	DEFB	0EDH,097H		; CALL.M1 SUB_FOR_CALLM1  ** テスト対象 **
	DEFW	SUB_FOR_CALLM1

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(MARKER5)
	LD	B,55H
	LD	DE,MSG_T5
	CALL	CHECK_BYTE

	;==========================================================
	; Test6: CALL.M2 addr24 (ED 98) + RET.M (bankをまたぐ呼出し往復)
	;==========================================================
	DI
	DEFB	0EDH,091H		; SET_M1 (コピーのため前提条件)
	XOR	A
	LD	(MARKER6),A

	LD	A,02H
	DEFB	0EDH,024H		; LD HL_B,A (=02h)
	LD	IX,SUB_FOR_CALLM2	; コピー元 (bank00h内)
	LD	HL,TARGET_CODE		; コピー先 (bank02h内, Test3と同じ
					; オフセットを再利用して上書きする)
	LD	B,7			; SUB_FOR_CALLM2の総バイト数 (下記参照)
	CALL	COPY_TO_BANK2

	DEFB	0EDH,098H		; CALL.M2 02:TARGET_CODE  ** テスト対象 **
	DEFW	TARGET_CODE
	DEFB	02H
	; (bank02hのSUB_FOR_CALLM2が実行されマーカーを書き換えRET.Mで戻る)

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	A,(MARKER6)
	LD	B,66H
	LD	DE,MSG_T6
	CALL	CHECK_BYTE

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

	; MSX-DOSのコマンドプロンプトへ確実に復帰する。
	LD	C,BDOS_TERM0
	CALL	BDOS

;==============================================================================
; COPY_TO_BANK2 : テンプレートバイト列を物理bank02hへ1byteずつコピーする
;   入力: IX = コピー元 (bank00h内, IX_Bは既定の00hのまま触らない)
;         HL = コピー先 (呼出し前にHL_B=02hを設定しておくこと)
;         B  = バイト数
;   破壊: A, IX, HL, B
;==============================================================================
COPY_TO_BANK2:
	LD	A,(IX+0)
	LD	(HL),A
	INC	IX
	INC	HL
	DJNZ	COPY_TO_BANK2
	RET

;==============================================================================
; CHECK_BYTE : 1byteの実測値と期待値を比較し、PASS/FAILを表示する
;   入力: A = 実測値, B = 期待値, DE = テスト名文字列へのポインタ($終端)
;
;   BDOS(CALL BDOS)はレジスタ/フラグの保存を保証しないため、比較に必要な
;   値は最初にCB_ACT/CB_EXPのメモリ変数へ退避してから使う
;   (Push24Test/CHECK24_IXと同じ手法)。
;==============================================================================
CHECK_BYTE:
	LD	(CB_ACT),A
	LD	A,B
	LD	(CB_EXP),A

	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR

	LD	A,(CB_ACT)
	LD	HL,CB_EXP
	CP	(HL)
	JR	NZ,CHECK_BYTE_FAIL

	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	CHECK_BYTE_DONE

CHECK_BYTE_FAIL:
	LD	DE,MSG_FAIL
	CALL	PRINT_STR
	LD	A,(CB_ACT)
	CALL	PRINT_HEX
	LD	DE,MSG_WANT
	CALL	PRINT_STR
	LD	A,(CB_EXP)
	CALL	PRINT_HEX
	LD	E,')'
	LD	C,2
	CALL	BDOS
	LD	HL,FAIL_COUNT
	INC	(HL)

CHECK_BYTE_DONE:
	LD	DE,MSG_CRLF
	CALL	PRINT_STR
	RET

; 終了前の安全な状態復元: M0へ戻し、使用したバンクレジスタを0クリアする
; (MMUTestのSAFE_RESETと同じ構成。MSP24自体は他のMSX-DOS/BIOSコードが
;  参照することのない専用レジスタなので明示的なクリアは行わない)
SAFE_RESET:
	DI
	DEFB	0EDH,090H		; SET_M0
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A
	EI
	RET

;==============================================================================
; 文字出力ユーティリティ (Push24Test/MMUTest と同じ構成)
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
; JP.M2/CALL.M2コピー先テンプレート (本体はbank00hに置かれるが、実行時には
; COPY_TO_BANK2で物理bank02hへ1byteずつコピーしてからそちらで実行される)
;==============================================================================

; JP.M2のコピー先: マーカーを書き換えた後、自らJP.M1でbank00hのT3_CONTへ
; 戻る(JP.M2は「呼出し」ではなく「ジャンプ」なので、戻り先は明示的に
; 自分でジャンプし直す必要がある)。
SUB_FOR_JPM2:
	LD	A,33H
	LD	(MARKER3),A
	DEFB	0EDH,094H		; JP.M1 T3_CONT
	DEFW	T3_CONT
; 上記の総バイト数 = 9 (3E 33 / 32 lo hi / ED 94 lo hi)。COPY_TO_BANK2
; 呼出し時の "LD B,9" と一致させること(このサブルーチンを変更した場合は
; 必ず再計算すること)。

; CALL.M2のコピー先: マーカーを書き換えた後、RET.Mで戻る(CALL.M2が積んだ
; 4byte戻りフレームにより、呼出し元のCALL.M2直後へ自動的に復帰する)。
SUB_FOR_CALLM2:
	LD	A,66H
	LD	(MARKER6),A
	DEFB	0EDH,099H		; RET.M
; 上記の総バイト数 = 7 (3E 66 / 32 lo hi / ED 99)。COPY_TO_BANK2
; 呼出し時の "LD B,7" と一致させること(このサブルーチンを変更した場合は
; 必ず再計算すること)。

;==============================================================================
; CALL.M0/CALL.M1の呼出し先 (addr16ターゲットなので常にbank00h内、
; bankをまたがず本プログラムの一部としてそのまま実行される)
;==============================================================================
SUB_FOR_CALLM0:
	LD	A,44H
	LD	(MARKER4),A
	DEFB	0EDH,099H		; RET.M

SUB_FOR_CALLM1:
	LD	A,55H
	LD	(MARKER5),A
	DEFB	0EDH,099H		; RET.M

;==============================================================================
; データ領域
;==============================================================================
MSG_BANNER:
	DEFB	"Z80X24 Phase12 mode-control test",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1A:	DEFB	"Test1a JP.M0 bank00 flat write (11h)$"
MSG_T1B:	DEFB	"Test1b JP.M0 bank01 unaffected (00h)$"
MSG_T2A:	DEFB	"Test2a JP.M1 bank00 unaffected (00h)$"
MSG_T2B:	DEFB	"Test2b JP.M1 bank01 bank-aware (22h)$"
MSG_T3:		DEFB	"Test3  JP.M2 bank02 exec marker (33h)$"
MSG_T4:		DEFB	"Test4  CALL.M0/RET.M marker (44h)$"
MSG_T5:		DEFB	"Test5  CALL.M1/RET.M marker (55h)$"
MSG_T6:		DEFB	"Test6  CALL.M2/RET.M bank02 marker (66h)$"

MSG_COLON:	DEFB	": $"
MSG_PASS:	DEFB	"PASS$"
MSG_FAIL:	DEFB	"FAIL (got=$"
MSG_WANT:	DEFB	", want=$"
MSG_CRLF:	DEFB	13,10,"$"

MSG_DONE1:	DEFB	13,10,"PASS=$"
MSG_DONE2:	DEFB	" FAIL=$"

; --- CHECK_BYTE用の退避領域 ---
CB_ACT:		DEFS	1
CB_EXP:		DEFS	1

; --- 各テストのスクラッチ/マーカー変数 (本プログラム自身のデータ領域) ---
SCRATCH1:	DEFS	1
T1_B00:		DEFS	1
T1_B01:		DEFS	1
SCRATCH2:	DEFS	1
T2_B00:		DEFS	1
T2_B01:		DEFS	1
MARKER3:	DEFS	1
MARKER4:	DEFS	1
MARKER5:	DEFS	1
MARKER6:	DEFS	1

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
