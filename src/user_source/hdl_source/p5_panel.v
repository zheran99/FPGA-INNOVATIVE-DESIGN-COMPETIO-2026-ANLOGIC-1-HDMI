`timescale 1ns / 1ps

module p5_panel #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter X0    = 182,      // 第 1 列起点
    parameter Y0    = 594,      // 第 1 行起点
    parameter CW    = 300,      // 格宽
    parameter CH    = 32,       // 格高（= 文字高，恰好容纳）
    parameter DX    = 308,      // 列间距（= CW + 8）
    parameter DY    = 40,       // 行间距（= CH + 8）
    parameter TB    = 2,        // 边框厚度

    // 文字几何

    parameter GLYPH_W  = 32,    // 字库字形宽（位）
    parameter CPITCH   = 32,    // 字距 = 字形宽（32 = 2^5 取列只用位选）
    parameter NAME_X   = 16,    // 名称左起（格内坐标）
    parameter VAL_X    = 180,   // 状态左起（格内坐标）

    // 配色

    parameter [23:0] C_SEL_BORD = 24'h67DDC8,
                     C_SEL_FILL = 24'h183738,
                     C_BORD     = 24'h455763,
                     C_TXT      = 24'hE0F1EF,
                     C_FILL     = 24'h14212A,
                     C_NAME_DIM = 24'hADC2CA,
                     C_VALUE    = 24'hA0F1DE,
                     C_OFF      = 24'hBCC9D2,
                     C_TRACK_ON = 24'h408F80,
                     C_TRACK_OFF= 24'h53616D,
                     C_KNOB_ON  = 24'hE6FFF8,
                     C_KNOB_OFF = 24'hB1BEC8
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_panel_en,     // 1 = 显示面板（仅 P5）
    input  wire [2:0]  I_item,         // 当前选中项 0..5

    input  wire        I_sub_on,       // #0 开关
    input  wire [1:0]  I_mode,         // #1 换句
    input  wire [1:0]  I_pos,          // #2 位置
    input  wire [1:0]  I_bg,           // #3 背景
    input  wire        I_size,         // #4 字号
    input  wire        I_monitor,      // #5 监视

    output wire [5:0]  O_font_idx,     // D2 地址（6 位汉字索引）
    output wire [4:0]  O_font_row,     // D2 地址（5 位行号）
    input  wire [31:0] I_font_word,    // D3 数据（32 位，与 gx_d2 同拍）

    output wire        O_de,           // 已延迟 4 拍
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    // 输入打 1 拍

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
        .clk     (I_clk),
        .rst     (I_rst),
        .de      (I_de),
        .vs      (I_vs),
        .x       (x_now),
        .y       (y_now),
        .pos_vld (        )
    );

    reg [11:0] x_d1, y_d1;        // 面板内坐标（已减原点）
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            x_d1 <= 12'd0; y_d1 <= 12'd0;
        end else begin
            x_d1 <= x_now - X0;
            y_d1 <= y_now - Y0;
        end
    end

    localparam X_END  = X0 + 2 * DX + CW;     // 182 + 616 + 300 = 1098
    localparam Y_END  = Y0 + DY + CH;         // 594 + 40 + 32 = 666
    localparam DX2    = 2 * DX;               // 616
    localparam CW_M   = CW - TB;
    localparam CH_M   = CH - TB;
    localparam X2P    = 2 * CPITCH;           // 64（每侧 2 字的显示跨度）

    wire in_panel = (x_d1 < X_END - X0) && (y_d1 < Y_END - Y0);

    localparam PX_W=$clog2(2*DX+CW), PY_W=$clog2(Y_END-Y0);
    localparam IX_W=$clog2(CW), IY_W=$clog2(CH);
    wire [PX_W-1:0] px = x_d1[PX_W-1:0];                    // 面板内 x（原点已在 D1 减掉）
    wire [PY_W-1:0] py = y_d1[PY_W-1:0];                    // 面板内 y

    wire col0 = (px < CW);
    wire col1 = (px >= DX)  && (px < DX + CW);
    wire col2 = (px >= DX2) && (px < DX2 + CW);

    // 行定位
    wire row0 = (py < CH);
    wire row1 = (py >= DY) && (py < DY + CH);

    wire [IX_W-1:0] ix = col0 ? px : (col1 ? (px - DX) : (px - DX2));
    wire [IY_W-1:0] iy = row0 ? py : (py - DY);

    wire in_cell = in_panel & (col0 | col1 | col2) & (row0 | row1);

    reg [2:0] text_cid_d1;
    wire [2:0] cid = text_cid_d1;

    wire bord = (ix < TB) || (ix >= CW_M) || (iy < TB) || (iy >= CH_M);

    wire sel = (cid == I_item);

    wire [11:0] text_x_next=x_now-X0, text_y_next=y_now-Y0;
    wire [PX_W-1:0] text_px_next=text_x_next[PX_W-1:0];
    wire [PY_W-1:0] text_py_next=text_y_next[PY_W-1:0];
    wire text_col0_next=text_px_next<CW;
    wire text_col1_next=text_px_next>=DX && text_px_next<DX+CW;
    wire [PX_W-1:0] OFF_NAME = text_col0_next ? NAME_X : (text_col1_next ? (DX + NAME_X) : (DX2 + NAME_X));
    wire [PX_W-1:0] OFF_VAL  = text_col0_next ? VAL_X  : (text_col1_next ? (DX + VAL_X)  : (DX2 + VAL_X));
    reg [5:0] nx_off,vx_off;
    reg in_name,in_val;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            text_cid_d1<=0;nx_off<=-NAME_X;vx_off<=-VAL_X;
            in_name<=0;in_val<=0;
        end else begin
            text_cid_d1<=(text_py_next<CH ? 3'd0 : 3'd3) +
                (text_col0_next ? 3'd0 : (text_col1_next ? 3'd1 : 3'd2));
            nx_off<=text_px_next[5:0]-OFF_NAME[5:0];
            vx_off<=text_px_next[5:0]-OFF_VAL[5:0];
            in_name<=(text_px_next>=OFF_NAME) && (text_px_next<OFF_NAME+X2P);
            in_val<=(text_px_next>=OFF_VAL) && (text_px_next<OFF_VAL+X2P);
        end
    end

    wire [5:0] off_c = in_val ? vx_off : nx_off;

    wire nm1 = nx_off[5];
    wire vl1 = vx_off[5];

    wire [4:0]  gx_c  = off_c[4:0];
    wire [4:0]  gy_c  = iy[4:0];        // 格高 32 = 2^5

    localparam [5:0] CN_KAI   = 6'd0,   // 开
                     CN_GUAN  = 6'd1,   // 关
                     CN_HUAN  = 6'd2,   // 换
                     CN_JU    = 6'd3,   // 句
                     CN_WEI   = 6'd4,   // 位
                     CN_ZHI   = 6'd5,   // 置
                     CN_BEI   = 6'd6,   // 背
                     CN_JING  = 6'd7,   // 景
                     CN_ZI    = 6'd8,   // 字
                     CN_HAO   = 6'd9,   // 号
                     CN_JIAN  = 6'd10,  // 监
                     CN_SHI   = 6'd11,  // 视
                     CN_GUN   = 6'd12,  // 滚
                     CN_DONG  = 6'd13,  // 动
                     CN_ZHIQ  = 6'd14,  // 直
                     CN_QIE   = 6'd15,  // 切
                     CN_DA    = 6'd18,  // 打（打字模式用；字=CN_ZI）
                     CN_DI    = 6'd19,  // 底
                     CN_BU    = 6'd20,  // 部
                     CN_DING  = 6'd21,  // 顶
                     CN_YOU   = 6'd22,  // 右
                     CN_WU    = 6'd23,  // 无
                     CN_BAN   = 6'd24,  // 半
                     CN_TOU   = 6'd25,  // 透
                     CN_SHIT  = 6'd26,  // 实
                     CN_XIAO  = 6'd27,  // 小
                     CN_ZHONG = 6'd28,  // 中
                     CN_XIA   = 6'd29;  // 下
    localparam [5:0] CN_BLANK = 6'd38;  // 空位（字库里全 0 不画）

    reg [5:0] nm0_c, nm1_c;
    always @(*) begin
        case (cid)
            3'd0: begin nm0_c = CN_KAI;  nm1_c = CN_GUAN; end  // 开关
            3'd1: begin nm0_c = CN_HUAN; nm1_c = CN_JU;   end  // 换句
            3'd2: begin nm0_c = CN_WEI;  nm1_c = CN_ZHI;  end  // 位置
            3'd3: begin nm0_c = CN_BEI;  nm1_c = CN_JING; end  // 背景
            3'd4: begin nm0_c = CN_ZI;   nm1_c = CN_HAO;  end  // 字号
            3'd5: begin nm0_c = CN_JIAN; nm1_c = CN_SHI;  end  // 监视
            default: begin nm0_c = CN_BLANK; nm1_c = CN_BLANK; end
        endcase
    end

    reg [5:0] v0_c, v1_c;
    always @(*) begin
        case (cid)

            3'd0: begin
                v0_c = I_sub_on ? CN_KAI : CN_GUAN;
                v1_c = CN_BLANK;
            end

            3'd1: begin
                case (I_mode)
                    2'd0:    begin v0_c = CN_GUN;  v1_c = CN_DONG; end // 滚动
                    2'd1:    begin v0_c = CN_ZHIQ; v1_c = CN_QIE;  end // 直切
                    default: begin v0_c = CN_DA;   v1_c = CN_ZI;   end // 打字
                endcase
            end
            3'd2: begin
                case (I_pos)
                    2'd0:    begin v0_c = CN_DI;   v1_c = CN_BU;   end // 底部
                    2'd1:    begin v0_c = CN_DING; v1_c = CN_BU;   end // 顶部
                    default: begin v0_c = CN_YOU;  v1_c = CN_XIA;  end // 右下
                endcase
            end
            3'd3: begin
                case (I_bg)
                    2'd0:    begin v0_c = CN_WU;   v1_c = CN_BLANK; end // 无
                    2'd1:    begin v0_c = CN_BAN;  v1_c = CN_TOU;   end // 半透
                    default: begin v0_c = CN_SHIT; v1_c = CN_DI;    end // 实底
                endcase
            end
            3'd4: begin
                v0_c = I_size ? CN_ZHONG : CN_XIAO;
                v1_c = CN_BLANK;
            end

            default: begin
                v0_c = I_monitor ? CN_KAI : CN_GUAN;
                v1_c = CN_BLANK;
            end
        endcase
    end

    wire [5:0] name_idx_c = nm1 ? nm1_c : nm0_c;
    wire [5:0] val_idx_c  = vl1 ? v1_c  : v0_c;

    wire [5:0] char_idx_c = in_val ? val_idx_c
                          : (in_name ? name_idx_c : CN_BLANK);

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        incell_d2, bord_d2, sel_d2, txtreg_d2;
    reg [4:0]  gx_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            incell_d2 <= 1'b0; bord_d2 <= 1'b0; sel_d2 <= 1'b0;
            txtreg_d2 <= 1'b0; gx_d2 <= 5'd0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1; rgb_d2 <= rgb_d1;
            incell_d2 <= in_cell & I_panel_en;
            bord_d2   <= bord;
            sel_d2    <= sel;
            txtreg_d2 <= in_name | in_val;     // 本像素是否在文字区
            gx_d2     <= gx_c;
        end
    end

    assign O_font_idx  = char_idx_c;        // D2 地址（6 位索引）
    assign O_font_row  = gy_c;              // D2 地址（5 位行号）
    wire [31:0] font_word = I_font_word;    // D3 数据（32 位）

    wire [4:0] bit_sel = 5'd31 - gx_d2;
    wire       pix_bit = font_word[bit_sel];

    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        incell_d3, bord_d3, sel_d3, txt_d3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            incell_d3 <= 1'b0; bord_d3 <= 1'b0; sel_d3 <= 1'b0; txt_d3 <= 1'b0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            incell_d3 <= incell_d2;
            bord_d3   <= bord_d2;
            sel_d3    <= sel_d2;
            txt_d3    <= txtreg_d2 & pix_bit;
        end
    end

    wire switch_en = (cid==0 || cid==5);
    wire switch_on = (cid==0 ? I_sub_on : I_monitor);
    wire focus_mark = (sel) && ix>=6 && ix<9 && iy>=11 && iy<21;
    wire switch_track = switch_en && ix>=248 && ix<284 && iy>=9 && iy<23;
    wire switch_knob = switch_track && iy>=11 && iy<21 &&
        (switch_on ? (ix>=270 && ix<282) : (ix>=250 && ix<262));
    wire [2:0] decoration = focus_mark ? 3'd1 :
        switch_knob ? (switch_on ? 3'd4 : 3'd5) :
        switch_track ? (switch_on ? 3'd2 : 3'd3) : 3'd0;
    reg [2:0] decoration_d2, decoration_d3;
    reg value_d2, value_d3, off_d2, off_d3;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            decoration_d2<=0; decoration_d3<=0;
            value_d2<=0; value_d3<=0; off_d2<=0; off_d3<=0;
        end else begin
            decoration_d2<=decoration; decoration_d3<=decoration_d2;
            value_d2<=in_val; value_d3<=value_d2;
            off_d2<=switch_en && !switch_on; off_d3<=off_d2;
        end
    end
    wire [23:0] decoration_color = decoration_d3==1 ? C_VALUE :
        decoration_d3==2 ? C_TRACK_ON : decoration_d3==3 ? C_TRACK_OFF :
        decoration_d3==4 ? C_KNOB_ON : C_KNOB_OFF;

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;                              // 默认：底图
        if (incell_d3) begin
            comp = sel_d3 ? C_SEL_FILL : C_FILL;    // 固定底板确保文字对比度
            if (bord_d3) comp = sel_d3 ? C_SEL_BORD : C_BORD;
            if (decoration_d3!=0) comp = decoration_color;
            if (txt_d3) comp = value_d3 ? (off_d3 ? C_OFF : C_VALUE) :
                                           (sel_d3 ? C_TXT : C_NAME_DIM);
        end
    end

    // 输出寄存

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
