`timescale 1ns/1ps

module osd_circle_rom (
    input  wire        clk,         // 视频时钟（同步读）
    input  wire [7:0]  row_idx,     // 0..114（= y - 573），须已寄存
    output reg  [7:0]  hw_inner,    // 圆环内沿 R_INNER=41（同步输出）
    output reg  [7:0]  hw_fill,     // 圆外边界 R_FILL=45
    output reg  [7:0]  hw_gap       // 矩内弧 R_GAP=57
);

    reg [23:0] mem [0:114];

    always @(posedge clk) begin
        {hw_inner, hw_fill, hw_gap} <= mem[row_idx];
    end

    integer i;
    initial begin
        for (i = 0; i < 115; i = i + 1) mem[i] = 24'd0;
        mem[   0] = 24'h000001;
        mem[   1] = 24'h00000B;
        mem[   2] = 24'h00000F;
        mem[   3] = 24'h000013;
        mem[   4] = 24'h000015;
        mem[   5] = 24'h000018;
        mem[   6] = 24'h00001A;
        mem[   7] = 24'h00001C;
        mem[   8] = 24'h00001E;
        mem[   9] = 24'h00001F;
        mem[  10] = 24'h000021;
        mem[  11] = 24'h000022;
        mem[  12] = 24'h000123;
        mem[  13] = 24'h000A25;
        mem[  14] = 24'h000E26;
        mem[  15] = 24'h001127;
        mem[  16] = 24'h011328;
        mem[  17] = 24'h0A1529;
        mem[  18] = 24'h0D172A;
        mem[  19] = 24'h10192B;
        mem[  20] = 24'h121A2C;
        mem[  21] = 24'h141C2D;
        mem[  22] = 24'h161D2D;
        mem[  23] = 24'h171E2E;
        mem[  24] = 24'h191F2F;
        mem[  25] = 24'h1A2030;
        mem[  26] = 24'h1B2130;
        mem[  27] = 24'h1C2231;
        mem[  28] = 24'h1D2332;
        mem[  29] = 24'h1E2432;
        mem[  30] = 24'h1F2533;
        mem[  31] = 24'h202533;
        mem[  32] = 24'h212634;
        mem[  33] = 24'h222734;
        mem[  34] = 24'h222735;
        mem[  35] = 24'h232835;
        mem[  36] = 24'h242835;
        mem[  37] = 24'h242936;
        mem[  38] = 24'h252936;
        mem[  39] = 24'h252A37;
        mem[  40] = 24'h262A37;
        mem[  41] = 24'h262B37;
        mem[  42] = 24'h272B37;
        mem[  43] = 24'h272B38;
        mem[  44] = 24'h272C38;
        mem[  45] = 24'h282C38;
        mem[  46] = 24'h282C38;
        mem[  47] = 24'h282C39;
        mem[  48] = 24'h292D39;
        mem[  49] = 24'h292D39;
        mem[  50] = 24'h292D39;
        mem[  51] = 24'h292D39;
        mem[  52] = 24'h292D39;
        mem[  53] = 24'h292D39;
        mem[  54] = 24'h292D39;
        mem[  55] = 24'h292D39;
        mem[  56] = 24'h292D39;
        mem[  57] = 24'h2A2E3A;
        mem[  58] = 24'h292D39;
        mem[  59] = 24'h292D39;
        mem[  60] = 24'h292D39;
        mem[  61] = 24'h292D39;
        mem[  62] = 24'h292D39;
        mem[  63] = 24'h292D39;
        mem[  64] = 24'h292D39;
        mem[  65] = 24'h292D39;
        mem[  66] = 24'h292D39;
        mem[  67] = 24'h282C39;
        mem[  68] = 24'h282C38;
        mem[  69] = 24'h282C38;
        mem[  70] = 24'h272C38;
        mem[  71] = 24'h272B38;
        mem[  72] = 24'h272B37;
        mem[  73] = 24'h262B37;
        mem[  74] = 24'h262A37;
        mem[  75] = 24'h252A37;
        mem[  76] = 24'h252936;
        mem[  77] = 24'h242936;
        mem[  78] = 24'h242835;
        mem[  79] = 24'h232835;
        mem[  80] = 24'h222735;
        mem[  81] = 24'h222734;
        mem[  82] = 24'h212634;
        mem[  83] = 24'h202533;
        mem[  84] = 24'h1F2533;
        mem[  85] = 24'h1E2432;
        mem[  86] = 24'h1D2332;
        mem[  87] = 24'h1C2231;
        mem[  88] = 24'h1B2130;
        mem[  89] = 24'h1A2030;
        mem[  90] = 24'h191F2F;
        mem[  91] = 24'h171E2E;
        mem[  92] = 24'h161D2D;
        mem[  93] = 24'h141C2D;
        mem[  94] = 24'h121A2C;
        mem[  95] = 24'h10192B;
        mem[  96] = 24'h0D172A;
        mem[  97] = 24'h0A1529;
        mem[  98] = 24'h011328;
        mem[  99] = 24'h001127;
        mem[ 100] = 24'h000E26;
        mem[ 101] = 24'h000A25;
        mem[ 102] = 24'h000123;
        mem[ 103] = 24'h000022;
        mem[ 104] = 24'h000021;
        mem[ 105] = 24'h00001F;
        mem[ 106] = 24'h00001E;
        mem[ 107] = 24'h00001C;
        mem[ 108] = 24'h00001A;
        mem[ 109] = 24'h000018;
        mem[ 110] = 24'h000015;
        mem[ 111] = 24'h000013;
        mem[ 112] = 24'h00000F;
        mem[ 113] = 24'h00000B;
        mem[ 114] = 24'h000001;
    end

endmodule
