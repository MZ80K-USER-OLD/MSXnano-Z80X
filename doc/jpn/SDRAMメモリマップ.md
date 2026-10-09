# SD-RAMメモリマップ（MSXnano-Z80X 実装検証版）

> ⚠️ 本バージョンは、ドキュメント内の全ての記述を実際のRTLソース（[fpga/top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v)、[fpga/src/memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v)、[fpga/src/ocm/swioports.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/ocm/swioports.vhd) 等）と照合して書き直したものです。旧版は移植元（OCM-PLD/1chipMSX系）の設計をそのまま転記しており、本リポジトリの実装と食い違う記述が複数含まれていたため全面修正しました。

Tang Nano 20K内蔵の8MB SD-RAM（物理バイトアドレス 0x000000〜0x7FFFFF、23bit幅）は、[memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:1) の `memory_ctrl` モジュールが一元管理しています。実際にSD-RAMへアクセスする要求元（クライアント）は次の3系統のみです。

- `mapper_req` / `mapper_addr`（Memory Mapper＝メインRAM）
- `megaram_req` / `megaram_addr`（MegaRAM / SCC拡張RAM）
- `vram_din` / `vram_addr`（VDP(V9958) VRAM、専用タイムスロットでアクセス）

`cpu_sdram_req` という4つ目の入力ポートも `memory_ctrl` には存在しますが（[memory.v:10](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:10)）、[top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v:1160) のインスタンス化箇所で接続されておらず、現状は未使用です。**MAIN-ROM/SUB-ROM（BIOS）はこの3系統のいずれにも含まれず、SD-RAMを一切使用しません**（詳細は3章）。

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

つまり、本実装でSD-RAMを実際に使っているのは **Memory Mapper・MegaRAM/SCC・VDP VRAM の3つだけ**です。MAIN-ROM/SUB-ROM/NEXTOR/KANJIをSD-RAMに載せる設計は移植元には存在しますが、本リポジトリでは引き継がれていません。

------------------------------
## 2. 実装に基づくSD-RAM物理アドレス配置表（検証済み）

バイトアドレス（23bit、0x000000〜0x7FFFFF = 8MB）は [memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:95) のアドレス結合ロジックから直接確認できます（旧版の「ワードアドレス×2＝バイトアドレス」という換算は撤廃し、実際にRTLで扱われているバイトアドレスのみを記載します）。

| 領域名（機能） | バイトアドレス範囲 | 容量 | 実装根拠（ファイル:行） |
|---|---|---|---|
| Memory Mapper（メインRAM） | 0x000000 〜 0x3FFFFF | 4MB | `sdram_addr <= {1'b0, mapper_addr[21:0]}` — [memory.v:97](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:97) |
| MegaRAM / SCC拡張RAM | 0x400000 〜 0x5FFFFF | 2MB | `sdram_addr <= {3'b10, megaram_addr[20:0]}` — [memory.v:105](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:105) |
| VDP VRAM（現在の実使用分） | 0x600000 〜 0x61FFFF | 128KB | `SdrBa<=2'b11`固定＋専用タイムスロット、`vram_addr`は実質17bit幅 — [memory.v:339-385](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:339) |
| **VDP VRAM予約領域**（拡張VRAM等を見込んだマージン） | 0x620000 〜 0x63FFFF | +128KB（合計256KB予約） | ハード的な制約はないが、V9958の拡張VRAMモード等に備えて**予約**（下記3.1参照） |
| 空き（安全に利用可能） | 0x640000 〜 0x7FFFFF | 約1.75MB（1792KB） | 上記いずれのクライアントからも未接続・未使用 |

### 2.1 VDP VRAMについて：256KBを予約領域とする理由

現在の実装では `vram_addr` は実質17bit幅（行アドレス`vram_addr[10:0]`＋列アドレス`vram_addr[15:11]`＋バイトレーン選択`vram_addr[16]`）で、アクセスされるのは先頭の **128KB（0x600000〜0x61FFFF）のみ**です（V9958の標準VRAM容量と一致）。

ただし、V9958は設定次第で128KBを超える拡張VRAM構成（192KB等）を取り得るため、将来的にVRAM容量を拡張する改修が入る可能性があります。そのため、本ドキュメントでは安全マージンとして **0x600000〜0x63FFFF（256KB）をVDP用に予約**し、他用途での使用を避けることを推奨します。現時点でこの256KB全体がハードウェア的に専有されているわけではなく、あくまで将来の拡張に備えた予約です。

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

現状のSD-RAM利用状況をまとめると、8MB中 Memory Mapper(4MB) + MegaRAM/SCC(2MB) + VDP VRAM予約(256KB) で合計 6.25MB が既存機能によって占有（または予約）されています。残りの **約1.75MB（0x640000〜0x7FFFFF）が、どのクライアントからも一切参照されていない、真に安全な空き領域**です。

| 項目 | 値 |
|---|---|
| 安全に利用可能なバイトアドレス範囲 | 0x640000 〜 0x7FFFFF |
| 容量 | 約1.75MB（1792KB） |
| 根拠 | `memory_ctrl`（[memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v)）内でMapper/MegaRAM/VRAMのいずれのアドレスデコードもこの範囲を生成しない |

### 利用時の注意

1. **VDP予約領域(0x600000〜0x63FFFFまでの256KB)とは重複させないこと。** 将来VRAM拡張が実装された場合に備え、0x640000以降のみを使用してください。
2. この領域を使う新規デバイス（例：追加ROM、拡張RAM）を実装する場合、`memory_ctrl` に新しいクライアントポート（`mapper_req`/`megaram_req`と同様の `req`/`addr`/`write`/`dout` 一式）を追加し、`sdram_seq`の調停ロジックへ組み込む必要があります。現状の `cpu_sdram_req`系ポート（[memory.v:10](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v:10)）は未結線のまま存在しているため、流用を検討できます。
3. SD-RAM自体は23bit＝8MBの物理アドレス空間の上限を持つため、これを超えるアドレス指定はラップアラウンドしてメモリ内容を破壊します。

------------------------------
## 5. 参照した実装ファイル一覧

- [fpga/top.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/top.v) — BIOS/SUBROM/ロゴのインスタンス化、`memory_ctrl`への接続
- [fpga/src/memory.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/memory.v) — SD-RAMアドレス調停・デコードロジック本体
- [fpga/src/bios_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/bios_msx2p.v) / [fpga/src/subrom_msx2p.v](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/subrom_msx2p.v) — BIOS/SUBROMの内蔵BRAM実装
- [fpga/src/ocm/swioports.vhd](/d:/Users/HeroineFactory/Documents/GIT/MSXNano-Z80X/msxnano-24bit/fpga/src/ocm/swioports.vhd) — 移植元由来のIPL関連信号（未結線）
