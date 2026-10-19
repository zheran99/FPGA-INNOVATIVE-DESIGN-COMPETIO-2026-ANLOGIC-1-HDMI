`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD        = 115200
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire       I_rx,          // 异步串口输入引脚（空闲=1）
    output reg  [7:0] O_data,        // 收到的字节
    output reg        O_valid        // 1 拍脉冲：O_data 有效
);

    localparam integer BIT_CLKS  = (CLK_FREQ_HZ + (BAUD / 2)) / BAUD;
    localparam integer HALF_CLKS = BIT_CLKS / 2;

    reg [1:0] rx_sync;
    reg       rx_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rx_sync <= 2'b11;        // 空闲态 = 1（避免复位后被当成起始位）
            rx_d    <= 1'b1;
        end
        else begin
            rx_sync <= {rx_sync[0], I_rx};
            rx_d    <= rx_sync[1];
        end
    end

    wire rx_bit    = rx_sync[1];                 // 同步后的"当前电平"
    wire rx_negedge = rx_d & ~rx_bit;            // 10：起始位候选

    // 采样状态机

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  st;
    reg [15:0] cnt;
    reg [2:0]  bidx;
    reg [7:0]  sh;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st      <= S_IDLE;
            cnt     <= 16'd0;
            bidx    <= 3'd0;
            sh      <= 8'd0;
            O_data  <= 8'd0;
            O_valid <= 1'b0;
        end
        else begin
            O_valid <= 1'b0;                 // 默认清脉冲

            case (st)

            S_IDLE: begin
                cnt <= 16'd0;
                if (rx_negedge) st <= S_START;   // 检测到下降沿 试起始位
            end

            S_START: begin
                if (cnt == (HALF_CLKS - 1)) begin
                    cnt <= 16'd0;
                    if (!rx_bit) begin
                        bidx <= 3'd0;
                        st   <= S_DATA;
                    end
                    else st <= S_IDLE;
                end
                else cnt <= cnt + 16'd1;
            end

            S_DATA: begin
                if (cnt == (BIT_CLKS - 1)) begin
                    cnt <= 16'd0;
                    sh  <= {rx_bit, sh[7:1]};    // LSB 先出：新位进 MSB
                    if (bidx == 3'd7) st   <= S_STOP;
                    else              bidx <= bidx + 3'd1;
                end
                else cnt <= cnt + 16'd1;
            end

            S_STOP: begin
                if (cnt == (BIT_CLKS - 1)) begin
                    cnt     <= 16'd0;
                    O_data  <= sh;
                    O_valid <= 1'b1;             // 1 拍脉冲
                    st      <= S_IDLE;
                end
                else cnt <= cnt + 16'd1;
            end

            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
