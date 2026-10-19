`timescale 1ns / 1ps

module ad_text #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter X0      = 16,     // 文字左上角
    parameter Y0      = 16,
    parameter GLYPH_W = 16,     // 字形宽（位）
    parameter GLYPH_H = 16,     // 字形高（行）
    parameter PITCH   = 16,     // 字距 = 字形宽（16 = 2^4 取列只用位选）

    parameter MAX_COLS  = 64,   // 每行最多字符数（col 6 位）
    parameter MAX_LINES = 4,    // 最多行数（line 2 位）

    // 配色
    parameter [23:0] C_TXT      = 24'hFFFFFF,   // 文字：白
                     C_BG_SOLID = 24'h000000    // 背景=实底：黑条
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_en,           // 1 = 显示广告文字（P6 的「广告」开关）
    input  wire [1:0]  I_bg,           // 0=无背景 1=半透 2=实底
    input  wire [4:0]  I_img,          // 图片序号 1..9（随切图变化）；

    input  wire        I_txt_wr_clk,
    input  wire        I_txt_wr_en,
    input  wire [5:0]  I_txt_wr_addr,
    input  wire [15:0] I_txt_wr_data,
    input  wire        I_ach_wr_en,
    input  wire [9:0]  I_ach_wr_addr,
    input  wire [7:0]  I_ach_wr_data,

    output wire        O_de,           // 已延迟 5 拍
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    wire [3:0] img_sel = I_img[3:0] - 4'd1;

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

    wire [7:0] col   = x_d1[11:4];
    wire [3:0] gx    = x_d1[3:0];     // 字形内列

    wire [1:0] line  = y_d1[5:4];     // 行号 0..3（= y_d1 / 16）
    wire [3:0] gy    = y_d1[3:0];     // 字形内行（行高 16 = 2^4）

    wire       in_block = ~|y_d1[11:6];

    wire [7:0] tbl_code;
    wire [5:0] tbl_len;
    ad_str_tbl u_str (
        .clk(I_clk),
        .img  (img_sel),
        .line (line),                 // 表只有 2 位行号
        .col  (col[5:0]),             // 表只有 6 位列
        .code (tbl_code),
        .len  (tbl_len),

        .I_wr_clk    (I_txt_wr_clk),
        .I_wr_en     (I_txt_wr_en),
        .I_wr_addr   (I_txt_wr_addr),
        .I_wr_data   (I_txt_wr_data),
        .I_ch_wr_en  (I_ach_wr_en),
        .I_ch_wr_addr(I_ach_wr_addr),
        .I_ch_wr_data(I_ach_wr_data)
    );

    wire [10:0] len_w = {tbl_len, 4'b0000};

    wire in_cell = (x_d1 < {1'b0, len_w}) && (in_block);

    reg de_q,hs_q,vs_q,incell_q;
    reg [1:0] bg_q;
    reg [23:0] rgb_q;
    reg [3:0] gx_q,gy_q;
    always @(posedge I_clk or posedge I_rst)begin
        if(I_rst)begin de_q<=0;hs_q<=0;vs_q<=0;rgb_q<=0;incell_q<=0;gx_q<=0;gy_q<=0;bg_q<=0;end
        else begin
            de_q<=de_d1;hs_q<=hs_d1;vs_q<=vs_d1;rgb_q<=rgb_d1;
            incell_q<=in_cell & I_en & (I_img>=1 && I_img<=9);
            gx_q<=gx;gy_q<=gy;bg_q<=I_bg;
        end
    end

    wire [7:0] font_idx = tbl_code;
    wire [3:0] font_row = gy_q;

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        incell_d2;
    reg [3:0]  gx_d2;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            incell_d2 <= 1'b0; gx_d2 <= 4'd0;
        end else begin
            de_d2 <= de_q; hs_d2 <= hs_q; vs_d2 <= vs_q; rgb_d2 <= rgb_q;
            incell_d2 <= incell_q;     // 总开关在这里门控
            gx_d2 <= gx_q;
        end
    end

    wire [15:0] font_word;
    ad_font_rom u_font (
        .clk      (I_clk),
        .char_idx (font_idx),          // D2 拍地址
        .row      (font_row),          // D2 拍地址
        .rom_row  (font_word)          // D3 拍数据（与 gx_d2 同拍）
    );

    wire [3:0] bit_sel = 4'd15 - gx_d2;
    wire       pix_bit = font_word[bit_sel];

    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        cell_d3, txt_d3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            cell_d3 <= 1'b0; txt_d3 <= 1'b0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            cell_d3 <= incell_d2;
            txt_d3  <= incell_d2 & pix_bit;
        end
    end

    wire [15:0] b60_r = {1'd0, rgb_d3[23:16], 7'd0} + {4'd0, rgb_d3[23:16], 4'd0}
                      + {5'd0, rgb_d3[23:16], 3'd0} + {7'd0, rgb_d3[23:16], 1'd0};
    wire [15:0] b60_g = {1'd0, rgb_d3[15:8],  7'd0} + {4'd0, rgb_d3[15:8],  4'd0}
                      + {5'd0, rgb_d3[15:8],  3'd0} + {7'd0, rgb_d3[15:8],  1'd0};
    wire [15:0] b60_b = {1'd0, rgb_d3[7:0],   7'd0} + {4'd0, rgb_d3[7:0],   4'd0}
                      + {5'd0, rgb_d3[7:0],   3'd0} + {7'd0, rgb_d3[7:0],   1'd0};
    wire [23:0] bg_mix = {b60_r[15:8],               // R × 60%
                          b60_g[15:8],               // G × 60%
                          b60_b[15:8]};              // B × 60%
    wire [23:0] bg_col = (bg_q == 2'd2) ? C_BG_SOLID : bg_mix;
    wire        bg_on  = (bg_q != 2'd0) & cell_d3;

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;                       // 默认：底图
        if (bg_on) comp = bg_col;            // 背景条
        if (txt_d3) comp = C_TXT;            // 文字（最高）
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

`timescale 1ns / 1ps

