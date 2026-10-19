`timescale 1ns/1ps

module logo_rom (
    input  wire             clk,      // video_clk（同步读）
    input  wire [11:0] addr,     // {sy, sx}
    output wire [15:0]      q         // rgb565（0 = 透明），地址后 1 拍有效
);

    wire [7:0] d_lo, d_hi;

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A  (8),
        .DATA_WIDTH_B  (8),
        .ADDR_WIDTH_A  (12),
        .ADDR_WIDTH_B  (12),
        .DATA_DEPTH_A  (4096),
        .DATA_DEPTH_B  (4096),
        .MODE          ("SP"),
        .REGMODE_A     ("NOREG"),   // 同步读、1 拍延迟
        .REGMODE_B     ("NOREG"),
        .IMPLEMENT     ("32K"),     // 不写只能用 bram9k
        .DEBUGGABLE    ("NO"),
        .PACKABLE      ("NO"),
        .INIT_FILE     ("python/logo_lo.mif"),
        .FILL_ALL      ("NONE")
    ) u_rom_lo (
        .dia   (8'd0),
        .dib   (8'd0),
        .addra (addr),
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
        .REGMODE_A     ("NOREG"),   // 同步读、1 拍延迟
        .REGMODE_B     ("NOREG"),
        .IMPLEMENT     ("32K"),     // 不写只能用 bram9k
        .DEBUGGABLE    ("NO"),
        .PACKABLE      ("NO"),
        .INIT_FILE     ("python/logo_hi.mif"),
        .FILL_ALL      ("NONE")
    ) u_rom_hi (
        .dia   (8'd0),
        .dib   (8'd0),
        .addra (addr),
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

    assign q = {d_hi, d_lo};

endmodule
