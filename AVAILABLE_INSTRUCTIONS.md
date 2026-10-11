# 使用可能な命令一覧

この一覧は、MSX T80 24bit 拡張仕様書に基づく、現在の構成で使用可能または想定される 24bit 拡張命令のまとめです。

> 参考: [README.md](README.md) からリンクされています。
> 本一覧は [MSX_T80_24bit化_CPU仕様書_V8](doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md) と
> [MSX_T80_24bit化_命令一覧_V7](doc/jpn/MSX_T80_24bit化_命令一覧_V7_2026-10-05.csv)（いずれもopcode確定・TBDなし）を正としています。旧V5仕様に基づく暫定opcodeの記載は廃止しました。
> 実装状態は、以下の基準で整理しています。
> - 実装済み: 現在のプロジェクト内（[t80.vhd](fpga/G80A/t80.vhd)）で対応が確認できている命令
> - 未実装: V8/V7で確定しているが、現時点で未対応の命令

---

## 1. モード制御

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 90` | `SET_M0` | 完全 Z80 互換モードへ移行 | 実装済み（HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成と連動。PC/SPアドレス生成はM0では元々plain 16bitのまま） |
| `ED 91` | `SET_M1` | データアクセス拡張モードへ移行 | 実装済み（HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成と連動。PC/SPアドレス生成はM1では元々plain 16bitのまま、CPU仕様書V8どおり） |
| `ED 92` | `SET_M2` | 24bit ネイティブ動作モードへ移行 | 実装済み（Phase10。HL/BC/DE/(IX+d)/(IY+d)の24bitデータアドレス生成に加え、PC24命令フェッチとMSP24アクティブスタックポインタとも連動。M0/M1→M2遷移時は`PC_B`(`bank_pc_r`)を00hへリセットし、M2→M2（再実行）では保持。詳細は下記「8. M2基本動作」参照） |
| `ED 93` | `JP.M0 addr16` | M0へモード遷移ジャンプ | 未実装 |
| `ED 94` | `JP.M1 addr16` | M1へモード遷移ジャンプ | 未実装 |
| `ED 95` | `JP.M2 addr24` | M2へモード遷移ジャンプ | 未実装 |
| `ED 96` | `CALL.M0 addr16` | M0へモード遷移コール | 未実装 |
| `ED 97` | `CALL.M1 addr16` | M1へモード遷移コール | 未実装 |
| `ED 98` | `CALL.M2 addr24` | M2へモード遷移コール | 未実装 |
| `ED 99` | `RET.M` | モード遷移フレームからの復帰 | 未実装 |

---

## 2. バンクレジスタ

既存16bitレジスタに付随する単純な8bit bankバイト。全モードで直接LD可能（F不変）。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 04` | `LD BC_B, A` | BC バンクレジスタへ書き込み | 実装済み |
| `ED 0C` | `LD A, BC_B` | BC バンクレジスタ読み出し | 実装済み |
| `ED 14` | `LD DE_B, A` | DE バンクレジスタへ書き込み | 実装済み |
| `ED 1C` | `LD A, DE_B` | DE バンクレジスタ読み出し | 実装済み |
| `ED 24` | `LD HL_B, A` | HL バンクレジスタへ書き込み | 実装済み |
| `ED 2C` | `LD A, HL_B` | HL バンクレジスタ読み出し | 実装済み |
| `ED 05` | `LD IX_B, A` | IX バンクレジスタへ書き込み | 実装済み |
| `ED 0D` | `LD A, IX_B` | IX バンクレジスタ読み出し | 実装済み |
| `ED 15` | `LD IY_B, A` | IY バンクレジスタへ書き込み | 実装済み |
| `ED 1D` | `LD A, IY_B` | IY バンクレジスタ読み出し | 実装済み |
| `ED 3A` | `LD RST_B, A` | RST.L用バンクレジスタへ書き込み | 実装済み |
| `ED 3E` | `LD A, RST_B` | RST.L用バンクレジスタ読み出し | 実装済み |

> `MSP24`/`IVR24`/`NVR24`は単純な8bit bankレジスタではなく、最初からフル24bitレジスタとして定義されており、上記のような単独`_B`直接LD命令は存在しません（下記「3. 24bit転送」「4. 割込ベクタ」参照）。`PC_B`も直接LDする命令は無く、`SET_M2`/`CALL.M2`等のモード遷移命令が自動的に設定します。

---

## 3. 24bit転送（HL24 hub / MSP）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 06` | `LD24 HL, BC` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 0E` | `LD24 BC, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 16` | `LD24 HL, DE` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 1E` | `LD24 DE, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `DD ED 26` | `LD24 HL, IX` | full 24bit、F不変 | 未実装（DD/ED二重プレフィクスの命令デコード拡張が必要、次増分予定） |
| `DD ED 2E` | `LD24 IX, HL` | full 24bit、F不変 | 未実装（同上） |
| `FD ED 26` | `LD24 HL, IY` | full 24bit、F不変 | 未実装（同上） |
| `FD ED 2E` | `LD24 IY, HL` | full 24bit、F不変 | 未実装（同上） |
| `ED 34 bl bh bn` | `LD24 MSP, imm24` | F不変 | 未実装（3byte即値フェッチのMCycleシーケンス拡張が必要、次増分予定） |
| `ED 35` | `LD24 MSP, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 36` | `LD24 HL, MSP` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |

