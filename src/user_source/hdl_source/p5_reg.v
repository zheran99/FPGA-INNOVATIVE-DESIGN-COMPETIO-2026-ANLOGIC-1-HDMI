`timescale 1ns / 1ps

module p5_reg (
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 key_ctrl
    input  wire [2:0]  I_key_short,     // {r, m, l} 短按单拍
    input  wire [2:0]  I_key_repeat,    // {r, m, l} 长按连发单拍（one-hot）

    // 来自 mode_decode
    input  wire [7:0]  I_mode_oh,       // {P8,...,P1}

    output reg  [2:0]  O_item,          // 当前选中的设置项 0..5

    output reg         O_sub_on,        // 字幕总开关 1=开
    output reg  [1:0]  O_mode,          // 换句方式 0=滚动 1=直切 2=打字（3 档）
    output reg  [1:0]  O_pos,           // 字幕位置 0=底部 1=顶部 2=右下
    output reg  [1:0]  O_bg,            // 字幕背景 0=无 1=半透 2=实底
    output reg         O_size,          // 字号 0=小 1=中
    output reg         O_monitor,       // 同步监视器 1=开

    output reg         O_changed,

    input  wire        I_u_wr,          // 1 拍写脉冲
    input  wire [2:0]  I_u_sel,
    input  wire [1:0]  I_u_val,
    input  wire        I_u_rst          // 恢复默认值
);

    // 设置项编号

    localparam [2:0] ITEM_ON   = 3'd0,   // 开关
                     ITEM_MODE = 3'd1,   // 换句
                     ITEM_POS  = 3'd2,   // 位置
                     ITEM_BG   = 3'd3,   // 背景
                     ITEM_SIZE = 3'd4,   // 字号
                     ITEM_MON  = 3'd5,   // 监视
                     ITEM_LAST = 3'd5;

    localparam [2:0] P5_SEL_SUB  = 3'd0,
                     P5_SEL_SBG  = 3'd1,
                     P5_SEL_MON  = 3'd2,
                     P5_SEL_SIZE = 3'd3;      // SSZn（0=小 1=中）

    localparam        SUB_ON_DEF = 1'b1,
                      SIZE_DEF   = 1'b0;      // 小字号
    localparam [1:0]  MODE_DEF   = 2'd1,      // 直切（默认：最稳、无过渡）
                      POS_DEF    = 2'd0,      // 底部
                      BG_DEF     = 2'd1;      // 半透

    // 按键边沿辅助

    wire key_prev = I_key_short[0] | I_key_repeat[0];   // key_l：上一项
    wire key_next = I_key_short[2] | I_key_repeat[2];   // key_r：下一项
    wire key_tog  = I_key_short[1];                     // key_m：切状态（不连发）

    wire in_p5 = I_mode_oh[4];              // P5 字幕设置

    wire hop = in_p5 & key_next;
    wire hop_back = in_p5 & key_prev;
    wire toggle = in_p5 & key_tog;

    // 主逻辑

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_item    <= ITEM_ON;
            O_sub_on  <= SUB_ON_DEF;
            O_mode    <= MODE_DEF;
            O_pos     <= POS_DEF;
            O_bg      <= BG_DEF;
            O_size    <= SIZE_DEF;
            O_monitor <= 1'b0;
            O_changed <= 1'b0;
        end else begin
            O_changed <= 1'b0;              // 默认清掉

            if (hop && !hop_back) begin
                O_item    <= (O_item >= ITEM_LAST) ? ITEM_ON : O_item + 3'd1;
                O_changed <= 1'b1;
            end else if (hop_back && !hop) begin
                O_item    <= (O_item == ITEM_ON) ? ITEM_LAST : O_item - 3'd1;
                O_changed <= 1'b1;
            end

            if (toggle) begin
                O_changed <= 1'b1;
                case (O_item)

                    ITEM_ON:   O_sub_on  <= ~O_sub_on;          // 2 档

                    ITEM_MODE: O_mode    <= (O_mode >= 2'd2) ? 2'd0
                                                            : O_mode + 2'd1;

                    ITEM_POS:  O_pos     <= (O_pos     >= 2'd2) ? 2'd0
                                                                : O_pos + 2'd1;

                    ITEM_BG:   O_bg      <= (O_bg      >= 2'd2) ? 2'd0
                                                                : O_bg + 2'd1;

                    ITEM_SIZE: O_size    <= ~O_size;            // 2 档

                    ITEM_MON:  O_monitor <= ~O_monitor;         // 2 档

                    default: ;
                endcase
            end

            if (I_u_rst) begin
                O_sub_on  <= SUB_ON_DEF;
                O_mode    <= MODE_DEF;
                O_pos     <= POS_DEF;
                O_bg      <= BG_DEF;
                O_size    <= SIZE_DEF;
                O_monitor <= 1'b0;
            end
            else if (I_u_wr) begin
                case (I_u_sel)

                P5_SEL_SUB: begin
                    O_sub_on <= (I_u_val != 2'd0);
                    O_mode   <= (I_u_val == 2'd0) ? MODE_DEF : (I_u_val - 2'd1);
                end

                P5_SEL_SBG: O_bg <= (I_u_val > 2'd2) ? 2'd2 : I_u_val;

                P5_SEL_MON: O_monitor <= I_u_val[0];

                P5_SEL_SIZE: O_size <= I_u_val[0];

                3'd4: O_sub_on <= I_u_val[0];
                3'd5: O_mode <= (I_u_val > 2'd1) ? 2'd1 : I_u_val;
                3'd6: O_pos <= (I_u_val > 2'd2) ? 2'd2 : I_u_val;

                default: ;
                endcase
            end
        end
    end

endmodule
