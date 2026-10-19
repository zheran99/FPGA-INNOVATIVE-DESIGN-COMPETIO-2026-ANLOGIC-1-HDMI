`timescale 1ns/1ps

module p6_reg (
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 key_ctrl
    input  wire [2:0]  I_key_short,     // {r, m, l} 短按单拍
    input  wire [2:0]  I_key_repeat,    // {r, m, l} 长按连发单拍（one-hot）

    // 来自 mode_decode
    input  wire [7:0]  I_mode_oh,       // {P8,...,P1}

    // 设置输出

    output reg  [1:0]  O_item,          // 当前选中的设置项 0..2

    output reg  [1:0]  O_logo_sel,      // #0 标志：0=关 1=开(静止) 2=动(弹移)
    output reg         O_ad_on,         // #1 广告：0=关 1=开（左上角显示文字）
    output reg  [1:0]  O_ad_bg,         // #2 背景：0=无 1=半透 2=实底

    output reg         O_logo_en,       // 1 = 需要叠加 Logo（标志 != 关）
    output reg  [1:0]  O_logo_mode,

    output reg         O_changed,

    input  wire        I_u_wr,          // 1 拍写脉冲
    input  wire [1:0]  I_u_sel,         // 0=LOGO
    input  wire [1:0]  I_u_val,         // LOGO：0=关 1=开(静止) 2=动(弹移)
    input  wire        I_u_rst          // 恢复默认值
);

    // 设置项编号

    localparam [1:0] ITEM_LOGO = 2'd0,   // 标志
                     ITEM_AD   = 2'd1,   // 广告
                     ITEM_BG   = 2'd2,   // 背景
                     ITEM_LAST = 2'd2;

    localparam [1:0] AD_BG_NONE  = 2'd0,
                     AD_BG_HALF  = 2'd1,
                     AD_BG_SOLID = 2'd2;

    // Logo

    localparam [1:0] LOGO_SEL_OFF  = 2'd0,
                     LOGO_SEL_ON   = 2'd1,
                     LOGO_SEL_MOVE = 2'd2;

    localparam [1:0] P6_SEL_LOGO = 2'd0;

    localparam [1:0] LOGO_SEL_DEF = LOGO_SEL_ON,
                     AD_BG_DEF    = AD_BG_HALF;
    localparam       AD_ON_DEF    = 1'b1;

    // 按键

    wire key_prev = I_key_short[0] | I_key_repeat[0];   // key_l：上一项
    wire key_next = I_key_short[2] | I_key_repeat[2];   // key_r：下一项
    wire key_tog  = I_key_short[1];                     // key_m：切状态（不连发）

    wire in_p6 = I_mode_oh[5];              // P6 广告牌设置

    wire hop      = in_p6 & key_next;
    wire hop_back = in_p6 & key_prev;
    wire toggle   = in_p6 & key_tog;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_item      <= ITEM_LOGO;
            O_logo_sel  <= LOGO_SEL_DEF;
            O_ad_on     <= AD_ON_DEF;
            O_ad_bg     <= AD_BG_DEF;
            O_logo_en   <= (LOGO_SEL_DEF != LOGO_SEL_OFF);
            O_logo_mode <= (LOGO_SEL_DEF == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;
            O_changed   <= 1'b0;
        end else begin
            O_changed <= 1'b0;                 // 默认清掉

            if (hop && !hop_back) begin
                O_item    <= (O_item >= ITEM_LAST) ? ITEM_LOGO : O_item + 2'd1;
                O_changed <= 1'b1;
            end else if (hop_back && !hop) begin
                O_item    <= (O_item == ITEM_LOGO) ? ITEM_LAST : O_item - 2'd1;
                O_changed <= 1'b1;
            end

            if (toggle) begin
                O_changed <= 1'b1;
                case (O_item)
                    ITEM_LOGO: O_logo_sel <= (O_logo_sel >= LOGO_SEL_MOVE)
                                             ? LOGO_SEL_OFF
                                             : O_logo_sel + 2'd1;
                    ITEM_AD:   O_ad_on    <= ~O_ad_on;

                    default:   O_ad_bg    <= (O_ad_bg >= AD_BG_SOLID)
                                             ? AD_BG_NONE
                                             : O_ad_bg + 2'd1;
                endcase
            end

            O_logo_en   <= (O_logo_sel != LOGO_SEL_OFF);
            O_logo_mode <= (O_logo_sel == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;

            if (I_u_rst) begin
                O_logo_sel  <= LOGO_SEL_DEF;
                O_ad_on     <= AD_ON_DEF;
                O_ad_bg     <= AD_BG_DEF;
                O_logo_en   <= (LOGO_SEL_DEF != LOGO_SEL_OFF);
                O_logo_mode <= (LOGO_SEL_DEF == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;
            end
            else if (I_u_wr && I_u_sel == 2'd1) begin
                O_ad_on <= I_u_val[0];
                O_changed <= 1'b1;
            end
            else if (I_u_wr && I_u_sel == 2'd2) begin
                O_ad_bg <= (I_u_val > 2'd2) ? 2'd2 : I_u_val;
                O_changed <= 1'b1;
            end
            else if (I_u_wr && (I_u_sel == P6_SEL_LOGO)) begin
                O_logo_sel  <= (I_u_val > LOGO_SEL_MOVE) ? LOGO_SEL_MOVE : I_u_val;
                O_logo_en   <= (I_u_val > LOGO_SEL_MOVE) ? 1'b1
                                                         : (I_u_val != LOGO_SEL_OFF);
                O_logo_mode <= (I_u_val == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;
            end
        end
    end

endmodule
