;==============================================================================
; P1314_TEST.ASM - Z80X24 Phase13(M2割込み)+Phase14(RST.L) 実機テストプログラム
;                  (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase14「RST拡張(RST.L)」と Phase13「割り込み(M2拡張)」を、実機(Tang Nano)
; またはMSXエミュレータ上のMSX-DOS(2)から起動して確認するためのテスト
; プログラムです。
;
;   doc/jpn/MSX_T80_24bit化_CPU仕様書_V10_2026-10-11.md section12 "RST.L"
;   doc/jpn/MSX_T80_24bit化_CPU仕様書_V10_2026-10-11.md section13 "Interrupt"
;   AVAILABLE_INSTRUCTIONS.md セクション11 "RST拡張(RST.L)"
;   AVAILABLE_INSTRUCTIONS.md セクション12 "割り込み(M2拡張)"
;   fpga/G80A/test/tb_rst_l.vhd (RST.LのGHDLシミュレーション版)
;   fpga/G80A/test/tb_phase13_m2_interrupt.vhd (M2割込みのGHDLシミュレーション版)
;
; 検証内容:
;   Test1/2/3: RST.L 00H/20H/38H (ED C7/E7/FF)。M2モードでそれぞれ物理
;              bank05h(TARGET_BANKに同じ)の対応するオフセット(0000h/
;              0020h/0038h)へジャンプし、RET.Lで復帰することを、専用の
;              マーカー変数で確認する(実行マーカー方式、P12TestのTest3/6
;              と同じ手法)。3種類の異なるvectorを代表して検証することで、
;              IR(5:3)のvectorデコードが正しいことを確認する(全8vectorの
;              網羅的な検証はGHDL側のtb_rst_l.vhdで実施済み)。
;   Test4    : RETN.L (ED 8C) スモークテスト。手動で構築した4byte frame
;              (PC_L/PC_H/PC_B/MODE)をMSP24スクラッチ領域(01:DFFCh)へ
;              直接書き込み、MSP24をそこへ設定した上でRETN.Lを実行し、
;              正しくPC24/bank_pc/mode24が復元されることを確認する。
;              (IFF1<-IFF2の復元自体は実機では検証できない。詳細は後述の
;              「本プログラムの対象範囲・既知の制約」参照。GHDL側の
;              tb_phase13_m2_interrupt.vhdでNMIを使い厳密に検証済み。)
;   DIAG1    : 診断用ストレステスト(割込み不使用)。Test5と同程度の
;              反復回数を、割込みを一切使わず(DIのまま)M2モードで実行
;              し続けるだけのテスト。Test5でフリーズが観測された場合に、
;              原因が「割込み」なのか「M2での持続的な命令実行そのもの」
;              なのかを切り分けるための診断であり、Phase13/14仕様の
;              正式なテスト項目ではない(PASS/FAIL判定も行わず、完走
;              すれば単に生存確認メッセージを表示するのみ)。
;   Test5    : 実機VDPフレーム割込み(垂直帰線割込み)を使い、M2の
;              マスク可能割込み(IRQ)がIM設定に関係なくIVR24へ直接分岐
;              することを実地検証する。IVR24ハンドラがVDPステータス
;              レジスタを読んで割込みをACKし、IRQ_COUNTを+1してRETI.L
;              で復帰する。本プログラムで初めて実際の非同期ハードウェア
;              割込みを使う検証(それ以前のPhase11/12同様のテストは
;              すべて命令列のみで完結する決定論的な検証だった)。
;   Test6    : Test5直後、RETI.LはIFF1<-IFF2を復元しないため、その後
;              何回VDPフレーム割込みが発生してもIRQ_COUNTが増加しない
;              (マスクされたまま)ことを、固定時間busy-waitで確認する。
;   Test7    : 明示的にEIした後、IRQ_COUNTが実際に2へ増加する(割込みが
;              再び受理される)ことを確認し、一連の機構が正常に動作し
;              続けることを確認する。
;
; 本プログラムの対象範囲・既知の制約:
;   - RST.LのM0/M1「完全degrade」挙動(通常Z80 RSTとしてSP16へ16bit push
;     し、固定0000h/0008h/.../0038hへジャンプする)は、本プログラムでは
;     実機テストしない。これらの固定アドレスはMSX-DOS/BIOSが既に所有
;     している零ページ(ウォームスタートベクタ、IM1割込みベクタ0038h等)
;     であり、実際にジャンプさせると未知のBIOS/DOSコードへ分岐して
;     クラッシュ・ハングする危険があるため。この挙動はGHDL側の
;     tb_rst_l.vhd(Test4/Test5)で既に厳密に検証済みである。
;   - RETN.Lの「IFF1<-IFF2を復元する」という、RETI.Lとの唯一の挙動差分
;     は、本プログラムでは実機検証できない。これを独立して検証するには
;     本物のNMI(ノンマスカブル割込み)が必要だが、標準的なMSX実機には
;     ソフトウェアから起動可能なNMIトリガが存在しない(リセット/一時
;     停止ボタン等、物理操作にのみ連動)ため。この挙動はGHDL側の
;     tb_phase13_m2_interrupt.vhd(Test3/Test3b/Test4、NMI_nを直接駆動)
;     で既に厳密に検証済みである。
;
; 安全設計上の注意 (MMUTest/P12Testの先例に厳密に従う):
;   - M1/M2モードでバンクレジスタを設定した状態のままBIOS/DOSコールを
;     行うと、BIOS/DOS側が内部で使う(HL)等のアクセスまで拡張メモリへ
;     誤ってリダイレクトされる危険がある。そのため、画面出力やBDOS
;     呼出しは必ずM0へ戻してEIした後に行う(Test5-7のVDP割込み待ちループ
;     はM2のままEIするが、ループ本体はレジスタ/メモリの単純な比較のみで
;     BDOS呼出しを一切含まない)。
;   - RST.L(M2)で実際にジャンプする先の物理bank05h(TARGET_BANK)のコードは、
;     本プログラム自身の(bank00hの)データ領域内に用意したテンプレート
;     バイト列を、bank-aware (HL)書込みで1byteずつコピーしたものであり、
;     コピー先オフセット(0000h/0020h/0038h)はbank05hという、本プログラム
;     の64KB空間や他のテストプログラム(P12Testの02h等)とも重ならない
;     物理bankの中なので、本プログラム自身やBIOS/DOSの既存コードを破壊
;     する心配はない。
;   - 拡張メモリアクセスで使用する物理bankは01h(MSP24スタック/Test4の
;     手動frame)・05h(RST.L M2コピー先コード)のみ。これはfpga/top.vの
;     CPU_SDRAM_BASE(0x640000)経由で、既存のMemory Mapper(0x000000-)や
;     MegaRAM(0x400000-)とは重ならない安全な領域(0x650000以降、詳細は
;     doc/jpn/SDRAMメモリマップ.md 2.2章)に収まる。
;   - Test5-7で使うVDPフレーム割込み(R#1 bit5=IE)は、BIOS管理のシャドウ
;     変数RG1SAV(0F3E0h)から現在値を読み出し保存した上でORでIEビットを
;     立て、VDPコントロールポート(99h)へ直接OUTする(B=値,C=レジスタ
;     番号形式のBIOS標準ルーチンWRTVDPは使わない - MSX-DOSのアプリ
;     ケーションからはBIOS ROM内のルーチンを直接CALLできない(正しくは
;     CALSLT、001CH/MAIN ROM経由でスロットを指定した間接呼出しが必要)
;     という規則に反していたため、実機テストでMSX-DOSへの予期しない
;     復帰(クラッシュ)を引き起こしていた。VDPはI/Oポート経由の
;     ハードウェアでスロット/BIOS ROMの概念と無関係なため、診断用画面
;     色マーカーと同じ直接OUT方式に統一し、BIOS依存自体を排除した)。
;     プログラム終了前に必ず元の値へ直接OUTで復元する。
;   - IVR24ハンドラは、VDPステータスレジスタ(IN A,(99H))を読んで割込み
;     要因をACKする。M2の割込みはIM/IStatusを一切参照しないため、IM
;     モード自体は本プログラムでは変更しない(標準のBIOS初期設定のまま)。
;   - プログラム終了前に、必ずM0へ戻し使用したバンクレジスタ(HL_B)を
;     0クリアし、VDP R#1も元の値へ復元してからMSX-DOSへ復帰する
;     (SAFE_RESET参照)。本プログラムが使用するバンクレジスタはHL_B/
;     RST_Bのみ(RST_Bは00hクリアまでは行わないが、他のテストに影響
;     しない独立したレジスタである)。
;   - Z80X24拡張が入っていない通常のMSX実機/エミュレータ上で実行すると、
;     ED系拡張opcodeは未定義命令(多くの実装ではNOP相当)として扱われる
;     ため、全テストがFAILと表示されるが、これは異常ではなく「拡張機能
;     が存在しない」ことを意味する。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `P1314T` と入力する。
;==============================================================================

	org	$0100

;------------------------------------------------------------------------------
; MSX-DOS / BDOS
;------------------------------------------------------------------------------
BDOS		EQU	0005H		; DOS function entry
BDOS_TERM0	EQU	0		; BDOS function 0: プログラム終了、MSX-DOSへ復帰

;------------------------------------------------------------------------------
; MSX BIOS
;------------------------------------------------------------------------------
WRTVDP		EQU	0047H		; VDPレジスタ書込み (B=値, C=レジスタ番号)
RG1SAV		EQU	0F3E0H		; VDP R#1 現在値のBIOSシャドウ変数
RG7SAV		EQU	0F3E6H		; VDP R#7 現在値のBIOSシャドウ変数(背景色。
					; 診断用の画面色マーカーで直接OUTする前に
					; 退避し、終了前に復元するために使用)
VDP_PORT	EQU	099H		; VDPコントロールポート(直接OUT用。診断
					; マーカーの書込みはBIOS WRTVDPを経由せず
					; 直接OUTする - M2中はCALLがMSP24を経由
					; するため、サブルーチン化せずその都度
					; インライン展開して使う)

;------------------------------------------------------------------------------
; Z80X24 独自オペコード (標準Z80アセンブラには無いため DEFB で直接発行する)
;------------------------------------------------------------------------------
; ED 90        SET_M0                          完全Z80互換モードへ
; ED 91        SET_M1                          データアクセスのみ24bit拡張モードへ
; ED 92        SET_M2                          24bitネイティブモードへ
; ED 24/2C     LD HL_B,A / LD A,HL_B           (Phase1, HLバンクレジスタ)
; ED 35        LD24 MSP,HL                     (Phase7, MSP24の設定に使用)
; ED 3A        LD RST_B,A                      (Phase1/14, RST.L用バンクレジスタ)
; ED C7        RST.L 00H                       (Phase14, 本プログラムの対象)
; ED E7        RST.L 20H                       (Phase14, 本プログラムの対象)
; ED FF        RST.L 38H                       (Phase14, 本プログラムの対象)
; ED C9        RET.L                           (Phase11, RST.L M2の復帰先)
; ED F3        RETI.L                          (V16.1コード、本プログラムの対象)
; ED 8C        RETN.L                          (Phase13, 本プログラムの対象)
; ED 9B        LD24 IVR,HL                     (Phase7, IVR24の設定に使用)
;------------------------------------------------------------------------------
TARGET_BANK	EQU	05H		; RST.L M2ジャンプ先 (物理bank、P12Testの02hとは別)

;==============================================================================
; エントリポイント
;==============================================================================
START:
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ==== 共通準備: MSP24 = 01:E000h (単純なレジスタ転送、メモリアクセス
	;      を伴わないためDI保護は不要。P12Test/Push24Testと同じ初期値) ====
	LD	HL,0E000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL

	;==========================================================
	; Test1/2/3: RST.L 00H/20H/38H (M2, 物理bank05hへ3種のvectorを
	; 代表してテストする)
	;==========================================================
	DI
	DEFB	0EDH,091H		; SET_M1 (コピーのため前提条件)
	XOR	A
	LD	(MARKER1),A
	LD	(MARKER2),A
	LD	(MARKER3),A

	LD	A,TARGET_BANK
	DEFB	0EDH,024H		; LD HL_B,A (=05h, コピー先物理bank)
	LD	IX,SUB_RST00		; コピー元 (bank00h内)
	LD	HL,00000H		; コピー先: bank05h:0000h (vector 00H)
	LD	B,SUB_RST_LEN
	CALL	COPY_TO_BANKX

	LD	A,TARGET_BANK
	DEFB	0EDH,024H
	LD	IX,SUB_RST20
	LD	HL,00020H		; コピー先: bank05h:0020h (vector 20H)
	LD	B,SUB_RST_LEN
	CALL	COPY_TO_BANKX

	LD	A,TARGET_BANK
	DEFB	0EDH,024H
	LD	IX,SUB_RST38
	LD	HL,00038H		; コピー先: bank05h:0038h (vector 38H)
	LD	B,SUB_RST_LEN
	CALL	COPY_TO_BANKX

	LD	A,TARGET_BANK
	DEFB	0EDH,03AH		; LD RST_B,A (=05h)
	DEFB	0EDH,092H		; SET_M2 (前提条件、ここから各RST.Lを実行)

	DEFB	0EDH,0C7H		; RST.L 00H  ** テスト対象 **
	; (bank05h:0000hのSUB_RST00が実行されマーカーを書き換え、RET.Lで
	;  この直後へ戻ってくる)
	DEFB	0EDH,0E7H		; RST.L 20H  ** テスト対象 **
	DEFB	0EDH,0FFH		; RST.L 38H  ** テスト対象 **

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0)
	EI

	LD	A,(MARKER1)
	LD	B,11H
	LD	DE,MSG_T1
	CALL	CHECK_BYTE
	LD	A,(MARKER2)
	LD	B,22H
	LD	DE,MSG_T2
	CALL	CHECK_BYTE
	LD	A,(MARKER3)
	LD	B,33H
	LD	DE,MSG_T3
	CALL	CHECK_BYTE

	;==========================================================
	; Test4: RETN.L (ED 8C) スモークテスト - 手動構築した4byte frame
	; (01:DFFCh起点)からPC24/bank_pc/mode24が正しく復元されることを
	; 確認する(IFF1<-IFF2の復元自体は上記「対象範囲」注記のとおり
	; 実機では検証しない)
	;==========================================================
	DI
	XOR	A
	LD	(MARKER4),A

	DEFB	0EDH,091H		; SET_M1 (bank-aware (HL)書込みの前提条件。
					; これが無いとM0のbank bypassにより下記の
					; 書込みがbank01hではなくbank00hへ誤って
					; 行われ、frameが全く書かれないまま
					; RETN.Lが未初期化データをpopしてしまう
					; - 実機テストで実際に発生したフリーズは
					; これが原因だった)

	LD	DE,T4_CONT		; 復帰先アドレス (本プログラム自身、bank00h)
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	HL,0DFFCH		; frame base = 01:DFFCh
	LD	A,E
	LD	(HL),A			; +0 = PC_L
	INC	HL
	LD	A,D
	LD	(HL),A			; +1 = PC_H
	INC	HL
	XOR	A
	LD	(HL),A			; +2 = PC_B (=00h, 本プログラムのbank)
	INC	HL
	LD	A,02H			; MODE byte = "000000" & mode24(=M2=10b) = 02h
	LD	(HL),A			; +3 = MODE

	LD	HL,0DFFCH		; frame baseへ戻す (HL_Bはまだ01hのまま)
	DEFB	0EDH,035H		; LD24 MSP,HL  (MSP24=01:DFFCh)

	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0, 以降の素のLD命令を安全にする)

	DEFB	0EDH,092H		; SET_M2 (RETN.Lが復元するMODEバイト=02h
					; と整合させておく。RETN.L自体の実行は
					; 現在のmode24に依存しないが、ポップした
					; 4byte frameはPC24/MSP24に対して常に
					; 真の24bitアドレスとして扱われるため、
					; この直前のmode24の値そのものは実行結果
					; に影響しない - 念のため意図を明示する
					; ために揃えてある)

	DEFB	0EDH,08CH		; RETN.L  ** テスト対象 ** (次の1byteへ復帰)