> Phase7（[MSX_T80_24bit化_実装手順_V2](doc/jpn/MSX_T80_24bit化_実装手順_V2_2026-10-05.md)セクション9）のうち、上記テーブルで「実装済み」の6命令（HL24⇔BC24/DE24、HL24⇔MSP24）は、単一ED prefixで完結するレジスタ間24bitコピー命令として実装済みです。[t80.vhd](fpga/G80A/t80.vhd)内の既存のパイプライン化されたレジスタアドレス生成機構（`RegAddrA_r`/`RegAddrB_r`）への条件追加のみで実装しており、t80_mcode.vhdやレジスタファイルの共有多分岐ロジックへの変更は一切ありません。GHDLテストベンチ（[tb_phase7_ld24.vhd](fpga/G80A/test/tb_phase7_ld24.vhd)）で、宛先の24bit値・ソース不変・F不変を検証済みです。
> IX/IY hub転送（DD/FD ED26/2E）と即値ロード（ED34/9A/9D）は、二重プレフィクスのデコードや複数byteオペランドフェッチのための追加のMCycleシーケンス機構が必要なため、本増分では未実装のまま次の増分へ持ち越しています。

---

## 4. 割込ベクタ（IVR24 / NVR24）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 9A bl bh bn` | `LD24 IVR, imm24` | F不変 | 未実装（3byte即値フェッチのMCycleシーケンス拡張が必要、次増分予定） |
| `ED 9B` | `LD24 IVR, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 9C` | `LD24 HL, IVR` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 9D bl bh bn` | `LD24 NVR, imm24` | F不変 | 未実装（同上） |
| `ED 9E` | `LD24 NVR, HL` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |
| `ED 9F` | `LD24 HL, NVR` | full 24bit、source/F不変 | 実装済み（GHDL検証済み、実機未検証） |

> `IVR`/`NVR`の16bit低位ワードは、Phase7実装に伴い新規追加した[t80.vhd](fpga/G80A/t80.vhd)内部レジスタです（バンクバイト`bank_int_r`/`bank_nvr_r`自体はPhase1から存在）。Reset値は[MSX_T80_24bit化_CPU仕様書_V8](doc/jpn/MSX_T80_24bit化_CPU仕様書_V8_2026-10-05.md)セクション2の規定どおり`000000h`です。あわせて、従来実装で`MSP`の低位16bitが（Z80標準SPレジスタの慣習を引き継いで）`FFFFh`にリセットされていた不整合を、同セクションの規定（`MSP24=000000h`）に合わせて`0000h`へ修正しました。

---

## 5. 24bit ALU

専用24bit ALUを使用。DD/FDプレフィクスでHL targetをIX/IYへ置換。SUB24は設けずC=0のSBC24を使う。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 23` | `INC24 HL` | 24bitで+1 | 実装済み（GHDL検証済み、実機未検証。HL targetのみ。DD/FD IX/IY targetは未実装） |
| `ED 2B` | `DEC24 HL` | 24bitで-1 | 実装済み（同上） |
| `ED 09` / `19` / `29` / `39` | `ADD24 HL, BC/DE/HL/SP` | 24bit加算 | 実装済み（同上。SP operandはMSP24） |
| `ED 07` / `17` / `27` / `37` | `ADC24 HL, BC/DE/HL/SP` | 24bit桁上げ加算 | 実装済み（同上） |
| `ED 0F` / `1F` / `2F` / `3F` | `SBC24 HL, BC/DE/HL/SP` | 24bit桁借り減算 | 実装済み（同上） |
| `ED 3D` | `CP24 HL, DE` | 24bit比較（writebackなし） | 実装済み（同上） |

