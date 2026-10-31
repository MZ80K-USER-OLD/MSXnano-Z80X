;==============================================================================
; LD24_MEM_INDIRECT_TEST.ASM - Z80X24 追加命令 "ED00/01/03/08" 実機テスト
;                                (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における、本増分で
; 新規実装した24bitメモリ間接転送命令(ED00/01/03/08)を、実機/エミュレータ上の
; MSX-DOS(2)から起動して確認するためのテストプログラムです。
;
;   doc/jpn/24bitメモリロード追加命令案.md
;   doc/jpn/OLD/MSX_T80_24bit化_実装手順_V4_不足転送命令追加案_2026-10-19.md
;   doc/jpn/OLD/MSX_T80_24bit化_命令一覧_V13_予約維持_2026-10-19.csv
;   AVAILABLE_INSTRUCTIONS.md セクション18
;   fpga/G80A/test/tb_ld24_mem_indirect.vhd (同じシナリオのGHDLシミュレーション版。
;     アドレス/期待値を共有するが、DOS・割込み・表示処理の実行環境は異なる)
;
; 【このプログラムを作成した目的:実機で継続調査中のPUSH24/POP24バンク境界
;  またぎバグの切り分け】
;   doc/jpn/PUSH24_POP24_bank境界またぎバグ_調査レポート.md で継続調査中の
;   バグは、PUSH24/POP24がMSP24専用のハードウェア機構(bank_msp_rの自動増減
;   ロジック)を経由した際、64KBバンク境界をまたぐとデータ破損が生じるという
;   ものである。本プログラムが対象とするED00/01/03/08は、PUSH24/POP24と全く
;   同じ「LOW/HIGH/BANKの3byte・境界またぎ時のbank自動繰上げ」という性質を
;   持ちながら、MSP24のハードウェア機構を一切経由しない独立したアドレス生成
;   経路(新設のaXferアドレスソース、t80.vhd参照)を使う。したがって:
;     - もし本プログラムのTest5/Test6(境界またぎ)がPUSH24/POP24と同様の
;       データ破損を示せば、バグの所在はMSP24固有のロジックではなく、CPU/
;       SDRAMコントローラのより一般的な部分にあることが強く示唆される。
;     - 逆に本プログラムが全てPASSすれば、MSP24のaMSPアドレス生成経路・
;       bank_msp_r増減ロジック自体に問題が局在している可能性が高まる。
;
; 検証内容:
;   Test1: ED00 LD24 BC,(HL) 通常アクセス(境界またぎ無し)。HL24=01:9000hの
;          指す3byte(AAh,99h,05h)をBC24へロードし、BC24=05:99AAhになること、
;          およびHL24自体が変化しないことを確認する。
;   Test2: ED01 LD24 DE,(HL) 通常アクセス(境界またぎ無し)。HL24=01:9010hの
;          指す3byte(11h,22h,33h)をDE24へロードし、DE24=33:2211hになること、
;          およびHL24自体が変化しないことを確認する。
;   Test3: ED03 LD24 (HL),BC 通常アクセス(境界またぎ無し)。BC24=EE:1234hを
;          HL24=01:9020hの指すアドレスへ書込み、(BC)間接読出し(ED03/ED08の
;          仕組みを一切経由しない独立した経路)で実際に書き込まれた内容を
;          直接確認する。
;   Test4: ED08 LD24 (HL),DE 通常アクセス(境界またぎ無し)。DE24=9A:5678hを
;          HL24=01:9030hの指すアドレスへ書込み、Test3と同じ(BC)間接読出しで
;          確認する。
;   Test5: ED00 64KBバンク境界またぎ読込み(本プログラムの最重要テスト)。
;          HL24=01:FFFEhの指す3byte(mem[01:FFFE]=CDh,mem[01:FFFF]=ABh,
;          mem[02:0000]=07h、3byte目がbank01hからbank02hへ境界をまたぐ)を
;          BC24へロードし、BC24=07:ABCDhになること、およびHL24自体が
;          (繰り上がらず)01:FFFEhのまま変化しないことを確認する。
;   Test6: ED03 64KBバンク境界またぎ書込み(本プログラムの最重要テスト、
;          Test5と対になる書込み版)。HL24=01:FFFEh、BC24=42:BEEFhを書込み、
;          (BC)間接読出しで01:FFFEh=EFh,01:FFFFh=BEh,02:0000h=42h(bank02hへ
;          境界またぎ)が実際に書き込まれたことを確認する。
;   Test_F: ED00の前後でF(フラグ)レジスタが変化しないことを確認する
;          (仕様上「F不変」)。
;
; 【実機安全性についての注意:FFFFFFhラップアラウンド試験は含まない】
;   tb_ld24_mem_indirect.vhd(GHDLシミュレーション版)にはTest9として、
;   HL24=FFh:FFFEhから3byte目がbank FFhからbank00hアドレス0000hへラップ
;   アラウンドする試験が含まれている。しかしbank00hはMSX互換の既存64KB
;   空間(実行中の本プログラム自身やMSX-DOS/BIOSが置かれている領域)を
;   SD-RAM拡張メモリ経路を経由せず直接参照するため、この試験を実機で
;   そのまま行うと実行中のプログラムコードやBIOSワークエリアを誤って
;   破壊しかねない。GHDLシミュレーション(閉じた仮想メモリ空間)でのみ
;   安全に検証可能な項目と判断し、本プログラムには含めていない。
;
; 安全設計上の注意:
;   - ED00/01/03/08はmode24_r(SET_M0/M1/M2)によるbank bypassルールに従う
;     (既存の(HL)/(BC)/(DE)間接アクセスと同じ規約)。そのため本プログラムは
;     各測定はDI→SET_M1→結果の絶対アドレス保存→SET_M0→EIで囲む。
;     比較・カウンタ更新・BDOS呼出しは必ずM0で行う。
;   - 本プログラムが使用する物理bankは01h/02hのみで、fpga/top.vの
;     CPU_SDRAM_BASE(0x640000)経由の安全な拡張領域(0x650000以降)に収まり、
;     既存のMemory Mapper(0x000000-)やMegaRAM(0x400000-)とは重ならない
;     (詳細はdoc/jpn/SDRAMメモリマップ.md 2.2章)。bank00h(実行中のプログラム
;     自身の64KB空間)には一切到達しない。
;   - Test5/Test6(境界またぎ)の直後には、Push24Testと同じ診断用の画面色
;     マーカー(MARK)を配置している。これは、PUSH24/POP24のbank境界またぎ
;     バグ調査でTest8(単体POP24)が実機フリーズを起こした前例があるため、
;     もし本プログラムの境界またぎ試験が同様にフリーズした場合でも、どこ
;     まで実行が進んでいたかを画面の背景色から目視で特定できるようにする
;     ためである。
;   - 各測定終了時にSET_M0で通常のZ80互換モードへ戻し、
;     BC/DE/HL/IX/IYバンクレジスタを0クリアしてから割込みを許可する
;     (SAFE_RESET参照)。
;
; ビルド: makefile参照 (z88dk-z80asm + z88dk-appmake)
; 実行: MSX-DOS(2)のコマンドラインから `LD24MI` と入力する。
;   (実行ファイル名はMSX-DOSの8.3形式に合わせ LD24MI.COM としている)
;==============================================================================

	org	$0100

;------------------------------------------------------------------------------
; MSX-DOS / BDOS
;------------------------------------------------------------------------------
BDOS		EQU	0005H		; DOS function entry
BDOS_TERM0	EQU	0		; BDOS function 0: プログラム終了、MSX-DOSへ復帰
VDP_PORT	EQU	099H		; VDPコントロールポート(直接OUT用。診断
					; マーカーの書込みはBIOS WRTVDPを経由せず
					; ここへ直接OUTする。Push24Testと同じ方式)
RG7SAV		EQU	0F3E6H		; VDP R#7 現在値のBIOSシャドウ変数(背景色。
					; 診断マーカーで変更する前に退避し、終了後に
					; 元へ復元するために使用)