T4_CONT:
	LD	A,44H
	LD	(MARKER4),A		; 絶対16bitアドレッシングは常にbank00hへの
					; flat書込み(modeに依存しない)なので、万一
					; bank_pc/modeの復元が誤っていてもここへ
					; 正しく到達できた時点でこの書込み自体は安全

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す、念のため)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A
	EI

	LD	A,(MARKER4)
	LD	B,44H
	LD	DE,MSG_T4
	CALL	CHECK_BYTE

	;==========================================================
	; DIAG1: M2持続実行ストレス診断 (割込み不使用)
	;   Test5でフリーズが観測された場合の原因切り分け用。Test5の
	;   WAIT_EARLY_EXIT/WAIT_FIXEDと同程度の反復回数を、割込みを一切
	;   使わず(DIのまま)M2モードで実行し続けるだけのテストである。
	;   これがここでフリーズする場合、原因は「割込み」ではなく
	;   「M2状態での持続的な命令実行そのもの」にある(Phase16「総合
	;   検証」のP&R/Fmaxタイミングクロージャが未確認である点と関連
	;   する可能性が高い)。これが完走しTest5だけがフリーズする場合は、
	;   実機の非同期割込み(VDPフレーム割込み)がM2のPhase13割込み機構
	;   と組み合わさったときに特有の問題がある可能性が高い。
	;==========================================================
	DI
	DEFB	0EDH,092H		; SET_M2 (M0から来ているのでbank_pc_r=00h)

	LD	B,10H
