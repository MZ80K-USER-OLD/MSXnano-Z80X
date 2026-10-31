;==============================================================================
; PUSH24_TEST.ASM - Z80X24 Phase9 "PUSH24/POP24" 実機テストプログラム (MSX-DOS .COM)
;
; MSXnano-Z80X (msxnano-24bit) の 24bit CPU拡張 (Z80X24) における
; Phase9「PUSH24/POP24」を、実機/エミュレータ上のMSX-DOS(2)から起動して
; 確認するためのテストプログラムです。
;
;   doc/jpn/doc/jpn/OLD/MSX_T80_24bit化_実装手順_V2_2026-10-05.md セクション11 "Phase 9"
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
;   Test7: bank境界をまたぎPUSH24/POP24往復試験(旧Test6相当、下記
;          「bank境界またぎPUSH24/POP24の再検証について」参照)。
;   Test8: POP24単体でのbank境界またぎ試験(PUSH24を経由せず、(BC)書込み
;          でメモリを直接用意してからPOP24のみ実行する。Test7がPUSH24
;          直後のPOP24という特殊な連続実行パターンに起因する問題なのか、
;          POP24単体のbank境界またぎ自体が問題なのかを切り分ける)。
;
; 【bank境界またぎPUSH24/POP24の再検証について】
;   当初はMSP24=02:0001hからPUSH24 HLを実行し、3回のデクリメントで
;   02:0001->02:0000->01:FFFF(bank borrow)->01:FFFEとbankをまたぐ試験
;   (旧Test6)を含めていたが、実機検証でTest5c完了直後にシステムが
;   フリーズする現象が再現した(GHDLシミュレーション(tb_phase9_push24_
;   pop24.vhd)ではこのシナリオは問題なくPASSしていたため、これは
;   実機固有の問題と判断される)。1命令内で複数の異なる物理bankへ
;   連続して書き込む(=SD-RAMコントローラが応答する前に物理bankが
;   切り替わる)経路は、Phase3/5の既存拡張メモリアクセス(1命令につき
;   拡張アクセス1回のみ)では一度も検証されておらず、本プロジェクトの
;   SD-RAMコントローラ(fpga/src/memory.v)にはCPU側へのWAIT状態生成
;   機構が存在しなかった(fpga/top.vのex_bus_wait_nは常時'1'固定)ため、
;   bankをまたぐ書込みがコントローラの内部処理時間を超過し、誤った
;   アドレスを破壊した可能性が疑われていた。
;
;   この根本原因調査の結果、fpga/src/memory.v(memory_ctrl)の
;   SDRAM調停ステートマシンに、CPU側へのWAIT状態生成に使える
;   cpu_sdram_busy出力を新設し、fpga/top.vでこれを基にした
;   cpu_sdram_wait_nをCPUのWAIT_n入力へAND結合する修正を実施した
;   (詳細はfpga/src/memory.v・fpga/top.vの該当コメント、および
;   AVAILABLE_INSTRUCTIONS.mdセクション7参照)。この修正により、
;   bank境界をまたぐ連続アクセス中はSDRAMコントローラがアドレス/
;   書込みフラグを安全にラッチし終えるまでCPUが待機するようになり、
;   本問題が解消される見込みである。Test7は、この修正を実機で検証
;   するために復元した、まさにこの境界またぎシナリオ(MSP24=02:0001h
;   からのPUSH24/POP24往復、PUSH24はbank境界を下向きに、POP24は
;   同じ境界を上向きにまたぐ)である。Test7がPASSすれば、この修正が
;   実機で機能していることが確認できる。
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
;     01h/02h/03h/04h/05hのみで、これはfpga/top.vのCPU_SDRAM_BASE
;     (0x640000)経由で、既存のMemory Mapper(0x000000-)やMegaRAM
;     (0x400000-)とは重ならない安全な領域(0x650000以降)に収まる
;     (詳細はdoc/jpn/SDRAMメモリマップ.md 2.2章)。Test7(bank境界
;     またぎ往復試験)は意図的にbank01h/02hの境界(02:0000h⇔01:FFFFh)
;     をまたぐが、この境界も含め本プログラムが使用する全bankは
;     01h〜05hの範囲に収まっており、bank00h(実行中のプログラム自身の
;     64KB空間)には一切到達しない。
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
VDP_PORT	EQU	099H		; VDPコントロールポート(直接OUT用。診断
					; マーカーの書込みはBIOS WRTVDPを経由せず
					; ここへ直接OUTする。P1314Testと同じ方式)