;------------------------------------------------------------------------------
; Z80X24 独自オペコード (標準Z80アセンブラには無いため DEFB で直接発行する)
;------------------------------------------------------------------------------
; ED 90        SET_M0                          (モード制御、終了前の復帰に使用)
; ED 91        SET_M1                          (割込み禁止の測定区間だけで使用)
; ED 04/0C     LD BC_B,A / LD A,BC_B           (Phase1)
; ED 14/1C     LD DE_B,A / LD A,DE_B           (Phase1)
; ED 24/2C     LD HL_B,A / LD A,HL_B           (Phase1)
; ED 00        LD24 BC,(HL)                    (本プログラムの対象、2026-10-19実装)
; ED 01        LD24 DE,(HL)                    (本プログラムの対象、2026-10-19実装)
; ED 03        LD24 (HL),BC                    (本プログラムの対象、2026-10-19実装)
; ED 08        LD24 (HL),DE                    (本プログラムの対象、2026-10-19実装)
;------------------------------------------------------------------------------

;==============================================================================
; エントリポイント
;==============================================================================
START:
	DI
	DEFB	0EDH,090H		; SET_M0
	CALL	SAFE_RESET
	EI
	XOR	A
	LD	(PASS_COUNT),A
	LD	(FAIL_COUNT),A
	LD	DE,MSG_BANNER
	CALL	PRINT_STR

	; ---- 診断マーカー用に、現在のVDP R#7(背景色)をBIOSシャドウ変数から
	; 退避しておく(プログラム終了後に元の色へ復元するため)。----
	LD	A,(RG7SAV)
	LD	(ORIG_R7),A

	; ==== Test1: ED00 LD24 BC,(HL) 通常アクセス(境界またぎ無し) ====
	; HL24=01:9000hの指す3byte(AAh,99h,05h)をBC24へロードする。
	; 期待値: BC24=05:99AAh。
	; まず(BC)間接書込みで、01:9000h/9001h/9002hへ事前にパターンを
	; 書き込んでおく(Phase3で検証済みの経路、ED00/01/03/08のロジックとは
	; 完全に独立)。
	CALL	ENTER_TEST
	LD	IY,PD_T1
	CALL	MEMPAT			; 00/FF/55AA/AA55/反転/正解値の書込み・読戻し
	LD	BC,9000H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,0AAH
	LD	(BC),A			; 01:9000h = AAh (LOW)

	LD	BC,9001H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,099H
	LD	(BC),A			; 01:9001h = 99h (HIGH)

	LD	BC,9002H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,005H
	LD	(BC),A			; 01:9002h = 05h (BANK)

	LD	BC,9000H
	LD	A,(BC)
	LD	(T1_PREP),A
	INC	BC
	LD	A,(BC)
	LD	(T1_PREP+1),A
	INC	BC
	LD	A,(BC)
	LD	(T1_PREP+2),A

	; HL24=01:9000hを設定し、BC24を一旦別の値で破壊してからED00を実行する。
	LD	HL,9000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	BC,0000H
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A (clobber)
	DEFB	0EDH,000H		; LD24 BC,(HL)  ** テスト対象 **

	LD	(T1_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T1_BC_BANK),A
	; HL24自体が不変であることも確認する(アドレス元が破壊されていないか)。
	LD	(T1_HL_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T1_HL_BANK),A

	CALL	LEAVE_TEST
	LD	DE,MSG_T1_PAT
	CALL	PAT_REPORT

	LD	HL,99AAH
	LD	B,05H
	LD	DE,MSG_T1_PREP
	LD	IX,T1_PREP
	CALL	CHECK24_IX

	LD	HL,99AAH
	LD	B,05H
	LD	DE,MSG_T1
	LD	IX,T1_BC_LO
	CALL	CHECK24_IX

	LD	HL,9000H
	LD	B,01H
	LD	DE,MSG_T1_HL
	LD	IX,T1_HL_LO
	CALL	CHECK24_IX

	; ==== Test2: ED01 LD24 DE,(HL) 通常アクセス(境界またぎ無し) ====
	; HL24=01:9010hの指す3byte(11h,22h,33h)をDE24へロードする。
	; 期待値: DE24=33:2211h。
	CALL	ENTER_TEST
	LD	IY,PD_T2
	CALL	MEMPAT
	LD	BC,9010H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,011H
	LD	(BC),A			; 01:9010h = 11h (LOW)

	LD	BC,9011H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,022H
	LD	(BC),A			; 01:9011h = 22h (HIGH)

	LD	BC,9012H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,033H
	LD	(BC),A			; 01:9012h = 33h (BANK)

	LD	BC,9010H
	LD	A,(BC)
	LD	(T2_PREP),A
	INC	BC
	LD	A,(BC)
	LD	(T2_PREP+1),A
	INC	BC
	LD	A,(BC)
	LD	(T2_PREP+2),A

	LD	HL,9010H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	DE,0000H
	XOR	A
	DEFB	0EDH,014H		; LD DE_B,A (clobber)
	DEFB	0EDH,001H		; LD24 DE,(HL)  ** テスト対象 **

	LD	(T2_DE_LO),DE
	DEFB	0EDH,01CH		; LD A,DE_B
	LD	(T2_DE_BANK),A
	LD	(T2_HL_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T2_HL_BANK),A

	CALL	LEAVE_TEST
	LD	DE,MSG_T2_PAT
	CALL	PAT_REPORT

	LD	HL,2211H
	LD	B,33H
	LD	DE,MSG_T2_PREP
	LD	IX,T2_PREP
	CALL	CHECK24_IX

	LD	HL,2211H
	LD	B,33H
	LD	DE,MSG_T2
	LD	IX,T2_DE_LO
	CALL	CHECK24_IX

	LD	HL,9010H
	LD	B,01H
	LD	DE,MSG_T2_HL
	LD	IX,T2_HL_LO
	CALL	CHECK24_IX

	; ==== Test3: ED03 LD24 (HL),BC 通常アクセス(境界またぎ無し) ====
	; BC24=EE:1234h(B=12h,C=34h)をHL24=01:9020hの指すアドレスへ書込む。
	; 期待値: 01:9020h=34h(LOW),01:9021h=12h(HIGH),01:9022h=EEh(BANK)。
	CALL	ENTER_TEST
	; 最後に期待値の反転を残し、ED03の書込み消失を検出できるようにする。
	LD	IY,PD_T3
	CALL	MEMPAT
	LD	HL,9020H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	BC,1234H
	LD	A,0EEH
	DEFB	0EDH,004H		; LD BC_B,A (=EEh)
	DEFB	0EDH,003H		; LD24 (HL),BC  ** テスト対象 **

	; (BC)間接読出し(ED03/ED08のロジックとは独立した経路)で、実際に
	; 書き込まれた内容を直接確認する。
	LD	BC,9020H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T3_PEEK_LO),A

	LD	BC,9021H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T3_PEEK_HI),A

	LD	BC,9022H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T3_PEEK_BANK),A

	CALL	LEAVE_TEST
	LD	DE,MSG_T3_PAT
	CALL	PAT_REPORT

	LD	HL,1234H
	LD	B,0EEH
	LD	DE,MSG_T3
	LD	IX,T3_PEEK_LO
	CALL	CHECK24_IX

	; ==== Test4: ED08 LD24 (HL),DE 通常アクセス(境界またぎ無し) ====
	; DE24=9A:5678h(D=56h,E=78h)をHL24=01:9030hの指すアドレスへ書込む。
	; 期待値: 01:9030h=78h(LOW),01:9031h=56h(HIGH),01:9032h=9Ah(BANK)。
	CALL	ENTER_TEST
	LD	IY,PD_T4
	CALL	MEMPAT
	LD	HL,9030H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	DE,5678H
	LD	A,09AH
	DEFB	0EDH,014H		; LD DE_B,A (=9Ah)
	DEFB	0EDH,008H		; LD24 (HL),DE  ** テスト対象 **

	LD	BC,9030H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T4_PEEK_LO),A

	LD	BC,9031H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T4_PEEK_HI),A

	LD	BC,9032H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T4_PEEK_BANK),A

	CALL	LEAVE_TEST
	LD	DE,MSG_T4_PAT
	CALL	PAT_REPORT

	LD	HL,5678H
	LD	B,09AH
	LD	DE,MSG_T4
	LD	IX,T4_PEEK_LO
	CALL	CHECK24_IX

	; ==== Test5: ED00 64KBバンク境界またぎ読込み(最重要テスト) ====
	; HL24=01:FFFEhの指す3byte(mem[01:FFFE]=CDh,mem[01:FFFF]=ABh,
	; mem[02:0000]=07h、3byte目がbank01hからbank02hへ境界をまたぐ)を
	; BC24へロードする。期待値: BC24=07:ABCDh。
	CALL	ENTER_TEST
	; ---- 診断マーカーF1: Test5でM1へ入った直後。----
	LD	A,0F1H
	CALL	MARK
	LD	IY,PD_T5
	CALL	MEMPAT			; 境界をまたぐ3byteのパターン試験
	LD	BC,0FFFEH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,0CDH
	LD	(BC),A			; 01:FFFEh = CDh (LOW)
	; ---- 診断マーカーF2: 01:FFFEh書込み完了。----
	LD	A,0F2H
	CALL	MARK

	LD	BC,0FFFFH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,0ABH
	LD	(BC),A			; 01:FFFFh = ABh (HIGH)
	; ---- 診断マーカーF3: 01:FFFFh書込み完了。----
	LD	A,0F3H
	CALL	MARK

	LD	BC,0000H
	LD	A,02H
	DEFB	0EDH,004H		; LD BC_B,A (=02h)
	LD	A,007H
	LD	(BC),A			; 02:0000h = 07h (BANK、境界をまたいだ先)
	; ---- 診断マーカーF4: 02:0000h書込み完了。----
	LD	A,0F4H
	CALL	MARK

	LD	BC,0FFFEH
	LD	A,01H
	DEFB	0EDH,004H
	LD	A,(BC)
	LD	(T5_PREP),A
	INC	BC
	LD	A,(BC)
	LD	(T5_PREP+1),A
	LD	BC,0000H
	LD	A,02H
	DEFB	0EDH,004H
	LD	A,(BC)
	LD	(T5_PREP+2),A

	; ---- 診断マーカーF5: ED00(境界またぎ)実行直前。----
	LD	A,0F5H
	CALL	MARK

	LD	HL,0FFFEH
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	BC,0000H
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A (clobber)
	DEFB	0EDH,000H		; LD24 BC,(HL)  ** テスト対象(境界またぎ読込み) **

	; ---- 診断マーカーF6: ED00(境界またぎ)実行直後。----
	LD	A,0F6H
	CALL	MARK

	LD	(T5_BC_LO),BC
	DEFB	0EDH,00CH		; LD A,BC_B
	LD	(T5_BC_BANK),A
	LD	(T5_HL_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T5_HL_BANK),A

	; ---- 診断マーカーE1: Test5結果回収完了。----
	LD	A,0E1H
	CALL	MARK

	CALL	LEAVE_TEST
	LD	DE,MSG_T5_PAT
	CALL	PAT_REPORT

	LD	HL,0ABCDH
	LD	B,07H
	LD	DE,MSG_T5_PREP
	LD	IX,T5_PREP
	CALL	CHECK24_IX

	LD	HL,0ABCDH
	LD	B,07H
	LD	DE,MSG_T5
	LD	IX,T5_BC_LO
	CALL	CHECK24_IX

	; HL24自体は繰り上がらず、01:FFFEhのまま変化しないはず。
	LD	HL,0FFFEH
	LD	B,01H
	LD	DE,MSG_T5_HL
	LD	IX,T5_HL_LO
	CALL	CHECK24_IX

	; ==== Test6: ED03 64KBバンク境界またぎ書込み(最重要テスト、Test5の
	; 書込み版) ====
	; HL24=01:FFFEh、BC24=42:BEEFh(B=BEh,C=EFh)を書込む。期待値:
	; 01:FFFEh=EFh(LOW),01:FFFFh=BEh(HIGH),02:0000h=42h(BANK、境界を
	; またいだ先)。
	; ---- 診断マーカー4: Test6準備完了、ED03(境界またぎ)実行前。----
	CALL	ENTER_TEST
	LD	A,0E2H
	CALL	MARK
	LD	IY,PD_T6
	CALL	MEMPAT			; 最後に期待値の反転を残す

	LD	HL,0FFFEH
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	LD	BC,0BEEFH
	LD	A,042H
	DEFB	0EDH,004H		; LD BC_B,A (=42h)
	DEFB	0EDH,003H		; LD24 (HL),BC  ** テスト対象(境界またぎ書込み) **

	; ---- 診断マーカー5: ED03(境界またぎ)実行直後。----
	LD	A,0E3H
	CALL	MARK

	LD	BC,0FFFEH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T6_PEEK_LO),A

	LD	BC,0FFFFH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T6_PEEK_HI),A

	LD	BC,0000H
	LD	A,02H
	DEFB	0EDH,004H		; LD BC_B,A (=02h)
	LD	A,(BC)
	LD	(T6_PEEK_BANK),A

	; ---- 診断マーカー6: 結果回収完了。----
	LD	A,0E4H
	CALL	MARK

	CALL	LEAVE_TEST
	LD	DE,MSG_T6_PAT
	CALL	PAT_REPORT

	LD	HL,0BEEFH
	LD	B,042H
	LD	DE,MSG_T6
	LD	IX,T6_PEEK_LO
	CALL	CHECK24_IX

	; ==== Test_F: ED00の前後でF(フラグ)レジスタが変化しないことを確認 ====
	; F不変の確認手法はLD24Test/Push24Testと同一(PUSH AF/POP BC/LD A,C
	; でFをAへ写し取り、BDOS呼出しを挟まず直接比較する)。
	CALL	ENTER_TEST
	LD	BC,9000H
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	HL,9000H
	DEFB	0EDH,024H		; LD HL_B,A (=01h、直前のAをそのまま再利用)
	LD	A,55H
	CP	0AAH			; deterministic nonzero flags, including carry
	PUSH	AF
	POP	BC
	LD	A,C			; A <- F(直前のスナップショット)
	LD	(TF_BEFORE),A

	DEFB	0EDH,000H		; LD24 BC,(HL)  (使い捨ての結果、Fのみ確認)

	PUSH	AF
	POP	BC
	LD	A,C			; A <- F(直後のスナップショット)
	LD	(TF_AFTER),A

	CALL	LEAVE_TEST
	LD	DE,MSG_TF
	CALL	PRINT_STR
	LD	DE,MSG_COLON
	CALL	PRINT_STR
	LD	A,(TF_BEFORE)
	LD	HL,TF_AFTER
	CP	(HL)
	JR	NZ,TF_FAIL
	LD	DE,MSG_PASS
	CALL	PRINT_STR
	LD	HL,PASS_COUNT
	INC	(HL)
	JR	TF_DONE