DIAG1_OUTER:
	LD	DE,0FFFFH
DIAG1_INNER:
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,DIAG1_INNER
	DJNZ	DIAG1_OUTER

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)
	EI

	LD	DE,MSG_DIAG1
	CALL	PRINT_STR

	;==========================================================
	; Test5/6/7: 実機VDPフレーム割込みによるM2 IRQ -> IVR24 実地検証
	;==========================================================
	XOR	A
	LD	(IRQ_COUNT),A

	; IVR24 = 00:IVR_HANDLER (単純なレジスタ転送、DI保護は不要)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (=0, IVR24ハンドラは本プログラム
					; 自身と同じbank00hに置く)
	LD	HL,IVR_HANDLER
	DEFB	0EDH,09BH		; LD24 IVR,HL

	; 診断用の画面色マーカーで使うVDP R#7(背景色)の現在値を退避する
	; (プログラム終了前に直接OUT方式で復元する)。
	LD	A,(RG7SAV)
	LD	(SAVED_R7),A

	; VDPフレーム割込み(R#1 bit5=IE)を有効化する。現在値をRG1SAVから
	; 読み保存し、IEビットだけを立てて直接VDPへOUTする(他のビットは
	; 保存した値のまま変更しない)。
	;
	; 注意: 当初BIOS標準ルーチンWRTVDP(0047h)をCALLする実装だったが、
	; 実機テストでDIAG1完走直後にMSX-DOSへ突然復帰する(クラッシュ)
	; 現象が発生した。根本原因は、**MSX-DOSのアプリケーションからは
	; BIOS ROM内のルーチンを直接CALLできない(正しくはCALSLT、001CH/
	; MAIN ROM経由でスロットを指定した間接呼出しが必要)**という規則に
	; 反していたことだった(本プログラム全体を通して、このCALL WRTVDPが
	; 唯一のBIOS ROM直接CALLであり、それ以前のCALLはすべて本プログラム
	; 自身のサブルーチンか、スロットを意識せず直接CALL可能なBDOS
	; (CALL 5)のみだった)。VDPはI/Oポート経由のハードウェアでスロット/
	; BIOS ROMの概念と無関係なため、CALSLTへ書き換える代わりにVDP R#7の
	; 診断マーカーと同じ直接OUT方式に統一し、BIOS依存自体を排除した。
	LD	A,(RG1SAV)
	LD	(SAVED_R1),A
	OR	20H
	OUT	(VDP_PORT),A
	LD	A,81H			; R#1 | 80h (レジスタ書込みモード)
	OUT	(VDP_PORT),A

	; ---- 診断チェックポイント2: IVR24設定/VDP R#1設定が完了し、
	; これからM2へ移行してEIする直前であることを(まだM0・安全な状態の
	; うちに)画面へ表示する。もしこのメッセージが表示されない場合、
	; 原因はTest5そのものではなく、ここより前(Test1-4/DIAG1、または
	; このTest5自身のセットアップコード)にあることになる。 ----
	LD	DE,MSG_T5_ARMED
	CALL	PRINT_STR

	DEFB	0EDH,092H		; SET_M2 (この後は割込みがIVR24経由でのみ
					; 処理される。IM/IStatusはM2では一切参照
					; されないため変更不要)
	EI				; 最初の武装 - Test7で再度EIするまで、この
					; 後は一切EIしない(Test6でマスク継続を
					; 確認するため。下記注記参照)

	; ---- Test5: 最初のVDP割込みを待つ(早期終了つきbusy-wait)。
	; サービスされればIRQ_COUNT=01hになるはずである。割込み受理時に
	; IFF1=IFF2=0へ強制され、RETI.LはIFFを一切復元しないため、この
	; 時点でIFF1は既に0(マスク状態)になっている。
	;
	; 注意: このbusy-waitは、WAIT_EARLY_EXITサブルーチンへのCALLでは
	; なくインライン展開している。M2モード中は通常のCALL/RETもMSP24を
	; 経由するため(Phase10仕様)、もしCALLを使うと「CALL自体がMSP24へ
	; push」した状態の上に「割込み受理自体の4byte frame」がネストして
	; 積まれる形になる。この組み合わせはGHDL側のテストベンチでは検証
	; されておらず、実機フリーズの一因となった可能性があるため、EIした
	; 状態で割込みを待つ区間ではCALL/RET自体を一切使わないよう、ここで
	; インライン化して安全側に倒した。 ----
	LD	B,08H
T5_OUTER:
	; ---- 心拍(heartbeat)マーカー: 外側ループの残りカウント(B=8..1)を
	; そのままVDP R#7(背景色)へ直接OUTする。BDOSのメッセージ表示とは
	; 違い、画面には即座に反映されるため、たとえこの後で本当に無限
	; ハングしても「最後に表示されていた色」から、ループが何周目まで
	; 進んでいたか(＝完全に動かなくなったのか、それとも単に割込みが
	; 来ていないだけなのか)を目視で判別できる。CALLではなくインライン
	; で直接OUTしている(M2中はCALL自体がMSP24を使うため、診断コード
	; 自体で新たなネストを増やさないようにするため)。 ----
	LD	A,B
	OUT	(VDP_PORT),A
	LD	A,87H			; R#7 | 80h (レジスタ書込みモード)
	OUT	(VDP_PORT),A

	LD	A,(IRQ_COUNT)
	OR	A
	JR	NZ,T5_DONE
	LD	DE,0FFFFH
T5_INNER:
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,T5_INNER
	DJNZ	T5_OUTER
T5_DONE:

	DEFB	0EDH,090H		; SET_M0 (いったんM0へ。ただしCHECK_BYTEは
					; まだ呼ばない - 下記注記参照)
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A

	; ---- 重要: Test5の結果はここでまだ表示しない。MSX-DOSの仕様上、
	; BDOS(CALL 5)は副作用として内部でEIを実行し、呼出し前の割込み
	; 禁止状態を保存・復元しない(MSX-DOS標準の既知の挙動)。もしここで
	; CHECK_BYTE(内部でBDOSを使用)を呼ぶと、Test6の観測ウィンドウが
	; 始まる前にBDOSが割込みを暗黙的に再武装してしまい、Test6が
	; 「RETI.Lが誤ってIFFを復元した」という偽陽性のFAILを報告して
	; しまう(実際に発生した現象)。そのため、Test5の結果は一旦
	; T5_RESULTへ退避するだけに留め、BDOSは一切呼ばずに直接Test6の
	; 観測ウィンドウへ進む。両方の結果はTest6の観測が終わった後、
	; まとめて表示する。 ----
	LD	A,(IRQ_COUNT)
	LD	(T5_RESULT),A

	; ---- Test6: RETI.Lは IFF1<-IFF2 を復元しないため、この後何回
	; VDP割込みが発生してもIRQ_COUNTは増加しないはず(マスクされた
	; まま)。固定時間待ってから確認する(Test5からここまでBDOS/EIを
	; 一切呼んでいないため、IFF1は確実に0のまま)。Test5と同じ理由で
	; インライン化し、CALL/RETを使わない。 ----
	DEFB	0EDH,092H		; SET_M2 (再度M2へ、IFF自体はTest5のRETI.L
					; 直後からそのまま変化していない=マスク中)
	LD	B,10H
T6_OUTER:
	LD	DE,0FFFFH
T6_INNER:
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,T6_INNER
	DJNZ	T6_OUTER

	DEFB	0EDH,090H		; SET_M0
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A
					; ここでようやくEIを許容してよい状態になる
					; (Test6の観測ウィンドウはもう閉じている)
					; が、Test7が明示的にEIするまでは念のため
					; 引き続き呼ばない。

	; ---- Test5/Test6の結果をまとめて表示する(両方ともBDOSを使うが、
	; どちらの観測ウィンドウも既に終わっているので問題ない)。 ----
	LD	A,(T5_RESULT)
	LD	B,01H
	LD	DE,MSG_T5
	CALL	CHECK_BYTE

	LD	A,(IRQ_COUNT)
	LD	B,01H
	LD	DE,MSG_T6
	CALL	CHECK_BYTE

	; ---- Test7: 明示的にEIし(Test5以来はじめての再武装)、割込みが
	; 再び受理されることを確認する(IRQ_COUNTが02hへ増加するはず)。
	; Test5と同じ理由でインライン化し、CALL/RETを使わない。 ----
	DEFB	0EDH,092H		; SET_M2
	EI
	LD	B,08H
T7_OUTER:
	LD	A,(IRQ_COUNT)
	LD	C,02H
	CP	C
	JR	Z,T7_DONE
	LD	DE,0FFFFH
T7_INNER:
	DEC	DE
	LD	A,D
	OR	E
	JR	NZ,T7_INNER
	DJNZ	T7_OUTER
T7_DONE:

	DEFB	0EDH,090H		; SET_M0
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A
	EI				; ここでは通常のDOS実行状態(割込み有効)へ
					; 確実に戻しておく

	LD	A,(IRQ_COUNT)
	LD	B,02H
	LD	DE,MSG_T7
	CALL	CHECK_BYTE

	; VDP R#1を元の値へ復元する(直接OUT方式。上記と同じ理由でBIOS
	; WRTVDP経由はやめた)。
	LD	A,(SAVED_R1)
	OUT	(VDP_PORT),A
	LD	A,81H
	OUT	(VDP_PORT),A

	; 診断用の画面色マーカーで変更したVDP R#7(背景色)も元の値へ復元する
	; (直接OUT方式)。
	LD	A,(SAVED_R7)
	OUT	(VDP_PORT),A
	LD	A,87H
	OUT	(VDP_PORT),A

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
; IVR24ハンドラ (bank00h, Test5/6/7で使用)
;   M2のマスク可能割込み(IRQ)はIM/IStatusに関係なく、ここへ直接分岐する。
;   VDPステータスレジスタを読んでVDP側の割込み要因をACKしてから戻る
;   (これを行わないと、同一フレーム内で割込みが繰り返しハング/再入
;   する可能性がある)。レジスタ/フラグは呼出し元(busy-waitループ)の
;   ために保存・復元する。
;
;   注意: 当初PUSH AF/POP AFでAFを退避していたが、実機テストで
;   ハンドラ内のPUSH/POPがフリーズを引き起こすことが判明した。M2中は
;   通常のPUSH/POP/CALL/RETもすべてMSP24を経由するため(Phase10仕様)、
;   M2割込み受理自体が積んだ4byte frame(MSP24)の上に、さらにハンドラ
;   内のPUSH AFがネストしてMSP24へ積む形になり、GHDL側のテストベンチ
;   (tb_phase13_m2_interrupt.vhd)では検証されていなかったこの「M2割込み
;   ハンドラ内で通常のPUSH/POPを使う」組み合わせで問題が起きる可能性が
;   高いと判断し、スタックを一切使わない EX AF,AF' (裏レジスタへの退避)
;   方式に変更した。
;
;   診断チェックポイント3/4: ハンドラの最初(IVR24へ到達できているか)
;   とRETI.L直前(VDP ACK+本体完走できているか)で、それぞれ異なる色を
;   VDP R#7(背景色)へ直接OUTする。これもBDOSメッセージではなく画面色
;   なので、万一この先で本当にハングしても、画面に最後に表示されていた
;   色から「entry(赤相当)で止まったか」「pre-RETI.L(青相当)まで到達した
;   後に止まったか」を目視で判別できる。
;==============================================================================
IVR_HANDLER:
	EX	AF,AF'			; AFを裏レジスタへ退避(スタック不使用)

	; ---- 診断チェックポイント3: IVR24ハンドラへ到達した直後。 ----
	LD	A,0DDH			; マゼンタ系(IVR24到達マーカー)
	OUT	(VDP_PORT),A
	LD	A,87H
	OUT	(VDP_PORT),A

	IN	A,(99H)			; VDPステータスレジスタ読出し = ACK
	LD	A,(IRQ_COUNT)
	INC	A
	LD	(IRQ_COUNT),A

	; ---- 診断チェックポイント4: VDP ACK + カウンタ更新が完走し、
	; RETI.Lを実行する直前。 ----
	LD	A,99H			; 明るい赤系(RETI.L直前マーカー)
	OUT	(VDP_PORT),A
	LD	A,87H
	OUT	(VDP_PORT),A

	EX	AF,AF'			; AFを復元
	DEFB	0EDH,0F3H		; RETI.L

