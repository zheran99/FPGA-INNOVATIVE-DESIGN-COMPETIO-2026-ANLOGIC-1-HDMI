`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD        = 115200
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire [7:0] I_data,        // 待发字节（I_start 时采样）
    input  wire       I_start,       // 1 拍脉冲：发起一次发送
    output reg        O_tx,          // 串口输出（空闲=1）
    output reg        O_busy         // 1 = 正在发送
);

    localparam integer BIT_CLKS = (CLK_FREQ_HZ + (BAUD / 2)) / BAUD;

    reg [15:0] cnt;
    reg [3:0]  bidx;
    reg [9:0]  sh;           // {停止, D7..D0, 起始}

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cnt   <= 16'd0;
            bidx  <= 4'd0;
            sh    <= 10'd0;
            O_tx  <= 1'b1;      // 空闲
            O_busy<= 1'b0;
        end
        else if (!O_busy) begin
            O_tx <= 1'b1;
            cnt  <= 16'd0;
            bidx <= 4'd0;
            if (I_start) begin

                O_busy <= 1'b1;
                O_tx   <= 1'b0;
                sh     <= {1'b1, I_data, 1'b0};   // sh[0]=起始位（先出）
            end
        end
        else begin
            if (cnt == (BIT_CLKS - 1)) begin
                cnt <= 16'd0;

                if (bidx == 4'd9) begin
                    O_busy <= 1'b0;              // 停止位时间到 收工
                    O_tx   <= 1'b1;              // 空闲保持高
                end
                else begin
                    bidx <= bidx + 4'd1;
                    sh   <= {1'b1, sh[9:1]};
                    O_tx <= sh[1];               // 下一位（D0..D7 / 停止位）
                end
            end
            else cnt <= cnt + 16'd1;
        end
    end

endmodule
