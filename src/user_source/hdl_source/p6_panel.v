`timescale 1ns / 1ps

module p6_panel #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter X0    = 182,      // 第 1 列起点（与 p5_panel 对齐）
    parameter Y0    = 614,      // 单行起点（585..675 带内垂直居中）
    parameter CW    = 300,      // 格宽（沿用 p5_panel）
    parameter CH    = 32,       // 格高（= 文字高，恰好容纳）
    parameter DX    = 308,      // 列间距（= CW + 8）
    parameter TB    = 2,        // 边框厚度

    parameter GLYPH_W  = 32,    // 字库字形宽（位）
    parameter CPITCH   = 32,    // 字距 = 字形宽（32 = 2^5 取列只用位选）
    parameter NAME_X   = 16,    // 名称左起（格内坐标）
    parameter VAL_X    = 180,   // 状态左起（格内坐标）

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

    input  wire        I_panel_en,     // 1 = 显示面板（仅 P6）
    input  wire [1:0]  I_item,         // 当前选中项 0..2

    input  wire [1:0]  I_logo_sel,     // #0 标志：0=关 1=开(静止) 2=动(弹移)
    input  wire        I_ad_on,        // #1 广告：0=关 1=开
    input  wire [1:0]  I_ad_bg,        // #2 背景：0=无 1=半透 2=实底

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

    reg [11:0] x_d1, y_d1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            x_d1 <= 12'd0; y_d1 <= 12'd0;
        end else begin
            x_d1 <= x_now - X0;
            y_d1 <= y_now - Y0;
        end
    end

    localparam X_END = X0 + 2 * DX + CW;      // 182 + 616 + 300 = 1098
    localparam Y_END = Y0 + CH;               // 614 + 32 = 646
    localparam DX2   = 2 * DX;                // 616
    localparam CW_M  = CW - TB;
    localparam CH_M  = CH - TB;
    localparam X2P   = 2 * CPITCH;            // 64（每侧 2 字的显示跨度）

    wire in_panel = (x_d1 < X_END - X0) && (y_d1 < Y_END - Y0);

    localparam PX_W=$clog2(2*DX+CW), PY_W=$clog2(Y_END-Y0);
    localparam IX_W=$clog2(CW), IY_W=$clog2(CH);
    wire [PX_W-1:0] px = x_d1[PX_W-1:0];                    // 面板内 x（原点已在 D1 减掉）
    wire [PY_W-1:0] py = y_d1[PY_W-1:0];                    // 面板内 y

    wire col0 = (px < CW);
    wire col1 = (px >= DX)  && (px < DX + CW);
    wire col2 = (px >= DX2) && (px < DX2 + CW);

    wire row0 = (py < CH);

    wire [IX_W-1:0] ix = col0 ? px : (col1 ? (px - DX) : (px - DX2));
    wire [IY_W-1:0] iy = py;

    wire in_cell = in_panel & (col0 | col1 | col2) & row0;

    // 格号 0..2

    wire [1:0] cid = col0 ? 2'd0 : (col1 ? 2'd1 : 2'd2);

    wire bord = (ix < TB) || (ix >= CW_M) || (iy < TB) || (iy >= CH_M);

    wire sel = (cid == I_item);

    wire [PX_W-1:0] OFF_NAME = col0 ? NAME_X : (col1 ? (DX + NAME_X) : (DX2 + NAME_X));
    wire [PX_W-1:0] OFF_VAL  = col0 ? VAL_X  : (col1 ? (DX + VAL_X)  : (DX2 + VAL_X));
    wire [5:0] nx_off = px[5:0] - OFF_NAME[5:0];
    wire [5:0] vx_off = px[5:0] - OFF_VAL[5:0];

    wire in_name = (px >= OFF_NAME) && (px < OFF_NAME + X2P);
    wire in_val  = (px >= OFF_VAL)  && (px < OFF_VAL + X2P);

    wire [5:0] off_c = in_val ? vx_off : nx_off;

    wire nm1 = nx_off[5];
    wire vl1 = vx_off[5];

    wire [4:0]  gx_c = off_c[4:0];
    wire [4:0]  gy_c = iy[4:0];        // 格高 32 = 2^5

    localparam [5:0] CN_KAI  = 6'd0,    // 开
                     CN_GUAN = 6'd1,    // 关
                     CN_BEI  = 6'd6,    // 背 #2 名称「背景」（与 p5_panel 同一对字）
                     CN_JING = 6'd7,    // 景
                     CN_DONG = 6'd13,   // 动
                     CN_DI   = 6'd19,   // 底
                     CN_WU   = 6'd23,   // 无
                     CN_BAN  = 6'd24,   // 半
                     CN_TOU  = 6'd25,   // 透
                     CN_SHIT = 6'd26,   // 实
                     CN_BIAO = 6'd39,
                     CN_ZHI  = 6'd40,
                     CN_GUANG= 6'd41,
                     CN_GAO  = 6'd42;

    localparam [5:0] CN_BLANK = 6'd38;

    reg [5:0] nm0_c, nm1_c;
    always @(*) begin
        case (cid)
            2'd0:    begin nm0_c = CN_BIAO;  nm1_c = CN_ZHI;  end  // 标志
            2'd1:    begin nm0_c = CN_GUANG; nm1_c = CN_GAO;  end  // 广告
            default: begin nm0_c = CN_BEI;   nm1_c = CN_JING; end  // 背景
        endcase
    end

    reg [5:0] v0_c, v1_c;
    always @(*) begin
        case (cid)
            2'd0: begin
                case (I_logo_sel)
                    2'd0:    begin v0_c = CN_GUAN; v1_c = CN_BLANK; end // 关
                    2'd1:    begin v0_c = CN_KAI;  v1_c = CN_BLANK; end // 开
                    default: begin v0_c = CN_DONG; v1_c = CN_BLANK; end // 动
                endcase
            end
            2'd1: begin
                v0_c = I_ad_on ? CN_KAI : CN_GUAN;
                v1_c = CN_BLANK;
            end

            default: begin
                case (I_ad_bg)
                    2'd0:    begin v0_c = CN_WU;   v1_c = CN_BLANK; end // 无
                    2'd1:    begin v0_c = CN_BAN;  v1_c = CN_TOU;   end // 半透
                    default: begin v0_c = CN_SHIT; v1_c = CN_DI;    end // 实底
                endcase
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
            bord_d2   <= in_cell & bord;
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

    wire switch_en = (cid==1);
    wire switch_on = I_ad_on;
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