TF_FAIL:
	LD	DE,MSG_FAIL_SIMPLE
	CALL	PRINT_STR
	LD	HL,FAIL_COUNT
	INC	(HL)
TF_DONE:
	LD	DE,MSG_CRLF
	CALL	PRINT_STR

	; ---- 全テスト完了。退避しておいた元のVDP R#7(背景色)へ復元する。----
	DI
	LD	A,(ORIG_R7)
	CALL	MARK
	EI

	; ---- 安全のため、SET_M0へ戻し、使用したバンクレジスタを0クリアする ----
	DEFB	0EDH,090H		; SET_M0
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
	RET

ENTER_TEST:
	DI
	DEFB	0EDH,091H		; SET_M1
	RET

LEAVE_TEST:
	DEFB	0EDH,090H		; SET_M0 before clearing captured banks
	CALL	SAFE_RESET
	EI
	RET

;==============================================================================
; MARK : 診断用の画面色マーカー。Aの値をそのままVDP R#7(背景色)へ直接OUTする
;   (Push24Testで使用した方式と同じ)。Test5/Test6(境界またぎ)の各ステップの
;   直後に異なる値でCALLする。BDOSのメッセージ表示より確実に即座に画面へ
;   反映されるため、万一この後でCPU/メモリバスが完全にハングしても、最後に
;   表示されていた色から「どこまで実行が進んでいたか」を目視で特定できる。
;   呼出し側でDIする。F1h～F6hは文字色を白に保ち背景だけを変更する。
;   破壊するレジスタ: なし(AF退避/復帰)。
;==============================================================================
MARK:
	PUSH	AF
	OUT	(VDP_PORT),A
	LD	A,87H			; R#7 | 80h (レジスタ書込みモード)
	OUT	(VDP_PORT),A
	POP	AF
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
;   (LD24Test/Push24TestのCHECK24_IXと同一のルーチン)。
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

