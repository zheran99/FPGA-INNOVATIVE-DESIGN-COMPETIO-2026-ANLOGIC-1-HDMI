`timescale 1ns / 1ps

module seg_status #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BLINK_HZ    = 4              // 闪烁频率
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 mode_decode
    input  wire [2:0]  I_mode_num,         // 0..7（内部 +1 显示为 1..8）

    // 来自 param_reg
    input  wire [2:0]  I_param_item,       // 0..5
    input  wire [15:0] I_param_val,

    input  wire [2:0]  I_tran_type,
    input  wire        I_tran_en,

    input  wire        I_auto_on,          // P2 轮播开关状态
    input  wire [4:0]  I_img_idx,

    input  wire        I_sd_warn,
    input  wire [4:0]  I_sd_found,

    input  wire [2:0]  I_aud_stat,
    input  wire        I_aud_mute,

    input  wire [2:0]  I_fsm_sel,
    input  wire [3:0]  I_aud_fsm,
    input  wire [3:0]  I_vid_fsm,
    input  wire [3:0]  I_load_cnt,       // 累计整图加载次数（低 4 位）
    input  wire [3:0]  I_sdram_flags,    // SDRAM 冲突锁存位 {C3,C2,-,C0}

 input  wire [3:0]  I_wr_diag,
 input  wire [3:0]  I_fifo_flags,

 input  wire [7:0]  I_uart_rx_cnt,
 input  wire [7:0]  I_uart_tx_cnt,

 input  wire [2:0]  I_ctrl_diag,
    output reg  [7:0]  O_seg_5,
    output reg  [7:0]  O_seg_4,
    output reg  [7:0]  O_seg_3,
    output reg  [7:0]  O_seg_2,
    output reg  [7:0]  O_seg_1,
    output reg  [7:0]  O_seg_0
);

    localparam [7:0] CH_BLANK = 8'hFF;   // 全灭
    localparam [7:0] CH_DASH  = 8'hBF;   // '-' (g 亮)
    localparam [7:0] CH_P     = 8'h8C;   // 'P'
    localparam [7:0] CH_B     = 8'h83;   // 'B'
    localparam [7:0] CH_S     = 8'h92;   // 'S' (与 5 同形，可接受)
    localparam [7:0] CH_r     = 8'hAF;   // 'r'
    localparam [7:0] CH_t     = 8'h8F;   // 't'
    localparam [7:0] CH_O     = 8'hC0;   // 'O'（用于 OFF）
    localparam [7:0] CH_E     = 8'h86;   // 'E' SD 诊断：常量填错
    localparam [7:0] CH_n     = 8'hAB;   // 'n' SD 诊断：未找到（备用）
    localparam [7:0] CH_u     = 8'hC1;   // 'u' 音频诊断：FIFO 欠载
    localparam [7:0] CH_PAUSE = 8'h8C;   // 'P' 音频诊断：被静音开关关闭
    localparam [7:0] CH_F     = 8'h8E;   // 'F' 音频诊断：没找到 WAV

    localparam [7:0] CH_L     = 8'hC7;   // 'L' 加载在途（卡住时恒亮）
    localparam [7:0] CH_C     = 8'hC6;

    function [7:0] num_char;
        input [3:0] d;
        begin
            case (d)
                4'd0: num_char = 8'hC0;   // 100_0000
                4'd1: num_char = 8'hF9;   // 111_1001
                4'd2: num_char = 8'hA4;   // 010_0100
                4'd3: num_char = 8'hB0;   // 011_0000
                4'd4: num_char = 8'h99;   // 001_1001
                4'd5: num_char = 8'h92;   // 001_0010
                4'd6: num_char = 8'h82;   // 000_0010
                4'd7: num_char = 8'hF8;   // 111_1000
                4'd8: num_char = 8'h80;   // 000_0000
                4'd9: num_char = 8'h90;   // 001_0000
                default: num_char = CH_BLANK;
            endcase
        end
    endfunction

    function [7:0] CH_hexA_to_F;
        input [3:0] d;
        begin
            case (d)
                4'd10: CH_hexA_to_F = 8'h88;   // 'A'
                4'd11: CH_hexA_to_F = 8'h83;   // 'b'
                4'd12: CH_hexA_to_F = 8'hC6;   // 'C'
                4'd13: CH_hexA_to_F = 8'hA1;   // 'd'
                4'd14: CH_hexA_to_F = 8'h86;   // 'E'
                4'd15: CH_hexA_to_F = 8'h8E;   // 'F'
                default: CH_hexA_to_F = CH_BLANK;
            endcase
        end
    endfunction

    reg [7:0] ch5, ch4, ch3, ch2, ch1, ch0;

    function [7:0] hex_char;
        input [3:0] d;
        begin
            hex_char = (d < 4'd10) ? num_char(d) : CH_hexA_to_F(d);
        end
    endfunction

    reg        sd_bad;
    reg [3:0]  sd_f_ten, sd_f_one;

    wire [3:0] item_disp = {1'b0, I_param_item} + 4'd1;

    wire [7:0] val8      = I_param_val[7:0];
    wire       val_ge100 = (val8 >= 8'd100);
    wire [7:0] val_sub   = val_ge100 ? (val8 - 8'd100) : val8;
    wire [3:0] v_hund    = val_ge100 ? 4'd1 : 4'd0;
    wire [3:0] v_ten     = val_sub / 8'd10;
    wire [3:0] v_one     = val_sub % 8'd10;

    wire [4:0] img_disp = I_img_idx;
    wire [3:0] img_ten  = (img_disp >= 5'd10) ? 4'd1 : 4'd0;   // 只有 10..16 有十位
    wire [3:0] img_one  = img_disp - (img_ten * 4'd10);        // 个位

    wire       img_2dig = (img_disp >= 5'd10);

    always @(*) begin
        ch5 = num_char({1'b0, I_mode_num} + 4'd1);

        if (I_fsm_sel == 2'd1)
            ch4 = num_char(I_aud_fsm);
        else if (I_fsm_sel == 2'd2)
            ch4 = num_char(I_vid_fsm);
        else if (I_fsm_sel == 2'd3)
            ch4 = (I_load_cnt < 4'd10) ? num_char(I_load_cnt)
                                       : CH_hexA_to_F(I_load_cnt);
        else if (I_fsm_sel == 3'd4)
            ch4 = (I_sdram_flags < 4'd10) ? num_char(I_sdram_flags)
                                          : CH_hexA_to_F(I_sdram_flags);

        else if (I_fsm_sel == 3'd5)
            ch4 = (I_fifo_flags < 4'd10) ? num_char(I_fifo_flags)
                                         : CH_hexA_to_F(I_fifo_flags);

        else if (I_fsm_sel == 3'd6)
            ch4 = (I_wr_diag < 4'd10) ? num_char(I_wr_diag)
                                      : CH_hexA_to_F(I_wr_diag);
        else
            ch4 = I_aud_mute           ? CH_PAUSE :
                  (I_aud_stat == 3'd4) ? CH_F     :
                  (I_aud_stat == 3'd3) ? CH_u     :
                  num_char({1'b0, I_aud_stat[1:0]});

        case (I_mode_num)

        3'd0: begin                       // P1 关闭
            ch3 = CH_DASH;  ch2 = CH_BLANK;  ch1 = CH_DASH;  ch0 = CH_BLANK;
        end

        3'd1: begin                       // P2 纯净显示
            ch3 = I_auto_on ? CH_P : CH_DASH;      // P=轮播中 / -=停止

            ch2 = I_ctrl_diag[2] ? CH_L :
                  (!I_ctrl_diag[1]) ? CH_C :
                  I_ctrl_diag[0] ? CH_t : CH_BLANK;

            ch1 = img_2dig ? num_char(img_ten) : num_char(img_one);
            ch0 = img_2dig ? num_char(img_one) : CH_BLANK;
        end

        3'd2: begin
            ch3 = num_char({1'b0, I_tran_type} + 4'd1);
            ch2 = CH_BLANK;
            ch1 = I_tran_en ? num_char(4'd1) : num_char(4'd0);
            ch0 = CH_BLANK;
        end

        3'd3: begin
            ch3 = num_char(item_disp);             // 参数项 1..6
            ch2 = val_ge100 ? num_char(v_hund) : CH_BLANK;
            ch1 = num_char(v_ten);
            ch0 = num_char(v_one);
        end

        3'd4: begin                       // P5 字幕设置
            ch3 = num_char(4'd1);   ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd5: begin                       // P6 Logo 设置
            ch3 = CH_B;             ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd6: begin                       // P7 音频可视化
            ch3 = num_char(4'd1);   ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd7: begin                       // P8 串口调试

            ch3 = hex_char(I_uart_rx_cnt[7:4]);
            ch2 = hex_char(I_uart_rx_cnt[3:0]);
            ch1 = hex_char(I_uart_tx_cnt[7:4]);
            ch0 = hex_char(I_uart_tx_cnt[3:0]);
        end

        default: begin
            ch3 = CH_DASH;  ch2 = CH_BLANK;  ch1 = CH_DASH;  ch0 = CH_BLANK;
        end
        endcase

        sd_bad = (I_sd_found == 5'd0) || I_sd_warn;

        sd_f_ten = (I_sd_found >= 5'd10) ? 4'd1 : 4'd0;
        sd_f_one = (I_sd_found >= 5'd10) ? (I_sd_found[3:0] - 4'd10)
                                         : I_sd_found[3:0];

        if (sd_bad && (I_mode_num == 3'd0 || I_mode_num == 3'd1)) begin
            ch3 = I_sd_warn ? CH_E : CH_S;   // 'E'=常量填错 / 'S'=SD 标志

            ch2 = num_char(I_vid_fsm);
            ch1 = num_char(sd_f_ten);        // 十位
            ch0 = num_char(sd_f_one);        // 个位
        end
    end

    localparam HALF_MAX = CLK_FREQ_HZ / (BLINK_HZ * 2);   // 125ms
    localparam HP_W = $clog2(HALF_MAX + 1);

    reg [HP_W-1:0] half_cnt;
    reg            blink_phase;        // 1 = 灭相

    reg [1:0] blink_cnt [5:0];         // 每位剩余闪烁次数
    reg [7:0] ch_last  [5:0];          // 每位上次的字符

    // 把合成字符装进数组便于循环
    wire [7:0] ch_now [5:0];
    assign ch_now[5] = ch5;
    assign ch_now[4] = ch4;
    assign ch_now[3] = ch3;
    assign ch_now[2] = ch2;
    assign ch_now[1] = ch1;
    assign ch_now[0] = ch0;

    integer j;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            half_cnt    <= {HP_W{1'b0}};
            blink_phase <= 1'b0;
            for (j = 0; j < 6; j = j + 1) begin
                blink_cnt[j] <= 2'd0;
                ch_last[j]   <= CH_BLANK;
            end
        end
        else begin

            if (half_cnt >= HALF_MAX[HP_W-1:0]) begin
                half_cnt <= {HP_W{1'b0}};
                if (blink_phase) begin
                    for (j = 0; j < 6; j = j + 1)
                        if (blink_cnt[j] != 2'd0)
                            blink_cnt[j] <= blink_cnt[j] - 1'b1;
                end
                blink_phase <= ~blink_phase;
            end
            else begin
                half_cnt <= half_cnt + 1'b1;
            end

            for (j = 0; j < 6; j = j + 1) begin
                if (ch_now[j] != ch_last[j]) begin
                    ch_last[j]   <= ch_now[j];
                    if ((j == 1) && (I_mode_num == 3'd1) && I_auto_on)
                        blink_cnt[j] <= 2'd0;
                    else
                        blink_cnt[j] <= 2'd3;    // 其余情况：闪 3 次
                end
            end
        end
    end

    wire [5:0] blank_mask = {
        (blink_cnt[5] != 2'd0) && blink_phase,
        (blink_cnt[4] != 2'd0) && blink_phase,
        (blink_cnt[3] != 2'd0) && blink_phase,
        (blink_cnt[2] != 2'd0) && blink_phase,
        (blink_cnt[1] != 2'd0) && blink_phase,
        (blink_cnt[0] != 2'd0) && blink_phase
    };

    always @(*) begin
        O_seg_5 = blank_mask[5] ? CH_BLANK : ch5;
        O_seg_4 = blank_mask[4] ? CH_BLANK : ch4;
        O_seg_3 = blank_mask[3] ? CH_BLANK : ch3;
        O_seg_2 = blank_mask[2] ? CH_BLANK : ch2;
        O_seg_1 = blank_mask[1] ? CH_BLANK : ch1;
        O_seg_0 = blank_mask[0] ? CH_BLANK : ch0;
    end

endmodule
