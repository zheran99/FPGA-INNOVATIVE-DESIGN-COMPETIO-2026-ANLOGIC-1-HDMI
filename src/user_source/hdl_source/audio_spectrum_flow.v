`timescale 1ns/1ps

module audio_spectrum_flow (
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,
    input  wire        I_en,           // 使能（VS 上升沿生效，与老模式一致）
    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,
    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output reg  [23:0] O_rgb,

    input  wire [13:0] I_frame,

    output wire [9:0]  O_lv_addr,
    input  wire [7:0]  I_lv_data
);
    localparam [11:0] Y_TOP    = 12'd288;
    localparam [11:0] Y_BOTTOM = 12'd719;
    localparam [3:0]  GAP      = 4'd14;   // 每柱前 14 px 实心，后 2 px 缝

    // 帧同步使能

    reg vs_prev, active;
    wire frame_start = I_vs & ~vs_prev;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            vs_prev <= 1'b0;
            active  <= 1'b0;
        end else begin
            vs_prev <= I_vs;
            if (frame_start) active <= I_en;
        end
    end

    // 像素坐标

    wire [11:0] x, y;
    osd_position #(.H_ACTIVE(1280), .V_ACTIVE(720)) u_pos (
        .clk(I_clk), .rst(I_rst), .de(I_de), .vs(I_vs),
        .x(x), .y(y), .pos_vld()
    );

    wire        in_box = I_de && active && (y >= Y_TOP);
    wire [6:0]  bar    = x[10:4];              // 0..79
    wire        gap    = (x[3:0] >= GAP);      // 柱右侧 2 px 缝
    wire [7:0]  dist2  = (Y_BOTTOM - y) >> 1;  // 底 0 .. 顶 215

    assign O_lv_addr = {3'b000, bar};

    reg         box1, gap1;
    reg [7:0]   dist1;
    reg [10:0]  x1;
    reg [23:0]  rgb1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            box1 <= 1'b0; gap1 <= 1'b0; dist1 <= 8'd0; x1 <= 11'd0; rgb1 <= 24'd0;
        end else begin
            box1  <= in_box;
            gap1  <= gap;
            dist1 <= dist2;
            x1    <= x[10:0];
            rgb1  <= I_rgb;
        end
    end

    wire [7:0] lv     = I_lv_data;
    wire       in_bar = (dist1 <= lv) && (lv != 8'd0) && !gap1;

    wire [7:0] g_r = 8'd170 - {1'b0, x1[10:4]} - {2'b00, x1[10:5]};
    wire [7:0] g_g = 8'd90  + x1[10:3] - {4'd0, x1[10:7]};
    wire [7:0] g_b = 8'd240 - {2'b00, x1[10:6]} - {4'd0, x1[10:7]};
    wire [7:0] t_r = g_r >> 1;
    wire [7:0] t_g = g_g >> 1;
    wire [7:0] t_b = g_b >> 1;

    reg        box2, inbar2;
    reg [7:0]  tr2, tg2, tb2;
    reg [23:0] rgb2;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            box2 <= 1'b0; inbar2 <= 1'b0;
            tr2 <= 8'd0; tg2 <= 8'd0; tb2 <= 8'd0;
            rgb2 <= 24'd0;
        end else begin
            box2   <= box1;
            inbar2 <= in_bar;
            tr2    <= t_r;
            tg2    <= t_g;
            tb2    <= t_b;
            rgb2   <= rgb1;
        end
    end

    wire [8:0] sum_r = {1'b0, rgb2[23:16]} + {1'b0, tr2};
    wire [8:0] sum_g = {1'b0, rgb2[15:8]}  + {1'b0, tg2};
    wire [8:0] sum_b = {1'b0, rgb2[7:0]}   + {1'b0, tb2};
    wire [23:0] mixed = {sum_r[8] ? 8'hFF : sum_r[7:0],
                         sum_g[8] ? 8'hFF : sum_g[7:0],
                         sum_b[8] ? 8'hFF : sum_b[7:0]};

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)                O_rgb <= 24'd0;
        else if (box2 && inbar2)  O_rgb <= mixed;
        else                      O_rgb <= rgb2;
    end

    reg [2:0] de_d, hs_d, vs_d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d <= 3'd0; hs_d <= 3'd0; vs_d <= 3'd0;
        end else begin
            de_d <= {de_d[1:0], I_de};
            hs_d <= {hs_d[1:0], I_hs};
            vs_d <= {vs_d[1:0], I_vs};
        end
    end
    assign O_de = de_d[2];
    assign O_hs = hs_d[2];
    assign O_vs = vs_d[2];
endmodule