;==============================================================================
; MEMPAT : 3byte領域の書込み・読戻しパターン試験 (DI/M1中に呼ぶ)
;   入力: IY = 記述子 (bank00):
;           +0..+2 1byte目の low,high,bank / +3..+5 2byte目 / +6..+8 3byte目
;           +9..+11 最後に残す値(V0,V1,V2)
;   手順: 00 → FF → 55,AA,55 → AA,55,AA → 反転V → V の6段階で、
;         毎回3byteを書いてから3byteを読み戻して比較する。
;   出力: PAT_ERR=最初に不一致だった段階(0=全一致)、
;         PAT_ERR_GOT/PAT_ERR_WANT=その段階の実測値/期待値(全一致時はV)。
;   M1では(BC)だけを拡張アクセスに使い、作業変数は絶対アドレス/
;   HL_B=DE_B=0の(HL)/(DE)でbank00へアクセスする。
;==============================================================================
MEMPAT:
	XOR	A
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,024H		; LD HL_B,A
	LD	(PAT_ERR),A
	LD	A,(IY+9)
	LD	(PAT_ERR_GOT),A
	LD	(PAT_ERR_WANT),A
	LD	A,(IY+10)
	LD	(PAT_ERR_GOT+1),A
	LD	(PAT_ERR_WANT+1),A
	LD	A,(IY+11)
	LD	(PAT_ERR_GOT+2),A
	LD	(PAT_ERR_WANT+2),A
	LD	A,1
	LD	(PAT_STEP),A
