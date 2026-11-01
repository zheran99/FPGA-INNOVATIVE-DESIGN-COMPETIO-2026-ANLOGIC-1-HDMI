localparam TOUCH_HEIGHT=264, TOUCH_PAGES=6, TOUCH_ROW_HEIGHT=44;
localparam TOUCH_GLYPHS=174;
localparam TOUCH_H_LEFT_X=9'd8, TOUCH_H_SIDE_W=9'd108,
    TOUCH_H_RIGHT_X=9'd364, TOUCH_H_MID_X=9'd124, TOUCH_H_MID_W=9'd232,
    TOUCH_H_BAR_Y=9'd4, TOUCH_H_BAR_H=9'd126, TOUCH_H_BAR2_Y=9'd134,
    TOUCH_H_LABEL_Y=9'd104, TOUCH_H_CAP_X=9'd292, TOUCH_H_CAP_Y=9'd54,
    TOUCH_H_CAP2_Y=9'd184;
localparam TOUCH_H_L_X0=TOUCH_H_LEFT_X, TOUCH_H_L_X1=TOUCH_H_LEFT_X+TOUCH_H_SIDE_W,
    TOUCH_H_L_Y0=9'd0, TOUCH_H_L_Y1=TOUCH_H_L_Y0+TOUCH_HEIGHT-9'd1,
    TOUCH_H_R_X0=TOUCH_H_RIGHT_X, TOUCH_H_R_X1=TOUCH_H_RIGHT_X+TOUCH_H_SIDE_W,
    TOUCH_H_R_Y0=9'd0, TOUCH_H_R_Y1=TOUCH_H_R_Y0+TOUCH_HEIGHT-9'd1,
    TOUCH_H_M1_X0=TOUCH_H_MID_X, TOUCH_H_M1_X1=TOUCH_H_MID_X+TOUCH_H_MID_W,
    TOUCH_H_M1_Y0=TOUCH_H_BAR_Y, TOUCH_H_M1_Y1=TOUCH_H_BAR_Y+TOUCH_H_BAR_H-9'd1,
    TOUCH_H_M2_X0=TOUCH_H_MID_X, TOUCH_H_M2_X1=TOUCH_H_MID_X+TOUCH_H_MID_W,
    TOUCH_H_M2_Y0=TOUCH_H_BAR2_Y, TOUCH_H_M2_Y1=TOUCH_H_BAR2_Y+TOUCH_H_BAR_H-9'd1;
localparam TOUCH_H_LB_XL=TOUCH_H_LEFT_X+(TOUCH_H_SIDE_W>>1)-9'd24, TOUCH_H_LB_XR=TOUCH_H_RIGHT_X+(TOUCH_H_SIDE_W>>1)-9'd24,
    TOUCH_H_LB_XM=TOUCH_H_MID_X+9'd16,
    TOUCH_H_LB_YS=TOUCH_H_BAR_Y+TOUCH_H_LABEL_Y,
    TOUCH_H_LB_YM1=TOUCH_H_BAR_Y+(TOUCH_H_BAR_H>>1)-9'd8,
    TOUCH_H_LB_YM2=TOUCH_H_BAR2_Y+(TOUCH_H_BAR_H>>1)-9'd8;
