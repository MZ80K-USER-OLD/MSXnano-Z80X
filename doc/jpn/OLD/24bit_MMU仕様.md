# MSX T80 24bit拡張 MMU 仕様書

## 1. 目的

本MMUは、MSX T80 24bit拡張CPUにおいて、64KB単位の論理バンクを物理バンクへマッピングするための機構である。

24bitアドレス空間は256個の64KBバンクで構成される。

- バンク数: 256
- 1バンク: 64KB
- 総アドレス空間: 16MB
- 論理バンク番号: `00h～FFh`
- 物理バンク番号: `00h～FFh`

## 2. MMUレジスタ

MMUは256個の8bitレジスタを持つ。

```text
MMU[00h] ～ MMU[FFh]
```

各レジスタの値は、対応する論理バンクの物理バンク番号を指定する。

```text
Physical Address[23:16] = MMU[Logical Address[23:16]]
Physical Address[15:0]  = Logical Address[15:0]
```

したがって、MMUは24bit論理アドレスの上位8bitだけを変換し、下位16bitはそのまま使用する。

## 3. バンク00hの固定

論理バンク`00h`は特別扱いとする。

```text
MMU[00h] = 00h
```

これはハードウェアで固定し、ソフトウェアから変更できない。

論理バンク00hの全64KBは、常に従来のMSX 64KB空間へ接続する。

```text
00:0000h ～ 00:FFFFh
        ↓
MSX 64KB
```

`MMU[00h]`への書き込みは無視する。

## 4. MMUの有効モード

MMUはM1およびM2で有効とする。

| CPUモード | MMU | 動作 |
|---|---|---|
| M0 | 無効 | MSX互換、従来の64KB空間 |
| M1 | 有効 | レジスタインダイレクト24bitアクセスで使用 |
| M2 | 有効 | 24bitネイティブアドレスアクセスで使用 |

M0ではMMUをバイパスする。

## 5. I/Oポート

MMU制御には2個のI/Oポートを使用する。

| I/Oポート | 名称 | 機能 |
|---|---|---|
| `0F0h` | `MMU_INDEX` | MMUレジスタ番号を指定 |
| `0F1h` | `MMU_DATA` | 指定したMMUレジスタの読み書き |

### 5.1 MMUレジスタ番号指定

```asm
LD A,12h
OUT (0F0h),A
```

実行後、

```text
MMU_INDEX = 12h
```

となる。

### 5.2 MMUレジスタ書き込み

```asm
LD A,80h
OUT (0F1h),A
```

実行後、

```text
MMU[12h] = 80h
```

となる。

動作は以下の通り。

```text
OUT (0F0h),A
    ↓
MMU_INDEX ← A

OUT (0F1h),A
    ↓
MMU[MMU_INDEX] ← A
```

ただし`MMU_INDEX=00h`の場合は、書き込みを無視する。

### 5.3 MMUレジスタ読み出し

```asm
LD A,12h
OUT (0F0h),A
IN A,(0F1h)
```

実行結果：

```text
A ← MMU[12h]
```

## 6. リセット時の初期値

リセット時は恒等マッピングとする。

```text
MMU[00h] = 00h
MMU[01h] = 01h
MMU[02h] = 02h
...
MMU[FEh] = FEh
MMU[FFh] = FFh
```

これにより、リセット直後は、

```text
論理BANK 00 → MSX 64KB
論理BANK 01 → 物理BANK 01
論理BANK 02 → 物理BANK 02
...
論理BANK FF → 物理BANK FF
```

となる。

ただし、物理メモリが8MB構成の場合、物理バンク`80h～FFh`には実体がない。
したがって、恒等マッピングの値を保持していても、物理バンク属性の`VALID`が0のバンクへのアクセスを有効なSDRAMアドレスへ折り返してはならない。

未実装の物理バンクへのアクセスは、以下の動作とする。

- 読み出し: `FFh`を返す
- 書き込み: 無視する
- 命令フェッチ: 読み出しと同じく`FFh`を返す

これにより、8MBを超える物理アドレスがSDRAMの先頭へラップアラウンドして、既存データを破壊することを防止する。

## 7. アドレス変換例

例えば、

```text
MMU[12h] = 80h
```

の場合、

```text
論理アドレス 12:8000h
        ↓
物理アドレス 80:8000h
```

となる。

また、

```text
MMU[02h] = 20h
```

なら、

```text
論理BANK 02h
0000h～FFFFh
        ↓
物理BANK 20h
0000h～FFFFh
```

となる。

## 8. FPGA実装上の基本構造

MMUは256×8bitのレジスタ配列として実装できる。

```text
CPU Logical Address[23:16]
          │
          ▼
      MMU[8bit]
          │
          ▼
Physical Address[23:16]

CPU Logical Address[15:0]
          │
          └──────────────→ Physical Address[15:0]
```

バンク00hについてはMMU配列の値によらず、MSX 64KBへ固定する。

## 9. M1/M2との関係

