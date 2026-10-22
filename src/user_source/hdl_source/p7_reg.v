`timescale 1ns / 1ps

module p7_reg (
    input wire I_clk,
    input wire I_rst_n,
    input wire [2:0] I_key_short,
    input wire [7:0] I_mode_oh,

    input wire I_u_wr,                  // 1 拍写脉冲
    input wire [1:0] I_u_sel,           // 0=SPE(频谱开关) 1=SPS(方向)
    input wire [1:0] I_u_val,
    input wire I_u_rst,                 // 恢复默认值

    output reg O_wave_on,
    output reg [1:0] O_item,
    output reg O_visual_on,
    output reg O_horizontal
);

    localparam [1:0] P7_SEL_WAVE = 2'd0,
                     P7_SEL_HORZ = 2'd1;

    localparam WAVE_ON_DEF = 1'b1;      // 上电默认"开"（保持原行为不变）
    localparam HORZ_DEF    = 1'b0;      // 上电默认"竖排"

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_visual_on<=1'b1; O_wave_on <= WAVE_ON_DEF; O_item <= 2'd0; O_horizontal <= HORZ_DEF;
        end else begin
            if (I_mode_oh[6]) begin
                if (I_key_short[0] ^ I_key_short[2])
                    O_item <= I_key_short[2] ? (O_item==2 ? 2'd0 : O_item+2'd1) : (O_item==0 ? 2'd2 : O_item-2'd1);
                else if (I_key_short[1] && !I_key_short[0] && !I_key_short[2]) begin
                    if (!O_item) O_wave_on <= ~O_wave_on;
                    else if(O_item==1) O_horizontal <= ~O_horizontal;
                    else O_visual_on<=~O_visual_on;
                end
            end

            if (I_u_rst) begin
                O_visual_on <= 1'b1;
                O_wave_on    <= WAVE_ON_DEF;
                O_horizontal <= HORZ_DEF;
            end
            else if (I_u_wr) begin
                case (I_u_sel)
                P7_SEL_WAVE: O_wave_on    <= I_u_val[0];
                P7_SEL_HORZ: O_horizontal <= I_u_val[0];
                2'd2: O_visual_on <= I_u_val[0];
                default: ;
                endcase
            end
        end
    end
endmodule