RG7SAV		EQU	0F3E6H		; VDP R#7 現在値のBIOSシャドウ変数(背景色。
					; 診断マーカーで変更する前に退避し、Test7
					; 終了後に元へ復元するために使用)

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

	; ---- 【一時切り分け】Test7本体を無効化し、Test8のみを単独実行する。----
	; Test7(PUSH24直後にPOP24を実行する構成)とTest8(PUSH24を経由せず
	; (BC)書込みで直接メモリを用意してからPOP24単体を実行する構成)の
	; どちらが実機フリーズの原因かを切り分けるため、一時的にTest7の
	; 命令列(PUSH24 HL/POP24 HLの連続実行、診断マーカー1〜5)を丸ごと
	; スキップし、Test8の開始地点(診断マーカー6の手前)へ直接ジャンプ
	; する。Test7をもう一度有効化する際は、この"JP TEST8_ONLY"の1行を
	; 削除するだけでよい(Test7の命令列自体はそのまま残してある)。
	; なお、Test7冒頭で行っていたT7_ORIG_R7(診断マーカー色の復元用
	; 退避値)の設定だけはスキップすると未初期化値が残ってしまうため、
	; ここで代わりに行っておく。
	LD	A,(RG7SAV)
	LD	(T7_ORIG_R7),A

	; 2026-10-22: Test8単独版が実機でPASS=0A FAIL=00となったため、
	; バス分離RTL上でTest7を再有効化した(JP TEST8_ONLYを削除)。

	; ==== Test7: bank境界をまたぐPUSH24/POP24往復試験 ====
	; MSP24=02:0001hからPUSH24 HLを実行すると、3回のデクリメントで
	; 02:0001h->02:0000h(BANK byte、境界またぎ無し)->01:FFFFh(bank
	; borrow、HIGH byte)->01:FFFEh(LOW byte)とbank境界を下向きに
	; またぐ。続くPOP24 HLは逆方向(01:FFFEh->01:FFFFh->02:0000h->
	; 02:0001h、同じ境界を上向きにまたぐ)で元のMSP24へ復帰するはず。
	; HL24の値だけでなく、MSP24自体がbank境界またぎを経て正しく
	; 02:0001hへ戻ることも、LD24 HL,MSP(ED 36)で直接読み出して確認
	; する(詳細な背景は本ファイル冒頭「bank境界またぎPUSH24/POP24の
	; 再検証について」参照)。
	LD	HL,0001H
	LD	A,02H
	DEFB	0EDH,024H		; LD HL_B,A (=02h)
	DEFB	0EDH,035H		; LD24 MSP,HL  (MSP24 = 02:0001h)

	; ---- 診断マーカー用に、現在のVDP R#7(背景色)をBIOSシャドウ変数
	; から退避しておく(Test7終了後に元の色へ復元するため)。----
	LD	A,(RG7SAV)
	LD	(T7_ORIG_R7),A

	; ---- 診断マーカー1: MSP24=02:0001hの設定完了直後(PUSH24実行前)。
	; ここまでは従来のTest1-6と同じ命令しか使っていないため、もし
	; このマーカーすら表示されない場合はTest7固有の問題ではない。----
	LD	A,01H
	CALL	MARK

	LD	HL,99AAH
	LD	A,05H
	DEFB	0EDH,024H		; LD HL_B,A (=05h、PUSH24対象の値)
	DEFB	0EDH,0E5H		; PUSH24 HL  ** テスト対象(bank境界またぎ、下向き) **

	; ---- 診断マーカー2: PUSH24 HL(bank境界またぎ、下向き)の直後。
	; もしフリーズがPUSH24 HL自体の実行中に起きている場合、この
	; マーカーは表示されずマーカー1の色のまま止まる。----
	LD	A,02H
	CALL	MARK

	; ---- PUSH24が書き込んだメモリの中身を、POP24/MSP24の仕組みを
	; 一切経由せず直接確認する(SET_M1でデータアクセスのみ24bit拡張
	; アドレッシングを有効にし、(BC)register-indirect読出しで3byteを
	; 個別に読む。Phase3で検証済みの経路であり、PUSH24/POP24のMSP24
	; 加減算ロジックとは完全に独立しているため、「PUSH24の書込み自体」
	; と「POP24の読出し/MSP24追跡」のどちらに問題があるかを切り分け
	; られる)。期待値: 01:FFFEh=AAh(LOW), 01:FFFFh=99h(HIGH),
	; 02:0000h=05h(BANK)。----
	DEFB	0EDH,091H		; SET_M1 (データアクセスのみ拡張アドレッシング)

	LD	BC,0FFFEH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T7_PEEK_LO),A		; 期待値 AAh (LOW byte)

	LD	BC,0FFFFH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,(BC)
	LD	(T7_PEEK_HI),A		; 期待値 99h (HIGH byte)

	LD	BC,0000H
	LD	A,02H
	DEFB	0EDH,004H		; LD BC_B,A (=02h)
	LD	A,(BC)
	LD	(T7_PEEK_BANK),A	; 期待値 05h (BANK byte)

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)

	; ---- 診断マーカー3: PUSH24直後のメモリ直接確認(peek)完了直後。
	; マーカー2までは表示されマーカー3が表示されない場合、SET_M1配下
	; の(BC)読出し自体に問題がある(PUSH24自体ではない)ことになる。----
	LD	A,03H
	CALL	MARK

	LD	HL,99AAH
	LD	B,05H
	LD	DE,MSG_T7_PEEK
	LD	IX,T7_PEEK_LO
	CALL	CHECK24_IX

	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,0E1H		; POP24 HL  ** テスト対象(bank境界またぎ、上向き) **

	; ---- 診断マーカー4: POP24 HL(bank境界またぎ、上向き)の直後。
	; マーカー3までは表示されマーカー4が表示されない場合、フリーズは
	; POP24 HL自体の実行中に起きていることになる。----
	LD	A,04H
	CALL	MARK

	LD	(T7_HL_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T7_HL_BANK),A

	LD	HL,99AAH
	LD	B,05H
	LD	DE,MSG_T7
	LD	IX,T7_HL_LO
	CALL	CHECK24_IX

	; MSP24自体がbank02:0001hへ正しく復帰したことを直接確認する
	; (LD24 HL,MSPでMSP24をHL24へ読み出す。HLは直前のCHECK24_IXで
	; 既に使用済みのため破壊して問題ない)。
	DEFB	0EDH,036H		; LD HL,MSP  (=LD24 HL,MSP)

	; ---- 診断マーカー5: LD24 HL,MSP(ED 36、MSP24読出し)の直後。
	; マーカー4までは表示されマーカー5が表示されない場合、PUSH24/
	; POP24自体ではなくLD24 HL,MSP側に問題があることになる。----
	LD	A,05H
	CALL	MARK

	LD	(T7_MSP_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T7_MSP_BANK),A

	LD	HL,0001H
	LD	B,02H
	LD	DE,MSG_T7_MSP
	LD	IX,T7_MSP_LO
	CALL	CHECK24_IX

	; ==== Test8: POP24単体でのbank境界またぎ試験(PUSH24を経由しない) ====
	; Test7はPUSH24直後にPOP24を実行する構成だったため、もし2命令の
	; 連続実行自体(SDRAMコントローラの残留状態など)が原因だった場合、
	; POP24単体では問題が再現しない可能性がある。これを切り分けるため、
	; PUSH24を一切使わず、(BC)register-indirect書込み(peekと同じ
	; SET_M1経路)で対象の3byteを直接メモリへ書いてからLD24 MSP,HLで
	; MSP24を01:FFFEhへ直接設定し、POP24 HLのみを単独で実行する。
	; Test7と同じ想定結果(HL24=05:99AAh、MSP24=02:0001h)になるはずである。
