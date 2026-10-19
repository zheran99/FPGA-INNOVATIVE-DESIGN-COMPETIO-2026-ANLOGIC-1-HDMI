`timescale 1ns/1ps

module subtitle_rom (
    input  wire        clk,
    input  wire [9:0]  cue_idx,      // 句号 0..N（N 是哨兵）
    output wire [23:0] cue_frame,    // 同步输出：该句起始帧号
    output wire [15:0] cue_coff,     // 同步输出：该句首字符在流里的下标
    output wire [15:0] cue_len,      // 同步输出：该句字符数
    output wire [23:0] cue_dur,      // 同步输出：该句显示时长（帧）

    input  wire        I_wr_clk,
    input  wire        I_wr_en,
    input  wire [5:0]  I_wr_addr,    // 0..63
    input  wire [63:0] I_wr_data
);

    localparam integer CUE_DEPTH = 64;              // 64 项 × 32 位
    localparam [31:0]  SENTINEL  = 32'hFFFF_FFFF;

    (* ram_style = "block" *) reg [31:0] m_cue [0:CUE_DEPTH-1];

    reg [31:0] cue_q;

    always @(posedge clk)
        cue_q <= m_cue[cue_idx[5:0]];

    assign cue_frame = {8'd0,  cue_q[31:16]};
    assign cue_coff  = {6'd0,  cue_q[15:6]};
    assign cue_len   = {10'd0, cue_q[5:0]};
    assign cue_dur   = 24'd0;

    always @(posedge I_wr_clk)
        if (I_wr_en)
            m_cue[I_wr_addr] <= {I_wr_data[15:0],    // frame[15:0]（blob 第 1、2 字节）
                                 I_wr_data[25:16],   // coff [ 9:0]（第 3、4 字节的低 10 位）
                                 I_wr_data[37:32]};  // len [ 5:0]（第 5、6 字节的低 6 位）

    integer i;
    initial begin
        for (i = 0; i < CUE_DEPTH; i = i + 1) m_cue[i] = SENTINEL;
    end

endmodule

module subtitle_char_rom (
    input  wire        clk,
    input  wire [15:0] char_addr,    // 字符下标（0 .. 1023）
    output reg  [7:0]  char_code,    // 同步输出（地址后 1 拍有效）

    input  wire        I_wr_clk,
    input  wire        I_wr_en,
    input  wire [9:0]  I_wr_addr,
    input  wire [7:0]  I_wr_data
);

    localparam integer STR_DEPTH = 1024;

    reg [7:0] m_ch [0:STR_DEPTH-1];

    always @(posedge clk)
        char_code <= m_ch[char_addr[9:0]];

    always @(posedge I_wr_clk)
        if (I_wr_en) m_ch[I_wr_addr] <= I_wr_data;

    integer i;
    initial begin
        for (i = 0; i < STR_DEPTH; i = i + 1) m_ch[i] = 8'h20;
    end

endmodule
