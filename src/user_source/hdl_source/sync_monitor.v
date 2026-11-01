`timescale 1ns/1ps

module sync_monitor #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,

    parameter X0   = 16,      // 面板左起
    parameter Y0   = 8,       // 面板上起
    parameter COLS = 12,      // 列数（16 px/列 192 px）
    parameter ROWS = 6,       // 行数（16 px/行 96 px）
    parameter ALIGN_ON = 1,   // 1 = 第一个 vs 时把两条计数一起归零（见 §）
    parameter CW   = 16,      // 字符格宽（= 字形宽，1:1）
    parameter ROWH = 16,      // 字符格高（= 字形高，1:1）
    parameter TB   = 1,       // 边框厚度

    // 配色
    parameter [23:0] C_BORD = 24'h40C0FF,   // 青边框
                     C_FILL = 24'h001018,   // 近黑填充
                     C_TXT  = 24'hFFFFFF,   // 白字
                     C_OK   = 24'h20FF40,   // 绿：锁定
                     C_BAD  = 24'hFF3020    // 红：失锁
)(
    input  wire        I_clk,          // video_clk
    input  wire        I_rst,

    input  wire        I_de,
    input  wire        I_hs,
    input  wire        I_vs,
    input  wire [23:0] I_rgb,

    input  wire        I_en,           // 1 = 显示（P5 或 P8 且"监视"=开）

    input  wire [23:0] I_frame,
    input  wire        I_aud_valid,    // 48 kHz 样本有效脉冲（video_clk 域）
    input  wire        I_paused,       // 1 = 音乐暂停
    input  wire        I_aud_undr,     // 1 = 音频 FIFO 欠载
    input  wire [4:0]  I_img_idx,      // 当前图片序号 1..16
    input  wire [4:0]  I_img_total,    // 卡上总张数 0..16
    input  wire [7:0]  I_vol,          // 音量 0..100
    input  wire        I_auto_on,

    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb
);

    localparam X_END = X0 + COLS * CW + 2 * TB;     // 16 + 192 + 2 = 210
    localparam Y_END = Y0 + ROWS * ROWH + 2 * TB;   // 8 + 96 + 2 = 106

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
            inpanel_d1 <= inpanel_now & I_en;   // I_en 在这里就并进来，后面各拍只传一个标志
        end
    end

    wire [11:0] pxi = px_d1 - TB[11:0];      // 字格区坐标（已去掉左边框）
    wire [11:0] pyi = py_d1 - TB[11:0];      // （已去掉上边框）

    wire        inner = (pxi < (COLS * CW)) && (pyi < (ROWS * ROWH));
    wire        bord  = inpanel_d1 && !inner;

    wire [3:0] col = pxi[7:4];     // 0..11（192/16 = 12 4 位）
    wire [2:0] row = pyi[6:4];     // 0..5 （ 96/16 = 6 3 位）

    wire [3:0] gx = pxi[3:0];      // 0..15
    wire [3:0] gy = pyi[3:0];      // 0..15

    reg        vs_d;
    wire       vs_rise = I_vs & ~vs_d;

    reg        algn_done;
    reg        aud_seen;
    wire       algn = vs_rise & ~algn_done & aud_seen & ~I_paused;
    wire       algn_act = algn & (ALIGN_ON != 0);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)          vs_d <= 1'b0;     // 漏了这句会让 vs_rise 恒为 x
        else                vs_d <= I_vs;
    end

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)        algn_done <= 1'b0;
        else if (algn)    algn_done <= 1'b1;
    end

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)            aud_seen <= 1'b0;
        else if (I_aud_valid) aud_seen <= 1'b1;
    end

    wire aud_step = I_aud_valid & ~I_paused;
    wire vid_step = vs_rise      & ~I_paused;

    function [4:0] bcd_digit_0;
        input [3:0] digit;input carry;
        begin case({carry,digit})
            5'd0:bcd_digit_0=5'd0;
            5'd1:bcd_digit_0=5'd1;
            5'd2:bcd_digit_0=5'd2;
            5'd3:bcd_digit_0=5'd3;
            5'd4:bcd_digit_0=5'd4;
            5'd5:bcd_digit_0=5'd5;
            5'd6:bcd_digit_0=5'd6;
            5'd7:bcd_digit_0=5'd7;
            5'd8:bcd_digit_0=5'd8;
            5'd9:bcd_digit_0=5'd9;
            5'd10:bcd_digit_0=5'd16;
            5'd11:bcd_digit_0=5'd17;
            5'd12:bcd_digit_0=5'd18;
            5'd13:bcd_digit_0=5'd19;
            5'd14:bcd_digit_0=5'd20;
            5'd15:bcd_digit_0=5'd21;
            5'd16:bcd_digit_0=5'd1;
            5'd17:bcd_digit_0=5'd2;
            5'd18:bcd_digit_0=5'd3;
            5'd19:bcd_digit_0=5'd4;
            5'd20:bcd_digit_0=5'd5;
            5'd21:bcd_digit_0=5'd6;
            5'd22:bcd_digit_0=5'd7;
            5'd23:bcd_digit_0=5'd8;
            5'd24:bcd_digit_0=5'd9;
            5'd25:bcd_digit_0=5'd16;
            5'd26:bcd_digit_0=5'd17;
            5'd27:bcd_digit_0=5'd18;
            5'd28:bcd_digit_0=5'd19;
            5'd29:bcd_digit_0=5'd20;
            5'd30:bcd_digit_0=5'd21;
            5'd31:bcd_digit_0=5'd22;
            default:bcd_digit_0=5'd0;
        endcase end
    endfunction
    function [4:0] bcd_digit_1;
        input [3:0] digit;input carry;
        begin case({carry,digit})
            5'd0:bcd_digit_1=5'd1;
            5'd1:bcd_digit_1=5'd2;
            5'd2:bcd_digit_1=5'd3;
            5'd3:bcd_digit_1=5'd4;
            5'd4:bcd_digit_1=5'd5;
            5'd5:bcd_digit_1=5'd6;
            5'd6:bcd_digit_1=5'd7;
            5'd7:bcd_digit_1=5'd8;
            5'd8:bcd_digit_1=5'd9;
            5'd9:bcd_digit_1=5'd16;
            5'd10:bcd_digit_1=5'd17;
            5'd11:bcd_digit_1=5'd18;
            5'd12:bcd_digit_1=5'd19;
            5'd13:bcd_digit_1=5'd20;
            5'd14:bcd_digit_1=5'd21;
            5'd15:bcd_digit_1=5'd22;
            5'd16:bcd_digit_1=5'd2;
            5'd17:bcd_digit_1=5'd3;
            5'd18:bcd_digit_1=5'd4;
            5'd19:bcd_digit_1=5'd5;
            5'd20:bcd_digit_1=5'd6;
            5'd21:bcd_digit_1=5'd7;
            5'd22:bcd_digit_1=5'd8;
            5'd23:bcd_digit_1=5'd9;
            5'd24:bcd_digit_1=5'd16;
            5'd25:bcd_digit_1=5'd17;
            5'd26:bcd_digit_1=5'd18;
            5'd27:bcd_digit_1=5'd19;
            5'd28:bcd_digit_1=5'd20;
            5'd29:bcd_digit_1=5'd21;
            5'd30:bcd_digit_1=5'd22;
            5'd31:bcd_digit_1=5'd23;
            default:bcd_digit_1=5'd0;
        endcase end
    endfunction
    function [4:0] bcd_digit_2;
        input [3:0] digit;input carry;
        begin case({carry,digit})
            5'd0:bcd_digit_2=5'd2;
            5'd1:bcd_digit_2=5'd3;
            5'd2:bcd_digit_2=5'd4;
            5'd3:bcd_digit_2=5'd5;
            5'd4:bcd_digit_2=5'd6;
            5'd5:bcd_digit_2=5'd7;
            5'd6:bcd_digit_2=5'd8;
            5'd7:bcd_digit_2=5'd9;
            5'd8:bcd_digit_2=5'd16;
            5'd9:bcd_digit_2=5'd17;
            5'd10:bcd_digit_2=5'd18;
            5'd11:bcd_digit_2=5'd19;
            5'd12:bcd_digit_2=5'd20;
            5'd13:bcd_digit_2=5'd21;
            5'd14:bcd_digit_2=5'd22;
            5'd15:bcd_digit_2=5'd23;
            5'd16:bcd_digit_2=5'd3;
            5'd17:bcd_digit_2=5'd4;
            5'd18:bcd_digit_2=5'd5;
            5'd19:bcd_digit_2=5'd6;
            5'd20:bcd_digit_2=5'd7;
            5'd21:bcd_digit_2=5'd8;
            5'd22:bcd_digit_2=5'd9;
            5'd23:bcd_digit_2=5'd16;
            5'd24:bcd_digit_2=5'd17;
            5'd25:bcd_digit_2=5'd18;
            5'd26:bcd_digit_2=5'd19;
            5'd27:bcd_digit_2=5'd20;
            5'd28:bcd_digit_2=5'd21;
            5'd29:bcd_digit_2=5'd22;
            5'd30:bcd_digit_2=5'd23;
            5'd31:bcd_digit_2=5'd24;
            default:bcd_digit_2=5'd0;
        endcase end
    endfunction
    function [4:0] bcd_digit_7;
        input [3:0] digit;input carry;
        begin case({carry,digit})
            5'd0:bcd_digit_7=5'd7;
            5'd1:bcd_digit_7=5'd8;
            5'd2:bcd_digit_7=5'd9;
            5'd3:bcd_digit_7=5'd16;
            5'd4:bcd_digit_7=5'd17;
            5'd5:bcd_digit_7=5'd18;
            5'd6:bcd_digit_7=5'd19;
            5'd7:bcd_digit_7=5'd20;
            5'd8:bcd_digit_7=5'd21;
            5'd9:bcd_digit_7=5'd22;
            5'd10:bcd_digit_7=5'd23;
            5'd11:bcd_digit_7=5'd24;
            5'd12:bcd_digit_7=5'd25;
            5'd13:bcd_digit_7=5'd26;
            5'd14:bcd_digit_7=5'd27;
            5'd15:bcd_digit_7=5'd28;
            5'd16:bcd_digit_7=5'd8;
            5'd17:bcd_digit_7=5'd9;
            5'd18:bcd_digit_7=5'd16;
            5'd19:bcd_digit_7=5'd17;
            5'd20:bcd_digit_7=5'd18;
            5'd21:bcd_digit_7=5'd19;
            5'd22:bcd_digit_7=5'd20;
            5'd23:bcd_digit_7=5'd21;
            5'd24:bcd_digit_7=5'd22;
            5'd25:bcd_digit_7=5'd23;
            5'd26:bcd_digit_7=5'd24;
            5'd27:bcd_digit_7=5'd25;
            5'd28:bcd_digit_7=5'd26;
            5'd29:bcd_digit_7=5'd27;
            5'd30:bcd_digit_7=5'd28;
            5'd31:bcd_digit_7=5'd29;
            default:bcd_digit_7=5'd0;
        endcase end
    endfunction
    function [4:0] bcd_digit_9;
        input [3:0] digit;input carry;
        begin case({carry,digit})
            5'd0:bcd_digit_9=5'd9;
            5'd1:bcd_digit_9=5'd16;
            5'd2:bcd_digit_9=5'd17;
            5'd3:bcd_digit_9=5'd18;
            5'd4:bcd_digit_9=5'd19;
            5'd5:bcd_digit_9=5'd20;
            5'd6:bcd_digit_9=5'd21;
            5'd7:bcd_digit_9=5'd22;
            5'd8:bcd_digit_9=5'd23;
            5'd9:bcd_digit_9=5'd24;
            5'd10:bcd_digit_9=5'd25;
            5'd11:bcd_digit_9=5'd26;
            5'd12:bcd_digit_9=5'd27;
            5'd13:bcd_digit_9=5'd28;
            5'd14:bcd_digit_9=5'd29;
            5'd15:bcd_digit_9=5'd30;
            5'd16:bcd_digit_9=5'd16;
            5'd17:bcd_digit_9=5'd17;
            5'd18:bcd_digit_9=5'd18;
            5'd19:bcd_digit_9=5'd19;
            5'd20:bcd_digit_9=5'd20;
            5'd21:bcd_digit_9=5'd21;
            5'd22:bcd_digit_9=5'd22;
            5'd23:bcd_digit_9=5'd23;
            5'd24:bcd_digit_9=5'd24;
            5'd25:bcd_digit_9=5'd25;
            5'd26:bcd_digit_9=5'd26;
            5'd27:bcd_digit_9=5'd27;
            5'd28:bcd_digit_9=5'd28;
            5'd29:bcd_digit_9=5'd29;
            5'd30:bcd_digit_9=5'd30;
            5'd31:bcd_digit_9=5'd31;
            default:bcd_digit_9=5'd0;
        endcase end
    endfunction

    reg [3:0] ad0, ad1, ad2, ad3, ad4, ad5, ad6, ad7;   // 音
    reg [3:0] vd0, vd1, vd2, vd3, vd4, vd5, vd6, vd7;   // 画

    wire [7:0] vg,vp;
    assign vg[0]=vd0>=4'd8;
    assign vp[0]=vd0==4'd7;
    assign vg[1]=vd1>=4'd1;
    assign vp[1]=vd1==4'd0;
    assign vg[2]=vd2>=4'd3;
    assign vp[2]=vd2==4'd2;
    assign vg[3]=vd3>=4'd10;
    assign vp[3]=vd3==4'd9;
    assign vg[4]=vd4>=4'd10;
    assign vp[4]=vd4==4'd9;
    assign vg[5]=vd5>=4'd10;
    assign vp[5]=vd5==4'd9;
    assign vg[6]=vd6>=4'd10;
    assign vp[6]=vd6==4'd9;
    assign vg[7]=vd7>=4'd10;
    assign vp[7]=vd7==4'd9;
    wire vc0=1'b0;
    wire [4:0] w0=bcd_digit_2(vd0,vc0);
    wire vc1=(vg[0]);
    wire [4:0] w1=bcd_digit_9(vd1,vc1);
    wire vc2=(vg[0] & vp[1]) | (vg[1]);
    wire [4:0] w2=bcd_digit_7(vd2,vc2);
    wire vc3=(vg[0] & vp[1] & vp[2]) | (vg[1] & vp[2]) | (vg[2]);
    wire [4:0] w3=bcd_digit_0(vd3,vc3);
    wire vc4=(vg[0] & vp[1] & vp[2] & vp[3]) | (vg[1] & vp[2] & vp[3]) | (vg[2] & vp[3]) | (vg[3]);
    wire [4:0] w4=bcd_digit_0(vd4,vc4);
    wire vc5=(vg[0] & vp[1] & vp[2] & vp[3] & vp[4]) | (vg[1] & vp[2] & vp[3] & vp[4]) | (vg[2] & vp[3] & vp[4]) | (vg[3] & vp[4]) | (vg[4]);
    wire [4:0] w5=bcd_digit_0(vd5,vc5);
    wire vc6=(vg[0] & vp[1] & vp[2] & vp[3] & vp[4] & vp[5]) | (vg[1] & vp[2] & vp[3] & vp[4] & vp[5]) | (vg[2] & vp[3] & vp[4] & vp[5]) | (vg[3] & vp[4] & vp[5]) | (vg[4] & vp[5]) | (vg[5]);
    wire [4:0] w6=bcd_digit_0(vd6,vc6);
    wire vc7=(vg[0] & vp[1] & vp[2] & vp[3] & vp[4] & vp[5] & vp[6]) | (vg[1] & vp[2] & vp[3] & vp[4] & vp[5] & vp[6]) | (vg[2] & vp[3] & vp[4] & vp[5] & vp[6]) | (vg[3] & vp[4] & vp[5] & vp[6]) | (vg[4] & vp[5] & vp[6]) | (vg[5] & vp[6]) | (vg[6]);
    wire [4:0] w7=bcd_digit_0(vd7,vc7);
    wire [7:0] ag,ap;
    assign ag[0]=ad0>=4'd9;
    assign ap[0]=ad0==4'd8;
    assign ag[1]=ad1>=4'd10;
    assign ap[1]=ad1==4'd9;
    assign ag[2]=ad2>=4'd10;
    assign ap[2]=ad2==4'd9;
    assign ag[3]=ad3>=4'd10;
    assign ap[3]=ad3==4'd9;
    assign ag[4]=ad4>=4'd10;
    assign ap[4]=ad4==4'd9;
    assign ag[5]=ad5>=4'd10;
    assign ap[5]=ad5==4'd9;
    assign ag[6]=ad6>=4'd10;
    assign ap[6]=ad6==4'd9;
    assign ag[7]=ad7>=4'd10;
    assign ap[7]=ad7==4'd9;
    wire ac0=1'b0;
    wire [4:0] as0=bcd_digit_1(ad0,ac0);
    wire ac1=(ag[0]);
    wire [4:0] as1=bcd_digit_0(ad1,ac1);
    wire ac2=(ag[0] & ap[1]) | (ag[1]);
    wire [4:0] as2=bcd_digit_0(ad2,ac2);
    wire ac3=(ag[0] & ap[1] & ap[2]) | (ag[1] & ap[2]) | (ag[2]);
    wire [4:0] as3=bcd_digit_0(ad3,ac3);
    wire ac4=(ag[0] & ap[1] & ap[2] & ap[3]) | (ag[1] & ap[2] & ap[3]) | (ag[2] & ap[3]) | (ag[3]);
    wire [4:0] as4=bcd_digit_0(ad4,ac4);
    wire ac5=(ag[0] & ap[1] & ap[2] & ap[3] & ap[4]) | (ag[1] & ap[2] & ap[3] & ap[4]) | (ag[2] & ap[3] & ap[4]) | (ag[3] & ap[4]) | (ag[4]);
    wire [4:0] as5=bcd_digit_0(ad5,ac5);
    wire ac6=(ag[0] & ap[1] & ap[2] & ap[3] & ap[4] & ap[5]) | (ag[1] & ap[2] & ap[3] & ap[4] & ap[5]) | (ag[2] & ap[3] & ap[4] & ap[5]) | (ag[3] & ap[4] & ap[5]) | (ag[4] & ap[5]) | (ag[5]);
    wire [4:0] as6=bcd_digit_0(ad6,ac6);
    wire ac7=(ag[0] & ap[1] & ap[2] & ap[3] & ap[4] & ap[5] & ap[6]) | (ag[1] & ap[2] & ap[3] & ap[4] & ap[5] & ap[6]) | (ag[2] & ap[3] & ap[4] & ap[5] & ap[6]) | (ag[3] & ap[4] & ap[5] & ap[6]) | (ag[4] & ap[5] & ap[6]) | (ag[5] & ap[6]) | (ag[6]);
    wire [4:0] as7=bcd_digit_0(ad7,ac7);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            {ad7, ad6, ad5, ad4, ad3, ad2, ad1, ad0} <= 32'd0;
        end else if (algn_act) begin

            {ad7, ad6, ad5, ad4, ad3, ad2, ad1, ad0}
                <= {vd7, vd6, vd5, vd4, vd3, vd2, vd1, vd0};
        end else if (aud_step) begin
            ad0 <= as0[3:0]; ad1 <= as1[3:0]; ad2 <= as2[3:0]; ad3 <= as3[3:0];
            ad4 <= as4[3:0]; ad5 <= as5[3:0]; ad6 <= as6[3:0]; ad7 <= as7[3:0];
        end
    end

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            {vd7, vd6, vd5, vd4, vd3, vd2, vd1, vd0} <= 32'd0;
        end else if (vid_step) begin
            vd0 <= w0[3:0]; vd1 <= w1[3:0]; vd2 <= w2[3:0]; vd3 <= w3[3:0];
            vd4 <= w4[3:0]; vd5 <= w5[3:0]; vd6 <= w6[3:0]; vd7 <= w7[3:0];
        end
    end

    reg [3:0] vs_div;

    wire disp_upd = vs_rise & (vs_div == 4'd15);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)        vs_div <= 4'd0;
        else if (vs_rise) vs_div <= vs_div + 4'd1;
    end

    reg [3:0] sa0, sa1, sa2, sa3, sa4, sa5, sa6, sa7;   // 音（显示值）
    reg [3:0] sv0, sv1, sv2, sv3, sv4, sv5, sv6, sv7;   // 画
    reg [3:0] d_dif;                                    // |音 − 画| 饱和 9
    reg       d_bad;                                    // 1 = 失锁

    wire [6:0] a10 = {ad1, 3'b000} + {ad1, 1'b0} + {3'b000, ad0};   // 0..99
    wire [6:0] v10 = {vd1, 3'b000} + {vd1, 1'b0} + {3'b000, vd0};   // 0..99
    wire [7:0] dif8 = {1'b0, a10} + 8'd100 - {1'b0, v10};           // 1..199
    wire       dif_neg = (dif8 < 8'd100);
    wire [7:0] dif_mag = dif_neg ? (8'd100 - dif8) : (dif8 - 8'd100);

    wire hi_same = ({ad7, ad6, ad5, ad4, ad3, ad2} ==
                    {vd7, vd6, vd5, vd4, vd3, vd2});

    wire lock_ok = hi_same && (dif_mag <= 8'd1);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            {sa7, sa6, sa5, sa4, sa3, sa2, sa1, sa0} <= 32'd0;
            {sv7, sv6, sv5, sv4, sv3, sv2, sv1, sv0} <= 32'd0;
            d_dif <= 4'd0; d_bad <= 1'b0;
        end else if (disp_upd) begin
            {sa7, sa6, sa5, sa4, sa3, sa2, sa1, sa0}
                <= {ad7, ad6, ad5, ad4, ad3, ad2, ad1, ad0};
            {sv7, sv6, sv5, sv4, sv3, sv2, sv1, sv0}
                <= {vd7, vd6, vd5, vd4, vd3, vd2, vd1, vd0};
            d_dif <= (dif_mag <= 8'd1) ? 4'd0 :              // ≤1 个样本视为 ０
                     ((dif_mag > 8'd9) ? 4'd9 : dif_mag[3:0]);
            d_bad <= ~lock_ok;
        end
    end

    localparam [5:0] CN_YIN    = 6'd0;    // 音
    localparam [5:0] CN_HUA    = 6'd1;    // 画
    localparam [5:0] CN_TONG   = 6'd2;    // 同
    localparam [5:0] CN_BU     = 6'd3;    // 步
    localparam [5:0] CN_CHA    = 6'd4;    // 差
    localparam [5:0] CN_SUO    = 6'd5;    // 锁
    localparam [5:0] CN_DING   = 6'd6;    // 定
    localparam [5:0] CN_SHI    = 6'd7;    // 失
    localparam [5:0] CN_D0     = 6'd8;    // ０
    localparam [5:0] CN_D1     = 6'd9;    // １
    localparam [5:0] CN_D2     = 6'd10;   // ２
    localparam [5:0] CN_D3     = 6'd11;   // ３
    localparam [5:0] CN_D4     = 6'd12;   // ４
    localparam [5:0] CN_D5     = 6'd13;   // ５
    localparam [5:0] CN_D6     = 6'd14;   // ６
    localparam [5:0] CN_D7     = 6'd15;   // ７
    localparam [5:0] CN_D8     = 6'd16;   // ８
    localparam [5:0] CN_D9     = 6'd17;   // ９
    localparam [5:0] CN_BLKF   = 6'd18;   // ■
    localparam [5:0] CN_BLKN   = 6'd19;   // □
    localparam [5:0] CN_LIANG  = 6'd20;   // 量
    localparam [5:0] CN_ZHUANG = 6'd21;   // 状
    localparam [5:0] CN_TAI    = 6'd22;   // 态
    localparam [5:0] CN_ZHENG  = 6'd23;   // 正
    localparam [5:0] CN_CHANG  = 6'd24;   // 常
    localparam [5:0] CN_QIAN   = 6'd25;   // 欠
    localparam [5:0] CN_ZAI    = 6'd26;   // 载
    localparam [5:0] CN_ZAN    = 6'd27;   // 暂
    localparam [5:0] CN_TING   = 6'd28;   // 停

    localparam CN_BLANK = 6'd63;

    // 行0 音画同步 cols 0..3

    wire [3:0] bar_k   = col - 4'd3;
    wire [6:0] bar_th  = {bar_k, 3'b000} + {1'b0, bar_k, 2'b00} + 7'd12;
    wire [6:0] vol7    = (I_vol > 8'd100) ? 7'd100 : I_vol[6:0];
    wire       bar_lit = (col >= 4'd3) && (col <= 4'd10) && (vol7 >= bar_th);

    wire st_pause = I_paused;
    wire st_undr  = !I_paused && I_aud_undr;

    reg [5:0] ch_c;
    always @(*) begin
        ch_c = CN_BLANK;
        case (row)
        3'd0: begin                                   // 音画同步
            if      (col == 4'd0) ch_c = CN_YIN;
            else if (col == 4'd1) ch_c = CN_HUA;
            else if (col == 4'd2) ch_c = CN_TONG;
            else if (col == 4'd3) ch_c = CN_BU;
        end
        3'd1: begin                                   // 音 ０００１２３４５
            if      (col == 4'd0) ch_c = CN_YIN;
            else if (col == 4'd2) ch_c = CN_D0 + sa7;
            else if (col == 4'd3) ch_c = CN_D0 + sa6;
            else if (col == 4'd4) ch_c = CN_D0 + sa5;
            else if (col == 4'd5) ch_c = CN_D0 + sa4;
            else if (col == 4'd6) ch_c = CN_D0 + sa3;
            else if (col == 4'd7) ch_c = CN_D0 + sa2;
            else if (col == 4'd8) ch_c = CN_D0 + sa1;
            else if (col == 4'd9) ch_c = CN_D0 + sa0;
        end
        3'd2: begin                                   // 画 ０００１２３４５
            if      (col == 4'd0) ch_c = CN_HUA;
            else if (col == 4'd2) ch_c = CN_D0 + sv7;
            else if (col == 4'd3) ch_c = CN_D0 + sv6;
            else if (col == 4'd4) ch_c = CN_D0 + sv5;
            else if (col == 4'd5) ch_c = CN_D0 + sv4;
            else if (col == 4'd6) ch_c = CN_D0 + sv3;
            else if (col == 4'd7) ch_c = CN_D0 + sv2;
            else if (col == 4'd8) ch_c = CN_D0 + sv1;
            else if (col == 4'd9) ch_c = CN_D0 + sv0;
        end
        3'd3: begin                                   // 差 ０ 锁定 / 失锁
            if      (col == 4'd0) ch_c = CN_CHA;
            else if (col == 4'd2) ch_c = CN_D0 + d_dif;
            else if (col == 4'd4) ch_c = d_bad ? CN_SHI : CN_SUO;
            else if (col == 4'd5) ch_c = d_bad ? CN_SUO : CN_DING;
        end
        3'd4: begin                                   // 音量 ■■■■■■□□
            if      (col == 4'd0) ch_c = CN_YIN;
            else if (col == 4'd1) ch_c = CN_LIANG;
            else if (bar_lit)     ch_c = CN_BLKF;
            else if ((col >= 4'd3) && (col <= 4'd10)) ch_c = CN_BLKN;
        end
        3'd5: begin                                   // 状态 正常/欠载/暂停
            if      (col == 4'd0) ch_c = CN_ZHUANG;
            else if (col == 4'd1) ch_c = CN_TAI;
            else if (col == 4'd3) ch_c = st_undr ? CN_QIAN :
                                         st_pause ? CN_ZAN : CN_ZHENG;
            else if (col == 4'd4) ch_c = st_undr ? CN_ZAI :
                                         st_pause ? CN_TING : CN_CHANG;
        end
        default: ch_c = CN_BLANK;
        endcase
    end

    reg        de_d2, hs_d2, vs_d2;
    reg [23:0] rgb_d2;
    reg        inpanel_d2, bord_d2;
    reg [3:0]  gx_d2, gy_d2;
    reg        lkcol_d2;             // 本像素落在「锁定」两格上
    reg        bad_d2;                 // 那时是否是失锁
    reg [5:0]  ch_d2;

    wire lkcol = (row == 3'd3) && (col >= 4'd4) && (col <= 4'd5);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d2 <= 1'b0; hs_d2 <= 1'b0; vs_d2 <= 1'b0; rgb_d2 <= 24'd0;
            inpanel_d2 <= 1'b0; bord_d2 <= 1'b0;
            gx_d2 <= 4'd0; gy_d2 <= 4'd0; ch_d2 <= CN_BLANK;
            lkcol_d2 <= 1'b0; bad_d2 <= 1'b0;
        end else begin
            de_d2 <= de_d1; hs_d2 <= hs_d1; vs_d2 <= vs_d1; rgb_d2 <= rgb_d1;
            inpanel_d2 <= inpanel_d1;
            bord_d2    <= bord;
            gx_d2      <= gx;
            gy_d2      <= gy;                // 与 ch_d2 同拍 字 + 行严格配对
            ch_d2      <= ch_c;              // D2 给字库地址
            lkcol_d2 <= lkcol;
            bad_d2     <= d_bad;
        end
    end

    wire [15:0] font_word;
    monitor_cn_font u_font (
        .clk       (I_clk),
        .char_idx  (ch_d2),
        .row       (gy_d2),
        .rom_row   (font_word)
    );

    reg [3:0]  gx_d3;
    reg        de_d3, hs_d3, vs_d3;
    reg [23:0] rgb_d3;
    reg        inpanel_d3, bord_d3;
    reg        lkcol_d3, bad_d3;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d3 <= 1'b0; hs_d3 <= 1'b0; vs_d3 <= 1'b0; rgb_d3 <= 24'd0;
            inpanel_d3 <= 1'b0; bord_d3 <= 1'b0; gx_d3 <= 4'd0;
            lkcol_d3 <= 1'b0; bad_d3 <= 1'b0;
        end else begin
            de_d3 <= de_d2; hs_d3 <= hs_d2; vs_d3 <= vs_d2; rgb_d3 <= rgb_d2;
            inpanel_d3 <= inpanel_d2;
            bord_d3    <= bord_d2;
            gx_d3      <= gx_d2;             // 与 font_word 同拍
            lkcol_d3 <= lkcol_d2;
            bad_d3     <= bad_d2;
        end
    end

    wire [3:0] bit_sel = 4'd15 - gx_d3;
    wire       pix_bit = font_word[bit_sel];

    reg [23:0] comp;
    always @(*) begin
        comp = rgb_d3;
        if (inpanel_d3) begin
            comp = C_FILL;
            if (bord_d3) comp = C_BORD;
            if (pix_bit) comp = (lkcol_d3 && bad_d3) ? C_BAD :
                                (lkcol_d3            ? C_OK  : C_TXT);
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
