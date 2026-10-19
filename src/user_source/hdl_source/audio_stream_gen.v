`timescale 1ns/1ps

module audio_stream_gen #(
    parameter integer CLK_FREQ_HZ    = 75_000_000,   // video_clk
    parameter integer SAMPLE_RATE_HZ = 48_000
)(
    input               I_clk,               // video_clk
    input               I_rst,

    // FIFO 读侧
    input               I_fifo_empty,
    input  [47:0]       I_fifo_dout,         // {L[23:0], R[23:0]}
    output reg          O_fifo_rd_en,

    output reg          O_audio_valid,
    output reg  [23:0]  O_audio_left_data,
    output reg  [23:0]  O_audio_right_data,

    // 控制
    input               I_mute,              // 1=暂停（冻结位置，但仍发 valid）

    // 状态
    output reg          O_underrun,          // 1=本次取到的是"静音填充"（FIFO 空）
    output reg  [31:0]  O_sample_cnt         // 已输出样本计数（32 位 ≈ 24.8h）
);

localparam integer ACC_W = $clog2(CLK_FREQ_HZ + SAMPLE_RATE_HZ);
localparam [ACC_W-1:0] SR_C  = SAMPLE_RATE_HZ;
localparam [ACC_W-1:0] CLK_C = CLK_FREQ_HZ;

reg [ACC_W-1:0] acc;
reg        en48;

wire [ACC_W:0] acc_nxt = {1'b0, acc} + SR_C;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        acc  <= {ACC_W{1'b0}};
        en48 <= 1'b0;
    end else begin
        en48 <= 1'b0;
        if (acc_nxt >= {1'b0, CLK_C}) begin
            acc  <= acc_nxt[ACC_W-1:0] - CLK_C;
            en48 <= 1'b1;
        end else begin
            acc <= acc_nxt[ACC_W-1:0];
        end
    end
end

reg rd_req_d;         // 上拍是否发了 rd_en
reg uc_pend;          // 上拍 en48 但 FIFO 空（欠载挂起）
reg data_started;     // 首个 PCM 到达后锁存，区分启动等待与运行时欠载

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_fifo_rd_en       <= 1'b0;
        O_audio_valid      <= 1'b0;
        O_audio_left_data  <= 24'd0;
        O_audio_right_data <= 24'd0;
        O_underrun         <= 1'b0;
        O_sample_cnt       <= 32'd0;
        rd_req_d           <= 1'b0;
        uc_pend            <= 1'b0;
        data_started       <= 1'b0;
    end else begin
        O_audio_valid <= 1'b0;
        O_fifo_rd_en  <= 1'b0;

        if (!I_fifo_empty)
            data_started <= 1'b1;

        if (en48 && !I_mute && data_started) begin
            O_fifo_rd_en <= ~I_fifo_empty;
            uc_pend      <=  I_fifo_empty;
        end

        if (rd_req_d) begin
            O_audio_left_data  <= I_fifo_dout[47:24];
            O_audio_right_data <= I_fifo_dout[23:0];
            O_audio_valid <= 1'b1;
            O_underrun    <= 1'b0;
            O_sample_cnt  <= O_sample_cnt + 32'd1;
            uc_pend       <= 1'b0;              // 正常路径优先，清欠载挂起
        end else if (en48 && (I_mute || !data_started)) begin

            O_audio_left_data  <= 24'd0;
            O_audio_right_data <= 24'd0;
            O_audio_valid      <= 1'b1;
            O_underrun         <= 1'b0;
        end else if (uc_pend) begin

            O_audio_left_data  <= 24'd0;
            O_audio_right_data <= 24'd0;
            O_audio_valid      <= 1'b1;
            O_underrun         <= 1'b1;
            O_sample_cnt       <= O_sample_cnt + 32'd1;
            uc_pend            <= 1'b0;
        end

        rd_req_d <= O_fifo_rd_en;
    end
end

endmodule
