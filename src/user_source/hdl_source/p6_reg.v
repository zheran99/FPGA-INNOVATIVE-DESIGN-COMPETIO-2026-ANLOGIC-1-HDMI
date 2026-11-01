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

    output reg  [2:0]  O_item,          // 当前选中的设置项 0..2

    output reg [1:0] O_logo_size, // 0=64, 1=128, 2=256
    output reg  [1:0]  O_logo_sel,      // #0 标志：0=关 1=开(静止) 2=动(弹移)
    output reg         O_ad_on,         // #1 广告：0=关 1=开（左上角显示文字）
    output reg  [2:0]  O_ad_bg,
    output reg  [1:0]  O_ad_language,   // 0=中文 1=英文 2=双语
    output reg         O_ad_layout,     // 0=左上 1=上方居中

    output reg         O_logo_en,       // 1 = 需要叠加 Logo（标志 != 关）
    output reg  [1:0]  O_logo_mode,

    output reg         O_changed,

    input  wire        I_u_wr,          // 1 拍写脉冲
    input  wire [2:0]  I_u_sel,         // 0=LOGO 1=开关 2=背景 3=语言 4=布局
    input  wire [2:0]  I_u_val,         // LOGO 用低 2 位；背景用全部 3 位（0..6）
    input  wire        I_u_rst          // 恢复默认值
);

    // 设置项编号

    localparam [2:0] ITEM_LOGO = 3'd0,
                     ITEM_AD = 3'd1,
                     ITEM_BG = 3'd2,
                     ITEM_LANGUAGE = 3'd3,
                     ITEM_LAYOUT = 3'd4,
                     ITEM_SIZE = 3'd5,
                     ITEM_LAST = 3'd5;

    localparam [2:0] AD_BG_NONE   = 3'd0,
                     AD_BG_HALF   = 3'd1,
                     AD_BG_SOLID  = 3'd2,
                     AD_BG_ACCENT = 3'd3,
                     AD_BG_CARD   = 3'd4,
                     AD_BG_ULINE  = 3'd5,
                     AD_BG_TEAL   = 3'd6,
                     AD_BG_LAST   = 3'd6;

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
            O_logo_size <= 2'd1;
            O_ad_language <= 2'd0;
            O_ad_layout <= 1'b0;
            O_logo_en   <= (LOGO_SEL_DEF != LOGO_SEL_OFF);
            O_logo_mode <= (LOGO_SEL_DEF == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;
            O_changed   <= 1'b0;
        end else begin
            O_changed <= 1'b0;                 // 默认清掉

            if (hop && !hop_back) begin
                case(O_item)
                    0:O_item<=5;5:O_item<=1;1:O_item<=2;2:O_item<=3;3:O_item<=4;default:O_item<=0;
                endcase
                O_changed <= 1'b1;
            end else if (hop_back && !hop) begin
                case(O_item)
                    0:O_item<=4;4:O_item<=3;3:O_item<=2;2:O_item<=1;1:O_item<=5;default:O_item<=0;
                endcase
                O_changed <= 1'b1;
            end

            if (toggle) begin
                O_changed <= 1'b1;
                case (O_item)
                    ITEM_LOGO: O_logo_sel <= (O_logo_sel >= LOGO_SEL_MOVE)
                                             ? LOGO_SEL_OFF
                                             : O_logo_sel + 2'd1;
                    ITEM_AD:   O_ad_on    <= ~O_ad_on;
                    ITEM_BG:   O_ad_bg    <= (O_ad_bg >= AD_BG_LAST)
                                             ? AD_BG_NONE
                                             : O_ad_bg + 3'd1;
                    ITEM_LANGUAGE: O_ad_language <= O_ad_language>=2 ? 2'd0 : O_ad_language+2'd1;
                    ITEM_LAYOUT: O_ad_layout <= ~O_ad_layout;
                    ITEM_SIZE: O_logo_size <= O_logo_size>=2 ? 2'd0 : O_logo_size+2'd1;
                    default: ;
                endcase
            end

            O_logo_en   <= (O_logo_sel != LOGO_SEL_OFF);
            O_logo_mode <= (O_logo_sel == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;

            if (I_u_rst) begin
                O_logo_sel  <= LOGO_SEL_DEF;
                O_ad_on     <= AD_ON_DEF;
                O_ad_bg     <= AD_BG_DEF;
                O_logo_size <= 2'd1;
            O_ad_language <= 2'd0;
                O_ad_layout <= 1'b0;
                O_logo_en   <= (LOGO_SEL_DEF != LOGO_SEL_OFF);
                O_logo_mode <= (LOGO_SEL_DEF == LOGO_SEL_MOVE) ? 2'd1 : 2'd0;
            end
            else if (I_u_wr && I_u_sel == 3'd5) begin
                O_logo_size <= I_u_val>2 ? 2'd2 : I_u_val;
                O_changed <= 1'b1;
            end
            else if (I_u_wr && I_u_sel == 3'd3) begin
                O_ad_language <= (I_u_val > 2) ? 2'd2 : I_u_val;
                O_changed <= 1'b1;
            end
            else if (I_u_wr && I_u_sel == 3'd4) begin
                O_ad_layout <= (I_u_val != 0);
                O_changed <= 1'b1;
            end
            else if (I_u_wr && I_u_sel == 3'd1) begin
                O_ad_on <= I_u_val[0];
                O_changed <= 1'b1;
            end
            else if (I_u_wr && I_u_sel == 2'd2) begin
                O_ad_bg <= (I_u_val[2:0] > AD_BG_LAST) ? AD_BG_LAST : I_u_val[2:0];
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
