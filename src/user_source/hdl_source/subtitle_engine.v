`timescale 1ns/1ps

module subtitle_engine #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter [11:0] X_SUB_TOP = 12'd320, Y_SUB_TOP = 12'd0,
                     X_SUB_BOT = 12'd320, Y_SUB_BOT = 12'd656,
                     X_SUB_BR  = 12'd620, Y_SUB_BR  = 12'd656,
                     W_SUB     = 12'd640, H_SUB     = 12'd64,
                     W_SUB_BR  = 12'd660,

    // 字符几何

    parameter CH_W_S = 8,  CH_H_S = 16, CH_PITCH_S = 10,   // 小：8×16 + 2 间隙
    parameter CH_W_M = 16, CH_H_M = 32, CH_PITCH_M = 20,   // 中：2× 放大
    parameter MAX_COLS = 64,          // 单行最多字符（= 640/10）
    parameter IN_STAGE_CYCLES = 4,    // 一句上屏后的过渡拍数（换句时短暂清屏）

    // 时间基

    parameter SAMPLES_PER_FRAME = 792,   // 黄金常数（48kHz / 60.606fps）

    parameter TYPE_RATE  = 1,
    parameter TYPE_SHIFT = 2,

    // 配色

    parameter [23:0] C_TXT      = 24'hFFFFFF,   // 当前句（白）
    parameter [23:0] C_TXT_DIM  = 24'h808080,   // 另一句（灰，仅滚动模式）
    parameter [23:0] C_BG_BAR   = 24'h000000,   // 背景=实底：黑条
    parameter [23:0] C_BG_HALF  = 24'h000000    // 非实底时的填充内容（见 §3.5）
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire [31:0] I_sample_cnt,

    input  wire        I_sub_on,       // 字幕总开关
    input  wire [1:0]  I_mode,         // 0=滚动 1=淡入 2=打字
    input  wire [1:0]  I_pos,          // 0=底部 1=顶部 2=右下
    input  wire [1:0]  I_bg,           // 0=无 1=半透黑 2=实底黑条
    input  wire        I_size,        // 0=小(8x16) 1=中(16x32，2× 放大)
    input  wire        I_preview,

    input  wire        I_loop_pulse,   // 1 = 歌曲回到开头（video_clk 域，单拍）
    input  wire [23:0] I_loop_frame,   // 音频总帧数（兜底：帧号超过它就归零）

    // 字幕数据 ROM
    output reg  [9:0]  O_cue_idx,
    input  wire [23:0] I_cue_frame,    // 该句起始帧号（同步读）
    input  wire [15:0] I_cue_coff,
    input  wire [15:0] I_cue_len,
    output wire [15:0] O_char_addr,
    input  wire [7:0]  I_char_code,    // 字符码（同步读）

    // 字库

    output wire [23:0] O_frame_now,

    output wire [7:0]  O_font_code,
    output wire [3:0]  O_font_row,
    input  wire [15:0] I_font_row,     // 行位图（同步读）

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam [9:0] SPF = SAMPLES_PER_FRAME[9:0];   // 792

    reg [31:0] samp_d;
    wire       frame_inc = (I_sample_cnt != samp_d);

    reg [9:0]  acc;        // 帧内样本偏移 0..791
    reg [23:0] frame_q;    // 帧号（寄存）

    wire song_restart = I_loop_pulse | (frame_q > I_loop_frame);
    wire frame_clr    = song_restart;          // 归零 从头播字幕

    wire [23:0] frame_now  = frame_q;                            // 供 使用
    wire        frame_tick = frame_inc & (acc == SPF - 10'd1);   // 进帧脉冲

    localparam [23:0] CUE_SENTINEL = 24'h00FFFF;

    localparam [1:0] S_IDLE = 2'd0, S_WAIT = 2'd1, S_CMP = 2'd2;
    reg [1:0]  st;

    reg [23:0] cur_frame;      // 当前句起始帧
    reg [15:0] cur_coff;
    reg [15:0] cur_len;
    reg        cue_valid;      // 当前句有效（已到起始帧，且非哨兵）

    reg [15:0] nxt2_coff;
    reg [15:0] nxt2_len;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            samp_d    <= 32'd0;
            acc       <= 10'd0;
            frame_q   <= 24'd0;
            st        <= S_IDLE;
            O_cue_idx <= 10'd0;
            cur_frame <= 24'd0;
            cur_coff  <= 16'd0;
            cur_len   <= 16'd0;
            nxt2_coff <= 16'd0;
            nxt2_len  <= 16'd0;
            cue_valid <= 1'b0;
        end else begin
            samp_d <= I_sample_cnt;

            if (frame_clr) begin

                acc     <= 10'd0;
                frame_q <= 24'd0;
            end else if (frame_inc) begin
                if (acc == SPF - 10'd1) begin
                    acc     <= 10'd0;
                    frame_q <= frame_q + 24'd1;
                end else begin
                    acc <= acc + 10'd1;
                end
            end

            case (st)

                S_IDLE: if (frame_tick | frame_clr) begin

                    O_cue_idx <= 10'd0;
                    st        <= S_WAIT;
                end

                S_WAIT: st <= S_CMP;               // 等地址/数据各打 1 拍

                S_CMP: begin
                    if (I_cue_frame == CUE_SENTINEL) begin

                        cue_valid <= (O_cue_idx != 10'd0) &&
                                     (frame_now >= cur_frame);
                        nxt2_coff <= 16'd0;        // 没有下一句 第 2 行不画
                        nxt2_len  <= 16'd0;
                        st        <= S_IDLE;
                    end else if (frame_now < I_cue_frame) begin

                        cue_valid <= (O_cue_idx != 10'd0);
                        nxt2_coff <= I_cue_coff;
                        nxt2_len  <= I_cue_len;
                        st        <= S_IDLE;
                    end else begin

                        cur_frame <= I_cue_frame;
                        cur_coff  <= I_cue_coff;
                        cur_len   <= I_cue_len;
                        O_cue_idx <= O_cue_idx + 10'd1;
                        st        <= S_WAIT;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

    wire        mid = I_size;                         // 中字号标志

    function [11:0] centre_off;
        input [15:0] len;
        input        is_mid;
        begin
            if (is_mid)
                centre_off = (len > 16'd20) ? 12'd0
                                            : (12'd320 - {len[11:0], 4'b0000});
            else
                centre_off = (len > 16'd40) ? 12'd0
                                            : (12'd320 - {len[11:0], 3'b000});
        end
    endfunction

    reg [11:0] start_x0, start_x1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            start_x0 <= 12'd0;
            start_x1 <= 12'd0;
        end else begin
            start_x0 <= centre_off(cur_len,  mid);
            start_x1 <= centre_off(nxt2_len, mid);
        end
    end

    wire [11:0] reg_x0 = (I_pos == 2'd0) ? X_SUB_BOT :
                         (I_pos == 2'd1) ? X_SUB_TOP : X_SUB_BR;
    wire [11:0] reg_y0 = (I_pos == 2'd0) ? Y_SUB_BOT :
                         (I_pos == 2'd1) ? Y_SUB_TOP : Y_SUB_BR;
    wire [11:0] reg_w  = (I_pos == 2'd2) ? W_SUB_BR  : W_SUB;
    wire [11:0] reg_x1 = reg_x0 + reg_w;
    wire [11:0] reg_y1 = reg_y0 + H_SUB;

    reg [11:0] reg_x0_d, reg_y0_d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            reg_x0_d <= X_SUB_BOT;
            reg_y0_d <= Y_SUB_BOT;
        end else begin
            reg_x0_d <= reg_x0;
            reg_y0_d <= reg_y0;
        end
    end

    wire [5:0]  ch_h  = mid ? 6'd32 : 6'd16;
    wire sub_en = (I_sub_on | I_preview) & cue_valid;

    wire [11:0] x_now, y_now;

    wire in_band_now = (x_now >= reg_x0) && (x_now < reg_x1) &&
                       (y_now >= reg_y0) && (y_now < reg_y1);

    reg        de_d1, hs_d1, vs_d1;
    reg [23:0] rgb_d1;
    reg [11:0] ox_d1, oy_d1;      // 带内偏移（减法已提前到本级，见 ）
    reg        inband_d1, en_d1;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d1 <= 1'b0; hs_d1 <= 1'b0; vs_d1 <= 1'b0; rgb_d1 <= 24'd0;
            ox_d1 <= 12'd0; oy_d1 <= 12'd0;
            inband_d1 <= 1'b0; en_d1 <= 1'b0;
        end else begin
            de_d1 <= I_de; hs_d1 <= I_hs; vs_d1 <= I_vs; rgb_d1 <= I_rgb;

            ox_d1 <= x_now - reg_x0;
            oy_d1 <= y_now - reg_y0;
            inband_d1 <= in_band_now;
            en_d1     <= sub_en;
        end
    end

    osd_position #(
        .H_ACTIVE (H_ACTIVE),
        .V_ACTIVE (V_ACTIVE)
    ) u_pos (
        .clk     (I_clk),
        .rst     (I_rst),
        .de      (I_de),
        .vs      (I_vs),
        .x       (x_now),
        .y       (y_now),
        .pos_vld (        )
    );

    wire [11:0] ox = ox_d1;
    wire [11:0] oy = oy_d1;

    wire in_l0 = (oy < ch_h);
    wire in_l1 = (oy >= ch_h) && (oy < {ch_h, 1'b0});   // ch_h*2 = {ch_h,1'b0}
    wire use_l1 = (I_mode == 2'd0) & in_l1;             // 仅滚动模式有第 2 行

    wire line1 = use_l1;
    wire [15:0] row_coff = line1 ? nxt2_coff : cur_coff;
    wire [15:0] row_len  = line1 ? nxt2_len  : cur_len;

    wire row1_ok = (row_len != 16'd0) && (row_coff != 16'd0);

    wire [11:0] row_sx = line1 ? start_x1 : start_x0;

    wire [11:0] oxn = (ox >= row_sx) ? (ox - row_sx) : 12'd0;

    wire [20:0] row_w = mid ? {row_len, 5'b00000}      // ×32
                           : {{1'b0, row_len}, 4'b0000}; // ×16
    wire        in_row = (ox >= row_sx) & ({9'd0, oxn} < row_w);

    wire [11:0] col0 = mid ? (oxn >> 5) : (oxn >> 4);

    wire [3:0] gx = mid ? oxn[4:1] : oxn[3:0];

    wire [3:0] gy = mid ? oy[4:1] : oy[3:0];

    wire        typed_mode = (I_mode == 2'd2);

    wire [23:0] in_sent = (frame_now >= cur_frame) ? (frame_now - cur_frame)
                                                  : 24'd0;

    wire [15:0] reveal_now = in_sent[18:3];

    wire       reveal_ok  = (~typed_mode) | use_l1 | (col0 < reveal_now);

    wire in_txt = in_l0 | use_l1;

    wire col_ok  = (col0 < row_len) & (use_l1 ? row1_ok : 1'b1) & in_row
                   & reveal_ok;

    assign O_char_addr = row_coff + {4'b0000, col0};

    assign O_font_code = I_char_code;   // 码值（S2 有效） 字库地址高位
    assign O_font_row  = gy_d2;         // 行号（S2） 字库地址低位

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        intxt_d2, l1_d2, en_d2, ok_d2;
    reg [3:0]  gx_d2;
    reg [3:0]  gy_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            intxt_d2 <= 1'b0; l1_d2 <= 1'b0; en_d2 <= 1'b0; ok_d2 <= 1'b0;
            gx_d2 <= 4'd0; gy_d2 <= 4'd0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1; rgb_d2 <= rgb_d1;
            intxt_d2 <= inband_d1 & in_txt;
            l1_d2    <= use_l1;
            en_d2    <= en_d1;
            ok_d2    <= col_ok & in_txt;
            gx_d2    <= gx;
            gy_d2    <= gy;                 // 与 S2 的码值一起给字库地址
        end
    end

    // D4: 取位 + 合成

    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        intxt_d3, l1_d3, en_d3, ok_d3;
    reg [3:0]  gx_d3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            intxt_d3 <= 1'b0; l1_d3 <= 1'b0; en_d3 <= 1'b0; ok_d3 <= 1'b0;
            gx_d3 <= 4'd0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            intxt_d3 <= intxt_d2;
            l1_d3    <= l1_d2;
            en_d3    <= en_d2;
            ok_d3    <= ok_d2;
            gx_d3    <= gx_d2;              // 与 I_font_row 同步到 D3
        end
    end

    wire [3:0] bit_sel = 4'd15 - gx_d3;
    wire       pix_bit = I_font_row[bit_sel];

    wire [15:0] b60_r = {1'd0, rgb_d3[23:16], 7'd0} + {4'd0, rgb_d3[23:16], 4'd0}
                      + {5'd0, rgb_d3[23:16], 3'd0} + {7'd0, rgb_d3[23:16], 1'd0};
    wire [15:0] b60_g = {1'd0, rgb_d3[15:8],  7'd0} + {4'd0, rgb_d3[15:8],  4'd0}
                      + {5'd0, rgb_d3[15:8],  3'd0} + {7'd0, rgb_d3[15:8],  1'd0};
    wire [15:0] b60_b = {1'd0, rgb_d3[7:0],   7'd0} + {4'd0, rgb_d3[7:0],   4'd0}
                      + {5'd0, rgb_d3[7:0],   3'd0} + {7'd0, rgb_d3[7:0],   1'd0};
    wire [23:0] bg_mix = {b60_r[15:8], b60_g[15:8], b60_b[15:8]};
    wire [23:0] bg_col = (I_bg == 2'd2) ? C_BG_BAR : bg_mix;
    wire        bg_on  = (I_bg != 2'd0) & intxt_d3;

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;                          // 默认：背景图
        if (en_d3) begin
            if (bg_on) comp = bg_col;           // 字幕带背景
            if (ok_d3 && pix_bit)               // 文字
                comp = l1_d3 ? C_TXT_DIM : C_TXT;
        end
    end

    reg        o_de, o_hs, o_vs;
    reg [23:0] o_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            o_de <= 1'b0; o_hs <= 1'b0; o_vs <= 1'b0; o_rgb <= 24'd0;
        end else begin
            o_de <= de_d3; o_hs <= hs_d3; o_vs <= vs_d3; o_rgb <= comp;
        end
    end

    assign O_de  = o_de;
    assign O_hs  = o_hs;
    assign O_vs  = o_vs;
    assign O_rgb = o_rgb;

    assign O_frame_now = frame_q;

endmodule
