LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

-- PS/2 (Scan Code Set 2) receiver that re-emits every key as a standard
-- USB HID usage-id bit in the same 128-bit "keyboard" vector produced by
-- hid.v for a real USB keyboard. This lets a single MSX matrix mapper
-- (usb_keyboard_msx) serve both PS/2 and USB keyboards.
--
-- Modifier keys (Ctrl/Shift/Alt/GUI) do not fit the 7-bit HID usage-id
-- range (their usage ids are 224..231), so - matching the convention
-- already used by this project's USB path (hid.v / mcu firmware) - they
-- are remapped down to 104..111 (usage_id - 120).

ENTITY ps2_hid_bridge IS
    PORT (
        CLK      : IN  STD_LOGIC;
        RESET    : IN  STD_LOGIC;

        -- HID usage-id vector, '1' = key pressed (same format as hid.v)
        keyboard : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);

        ps2_clk  : INOUT STD_LOGIC;
        ps2_data : INOUT STD_LOGIC
    );
END ps2_hid_bridge;

ARCHITECTURE rtl OF ps2_hid_bridge IS

    -- PS/2 受信バッファおよびデコーダ用信号
    -- 11-bit frame = start(0), data(1..8), parity(9), stop(10)
    SIGNAL shift_reg    : STD_LOGIC_VECTOR(10 DOWNTO 0) := (OTHERS => '0');
    SIGNAL bit_count    : INTEGER RANGE 0 TO 10 := 0;
    SIGNAL ps2_clk_sync : STD_LOGIC_VECTOR(2 DOWNTO 0) := "111";
    SIGNAL scan_code    : STD_LOGIC_VECTOR(7 DOWNTO 0) := X"00";
    SIGNAL code_ready   : STD_LOGIC := '0';

    SIGNAL is_break     : STD_LOGIC := '0';
    SIGNAL is_extended  : STD_LOGIC := '0';

    SIGNAL keyboard_reg : STD_LOGIC_VECTOR(127 DOWNTO 0) := (OTHERS => '0');