TEST8_ONLY:
	DEFB	0EDH,091H		; SET_M1 (データアクセスのみ拡張アドレッシング)

	; ---- 診断マーカー7: SET_M1直後。これが表示されない場合、Test7側の
	; マーカー6完了後、通常のZ80命令(JP/LD/CALL MARK)自体が既に動作
	; していない(BDOS復帰やVDPポートアクセス自体に問題がある)ことに
	; なり、Test8固有の問題ではなく、むしろ直前のTest7側処理(診断
	; マーカー5以降の処理やCHECK24_IX呼出し)に原因がある可能性が高い。
	LD	A,07H
	CALL	MARK

	LD	BC,0FFFEH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,0AAH
	LD	(BC),A			; 01:FFFEh = AAh (LOW byte)

	; ---- 診断マーカー8: 01:FFFEhへの(BC)書込み直後。Test7のpeek診断
	; では(BC)経由の"読出し"は実機で動作実績があるが、"書込み"は
	; Test8で初めて行うため、これが新規未検証の箇所になる。7は表示
	; され8が表示されない場合、この(BC)書込み自体でフリーズしている
	; ことになる。----
	LD	A,08H
	CALL	MARK

	LD	BC,0FFFFH
	LD	A,01H
	DEFB	0EDH,004H		; LD BC_B,A (=01h)
	LD	A,099H
	LD	(BC),A			; 01:FFFFh = 99h (HIGH byte)

	; ---- 診断マーカー9: 01:FFFFhへの(BC)書込み直後。----
	LD	A,09H
	CALL	MARK

	LD	BC,0000H
	LD	A,02H
	DEFB	0EDH,004H		; LD BC_B,A (=02h)
	LD	A,005H
	LD	(BC),A			; 02:0000h = 05h (BANK byte)

	; ---- 診断マーカー10: 02:0000hへの(BC)書込み直後。----
	LD	A,0DH
	CALL	MARK

	DEFB	0EDH,090H		; SET_M0 (安全な状態へ戻す)

	; ---- 診断マーカー11: SET_M0直後。----
	LD	A,0EH
	CALL	MARK

	LD	HL,0FFFEH
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A (=01h)
	DEFB	0EDH,035H		; LD24 MSP,HL  (MSP24 = 01:FFFEh、PUSH24を経由せず直接設定)

	; ---- 診断マーカー12: LD24 MSP,HL(ED 35、MSP24直接設定)直後。
	; 11は表示され12が表示されない場合、PUSH24を経由しないMSP24直接
	; 設定(ED 35)自体に、PUSH24経由の設定とは異なる何らかの問題が
	; あることになる。12まで表示されれば、残る疑いは直後のPOP24命令
	; 自体(マーカー6との間)に絞られる。----
	LD	A,0FH
	CALL	MARK

	LD	HL,0000H
	XOR	A
	DEFB	0EDH,024H		; LD HL_B,A (clobber)
	DEFB	0EDH,0E1H		; POP24 HL  ** テスト対象(PUSH24非経由、単体POP24のbank境界またぎ) **

	; ---- 診断マーカー6: 単体POP24(Test8)実行直後。----
	LD	A,06H
	CALL	MARK

	; ---- 【一時切り分け】マーカー6以降をさらに細分化する。各命令の
	; 直後に異なる背景色でCALL MARKし、具体的にどの命令でフリーズして
	; いるかを1命令単位で特定する。原因箇所の特定後はこれらの追加
	; マーカー(6a/6b/6c)を削除してよい。----
	LD	(T7_HL_LO),HL
	; ---- 診断マーカー6a: 通常のLD (mem),HL(標準Z80命令、拡張無し)
	; 完了直後。これが表示されない場合、POP24直後の最初の通常メモリ
	; 書込み命令自体でフリーズしていることになる。----
	LD	A,0AH
	CALL	MARK

	DEFB	0EDH,02CH		; LD A,HL_B
	; ---- 診断マーカー6b: ED 2C(LD A,HL_B、拡張命令だがメモリ非経由の
	; 内部レジスタ読出しのみ)完了直後。6aは表示され6bが表示されない
	; 場合、このED 2C命令自体(メモリバスを伴わないはずの内部読出し)
	; でフリーズしていることになる。ED 2Cの結果(A=バンク値)は後で
	; T7_HL_BANKへ格納する必要があるため、PUSH AFで退避してから
	; マーカー用の値をAへロードする(MARK自体もAF退避/復帰するが、
	; マーカー値をAへロードする本処理側でも退避しないとED 2Cの結果を
	; 破壊してしまうため)。----
	PUSH	AF
	LD	A,0BH
	CALL	MARK
	POP	AF

	LD	(T7_HL_BANK),A
	; ---- 診断マーカー6c: 通常のLD (mem),A(標準Z80命令)完了直後、
	; CHECK24_IX呼出し(BDOS経由の文字列表示を含む)の直前。6bは表示
	; され6cが表示されない場合、この通常メモリ書込み命令でフリーズ
	; していることになる。6cまで表示されればCHECK24_IX呼出し(BDOS)
	; 側でフリーズしていることになる。----
	LD	A,0CH
	CALL	MARK

	LD	HL,99AAH
	LD	B,05H
	LD	DE,MSG_T8
	LD	IX,T7_HL_LO
	CALL	CHECK24_IX

	DEFB	0EDH,036H		; LD HL,MSP  (=LD24 HL,MSP)
	LD	(T7_MSP_LO),HL
	DEFB	0EDH,02CH		; LD A,HL_B
	LD	(T7_MSP_BANK),A

	LD	HL,0001H
	LD	B,02H
	LD	DE,MSG_T8_MSP
	LD	IX,T7_MSP_LO
	CALL	CHECK24_IX

	; ---- Test7/Test8完了。退避しておいた元のVDP R#7(背景色)へ復元する。----
	LD	A,(T7_ORIG_R7)
	CALL	MARK

	; MSP24を他のテストと同じ初期値(01:E000h)へ戻しておく
	; (プログラム終了前の安全な状態に合わせるため)。
	LD	HL,0E000H
	LD	A,01H
	DEFB	0EDH,024H		; LD HL_B,A
	DEFB	0EDH,035H		; LD24 MSP,HL

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
; MARK : 診断用の画面色マーカー。Aの値をそのままVDP R#7(背景色)へ直接OUTする
;   (P1314Testで使用した方式と同じ)。Test7のbank境界またぎフリーズが
;   具体的にどの命令の実行中に発生しているかを切り分けるために、Test7の
;   各ステップの直後に異なる値でCALLする。BDOSのメッセージ表示より確実に
;   即座に画面へ反映されるため、万一この後でCPU/メモリバスが完全にハング
;   しても、最後に表示されていた色から「どこまで実行が進んでいたか」を
;   目視で特定できる。
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
MSG_T7:		DEFB	"Test7 PUSH24/POP24 HL across a bank boundary$"
MSG_T7_PEEK:	DEFB	"Test7 PUSH24 wrote the correct bytes to memory$"
MSG_T7_MSP:	DEFB	"Test7 MSP24 restored across the same boundary$"
MSG_T8:		DEFB	"Test8 POP24-only (no PUSH24) across a bank boundary$"
MSG_T8_MSP:	DEFB	"Test8 MSP24 restored across the same boundary$"

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

T7_HL_LO:	DEFS	2
T7_HL_BANK:	DEFS	1
T7_PEEK_LO:	DEFS	1		; PUSH24直後に(BC)で直接読んだLOW byte
T7_PEEK_HI:	DEFS	1		; PUSH24直後に(BC)で直接読んだHIGH byte
T7_PEEK_BANK:	DEFS	1		; PUSH24直後に(BC)で直接読んだBANK byte
T7_MSP_LO:	DEFS	2
T7_MSP_BANK:	DEFS	1
T7_ORIG_R7:	DEFS	1		; Test7診断マーカー用、元のVDP R#7退避先

PASS_COUNT:	DEFB	0
FAIL_COUNT:	DEFB	0
