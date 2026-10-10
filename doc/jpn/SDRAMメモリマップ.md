# SD-RAMメモリマップ（MSXnano-Z80X 実装検証版）

> ⚠️ 本バージョンは、ドキュメント内の全ての記述を実際のRTLソース（[fpga/top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v)、[fpga/src/memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v)、[fpga/src/ocm/swioports.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/ocm/swioports.vhd) 等）と照合して書き直したものです。旧版は移植元（OCM-PLD/1chipMSX系）の設計をそのまま転記しており、本リポジトリの実装と食い違う記述が複数含まれていたため全面修正しました。

Tang Nano 20K内蔵の8MB SD-RAM（物理バイトアドレス 0x000000〜0x7FFFFF、23bit幅）は、[memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:1) の `memory_ctrl` モジュールが一元管理しています。実際にSD-RAMへアクセスする要求元（クライアント）は次の4系統です。

- `mapper_req` / `mapper_addr`（Memory Mapper＝メインRAM）
- `megaram_req` / `megaram_addr`（MegaRAM / SCC拡張RAM）
- `vram_din` / `vram_addr`（VDP(V9958) VRAM、専用タイムスロットでアクセス）
- `cpu_sdram_req` / `cpu_sdram_addr`（Z80X24 24bit CPU拡張メモリ。MMU24によるバンク変換経由、Phase5で接続。詳細は4章）

`cpu_sdram_req` という4つ目の入力ポートも `memory_ctrl` には存在し（[memory.v:10](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:10)）、Phase5（24bit CPU拡張のMMU実機検証）で [top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1230) のインスタンス化箇所に接続されました。詳細は4章を参照してください。**MAIN-ROM/SUB-ROM（BIOS）はこの4系統のいずれにも含まれず、SD-RAMを一切使用しません**（詳細は3章）。

------------------------------
## 1. OCM-PLD（移植元）と MSXnano-Z80X（本実装）の違い

本プロジェクトは 1chipMSX / OCM-PLD 系コア（jabadiagm/MSXgoauld_tn20k, RetroSilicon/MSXnano 等）を移植したものですが、BIOS周りの実装方針は移植元と大きく異なります。混同しないよう、設計意図（移植元）と実装事実（本リポジトリ）を分けて整理します。

| 項目 | OCM-PLD / 1chipMSX系（移植元の設計） | MSXnano-Z80X（本リポジトリの実装） |
|---|---|---|
| MAIN-ROM/SUB-ROM(BIOS)の格納場所 | SD-RAM上（380000h〜 等）に配置 | **FPGA内蔵ブロックRAM（BSRAM）**。SD-RAM不使用 |
| BIOSの供給方法 | SDカード上の `OCM-BIOS.DAT` をIPL（初期ローダー）がSD-RAMへ書き込み、差し替え・アップデートが可能 | **合成（論理合成）時に `.hex` ファイルの内容をビットストリームへ焼き込み**。実行時のロードなし、差し替え不可 |
| IPL（初期ローダー）回路 | 実装あり | **実装なし**。`ff_ldbios_n`等 "IPL-ROM" グループの信号は [swioports.vhd:103](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/ocm/swioports.vhd:103) に残存するが、[top.v:1913](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1913) のインスタンス化で未結線 |
| NEXTOR/DISK-BIOS 領域 | SD-RAM上に確保 | 該当回路自体が存在しない（未実装） |
| KANJI/OPLL内蔵ROM 領域 | SD-RAM上に確保 | 該当回路自体が存在しない（未実装） |
| VDP VRAM | SD-RAM上 | 同じく **SD-RAM上**（この点は移植元と同じ。専用バンク固定・CPU経路とは別のタイムスロットでアクセス） |
| `OCM-BIOS.DAT` というファイル名 | 実在（SDカードに配置） | リポジトリ全体を検索しても該当箇所なし（本実装では不要） |

つまり、本実装でSD-RAMを実際に使っているのは **Memory Mapper・MegaRAM/SCC・VDP VRAM・（Phase5以降）Z80X24 CPU拡張メモリ** です。MAIN-ROM/SUB-ROM/NEXTOR/KANJIをSD-RAMに載せる設計は移植元には存在しますが、本リポジトリでは引き継がれていません。

------------------------------
## 2. 実装に基づくSD-RAM物理アドレス配置表（検証済み）

バイトアドレス（23bit、0x000000〜0x7FFFFF = 8MB）は [memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:95) のアドレス結合ロジックから直接確認できます（旧版の「ワードアドレス×2＝バイトアドレス」という換算は撤廃し、実際にRTLで扱われているバイトアドレスのみを記載します）。