;==============================================================================
; COPY_TO_BANKX : テンプレートバイト列を物理bank(呼出し前にHL_B設定済み)
;   の指定オフセットへ1byteずつコピーする (P12TestのCOPY_TO_BANK2と同じ)
;   入力: IX = コピー元 (bank00h内, IX_Bは既定の00hのまま触らない)
;         HL = コピー先オフセット (呼出し前にHL_Bを設定しておくこと)
;         B  = バイト数
;   破壊: A, IX, HL, B
;==============================================================================
COPY_TO_BANKX:
	LD	A,(IX+0)
	LD	(HL),A
	INC	IX
	INC	HL
	DJNZ	COPY_TO_BANKX
	RET

;==============================================================================
; CHECK_BYTE : 1byteの実測値と期待値を比較し、PASS/FAILを表示する
;   入力: A = 実測値, B = 期待値, DE = テスト名文字列へのポインタ($終端)
;
;   BDOS(CALL BDOS)はレジスタ/フラグの保存を保証しないため、比較に必要な
;   値は最初にCB_ACT/CB_EXPのメモリ変数へ退避してから使う
;   (P12Test/Push24Testと同じ手法)。
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
; (MMUTest/P12TestのSAFE_RESETと同じ構成。MSP24自体は他のMSX-DOS/BIOS
;  コードが参照することのない専用レジスタなので明示的なクリアは行わない)
SAFE_RESET:
	DI
	DEFB	0EDH,090H		; SET_M0
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A
	EI
	RET