M1ではCPUが生成した24bit論理アドレスの上位8bitをMMUレジスタ番号として使用する。

M2でも同じMMU変換規則を使用し、24bit論理アドレスを24bit物理アドレスへ変換する。

したがってMMUは、

```text
24bit Logical Address
        ↓
       MMU
        ↓
24bit Physical Address
```

## 10. バンク属性

MMUレジスタの物理バンク番号とは別に、各バンクに属性を持たせる。
属性は、物理バンクが実在するか、およびそのバンクをどのようなデバイスとして扱うかを決定する。

### 10.1 属性項目

| 属性 | 内容 |
|---|---|
| `VALID` | 物理バンクが実在し、アクセス可能か。0の場合は未実装または予約領域 |
| `TYPE` | `MSX64K`、`RAM`、`ROM`、`VRAM`、`IO`、`RESERVED`のいずれか |
| `READ` | 読み出し可能か |
| `WRITE` | 書き込み可能か |
| `EXECUTE` | 命令フェッチ可能か |
| `SIDE_EFFECT` | アクセスによりデバイス動作などの副作用が発生するか |
| `OWNER` | `MSX_COMPAT`、`LINEAR_24BIT`、`SHARED`のいずれか |

`physical_bank`は物理バンクの位置を示し、これらの属性は物理バンクの性質を示す。
論理バンクごとのアクセス制限を設ける場合は、物理バンク属性に加えて論理MMUエントリ側にも`READ`、`WRITE`、`EXECUTE`を持たせる。
実際のアクセス権は、物理属性と論理属性の両方が許可している場合に限り有効とする。

### 10.2 MMU属性レジスタの構成

既存の`MMU_INDEX`および`MMU_DATA`の動作は維持する。
属性をソフトウェアから参照または設定する場合は、属性アクセス用のポートを追加する。

| I/Oポート | 名称 | 機能 |
|---|---|---|
| `0F0h` | `MMU_INDEX` | 論理バンク番号を指定 |
| `0F1h` | `MMU_DATA` | 物理バンク番号を読み書き |
| `0F2h` | `MMU_ATTR` | 指定した論理バンクの属性を読み書き |

`MMU_ATTR`のビット割り当ては以下を基本とする。

```text
bit 0: VALID
bit 1: READ
bit 2: WRITE
bit 3: EXECUTE
bit 4: SIDE_EFFECT
bit 5: LINEAR_24BIT
bit 6: MSX_COMPAT
bit 7: 予約、0を書き込む
```

物理デバイスの`TYPE`および`OWNER`は、ハードウェアで固定してもよい。
少なくとも`VALID`、`READ`、`WRITE`、`EXECUTE`は、アクセス判定に使用できるようにする。

### 10.3 物理バンクの初期属性

MSXnanoの8MB SDRAM構成では、64KB単位の物理バンクを以下のように割り当てる。

| 物理バンク | 属性 | 容量 | アクセス |
|---|---|---:|---|
| `00h` | `MSX64K`、`MSX_COMPAT` | 64KB | MSX互換空間へ固定接続 |
| `01h～3Fh` | `RAM`、`SHARED` | 約4MB | `READ/WRITE/EXECUTE` |
| `40h～5Fh` | `RAM`、`LINEAR_24BIT` | 2MB | `READ/WRITE/EXECUTE` |
| `60h～63h` | `VRAM`、`SHARED` | 256KB | `READ/WRITE`、`EXECUTE=0` |
| `64h～6Fh` | `RESERVED`または24bit RAM | 768KB | 実装に応じて設定 |
| `70h～77h` | `ROM`、`MSX_COMPAT` | 512KB | `READ/EXECUTE` |
| `78h～7Bh` | `ROM`、`MSX_COMPAT` | 256KB | `READ/EXECUTE` |
| `7Ch～7Fh` | `ROM`、`MSX_COMPAT` | 256KB | `READ`、必要に応じて`EXECUTE` |
| `80h～FFh` | `RESERVED`、`VALID=0` | 未実装 | 読み出し`FFh`、書き込み無視 |

論理バンク`00h`の属性はソフトウェアから変更できない。
`MMU[00h]`への書き込みを無視する既存仕様に加え、常に`MSX64K`かつ`MSX_COMPAT`として扱う。

### 10.4 アクセス判定

アクセス時は、以下の順序で判定する。

1. M0の場合はMMUをバイパスし、従来のMSX 64KB空間へ接続する。
2. 論理バンクが`00h`の場合は、MMU値によらずMSX 64KB空間へ接続する。
3. MMUから`physical_bank`を取得する。
4. 物理バンクの`VALID`が0の場合は、読み出し`FFh`、書き込み無視とする。
5. 論理属性と物理属性のアクセス権を確認する。
6. 許可されている場合だけ、`TYPE`に応じたメモリまたはデバイスへアクセスする。

物理バンク番号をSDRAMアドレスの上位ビットへ直接接続する場合でも、`VALID`判定を先に行い、未実装バンクのアドレスを生成してはならない。

という共通のアドレス変換機構となる。