| 領域名（機能） | バイトアドレス範囲 | 容量 | 実装根拠（ファイル:行） |
|---|---|---|---|
| Memory Mapper（メインRAM） | 0x000000 〜 0x3FFFFF | 4MB | `sdram_addr <= {1'b0, mapper_addr[21:0]}` — [memory.v:97](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:97) |
| MegaRAM / SCC拡張RAM | 0x400000 〜 0x5FFFFF | 2MB | `sdram_addr <= {3'b10, megaram_addr[20:0]}` — [memory.v:105](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:105) |
| VDP VRAM（現在の実使用分） | 0x600000 〜 0x61FFFF | 128KB | `SdrBa<=2'b11`固定＋専用タイムスロット、`vram_addr`は実質17bit幅 — [memory.v:339-385](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:339) |
| **VDP VRAM予約領域**（拡張VRAM等を見込んだマージン） | 0x620000 〜 0x63FFFF | +128KB（合計256KB予約） | ハード的な制約はないが、V9958の拡張VRAMモード等に備えて**予約**（下記3.1参照） |
| （未使用、予備） | 0x640000 〜 0x64FFFF | 64KB | Z80X24拡張メモリ領域の先頭64KB。物理bank 00hは「MSX互換64KBへのalias」専用（[mmu24.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A/mmu24.vhd)）のためこの経路を通らず、意図的に未割当のまま |
| **Z80X24 CPU拡張メモリ**（物理bank 01h〜1Bh） | 0x650000 〜 0x7FFFFF | 約1.6875MB（27×64KB） | `cpu_sdram_addr <= CPU_SDRAM_BASE + {mmu_physical_bank, bus_addr}` — [top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1230)（`CPU_SDRAM_BASE=0x640000`、`mmu_physical_bank`は[mmu24.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A/mmu24.vhd)のMMU_DATA変換結果） |

### 2.1 VDP VRAMについて：256KBを予約領域とする理由

現在の実装では `vram_addr` は実質17bit幅（行アドレス`vram_addr[10:0]`＋列アドレス`vram_addr[15:11]`＋バイトレーン選択`vram_addr[16]`）で、アクセスされるのは先頭の **128KB（0x600000〜0x61FFFF）のみ**です（V9958の標準VRAM容量と一致）。

ただし、V9958は設定次第で128KBを超える拡張VRAM構成（192KB等）を取り得るため、将来的にVRAM容量を拡張する改修が入る可能性があります。そのため、本ドキュメントでは安全マージンとして **0x600000〜0x63FFFF（256KB）をVDP用に予約**し、他用途での使用を避けることを推奨します。現時点でこの256KB全体がハードウェア的に専有されているわけではなく、あくまで将来の拡張に備えた予約です。

### 2.2 Z80X24 CPU拡張メモリについて（Phase5で追加）

24bit CPU拡張（M1/M2モード）でCPUコアが出す論理バンクバイト（`A_Bank`）は、[mmu24.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/G80A/mmu24.vhd) のMMU_DATAテーブル（F0h/F1h経由でソフトウェアが設定）で物理バンクバイトへ変換されます。この物理バンクバイトは [top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1230) で `cpu_sdram_req`/`cpu_sdram_addr` として `memory_ctrl` の空きクライアントポートへ配線されており、以下のルールで実アドレスへ変換されます。

- 物理bank 00h：`mmu24.vhd`で固定的に「MSX互換64KBへのalias」を意味するため、`cpu_sdram_req`は発行されず、既存のスロット/BIOS/マッパーデコード（本ドキュメント2章の領域）がそのまま使われます。
- 物理bank 01h〜1Bh（27バンク）：`0x650000`〜`0x7FFFFF`へ1バンク=64KBで直線的にマッピングされます。
- 物理bank 1Ch以上：現状どの領域にも接続されていません（アクセスすると読出しは`0xFF`、書込みは無視されます）。より大きな専用SD-RAM割り当てを追加する際の拡張余地です。

`cpu_sdram_req`は `mode24`/バンクレジスタの値のみで判定しており、既存のスロット/マッパーデコード（`pri_slot_num`等）とは独立しています。そのため、拡張メモリアクセス中のHL/BC/DE/(IX+d)/(IY+d)がMemory Mapper等が有効な16bitアドレスと重なった場合、同一バスサイクルで両方のクライアントが要求を出すことがあります。MSX-DOS2は多くの構成でTPA自体をMemory Mapper RAM上に置くため、これは実運用では「稀なケース」ではなく「ほぼ毎回起きるケース」でした。