MP_LOOP:
	LD	A,(PAT_STEP)
	CP	5
	JR	NC,MP_FINAL
	DEC	A
	LD	E,A
	ADD	A,A
	ADD	A,E
	LD	E,A
	LD	D,0
	LD	HL,PAT_TBL
	ADD	HL,DE
	LD	A,(HL)
	LD	(PAT_CUR),A
	INC	HL
	LD	A,(HL)
	LD	(PAT_CUR+1),A
	INC	HL
	LD	A,(HL)
	LD	(PAT_CUR+2),A
	JR	MP_WRITE
MP_FINAL:
	LD	A,(IY+9)
	LD	(PAT_CUR),A
	LD	A,(IY+10)
	LD	(PAT_CUR+1),A
	LD	A,(IY+11)
	LD	(PAT_CUR+2),A
	LD	A,(PAT_STEP)
	CP	5
	JR	NZ,MP_WRITE
	LD	HL,PAT_CUR
	LD	A,(HL)
	CPL
	LD	(HL),A
	INC	HL
	LD	A,(HL)
	CPL
	LD	(HL),A
	INC	HL
	LD	A,(HL)
	CPL
	LD	(HL),A
MP_WRITE:
	LD	C,(IY+0)
	LD	B,(IY+1)
	LD	A,(IY+2)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(PAT_CUR)
	LD	(BC),A
	LD	C,(IY+3)
	LD	B,(IY+4)
	LD	A,(IY+5)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(PAT_CUR+1)
	LD	(BC),A
	LD	C,(IY+6)
	LD	B,(IY+7)
	LD	A,(IY+8)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(PAT_CUR+2)
	LD	(BC),A

	LD	C,(IY+0)
	LD	B,(IY+1)
	LD	A,(IY+2)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(BC)
	LD	(PAT_GOT),A
	LD	C,(IY+3)
	LD	B,(IY+4)
	LD	A,(IY+5)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(BC)
	LD	(PAT_GOT+1),A
	LD	C,(IY+6)
	LD	B,(IY+7)
	LD	A,(IY+8)
	DEFB	0EDH,004H		; LD BC_B,A
	LD	A,(BC)
	LD	(PAT_GOT+2),A

	LD	HL,PAT_GOT
	LD	DE,PAT_CUR
	LD	B,3
