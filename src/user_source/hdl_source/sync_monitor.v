`timescale 1ns/1ps

module sync_monitor #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    // 几何
    parameter X0   = 16,      // 面板左起（靠左，留 16px 边距）
    parameter Y0   = 8,       // 面板上起（靠上，留 8px 边距）
    parameter COLS = 20,      // 列数
    parameter ROWS = 7,       // 行数
    parameter CW   = 8,       // 字符格宽（= 字形宽，1:1）
    parameter ROWH = 16,      // 字符格高（= 字形高，1:1）
    parameter TB   = 1,       // 边框厚度（小面板 1px 即可）

    // 配色
    parameter [23:0] C_BORD = 24'h40C0FF,   // 青边框
                     C_FILL = 24'h001018,   // 近黑填充
                     C_TXT  = 24'hFFFFFF    // 白字
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_en,           // 1 = 显示（P5 或 P8 且"监视"=开）

    input  wire [23:0] I_frame,
    input  wire [31:0] I_sample_cnt,   // 音频样本计数
    input  wire [7:0]  I_aud_fsm,      // wav_read 主状态机号
    input  wire        I_aud_undr,     // 1 = FIFO 欠载
    input  wire [7:0]  I_vid_fsm,      // 视频状态机号
    input  wire [3:0]  I_img_idx,      // 当前图片序号
    input  wire [7:0]  I_mode_num,     // 当前模式号
    input  wire [2:0]  I_item,         // P5 当前设置项

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam X_END = X0 + COLS * CW;     // 480 + 320 = 800
    localparam Y_END = Y0 + ROWS * ROWH;   // 248 + 224 = 472

    wire [11:0] x_now, y_now;
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

    wire inpanel_now = (x_now >= X0[11:0]) && (x_now < X_END[11:0]) &&
                       (y_now >= Y0[11:0]) && (y_now < Y_END[11:0]);

    reg        de_d1, hs_d1, vs_d1;
    reg [23:0] rgb_d1;
    reg [11:0] px_d1, py_d1;
    reg        inpanel_d1;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d1 <= 1'b0; hs_d1 <= 1'b0; vs_d1 <= 1'b0; rgb_d1 <= 24'd0;
            px_d1 <= 12'd0; py_d1 <= 12'd0; inpanel_d1 <= 1'b0;
        end else begin
            de_d1 <= I_de; hs_d1 <= I_hs; vs_d1 <= I_vs; rgb_d1 <= I_rgb;
            px_d1 <= x_now - X0[11:0];
            py_d1 <= y_now - Y0[11:0];
            inpanel_d1 <= inpanel_now;
        end
    end

    wire [4:0] col = px_d1[7:3];     // 0..19（160/8 = 20 5 位）
    wire [2:0] row = py_d1[8:4];     // 0..6 （112/16 = 7 3 位）

    wire [2:0] gx = px_d1[2:0];      // 0..7
    wire [3:0] gy = py_d1[3:0];      // 0..15

    wire bord = (px_d1 < TB[11:0]) || (px_d1 >= (COLS * CW - TB)) ||
                (py_d1 < TB[11:0]) || (py_d1 >= (ROWS * ROWH - TB));

    reg [23:0] fr_prev;
    wire fr_up  = (I_frame > fr_prev);     // 正常前进（每帧 +1）
    wire fr_clr = (I_frame < fr_prev);     // 歌曲循环 帧号归零

    reg [3:0] f0, f1, f2, f3, f4, f5, f6;

    reg [13:0] frac;                       // 0..9999
    reg [3:0] s0, s1, s2, s3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            fr_prev <= 24'd0;
            {f6, f5, f4, f3, f2, f1, f0} <= 28'd0;
            frac <= 14'd0;
            {s3, s2, s1, s0} <= 16'd0;
        end else begin
            fr_prev <= I_frame;

            if (fr_clr) begin

                {f6, f5, f4, f3, f2, f1, f0} <= 28'd0;
                frac <= 14'd0;
                {s3, s2, s1, s0} <= 16'd0;
            end else if (fr_up) begin

                if (f0 != 4'd9) f0 <= f0 + 4'd1;
                else begin
                    f0 <= 4'd0;
                    if (f1 != 4'd9) f1 <= f1 + 4'd1;
                    else begin
                        f1 <= 4'd0;
                        if (f2 != 4'd9) f2 <= f2 + 4'd1;
                        else begin
                            f2 <= 4'd0;
                            if (f3 != 4'd9) f3 <= f3 + 4'd1;
                            else begin
                                f3 <= 4'd0;
                                if (f4 != 4'd9) f4 <= f4 + 4'd1;
                                else begin
                                    f4 <= 4'd0;
                                    if (f5 != 4'd9) f5 <= f5 + 4'd1;
                                    else begin
                                        f5 <= 4'd0;
                                        f6 <= (f6 == 4'd9) ? 4'd9 : f6 + 4'd1;
                                    end
                                end
                            end
                        end
                    end
                end

                if ((frac + 14'd165) >= 14'd10000) begin
                    frac <= frac + 14'd165 - 14'd10000;
                    if (s0 != 4'd9) s0 <= s0 + 4'd1;
                    else begin
                        s0 <= 4'd0;
                        if (s1 != 4'd9) s1 <= s1 + 4'd1;
                        else begin
                            s1 <= 4'd0;
                            if (s2 != 4'd9) s2 <= s2 + 4'd1;
                            else begin
                                s2 <= 4'd0;
                                s3 <= (s3 == 4'd9) ? 4'd9 : s3 + 4'd1;
                            end
                        end
                    end
                end else begin
                    frac <= frac + 14'd165;
                end
            end
        end
    end

    function [7:0] dec; input [3:0] d;
        begin dec = 8'h30 + {4'd0, d}; end
    endfunction

    function [7:0] hexd; input [3:0] d;
        begin hexd = (d < 4'd10) ? (8'h30 + {4'd0, d})
                                 : (8'h41 + {4'd0, d} - 8'd10);
        end
    endfunction

    reg [7:0] ch_c;
    always @(*) begin
        ch_c = 8'h20;
        case (row)
        3'd0: begin
            if      (col == 5'd0)  ch_c = "S";
            else if (col == 5'd1)  ch_c = "Y";
            else if (col == 5'd2)  ch_c = "N";
            else if (col == 5'd3)  ch_c = "C";
            else if (col == 5'd5)  ch_c = "M";
            else if (col == 5'd6)  ch_c = "O";
            else if (col == 5'd7)  ch_c = "N";
            else if (col == 5'd8)  ch_c = "I";
            else if (col == 5'd9)  ch_c = "T";
            else if (col == 5'd10) ch_c = "O";
            else if (col == 5'd11) ch_c = "R";
        end

        3'd1: begin
            if      (col == 5'd0)  ch_c = "F";
            else if (col == 5'd1)  ch_c = "R";
            else if (col == 5'd2)  ch_c = "A";
            else if (col == 5'd3)  ch_c = "M";
            else if (col == 5'd4)  ch_c = "E";
            else if (col == 5'd6)  ch_c = dec(f6);
            else if (col == 5'd7)  ch_c = dec(f5);
            else if (col == 5'd8)  ch_c = dec(f4);
            else if (col == 5'd9)  ch_c = dec(f3);
            else if (col == 5'd10) ch_c = dec(f2);
            else if (col == 5'd11) ch_c = dec(f1);
            else if (col == 5'd12) ch_c = dec(f0);
        end

        3'd2: begin
            if      (col == 5'd0)  ch_c = "S";
            else if (col == 5'd1)  ch_c = "A";
            else if (col == 5'd2)  ch_c = "M";
            else if (col == 5'd3)  ch_c = "P";
            else if (col == 5'd5)  ch_c = "h";
            else if (col == 5'd7)  ch_c = hexd(I_sample_cnt[23:20]);
            else if (col == 5'd8)  ch_c = hexd(I_sample_cnt[19:16]);
            else if (col == 5'd9)  ch_c = hexd(I_sample_cnt[15:12]);
            else if (col == 5'd10) ch_c = hexd(I_sample_cnt[11:8]);
            else if (col == 5'd11) ch_c = hexd(I_sample_cnt[7:4]);
            else if (col == 5'd12) ch_c = hexd(I_sample_cnt[3:0]);
        end
        3'd3: begin
            if      (col == 5'd0) ch_c = dec(s3);
            else if (col == 5'd1) ch_c = dec(s2);
            else if (col == 5'd2) ch_c = dec(s1);
            else if (col == 5'd3) ch_c = dec(s0);
            else if (col == 5'd5) ch_c = "S";
            else if (col == 5'd6) ch_c = "E";
            else if (col == 5'd7) ch_c = "C";
        end
        3'd4: begin
            if      (col == 5'd0)  ch_c = "A";
            else if (col == 5'd1)  ch_c = "U";
            else if (col == 5'd2)  ch_c = "D";
            else if (col == 5'd4)  ch_c = "F";
            else if (col == 5'd5)  ch_c = "S";
            else if (col == 5'd6)  ch_c = "M";
            else if (col == 5'd8)  ch_c = hexd(I_aud_fsm[7:4]);
            else if (col == 5'd9)  ch_c = hexd(I_aud_fsm[3:0]);
            else if (col == 5'd11) ch_c = "U";
            else if (col == 5'd13) ch_c = I_aud_undr ? "1" : "0";
        end
        3'd5: begin
            if      (col == 5'd0) ch_c = "V";
            else if (col == 5'd1) ch_c = "I";
            else if (col == 5'd2) ch_c = "D";
            else if (col == 5'd4) ch_c = "F";
            else if (col == 5'd5) ch_c = "S";
            else if (col == 5'd6) ch_c = "M";
            else if (col == 5'd8) ch_c = hexd(I_vid_fsm[7:4]);
            else if (col == 5'd9) ch_c = hexd(I_vid_fsm[3:0]);
        end
        3'd6: begin
            if      (col == 5'd0)  ch_c = "I";
            else if (col == 5'd1)  ch_c = "M";
            else if (col == 5'd2)  ch_c = "G";
            else if (col == 5'd4)  ch_c = hexd(I_img_idx);
            else if (col == 5'd6)  ch_c = "M";
            else if (col == 5'd7)  ch_c = "O";
            else if (col == 5'd8)  ch_c = "D";
            else if (col == 5'd9)  ch_c = "E";
            else if (col == 5'd11) ch_c = hexd(I_mode_num[3:0]);
            else if (col == 5'd13) ch_c = "I";
            else if (col == 5'd14) ch_c = "T";
            else if (col == 5'd16) ch_c = dec({1'b0, I_item});
        end
        default: ch_c = 8'h20;
        endcase
    end

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        inpanel_d2, bord_d2;
    reg [3:0]  gx_d2;
    function [4:0] compact_glyph;
 input [7:0] code;
 begin case(code)
8'd32:compact_glyph=5'd0;
8'd48:compact_glyph=5'd1;
8'd49:compact_glyph=5'd2;
8'd50:compact_glyph=5'd3;
8'd51:compact_glyph=5'd4;
8'd52:compact_glyph=5'd5;
8'd53:compact_glyph=5'd6;
8'd54:compact_glyph=5'd7;
8'd55:compact_glyph=5'd8;
8'd56:compact_glyph=5'd9;
8'd57:compact_glyph=5'd10;
8'd65:compact_glyph=5'd11;
8'd66:compact_glyph=5'd12;
8'd67:compact_glyph=5'd13;
8'd68:compact_glyph=5'd14;
8'd69:compact_glyph=5'd15;
8'd70:compact_glyph=5'd16;
8'd71:compact_glyph=5'd17;
8'd73:compact_glyph=5'd18;
8'd77:compact_glyph=5'd19;
8'd78:compact_glyph=5'd20;
8'd79:compact_glyph=5'd21;
8'd80:compact_glyph=5'd22;
8'd82:compact_glyph=5'd23;
8'd83:compact_glyph=5'd24;
8'd84:compact_glyph=5'd25;
8'd85:compact_glyph=5'd26;
8'd86:compact_glyph=5'd27;
8'd89:compact_glyph=5'd28;
8'd104:compact_glyph=5'd29;
default:compact_glyph=0;
 endcase end
endfunction
reg [4:0] ch_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            inpanel_d2 <= 1'b0; bord_d2 <= 1'b0;
            gx_d2 <= 4'd0; ch_d2 <= 0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1; rgb_d2 <= rgb_d1;
            inpanel_d2 <= inpanel_d1 & I_en;
            bord_d2    <= bord;
            gx_d2      <= gx;
            ch_d2 <= compact_glyph(ch_c);              // D2 给字库地址
        end
    end

    wire [15:0] font_word;
    monitor_compact_font u_font (
        .clk       (I_clk),
        .char_code (ch_d2),
        .row       (gy),
        .rom_row   (font_word)
    );

    wire [3:0] bit_sel = 4'd15 - gx_d2;
    wire       pix_bit = font_word[bit_sel];

    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        inpanel_d3, bord_d3, txt_d3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            inpanel_d3 <= 1'b0; bord_d3 <= 1'b0; txt_d3 <= 1'b0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            inpanel_d3 <= inpanel_d2;
            bord_d3    <= bord_d2;
            txt_d3     <= pix_bit;
        end
    end

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;
        if (inpanel_d3) begin
            comp = C_FILL;
            if (bord_d3) comp = C_BORD;
            if (txt_d3)  comp = C_TXT;
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

endmodule