;==============================================================================
; 文字出力ユーティリティ (P12Test/Push24Test/MMUTest と同じ構成)
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
; RST.L M2コピー先テンプレート (本体はbank00hに置かれるが、実行時には
; COPY_TO_BANKXで物理bank05hの各vectorオフセットへ1byteずつコピーして
; からそちらで実行される)。マーカーを書き換えた後、RET.Lで戻る(RST.Lが
; 積んだ3byte戻りフレームにより、呼出し元のRST.L直後へ自動的に復帰する)。
;==============================================================================
SUB_RST00:
	LD	A,11H
	LD	(MARKER1),A
	DEFB	0EDH,0C9H		; RET.L
SUB_RST00_END:

SUB_RST20:
	LD	A,22H
	LD	(MARKER2),A
	DEFB	0EDH,0C9H		; RET.L
SUB_RST20_END:

SUB_RST38:
	LD	A,33H
	LD	(MARKER3),A
	DEFB	0EDH,0C9H		; RET.L
SUB_RST38_END:

; 上記3つの総バイト数はいずれも7 (3E xx / 32 lo hi / ED C9)。同一の長さに
; なるよう揃えてある(このテンプレートを変更した場合は必ず再計算すること)。
SUB_RST_LEN	EQU	7

;==============================================================================
; データ領域
;==============================================================================
MSG_BANNER:
	DEFB	"Z80X24 Phase13/14 (M2 interrupt / RST.L) test",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1:		DEFB	"Test1  RST.L 00H bank05 marker (11h)$"
MSG_T2:		DEFB	"Test2  RST.L 20H bank05 marker (22h)$"
MSG_T3:		DEFB	"Test3  RST.L 38H bank05 marker (33h)$"
MSG_T4:		DEFB	"Test4  RETN.L manual-frame restore (44h)$"
MSG_DIAG1:	DEFB	"DIAG1  M2 sustained execution (no IRQ) survived",13,10,"$"
MSG_T5_ARMED:	DEFB	"T5: IVR/R1 setup done (direct OUT, no BIOS CALL), arming M2+EI now",13,10,"$"
MSG_T5:		DEFB	"Test5  VDP IRQ -> IVR24 -> RETI.L (count=01)$"
MSG_T6:		DEFB	"Test6  RETI.L must NOT unmask IFF (count=01)$"
MSG_T7:		DEFB	"Test7  EI re-arms, IRQ serviced again (count=02)$"

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
MARKER1:	DEFS	1
MARKER2:	DEFS	1
MARKER3:	DEFS	1
MARKER4:	DEFS	1
IRQ_COUNT:	DEFS	1
T5_RESULT:	DEFS	1
SAVED_R1:	DEFS	1
SAVED_R7:	DEFS	1

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
