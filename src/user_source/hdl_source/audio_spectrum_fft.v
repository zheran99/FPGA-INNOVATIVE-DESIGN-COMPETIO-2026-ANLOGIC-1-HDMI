`timescale 1ns/1ps

module audio_spectrum_fft (
    input wire I_clk, I_rst, I_en, I_sample_valid,
    input wire [23:0] I_sample_left,
    output reg O_valid,
    output wire [127:0] O_levels
);
    localparam COLLECT=0, READ_A=1, WAIT_A=2, READ_B=3, WAIT_B=4,
               MUL=5, ROTATE=6, WRITE_A=7, WRITE_B=8,
               SCAN_READ=9, SCAN_USE=10, FINISH=11,
               SCAN_SUM=12, SCAN_HEIGHT=13, SCAN_STORE=14;
    reg [3:0] state;
    reg [8:0] sample_count, base, offset, scan_bin;
    reg [3:0] stage;
    wire [8:0] half_span = 9'd1 << stage;
    wire [9:0] full_span = {1'b0, half_span} << 1;
    wire [8:0] addr_a = base + offset;
    wire [8:0] addr_b = addr_a + half_span;
    wire [8:0] reversed_sample = {sample_count[0],sample_count[1],
        sample_count[2],sample_count[3],sample_count[4],sample_count[5],
        sample_count[6],sample_count[7],sample_count[8]};
    wire [7:0] twiddle_addr = offset << (8-stage);
    wire [7:0] cos_addr = twiddle_addr<=128 ? 8'd128-twiddle_addr : twiddle_addr-8'd128;
    wire [7:0] sin_addr = twiddle_addr<=128 ? twiddle_addr : 8'd0-twiddle_addr;
    wire [7:0] rom_addr = state==READ_B || state==WAIT_B ? sin_addr : cos_addr;
    wire [15:0] twiddle_q;
    audio_spectrum_twiddle u_twiddle(I_clk, rom_addr, twiddle_q);
    reg signed [15:0] tw_re, tw_im;
    reg signed [15:0] a_re, a_im, b_re, b_im;
    reg signed [31:0] prod_rr, prod_ii, prod_ri, prod_ir;
    wire signed [32:0] rot_re_full = {prod_rr[31],prod_rr} - {prod_ii[31],prod_ii};
    wire signed [32:0] rot_im_full = {prod_ri[31],prod_ri} + {prod_ir[31],prod_ir};
    reg signed [17:0] rot_re, rot_im;
    wire signed [18:0] sum_re = {{3{a_re[15]}},a_re} + {rot_re[17],rot_re};
    wire signed [18:0] sum_im = {{3{a_im[15]}},a_im} + {rot_im[17],rot_im};
    wire signed [18:0] diff_re = {{3{a_re[15]}},a_re} - {rot_re[17],rot_re};
    wire signed [18:0] diff_im = {{3{a_im[15]}},a_im} - {rot_im[17],rot_im};
    wire [31:0] fft_q;
    wire ram_write = !I_rst && I_en &&
        ((state == COLLECT && I_sample_valid) || state == WRITE_A || state == WRITE_B);
    wire [8:0] wr_addr = state == COLLECT ? reversed_sample :
                         state == WRITE_A ? addr_a : addr_b;
    wire [31:0] wr_data = state == COLLECT ? {I_sample_left[23:8],16'd0} :
        state == WRITE_A ? {sum_re[16:1],sum_im[16:1]} : {diff_re[16:1],diff_im[16:1]};
    wire [8:0] rd_addr = state >= SCAN_READ ? scan_bin :
                         state == READ_B || state == WAIT_B ? addr_b : addr_a;
    audio_spectrum_ram u_fft_ram(I_clk, ram_write, wr_addr, wr_data, rd_addr, fft_q);

    function [3:0] band_for_bin;
        input [8:0] bin;
        begin
            if (bin<28) begin
                if (bin<6) begin
                    if (bin<3) band_for_bin=bin<2 ? 0 : 1;
                    else band_for_bin=bin<4 ? 2 : 3;
                end else if (bin<13) band_for_bin=bin<9 ? 4 : 5;
                else band_for_bin=bin<19 ? 6 : 7;
            end else begin
                if (bin<126) begin
                    if (bin<60) band_for_bin=bin<41 ? 8 : 9;
                    else band_for_bin=bin<87 ? 10 : 11;
                end else if (bin<211) band_for_bin=bin<171 ? 12 : 13;
                else band_for_bin=bin<241 ? 14 : 15;
            end
        end
    endfunction
    wire [15:0] abs_re = fft_q[31] ? (~fft_q[31:16]+16'd1) : fft_q[31:16];
    wire [15:0] abs_im = fft_q[15] ? (~fft_q[15:0]+16'd1) : fft_q[15:0];
    reg [15:0] abs_re_d,abs_im_d;
    reg [16:0] magnitude;
    reg [7:0] scan_height_d;
    reg [3:0] scan_band_d;
    reg [15:0] scan_select_d;
    reg [7:0] scan_peak;
    reg scan_new_band_d;
    wire scan_better=scan_new_band_d || scan_height_d>scan_peak;

    function [7:0] height_for_magnitude;
        input [16:0] mag;
        begin
            if (|mag[16:15]) height_for_magnitude=80;
            else if (mag[14]) height_for_magnitude=73+{5'b0,mag[13:11]};
            else if (mag[13]) height_for_magnitude=65+{5'b0,mag[12:10]};
            else if (mag[12]) height_for_magnitude=57+{5'b0,mag[11:9]};
            else if (mag[11]) height_for_magnitude=49+{5'b0,mag[10:8]};
            else if (mag[10]) height_for_magnitude=41+{5'b0,mag[9:7]};
            else if (mag[9]) height_for_magnitude=33+{5'b0,mag[8:6]};
            else if (mag[8]) height_for_magnitude=25+{5'b0,mag[7:5]};
            else if (mag[7]) height_for_magnitude=17+{5'b0,mag[6:4]};
            else if (mag[6]) height_for_magnitude=9+{5'b0,mag[5:3]};
            else if (mag[5]) height_for_magnitude=1+{5'b0,mag[4:2]};
            else height_for_magnitude=0;
        end
    endfunction
    reg [7:0] levels [0:15];

    reg [3:0] scan_band;
    wire [7:0] scan_height = height_for_magnitude(magnitude);
    genvar g;
    generate for (g=0; g<16; g=g+1) begin: pack_levels
        assign O_levels[g*8 +: 8] = levels[g];

        always @(posedge I_clk or posedge I_rst) begin
            if (I_rst) levels[g]<=0;
            else if (!I_en || (state==WRITE_B && !(offset+9'd1 < half_span) &&
                     !({1'b0,base}+full_span < 512) && stage==8)) levels[g]<=0;
            else if (state==SCAN_STORE && scan_select_d[g] && scan_better)
                levels[g]<=scan_height_d;
        end
    end endgenerate
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            state<=COLLECT; sample_count<=0; base<=0; offset<=0; stage<=0;
            scan_bin<=1; O_valid<=0;
            a_re<=0; a_im<=0; b_re<=0; b_im<=0;
            prod_rr<=0; prod_ii<=0; prod_ri<=0; prod_ir<=0; rot_re<=0; rot_im<=0;
            tw_re<=0; tw_im<=0;
            abs_re_d<=0;abs_im_d<=0;magnitude<=0;scan_height_d<=0;scan_band_d<=0;
            scan_select_d<=0;scan_band<=0;
            scan_peak<=0;scan_new_band_d<=0;
        end else begin
            O_valid<=0;
            if (!I_en) begin
                state<=COLLECT; sample_count<=0; base<=0; offset<=0; stage<=0;
            end else case (state)
                COLLECT: if (I_sample_valid) begin
                    if (sample_count==511) begin
                        sample_count<=0; base<=0; offset<=0; stage<=0; state<=READ_A;
                    end else sample_count<=sample_count+1'b1;
                end
                READ_A: state<=WAIT_A;
                WAIT_A: begin
                    a_re<=fft_q[31:16]; a_im<=fft_q[15:0];
                    tw_re<=twiddle_addr<=128 ? $signed(twiddle_q) : -$signed(twiddle_q);
                    state<=READ_B;
                end
                READ_B: state<=WAIT_B;
                WAIT_B: begin
                    b_re<=fft_q[31:16]; b_im<=fft_q[15:0];
                    tw_im<=-$signed(twiddle_q); state<=MUL;
                end
                MUL: begin
                    prod_rr<=b_re*tw_re; prod_ii<=b_im*tw_im;
                    prod_ri<=b_re*tw_im; prod_ir<=b_im*tw_re; state<=ROTATE;
                end
                ROTATE: begin rot_re<=rot_re_full>>>15; rot_im<=rot_im_full>>>15; state<=WRITE_A; end
                WRITE_A: state<=WRITE_B;
                WRITE_B: begin
                    if (offset+9'd1 < half_span) begin offset<=offset+1'b1; state<=READ_A; end
                    else if ({1'b0,base}+full_span < 512) begin
                        base<=base+full_span; offset<=0; state<=READ_A;
                    end else if (stage<8) begin stage<=stage+1'b1; base<=0; offset<=0; state<=READ_A; end
                    else begin
                        scan_bin<=1; state<=SCAN_READ;
                    end
                end
                SCAN_READ: begin scan_band<=band_for_bin(scan_bin); state<=SCAN_USE; end
                SCAN_USE: begin
                    abs_re_d<=abs_re;abs_im_d<=abs_im;state<=SCAN_SUM;
                end
                SCAN_SUM: begin
                    magnitude<={1'b0,abs_re_d}+{1'b0,abs_im_d};state<=SCAN_HEIGHT;
                end
                SCAN_HEIGHT: begin
                    scan_height_d<=scan_height;scan_band_d<=scan_band;state<=SCAN_STORE;
                    scan_select_d<=16'b1<<scan_band;
                    scan_new_band_d<=scan_bin==1 || scan_band!=scan_band_d;
                end
                SCAN_STORE: begin
                    if(scan_better)scan_peak<=scan_height_d;
                    if (scan_bin==255) state<=FINISH;
                    else begin scan_bin<=scan_bin+1'b1; state<=SCAN_READ; end
                end
                FINISH: begin O_valid<=1; state<=COLLECT; end
                default: begin state<=COLLECT; sample_count<=0; end
            endcase
        end
    end
endmodule

module audio_spectrum_ram (
    input wire clk, wr_en,
    input wire [8:0] wr_addr,
    input wire [31:0] wr_data,
    input wire [8:0] rd_addr,
    output reg [31:0] q
);
    reg [31:0] mem [0:511];
    always @(posedge clk) begin
        if (wr_en) mem[wr_addr]<=wr_data;
        q<=mem[rd_addr];
    end
endmodule
