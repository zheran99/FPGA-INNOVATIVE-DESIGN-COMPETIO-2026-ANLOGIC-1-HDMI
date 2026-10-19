`timescale 1ns / 1ps

module mode_decode (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire [3:0]  I_sw,          // {sw3, sw2, sw1, sw0}，拨上=1

    output reg  [2:0]  O_mode_num,    // 0..7（也可直接当"模式号-1"用）
    output reg  [7:0]  O_mode_oh,     // one-hot：{P8,...,P1}
    output reg         O_audio_pause  // sw[3]=1 暂停音乐
);

    reg [3:0] sw_sync_1d, sw_sync_2d;
    always @(posedge I_clk) begin
        sw_sync_1d <= I_sw;
        sw_sync_2d <= sw_sync_1d;
    end

    // 模式译码

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode_num   <= 3'd0;      // 复位进 P1（关闭模式），最安全
            O_mode_oh    <= 8'b0000_0001;
            O_audio_pause <= 1'b0;
        end
        else begin
            O_mode_num <= sw_sync_2d[2:0];

            case (sw_sync_2d[2:0])
                3'd0: O_mode_oh <= 8'b0000_0001;   // P1 关闭
                3'd1: O_mode_oh <= 8'b0000_0010;   // P2 纯净显示
                3'd2: O_mode_oh <= 8'b0000_0100;   // P3 转场设置
                3'd3: O_mode_oh <= 8'b0000_1000;   // P4 参数设置
                3'd4: O_mode_oh <= 8'b0001_0000;   // P5 字幕设置
                3'd5: O_mode_oh <= 8'b0010_0000;   // P6 Logo 设置
                3'd6: O_mode_oh <= 8'b0100_0000;   // P7 音频可视化
                3'd7: O_mode_oh <= 8'b1000_0000;   // P8 串口调试
            endcase

            O_audio_pause <= sw_sync_2d[3];
        end
    end

    // 留给 seg_status 使用

endmodule