MP_CMP:
	LD	A,(DE)
	CP	(HL)
	JR	NZ,MP_BAD
	INC	HL
	INC	DE
	DJNZ	MP_CMP
	JR	MP_NEXT
MP_BAD:
	LD	A,(PAT_ERR)
	OR	A
	JR	NZ,MP_NEXT
	LD	A,(PAT_STEP)
	LD	(PAT_ERR),A
	LD	A,(PAT_GOT)
	LD	(PAT_ERR_GOT),A
	LD	A,(PAT_GOT+1)
	LD	(PAT_ERR_GOT+1),A
	LD	A,(PAT_GOT+2)
	LD	(PAT_ERR_GOT+2),A
	LD	A,(PAT_CUR)
	LD	(PAT_ERR_WANT),A
	LD	A,(PAT_CUR+1)
	LD	(PAT_ERR_WANT+1),A
	LD	A,(PAT_CUR+2)
	LD	(PAT_ERR_WANT+2),A
MP_NEXT:
	LD	A,(PAT_STEP)
	INC	A
	LD	(PAT_STEP),A
	CP	7
	JP	C,MP_LOOP
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A
	RET

; PAT_REPORT : MEMPATの結果を表示・集計する (M0で呼ぶ)。DE=テスト名。
;   FAIL時は got/want の後に、最初に失敗した段階番号を表示する。
PAT_REPORT:
	LD	HL,(PAT_ERR_WANT)
	LD	A,(PAT_ERR_WANT+2)
	LD	B,A
	LD	IX,PAT_ERR_GOT
	CALL	CHECK24_IX
	LD	A,(PAT_ERR)
	OR	A
	RET	Z
	LD	DE,MSG_PAT_STEP
	CALL	PRINT_STR
	LD	A,(PAT_ERR)
	CALL	PRINT_HEX
	LD	DE,MSG_CRLF
	CALL	PRINT_STR
	RET

