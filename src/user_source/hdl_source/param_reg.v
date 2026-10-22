`timescale 1ns / 1ps

module param_reg #(
    parameter ROT_DEFAULT = 3'd2
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 key_ctrl
    input  wire [2:0]  I_key_short,     // {r, m, l} 短按单拍
    input  wire [2:0]  I_key_repeat,    // {r, m, l} 长按连发单拍（one-hot）

    // 来自 mode_decode
    input  wire [7:0]  I_mode_oh,       // {P8,...,P1}

    output reg         O_next_img,      // 下一张图片（P2/P3/P5 的 key_r）
    output reg         O_prev_img,      // 上一张图片（key_l）
    output reg         O_auto_toggle,   // 轮播开关切换（P2 的 key_m）

    output reg  [7:0]  O_bri,
    output reg  [7:0]  O_con,           // 对比度 50..200 默认 100
    output reg  [7:0]  O_sat,           // 饱和度 0..200 默认 100
    output reg  [7:0]  O_vol,           // 音量 0..100 默认 100
    output reg  [7:0]  O_irn,           // 没人亮度 0..100 默认 100（P8 触摸滑块调）
    output reg  [2:0]  O_rot,           // 轮播档位 0..4 默认 ROT_DEFAULT

    output reg  [2:0]  O_tran_type,     // 转场类型 0..5（默认 1=交叉淡化）
    output reg         O_tran_en,       // 转场开关（默认 1=开）

    // 供数码管显示
    output reg  [2:0]  O_param_item,    // 当前参数项编号 0..3
    output wire [15:0] O_param_val,     // 当前项的值（16 位够放 0..200）

    input  wire        I_u_wr,          // 1 拍写脉冲
    input  wire [3:0]  I_u_sel,
    input  wire [7:0]  I_u_val,         // 原始值（本模块负责钳位）
    input  wire        I_u_rset         // 恢复默认值
);

    // 参数项编号

    localparam ITEM_BRI   = 3'd0,
               ITEM_CON   = 3'd1,
               ITEM_SAT   = 3'd2,
               ITEM_VOL   = 3'd3,
               ITEM_LAST  = 3'd3;

    // 各项边界
    localparam BRI_MIN = 8'd0,   BRI_MAX = 8'd100, BRI_DEF = 8'd50;
    localparam CON_MIN = 8'd50,  CON_MAX = 8'd200, CON_DEF = 8'd100;
    localparam SAT_MIN = 8'd0,   SAT_MAX = 8'd200, SAT_DEF = 8'd100;
    localparam VOL_MIN = 8'd0,   VOL_MAX = 8'd100, VOL_DEF = 8'd100;
    localparam IRN_MIN = 8'd0,   IRN_MAX = 8'd100, IRN_DEF = 8'd100;

    localparam TRAN_TYPE_MIN = 3'd0, TRAN_TYPE_MAX = 3'd5, TRAN_TYPE_DEF = 3'd1;

    localparam [3:0] S_BRI = 4'd0, S_CON = 4'd1, S_SAT = 4'd2,
                     S_VOL = 4'd3, S_TRAN = 4'd4, S_TE = 4'd5, S_IRN = 4'd6;

    wire adj_dec = I_key_short[0] | I_key_repeat[0];   // key_l：减
    wire adj_inc = I_key_short[2] | I_key_repeat[2];   // key_r：加
    wire key_m_short = I_key_short[1];

    wire in_p4 = I_mode_oh[3];                      // P4 参数设置
    wire in_p3 = I_mode_oh[2];                      // P3 转场设置

    wire in_p5 = I_mode_oh[4];                      // P5 字幕设置

    wire in_p6 = I_mode_oh[5];                      // P6 Logo 行为
    wire in_p7 = I_mode_oh[6];                      // P7 waveform owns its keys

    // 主逻辑

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_bri        <= BRI_DEF;
            O_con        <= CON_DEF;
            O_sat        <= SAT_DEF;
            O_vol        <= VOL_DEF;
            O_irn        <= IRN_DEF;
            O_rot        <= ROT_DEFAULT;      // 固定默认值（不再可调）
            O_tran_type  <= TRAN_TYPE_DEF;    // 默认交叉淡化
            O_tran_en    <= 1'b1;             // 默认开
            O_param_item <= ITEM_BRI;
            O_next_img   <= 1'b0;
            O_prev_img   <= 1'b0;
            O_auto_toggle<= 1'b0;
        end
        else begin
            O_next_img    <= 1'b0;
            O_prev_img    <= 1'b0;
            O_auto_toggle <= 1'b0;

            if (in_p4) begin

                if (key_m_short) begin
                    if (O_param_item >= ITEM_LAST)
                        O_param_item <= ITEM_BRI;
                    else
                        O_param_item <= O_param_item + 1'b1;
                end

                if (adj_dec || adj_inc) begin
                    case (O_param_item)

                    ITEM_BRI: begin
                        if (adj_inc && O_bri < BRI_MAX) O_bri <= O_bri + 8'd1;
                        if (adj_dec && O_bri > BRI_MIN) O_bri <= O_bri - 8'd1;
                    end

                    ITEM_CON: begin
                        if (adj_inc && O_con <= (CON_MAX - 8'd2)) O_con <= O_con + 8'd2;
                        if (adj_dec && O_con >= (CON_MIN + 8'd2)) O_con <= O_con - 8'd2;
                    end

                    ITEM_SAT: begin
                        if (adj_inc && O_sat < SAT_MAX) O_sat <= O_sat + 8'd2;
                        if (adj_dec && O_sat > SAT_MIN) O_sat <= O_sat - 8'd2;
                    end

                    ITEM_VOL: begin
                        if (adj_inc && O_vol < VOL_MAX) O_vol <= O_vol >= VOL_MAX-8'd2 ? VOL_MAX : O_vol + 8'd2;
                        if (adj_dec && O_vol > VOL_MIN) O_vol <= O_vol <= VOL_MIN+8'd2 ? VOL_MIN : O_vol - 8'd2;
                    end

                    default: ;
                    endcase
                end
            end
            else if (in_p3) begin

                if (I_key_short[2]) begin            // key_r：下一种
                    if (O_tran_type >= TRAN_TYPE_MAX) O_tran_type <= TRAN_TYPE_MIN;
                    else                              O_tran_type <= O_tran_type + 1'b1;
                end
                if (I_key_short[0]) begin            // key_l：上一种
                    if (O_tran_type == TRAN_TYPE_MIN) O_tran_type <= TRAN_TYPE_MAX;
                    else                              O_tran_type <= O_tran_type - 1'b1;
                end
                if (key_m_short) begin               // key_m：转场开关
                    O_tran_en <= ~O_tran_en;
                    if (!O_tran_en) O_next_img <= 1'b1;
                end
            end
            else if (!in_p5 && !in_p6 && !in_p7) begin

                if (I_key_short[2]) O_next_img    <= 1'b1;   // key_r
                if (I_key_short[0]) O_prev_img    <= 1'b1;   // key_l
                if (key_m_short)    O_auto_toggle <= 1'b1;   // key_m
            end

            if (I_u_rset) begin
                O_bri        <= BRI_DEF;
                O_con        <= CON_DEF;
                O_sat        <= SAT_DEF;
                O_vol        <= VOL_DEF;
                O_irn        <= IRN_DEF;
                O_rot        <= ROT_DEFAULT;
                O_tran_type  <= TRAN_TYPE_DEF;
                O_tran_en    <= 1'b1;
                O_param_item <= ITEM_BRI;
            end
            else if (I_u_wr) begin
                case (I_u_sel)

                S_BRI: O_bri <= (I_u_val > BRI_MAX) ? BRI_MAX : I_u_val;

                S_CON: begin
                    if      (I_u_val < CON_MIN) O_con <= CON_MIN;
                    else if (I_u_val > CON_MAX) O_con <= CON_MAX;
                    else                        O_con <= I_u_val;
                end

                S_SAT: O_sat <= (I_u_val > SAT_MAX) ? SAT_MAX : I_u_val;

                S_VOL: O_vol <= (I_u_val > VOL_MAX) ? VOL_MAX : I_u_val;

                S_TRAN: O_tran_type <= (I_u_val > {5'd0, TRAN_TYPE_MAX})
                                       ? TRAN_TYPE_MAX : I_u_val[2:0];

                S_TE:   O_tran_en <= I_u_val[0];

                S_IRN:  O_irn <= (I_u_val > IRN_MAX) ? IRN_MAX : I_u_val;

                default: ;
                endcase
            end
        end
    end

    reg [15:0] val_mux;
    always @(*) begin
        case (O_param_item)
            ITEM_BRI:   val_mux = {8'd0, O_bri};
            ITEM_CON:   val_mux = {8'd0, O_con};
            ITEM_SAT:   val_mux = {8'd0, O_sat};
            ITEM_VOL:   val_mux = {8'd0, O_vol};
            default:    val_mux = 16'd0;
        endcase
    end

    assign O_param_val = val_mux;

endmodule
