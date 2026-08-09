LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Simple USB -> MSX keyboard matrix mapper
-- Matrix: 11 rows (0..10), 8 columns (bit7..bit0) according to your table.

ENTITY ps2_keyboard_msx IS
    PORT (
        CLK      : IN  STD_LOGIC;
        RESET    : IN  STD_LOGIC;

        -- key vector from USB module; '1' = key pressed
        keyboard : IN  STD_LOGIC_VECTOR(127 DOWNTO 0);

        -- matrix row number selected by CPU (0..10)
        A        : IN  STD_LOGIC_VECTOR(3 DOWNTO 0);

        -- column state in selected row, active low '0'
        DO       : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);

        -- function keys line (F1..F12), active high '1'
        FN       : OUT STD_LOGIC_VECTOR(1 TO 12);

        -- =====================================================================
        -- ★【追加ポート】BeebFPGA Dock BoardからのPS/2物理ピン
        -- 補足: 最上位層(top.v)から接続しやすいよう、あえてinoutとして追加します。
        -- =====================================================================
        ps2_clk  : INOUT STD_LOGIC;
        ps2_data : INOUT STD_LOGIC
    );
END ps2_keyboard_msx;

ARCHITECTURE rtl OF ps2_keyboard_msx IS

    -- 元のコードにあった「keys」という11行分のマトリクス型を定義
    TYPE matrix_type IS ARRAY (0 TO 10) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL keys : matrix_type := (OTHERS => X"FF");

    -- PS/2 受信バッファおよびデコーダ用信号
    -- 11-bit frame = start(0), data(1..8), parity(9), stop(10)
    SIGNAL shift_reg   : STD_LOGIC_VECTOR(10 DOWNTO 0) := (OTHERS => '0');
    SIGNAL bit_count   : INTEGER RANGE 0 TO 10 := 0;
    SIGNAL ps2_clk_sync: STD_LOGIC_VECTOR(2 DOWNTO 0) := "111";
    SIGNAL scan_code   : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"00";
    SIGNAL code_ready  : STD_LOGIC := '0';
    
    -- PS/2 状態管理フラグ
    SIGNAL is_break    : STD_LOGIC := '0';
    SIGNAL is_extended : STD_LOGIC := '0';

    -- ファンクションキー保持用レジスタ（アクティブ・ハイ）
    SIGNAL fn_reg      : STD_LOGIC_VECTOR(1 TO 12) := (OTHERS => '0');