; 終了前の安全な状態復元: 使用したバンクレジスタを0クリアする
SAFE_RESET:
	XOR	A
	DEFB	0EDH,004H		; LD BC_B,A
	DEFB	0EDH,014H		; LD DE_B,A
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,005H		; LD IX_B,A
	DEFB	0EDH,015H		; LD IY_B,A
	RET

;==============================================================================
; 文字出力ユーティリティ (MMUTest/LD24Test/Push24Test と同じ構成)
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
	DEFB	"Z80X24 LD24 mem-indirect v2 MODE-SAFE",13,10
	DEFB	"MSXnano-Z80X / msxnano-24bit",13,10,13,10,"$"

MSG_T1_PAT:	DEFB	"Test1 R/W patterns 01:9000$"
MSG_T2_PAT:	DEFB	"Test2 R/W patterns 01:9010$"
MSG_T3_PAT:	DEFB	"Test3 R/W patterns 01:9020$"
MSG_T4_PAT:	DEFB	"Test4 R/W patterns 01:9030$"
MSG_T5_PAT:	DEFB	"Test5 R/W patterns 01:FFFE-02:0000$"
MSG_T6_PAT:	DEFB	"Test6 R/W patterns 01:FFFE-02:0000$"
MSG_PAT_STEP:	DEFB	"  first failing step=$"
MSG_T1_PREP:	DEFB	"Test1 setup byte-readback$"
MSG_T2_PREP:	DEFB	"Test2 setup byte-readback$"
MSG_T5_PREP:	DEFB	"Test5 setup byte-readback across boundary$"
MSG_T1:		DEFB	"Test1 ED00 LD24 BC,(HL) normal read$"
MSG_T1_HL:	DEFB	"Test1 HL24 unchanged after ED00$"
MSG_T2:		DEFB	"Test2 ED01 LD24 DE,(HL) normal read$"
MSG_T2_HL:	DEFB	"Test2 HL24 unchanged after ED01$"
MSG_T3:		DEFB	"Test3 ED03 LD24 (HL),BC normal write$"
MSG_T4:		DEFB	"Test4 ED08 LD24 (HL),DE normal write$"
MSG_T5:		DEFB	"Test5 ED00 LD24 BC,(HL) across a bank boundary$"
MSG_T5_HL:	DEFB	"Test5 HL24 unchanged across the same boundary$"
MSG_T6:		DEFB	"Test6 ED03 LD24 (HL),BC across a bank boundary$"
MSG_TF:		DEFB	"Test_F F register unchanged by ED00$"

