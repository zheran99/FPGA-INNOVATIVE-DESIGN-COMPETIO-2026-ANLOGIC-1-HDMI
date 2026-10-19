`timescale 1ns/1ps

module logo_overlay #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter W  = 64,
    parameter AW = 6,            // 每轴地址位宽（W = 2^AW）

    parameter SCNT = 1,

    // 静止位置 / 弹移初速

    parameter [10:0] X_DEF = 11'd1120,   // 右下（贴右边，留 32 px）
    parameter [10:0] Y_DEF = 11'd520,    // 字幕带上方 8 px
    parameter [4:0]  VX0   = 5'd4,       // 像素/帧（有符号 5 位，可见值 0..15）
    parameter [4:0]  VY0   = 5'd3
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_en,           // 1 = 在 P6（允许叠加）
    input  wire [1:0]  I_mode,         // 0=静止 1=弹移 2=消失

    // Logo ROM
    output wire [2*AW-1:0] O_rom_addr,
    input  wire [15:0] I_rom_q,        // rgb565（0 = 透明），地址后 1 拍有效

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

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

    reg vs_d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) vs_d <= 1'b0;
        else       vs_d <= I_vs;
    end
    wire frame_start = I_vs & ~vs_d;

    // 位置与速度寄存器

    reg [10:0] logo_x, logo_y;
    reg [4:0]  vx, vy;                 // 有符号 5 位：bit4 = 负方向

    localparam [10:0] X_MAX = H_ACTIVE - (W << SCNT);   // 1152
    localparam [10:0] Y_MAX = V_ACTIVE - (W << SCNT);   // 592

    wire       vx_neg = vx[4];
    wire [4:0] vx_mag = vx_neg ? (~vx + 5'd1) : vx;
    wire       vy_neg = vy[4];
    wire [4:0] vy_mag = vy_neg ? (~vy + 5'd1) : vy;

    wire [11:0] mx12 = {7'd0, vx_mag};
    wire [11:0] my12 = {7'd0, vy_mag};

    wire x_lo = (logo_x < mx12);
    wire x_hi = (logo_x + mx12 > X_MAX);
    wire bounce_x = vx_neg ? x_lo : x_hi;
    wire y_lo = (logo_y < my12);
    wire y_hi = (logo_y + my12 > Y_MAX);
    wire bounce_y = vy_neg ? y_lo : y_hi;

    wire [11:0] x_step = vx_neg ? (logo_x - vx_mag) : (logo_x + vx_mag);
    wire [11:0] y_step = vy_neg ? (logo_y - vy_mag) : (logo_y + vy_mag);

    wire moving = I_en & (I_mode == 2'd1);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            logo_x <= X_DEF;
            logo_y <= Y_DEF;
            vx     <= VX0;
            vy     <= VY0;
        end else if (!moving) begin

            logo_x <= X_DEF;
            logo_y <= Y_DEF;
            vx     <= VX0;
            vy     <= VY0;
        end else if (frame_start) begin
            vx <= bounce_x ? (~vx + 5'd1) : vx;
            vy <= bounce_y ? (~vy + 5'd1) : vy;

            if (!bounce_x) logo_x <= x_step[10:0];
            if (!bounce_y) logo_y <= y_step[10:0];
        end
    end

    wire [11:0] lx = x_now - {1'b0, logo_x};
    wire [11:0] ly = y_now - {1'b0, logo_y};

    localparam [11:0] DISP12 = W << SCNT;          // 上屏边长 = 128
    wire        in_rect_now = (lx < DISP12) && (ly < DISP12);

    wire [AW-1:0] sx = lx[AW+SCNT-1:SCNT];
    wire [AW-1:0] sy = ly[AW+SCNT-1:SCNT];

    assign O_rom_addr = {sy, sx};

    reg        de_d1, hs_d1, vs_d1;
    reg [23:0] rgb_d1;
    reg        inrect_d1, en_d1;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d1 <= 1'b0; hs_d1 <= 1'b0; vs_d1 <= 1'b0;
            rgb_d1 <= 24'd0;
            inrect_d1 <= 1'b0; en_d1 <= 1'b0;
        end else begin
            de_d1     <= I_de;
            hs_d1     <= I_hs;
            vs_d1     <= I_vs;
            rgb_d1    <= I_rgb;
            inrect_d1 <= in_rect_now;
            en_d1     <= I_en & (I_mode != 2'd2);   // "消失"档 不叠加
        end
    end

    wire [4:0] lr5 = I_rom_q[15:11];
    wire [5:0] lg6 = I_rom_q[10:5];
    wire [4:0] lb5 = I_rom_q[4:0];
    wire [23:0] logo_rgb = {lr5, lr5[4:2], lg6, lg6[5:4], lb5, lb5[4:2]};

    wire        show  = inrect_d1 & (|I_rom_q) & en_d1;
    wire [23:0] mixed = show ? logo_rgb : rgb_d1;

    reg        o_de, o_hs, o_vs;
    reg [23:0] o_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            o_de <= 1'b0; o_hs <= 1'b0; o_vs <= 1'b0; o_rgb <= 24'd0;
        end else begin
            o_de <= de_d1; o_hs <= hs_d1; o_vs <= vs_d1; o_rgb <= mixed;
        end
    end

    assign O_de  = o_de;
    assign O_hs  = o_hs;
    assign O_vs  = o_vs;
    assign O_rgb = o_rgb;

endmodule