BEGIN
    -- -------------------------------------------------------------------------
    -- 1. PS/2 物理信号（Clock / Data）の同期とシリアルデコード
    -- -------------------------------------------------------------------------
    PROCESS(CLK, RESET)
    BEGIN
        IF RESET = '1' THEN
            bit_count    <= 0;
            ps2_clk_sync <= "111";
            shift_reg    <= (OTHERS => '0');
            scan_code    <= X"00";
            code_ready   <= '0';
        ELSIF rising_edge(CLK) THEN
            code_ready   <= '0';
            ps2_clk_sync <= ps2_clk_sync(1 DOWNTO 0) & ps2_clk;

            IF ps2_clk_sync(2 DOWNTO 1) = "10" THEN
                shift_reg(bit_count) <= ps2_data;

                IF bit_count = 10 THEN
                    bit_count <= 0;
                    -- PS/2 frame layout: start bit at index 0, data bits at 1..8
                    scan_code <= shift_reg(8 DOWNTO 1);
                    code_ready <= '1';
                    shift_reg <= (OTHERS => '0');
                ELSE
                    bit_count <= bit_count + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- -------------------------------------------------------------------------
    -- 2. PS/2 スキャンコード(Set2) から MSXキーマトリクス「keys」への変換
    -- -------------------------------------------------------------------------
    PROCESS(CLK, RESET)
        VARIABLE key_val : STD_LOGIC;
        VARIABLE fn_val  : STD_LOGIC;
    BEGIN
        IF RESET = '1' THEN
            keys        <= (OTHERS => X"FF"); -- 初期状態は全キー解放
            fn_reg      <= (OTHERS => '0');
            is_break    <= '0';
            is_extended <= '0';
        ELSIF rising_edge(CLK) THEN
            IF code_ready = '1' THEN
                IF scan_code = X"F0" THEN
                    is_break <= '1';
                ELSIF scan_code = X"E0" THEN
                    is_extended <= '1';
                ELSE
                    IF is_break = '1' THEN key_val := '1'; fn_val := '0'; 
                    ELSE                   key_val := '0'; fn_val := '1'; 
                    END IF;
                    
                    CASE scan_code IS
                        -- =====================================================
                        -- 行 0 (数値キー等)
                        -- =====================================================
                        WHEN X"45" => keys(0)(0) <= key_val; -- '0'
                        WHEN X"16" => keys(0)(1) <= key_val; -- '1'
                        WHEN X"1E" => keys(0)(2) <= key_val; -- '2'
                        WHEN X"26" => keys(0)(3) <= key_val; -- '3'
                        WHEN X"25" => keys(0)(4) <= key_val; -- '4'
                        WHEN X"2E" => keys(0)(5) <= key_val; -- '5'
                        WHEN X"36" => keys(0)(6) <= key_val; -- '6'
                        WHEN X"3D" => keys(0)(7) <= key_val; -- '7'
                        -- =====================================================
                        -- 行 1 (数値キー、記号等)
                        -- =====================================================
                        WHEN X"3E" => keys(1)(0) <= key_val; -- '8'
                        WHEN X"46" => keys(1)(1) <= key_val; -- '9'
                        -- PCの '-' ➡️ MSXの '-'
                        WHEN X"4E" => keys(1)(2) <= key_val; -- '-' (マイナス)
                        -- PCの '^' または 英語キーの '=' ➡️ MSXの '^'
                        WHEN X"55" => keys(1)(3) <= key_val; -- '^' または '='
                        -- PCの '\' (円マーク) ➡️ MSXの '¥'
                        WHEN X"6A" => keys(1)(4) <= key_val; -- '¥' (国際キーボード対応)
                        -- PCの '@' ➡️ MSXの '@'
                        WHEN X"52" => keys(1)(5) <= key_val; -- '@'
                        -- PCの '[' ➡️ MSXの '['
                        WHEN X"54" => keys(1)(6) <= key_val; -- '['
                        -- PCの ';' ➡️ MSXの ';'
                        WHEN X"4C" => keys(1)(7) <= key_val; -- ';'

                        -- =====================================================
                        -- 行 2 / 3 / 4 / 5 (アルファベット)
                        -- ここは MSX のキーボード行列に合わせて配置する。
                        -- 旧 USB 版と同じ配置に寄せる。
                        -- =====================================================
                        WHEN X"1C" => keys(2)(6) <= key_val; -- 'A'
                        WHEN X"32" => keys(2)(7) <= key_val; -- 'B'
                        WHEN X"21" => keys(3)(0) <= key_val; -- 'C'
                        WHEN X"23" => keys(3)(1) <= key_val; -- 'D'
                        WHEN X"24" => keys(3)(2) <= key_val; -- 'E'
                        WHEN X"2B" => keys(3)(3) <= key_val; -- 'F'
                        WHEN X"34" => keys(3)(4) <= key_val; -- 'G'
                        WHEN X"33" => keys(3)(5) <= key_val; -- 'H'

                        WHEN X"43" => keys(3)(6) <= key_val; -- 'I'
                        WHEN X"3B" => keys(3)(7) <= key_val; -- 'J'
                        WHEN X"42" => keys(4)(0) <= key_val; -- 'K'
                        WHEN X"4B" => keys(4)(1) <= key_val; -- 'L'
                        WHEN X"3A" => keys(4)(2) <= key_val; -- 'M'
                        WHEN X"31" => keys(4)(3) <= key_val; -- 'N'
                        WHEN X"44" => keys(4)(4) <= key_val; -- 'O'
                        WHEN X"4D" => keys(4)(5) <= key_val; -- 'P'

                        WHEN X"15" => keys(4)(6) <= key_val; -- 'Q'
                        WHEN X"2D" => keys(4)(7) <= key_val; -- 'R'
                        WHEN X"1B" => keys(5)(0) <= key_val; -- 'S'
                        WHEN X"2C" => keys(5)(1) <= key_val; -- 'T'
                        WHEN X"3C" => keys(5)(2) <= key_val; -- 'U'
                        WHEN X"2A" => keys(5)(3) <= key_val; -- 'V'
                        WHEN X"1D" => keys(5)(4) <= key_val; -- 'W'
                        WHEN X"22" => keys(5)(5) <= key_val; -- 'X'

                        WHEN X"35" => keys(5)(6) <= key_val; -- 'Y'
                        WHEN X"1A" => keys(5)(7) <= key_val; -- 'Z'
                        -- PCの ':' ➡️ MSXの ':'
                        WHEN X"5B" => keys(5)(2) <= key_val; -- ':'
                        -- PCの ']' ➡️ MSXの ']'
                        WHEN X"5D" => keys(5)(3) <= key_val; -- ']'
                        -- PCの ',' ➡️ MSXの ','
                        WHEN X"41" => keys(5)(4) <= key_val; -- ','
                        -- PCの '.' ➡️ MSXの '.'
                        WHEN X"49" => keys(5)(5) <= key_val; -- '.'
                        -- PCの '/' ➡️ MSXの '/'
                        WHEN X"4A" => keys(5)(6) <= key_val; -- '/'
                        -- PCの '_' (アンダーバー・ろのキー) ➡️ MSXの '_'
                        WHEN X"51" => keys(5)(7) <= key_val; -- '_'

                        -- =====================================================
                        -- 行 6 (修飾キー)
                        -- =====================================================
                        WHEN X"12" | X"59" => keys(6)(0) <= key_val; -- 'Shift' (左右対応)
                        WHEN X"14" => 
                            IF is_extended = '0' THEN keys(6)(1) <= key_val; END IF; -- 'Ctrl'
                        -- PCの 'Left Alt' ➡️ MSXの 'GRAPH' キー
                        WHEN X"11" => 
                            IF is_extended = '0' THEN keys(6)(2) <= key_val; END IF; -- 'GRAPH'
                        -- PCの '無変換' または 'Right Alt' ➡️ MSXの 'かな' キー
                        WHEN X"67" => keys(6)(3) <= key_val; -- 'かな' (日本語キー用)
                        -- PCの 'Caps Lock' ➡️ MSXの 'CAPS' キー
                        WHEN X"58" => keys(6)(4) <= key_val; -- 'CAPS'

                        -- =====================================================
                        -- 行 7 (システム・制御キー)
                        -- =====================================================
                        -- PCの '全角/半角' ➡️ MSXの 'かな' (代替手段)
                        WHEN X"0E" => keys(7)(0) <= key_val; -- 'かな' 
                        -- PCの 'Tab' ➡️ MSXの 'TAB' キー
                        WHEN X"0D" => keys(7)(3) <= key_val; -- 'TAB'
                        -- PCの 'ESC' ➡️ MSXの 'STOP' キー
                        WHEN X"76" => keys(7)(4) <= key_val; -- 'STOP'
                        -- PCの 'Backspace' ➡️ MSXの 'BS' キー
                        WHEN X"66" => keys(7)(5) <= key_val; -- 'BS'
                        -- PCの 'Select/Application' ➡️ MSXの 'SELECT' キー
                        WHEN X"2F" => 
                            IF is_extended = '1' THEN keys(7)(6) <= key_val; END IF; -- 'SELECT'
                        -- PCの 'Return/Enter' ➡️ MSXの 'RETURN' キー
                        WHEN X"5A" => 
                            IF is_extended = '0' THEN keys(7)(7) <= key_val; END IF; -- 'RETURN'

                        -- =====================================================
                        -- 行 8 (スペース & 矢印キー)
                        -- =====================================================
                        WHEN X"29" => keys(8)(0) <= key_val; -- 'Space'
                        -- PCの 'Home' ➡️ MSXの 'HOME' キー
                        WHEN X"6C" => 
                            IF is_extended = '1' THEN keys(8)(1) <= key_val; END IF; -- 'HOME'
                        -- PCの 'Delete' ➡️ MSXの 'DEL' キー
                        WHEN X"71" => 
                            IF is_extended = '1' THEN keys(8)(2) <= key_val; END IF; -- 'DEL'
                        
                        -- カーソルキー群 (PS/2拡張コード E0フラグを条件にする)
                        WHEN X"6B" => 
                            IF is_extended = '1' THEN keys(8)(4) <= key_val; END IF; -- 'Left'
                        WHEN X"75" => 
                            IF is_extended = '1' THEN keys(8)(5) <= key_val; END IF; -- 'Up'
                        WHEN X"72" => 
                            IF is_extended = '1' THEN keys(8)(6) <= key_val; END IF; -- 'Down'
                        WHEN X"74" => 
                            IF is_extended = '1' THEN keys(8)(7) <= key_val; END IF; -- 'Right'

                        -- ファンクションキー
                        -- F1..F5 は MSX の行列にも反映しつつ FN 出力も立てる
                        WHEN X"05" => 
                            keys(6)(5) <= key_val; -- F1
                            fn_reg(1)  <= fn_val;
                        WHEN X"06" => 
                            keys(6)(6) <= key_val; -- F2
                            fn_reg(2)  <= fn_val;
                        WHEN X"04" => 
                            keys(6)(7) <= key_val; -- F3
                            fn_reg(3)  <= fn_val;
                        WHEN X"0C" => 
                            keys(7)(0) <= key_val; -- F4
                            fn_reg(4)  <= fn_val;
                        WHEN X"03" => 
                            keys(7)(1) <= key_val; -- F5
                            fn_reg(5)  <= fn_val;

                        -- F6..F12 は FN 出力のみ
                        WHEN X"0B" => fn_reg(6)  <= fn_val; -- F6
                        WHEN X"83" => fn_reg(7)  <= fn_val; -- F7
                        WHEN X"0A" => fn_reg(8)  <= fn_val; -- F8
                        WHEN X"01" => fn_reg(9)  <= fn_val; -- F9
                        WHEN X"09" => fn_reg(10) <= fn_val; -- F10
                        WHEN X"78" => fn_reg(11) <= fn_val; -- F11
                        WHEN X"07" => fn_reg(12) <= fn_val; -- F12

                        -- カーソルキー
                        --WHEN X"75" => IF is_extended = '1' THEN keys(8)(5) <= key_val; END IF; -- Up
                        --WHEN X"72" => IF is_extended = '1' THEN keys(8)(6) <= key_val; END IF; -- Down
                        --WHEN X"6B" => IF is_extended = '1' THEN keys(8)(4) <= key_val; END IF; -- Left
                        --WHEN X"74" => IF is_extended = '1' THEN keys(8)(7) <= key_val; END IF; -- Right
                            
                        WHEN OTHERS => NULL;
                    END CASE;

                    is_break    <= '0';
                    is_extended <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;
    -- -------------------------------------------------------------------------
    -- 3. 【元のロジックを完全再現】 行(A)の要求に応じたデータ(DO)の出力
    -- -------------------------------------------------------------------------
    PROCESS (A, keys)
    BEGIN
        CASE A IS
            WHEN "0000" => DO <= keys(0);
            WHEN "0001" => DO <= keys(1);
            WHEN "0010" => DO <= keys(2);
            WHEN "0011" => DO <= keys(3);
            WHEN "0100" => DO <= keys(4);
            WHEN "0101" => DO <= keys(5);
            WHEN "0110" => DO <= keys(6);
            WHEN "0111" => DO <= keys(7);
            WHEN "1000" => DO <= keys(8);
            WHEN "1001" => DO <= keys(9);
            WHEN "1010" => DO <= keys(10);
            WHEN OTHERS => DO <= (OTHERS => '1');  -- nothing selected
        END CASE;
    END PROCESS;

    -- ファンクションキーの出力接続
    FN <= fn_reg;
 

END rtl;