module tran_label #(
    parameter H_ACTIVE  = 1280,
    parameter V_ACTIVE  = 720,

    // 字幕几何
    parameter [11:0] X_CTR   = 12'd640,   // 水平中心（1280/2）
    parameter [11:0] Y_TOP   = 12'd656,   // 字幕条顶边（底部 656..688，留 32px 边距）
    parameter [5:0]  GLYPH   = 6'd32,     // 字形 32×32
    parameter        CPITCH  = 32,        // 字距 = 32 = 2^5 取列用移位/位选
    parameter [2:0]  MAX_LEN = 3'd4,      // 单条最多 4 字（交叉淡化/水平擦除）

    // 计时
    parameter [7:0]  FRAMES_ON = 8'd90,   // 显示帧数（≈1.48s @60.6fps）

    // 配色
    parameter [23:0] C_TXT = 24'hFFFFFF,  // 文字：白
    parameter [23:0] C_BG  = 24'h000000   // 背景条：黑
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire I_suppress,
    input  wire [2:0]  I_tran_type,    // 0..5

    input  wire [31:0] I_font_word,    // D3 数据（地址后 1 拍有效）

    output wire [5:0]  O_font_idx,
    output wire [4:0]  O_font_row,
    output wire        O_label_on,     // 1 = 正在显示字幕（顶层据此让路给本模块）

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam [5:0] CN_BLANK  = 6'd38;   // 空格（现有空位，全 0 不画）
    localparam [5:0] CN_SHUN   = 6'd43;   // 瞬
    localparam [5:0] CN_QIE    = 6'd44;   // 切
    localparam [5:0] CN_JIAO   = 6'd45;   // 交
    localparam [5:0] CN_CHA    = 6'd46;   // 叉
    localparam [5:0] CN_DAN    = 6'd47;   // 淡
    localparam [5:0] CN_HUA    = 6'd48;   // 化
    localparam [5:0] CN_SHUI   = 6'd49;   // 水
    localparam [5:0] CN_PING   = 6'd50;   // 平
    localparam [5:0] CN_CA     = 6'd51;   // 擦
    localparam [5:0] CN_CHU    = 6'd52;   // 除
    localparam [5:0] CN_BAI    = 6'd53;   // 百
    localparam [5:0] CN_YE     = 6'd54;   // 叶
    localparam [5:0] CN_CHUANG = 6'd55;   // 窗
    localparam [5:0] CN_SHU    = 6'd56;   // 竖
    localparam [5:0] CN_TIAO   = 6'd57;   // 条
    localparam [5:0] CN_WANG   = 6'd58;   // 网
    localparam [5:0] CN_GE     = 6'd59;   // 格

    function [5:0] str_char;
        input [2:0] mode;
        input [1:0] col;
        begin
            case ({mode, col})
                {3'd0, 2'd0}: str_char = CN_SHUN;   // 瞬切
                {3'd0, 2'd1}: str_char = CN_QIE;
                {3'd0, 2'd2}: str_char = CN_BLANK;
                {3'd0, 2'd3}: str_char = CN_BLANK;

                {3'd1, 2'd0}: str_char = CN_JIAO;   // 交叉淡化
                {3'd1, 2'd1}: str_char = CN_CHA;
                {3'd1, 2'd2}: str_char = CN_DAN;
                {3'd1, 2'd3}: str_char = CN_HUA;

                {3'd2, 2'd0}: str_char = CN_SHUI;   // 水平擦除
                {3'd2, 2'd1}: str_char = CN_PING;
                {3'd2, 2'd2}: str_char = CN_CA;
                {3'd2, 2'd3}: str_char = CN_CHU;

                {3'd3, 2'd0}: str_char = CN_BAI;    // 百叶窗
                {3'd3, 2'd1}: str_char = CN_YE;
                {3'd3, 2'd2}: str_char = CN_CHUANG;
                {3'd3, 2'd3}: str_char = CN_BLANK;

                {3'd4, 2'd0}: str_char = CN_SHU;    // 竖条
                {3'd4, 2'd1}: str_char = CN_TIAO;
                {3'd4, 2'd2}: str_char = CN_BLANK;
                {3'd4, 2'd3}: str_char = CN_BLANK;

                {3'd5, 2'd0}: str_char = CN_WANG;   // 网格
                {3'd5, 2'd1}: str_char = CN_GE;
                {3'd5, 2'd2}: str_char = CN_BLANK;
                {3'd5, 2'd3}: str_char = CN_BLANK;

                default: str_char = CN_BLANK;
            endcase
        end
    endfunction

    function [2:0] str_len;
        input [2:0] mode;
        begin
            case (mode)
                3'd0: str_len = 3'd2;   // 瞬切
                3'd1: str_len = 3'd4;   // 交叉淡化
                3'd2: str_len = 3'd4;   // 水平擦除
                3'd3: str_len = 3'd3;   // 百叶窗
                3'd4: str_len = 3'd2;   // 竖条
                3'd5: str_len = 3'd2;   // 网格
                default: str_len = 3'd0;
            endcase
        end
    endfunction

    reg        vs_d1;
    wire       vs_fall = vs_d1 & ~I_vs;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) vs_d1 <= 1'b0;
        else       vs_d1 <= I_vs;
    end

    reg [2:0]  tran_d;        // 上一拍的转场方式
    reg [2:0]  label_mode;    // 锁存要显示的方式
    reg [7:0]  frame_cnt;     // 已显示帧数
    reg        label_on_r;    // 1 = 正在显示
    reg [1:0]  warmup_cnt;    // 上电后先跳过 2 帧（见下）

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            tran_d     <= 3'd0;
            label_mode <= 3'd0;
            frame_cnt  <= 8'd0;
            label_on_r <= 1'b0;
            warmup_cnt <= 2'd0;
        end else begin
            tran_d <= I_tran_type;

            if(I_suppress) begin
                label_on_r<=0;frame_cnt<=0;label_mode<=I_tran_type;
                warmup_cnt<=2;
            end else if (warmup_cnt != 2'd2) begin
                if (vs_fall) warmup_cnt <= warmup_cnt + 2'd1;
                label_on_r <= 1'b0;
                frame_cnt  <= 8'd0;
            end else if (I_tran_type != tran_d) begin

                label_mode <= I_tran_type;
                frame_cnt  <= 8'd0;
                label_on_r <= 1'b1;
            end else if (vs_fall && label_on_r) begin
                if (frame_cnt >= FRAMES_ON - 8'd1)
                    label_on_r <= 1'b0;
                else
                    frame_cnt <= frame_cnt + 8'd1;
            end
        end
    end

    wire [2:0] mode  = label_mode;
    wire       l_on  = label_on_r;
    wire [2:0] nlen  = str_len(mode);        // 当前方式名长度（字数）

    wire [11:0] label_w = {4'd0, nlen, 5'b00000};          // len×32，max 128
    wire [11:0] start_x = X_CTR - {5'd0, nlen, 4'b0000};   // 640 − len×16

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

    reg        de_d1, hs_d1, vs_d1_2;
    reg [23:0] rgb_d1;
    reg [11:0] x_d1, y_d1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d1 <= 1'b0; hs_d1 <= 1'b0; vs_d1_2 <= 1'b0; rgb_d1 <= 24'd0;
            x_d1 <= 12'd0; y_d1 <= 12'd0;
        end else begin
            de_d1 <= I_de; hs_d1 <= I_hs; vs_d1_2 <= I_vs; rgb_d1 <= I_rgb;
            x_d1 <= x_now - start_x;
            y_d1 <= y_now - Y_TOP;
        end
    end

    wire [1:0]  col   = x_d1[6:5];      // x_d1/32，0..3（有效区内 x_d1<128）
    wire [4:0]  gx    = x_d1[4:0];      // 字形内列 0..31
    wire [4:0]  gy    = y_d1[4:0];      // 字形内行 0..31（y_d1<32 才有效）

    wire        in_cell = l_on && (x_d1 < label_w) && (y_d1 < {6'd0, GLYPH});

    assign O_font_idx = str_char(mode, col);
    assign O_font_row = gy;
    assign O_label_on = l_on;

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        incell_d2;
    reg [4:0]  gx_d2;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            incell_d2 <= 1'b0; gx_d2 <= 5'd0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1_2; rgb_d2 <= rgb_d1;
            incell_d2 <= in_cell;
            gx_d2     <= gx;
        end
    end

    wire [4:0] bit_sel = 5'd31 - gx_d2;
    wire       pix_bit = I_font_word[bit_sel];

    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        cell_d3, txt_d3;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            cell_d3 <= 1'b0; txt_d3 <= 1'b0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            cell_d3 <= incell_d2;
            txt_d3  <= incell_d2 & pix_bit;
        end
    end

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;                       // 默认：底图
        if (cell_d3) begin
            comp = C_BG;                     // 背景条（黑）
            if (txt_d3) comp = C_TXT;        // 文字（白）
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
