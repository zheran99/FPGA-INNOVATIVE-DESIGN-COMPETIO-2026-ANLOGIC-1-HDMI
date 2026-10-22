`timescale 1ns/1ps

module p3_panel #(

    parameter [23:0] C_SEL_BORD = 24'h67DDC8,
                     C_SEL_FILL = 24'h183738,
                     C_BORD     = 24'h455763,
                     C_TXT      = 24'hE0F1EF,
                     C_FILL     = 24'h14212A,
                     C_NAME_DIM = 24'hADC2CA,
                     C_VALUE    = 24'hA0F1DE,
                     C_OFF      = 24'hBCC9D2,
                     C_TRACK_ON = 24'h408F80,
                     C_TRACK_OFF= 24'h53616D,
                     C_KNOB_ON  = 24'hE6FFF8,
                     C_KNOB_OFF = 24'hB1BEC8
)(
    input wire I_clk,I_rst,I_de,I_hs,I_vs,
    input wire [23:0] I_rgb,
    input wire I_panel_en,I_on,
    input wire [2:0] I_type,
    output wire [5:0] O_font_idx,
    output wire [4:0] O_font_row,
    input wire [31:0] I_font_word,
    output wire O_de,O_hs,O_vs,
    output reg [23:0] O_rgb
);
    wire [11:0] x,y;
    osd_position u_pos(.clk(I_clk),.rst(I_rst),.de(I_de),.vs(I_vs),.x(x),.y(y),.pos_vld());
    reg [11:0] px,py;
    reg [23:0] rgb1,rgb2,rgb3;
    reg [3:0] de_pipe,hs_pipe,vs_pipe;
    wire second=px>=308;

    wire [8:0] ix=second ? px[8:0]-9'd308 : px[8:0];
    wire [4:0] cy=py[4:0];
    wire hit=py<32 && (px<300 || (px>=308 && px<608));
    wire border=second ? (px<12'd310 || px>=12'd606 || cy<5'd2 || cy>=5'd30) :
        (px<12'd2 || px>=12'd298 || cy<5'd2 || cy>=5'd30);
    localparam [5:0] CN_BLANK  = 6'd38;   // 空格（现有空位，全 0 不画）
    localparam [5:0] CN_SHUN   = 6'd43;   // 瞬
    localparam [5:0] CN_QIE    = 6'd44;   // 切
    localparam [5:0] CN_JIAO   = 6'd45;   // 交
    localparam [5:0] CN_CHA    = 6'd46;   // 叉
    localparam [5:0] CN_DAN    = 6'd47;   // 淡
    localparam [5:0] CN_HUA    = 6'd48;   // 化
    localparam [5:0] CN_SHUI   = 6'd49;   // 水
    localparam [5:0] CN_PING   = 6'd50;   // 平
    localparam [5:0] CN_CA     = 6'd51;   // 擦
    localparam [5:0] CN_CHU    = 6'd52;   // 除
    localparam [5:0] CN_BAI    = 6'd53;   // 百
    localparam [5:0] CN_YE     = 6'd54;   // 叶
    localparam [5:0] CN_CHUANG = 6'd55;   // 窗
    localparam [5:0] CN_SHU    = 6'd56;   // 竖
    localparam [5:0] CN_TIAO   = 6'd57;   // 条
    localparam [5:0] CN_WANG   = 6'd58;   // 网
    localparam [5:0] CN_GE     = 6'd59;   // 格

    function [5:0] str_char;
        input [2:0] mode;
        input [1:0] col;
        begin
            case ({mode, col})
                {3'd0, 2'd0}: str_char = CN_SHUN;   // 瞬切
                {3'd0, 2'd1}: str_char = CN_QIE;
                {3'd0, 2'd2}: str_char = CN_BLANK;
                {3'd0, 2'd3}: str_char = CN_BLANK;

                {3'd1, 2'd0}: str_char = CN_JIAO;   // 交叉淡化
                {3'd1, 2'd1}: str_char = CN_CHA;
                {3'd1, 2'd2}: str_char = CN_DAN;
                {3'd1, 2'd3}: str_char = CN_HUA;

                {3'd2, 2'd0}: str_char = CN_SHUI;   // 水平擦除
                {3'd2, 2'd1}: str_char = CN_PING;
                {3'd2, 2'd2}: str_char = CN_CA;
                {3'd2, 2'd3}: str_char = CN_CHU;

                {3'd3, 2'd0}: str_char = CN_BAI;    // 百叶窗
                {3'd3, 2'd1}: str_char = CN_YE;
                {3'd3, 2'd2}: str_char = CN_CHUANG;
                {3'd3, 2'd3}: str_char = CN_BLANK;

                {3'd4, 2'd0}: str_char = CN_SHU;    // 竖条
                {3'd4, 2'd1}: str_char = CN_TIAO;
                {3'd4, 2'd2}: str_char = CN_BLANK;
                {3'd4, 2'd3}: str_char = CN_BLANK;

                {3'd5, 2'd0}: str_char = CN_WANG;   // 网格
                {3'd5, 2'd1}: str_char = CN_GE;
                {3'd5, 2'd2}: str_char = CN_BLANK;
                {3'd5, 2'd3}: str_char = CN_BLANK;

                default: str_char = CN_BLANK;
            endcase
        end
    endfunction

    wire [6:0] name_off=second ? {1'b0,ix[5:0]-6'd16} : ix[6:0]-7'd86;
    wire [5:0] value_off=ix[5:0]-6'd52;
    wire in_name=(px>=12'd324 && px<12'd388) || (px>=12'd86 && px<12'd214);
    wire in_value=px>=12'd488 && px<12'd552;
    wire [4:0] gx=in_value ? value_off[4:0] : name_off[4:0];

    wire [5:0] effect_idx=px<12'd118 ? str_char(I_type,2'd0) :
        px<12'd150 ? str_char(I_type,2'd1) :
        px<12'd182 ? str_char(I_type,2'd2) : str_char(I_type,2'd3);
    wire [5:0] value_idx=px>=12'd520 ? CN_BLANK : (I_on ? 6'd0 : 6'd1);

    assign O_font_idx=second ? (px>=12'd488 ? value_idx : (px>=12'd356 ? 6'd1 : 6'd0)) : effect_idx;
    assign O_font_row=py[4:0];

    wire switch_en = second;
    wire switch_on = I_on;
    wire focus_mark = px>=12'd6 && px<12'd9 && cy>=5'd11 && cy<5'd21;
    wire switch_track = px>=12'd556 && px<12'd592 && cy>=5'd9 && cy<5'd23;
    wire switch_knob = switch_track && cy>=5'd11 && cy<5'd21 &&
        (switch_on ? (px>=12'd578 && px<12'd590) : (px>=12'd558 && px<12'd570));
    wire [2:0] decoration = focus_mark ? 3'd1 :
        switch_knob ? (switch_on ? 3'd4 : 3'd5) :
        switch_track ? (switch_on ? 3'd2 : 3'd3) : 3'd0;
    reg [2:0] decoration_d2, decoration_d3;
    reg value_d2, value_d3, off_d2, off_d3;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            decoration_d2<=0; decoration_d3<=0;
            value_d2<=0; value_d3<=0; off_d2<=0; off_d3<=0;
        end else begin
            decoration_d2<=decoration; decoration_d3<=decoration_d2;
            value_d2<=in_value; value_d3<=value_d2;
            off_d2<=switch_en && !switch_on; off_d3<=off_d2;
        end
    end
    wire [23:0] decoration_color = decoration_d3==1 ? C_VALUE :
        decoration_d3==2 ? C_TRACK_ON : decoration_d3==3 ? C_TRACK_OFF :
        decoration_d3==4 ? C_KNOB_ON : C_KNOB_OFF;

    reg hit2,hit3,border2,border3,selected2,selected3,text2,pixel3;
    reg [4:0] gx2;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            px<=0;py<=0;rgb1<=0;rgb2<=0;rgb3<=0;O_rgb<=0;
            de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
            hit2<=0;hit3<=0;border2<=0;border3<=0;
            selected2<=0;selected3<=0;text2<=0;pixel3<=0;gx2<=0;
        end else begin
            px<=x-12'd336;py<=y-12'd614;
            rgb1<=I_rgb;rgb2<=rgb1;rgb3<=rgb2;
            de_pipe<={de_pipe[2:0],I_de};hs_pipe<={hs_pipe[2:0],I_hs};
            vs_pipe<={vs_pipe[2:0],I_vs};
            hit2<=hit && I_panel_en && de_pipe[0];hit3<=hit2;
            border2<=border;border3<=border2;
            selected2<=!second;selected3<=selected2;
            text2<=in_name || in_value;gx2<=gx;
            pixel3<=text2 && I_font_word[5'd31-gx2];
            if(!hit3) O_rgb<=rgb3;
            else if(pixel3) O_rgb<=value_d3 ? (off_d3 ? C_OFF : C_VALUE) : (selected3 ? C_TXT : C_NAME_DIM);
            else if(decoration_d3!=0) O_rgb<=decoration_color;
            else if(border3) O_rgb<=selected3 ? C_SEL_BORD : C_BORD;
            else O_rgb<=selected3 ? C_SEL_FILL : C_FILL;
        end
    end
    assign O_de=de_pipe[3];assign O_hs=hs_pipe[3];assign O_vs=vs_pipe[3];
endmodule
