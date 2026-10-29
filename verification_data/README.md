# 検証用データ

入力・期待結果と、RTLシミュレーションの実測結果を分けて保存する。
Fuseのテストベクトルに着想を得た形式だが、Fuseのファイル構文そのものではない。
Z80X24固有のバンク・MODE・WAITを記録するため、UTF-8のJSON Linesを使う。

- [V15 16bit indexed LD](v15_index16/README.md)
- [INDEX16.COM実行回帰](index16_com/README.md)
- [V15 24bit indexed LD](v15_index24/README.md)
- [INDEX24.COM実行回帰](index24_com/README.md)
- [I16M2.COM実行回帰](index16_m2_com/README.md)
- [I24M2.COM実行回帰](index24_m2_com/README.md)
- [V16.1 IM0予防措置](v161_im0/README.md)

実機ログとは区別する。シミュレーションでのPASSを実機検証済みとは扱わない。
