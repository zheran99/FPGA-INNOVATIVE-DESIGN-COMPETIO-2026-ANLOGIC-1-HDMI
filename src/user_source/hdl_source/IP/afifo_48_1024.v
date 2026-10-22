`timescale 1ns/1ps

module afifo_48_1024 #(
    parameter integer DATA_WIDTH = 48,
    parameter integer ADDR_WIDTH = 10            // 深度 = 2^10 = 1024
)(

    input                       wr_clk,
    input                       wr_rst,          // 异步复位，高有效
    input                       wr_en,
    input  [DATA_WIDTH-1:0]     wr_data,

    input                       rd_clk,
    input                       rd_rst,          // 异步复位，高有效
    input                       rd_en,
    output [DATA_WIDTH-1:0]     rd_data,         // rd_en 拉高后 1 拍有效

    // 状态
    output                      full,
    output                      empty,
    output [ADDR_WIDTH:0]       wr_used          // 写侧可见的已用字数（已寄存）
);

localparam integer PW = ADDR_WIDTH + 1;

function [PW-1:0] gray2bin;
    input [PW-1:0] g;
    integer i;
    begin
        gray2bin[PW-1] = g[PW-1];
        for (i = PW-2; i >= 0; i = i - 1)
            gray2bin[i] = gray2bin[i+1] ^ g[i];
    end
endfunction

// 写侧

reg [PW-1:0] wr_bin, wr_gray;
wire [PW-1:0] wr_bin_nxt  = wr_bin + 1'b1;
wire [PW-1:0] wr_gray_nxt = (wr_bin_nxt >> 1) ^ wr_bin_nxt;

reg [PW-1:0] rd_gray_w1, rd_gray_w2;
reg [PW-1:0] rd_bin_w;                           // 同步后转二进制（寄存）

// 读侧

reg [PW-1:0] rd_bin, rd_gray;
wire [PW-1:0] rd_bin_nxt  = rd_bin + 1'b1;
wire [PW-1:0] rd_gray_nxt = (rd_bin_nxt >> 1) ^ rd_bin_nxt;

reg [PW-1:0] wr_gray_r1, wr_gray_r2;

assign empty = (rd_gray == wr_gray_r2);
assign full  = (wr_gray == {~rd_gray_w2[PW-1:PW-2], rd_gray_w2[PW-3:0]});

reg [ADDR_WIDTH:0] wr_used_r;

always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst)
        wr_used_r <= {ADDR_WIDTH+1{1'b0}};
    else
        wr_used_r <= wr_bin - rd_bin_w;
end

assign wr_used = wr_used_r;

// 指针更新

always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst) begin
        wr_bin  <= {PW{1'b0}};
        wr_gray <= {PW{1'b0}};
    end else if (!wr_rst && wr_en && !full) begin
        wr_bin  <= wr_bin_nxt;
        wr_gray <= wr_gray_nxt;
    end
end

always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst) begin
        rd_bin  <= {PW{1'b0}};
        rd_gray <= {PW{1'b0}};
    end else if (!rd_rst && rd_en && !empty) begin
        rd_bin  <= rd_bin_nxt;
        rd_gray <= rd_gray_nxt;
    end
end

// 读指针 写域
always @(posedge wr_clk or posedge wr_rst) begin
    if (wr_rst) begin
        rd_gray_w1 <= {PW{1'b0}};
        rd_gray_w2 <= {PW{1'b0}};
        rd_bin_w   <= {PW{1'b0}};
    end else begin
        rd_gray_w1 <= rd_gray;
        rd_gray_w2 <= rd_gray_w1;
        rd_bin_w   <= gray2bin(rd_gray_w2);
    end
end

// 写指针 读域
always @(posedge rd_clk or posedge rd_rst) begin
    if (rd_rst) begin
        wr_gray_r1 <= {PW{1'b0}};
        wr_gray_r2 <= {PW{1'b0}};
    end else begin
        wr_gray_r1 <= wr_gray;
        wr_gray_r2 <= wr_gray_r1;
    end
end

reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

always @(posedge wr_clk) begin
    if (!wr_rst && wr_en && !full)
        mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
end

reg [DATA_WIDTH-1:0] rd_data_r;
always @(posedge rd_clk) begin
    if (!rd_rst && rd_en && !empty)
        rd_data_r <= mem[rd_bin[ADDR_WIDTH-1:0]];
end

assign rd_data = rd_data_r;

endmodule
