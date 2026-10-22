`timescale 1ns/1ps

module p7_panel #(

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
    input wire I_panel_en,I_on,I_horizontal,I_visual_on,
    input wire [1:0] I_item,
    output wire [6:0] O_font_idx,
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

    wire [11:0] px_next=x-12'd182;
    wire third_next=px_next>=12'd616;
    wire second_next=px_next>=12'd308 && !third_next;
    reg third,second;
    reg [8:0] ix;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin third<=0;second<=0;ix<=0;end
        else begin
            third<=third_next;second<=second_next;
            ix<=third_next ? x[8:0]-9'd286 :
                second_next ? x[8:0]-9'd490 : x[8:0]-9'd182;
        end
    end
    wire [1:0] card=third ? 2'd2 : second ? 2'd1 : 2'd0;

    wire [4:0] cy=py[4:0];
    wire hit=py<32 && (px<300 || (px>=308 && px<608) || (px>=616 && px<916));
    wire border=ix<9'd2 || ix>=9'd298 || cy<5'd2 || cy>=5'd30;
    wire [5:0] name_off=ix[5:0]-6'd16,value_off=ix[5:0]-6'd52;
    wire in_name=ix>=9'd16 && ix<(third ? 9'd112 : 9'd80);
    wire in_value=ix>=9'd180 && ix<9'd244;
    wire [4:0] gx=in_value ? value_off[4:0] : name_off[4:0];
    wire [6:0] name_idx=third ? (ix>=80 ? 7'd48 : name_off[5] ? 7'd11 : 7'd75) : second ? (name_off[5] ? 6'd63 : 6'd62) :
                                             (name_off[5] ? 6'd61 : 6'd60);
    wire [6:0] value_idx=second ?
        (I_horizontal ? (value_off[5] ? 6'd50 : 6'd49) :
                        (value_off[5] ? 6'd14 : 6'd56)) :
        (value_off[5] ? 6'd38 : ((third ? I_visual_on : I_on) ? 6'd0 : 6'd1));

    assign O_font_idx=ix[7] ? value_idx : name_idx;
    assign O_font_row=py[4:0];

    wire switch_en = !second;
    wire switch_on = third ? I_visual_on : I_on;
    wire focus_mark = (card==I_item) && ix>=9'd6 && ix<9'd9 && cy>=5'd11 && cy<5'd21;
    wire switch_track = switch_en && ix>=9'd248 && ix<9'd284 && cy>=5'd9 && cy<5'd23;
    wire switch_knob = switch_track && cy>=5'd11 && cy<5'd21 &&
        (switch_on ? (ix>=9'd270 && ix<9'd282) : (ix>=9'd250 && ix<9'd262));

    wire arrow_right = (ix>=9'd258 && ix<9'd278 && cy>=5'd15 && cy<5'd17) ||
        (ix==9'd278 && cy==5'd16) || (ix==9'd277 && cy>=5'd15 && cy<=5'd17) ||
        (ix==9'd276 && cy>=5'd14 && cy<=5'd18) || (ix==9'd275 && cy>=5'd13 && cy<=5'd19) ||
        (ix==9'd274 && cy>=5'd12 && cy<=5'd20) || (ix==9'd273 && cy>=5'd11 && cy<=5'd21);
    wire arrow_up = (ix>=9'd269 && ix<9'd271 && cy>=5'd10 && cy<5'd24) ||
        (cy==5'd9 && ix>=9'd269 && ix<=9'd270) || (cy==5'd10 && ix>=9'd268 && ix<=9'd271) ||
        (cy==5'd11 && ix>=9'd267 && ix<=9'd272) || (cy==5'd12 && ix>=9'd266 && ix<=9'd273) ||
        (cy==5'd13 && ix>=9'd265 && ix<=9'd274) || (cy==5'd14 && ix>=9'd264 && ix<=9'd275);
    wire arrow_hit = second && (I_horizontal ? arrow_right : arrow_up);
    wire [2:0] decoration = (focus_mark || arrow_hit) ? 3'd1 :
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
            px<=x-12'd182;py<=y-12'd614;
            rgb1<=I_rgb;rgb2<=rgb1;rgb3<=rgb2;
            de_pipe<={de_pipe[2:0],I_de};hs_pipe<={hs_pipe[2:0],I_hs};
            vs_pipe<={vs_pipe[2:0],I_vs};
            hit2<=hit && I_panel_en && de_pipe[0];hit3<=hit2;
            border2<=border;border3<=border2;
            selected2<=card==I_item;selected3<=selected2;
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
