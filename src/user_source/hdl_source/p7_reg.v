`timescale 1ns / 1ps

module p7_reg (
    input wire I_clk,
    input wire I_rst_n,
    input wire [2:0] I_key_short,
    input wire [7:0] I_mode_oh,

    input wire I_u_wr,                  // 1 拍写脉冲
    input wire [1:0] I_u_sel,           // 0=SPE(频谱开关) 1=SPS(方向)
    input wire [2:0] I_u_val,
    input wire I_u_rst,                 // 恢复默认值

    output reg O_wave_on,
    output reg [1:0] O_item,
    output reg O_visual_on,
    output reg O_horizontal,
    output reg [1:0] O_shape,
    output wire O_import_mode,
    output reg [1:0] O_visual_mode
);
    assign O_import_mode=O_visual_mode==2;

    localparam [1:0] P7_SEL_WAVE = 2'd0,
                     P7_SEL_HORZ = 2'd1;

    localparam WAVE_ON_DEF = 1'b1;      // 上电默认"开"（保持原行为不变）
    localparam HORZ_DEF    = 1'b0;      // 上电默认"竖排"

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_visual_on<=1'b1; O_visual_mode<=2'd1; O_wave_on <= WAVE_ON_DEF; O_item <= 2'd0; O_horizontal <= HORZ_DEF; O_shape<=2'd0;
        end else begin
            if (I_mode_oh[6]) begin
                if (I_key_short[0] ^ I_key_short[2])
                    O_item <= O_item==0 ? 2'd3 : 2'd0;
                else if (I_key_short[1] && !I_key_short[0] && !I_key_short[2]) begin
                    if (!O_item) O_wave_on <= ~O_wave_on;
                    else begin
                        O_horizontal<=1'b0;
                        O_visual_on<=1'b1;
                        if(O_visual_mode==2)begin O_visual_mode<=1;O_shape<=0;end
                        else if(O_shape==3)O_visual_mode<=2;
                        else begin O_shape<=O_shape+2'd1;O_visual_mode<=1;end
                    end
                end
            end

            if (I_u_rst) begin
                O_visual_on <= 1'b1; O_visual_mode<=2'd1;
                O_wave_on    <= WAVE_ON_DEF;
                O_horizontal <= HORZ_DEF;
                O_shape      <= 2'd0;
            end
            else if (I_u_wr) begin
                case (I_u_sel)
                P7_SEL_WAVE: O_wave_on    <= I_u_val[0];
                P7_SEL_HORZ: O_horizontal <= I_u_val[0];
                2'd2:begin O_visual_mode<=I_u_val>2 ? 2'd2 : I_u_val[1:0];O_visual_on<=I_u_val!=0;end
                2'd3: begin
                    O_visual_on <= 1'b1;
                    O_horizontal <= 1'b0;
                    if (I_u_val >= 3'd4) O_visual_mode <= 2'd2;
                    else begin O_shape <= I_u_val[1:0]; O_visual_mode <= 2'd1; end
                end
                default: ;
                endcase
            end
        end
    end
endmodule
