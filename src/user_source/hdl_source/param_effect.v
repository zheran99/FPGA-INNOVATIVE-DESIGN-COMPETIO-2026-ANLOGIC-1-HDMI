`timescale 1ns / 1ps

module param_effect (
    input  wire        I_clk,          // video_clk（75 MHz）
    input  wire        I_rst,          // 高有效

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,          // {R[7:0], G[7:0], B[7:0]}

    input  wire [7:0]  I_bri,          // 亮度 0..100，默认 50
    input  wire [7:0]  I_con,          // 对比度 50..200，默认 100
    input  wire [7:0]  I_sat,          // 饱和度 0..200，默认 100

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam LATENCY = 6;

    reg [8:0]  con_g_r;      // 0..256（9 位）
    reg [8:0]  sat_g_r;      // 0..256
    reg signed [7:0] bri_o_r; // 100..+100

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            con_g_r <= 9'd128;      // 默认 1.0x
            sat_g_r <= 9'd128;
            bri_o_r <= 8'sd0;
        end else begin
            con_g_r <= (I_con * 17'd328) >> 8;    // 100 128
            sat_g_r <= (I_sat * 17'd328) >> 8;
            bri_o_r <= $signed({1'b0, I_bri}) - 8'sd50;   // 50..+50
        end
    end

    wire signed [8:0] bri_off = $signed(bri_o_r) * 9'sd2;

    wire [7:0] r_in = I_rgb[23:16];
    wire [7:0] g_in = I_rgb[15:8];
    wire [7:0] b_in = I_rgb[7:0];

    reg [5:0] de_d, hs_d, vs_d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d <= 6'd0;  hs_d <= 6'd0;  vs_d <= 6'd0;
        end else begin
            de_d <= {de_d[4:0], I_de};
            hs_d <= {hs_d[4:0], I_hs};
            vs_d <= {vs_d[4:0], I_vs};
        end
    end

    assign O_de = de_d[5];
    assign O_hs = hs_d[5];
    assign O_vs = vs_d[5];

    function [7:0] add_off;
        input [7:0]        v;
        input signed [8:0] off;
        reg   signed [9:0] t;
        begin
            t = $signed({1'b0, v}) + off;
            if      (t < 10'sd0)   add_off = 8'd0;
            else if (t > 10'sd255) add_off = 8'd255;
            else                   add_off = t[7:0];
        end
    endfunction

    reg [23:0] p1_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) p1_rgb <= 24'd0;
        else       p1_rgb <= {add_off(r_in, bri_off),
                              add_off(g_in, bri_off),
                              add_off(b_in, bri_off)};
    end

    wire signed [8:0] d2_r = $signed({1'b0, p1_rgb[23:16]}) - 9'sd128;
    wire signed [8:0] d2_g = $signed({1'b0, p1_rgb[15:8]})  - 9'sd128;
    wire signed [8:0] d2_b = $signed({1'b0, p1_rgb[7:0]})   - 9'sd128;

    wire signed [17:0] m2_r = d2_r * $signed({1'b0, con_g_r});
    wire signed [17:0] m2_g = d2_g * $signed({1'b0, con_g_r});
    wire signed [17:0] m2_b = d2_b * $signed({1'b0, con_g_r});

    reg signed [17:0] m2_r_r, m2_g_r, m2_b_r;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            m2_r_r <= 18'sd0;  m2_g_r <= 18'sd0;  m2_b_r <= 18'sd0;
        end else begin
            m2_r_r <= m2_r;    m2_g_r <= m2_g;    m2_b_r <= m2_b;
        end
    end

    function [7:0] con_finish;
        input signed [17:0] m;
        reg   signed [17:0] q;
        begin
            q = (m + 18'sd64) >>> 7;      // 128 带四舍五入
            q = q + 18'sd128;             // 加回中点
            if      (q < 18'sd0)   con_finish = 8'd0;
            else if (q > 18'sd255) con_finish = 8'd255;
            else                   con_finish = q[7:0];
        end
    endfunction

    reg [23:0] p3_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) p3_rgb <= 24'd0;
        else       p3_rgb <= {con_finish(m2_r_r),
                              con_finish(m2_g_r),
                              con_finish(m2_b_r)};
    end

    wire [15:0] gs_r = p3_rgb[23:16] * 16'd77;
    wire [15:0] gs_g = p3_rgb[15:8]  * 16'd150;
    wire [15:0] gs_b = p3_rgb[7:0]   * 16'd29;

    wire [15:0] gray_sum = gs_r + gs_g + gs_b;

    reg [7:0]  gray_r;
    reg [23:0] p4_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            gray_r <= 8'd0;
            p4_rgb <= 24'd0;
        end else begin
            gray_r <= gray_sum[15:8];    // >>8
            p4_rgb <= p3_rgb;            // 原色值同步延迟（与 gray_r 对齐）
        end
    end

    wire signed [9:0] d5_r = $signed({1'b0, p4_rgb[23:16]}) - $signed({1'b0, gray_r});
    wire signed [9:0] d5_g = $signed({1'b0, p4_rgb[15:8]})  - $signed({1'b0, gray_r});
    wire signed [9:0] d5_b = $signed({1'b0, p4_rgb[7:0]})   - $signed({1'b0, gray_r});

    wire signed [18:0] m5_r = d5_r * $signed({1'b0, sat_g_r});
    wire signed [18:0] m5_g = d5_g * $signed({1'b0, sat_g_r});
    wire signed [18:0] m5_b = d5_b * $signed({1'b0, sat_g_r});

    reg signed [18:0] m5_r_r, m5_g_r, m5_b_r;
    reg [7:0] gray_rr;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            m5_r_r <= 19'sd0;  m5_g_r <= 19'sd0;  m5_b_r <= 19'sd0;
            gray_rr <= 8'd0;
        end else begin
            m5_r_r <= m5_r;    m5_g_r <= m5_g;    m5_b_r <= m5_b;
            gray_rr <= gray_r;
        end
    end

    function [7:0] sat_finish;
        input signed [18:0] m;
        input [7:0]         gry;
        reg   signed [18:0] q;
        begin
            q = (m + 19'sd64) >>> 7;
            q = q + $signed({1'b0, gry});
            if      (q < 19'sd0)   sat_finish = 8'd0;
            else if (q > 19'sd255) sat_finish = 8'd255;
            else                   sat_finish = q[7:0];
        end
    endfunction

    reg [23:0] p6_rgb;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) p6_rgb <= 24'd0;
        else       p6_rgb <= {sat_finish(m5_r_r, gray_rr),
                              sat_finish(m5_g_r, gray_rr),
                              sat_finish(m5_b_r, gray_rr)};
    end

    assign O_rgb = de_d[5] ? p6_rgb : 24'd0;

endmodule
