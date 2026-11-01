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
    input wire clk, input wire [6:0] addr, output reg [16:0] q,
    input wire I_wr_clk, input wire I_wr_en,
    input wire [6:0] I_wr_addr, input wire [16:0] I_wr_data
);
    (* ram_style = "bram" *) reg [16:0] m_ln [0:127];
    always @(posedge clk) q <= m_ln[addr];
    always @(posedge I_wr_clk) if(I_wr_en) m_ln[I_wr_addr] <= I_wr_data;
    integer i;
    initial for(i=0;i<128;i=i+1) m_ln[i]=0;
endmodule

module ad_str_tbl (
    input wire clk, input wire rst, input wire blank,
    input wire [3:0] img, input wire [2:0] line, input wire [5:0] col,
    input wire [1:0] I_lang,
    output wire [7:0] code, output wire [5:0] len, output wire ready,
    output wire [10:0] max_w,
    input wire I_wr_clk, input wire I_wr_en,
    input wire [6:0] I_wr_addr, input wire [16:0] I_wr_data,
    input wire I_ch_wr_en, input wire [10:0] I_ch_wr_addr,
    input wire [7:0] I_ch_wr_data
);
    reg [3:0] fetch_img, cached_img;
    reg [3:0] count;
    reg busy, valid_cache, active_bank, fetch_nonempty;

    (* ram_style = "dram" *) reg [16:0] cache [0:15];
    wire [16:0] ram_q;
    wire [2:0] read_slot=count[2:0];
    ad_line_ram u_ln(.clk(clk),.addr({fetch_img,read_slot}),.q(ram_q),
        .I_wr_clk(I_wr_clk),.I_wr_en(I_wr_en),.I_wr_addr(I_wr_addr),.I_wr_data(I_wr_data));
    wire [2:0] write_slot=count[2:0]-3'd1;
    wire cache_we=!rst && blank && busy && count!=0 && count<9;
    always @(posedge clk)
        if(cache_we) cache[{~active_bank,write_slot}]<=ram_q;
    integer k;
    initial for(k=0;k<16;k=k+1) cache[k]=0;

    // 槽 7 未使用 ×8

    wire        cjk_slot = (write_slot >= 3'd1) && (write_slot < 3'd4);
    wire [10:0] slot_px  = cjk_slot ? {1'd0,ram_q[16:11],4'd0}     // ×16
                                    : {2'd0,ram_q[16:11],3'd0};    // ×8
    wire        slot_shown = (write_slot == 3'd0)
                          || (I_lang == 2'd0 && write_slot <= 3'd2)              // 中文
                          || (I_lang == 2'd1 && write_slot >= 3'd4 && write_slot <= 3'd6) // 英文
                          || (I_lang == 2'd2 && write_slot <= 3'd6);             // 双语
    reg  [10:0] fetch_max, max_len_r;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            fetch_img<=0;cached_img<=15;count<=0;busy<=0;valid_cache<=0;
            active_bank<=0;fetch_nonempty<=0;fetch_max<=0;max_len_r<=0;
        end else if(!blank) begin busy<=0;count<=0;end
        else if(!busy) begin fetch_img<=img;count<=0;busy<=1;fetch_nonempty<=0;fetch_max<=0;end
        else if(count<9) begin

            if(count!=0 && write_slot!=3 && write_slot!=7)
                fetch_nonempty<=fetch_nonempty || |ram_q[16:11];
            if(count!=0 && slot_shown && slot_px>fetch_max) fetch_max<=slot_px;
            count<=count+1'b1;
        end else begin
            if(img==fetch_img) begin
                active_bank<=~active_bank;
                cached_img<=fetch_img;
                valid_cache<=fetch_nonempty;
                max_len_r<=fetch_max;
            end
            busy<=0;count<=0;
        end
    end
    assign ready=valid_cache && cached_img==img && img<9;
    assign max_w=max_len_r;
    wire [16:0] cur=cache[{active_bank,line}];
    assign len=ready ? cur[16:11] : 6'd0;
    (* use_ripple = 1 *) wire [10:0] addr=cur[10:0]+{5'd0,col};
    wire [7:0] raw_code;
    reg valid;
    always @(posedge clk) valid<=ready && col<len;
    ad_char_stream u_chars(.clk(clk),.addr(addr),.code(raw_code),
        .I_wr_clk(I_wr_clk),.I_wr_en(I_ch_wr_en),.I_wr_addr(I_ch_wr_addr),.I_wr_data(I_ch_wr_data));
    assign code=valid ? raw_code : 8'd0;
endmodule

module ad_char_stream (
    input wire clk, input wire [10:0] addr, output reg [7:0] code,
    input wire I_wr_clk, input wire I_wr_en,
    input wire [10:0] I_wr_addr, input wire [7:0] I_wr_data
);
    reg [7:0] mem [0:2047];
    always @(posedge clk) code<=mem[addr];
    always @(posedge I_wr_clk) if(I_wr_en) mem[I_wr_addr]<=I_wr_data;
    integer i;
    initial for(i=0;i<2048;i=i+1) mem[i]=0;
endmodule