function [7:0] touch_row; input [2:0] page; input [8:0] cy,cx; begin touch_row=255;
if(cx>=9'd8 && cx<9'd472) begin case(page)
3'd0:begin
if(cx>=9'd8 && cx<9'd116 && cy>=9'd0 && cy<9'd264) touch_row=8'd4;
if(cx>=9'd364 && cx<9'd472 && cy>=9'd0 && cy<9'd264) touch_row=8'd5;
if(cx>=9'd124 && cx<9'd356 && cy>=9'd4 && cy<9'd130) touch_row=8'd6;
if(cx>=9'd124 && cx<9'd356 && cy>=9'd134 && cy<9'd260) touch_row=8'd7;
end
3'd1:begin
if(cy>=9'd0 && cy<9'd44) touch_row=8'd8;
if(cy>=9'd44 && cy<9'd88) touch_row=8'd9;
if(cy>=9'd88 && cy<9'd132) touch_row=8'd27;
if(cy>=9'd132 && cy<9'd176) touch_row=8'd28;
if(cy>=9'd176 && cy<9'd220) touch_row=8'd29;
if(cy>=9'd220 && cy<9'd264) touch_row=8'd30;
end
3'd2:begin
if(cy>=9'd0 && cy<9'd44) touch_row=8'd0;
if(cy>=9'd44 && cy<9'd88) touch_row=8'd1;
if(cy>=9'd88 && cy<9'd132) touch_row=8'd2;
if(cy>=9'd132 && cy<9'd176) touch_row=8'd3;
if(cy>=9'd176 && cy<9'd220) touch_row=8'd21;
if(cy>=9'd220 && cy<9'd264) touch_row=8'd31;
end
3'd3:begin
if(cy>=9'd0 && cy<9'd44) touch_row=8'd10;
if(cy>=9'd44 && cy<9'd88) touch_row=8'd11;
if(cy>=9'd88 && cy<9'd132) touch_row=8'd12;
if(cy>=9'd132 && cy<9'd176) touch_row=8'd13;
if(cy>=9'd176 && cy<9'd220) touch_row=8'd14;
if(cy>=9'd220 && cy<9'd264) touch_row=8'd15;
end
3'd4:begin
if(cy>=9'd0 && cy<9'd44) touch_row=8'd16;
if(cy>=9'd44 && cy<9'd88) touch_row=8'd25;
if(cy>=9'd88 && cy<9'd132) touch_row=8'd17;
if(cy>=9'd132 && cy<9'd176) touch_row=8'd18;
if(cy>=9'd176 && cy<9'd220) touch_row=8'd19;
if(cy>=9'd220 && cy<9'd264) touch_row=8'd20;
end
3'd5:begin
if(cy>=9'd88 && cy<9'd132) touch_row=8'd23;
if(cy>=9'd132 && cy<9'd176) touch_row=8'd24;
end
default:; endcase end end endfunction
function [5:0] touch_changed_rows; input [2:0] page;
input [31:0] changes; begin touch_changed_rows=0; case(page)
3'd0:begin
if(changes[4] || changes[5] || changes[6] || changes[7]) touch_changed_rows=6'b111111;
end
3'd1:begin
touch_changed_rows[0]=changes[8];
touch_changed_rows[1]=changes[9];
touch_changed_rows[2]=changes[27];
touch_changed_rows[3]=changes[28];
touch_changed_rows[4]=changes[29];
touch_changed_rows[5]=changes[30];
end
3'd2:begin
touch_changed_rows[0]=changes[0];
touch_changed_rows[1]=changes[1];
touch_changed_rows[2]=changes[2];
touch_changed_rows[3]=changes[3];
touch_changed_rows[4]=changes[21];
touch_changed_rows[5]=changes[31];
end
3'd3:begin
touch_changed_rows[0]=changes[10];
touch_changed_rows[1]=changes[11];
touch_changed_rows[2]=changes[12];
touch_changed_rows[3]=changes[13];
touch_changed_rows[4]=changes[14];
touch_changed_rows[5]=changes[15];
end
3'd4:begin
touch_changed_rows[0]=changes[16];
touch_changed_rows[1]=changes[25];
touch_changed_rows[2]=changes[17];
touch_changed_rows[3]=changes[18];
touch_changed_rows[4]=changes[19];
touch_changed_rows[5]=changes[20];
end
3'd5:begin
touch_changed_rows[2]=changes[23];
touch_changed_rows[3]=changes[24];
end
default:; endcase end endfunction
function [5:0] touch_focus_row; input [7:0] encoded;
begin touch_focus_row=0; case(encoded)
8'd8,8'd10,8'd12,8'd14:touch_focus_row=6'b111111;
8'd0,8'd16,8'd20,8'd32:touch_focus_row=6'd1;
8'd2,8'd18,8'd22,8'd50:touch_focus_row=6'd2;
8'd4,8'd24,8'd34,8'd46,8'd54:touch_focus_row=6'd4;
8'd6,8'd26,8'd36,8'd48,8'd56:touch_focus_row=6'd8;
8'd28,8'd38,8'd42,8'd58:touch_focus_row=6'd16;
8'd30,8'd40,8'd60,8'd62:touch_focus_row=6'd32;
default:; endcase end endfunction
localparam TOUCH_SLIDER_LEFT=192, TOUCH_SLIDER_RIGHT=448;
function [7:0] touch_slider_scaled; input [7:0] id; input [15:0] p25;
reg [15:0] ticks; begin
case(id)
0:begin ticks=((p25<<2)+128)>>8; touch_slider_scaled=ticks[7:0]; end
1:begin ticks=((p25<<1)+p25+128)>>8; touch_slider_scaled=50+(ticks[7:0]<<1); end
2:begin ticks=((p25<<2)+128)>>8; touch_slider_scaled=ticks[7:0]<<1; end
3:begin ticks=((p25<<1)+128)>>8; touch_slider_scaled=ticks[7:0]<<1; end
27:begin ticks=((p25<<2)+128)>>8; touch_slider_scaled=ticks[7:0]; end
28:begin ticks=((p25<<1)+p25+128)>>8; touch_slider_scaled=50+(ticks[7:0]<<1); end
29:begin ticks=((p25<<2)+128)>>8; touch_slider_scaled=ticks[7:0]<<1; end
30:begin ticks=((p25<<1)+128)>>8; touch_slider_scaled=ticks[7:0]<<1; end
default:begin ticks=0; touch_slider_scaled=0; end
endcase end endfunction
function [7:0] touch_slider_value; input [7:0] id; input [8:0] x;
reg [8:0] pos; reg [15:0] p25; begin
pos=x<=192?0:(x>=448?256:x-192);
p25=({7'd0,pos}<<4)+({7'd0,pos}<<3)+pos;
touch_slider_value=touch_slider_scaled(id,p25); end endfunction
function [8:0] touch_top; input [7:0] id; begin
touch_top=0; case(id)
4:touch_top=9'd0;
5:touch_top=9'd0;
6:touch_top=9'd4;
7:touch_top=9'd134;
8:touch_top=9'd0;
9:touch_top=9'd44;
27:touch_top=9'd88;
28:touch_top=9'd132;
29:touch_top=9'd176;
30:touch_top=9'd220;
0:touch_top=9'd0;
1:touch_top=9'd44;
2:touch_top=9'd88;
3:touch_top=9'd132;
21:touch_top=9'd176;
31:touch_top=9'd220;
10:touch_top=9'd0;
11:touch_top=9'd44;
12:touch_top=9'd88;
13:touch_top=9'd132;
14:touch_top=9'd176;
15:touch_top=9'd220;
16:touch_top=9'd0;
25:touch_top=9'd44;
17:touch_top=9'd88;
18:touch_top=9'd132;
19:touch_top=9'd176;
20:touch_top=9'd220;
23:touch_top=9'd88;
24:touch_top=9'd132;
default:; endcase end endfunction
function [2:0] touch_page; input [7:0] id; begin
touch_page=7; case(id)
4:touch_page=3'd0;
5:touch_page=3'd0;
6:touch_page=3'd0;
7:touch_page=3'd0;
8:touch_page=3'd1;
9:touch_page=3'd1;
27:touch_page=3'd1;
28:touch_page=3'd1;
29:touch_page=3'd1;
30:touch_page=3'd1;
0:touch_page=3'd2;
1:touch_page=3'd2;
2:touch_page=3'd2;
3:touch_page=3'd2;
21:touch_page=3'd2;
31:touch_page=3'd2;
10:touch_page=3'd3;
11:touch_page=3'd3;
12:touch_page=3'd3;
13:touch_page=3'd3;
14:touch_page=3'd3;
15:touch_page=3'd3;
16:touch_page=3'd4;
25:touch_page=3'd4;
17:touch_page=3'd4;
18:touch_page=3'd4;
19:touch_page=3'd4;
20:touch_page=3'd4;
23:touch_page=3'd5;
24:touch_page=3'd5;
default:; endcase end endfunction
function [2:0] touch_target; input [7:0] id; begin
touch_target=7; case(id)
4:touch_target=3'd4;
5:touch_target=3'd4;
6:touch_target=3'd4;
7:touch_target=3'd4;
8:touch_target=3'd0;
9:touch_target=3'd0;
27:touch_target=3'd0;
28:touch_target=3'd0;
29:touch_target=3'd0;
30:touch_target=3'd0;
0:touch_target=3'd0;
1:touch_target=3'd0;
2:touch_target=3'd0;
3:touch_target=3'd0;
21:touch_target=3'd3;
31:touch_target=3'd3;
10:touch_target=3'd1;
11:touch_target=3'd1;
12:touch_target=3'd1;
13:touch_target=3'd1;
14:touch_target=3'd1;
15:touch_target=3'd1;
16:touch_target=3'd2;
25:touch_target=3'd2;
17:touch_target=3'd2;
18:touch_target=3'd2;
19:touch_target=3'd2;
20:touch_target=3'd2;
23:touch_target=3'd5;
24:touch_target=3'd5;
default:; endcase end endfunction
function [3:0] touch_field; input [7:0] id; begin
touch_field=0; case(id)
4:touch_field=4'd0;
5:touch_field=4'd1;
6:touch_field=4'd2;
7:touch_field=4'd3;
8:touch_field=4'd4;
9:touch_field=4'd5;
27:touch_field=4'd6;
28:touch_field=4'd7;
29:touch_field=4'd8;
30:touch_field=4'd9;
0:touch_field=4'd0;
1:touch_field=4'd1;
2:touch_field=4'd2;
3:touch_field=4'd3;
21:touch_field=4'd0;
31:touch_field=4'd3;
10:touch_field=4'd4;
11:touch_field=4'd5;
12:touch_field=4'd6;
13:touch_field=4'd1;
14:touch_field=4'd3;
15:touch_field=4'd2;
16:touch_field=4'd0;
25:touch_field=4'd5;
17:touch_field=4'd1;
18:touch_field=4'd2;
19:touch_field=4'd3;
20:touch_field=4'd4;
23:touch_field=4'd2;
24:touch_field=4'd3;
default:; endcase end endfunction
function [7:0] touch_min; input [7:0] id; begin
touch_min=0; case(id)
4:touch_min=8'd0;
5:touch_min=8'd0;
6:touch_min=8'd0;
7:touch_min=8'd0;
8:touch_min=8'd0;
9:touch_min=8'd0;
27:touch_min=8'd0;
28:touch_min=8'd50;
29:touch_min=8'd0;
30:touch_min=8'd0;
0:touch_min=8'd0;
1:touch_min=8'd50;
2:touch_min=8'd0;
3:touch_min=8'd0;
21:touch_min=8'd0;
31:touch_min=8'd0;
10:touch_min=8'd0;
11:touch_min=8'd0;
12:touch_min=8'd0;
13:touch_min=8'd0;
14:touch_min=8'd0;
15:touch_min=8'd0;
16:touch_min=8'd0;
25:touch_min=8'd0;
17:touch_min=8'd0;
18:touch_min=8'd0;
19:touch_min=8'd0;
20:touch_min=8'd0;
23:touch_min=8'd0;
24:touch_min=8'd0;
default:; endcase end endfunction
function [7:0] touch_max; input [7:0] id; begin
touch_max=0; case(id)
4:touch_max=8'd0;
5:touch_max=8'd0;
6:touch_max=8'd1;
7:touch_max=8'd1;
8:touch_max=8'd5;
9:touch_max=8'd1;
27:touch_max=8'd100;
28:touch_max=8'd200;
29:touch_max=8'd200;
30:touch_max=8'd100;
0:touch_max=8'd100;
1:touch_max=8'd200;
2:touch_max=8'd200;
3:touch_max=8'd100;
21:touch_max=8'd1;
31:touch_max=8'd4;
10:touch_max=8'd1;
11:touch_max=8'd1;
12:touch_max=8'd2;
13:touch_max=8'd2;
14:touch_max=8'd1;
15:touch_max=8'd1;
16:touch_max=8'd2;
25:touch_max=8'd2;
17:touch_max=8'd1;
18:touch_max=8'd6;
19:touch_max=8'd2;
20:touch_max=8'd1;
23:touch_max=8'd0;
24:touch_max=8'd0;
default:; endcase end endfunction
function [7:0] touch_step; input [7:0] id; begin
touch_step=0; case(id)
4:touch_step=8'd0;
5:touch_step=8'd0;
6:touch_step=8'd0;
7:touch_step=8'd0;
8:touch_step=8'd0;
9:touch_step=8'd0;
27:touch_step=8'd1;
28:touch_step=8'd2;
29:touch_step=8'd2;
30:touch_step=8'd2;
0:touch_step=8'd1;
1:touch_step=8'd2;
2:touch_step=8'd2;
3:touch_step=8'd2;
21:touch_step=8'd0;
31:touch_step=8'd0;
10:touch_step=8'd0;
11:touch_step=8'd0;
12:touch_step=8'd0;
13:touch_step=8'd0;
14:touch_step=8'd0;
15:touch_step=8'd0;
16:touch_step=8'd0;
25:touch_step=8'd0;
17:touch_step=8'd0;
18:touch_step=8'd0;
19:touch_step=8'd0;
20:touch_step=8'd0;
23:touch_step=8'd0;
24:touch_step=8'd0;
default:; endcase end endfunction
function [7:0] touch_label; input [7:0] id; input [4:0] ch;
begin touch_label=0;
if(id==8'd4) begin case(ch)
0:touch_label=8'd16;
1:touch_label=8'd17;
2:touch_label=8'd18;
default:; endcase end
if(id==8'd5) begin case(ch)
0:touch_label=8'd19;
1:touch_label=8'd17;
2:touch_label=8'd18;
default:; endcase end
if(id==8'd6) begin case(ch)
0:touch_label=8'd20;
1:touch_label=8'd12;
default:; endcase end
if(id==8'd7) begin case(ch)
0:touch_label=8'd4;
1:touch_label=8'd48;
2:touch_label=8'd21;
3:touch_label=8'd22;
default:; endcase end
if(id==8'd8) begin case(ch)
0:touch_label=8'd14;
1:touch_label=8'd15;
2:touch_label=8'd23;
3:touch_label=8'd24;
default:; endcase end
if(id==8'd9) begin case(ch)
0:touch_label=8'd14;
1:touch_label=8'd15;
2:touch_label=8'd25;
3:touch_label=8'd26;
default:; endcase end
if(id==8'd27) begin case(ch)
0:touch_label=8'd100;
1:touch_label=8'd5;
2:touch_label=8'd6;
default:; endcase end
if(id==8'd28) begin case(ch)
0:touch_label=8'd100;
1:touch_label=8'd7;
2:touch_label=8'd8;
3:touch_label=8'd6;
default:; endcase end
if(id==8'd29) begin case(ch)
0:touch_label=8'd100;
1:touch_label=8'd9;
2:touch_label=8'd10;
3:touch_label=8'd6;
default:; endcase end
if(id==8'd30) begin case(ch)
0:touch_label=8'd100;
1:touch_label=8'd4;
2:touch_label=8'd11;
default:; endcase end
if(id==8'd0) begin case(ch)
0:touch_label=8'd5;
1:touch_label=8'd6;
default:; endcase end
if(id==8'd1) begin case(ch)
0:touch_label=8'd7;
1:touch_label=8'd8;
2:touch_label=8'd6;
default:; endcase end
if(id==8'd2) begin case(ch)
0:touch_label=8'd9;
1:touch_label=8'd10;
2:touch_label=8'd6;
default:; endcase end
if(id==8'd3) begin case(ch)
0:touch_label=8'd4;
1:touch_label=8'd11;
default:; endcase end
if(id==8'd21) begin case(ch)
0:touch_label=8'd48;
1:touch_label=8'd49;
2:touch_label=8'd25;
3:touch_label=8'd26;
default:; endcase end
if(id==8'd31) begin case(ch)
0:touch_label=8'd153;
1:touch_label=8'd61;
default:; endcase end
if(id==8'd10) begin case(ch)
0:touch_label=8'd27;
1:touch_label=8'd28;
2:touch_label=8'd25;
3:touch_label=8'd26;
default:; endcase end
if(id==8'd11) begin case(ch)
0:touch_label=8'd29;
1:touch_label=8'd30;
default:; endcase end
if(id==8'd12) begin case(ch)
0:touch_label=8'd31;
1:touch_label=8'd32;
default:; endcase end
if(id==8'd13) begin case(ch)
0:touch_label=8'd27;
1:touch_label=8'd28;
2:touch_label=8'd33;
3:touch_label=8'd34;
default:; endcase end
if(id==8'd14) begin case(ch)
0:touch_label=8'd27;
1:touch_label=8'd35;
default:; endcase end
if(id==8'd15) begin case(ch)
0:touch_label=8'd36;
1:touch_label=8'd37;
2:touch_label=8'd38;
default:; endcase end
if(id==8'd16) begin case(ch)
0:touch_label=8'd41;
1:touch_label=8'd42;
default:; endcase end
if(id==8'd25) begin case(ch)
0:touch_label=8'd41;
1:touch_label=8'd42;
2:touch_label=8'd148;
3:touch_label=8'd81;
default:; endcase end
if(id==8'd17) begin case(ch)
0:touch_label=8'd39;
1:touch_label=8'd40;
2:touch_label=8'd25;
3:touch_label=8'd26;
default:; endcase end
if(id==8'd18) begin case(ch)
0:touch_label=8'd39;
1:touch_label=8'd40;
2:touch_label=8'd33;
3:touch_label=8'd34;
default:; endcase end
if(id==8'd19) begin case(ch)
0:touch_label=8'd39;
1:touch_label=8'd40;
2:touch_label=8'd127;
3:touch_label=8'd128;
default:; endcase end
if(id==8'd20) begin case(ch)
0:touch_label=8'd39;
1:touch_label=8'd40;
2:touch_label=8'd129;
3:touch_label=8'd130;
default:; endcase end
if(id==8'd23) begin case(ch)
0:touch_label=8'd54;
1:touch_label=8'd55;
2:touch_label=8'd56;
3:touch_label=8'd57;
default:; endcase end
if(id==8'd24) begin case(ch)
0:touch_label=8'd58;
1:touch_label=8'd59;
2:touch_label=8'd60;
3:touch_label=8'd61;
default:; endcase end
end endfunction
function [7:0] touch_string; input [5:0] id; input [4:0] ch; begin
touch_string=0; case({id,ch})
11'd32:touch_string=8'd110;
11'd33:touch_string=8'd86;
11'd34:touch_string=8'd29;
11'd35:touch_string=8'd111;
11'd36:touch_string=8'd72;
11'd37:touch_string=8'd70;
11'd38:touch_string=8'd112;
11'd39:touch_string=8'd113;
11'd416:touch_string=8'd54;
11'd417:touch_string=8'd55;
11'd418:touch_string=8'd56;
11'd419:touch_string=8'd57;
11'd448:touch_string=8'd25;
11'd480:touch_string=8'd26;
11'd512:touch_string=8'd76;
11'd544:touch_string=8'd77;
11'd545:touch_string=8'd78;
11'd576:touch_string=8'd79;
11'd577:touch_string=8'd80;
11'd608:touch_string=8'd83;
11'd609:touch_string=8'd84;
11'd640:touch_string=8'd85;
11'd641:touch_string=8'd86;
11'd672:touch_string=8'd80;
11'd673:touch_string=8'd88;
11'd704:touch_string=8'd87;
11'd705:touch_string=8'd88;
11'd736:touch_string=8'd89;
11'd737:touch_string=8'd19;
11'd768:touch_string=8'd81;
11'd800:touch_string=8'd82;
11'd832:touch_string=8'd90;
11'd833:touch_string=8'd91;
11'd864:touch_string=8'd92;
11'd865:touch_string=8'd85;
11'd928:touch_string=8'd150;
11'd929:touch_string=8'd63;
11'd930:touch_string=8'd151;
11'd931:touch_string=8'd62;
11'd960:touch_string=8'd86;
11'd961:touch_string=8'd29;
11'd1024:touch_string=8'd84;
11'd1056:touch_string=8'd12;
11'd1057:touch_string=8'd13;
11'd1088:touch_string=8'd14;
11'd1089:touch_string=8'd15;
11'd1090:touch_string=8'd222;
11'd1091:touch_string=8'd100;
11'd1092:touch_string=8'd223;
11'd1093:touch_string=8'd121;
11'd1120:touch_string=8'd1;
11'd1121:touch_string=8'd2;
11'd1122:touch_string=8'd222;
11'd1123:touch_string=8'd3;
11'd1124:touch_string=8'd4;
11'd1152:touch_string=8'd27;
11'd1153:touch_string=8'd28;
11'd1184:touch_string=8'd39;
11'd1185:touch_string=8'd40;
11'd1216:touch_string=8'd52;
11'd1217:touch_string=8'd53;
11'd1280:touch_string=8'd82;
11'd1281:touch_string=8'd131;
11'd1312:touch_string=8'd132;
11'd1313:touch_string=8'd131;
11'd1344:touch_string=8'd133;
11'd1345:touch_string=8'd127;
11'd1376:touch_string=8'd134;
11'd1377:touch_string=8'd16;
11'd1408:touch_string=8'd135;
11'd1409:touch_string=8'd82;
11'd1440:touch_string=8'd136;
11'd1441:touch_string=8'd86;
11'd1472:touch_string=8'd137;
11'd1473:touch_string=8'd138;
11'd1474:touch_string=8'd139;
11'd1475:touch_string=8'd140;
11'd1504:touch_string=8'd90;
11'd1505:touch_string=8'd91;
11'd1506:touch_string=8'd141;
11'd1507:touch_string=8'd98;
11'd1536:touch_string=8'd142;
11'd1537:touch_string=8'd143;
11'd1538:touch_string=8'd144;
11'd1568:touch_string=8'd92;
11'd1569:touch_string=8'd145;
11'd1600:touch_string=8'd146;
11'd1601:touch_string=8'd147;
11'd1632:touch_string=8'd148;
11'd1664:touch_string=8'd133;
11'd1665:touch_string=8'd154;
11'd1666:touch_string=8'd155;
11'd1667:touch_string=8'd156;
11'd1696:touch_string=8'd13;
11'd1697:touch_string=8'd157;
11'd1698:touch_string=8'd49;
11'd1699:touch_string=8'd158;
11'd1728:touch_string=8'd133;
11'd1729:touch_string=8'd51;
11'd1730:touch_string=8'd159;
11'd1731:touch_string=8'd160;
11'd1760:touch_string=8'd161;
11'd1761:touch_string=8'd162;
11'd1762:touch_string=8'd163;
11'd1763:touch_string=8'd156;
11'd1792:touch_string=8'd171;
11'd1793:touch_string=8'd145;
11'd1824:touch_string=8'd164;
11'd1825:touch_string=8'd107;
11'd1856:touch_string=8'd19;
11'd1857:touch_string=8'd165;
11'd1858:touch_string=8'd166;
11'd1888:touch_string=8'd167;
11'd1889:touch_string=8'd80;
11'd1920:touch_string=8'd79;
11'd1921:touch_string=8'd168;
11'd1952:touch_string=8'd169;
11'd1953:touch_string=8'd170;
11'd1984:touch_string=8'd90;
11'd1985:touch_string=8'd91;
11'd1986:touch_string=8'd48;
11'd1987:touch_string=8'd49;
default:; endcase end endfunction
function [4:0] touch_string_len; input [5:0] id; begin case(id)
1:touch_string_len=5'd8;
13:touch_string_len=5'd4;
14:touch_string_len=5'd1;
15:touch_string_len=5'd1;
16:touch_string_len=5'd1;
17:touch_string_len=5'd2;
18:touch_string_len=5'd2;
19:touch_string_len=5'd2;
20:touch_string_len=5'd2;
21:touch_string_len=5'd2;
22:touch_string_len=5'd2;
23:touch_string_len=5'd2;
24:touch_string_len=5'd1;
25:touch_string_len=5'd1;
26:touch_string_len=5'd2;
27:touch_string_len=5'd2;
29:touch_string_len=5'd4;
30:touch_string_len=5'd2;
32:touch_string_len=5'd1;
33:touch_string_len=5'd2;
34:touch_string_len=5'd6;
35:touch_string_len=5'd5;
36:touch_string_len=5'd2;
37:touch_string_len=5'd2;
38:touch_string_len=5'd2;
39:touch_string_len=5'd0;
40:touch_string_len=5'd2;
41:touch_string_len=5'd2;
42:touch_string_len=5'd2;
43:touch_string_len=5'd2;
44:touch_string_len=5'd2;
45:touch_string_len=5'd2;
46:touch_string_len=5'd4;
47:touch_string_len=5'd4;
48:touch_string_len=5'd3;
49:touch_string_len=5'd2;
50:touch_string_len=5'd2;
51:touch_string_len=5'd1;
52:touch_string_len=5'd4;
53:touch_string_len=5'd4;
54:touch_string_len=5'd4;
55:touch_string_len=5'd4;
56:touch_string_len=5'd2;
57:touch_string_len=5'd2;
58:touch_string_len=5'd3;
59:touch_string_len=5'd2;
60:touch_string_len=5'd2;
61:touch_string_len=5'd2;
62:touch_string_len=5'd4;
default:touch_string_len=0; endcase end endfunction
function [7:0] touch_digit; input [3:0] digit; begin case(digit)
0:touch_digit=8'd62;
1:touch_digit=8'd63;
2:touch_digit=8'd64;
3:touch_digit=8'd65;
4:touch_digit=8'd66;
5:touch_digit=8'd67;
6:touch_digit=8'd68;
7:touch_digit=8'd69;
8:touch_digit=8'd70;
9:touch_digit=8'd71;
default:touch_digit=0; endcase end endfunction

function [11:0] touch_bcd; input [7:0] value;
reg [11:0] bcd; integer bit_index; begin bcd=0;
for(bit_index=7;bit_index>=0;bit_index=bit_index-1) begin
if(bcd[3:0]>=4'd5) bcd[3:0]=bcd[3:0]+4'd3;
if(bcd[7:4]>=4'd5) bcd[7:4]=bcd[7:4]+4'd3;
if(bcd[11:8]>=4'd5) bcd[11:8]=bcd[11:8]+4'd3;
bcd={bcd[10:0],value[bit_index]}; end
touch_bcd=bcd; end endfunction