BEGIN
    -- -------------------------------------------------------------------
    -- 1. PS/2 物理信号（Clock / Data）の同期とシリアルデコード
    -- -------------------------------------------------------------------
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
                    scan_code  <= shift_reg(8 DOWNTO 1);
                    code_ready <= '1';
                    shift_reg  <= (OTHERS => '0');
                ELSE
                    bit_count <= bit_count + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- -------------------------------------------------------------------
    -- 2. PS/2 スキャンコード(Set2) から USB HID usage-id への変換
    -- -------------------------------------------------------------------
    PROCESS(CLK, RESET)
        VARIABLE hid_code : INTEGER RANGE 0 TO 127;
        VARIABLE valid     : STD_LOGIC;
    BEGIN
        IF RESET = '1' THEN
            keyboard_reg <= (OTHERS => '0');
            is_break     <= '0';
            is_extended  <= '0';
        ELSIF rising_edge(CLK) THEN
            IF code_ready = '1' THEN
                IF scan_code = X"F0" THEN
                    is_break <= '1';
                ELSIF scan_code = X"E0" THEN
                    is_extended <= '1';
                ELSE
                    valid := '1';

                    IF is_extended = '1' THEN
                        -- 拡張(E0)コード: カーソル/編集キー等
                        CASE scan_code IS
                            WHEN X"2F" => hid_code := 101; -- Application -> SELECT
                            WHEN X"6C" => hid_code := 74;  -- Home
                            WHEN X"71" => hid_code := 76;  -- Delete
                            WHEN X"6B" => hid_code := 80;  -- Left
                            WHEN X"75" => hid_code := 82;  -- Up
                            WHEN X"72" => hid_code := 81;  -- Down
                            WHEN X"74" => hid_code := 79;  -- Right
                            WHEN X"5A" => hid_code := 88;  -- Keypad Enter
                            WHEN X"4A" => hid_code := 84;  -- Keypad /
                            WHEN OTHERS => valid := '0';
                        END CASE;
                    ELSE
                        -- 非拡張コード
                        CASE scan_code IS
                            -- アルファベット
                            WHEN X"1C" => hid_code := 4;  -- A
                            WHEN X"32" => hid_code := 5;  -- B
                            WHEN X"21" => hid_code := 6;  -- C
                            WHEN X"23" => hid_code := 7;  -- D
                            WHEN X"24" => hid_code := 8;  -- E
                            WHEN X"2B" => hid_code := 9;  -- F
                            WHEN X"34" => hid_code := 10; -- G
                            WHEN X"33" => hid_code := 11; -- H
                            WHEN X"43" => hid_code := 12; -- I
                            WHEN X"3B" => hid_code := 13; -- J
                            WHEN X"42" => hid_code := 14; -- K
                            WHEN X"4B" => hid_code := 15; -- L
                            WHEN X"3A" => hid_code := 16; -- M
                            WHEN X"31" => hid_code := 17; -- N
                            WHEN X"44" => hid_code := 18; -- O
                            WHEN X"4D" => hid_code := 19; -- P
                            WHEN X"15" => hid_code := 20; -- Q
                            WHEN X"2D" => hid_code := 21; -- R
                            WHEN X"1B" => hid_code := 22; -- S
                            WHEN X"2C" => hid_code := 23; -- T
                            WHEN X"3C" => hid_code := 24; -- U
                            WHEN X"2A" => hid_code := 25; -- V
                            WHEN X"1D" => hid_code := 26; -- W
                            WHEN X"22" => hid_code := 27; -- X
                            WHEN X"35" => hid_code := 28; -- Y
                            WHEN X"1A" => hid_code := 29; -- Z

                            -- 数字キー(上段)
                            WHEN X"16" => hid_code := 30; -- 1
                            WHEN X"1E" => hid_code := 31; -- 2
                            WHEN X"26" => hid_code := 32; -- 3
                            WHEN X"25" => hid_code := 33; -- 4
                            WHEN X"2E" => hid_code := 34; -- 5
                            WHEN X"36" => hid_code := 35; -- 6
                            WHEN X"3D" => hid_code := 36; -- 7
                            WHEN X"3E" => hid_code := 37; -- 8
                            WHEN X"46" => hid_code := 38; -- 9
                            WHEN X"45" => hid_code := 39; -- 0

                            WHEN X"5A" => hid_code := 40; -- Enter
                            WHEN X"76" => hid_code := 41; -- Esc
                            WHEN X"66" => hid_code := 42; -- Backspace
                            WHEN X"0D" => hid_code := 43; -- Tab
                            WHEN X"29" => hid_code := 44; -- Space

                            WHEN X"4E" => hid_code := 45; -- -
                            WHEN X"55" => hid_code := 46; -- =
                            WHEN X"54" => hid_code := 47; -- [
                            WHEN X"5B" => hid_code := 48; -- ]
                            WHEN X"5D" => hid_code := 49; -- \
                            WHEN X"4C" => hid_code := 51; -- ;
                            WHEN X"52" => hid_code := 52; -- '
                            WHEN X"41" => hid_code := 54; -- ,
                            WHEN X"49" => hid_code := 55; -- .
                            WHEN X"4A" => hid_code := 56; -- /
                            WHEN X"58" => hid_code := 57; -- CapsLock

                            -- ファンクションキー
                            WHEN X"05" => hid_code := 58; -- F1
                            WHEN X"06" => hid_code := 59; -- F2
                            WHEN X"04" => hid_code := 60; -- F3
                            WHEN X"0C" => hid_code := 61; -- F4
                            WHEN X"03" => hid_code := 62; -- F5
                            WHEN X"0B" => hid_code := 63; -- F6
                            WHEN X"83" => hid_code := 64; -- F7
                            WHEN X"0A" => hid_code := 65; -- F8
                            WHEN X"01" => hid_code := 66; -- F9
                            WHEN X"09" => hid_code := 67; -- F10
                            WHEN X"78" => hid_code := 68; -- F11
                            WHEN X"07" => hid_code := 69; -- F12

                            -- テンキー
                            WHEN X"77" => hid_code := 83; -- NumLock
                            WHEN X"7C" => hid_code := 85; -- KP *
                            WHEN X"7B" => hid_code := 86; -- KP -
                            WHEN X"79" => hid_code := 87; -- KP +
                            WHEN X"69" => hid_code := 89; -- KP 1
                            WHEN X"72" => hid_code := 90; -- KP 2
                            WHEN X"7A" => hid_code := 91; -- KP 3
                            WHEN X"6B" => hid_code := 92; -- KP 4
                            WHEN X"73" => hid_code := 93; -- KP 5
                            WHEN X"74" => hid_code := 94; -- KP 6
                            WHEN X"6C" => hid_code := 95; -- KP 7
                            WHEN X"75" => hid_code := 96; -- KP 8
                            WHEN X"7D" => hid_code := 97; -- KP 9
                            WHEN X"70" => hid_code := 98; -- KP 0
                            WHEN X"71" => hid_code := 99; -- KP .

                            -- Non-US \| (JIS配列の '_'/ろ キー)
                            WHEN X"51" => hid_code := 100;

                            -- 日本語配列特殊キー
                            -- 標準HID usage id(135..140)は127bitのkeyboardベクタに収まらないため、
                            -- 修飾キーと同様に空き番地(112..)へ詰め替える project-local な拡張コード。
                            WHEN X"67" => hid_code := 112; -- 無変換 -> かな
                            WHEN X"0E" => hid_code := 113; -- 全角/半角 -> かな(代替)

                            -- 修飾キー (usage_id - 120 に詰め替え)
                            WHEN X"14" => hid_code := 104; -- Left Ctrl
                            WHEN X"12" => hid_code := 105; -- Left Shift
                            WHEN X"11" => hid_code := 106; -- Left Alt -> GRAPH
                            WHEN X"59" => hid_code := 109; -- Right Shift

                            WHEN OTHERS => valid := '0';
                        END CASE;
                    END IF;

                    IF valid = '1' THEN
                        keyboard_reg(hid_code) <= NOT is_break;
                    END IF;

                    is_break    <= '0';
                    is_extended <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    keyboard <= keyboard_reg;

END rtl;