- 実装は[t80.vhd](fpga/G80A/t80.vhd)内の専用の組合せ論理プロセスと、[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Alu24_AddSub`関数（t80_alu.vhdの既存8bit ALUとは完全に独立）で構成されており、Phase7と同様にT80コア共通部分（`t80_mcode.vhd`やレジスタファイルのメインデコード経路）には一切手を加えていません。
- フラグ: `S`=bit23、`Z`=24bit zero、`H`は変更なし（保持）、`P/V`=24bit符号付きオーバーフロー、`N`=加算系命令で0・減算系命令で1、`C`=24bit carry/borrow。未定義のX/Y（bit3/5）フラグも同様にこの命令群では変更されません（CPU仕様書V8はこれらを規定していないため、保持する設計としています）。
- `CP24`は書き込みを行わず、フラグのみを更新します（HL24は変更されません）。
- DD/FDプレフィクスによるIX/IYターゲットの置換は未実装です（Phase7のLD24 HL,IX/IYと同様、二重プレフィクスのデコード拡張が必要なため次フェーズに繰り越し）。DD/FD付きでこれらのopcodeを実行した場合は未定義命令としてNOP扱いになります。
- GHDLテストベンチ: [tb_phase8_alu24.vhd](fpga/G80A/test/tb_phase8_alu24.vhd)（全9ケース、符号付きオーバーフロー・24bit carry/borrow・H保持・MSP24オペランド・CP24の非書き込みを含めて検証済み）。

---

## 6. Indexed転送

DD/FD ED80〜8B。80〜82=LD16 load、83〜85=LD16 store、86〜88=LD24 load、89〜8B=LD24 store。M0=16bit EA、M1/M2=24bit EA。LD16はbank byte不変。

| オペコード | 命令 | 状態 |
|---|---|---|
| `DD/FD ED 80` | `LD16 BC, (IX/IY+d)` | 未実装 |
| `DD/FD ED 81` | `LD16 DE, (IX/IY+d)` | 未実装 |
| `DD/FD ED 82` | `LD16 HL, (IX/IY+d)` | 未実装 |
| `DD/FD ED 83` | `LD16 (IX/IY+d), BC` | 未実装 |
| `DD/FD ED 84` | `LD16 (IX/IY+d), DE` | 未実装 |
| `DD/FD ED 85` | `LD16 (IX/IY+d), HL` | 未実装 |
| `DD/FD ED 86` | `LD24 BC, (IX/IY+d)` | 未実装 |
| `DD/FD ED 87` | `LD24 DE, (IX/IY+d)` | 未実装 |
| `DD/FD ED 88` | `LD24 HL, (IX/IY+d)` | 未実装 |
| `DD/FD ED 89` | `LD24 (IX/IY+d), BC` | 未実装 |
| `DD/FD ED 8A` | `LD24 (IX/IY+d), DE` | 未実装 |
| `DD/FD ED 8B` | `LD24 (IX/IY+d), HL` | 未実装 |

---

## 7. 24bit Stack（PUSH24 / POP24）

対象はBC24/DE24/HL24/IX24/IY24のみ（AFは対象外）。MSPを使用し3byte転送。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED C5` / `C1` | `PUSH24` / `POP24 BC` | 実装済み（GHDL検証済み、実機確認済み。ただし単一物理bank内でのみ。下記「既知の問題」参照） |
| `ED D5` / `D1` | `PUSH24` / `POP24 DE` | 実装済み（同上） |
| `ED E5` / `E1` | `PUSH24` / `POP24 HL` | 実装済み（同上） |
| `DD ED E5` / `E1` | `PUSH24` / `POP24 IX` | 未実装（DD/ED二重プレフィクスの命令デコード拡張が必要、Phase7のLD24 HL,IX/IYと同様の理由で次フェーズに繰り越し） |
| `FD ED E5` / `E1` | `PUSH24` / `POP24 IY` | 未実装（同上） |

- PUSH24はMSP24（`bank_msp_r`+`MSP`、Phase7で新設）を1ずつ3回デクリメントしながらBANK→HIGH→LOWの順でメモリへ書き込み、POP24は逆にLOW→HIGH→BANKの順で読み出しながら1ずつ3回インクリメントします。最終的なMSP24はPUSH24で-3、POP24で+3となり、互いに逆操作として往復が可能です。
- バンクバイトとの繰り上がり/繰り下がりは[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Dec`/`Addr24_Inc`（Phase2で追加、Phase9向けに既に用意されていたもの）を使って計算されるため、16bitワードの境界（0000h⇔FFFFh）をまたぐ際にバンクバイトも正しく繰り上がり/繰り下がりします。
- LOW/HIGH byteの読み書きは、既存のBC/DE/HLレジスタファイル書き込み機構（`Read_To_Reg`/`Set_BusA_To`、`Set_BusB_To`経由のBusB staging）をそのまま再利用しており、通常のPUSH qq/POP qqと全く同じ仕組みです。BANK byteのみ、レジスタファイル外の`bank_bc_r`/`bank_de_r`/`bank_hl_r`信号を対象とするため、[t80.vhd](fpga/G80A/t80.vhd)内で直接の書き込み（PUSH側はDOへの直接上書き、POP側は`DI_Reg`からの直接キャプチャ）として実装されています。アドレス生成には新規の`Set_Addr_To`値`aMSP`（従来未使用だった`"011"`を割り当て）を追加しましたが、既存の`aSP`/`aBC`/`aDE`等の経路には一切手を加えていません。
- フラグ（F）は変更されません（Z80標準のPUSH/POPと同様）。
- GHDLテストベンチ: [tb_phase9_push24_pop24.vhd](fpga/G80A/test/tb_phase9_push24_pop24.vhd)（PUSH24→POP24の往復、バンク境界またぎ時の繰り下がり、F不変を含めて検証済み）。

### 既知の問題: bank境界をまたぐPUSH24/POP24で実機フリーズを確認（未解決）

1回のPUSH24/POP24呼出しの中で物理bankが変化するシナリオ（例:
MSP24=02:0001hからPUSH24を実行し、3回のデクリメントで
02:0001→02:0000→01:FFFF（bank繰り下がり）→01:FFFEとbankをまたぐ）を
[Project/Push24Test](../Project/Push24Test)で実機検証したところ、
**先行するTest5完了直後にシステムがフリーズする現象を確認しました**
（画面にプログラム起動時のバナーが再表示された後、応答不能に。PCが暴走し
プログラム先頭付近へ飛んだ可能性が高い）。GHDLシミュレーション
（`tb_phase9_push24_pop24.vhd`）では同じシナリオが問題なくPASSしているため、
実機固有の問題と判断されます。

原因として、1命令内で連続する3回のメモリアクセス（BANK/HIGH/LOW
byte）がそれぞれ異なる物理bankへルーティングされる経路が、Phase3/5で
検証済みの既存拡張メモリアクセス（`(HL)`/`(BC)`/`(DE)`/`(IX+d)`。いずれも
1命令につき拡張アクセスは1回のみ）では一度も検証されていなかったこと、
および本プロジェクトのSD-RAMコントローラ（[memory.v](fpga/src/memory.v)・
sdram.v）にはCPU側へのWAIT状態生成機構が存在しない（[top.v](fpga/top.v)の
`ex_bus_wait_n`は常時`1'b1`固定）ため、bank切替にコントローラ側の処理が
間に合わずアドレス生成が一時的に乱れ、意図しない領域（bank00h＝実行中
プログラム自身の空間や、BIOS/割込みベクタ等）を破壊した可能性が疑われます。

根本原因の特定には[memory.v](fpga/src/memory.v)・sdram.vのSD-RAMタイミング
のより詳細な調査が必要で、**現時点では未解決**です。[Project/Push24Test](../Project/Push24Test)
の実機テストプログラムは、この問題が判明した時点でbank境界をまたぐ
シナリオを削除し、常に単一物理bank内で完結するテストのみに修正済みです。
PUSH24/POP24を単一物理bank内で使う限りは実機で正常動作を確認済みですが、
bank境界をまたぐ使用は本問題が解決されるまで避けてください。

---

## 8. M2基本動作（PC24フェッチ / MSPアクティブスタック）

CPU仕様書V8セクション2「MODE」が定義するM2モード（`PC: 24bit`、`Active stack: MSP24`）の基本動作。新規opcodeの追加ではなく、既存のT80共有機構（PC自動インクリメント、`aSP`アドレス生成、SP用`IncDec_16`機構）がM2実行時にのみ条件分岐で経路を切り替える形で実装されています。

| 項目 | 内容 | 状態 |
|---|---|---|
| PC24命令フェッチ | M2では`PC24={bank_pc_r,PC}`として、通常の命令フェッチ（オペコードbyte・オペランドbyteの自動インクリメント）が[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Inc`経由で24bit演算になり、PCが0xFFFF→0x0000をまたぐ際に`bank_pc_r`が正しく繰り上がる | 実装済み（GHDL検証済み、実機未検証） |
| `SET_M2`のPC_B挙動 | M0/M1→M2遷移時は`bank_pc_r`を00hへリセットし、M2→M2（既にM2の状態での再実行）では`bank_pc_r`を保持（CPU仕様書V8「SET_M2はM0/M1→M2でPC_B<-00h、M2→M2ではPC_B保持」） | 実装済み（GHDL検証済み、実機未検証） |
| MSP24アクティブスタック | M2では、既存のZ80標準`PUSH qq`/`POP qq`/`EX (SP),HL/IX/IY`/`CALL`/`CALL cc`/`RET`/`RET cc`/`RST p`が、通常のSPではなくMSP24（`bank_msp_r`+`MSP`）を使うようになる。転送byte数は2byteのまま（bank byte自体はPUSH24/POP24と異なりdataとして転送されない）で、MSP24自体は[t80_pack.vhd](fpga/G80A/t80_pack.vhd)の`Addr24_Dec`/`Addr24_Inc`で64KB境界をまたいで正しく繰り上がり/繰り下がりする | 実装済み（GHDL検証済み、実機未検証） |

- 実装は、既存の`aSP`（Set_Addr_To）ケースと、SP用`IncDec_16(2 downto 0)="111"`インクリメント/デクリメント機構の両方に`if mode24_r = "10" then ... (MSP24側) ... else ... (従来のSP) ... end if;`を追加しただけで、[t80_mcode.vhd](fpga/G80A/t80_mcode.vhd)には一切手を加えていません。これにより、`aSP`を使う既存命令（PUSH/POP qq、EX (SP),HL/IX/IY、CALL/CALL cc/RET/RET cc/RST p、および未実装のPhase13 M2割込みが実装されるまで暫定的にこの2byte機構へフォールスルーするNMI/INT(IM2)/RETI/RETN）が自動的にMSP24対応になります。
- 既存のZ80標準`SP`レジスタ自体はM2実行中も一切変更されません（GHDLテストベンチで`ADD HL,SP`トリックを使い、M2でのPUSH/POP前後でSPが完全に不変であることを確認済み）。
- PC24のバンクbyteが影響するのは「通常の順次フェッチ」のみです。`JP`/`JR`/`CALL`/`RST`等の分岐・ジャンプ命令は、CPU仕様書V8の「既存Z80命令が16bit即値アドレスを生成する場合はbank00と解釈する」規定に従い、ジャンプ/コール先は引き続きbank00hへ固定されます（`bank_pc_r`もこれらの命令の直後に00hへリセットされ、次の命令フェッチが正しいバンクを使えるようにしています）。ただし、これらの命令自身のPCアドレス計算（JR/DJNZの相対変位、ブロック転送命令の繰り返し用アドレス補正等）自体を24bit対応にする作業はPhase11「M2制御フロー」の範囲として未着手です。M2でJR/DJNZ等が64KB境界をまたぐケースでは`bank_pc_r`が正しく追従しない既知の制限があります。
- 新規追加した割込み関連opcode(`DD/FD ED26/2E`相当の二重プレフィクス、JP.L/CALL.L/RET.L等)は本フェーズの対象外です。M2割込み（IRQ→IVR24、NMI→NVR24、4byte MSP frame）はPhase13の範囲で、現状のNMI/INT(IM2)/RETI/RETNは上記の2byte MSP機構へ暫定的にフォールスルーするのみで、Phase13仕様の4byte frameとは一致しません。
- GHDLテストベンチ: [tb_phase10_m2_basic.vhd](fpga/G80A/test/tb_phase10_m2_basic.vhd)（SET_M2のPC_Bリセット/保持、PC24の64KB境界またぎ時の繰り上がり、MSP24を使った通常PUSH/POPの2byte転送とSP不変を検証済み）。

---

## 9. 24bit制御（JR.L / JP.L / CALL.L / RET.L）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 18` | `JR.L e16` | M2=PC24相対、M0/M1=PC16相対 | 実装済み（GHDL検証済み。詳細は下記「9.3 JR.L」参照） |
| `ED 20` / `28` | `JR.L NZ/Z, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED 30` / `38` | `JR.L NC/C, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED A7` / `AF` | `JR.L PO/PE, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED B7` / `BF` | `JR.L P/M, e16` | 条件付き | 実装済み（GHDL検証済み） |
| `ED C3` | `JP.L addr24` | 24bit無条件ジャンプ | 実装済み（GHDL検証済み。M2ではbank_pcへ即値のbankバイトを反映、M0/M1では3byte目は読み捨てbank00h扱い。詳細は下記「9.1 JP.L」参照） |
| `ED C2/CA/D2/DA/E2/EA/F2/FA` | `JP.L cc, addr24` | 条件付き24bitジャンプ | 実装済み（GHDL検証済み。条件不成立時も3byteのアドレスは読み飛ばし、bank_pcは変化しない） |
| `ED CD` | `CALL.L addr24` | MSPへPC24を3byte保存（M2専用） | 実装済み（GHDL検証済み。詳細は下記「9.2 CALL.L/RET.L」参照） |
| `ED C4/CC/D4/DC/E4/EC/F4/FC` | `CALL.L cc, addr24` | 条件付きfar call（M2専用） | 実装済み（GHDL検証済み） |
| `ED C9` | `RET.L` | MSPからPC24復元（M2専用） | 実装済み（GHDL検証済み） |
| `ED C0/C8/D0/D8/E0/E8/F0/F8` | `RET.L cc` | 条件付きfar return（M2専用） | 実装済み（GHDL検証済み） |

### 9.1 JP.L / JP.L cc 実装メモ（Phase11着手）

`JP.L`/`JP.L cc`は、Phase11「M2制御フロー」のうちスタック(MSP)を使わない
最もシンプルな部分として先行実装した。

- 命令長はED prefix込みで5byte固定（`ED xx + lo + hi + bank`）。条件が
  不成立の場合も、実機Z80の`JP cc,nn`と同様に3byteのアドレスは最後まで
  読み進める（ジャンプしないだけで命令長は変わらない）。
- `ED C3`は、このプロジェクトでは常にMode=0（Z80相当）固定でビルドして
  おりR800拡張（MULUW/MULUB）には到達しないため、元々未使用だった
  R800 MULUWのopcodeスロットを転用した（`ED F3`はMULUWプレースホルダの
  ままで変更していない）。
- **M2でのみ本来の24bitジャンプとして機能する**: `mode24=M2`のとき、
  読み込んだ3byte目（bankバイト）がそのまま`bank_pc`（PC24の物理バンク
  レジスタ）に反映され、真の24bit far jumpとして動作する。
- **M0/M1では3byte目は読み捨てられ、常にbank00h扱いになる**（CALL.L/
  RET.LのM2専用制限と同じ考え方）。これは意図的な設計判断であり、
  Phase10で`bank_pc`はM2のときしか命令フェッチに参照されないため、
  M0/M1でbank_pcへ非ゼロ値を書き込んでも「ジャンプ直後の1回だけ正しい
  バンクが見えて、以降のフェッチでは静かにbank00hへ戻ってしまう」
  という不整合（"zombie bank_pc"）を避けるため。
- GHDLテストベンチ: [tb_phase11_jpl.vhd](fpga/G80A/test/tb_phase11_jpl.vhd)
  （M2での無条件/条件付き（成立・不成立）ジャンプ、M0でのbankバイト
  読み捨てを検証済み）。
- 未実装: `JR.L`（相対ジャンプ、PC24全体にsigned変位を加算）は、本
  セクション表のとおり引き続きPhase11のTODOとして残っている。

### 9.2 CALL.L / RET.L 実装メモ（Phase11）

`CALL.L addr24`/`CALL.L cc,addr24`/`RET.L`/`RET.L cc`は、Phase9の
PUSH24/POP24と同じ「MSP24へ3byte転送」の仕組みを流用し、PC24の
far call/returnとして実装した。

- **フレーム構成**: `CALL.L`はMSP24へ`bank_pc_r`(戻り先bank)→`PC_H`→
  `PC_L`の順に3byte push（decrementしながら書き込み、最終的にMSP24は
  LOWバイトを指す）。`RET.L`はLOW→HIGH→BANKの順に3byte pop（incrementし
  ながら読み込み）し、`PC24={BANK,HIGH,LOW}`へジャンプする。書き込み/
  読み込み順序・MSP24の増減タイミングはPhase9のPUSH24/POP24と完全に
  同じパターン（decrement-before-write / increment-after-read）。
- **条件付き版の中断動作**: `CALL.L cc`は条件不成立時、実機Z80の
  `CALL cc,nn`と同様に3byteのアドレスは最後まで読み進めるが、MSP24へは
  一切触れない（push phaseへ進まない）。`RET.L cc`は条件不成立時、
  即座に中断し（opcodeフェッチのみ）、MSP24は一切変化しない。
- **既存のED CD/C9 opcodeスロットについて**: `ED CD`は元々未使用
  （NOP扱い）だったスロットを使用。`ED C9`は、JP.Lと同様にこのプロジェ
  クトでは到達しないR800 MULUBのopcodeスロット（`ED D9`とペア）を
  転用し、`ED D9`はMULUBプレースホルダのまま変更していない。
- **通常CALL/RETのbank_pc挙動もPhase11で修正**: ロードマップPhase11の
  「通常CALL/RETは同一64KB segment内用、PC_B=不変」との規定に合わせ、
  既存の（ED prefixを使わない）プレーンな`CALL`/`CALL cc`/`RET`/
  `RET cc`命令についても、M2実行時に`bank_pc`をbank00hへリセットして
  いた旧Phase10の挙動を「`bank_pc`を変更せず保持する」よう修正した
  （RET側は新設の`JumpR`信号で`Jump`と区別し、CALL側は既存の`Call`
  信号のbank_pc_rリセットを単純に削除）。JP/JR/RST等、16bit即値ターゲ
  ットを生成する他の命令は引き続きbank00hへリセットする（CPU仕様書V8
  section 5のルールのまま）。

#### T80コア側で発見・修正した前提条件（既存バグ、Phase11で表面化）

CALL.L/RET.Lの実装過程で、T80コア本体（`fpga/G80A/t80.vhd`・
`fpga/G80A/t80_mcode.vhd`）に存在していた、**DD/FD+CBの二重prefix
継続処理専用のはずのロジックが、`MCycle`の値（110/111=6/7）だけで無条件
に発火してしまう**という前提条件がいくつか見つかった。これらは今まで
「どの命令のMCyclesも6/7に到達しない」という暗黙の前提の上でのみ安全
だった潜在バグで、CALL.L（7 MCycles必要）の追加で初めて表面化した。
すべて`XY_State /= "00"`（DD/FD prefix実行中かどうか）によるガード条件
追加で最小限に修正した（DD/FD+CB自体の動作は変更なし、GHDL回帰
Phase2〜11で確認済み）。

- `t80.vhd`のメイン状態機械: `MCycle="111"`に達すると常に
  `Pre_XY_F_M`から復元する処理が無条件発火 → 新規1bitフラグ
  `XYF_Pending`を追加し、`NextIs_XY_Fetch`経由で来た場合のみ有効化。
- `t80_mcode.vhd`末尾の共通ブロック: `MCycle="110"/"111"`で
  `Inc_PC`/`Set_Addr_To`/`TStates`等を無条件に上書き。
- `t80.vhd`の(IX/IY+d)実効アドレス計算: `TState=3 and MCycle="110"`で
  `TmpAddr`/`TmpBank`を無条件に上書き。
- `t80.vhd`の`XY_Ind`セット、`RegAddrC`選択: いずれも`MCycle="110"`の
  単独条件で無条件発火。
- さらに、CALL.L cc自身の実装バグとして、条件不成立時にも「push phase
  手前の最初のMSP24デクリメント」だけは発火してしまう問題を発見・
  修正（`Set_Addr_To=aMSP`であることを追加の条件としてガード）。

GHDLテストベンチ:
[tb_phase11_call_ret_l.vhd](fpga/G80A/test/tb_phase11_call_ret_l.vhd)
（無条件/条件成立/条件不成立のCALL.L・RET.L双方、複数回の呼び出し
ネストを経てもMSP24が正しく復元されることを検証済み）。

### 9.3 JR.L / JR.L cc 実装メモ（Phase11完了）

`JR.L`/`JR.L cc`は、Phase11「M2制御フロー」の最後のピースとして実装し、
これでPhase11は完了した。

- **16bit符号付き変位**: 実機Z80の`JR e`/`JR cc,e`は8bit符号付き変位
  だが、`JR.L`はED prefix込みで4byte固定（`ED xx + lo + hi`）、16bit
  符号付き変位を使う。M2ではPC24全体（`bank_pc`+PC）に対して
  `Addr24_AddDisp16`（t80_pack.vhd、Phase2から用意されていた関数）で
  24bit演算し、bank境界を正しく跨ぐ（繰り上がり・繰り下がり両方、
  8bitのbankバイト自体の折り返しも含めて検証済み）。
- **M0/M1では従来どおりの16bit wrap**（JP.L同様、bank_pcはM0/M1の
  フェッチで参照されないため、ここでは一切変更しない）。
- **2種類のopcode/条件エンコーディングが混在**: `ED 18/20/28/30/38`は
  実機Z80の`JR e`/`JR NZ,Z,NC,C,e`と全く同じopcodeバイトをそのまま
  ED prefix付きで再利用（条件は実機JRと同じ2bitエンコーディング）。
  `ED A7/AF/B7/BF`は実機JRには存在しないPO/PE/P/M条件用で、偶然にも
  JP.L/CALL.L等と同じ3bit cc（`IR(5:3)`）エンコーディングに一致する
  オペコードバイトが空いていたため採用した。
- **条件不成立時**: 実機Z80の`JR cc,e`と同様、2byteの変位は最後まで
  読み進めるが、ジャンプはしない（タイミングも可変長）。
- GHDLテストベンチ: [tb_phase11_jrl.vhd](fpga/G80A/test/tb_phase11_jrl.vhd)
  （M2での無条件/条件成立/条件不成立、前方/後方双方のbank境界またぎ
  （bankバイト自体の折り返しを含む）、M0での16bit wrap退化を検証済み）。

**Phase11はこれで完了**（JR.L / JP.L / CALL.L / RET.L すべて実装済み）。

---

## 10. モード間制御（JP.Mx / CALL.Mx / RET.M）

Phase12「モード間制御」。`JP.Mx`/`CALL.Mx`は、通常のJP/CALLとは異なり
ジャンプ/コールと同時にモード（M0/M1/M2）自体を切り替える専用命令。
`RET.M`はその対になる復帰命令で、戻り先のモードもフレームから復元する。

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 93` | `JP.M0 addr16` | M0へ切替えて16bit addrへジャンプ | 実装済み（GHDL検証済み） |
| `ED 94` | `JP.M1 addr16` | M1へ切替えて16bit addrへジャンプ | 実装済み（GHDL検証済み） |
| `ED 95` | `JP.M2 addr24` | M2へ切替えて24bit addrへジャンプ | 実装済み（GHDL検証済み） |
| `ED 96` | `CALL.M0 addr16` | M0へ切替えてcall（MSPへ4byte frame保存） | 実装済み（GHDL検証済み） |
| `ED 97` | `CALL.M1 addr16` | M1へ切替えてcall（MSPへ4byte frame保存） | 実装済み（GHDL検証済み） |
| `ED 98` | `CALL.M2 addr24` | M2へ切替えてcall（MSPへ4byte frame保存） | **未実装（保留、下記参照）** |
| `ED 99` | `RET.M` | MSPから4byte frameを復元しPC24・モード両方を復帰 | 実装済み（GHDL検証済み） |

### 10.1 実装メモ

- **JP.Mx**: `JP.M0`/`JP.M1`はaddr16（2byte）、`JP.M2`はaddr24（3byte、
  bankバイト込み）をジャンプ先として読み込み、同時に`mode24`
  （モードレジスタ）を強制的に切り替える。`JP.L`と異なり、現在の
  モードに関わらず常にモード切替え・bankバイト適用を行う（`JP.L`は
  既にM2のときだけbankバイトを反映し、モード自体は変更しない）。
  addr16ターゲット（JP.M0/M1）は常にbank00h扱い。
- **CALL.Mx**: ジャンプ先読み込みは`JP.Mx`と同じだが、戻り先として
  MSPへ4byte（`MSP+0=PC_L, MSP+1=PC_H, MSP+2=PC_B, MSP+3=MODE`、
  decrementしながら書き込み）を保存してからモードを切り替える。
  write順序・MSP24増減タイミングはPhase11のCALL.L（3byte版）に
  「MODEバイトを先頭に追加」した形でそのまま拡張。
- **RET.M**: 4byte（LOW→HIGH→BANK→MODEの順、incrementしながら読み込み）
  をpopし、PC24とモード両方を復元する。他のPhase12命令（JP.Mx/CALL.Mx）
  がモードを固定値へ切り替えるのに対し、RET.Mだけはpopした値から
  モードを復元する点が異なる。
- GHDLテストベンチ:
  [tb_phase12_mode_control.vhd](fpga/G80A/test/tb_phase12_mode_control.vhd)
  （JP.M0/M1/M2、CALL.M0/M1→RET.Mの往復2回を検証済み。4byte frame
  の内容・MSP24の正しい復元も確認済み）。

### 10.2 既知の問題：CALL.M2 addr24は未実装（MCycle幅の上限）

`CALL.M2 addr24`は、addr24ターゲットの読み込み（3byte）と4byte frame
の書き込みを合わせて「1(opcode) + 3(fetch) + 4(push) = 8 MCycles」が
必要になるが、T80コアの`MCycle`信号は3bit幅（表現できる最大値は7）で
あり、**ハードウェア的にこれ以上拡張できない**。

Phase11のCALL.L実装時に発見・修正した「DD/FD+CB二重prefix専用のはずの
`MCycle=110/111`無条件発火バグ」（`XY_State`ガードで解決済み）とは
異なり、これは信号幅そのものの限界であり、同様の対症療法では解決
できない。解決するには以下のいずれかが必要で、いずれもT80コア本体への
比較的大きな変更を伴うため、現時点では保留とし、着手前に方針を
別途相談する。

- `MCycle`を4bit以上へ拡張する（t80_mcode.vhd全体の既存比較箇所
  （100箇所以上）に影響するため、工数・リグレッションリスクが大きい）。
- `CALL.M2`のフレーム構成・フェッチ方式を見直し、7 MCycle以内に
  収まる代替実装にする（例: 4byte push相当の情報を分割する、等）。

`JP.M2`/`CALL.M0`/`CALL.M1`/`RET.M`は上記の制約を受けないため、
既に実装・検証済み。

---

## 11. RST拡張（RST.L）

`RST_B`がRST.L用8bit bankレジスタ（上記「2. バンクレジスタ」参照）。M0/M1では対応する通常Z80 RST（return PCは16bit）、M2ではreturn PC24をMSPへ3byte pushし`PC24={RST_B,00h,vector}`。

| オペコード | 命令 | 状態 |
|---|---|---|
| `ED C7` / `CF` | `RST.L 00H` / `08H` | 未実装 |
| `ED D7` / `DF` | `RST.L 10H` / `18H` | 未実装 |
| `ED E7` / `EF` | `RST.L 20H` / `28H` | 未実装 |
| `ED F7` / `FF` | `RST.L 30H` / `38H` | 未実装 |

> 通常（ED非前置）の `RST 00H〜38H` は既存Z80標準命令として実装済みです。

---

## 12. 割り込み（M2拡張）

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED 4E` | `RETI.L` | M2用4byte frame復元 | 未実装 |
| `ED 8C` | `RETN.L` | M2用4byte frame復元、IFF1<-IFF2 | 未実装 |
| `ED 8D`〜`8F` | RESERVED | 未実装中はNOP | 未実装（現状は未定義opcodeとしてNOP動作） |

---

## 13. 標準 Z80 ブロック転送 / I/O

| オペコード | 命令 | 内容 | 状態 |
|---|---|---|---|
| `ED A0` / `A8` | `LDI` / `LDD` | ブロック転送 | 実装済み（Z80 標準） |
| `ED B0` / `B8` | `LDIR` / `LDDR` | 連続ブロック転送 | 実装済み（Z80 標準） |
| `ED 78` / `48` | `IN A, (C)` / `OUT (C), A` | I/O ポートアクセス | 実装済み（Z80 標準） |
| `ED A2` / `A3` | `INI` / `OUTI` | I/O からメモリ転送 | 実装済み（Z80 標準） |
| `ED B2` / `B3` | `INIR` / `OTIR` | 連続 I/O 転送 | 実装済み（Z80 標準） |

---

## 14. バンクマッピング / MMU I/O ポート

**デフォルトビルドの標準仕様（MMUなし）:** 24bit論理アドレスのバンクバイト（A23:A16、`A_Bank`/`cpu_addr24[23:16]`）は、変換テーブルを介さず**そのまま**物理バンクバイトとして使われます（straight-through mapping、[top.v](fpga/top.v)の`assign mmu_physical_bank = cpu_addr24[23:16];`）。論理bank00h（Z80互換空間）は例外的に既存のMSX互換スロット/BIOS/マッパー経路をそのまま使い、常に読み書き可能です。それ以外の論理bank（01h〜1Bh、27バンク）はそのまま同じ値の物理bankとしてSD-RAM拡張メモリ領域（詳細は[SDRAMメモリマップ.md](doc/jpn/SDRAMメモリマップ.md)2.2章）へ直結され、write protectionなしで常に読み書き可能です。F0h/F1h/F2h等のMMU I/Oポートはデフォルトビルドには存在しません。

### 14.1 オプション機能：MMU（論理→物理バンク変換・write protection）

24bit論理アドレスのバンクバイトを物理バンクへ変換するLUT（[mmu24.vhd](fpga/G80A/mmu24.vhd)）を、オプションの追加機能として用意しています。変換そのものは非同期lookupで、追加のWAIT/T-stateは発生しません。**本リポジトリに実装・GHDL検証済みの状態で同梱されていますが、デフォルトビルドの`top.v`からは呼び出されておらず（`MSXNanoTang20K_Z80X24.gprj`でも`enable="0"`）、合成結果には含まれません。** これは、Tang Nano 20K上の現在のFPGA面積配分ではブートROM等の既存IPがBSRAMを全消費しており、MMUの256エントリテーブルがLUTベースの distributed RAMへfallbackしてLUT/Register使用率をそれぞれ約12〜13ポイント押し上げていたためです。BSRAMに余裕のある構成では、`mmu24.vhd`冒頭コメントおよび[top.v](fpga/top.v)の該当コメントの手順に従って再度有効化できます。

| ポート | 名称 | 内容 | 状態 |
|---|---|---|---|
| `F0h` | `MMU_INDEX` | `MMU_DATA`/`MMU_ATTR` が参照するテーブル index（8bit）の読み書き | 実装済み・実機確認済み（有効化していた時点で[top.v](fpga/top.v)にF0h/F1h/F2h I/Oポートとして配線・動作確認。現在はデフォルトビルドでは無効） |
| `F1h` | `MMU_DATA` | `MMU_DATA[MMU_INDEX]`（論理bank→物理bankの変換テーブル1エントリ）の読み書き | 実装済み・実機確認済み（index=00hへの書込みは無視され常に00h固定） |
| `F2h` | `MMU_ATTR` | `MMU_ATTR[MMU_INDEX]`（bit5=W：書込み許可属性。他bitはRESERVED）の読み書き | 実装済み（GHDLシミュレーション確認済み、[tb_phase6_mmu_attr.vhd](fpga/G80A/test/tb_phase6_mmu_attr.vhd)参照。実機未確認） |

- Reset時は全`MMU_DATA`=00hで、論理bank00hは常に物理bank00h（既存MSX互換64KB）へaliasします。`MMU_DATA[00]`は固定で書込みを無視します。
- Reset時は全`MMU_ATTR`=20h（bit5=W=1、書込み許可）です。ソフトウェアが明示的にW=0へ設定するまで、既存の24bit対応コードの挙動は変わりません。
- `F0h`（`MMU_INDEX`）はF0hへの明示的な書込みでのみ変化します。`F1h`/`F2h`へのアクセス（読み書きいずれも）はindexを自動incrementしません。
- `MMU_ATTR`のW=0は、対応する論理bankへの実際の書込み（Write Enable）のみを抑止します。CPU命令自体は正常完了し、例外/trapは発生しません（有効化した場合、`top.v`で`Write_Allow`が`cpu_sdram_write`をゲートします）。
- 論理bank00h（Z80/MSX互換64KB空間）は`MMU_DATA`と同様に`MMU_ATTR`でも例外扱いです。`MMU_ATTR[00h]`への書込みは無視され、bank00hの`Write_Allow`は常に`1`（書込み許可）として扱われます。bank00hは拡張SD-RAM経路自体を使わず既存のMSX互換スロット/マッパー経由でアクセスされるため、常に読み書き可能という不変条件が保たれます。
- 変換結果（物理bank）は有効化した場合、[top.v](fpga/top.v)で実SD-RAM経路（`memory_ctrl`の`cpu_sdram_req`/`cpu_sdram_addr`）に配線されます。ただし物理bank **01h〜1Bh（27バンク、約1.6875MB）のみ**対応しており、これを超える物理bankは未接続（読出しは0xFF、書込みは無視）です。詳細な物理アドレス割り当ては[SDRAMメモリマップ.md](doc/jpn/SDRAMメモリマップ.md)の2.2章を参照してください。
- **Phase5「MMU実機検証」は、MMUが有効だった時点で実機（Tang Nano）で確認済みです**（[Project/MMUTest](../Project/MMUTest)のMSX-DOS(2)用テストプログラム`MMUTEST.COM`で、物理bank間の独立性・エイリアス・MMU_DATA[n]=00hの64KB互換aliasを含む全8テストがPASS）。Phase6（`MMU_ATTR.W`）はGHDLシミュレーションで確認済みですが、実機検証は未実施です。MMUTestはMMU_DATA[n]=n（straight-through）設定で動かせば、現在のデフォルト仕様の動作確認にもそのまま使えます。

---

## 補足

- 24bit 拡張命令には、Z80 既存命令に `ED` を前置する「mirror 方式」を採用しています。
- `M0` の場合は従来の 64KB 空間へ戻り、互換性を維持します。
- `M1` はデータアクセスのみ 24bit 化されます。(Phase3時点では `(HL)` / `(BC)` / `(DE)` / `(IX+d)` / `(IY+d)` の間接アクセスが対象。SP経由のスタックアクセスとPC相対の命令フェッチ・直接16bitアドレス指定は未対応で、`M0`/`M1`/`M2` のいずれでも常に16bit扱いです。)
- `M2` は 24bit ネイティブ動作としてフル拡張モードになります。