このため、[memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v)のアービタは `cpu_sdram_req` を `mapper_req`/`megaram_req` より**常に優先**するよう実装されています（Phase5実機検証で発見・修正。優先順位が逆だった当初実装では、拡張メモリへの書込みが実際にはMemory Mapper RAMへ書き込まれてしまい、読出しは常に未更新の`cpu_sdram_dout`=00hを返していました）。`cpu_sdram_req`はmode24=M0の通常MSXソフトでは常に0なので、この優先順位変更は既存のMSX互換動作には一切影響しません。

この優先順位修正を含め、[Project/MMUTest](../../Project/MMUTest)のMSX-DOS(2)用テストプログラム`MMUTEST.COM`により、物理bank間の独立性・エイリアス・`MMU_DATA[n]=00h`の64KB互換aliasを含む全8テストが実機（Tang Nano）でPASSすることを確認済みです。

------------------------------
## 3. MAIN-ROM/SUB-ROM（BIOS）の実際の格納方式

[top.v:962](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:962) で、BIOS関連は以下のように直接インスタンス化されています。SD-RAMコントローラ（`memory_ctrl`）へは一切接続されていません。

| 内容 | モジュール | ROMデータソース | 容量 |
|---|---|---|---|
| MAIN-ROM (BIOS) | `bios_msx2p`（[bios_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/bios_msx2p.v)） | `bios_msx2p.hex` | 32KB |
| SUB-ROM | `subrom_msx2p`（[subrom_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/subrom_msx2p.v)） | `16k_msx2p_subrom.hex` | 16KB |
| MSXロゴ | `logo_fm` | （専用hexファイル） | 14KB分のアドレス空間 |

いずれも `reg [7:0] mem_r[...]` ＋ `$readmemh(...)` という単純な配列記述で、**論理合成時にFPGA内蔵ブロックRAM（BSRAM）として推論され、ビットストリームに内容が焼き込まれます**。実行時にSDカードからロードする処理（IPL）は存在せず、`OCM-BIOS.DAT` というファイルもこのリポジトリ内に見当たりません。

BIOSを差し替えたい場合は、合成前に該当 `.hex` ファイルを書き換えて再ビルドする必要があります。

------------------------------
## 4. Z80X24プロジェクトで安全に使える領域

現状のSD-RAM利用状況をまとめると、8MB中 Memory Mapper(4MB) + MegaRAM/SCC(2MB) + VDP VRAM予約(256KB) で合計 6.25MB が既存機能によって占有（または予約）されています。残りの約1.75MB（0x640000〜0x7FFFFF）のうち、Phase5で追加した **Z80X24 CPU拡張メモリ（物理bank 01h〜1Bh、0x650000〜0x7FFFFF、約1.6875MB）が新たに占有**しました。残る安全な空き領域は、先頭の64KB（0x640000〜0x64FFFF）のみです。

| 項目 | 値 |
|---|---|
| 安全に利用可能なバイトアドレス範囲 | 0x640000 〜 0x64FFFF |
| 容量 | 64KB |
| 根拠 | `memory_ctrl`（[memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v)）内でMapper/MegaRAM/VRAM/`cpu_sdram_*`のいずれのアドレスデコードもこの範囲を生成しない（`cpu_sdram_addr`は物理bank 00hを使わないため0x650000から開始、[top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1230)参照） |

### 利用時の注意

1. **VDP予約領域(0x600000〜0x63FFFFまでの256KB)、およびZ80X24 CPU拡張メモリ領域(0x650000〜0x7FFFFF)とは重複させないこと。**
2. この64KBを使う新規デバイスを実装する場合、`memory_ctrl` に新しいクライアントポート一式（`req`/`addr`/`write`/`dout`）を追加し、`sdram_seq`の調停ロジックへ組み込む必要があります（現状の `cpu_sdram_req`系ポートはZ80X24 CPU拡張メモリとして使用済みです、2.2章参照）。
3. SD-RAM自体は23bit＝8MBの物理アドレス空間の上限を持つため、これを超えるアドレス指定はラップアラウンドしてメモリ内容を破壊します。
4. Z80X24 CPU拡張メモリの物理bank 1Ch以上は現状どこにも接続されておらず、より広い領域が必要になった場合は`memory_ctrl`側のSD-RAM割り当て再設計（`CPU_SDRAM_BANK_MAX`の拡大、または専用クライアントポートの追加）が必要です。

------------------------------
## 5. 参照した実装ファイル一覧

- [fpga/top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v) — BIOS/SUBROM/ロゴのインスタンス化、`memory_ctrl`への接続
- [fpga/src/memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v) — SD-RAMアドレス調停・デコードロジック本体
- [fpga/src/bios_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/bios_msx2p.v) / [fpga/src/subrom_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/subrom_msx2p.v) — BIOS/SUBROMの内蔵BRAM実装
- [fpga/src/ocm/swioports.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/ocm/swioports.vhd) — 移植元由来のIPL関連信号（未結線）
