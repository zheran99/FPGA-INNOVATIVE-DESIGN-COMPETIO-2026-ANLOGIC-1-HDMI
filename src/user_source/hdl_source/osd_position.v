`timescale 1ns/1ps

module osd_position #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
)(
    input  wire        clk,          // video_clk (75 MHz)
    input  wire        rst,
    input  wire        de,           // 高有效
    input  wire        vs,           // 正极性（1 = 垂直同步脉冲）
    output wire [11:0] x,            // 0..H_ACTIVE-1（de=1 期间有效）
    output wire [11:0] y,            // 0..V_ACTIVE-1 （de=1 期间有效）
    output wire        pos_vld       // de（坐标有效标志，供下游门控）
);

    localparam [11:0] X_TOP_BAR  = 12'd0,    Y_TOP_BAR  = 12'd8,
                      W_TOP_BAR  = 12'd1280, H_TOP_BAR  = 12'd16;

    localparam [11:0] X_SUB_TOP  = 12'd320,  Y_SUB_TOP  = 12'd0,
                      W_SUB_TOP  = 12'd640,  H_SUB_TOP  = 12'd64;

    localparam [11:0] X_SUB_BOT  = 12'd320,  Y_SUB_BOT  = 12'd656,
                      W_SUB_BOT  = 12'd640,  H_SUB_BOT  = 12'd64;

    localparam [11:0] X_SUB_BR   = 12'd620,  Y_SUB_BR   = 12'd656,
                      W_SUB_BR   = 12'd660,  H_SUB_BR   = 12'd64;

    localparam [11:0] X_SPECTRUM = 12'd0,    Y_SPECTRUM = 12'd585,
                      W_SPECTRUM = 12'd320,  H_SPECTRUM = 12'd90;

    localparam [11:0] X_PANEL    = 12'd0,    Y_PANEL    = 12'd585,
                      W_PANEL    = 12'd1280, H_PANEL    = 12'd90;

    // 边沿检测

    reg de_d, vs_d;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            de_d <= 1'b0;
            vs_d <= 1'b0;
        end else begin
            de_d <= de;
            vs_d <= vs;
        end
    end
    wire de_fall = de_d & ~de;      // 一个有效行的结束
    wire vs_rise = vs  & ~vs_d;     // 帧同步脉冲开始 新一帧

    reg [11:0] x_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            x_r <= 12'd0;
        else if (!de)
            x_r <= 12'd0;           // 消隐期清零（与 de 同拍，无额外延迟）
        else
            x_r <= x_r + 12'd1;
    end

    reg [11:0] y_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            y_r <= 12'd0;
        else if (vs_rise)
            y_r <= 12'd0;           // 新一帧
        else if (de_fall)
            y_r <= y_r + 12'd1;     // 一行结束
    end

    assign x       = x_r;
    assign y       = y_r;
    assign pos_vld = de;            // 直通，不引入延迟

endmodule