MSG_COLON:	DEFB	": $"
MSG_PASS:	DEFB	"PASS$"
MSG_FAIL:	DEFB	"FAIL (got=$"
MSG_FAIL_SIMPLE: DEFB	"FAIL$"
MSG_WANT:	DEFB	", want=$"
MSG_CRLF:	DEFB	13,10,"$"

MSG_DONE1:	DEFB	13,10,"PASS=$"
MSG_DONE2:	DEFB	" FAIL=$"

; --- CHECK24_IX用の退避領域 (BDOS呼出しでレジスタが破壊されても ----
; --- 安全に比較できるよう、期待値・実測値をここへ一旦コピーする) ----
CHK_EXP_LO:	DEFS	1
CHK_EXP_HI:	DEFS	1
CHK_EXP_BANK:	DEFS	1
CHK_ACT_LO:	DEFS	1
CHK_ACT_HI:	DEFS	1
CHK_ACT_BANK:	DEFS	1

; --- 各テストの実測値バッファ (低位word 2byte + バンクbyte 1byte の順) ---
; MEMPATの段階1〜4で書く固定パターン(各3byte)
PAT_TBL:	DEFB	000H,000H,000H
		DEFB	0FFH,0FFH,0FFH
		DEFB	055H,0AAH,055H
		DEFB	0AAH,055H,0AAH
; MEMPAT記述子: 3byteの24bitアドレス(low,high,bank)×3 + 最後に残す値
PD_T1:		DEFB	000H,090H,001H, 001H,090H,001H, 002H,090H,001H
		DEFB	0AAH,099H,005H
PD_T2:		DEFB	010H,090H,001H, 011H,090H,001H, 012H,090H,001H
		DEFB	011H,022H,033H
PD_T3:		DEFB	020H,090H,001H, 021H,090H,001H, 022H,090H,001H
		DEFB	0CBH,0EDH,011H		; 期待値34,12,EEの反転
PD_T4:		DEFB	030H,090H,001H, 031H,090H,001H, 032H,090H,001H
		DEFB	087H,0A9H,065H		; 期待値78,56,9Aの反転
PD_T5:		DEFB	0FEH,0FFH,001H, 0FFH,0FFH,001H, 000H,000H,002H
		DEFB	0CDH,0ABH,007H
PD_T6:		DEFB	0FEH,0FFH,001H, 0FFH,0FFH,001H, 000H,000H,002H
		DEFB	010H,041H,0BDH		; 期待値EF,BE,42の反転
PAT_STEP:	DEFS	1
PAT_ERR:	DEFS	1
PAT_CUR:	DEFS	3
PAT_GOT:	DEFS	3
PAT_ERR_GOT:	DEFS	3
PAT_ERR_WANT:	DEFS	3
T1_PREP:	DEFS	3
T2_PREP:	DEFS	3
T5_PREP:	DEFS	3
T1_BC_LO:	DEFS	2
T1_BC_BANK:	DEFS	1
T1_HL_LO:	DEFS	2
T1_HL_BANK:	DEFS	1
T2_DE_LO:	DEFS	2
T2_DE_BANK:	DEFS	1
T2_HL_LO:	DEFS	2
T2_HL_BANK:	DEFS	1
T3_PEEK_LO:	DEFS	1
T3_PEEK_HI:	DEFS	1
T3_PEEK_BANK:	DEFS	1
T4_PEEK_LO:	DEFS	1
T4_PEEK_HI:	DEFS	1
T4_PEEK_BANK:	DEFS	1
T5_BC_LO:	DEFS	2
T5_BC_BANK:	DEFS	1
T5_HL_LO:	DEFS	2
T5_HL_BANK:	DEFS	1
T6_PEEK_LO:	DEFS	1
T6_PEEK_HI:	DEFS	1
T6_PEEK_BANK:	DEFS	1

TF_BEFORE:	DEFS	1
TF_AFTER:	DEFS	1

ORIG_R7:	DEFS	1		; 診断マーカー用、元のVDP R#7退避先

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
