`timescale 1ns/1ps

module osd_param_panel #(

    // 画布/视频

    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter CX       = 640,       // 圆心 x（横向居中）
    parameter CY       = 630,       // 圆心 y v5：整体压到屏幕下方
    parameter R_FILL   = 45,        // 圆的可见外边界 v5：45（含边框后正好 90 高）
    parameter T_BORDER = 4,         // 边框厚度（圆环 + 矩形共用）
    parameter GAP      = 12,        // 统一间距：矩形圆、上矩形下矩形
    parameter R_INNER  = R_FILL - T_BORDER,    // 圆环内沿 = 41
    parameter R_GAP    = R_FILL + GAP,         // 矩形内侧弧半径 = 57
    parameter Y_BASE   = CY - R_GAP,           // 圆 ROM 起始行 = 573
    parameter ROWS     = 2 * R_GAP + 1,        // 115（dy = -57..+57）

    parameter BAR_W     = 263,      // 矩形径向厚度（标定到屏幕横向 1/4..3/4）
    parameter BAR_DY_IN = GAP / 2,  // 内侧边界 |dy| = 6 垂直间隔 = 12
    parameter BAR_DY_OUT= R_FILL,   // 外侧边界 |dy| = 45 与圆平齐

    parameter LEN_K     = 327,

    parameter CH_W     = 16,        // 字符点阵宽
    parameter CH_H     = 16,        // 字符点阵高
    parameter CH_PITCH = 20,        // 字符间距 = 16 点阵 + 4 间隙
    parameter NM_SPAN  = CH_PITCH + CH_W,      // 名称 2 字跨度 = 36
    parameter VL_SPAN  = 2 * CH_PITCH + CH_W,  // 数值 3 字跨度 = 56
    parameter NX       = CX - 18,   // 名称行左边界 = 622（2 字居中）
    parameter VX       = CX - 28,   // 数值行左边界 = 612（3 字居中）
    parameter TY_NAME  = CY - 22,   // 名称行顶 y = 608
    parameter TY_VAL   = CY + 6,    // 数值行顶 y = 636

    parameter [23:0] C_BAR_BORDER     = 24'h455763,  // 灰青边框
    parameter [23:0] C_BAR_FILL       = 24'h408F80,  // 深青（未选中）
    parameter [23:0] C_BAR_FILL_SEL   = 24'h67DDC8,  // 浅青（选中）
    parameter [23:0] C_RING           = 24'h455763,
    parameter [23:0] C_DISC           = 24'h14212A,
    // 文字
    parameter [23:0] C_TEXT_NAME      = 24'hE0F1EF,  // 参数名：浅色
    parameter [23:0] C_TEXT_VAL       = 24'hA0F1DE   // 参数值：青绿
)(
    input  wire        I_clk,        // video_clk (75 MHz)
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_panel_en,   // 1 = 显示面板（仅在 P4 模式下）
    input  wire [2:0]  I_sel_idx,
    input  wire [7:0]  I_bri,
    input  wire [7:0]  I_con,
    input  wire [7:0]  I_sat,
    input  wire [7:0]  I_vol,

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam DX_W  = 10;
    localparam VN_W  = 17;

    reg        de_d1, hs_d1, vs_d1;
    reg [23:0] rgb_d1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d1 <= 1'b0; hs_d1 <= 1'b0; vs_d1 <= 1'b0; rgb_d1 <= 24'd0;
        end else begin
            de_d1 <= I_de; hs_d1 <= I_hs; vs_d1 <= I_vs; rgb_d1 <= I_rgb;
        end
    end

    wire [11:0] x_now, y_now;
    osd_position #(
        .H_ACTIVE (H_ACTIVE),
        .V_ACTIVE (V_ACTIVE)
    ) u_pos (
        .clk      (I_clk),
        .rst      (I_rst),
        .de       (I_de),
        .vs       (I_vs),
        .x        (x_now),
        .y        (y_now),
        .pos_vld  (          )
    );

    wire [11:0] dx_full_now = (x_now >= CX[11:0]) ? (x_now - CX[11:0])
                                                  : (CX[11:0] - x_now);
    wire [DX_W-1:0] dx_now  = (dx_full_now > 12'd1023) ? {DX_W{1'b1}}
                                                       : dx_full_now[DX_W-1:0];

    wire signed [12:0] dy_s_now = $signed({1'b0, y_now}) - $signed(Y_BASE[12:0]);
    wire        row_ok_now = (dy_s_now >= 0) && (dy_s_now < ROWS);
    wire [7:0]  row_idx_now = row_ok_now ? dy_s_now[7:0] : 8'hFF;

    reg         row_ok_p;
    reg  [7:0]  row_idx_p;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            row_ok_p <= 1'b0;  row_idx_p <= 8'hFF;
        end else begin
            row_ok_p  <= row_ok_now;
            row_idx_p <= row_idx_now;
        end
    end

    wire [7:0]  hw_inner_now, hw_fill_now, hw_gap_now;
    osd_circle_rom u_circle (
        .clk       (I_clk),              // v6：同步读
        .row_idx   (row_idx_p),          // 已寄存的地址 ROM 起点是寄存器
        .hw_inner  (hw_inner_now),       // 同步输出（下一拍有效）
        .hw_fill   (hw_fill_now),
        .hw_gap    (hw_gap_now)
    );

    wire [11:0] dy_abs_now = (y_now >= CY[11:0]) ? (y_now - CY[11:0])
                                                 : (CY[11:0] - y_now);
    wire row_rect_now   = (dy_abs_now >  BAR_DY_IN) && (dy_abs_now <  BAR_DY_OUT);
    wire row_rect_i_now = (dy_abs_now > (BAR_DY_IN + T_BORDER)) &&
                          (dy_abs_now < (BAR_DY_OUT - T_BORDER));

    wire left_side_now  = (x_now < CX[11:0]);
    wire upper_side_now = (y_now < CY[11:0]);

    wire [VN_W-1:0] bri_xk = {{(VN_W-8){1'b0}}, I_bri} * LEN_K;
    wire [VN_W-1:0] con_xk = {{(VN_W-8){1'b0}}, I_con} * LEN_K;
    wire [VN_W-1:0] sat_xk = {{(VN_W-8){1'b0}}, I_sat} * LEN_K;
    wire [VN_W-1:0] vol_xk = {{(VN_W-8){1'b0}}, I_vol} * LEN_K;
    reg [7:0] bri_len, con_len, sat_len, vol_len;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            bri_len<=0; con_len<=0; sat_len<=0; vol_len<=0;
        end else begin
            bri_len<=bri_xk[15:8]; con_len<=con_xk[15:8];
            sat_len<=sat_xk[15:8]; vol_len<=vol_xk[15:8];
        end
    end
    wire [7:0] len_left = upper_side_now ? bri_len : sat_len;
    wire [7:0] len_right = upper_side_now ? con_len : vol_len;
    wire [7:0] len_c = left_side_now ? len_left : len_right;

    reg [11:0] x_d1, y_d1;
    reg [DX_W-1:0] dx_d1;
    reg [7:0]  hw_inner_d1, hw_fill_d1, hw_gap_d1;
    reg        row_ok_d1, row_rect_d1, row_rect_i_d1;
    reg        left_side_d1, upper_side_d1;
    reg [7:0]  len_r;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            x_d1 <= 12'd0;                y_d1 <= 12'd0;
            dx_d1 <= {DX_W{1'b0}};
            hw_inner_d1 <= 8'd0;          hw_fill_d1 <= 8'd0;
            hw_gap_d1   <= 8'd0;
            row_ok_d1 <= 1'b0;            row_rect_d1 <= 1'b0;
            row_rect_i_d1 <= 1'b0;
            left_side_d1 <= 1'b0;         upper_side_d1 <= 1'b0;
            len_r <= 8'd0;
        end else begin
            x_d1 <= x_now;                y_d1 <= y_now;
            dx_d1 <= dx_now;

            hw_inner_d1 <= hw_inner_now;  hw_fill_d1 <= hw_fill_now;
            hw_gap_d1   <= hw_gap_now;
            row_ok_d1 <= row_ok_p;        row_rect_d1 <= row_rect_now;
            row_rect_i_d1 <= row_rect_i_now;
            left_side_d1 <= left_side_now;
            upper_side_d1 <= upper_side_now;
            len_r <= len_c;
        end
    end

    wire in_inner = row_ok_d1 && (dx_d1 < hw_inner_d1);
    wire in_fill  = row_ok_d1 && (dx_d1 < hw_fill_d1);
    wire in_ring  = in_fill && !in_inner;

    wire in_rect   = row_ok_d1 && row_rect_d1 &&
                     (dx_d1 >= hw_gap_d1) && (dx_d1 < (hw_gap_d1 + BAR_W));

    wire in_rect_i = row_ok_d1 && row_rect_i_d1 &&
                     (dx_d1 >= (hw_gap_d1 + T_BORDER)) &&
                     (dx_d1 <  (hw_gap_d1 + BAR_W - T_BORDER));

    wire rect_border = in_rect & ~in_rect_i;

    wire bar0 = in_rect &&  left_side_d1 &&  upper_side_d1;   // 左上
    wire bar1 = in_rect && !left_side_d1 &&  upper_side_d1;   // 右上
    wire bar2 = in_rect &&  left_side_d1 && !upper_side_d1;   // 左下
    wire bar3 = in_rect && !left_side_d1 && !upper_side_d1;   // 右下
    wire bar_sel = (bar0 & (I_sel_idx == 3'd0)) |
                   (bar1 & (I_sel_idx == 3'd1)) |
                   (bar2 & (I_sel_idx == 3'd2)) |
                   (bar3 & (I_sel_idx == 3'd3));

    wire rect_fill = in_rect_i && (dx_d1 < (hw_gap_d1 + T_BORDER + len_r));

    reg de_d2, hs_d2, vs_d2;
    reg in_fill_d2, in_ring_d2, panel_d2;
    reg rect_border_d2, rect_fill_d2, rect_sel_d2;
    reg rect_bg_d2;
    reg [23:0] rgb_d2;
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
8'd127:compact_glyph=5'd11;
8'd128:compact_glyph=5'd12;
8'd129:compact_glyph=5'd13;
8'd130:compact_glyph=5'd14;
8'd131:compact_glyph=5'd15;
8'd132:compact_glyph=5'd16;
8'd133:compact_glyph=5'd17;
8'd134:compact_glyph=5'd18;
default:compact_glyph=0;
 endcase end
endfunction
reg [4:0] font_code_d2;
    reg [3:0]  font_row_d2;
    reg        bit_in_txt_d2, in_val_row_d2;
    reg [3:0]  font_bitcol_d2;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0;
            in_fill_d2 <= 1'b0; in_ring_d2 <= 1'b0;
            rect_bg_d2 <= 1'b0; rect_border_d2 <= 1'b0; rect_fill_d2 <= 1'b0;
            rect_sel_d2 <= 1'b0; panel_d2 <= 1'b0;
            rgb_d2 <= 24'd0;
            font_code_d2 <= 0; font_row_d2 <= 4'd0;
            bit_in_txt_d2 <= 1'b0; in_val_row_d2 <= 1'b0;
            font_bitcol_d2 <= 4'd0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1;
            in_fill_d2 <= in_fill; in_ring_d2 <= in_ring;
            rect_bg_d2 <= in_rect;
            rect_border_d2 <= rect_border; rect_fill_d2 <= rect_fill;
            rect_sel_d2 <= bar_sel;
            panel_d2 <= I_panel_en;
            rgb_d2 <= rgb_d1;

            font_code_d2 <= compact_glyph(in_name_row_c ? name_code_c : val_code_c);
            font_row_d2   <= in_name_row_c ? txt_row_c   : txt_row_val_c;

            bit_in_txt_d2 <= (in_name_row_c & bit_in_name_col_c) |
                             (in_val_row_c  & bit_in_val_col_c);   // 两者互斥
            in_val_row_d2 <= in_val_row_c;                   // 决定文字颜色
            font_bitcol_d2<= in_name_row_c ? name_bitcol_c : val_bitcol_c;
        end
    end

    wire [11:0] nm_off = (x_d1 >= NX[11:0]) ? (x_d1 - NX[11:0]) : 12'd0;
    wire in_name_col_c = (x_d1 >= NX[11:0]) && (x_d1 < (NX + NM_SPAN));
    wire [11:0] name_coff_c = (nm_off < 12'd20) ? nm_off
                            : (nm_off < 12'd36) ? (nm_off - 12'd20)
                                                : (nm_off - 12'd36);
    wire        in_name_row_c = (y_d1 >= TY_NAME[11:0]) &&
                                (y_d1 < (TY_NAME + CH_H));
    wire        bit_in_name_col_c = in_name_row_c && in_name_col_c &&
                                    (name_coff_c < CH_W);
    wire [3:0]  name_bitcol_c = name_coff_c[3:0];       // 0..15

    wire [11:0] name_yoff_c   = y_d1 - TY_NAME[11:0];
    wire [3:0]  txt_row_c     = name_yoff_c[3:0];

    wire [11:0] vl_off = (x_d1 >= VX[11:0]) ? (x_d1 - VX[11:0]) : 12'd0;
    wire in_val_col_c = (x_d1 >= VX[11:0]) && (x_d1 < (VX + VL_SPAN));
    wire [11:0] val_coff_c = (vl_off < 12'd20) ? vl_off
                           : (vl_off < 12'd40) ? (vl_off - 12'd20)
                                               : (vl_off - 12'd40);
    wire        in_val_row_c = (y_d1 >= TY_VAL[11:0]) &&
                               (y_d1 < (TY_VAL + CH_H));
    wire        bit_in_val_col_c = in_val_row_c && in_val_col_c &&
                                   (val_coff_c < CH_W);
    wire [3:0]  val_bitcol_c = val_coff_c[3:0];
    wire [11:0] val_yoff_c   = y_d1 - TY_VAL[11:0];
    wire [3:0]  txt_row_val_c = val_yoff_c[3:0];

    localparam [7:0] CN_YIN     = 8'h7F,   // 音
                     CN_LIANG_V = 8'h80,   // 量（用于\"音量\"的第二字）
                     CN_LIANG   = 8'h81,   // 亮
                     CN_DU      = 8'h82,   // 度
                     CN_DUI     = 8'h83,   // 对
                     CN_BI      = 8'h84,   // 比
                     CN_BAO     = 8'h85,   // 饱
                     CN_HE      = 8'h86;   // 和

    reg [7:0] cn0_c, cn1_c;
    always @(*) begin
        case (I_sel_idx)
            3'd0: begin cn0_c = CN_LIANG;   cn1_c = CN_DU;      end  // 亮度
            3'd1: begin cn0_c = CN_DUI;     cn1_c = CN_BI;      end  // 对比
            3'd2: begin cn0_c = CN_BAO;     cn1_c = CN_HE;      end  // 饱和
            3'd3: begin cn0_c = CN_YIN;     cn1_c = CN_LIANG_V; end  // 音量
            default: begin cn0_c = 8'h20;   cn1_c = 8'h20; end
        endcase
    end

    wire [7:0] name_code_c = (x_d1 < NX[11:0] + 12'd20) ? cn0_c : cn1_c;

    wire [7:0] sel_val_c = (I_sel_idx == 3'd0) ? I_bri :
                           (I_sel_idx == 3'd1) ? I_con :
                           (I_sel_idx == 3'd2) ? I_sat : I_vol;
    wire       v_ge200_c = (sel_val_c >= 8'd200);
    wire       v_ge100_c = (sel_val_c >= 8'd100) && !v_ge200_c;
    wire       v_ge10_c  = (sel_val_c >= 8'd10);
    wire [3:0] v_hund_c  = v_ge200_c ? 4'd2 : (v_ge100_c ? 4'd1 : 4'd0);
    wire [7:0] v_rem_c   = v_ge200_c ? (sel_val_c - 8'd200) :
                           v_ge100_c ? (sel_val_c - 8'd100) : sel_val_c;

    reg [7:0] sel_val_a;
    reg [3:0] v_hund_a;
    reg [7:0] v_rem_a;
    reg       v_ge10_a, v_ge100_a;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            sel_val_a <= 8'd0; v_hund_a <= 4'd0; v_rem_a <= 8'd0;
            v_ge10_a <= 1'b0;  v_ge100_a <= 1'b0;
        end else begin
            sel_val_a <= sel_val_c;
            v_hund_a  <= v_hund_c;
            v_rem_a   <= v_rem_c;
            v_ge10_a  <= v_ge10_c;
            v_ge100_a <= (v_ge100_c | v_ge200_c);   // 百位"该显示"（100..200）
        end
    end

    wire [3:0] v_ten_a   = v_rem_a / 8'd10;              // 0..9
    wire [4:0] v_ten_x10 = {1'b0, v_ten_a} << 3;         // *8
    wire [4:0] v_ten_x2  = {1'b0, v_ten_a} << 1;         // *2
    wire [5:0] v_ten_mul = v_ten_x10 + v_ten_x2;         // *10 ≤ 90
    wire [7:0] v_one_a   = v_rem_a - {2'd0, v_ten_mul};  // 0..9

    reg [3:0] v_hund_p, v_ten_p, v_one_p;
    reg       v_ge10_p, v_ge100_p;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            v_hund_p <= 4'd0; v_ten_p <= 4'd0; v_one_p <= 4'd0;
            v_ge10_p <= 1'b0; v_ge100_p <= 1'b0;
        end else begin
            v_hund_p  <= v_hund_a;
            v_ten_p   <= v_ten_a;
            v_one_p   <= v_one_a[3:0];
            v_ge10_p  <= v_ge10_a;
            v_ge100_p <= v_ge100_a;
        end
    end

    wire [7:0] val_code_c = (val_coff_c < CH_W) ?
                            ((vl_off < 12'd20) ? (v_ge100_p ? (8'h30 + v_hund_p) : 8'h20) :
                             (vl_off < 12'd40) ? (v_ge10_p  ? (8'h30 + v_ten_p)  : 8'h20)
                                               : (8'h30 + v_one_p))
                          : 8'h20;

    wire [15:0] font_word;
    p4_compact_font u_font (
        .clk       (I_clk),
        .char_code (font_code_d2),          // D2 地址
        .row       (font_row_d2),           // D2 地址
        .rom_row   (font_word)              // D3 数据（地址后 1 拍）
    );

    reg        de_d3, hs_d3, vs_d3;
    reg        in_fill_d3, in_ring_d3, panel_d3;
    reg        rect_border_d3, rect_fill_d3, rect_sel_d3;
    reg rect_bg_d3;
    reg [3:0]  font_bitcol_d3;
    reg        bit_in_txt_d3, in_val_row_d3;
    reg [23:0] rgb_d3;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0;
            in_fill_d3 <= 1'b0; in_ring_d3 <= 1'b0; panel_d3 <= 1'b0;
            rect_bg_d3 <= 1'b0; rect_border_d3 <= 1'b0; rect_fill_d3 <= 1'b0; rect_sel_d3 <= 1'b0;
            font_bitcol_d3 <= 4'd0;
            bit_in_txt_d3 <= 1'b0; in_val_row_d3 <= 1'b0;
            rgb_d3 <= 24'd0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2;
            in_fill_d3 <= in_fill_d2; in_ring_d3 <= in_ring_d2;
            panel_d3 <= panel_d2;
            rect_bg_d3 <= rect_bg_d2;
            rect_border_d3 <= rect_border_d2;
            rect_fill_d3 <= rect_fill_d2;
            rect_sel_d3 <= rect_sel_d2;
            font_bitcol_d3 <= font_bitcol_d2;   // 与 font_word 同拍
            bit_in_txt_d3  <= bit_in_txt_d2;
            in_val_row_d3  <= in_val_row_d2;
            rgb_d3 <= rgb_d2;
        end
    end

    wire [3:0] font_bit_sel_d3 = 4'd15 - font_bitcol_d3;
    wire       txt_pix_d3      = bit_in_txt_d3 & font_word[font_bit_sel_d3];

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;                                   // 默认：背景图
        if (panel_d3) begin
            if (txt_pix_d3)
                comp = in_val_row_d3 ? C_TEXT_VAL : C_TEXT_NAME;   // 文字
            else if (in_ring_d3)
                comp = C_RING;                                     // 圆环（灰青）
            else if (in_fill_d3)
                comp = C_DISC;                                     // 圆填充（深色）
            else if (rect_border_d3)
                comp = rect_sel_d3 ? C_BAR_FILL_SEL : C_BAR_BORDER;                               // 矩形边框（灰青）
            else if (rect_fill_d3)
                comp = rect_sel_d3 ? C_BAR_FILL_SEL : C_BAR_FILL;  // 深青 / 浅青
            else if (rect_bg_d3)
                comp = rect_sel_d3 ? 24'h183738 : C_DISC;
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
