`timescale 1ns/1ps

module afifo_32_32_1024 #(
    parameter integer DATA_WIDTH_W = 32,
    parameter integer DATA_WIDTH_R = 32,
    parameter integer ADDR_WIDTH   = 10,           // 深度 = 2^10 = 1024
    parameter integer AL_FULL_NUM  = 1021,         // 几乎满阈值（与原 IP 语义一致）
    parameter integer AL_EMPTY_NUM = 2             // 几乎空阈值
)(

    input                       clkr,
    input                       re,
    output [DATA_WIDTH_R-1:0]   dout,              // re 拉高后 1 拍有效
    output                      empty_flag,
    output [ADDR_WIDTH:0]       rdusedw,           // 读域可见的已用字数（本工程不接）
    output                      aempty,            // 几乎空（本工程不接）

    input                       clkw,
    input                       rst,               // 异步复位，高有效（两侧共用）
    input                       we,
    input  [DATA_WIDTH_W-1:0]   di,
    output                      full_flag,
    output [ADDR_WIDTH:0]       wrusedw,           // 写时钟域！11 位
    output                      afull,             // 几乎满（本工程不接）

    output                      valid
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

    reg [2:0] clear_w=3'b111,clear_r=3'b111; /* fehdl keep="true" */
    always @(posedge clkw or posedge rst)
        if(rst)clear_w<=3'b111;else clear_w<={clear_w[1:0],1'b0};
    always @(posedge clkr or posedge rst)
        if(rst)clear_r<=3'b111;else clear_r<={clear_r[1:0],1'b0};
    wire reset_w=clear_w[2],reset_r=clear_r[2];

    // 写侧寄存器

    reg [PW-1:0] wr_bin, wr_gray;
    wire [PW-1:0] wr_bin_nxt  = wr_bin + 1'b1;
    wire [PW-1:0] wr_gray_nxt = (wr_bin_nxt >> 1) ^ wr_bin_nxt;

    // 读指针同步到写域
    reg [PW-1:0] rd_gray_w1, rd_gray_w2;
    reg [PW-1:0] rd_bin_w;

    // 读侧寄存器

    reg [PW-1:0] rd_bin, rd_gray;
    wire [PW-1:0] rd_bin_nxt  = rd_bin + 1'b1;
    wire [PW-1:0] rd_gray_nxt = (rd_bin_nxt >> 1) ^ rd_bin_nxt;

    // 写指针同步到读域
    reg [PW-1:0] wr_gray_r1, wr_gray_r2;

    assign empty_flag = reset_r || (rd_gray == wr_gray_r2);
    assign full_flag  = reset_w || (wr_gray == {~rd_gray_w2[PW-1:PW-2], rd_gray_w2[PW-3:0]});

    reg [PW-1:0] wr_bin_r;
    wire [ADDR_WIDTH:0] used_now = wr_bin_r - rd_bin;   // 读域可见的已用字数（组合）
    assign aempty = (used_now <= AL_EMPTY_NUM[ADDR_WIDTH:0]);
    assign afull  = (used_now >= AL_FULL_NUM[ADDR_WIDTH:0]);

    reg [ADDR_WIDTH:0] wr_used_r;
    always @(posedge clkw or posedge reset_w) begin
        if (reset_w)
            wr_used_r <= {(ADDR_WIDTH+1){1'b0}};
        else
            wr_used_r <= wr_bin - rd_bin_w;
    end
    assign wrusedw = wr_used_r;

    reg [ADDR_WIDTH:0] rd_used_r;
    always @(posedge clkr or posedge reset_r) begin
        if (reset_r) begin
            wr_bin_r  <= {PW{1'b0}};
            rd_used_r <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wr_bin_r  <= gray2bin(wr_gray_r1);   // 用 r1，少一级延迟
            rd_used_r <= wr_bin_r - rd_bin;
        end
    end
    assign rdusedw = rd_used_r;

    // 指针更新

    always @(posedge clkw or posedge reset_w) begin
        if (reset_w) begin
            wr_bin  <= {PW{1'b0}};
            wr_gray <= {PW{1'b0}};
        end else if (we && !full_flag) begin
            wr_bin  <= wr_bin_nxt;
            wr_gray <= wr_gray_nxt;
        end
    end

    always @(posedge clkr or posedge reset_r) begin
        if (reset_r) begin
            rd_bin  <= {PW{1'b0}};
            rd_gray <= {PW{1'b0}};
        end else if (re && !empty_flag) begin
            rd_bin  <= rd_bin_nxt;
            rd_gray <= rd_gray_nxt;
        end
    end

    // 读指针 写域
    always @(posedge clkw or posedge reset_w) begin
        if (reset_w) begin
            rd_gray_w1 <= {PW{1'b0}};
            rd_gray_w2 <= {PW{1'b0}};
            rd_bin_w   <= {PW{1'b0}};
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
            rd_bin_w   <= gray2bin(rd_gray_w1);     // 用 w1，少一级延迟
        end
    end

    // 写指针 读域
    always @(posedge clkr or posedge reset_r) begin
        if (reset_r) begin
            wr_gray_r1 <= {PW{1'b0}};
            wr_gray_r2 <= {PW{1'b0}};
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
        end
    end

    reg [DATA_WIDTH_W-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clkw) begin
        if (we && !full_flag)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= di;
    end

    reg [DATA_WIDTH_R-1:0] dout_r;
    always @(posedge clkr) begin
        if (re && !empty_flag)
            dout_r <= mem[rd_bin[ADDR_WIDTH-1:0]];
    end

    assign dout = dout_r;

    assign valid = re & ~empty_flag;

endmodule
