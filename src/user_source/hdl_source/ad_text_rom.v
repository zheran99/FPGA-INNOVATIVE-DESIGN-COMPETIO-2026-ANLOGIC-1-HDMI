`timescale 1ns/1ps

module ad_font_rom (
    input  wire [7:0]  char_idx,
    input  wire [3:0]  row,          // 0..15
    output wire [15:0] rom_row,      // 同步输出：地址后 1 拍有效
    input  wire        clk           // video_clk
);

    wire [11:0] a_mem = {char_idx[7:0], row[3:0]};
    wire [7:0]  d_lo, d_hi;

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A  (8),
        .DATA_WIDTH_B  (8),
        .ADDR_WIDTH_A  (12),
        .ADDR_WIDTH_B  (12),
        .DATA_DEPTH_A  (4096),
        .DATA_DEPTH_B  (4096),
        .MODE          ("SP"),
        .REGMODE_A     ("NOREG"),   // 同步读、1 拍延迟（与旧的数组推断一致）
        .REGMODE_B     ("NOREG"),
        .IMPLEMENT     ("32K"),     // 关键："9K" 会变成 8 块 bram9k
        .DEBUGGABLE    ("NO"),
        .PACKABLE      ("NO"),
        .INIT_FILE     ("python/ad_cn_font_lo.mif"),
        .FILL_ALL      ("NONE")
    ) u_ram_lo (
        .dia   (8'd0),
        .dib   (8'd0),
        .addra (a_mem),
        .addrb (12'd0),
        .cea   (1'b1),
        .ceb   (1'b0),
        .wea   (1'b0),
        .web   (1'b0),
        .bea   (1'b0),
        .beb   (1'b0),
        .ocea  (1'b0),
        .oceb  (1'b0),
        .clka  (clk),
        .clkb  (1'b0),
        .rsta  (1'b0),
        .rstb  (1'b0),
        .doa   (d_lo),
        .dob   ()
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A  (8),
        .DATA_WIDTH_B  (8),
        .ADDR_WIDTH_A  (12),
        .ADDR_WIDTH_B  (12),
        .DATA_DEPTH_A  (4096),
        .DATA_DEPTH_B  (4096),
        .MODE          ("SP"),
        .REGMODE_A     ("NOREG"),
        .REGMODE_B     ("NOREG"),
        .IMPLEMENT     ("32K"),
        .DEBUGGABLE    ("NO"),
        .PACKABLE      ("NO"),
        .INIT_FILE     ("python/ad_cn_font_hi.mif"),
        .FILL_ALL      ("NONE")
    ) u_ram_hi (
        .dia   (8'd0),
        .dib   (8'd0),
        .addra (a_mem),
        .addrb (12'd0),
        .cea   (1'b1),
        .ceb   (1'b0),
        .wea   (1'b0),
        .web   (1'b0),
        .bea   (1'b0),
        .beb   (1'b0),
        .ocea  (1'b0),
        .oceb  (1'b0),
        .clka  (clk),
        .clkb  (1'b0),
        .rsta  (1'b0),
        .rstb  (1'b0),
        .doa   (d_hi),
        .dob   ()
    );

    assign rom_row = {d_hi, d_lo};

endmodule

module ad_line_ram (
    input  wire        clk,          // video_clk（读）
    input  wire [5:0]  addr,         // {img[3:0], line[1:0]}
    output reg  [15:0] q,            // {len[5:0], offset[9:0]}

    input  wire        I_wr_clk,     // sd_card_clk（写）
    input  wire        I_wr_en,
    input  wire [5:0]  I_wr_addr,
    input  wire [15:0] I_wr_data
);

    (* ram_style = "dram" *) reg [15:0] m_ln [0:63];
    always @(posedge clk)
        q <= m_ln[addr];
    always @(posedge I_wr_clk)
        if (I_wr_en) m_ln[I_wr_addr] <= I_wr_data;

    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1) m_ln[i] = 16'd0;
    end
endmodule

module ad_str_tbl(
    input  wire        clk,
    input  wire [3:0]  img,
    input  wire [1:0]  line,
    input  wire [5:0]  col,
    output wire [7:0]  code,
    output reg  [5:0]  len,

    input  wire        I_wr_clk,
    input  wire        I_wr_en,
    input  wire [5:0]  I_wr_addr,
    input  wire [15:0] I_wr_data,

    input  wire        I_ch_wr_en,
    input  wire [9:0]  I_ch_wr_addr,
    input  wire [7:0]  I_ch_wr_data
);

    reg [1:0] ridx, ridx_d;
    reg [15:0] ln0, ln1, ln2, ln3;
    wire [15:0] ram_q;

    ad_line_ram u_ln (
        .clk        (clk),
        .addr       ({img, ridx}),
        .q          (ram_q),
        .I_wr_clk   (I_wr_clk),
        .I_wr_en    (I_wr_en),
        .I_wr_addr  (I_wr_addr),
        .I_wr_data  (I_wr_data)
    );

    always @(posedge clk) begin
        ridx   <= ridx + 2'd1;
        ridx_d <= ridx;
        case (ridx_d)
            2'd0: ln0 <= ram_q;
            2'd1: ln1 <= ram_q;
            2'd2: ln2 <= ram_q;
            2'd3: ln3 <= ram_q;
        endcase
    end

    wire [15:0] cur = (line == 2'd0) ? ln0 :
                      (line == 2'd1) ? ln1 :
                      (line == 2'd2) ? ln2 : ln3;
    wire [9:0] offset = cur[9:0];

    always @(*) len = cur[15:10];

    wire [9:0]  addr     = offset + {4'd0, col};
    wire [7:0]  raw_code;
    reg         valid;
    always @(posedge clk) valid <= (img < 9) && (col < len);
    ad_char_stream u_chars (
        .clk       (clk),
        .addr      (addr),
        .code      (raw_code),
        .I_wr_clk  (I_wr_clk),
        .I_wr_en   (I_ch_wr_en),
        .I_wr_addr (I_ch_wr_addr),
        .I_wr_data (I_ch_wr_data)
    );
    assign code = valid ? raw_code : 8'd0;
endmodule

module ad_char_stream(
    input  wire        clk,
    input  wire [9:0]  addr,
    output reg  [7:0]  code,

    input  wire        I_wr_clk,
    input  wire        I_wr_en,
    input  wire [9:0]  I_wr_addr,
    input  wire [7:0]  I_wr_data
);
    reg [7:0] mem [0:1023];
    always @(posedge clk)
        code <= mem[addr];
    always @(posedge I_wr_clk)
        if (I_wr_en) mem[I_wr_addr] <= I_wr_data;
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) mem[i] = 8'd0;
    end
endmodule
