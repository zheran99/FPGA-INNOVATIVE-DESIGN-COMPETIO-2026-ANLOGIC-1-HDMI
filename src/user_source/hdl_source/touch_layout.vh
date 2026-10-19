localparam TOUCH_HEIGHT=1296;
localparam TOUCH_GLYPHS=127;
function [7:0] touch_row; input [10:0] cy; begin touch_row=255;
if(cy>=32 && cy<80) touch_row=8'd0;
if(cy>=80 && cy<128) touch_row=8'd1;
if(cy>=128 && cy<176) touch_row=8'd2;
if(cy>=176 && cy<224) touch_row=8'd3;
if(cy>=256 && cy<304) touch_row=8'd4;
if(cy>=304 && cy<352) touch_row=8'd5;
if(cy>=352 && cy<400) touch_row=8'd6;
if(cy>=400 && cy<448) touch_row=8'd7;
if(cy>=448 && cy<496) touch_row=8'd8;
if(cy>=496 && cy<544) touch_row=8'd9;
if(cy>=576 && cy<624) touch_row=8'd10;
if(cy>=624 && cy<672) touch_row=8'd11;
if(cy>=672 && cy<720) touch_row=8'd12;
if(cy>=720 && cy<768) touch_row=8'd13;
if(cy>=768 && cy<816) touch_row=8'd14;
if(cy>=816 && cy<864) touch_row=8'd15;
if(cy>=896 && cy<944) touch_row=8'd16;
if(cy>=944 && cy<992) touch_row=8'd17;
if(cy>=992 && cy<1040) touch_row=8'd18;
if(cy>=1072 && cy<1120) touch_row=8'd21;
if(cy>=1120 && cy<1168) touch_row=8'd22;
if(cy>=1200 && cy<1248) touch_row=8'd23;
if(cy>=1248 && cy<1296) touch_row=8'd24;
end endfunction
localparam TOUCH_SLIDER_LEFT=192, TOUCH_SLIDER_RIGHT=448;
function [7:0] touch_slider_value; input [7:0] id; input [8:0] x;
reg [8:0] pos; reg [15:0] p25,ticks; begin
pos=x<=192?0:(x>=448?256:x-192);
p25=({7'd0,pos}<<4)+({7'd0,pos}<<3)+pos;
case(id)
0:begin ticks=((p25<<2)+128)>>8; touch_slider_value=ticks[7:0]; end
1:begin ticks=((p25<<1)+p25+128)>>8; touch_slider_value=50+(ticks[7:0]<<1); end
2:begin ticks=((p25<<2)+128)>>8; touch_slider_value=ticks[7:0]<<1; end
3:begin ticks=((p25<<1)+128)>>8; touch_slider_value=ticks[7:0]<<1; end
default:begin ticks=0; touch_slider_value=0; end
endcase end endfunction
function [10:0] touch_top; input [7:0] id; begin
touch_top=0; case(id)
0:touch_top=11'd32;
1:touch_top=11'd80;
2:touch_top=11'd128;
3:touch_top=11'd176;
4:touch_top=11'd256;
5:touch_top=11'd304;
6:touch_top=11'd352;
7:touch_top=11'd400;
8:touch_top=11'd448;
9:touch_top=11'd496;
10:touch_top=11'd576;
11:touch_top=11'd624;
12:touch_top=11'd672;
13:touch_top=11'd720;
14:touch_top=11'd768;
15:touch_top=11'd816;
16:touch_top=11'd896;
17:touch_top=11'd944;
18:touch_top=11'd992;
21:touch_top=11'd1072;
22:touch_top=11'd1120;
23:touch_top=11'd1200;
24:touch_top=11'd1248;
default:; endcase end endfunction
function [2:0] touch_target; input [7:0] id; begin
touch_target=7; case(id)
0:touch_target=3'd0;
1:touch_target=3'd0;
2:touch_target=3'd0;
3:touch_target=3'd0;
4:touch_target=3'd4;
5:touch_target=3'd4;
6:touch_target=3'd4;
7:touch_target=3'd4;
8:touch_target=3'd0;
9:touch_target=3'd0;
10:touch_target=3'd1;
11:touch_target=3'd1;
12:touch_target=3'd1;
13:touch_target=3'd1;
14:touch_target=3'd1;
15:touch_target=3'd1;
16:touch_target=3'd2;
17:touch_target=3'd2;
18:touch_target=3'd2;
21:touch_target=3'd3;
22:touch_target=3'd3;
23:touch_target=3'd5;
24:touch_target=3'd5;
default:; endcase end endfunction
function [3:0] touch_field; input [7:0] id; begin
touch_field=0; case(id)
0:touch_field=4'd0;
1:touch_field=4'd1;
2:touch_field=4'd2;
3:touch_field=4'd3;
4:touch_field=4'd0;
5:touch_field=4'd1;
6:touch_field=4'd2;
7:touch_field=4'd3;
8:touch_field=4'd4;
9:touch_field=4'd5;
10:touch_field=4'd4;
11:touch_field=4'd5;
12:touch_field=4'd6;
13:touch_field=4'd1;
14:touch_field=4'd3;
15:touch_field=4'd2;
16:touch_field=4'd0;
17:touch_field=4'd1;
18:touch_field=4'd2;
21:touch_field=4'd0;
22:touch_field=4'd1;
23:touch_field=4'd2;
24:touch_field=4'd3;
default:; endcase end endfunction
function [7:0] touch_min; input [7:0] id; begin
touch_min=0; case(id)
0:touch_min=8'd0;
1:touch_min=8'd50;
2:touch_min=8'd0;
3:touch_min=8'd0;
4:touch_min=8'd0;
5:touch_min=8'd0;
6:touch_min=8'd0;
7:touch_min=8'd0;
8:touch_min=8'd0;
9:touch_min=8'd0;
10:touch_min=8'd0;
11:touch_min=8'd0;
12:touch_min=8'd0;
13:touch_min=8'd0;
14:touch_min=8'd0;
15:touch_min=8'd0;
16:touch_min=8'd0;
17:touch_min=8'd0;
18:touch_min=8'd0;
21:touch_min=8'd0;
22:touch_min=8'd0;
23:touch_min=8'd0;
24:touch_min=8'd0;
default:; endcase end endfunction
function [7:0] touch_max; input [7:0] id; begin
touch_max=0; case(id)
0:touch_max=8'd100;
1:touch_max=8'd200;
2:touch_max=8'd200;
3:touch_max=8'd100;
4:touch_max=8'd0;
5:touch_max=8'd0;
6:touch_max=8'd1;
7:touch_max=8'd1;
8:touch_max=8'd5;
9:touch_max=8'd1;
10:touch_max=8'd1;
11:touch_max=8'd1;
12:touch_max=8'd2;
13:touch_max=8'd2;
14:touch_max=8'd1;
15:touch_max=8'd1;
16:touch_max=8'd2;
17:touch_max=8'd1;
18:touch_max=8'd2;
21:touch_max=8'd1;
22:touch_max=8'd1;
23:touch_max=8'd0;
24:touch_max=8'd0;
default:; endcase end endfunction
function [7:0] touch_step; input [7:0] id; begin
touch_step=0; case(id)
0:touch_step=8'd1;
1:touch_step=8'd2;
2:touch_step=8'd2;
3:touch_step=8'd2;
4:touch_step=8'd0;
5:touch_step=8'd0;
6:touch_step=8'd0;
7:touch_step=8'd0;
8:touch_step=8'd0;
9:touch_step=8'd0;
10:touch_step=8'd0;
11:touch_step=8'd0;
12:touch_step=8'd0;
13:touch_step=8'd0;
14:touch_step=8'd0;
15:touch_step=8'd0;
16:touch_step=8'd0;
17:touch_step=8'd0;
18:touch_step=8'd0;
21:touch_step=8'd0;
22:touch_step=8'd0;
23:touch_step=8'd0;
24:touch_step=8'd0;
default:; endcase end endfunction
function [6:0] touch_label; input [10:0] cy; input [4:0] ch;
begin touch_label=0;
if(cy>=8 && cy<24) begin case(ch)
0:touch_label=7'd1;
1:touch_label=7'd2;
2:touch_label=7'd3;
3:touch_label=7'd4;
default:; endcase end
if(cy>=48 && cy<64) begin case(ch)
0:touch_label=7'd5;
1:touch_label=7'd6;
default:; endcase end
if(cy>=96 && cy<112) begin case(ch)
0:touch_label=7'd7;
1:touch_label=7'd8;
2:touch_label=7'd6;
default:; endcase end
if(cy>=144 && cy<160) begin case(ch)
0:touch_label=7'd9;
1:touch_label=7'd10;
2:touch_label=7'd6;
default:; endcase end
if(cy>=192 && cy<208) begin case(ch)
0:touch_label=7'd4;
1:touch_label=7'd11;
default:; endcase end
if(cy>=232 && cy<248) begin case(ch)
0:touch_label=7'd12;
1:touch_label=7'd13;
2:touch_label=7'd14;
3:touch_label=7'd15;
default:; endcase end
if(cy>=272 && cy<288) begin case(ch)
0:touch_label=7'd16;
1:touch_label=7'd17;
2:touch_label=7'd18;
default:; endcase end
if(cy>=320 && cy<336) begin case(ch)
0:touch_label=7'd19;
1:touch_label=7'd17;
2:touch_label=7'd18;
default:; endcase end
if(cy>=368 && cy<384) begin case(ch)
0:touch_label=7'd20;
1:touch_label=7'd12;
default:; endcase end
if(cy>=416 && cy<432) begin case(ch)
0:touch_label=7'd4;
1:touch_label=7'd48;
2:touch_label=7'd21;
3:touch_label=7'd22;
default:; endcase end
if(cy>=464 && cy<480) begin case(ch)
0:touch_label=7'd14;
1:touch_label=7'd15;
2:touch_label=7'd23;
3:touch_label=7'd24;
default:; endcase end
if(cy>=512 && cy<528) begin case(ch)
0:touch_label=7'd14;
1:touch_label=7'd15;
2:touch_label=7'd25;
3:touch_label=7'd26;
default:; endcase end
if(cy>=552 && cy<568) begin case(ch)
0:touch_label=7'd27;
1:touch_label=7'd28;
default:; endcase end
if(cy>=592 && cy<608) begin case(ch)
0:touch_label=7'd27;
1:touch_label=7'd28;
2:touch_label=7'd25;
3:touch_label=7'd26;
default:; endcase end
if(cy>=640 && cy<656) begin case(ch)
0:touch_label=7'd29;
1:touch_label=7'd30;
default:; endcase end
if(cy>=688 && cy<704) begin case(ch)
0:touch_label=7'd31;
1:touch_label=7'd32;
default:; endcase end
if(cy>=736 && cy<752) begin case(ch)
0:touch_label=7'd27;
1:touch_label=7'd28;
2:touch_label=7'd33;
3:touch_label=7'd34;
default:; endcase end
if(cy>=784 && cy<800) begin case(ch)
0:touch_label=7'd27;
1:touch_label=7'd35;
default:; endcase end
if(cy>=832 && cy<848) begin case(ch)
0:touch_label=7'd36;
1:touch_label=7'd37;
2:touch_label=7'd38;
default:; endcase end
if(cy>=872 && cy<888) begin case(ch)
0:touch_label=7'd39;
1:touch_label=7'd40;
default:; endcase end
if(cy>=912 && cy<928) begin case(ch)
0:touch_label=7'd41;
1:touch_label=7'd42;
default:; endcase end
if(cy>=960 && cy<976) begin case(ch)
0:touch_label=7'd39;
1:touch_label=7'd40;
2:touch_label=7'd25;
3:touch_label=7'd26;
default:; endcase end
if(cy>=1008 && cy<1024) begin case(ch)
0:touch_label=7'd39;
1:touch_label=7'd40;
2:touch_label=7'd33;
3:touch_label=7'd34;
default:; endcase end
if(cy>=1048 && cy<1064) begin case(ch)
0:touch_label=7'd48;
1:touch_label=7'd49;
default:; endcase end
if(cy>=1088 && cy<1104) begin case(ch)
0:touch_label=7'd48;
1:touch_label=7'd49;
2:touch_label=7'd25;
3:touch_label=7'd26;
default:; endcase end
if(cy>=1136 && cy<1152) begin case(ch)
0:touch_label=7'd50;
1:touch_label=7'd51;
default:; endcase end
if(cy>=1176 && cy<1192) begin case(ch)
0:touch_label=7'd52;
1:touch_label=7'd53;
default:; endcase end
if(cy>=1216 && cy<1232) begin case(ch)
0:touch_label=7'd54;
1:touch_label=7'd55;
2:touch_label=7'd56;
3:touch_label=7'd57;
default:; endcase end
if(cy>=1264 && cy<1280) begin case(ch)
0:touch_label=7'd58;
1:touch_label=7'd59;
2:touch_label=7'd60;
3:touch_label=7'd61;
default:; endcase end
end endfunction
function [3:0] touch_label_y; input [10:0] cy; begin touch_label_y=0;
if(cy>=8 && cy<24) touch_label_y=cy-8;
if(cy>=48 && cy<64) touch_label_y=cy-48;
if(cy>=96 && cy<112) touch_label_y=cy-96;
if(cy>=144 && cy<160) touch_label_y=cy-144;
if(cy>=192 && cy<208) touch_label_y=cy-192;
if(cy>=232 && cy<248) touch_label_y=cy-232;
if(cy>=272 && cy<288) touch_label_y=cy-272;
if(cy>=320 && cy<336) touch_label_y=cy-320;
if(cy>=368 && cy<384) touch_label_y=cy-368;
if(cy>=416 && cy<432) touch_label_y=cy-416;
if(cy>=464 && cy<480) touch_label_y=cy-464;
if(cy>=512 && cy<528) touch_label_y=cy-512;
if(cy>=552 && cy<568) touch_label_y=cy-552;
if(cy>=592 && cy<608) touch_label_y=cy-592;
if(cy>=640 && cy<656) touch_label_y=cy-640;
if(cy>=688 && cy<704) touch_label_y=cy-688;
if(cy>=736 && cy<752) touch_label_y=cy-736;
if(cy>=784 && cy<800) touch_label_y=cy-784;
if(cy>=832 && cy<848) touch_label_y=cy-832;
if(cy>=872 && cy<888) touch_label_y=cy-872;
if(cy>=912 && cy<928) touch_label_y=cy-912;
if(cy>=960 && cy<976) touch_label_y=cy-960;
if(cy>=1008 && cy<1024) touch_label_y=cy-1008;
if(cy>=1048 && cy<1064) touch_label_y=cy-1048;
if(cy>=1088 && cy<1104) touch_label_y=cy-1088;
if(cy>=1136 && cy<1152) touch_label_y=cy-1136;
if(cy>=1176 && cy<1192) touch_label_y=cy-1176;
if(cy>=1216 && cy<1232) touch_label_y=cy-1216;
if(cy>=1264 && cy<1280) touch_label_y=cy-1264;
end endfunction
function [6:0] touch_string; input [5:0] id; input [4:0] ch; begin
touch_string=0; case({id,ch})
11'd0:touch_string=7'd72;
11'd1:touch_string=7'd70;
11'd2:touch_string=7'd0;
11'd3:touch_string=7'd1;
11'd4:touch_string=7'd2;
11'd5:touch_string=7'd108;
11'd6:touch_string=7'd109;
11'd32:touch_string=7'd110;
11'd33:touch_string=7'd86;
11'd34:touch_string=7'd29;
11'd35:touch_string=7'd111;
11'd36:touch_string=7'd72;
11'd37:touch_string=7'd70;
11'd38:touch_string=7'd112;
11'd39:touch_string=7'd113;
11'd64:touch_string=7'd114;
11'd65:touch_string=7'd84;
11'd66:touch_string=7'd103;
11'd67:touch_string=7'd123;
11'd68:touch_string=7'd124;
11'd69:touch_string=7'd125;
11'd70:touch_string=7'd126;
11'd96:touch_string=7'd93;
11'd97:touch_string=7'd94;
11'd128:touch_string=7'd95;
11'd129:touch_string=7'd96;
11'd160:touch_string=7'd97;
11'd161:touch_string=7'd98;
11'd192:touch_string=7'd99;
11'd193:touch_string=7'd100;
11'd224:touch_string=7'd29;
11'd225:touch_string=7'd101;
11'd256:touch_string=7'd102;
11'd257:touch_string=7'd104;
11'd288:touch_string=7'd103;
11'd289:touch_string=7'd104;
11'd320:touch_string=7'd102;
11'd352:touch_string=7'd103;
11'd384:touch_string=7'd43;
11'd385:touch_string=7'd44;
11'd386:touch_string=7'd106;
11'd387:touch_string=7'd107;
11'd416:touch_string=7'd54;
11'd417:touch_string=7'd55;
11'd418:touch_string=7'd56;
11'd419:touch_string=7'd57;
11'd448:touch_string=7'd25;
11'd480:touch_string=7'd26;
11'd512:touch_string=7'd76;
11'd544:touch_string=7'd77;
11'd545:touch_string=7'd78;
11'd576:touch_string=7'd79;
11'd577:touch_string=7'd80;
11'd608:touch_string=7'd83;
11'd609:touch_string=7'd84;
11'd640:touch_string=7'd85;
11'd641:touch_string=7'd86;
11'd672:touch_string=7'd80;
11'd673:touch_string=7'd88;
11'd704:touch_string=7'd87;
11'd705:touch_string=7'd88;
11'd736:touch_string=7'd89;
11'd737:touch_string=7'd19;
11'd768:touch_string=7'd81;
11'd800:touch_string=7'd82;
11'd832:touch_string=7'd90;
11'd833:touch_string=7'd91;
11'd864:touch_string=7'd92;
11'd865:touch_string=7'd85;
11'd896:touch_string=7'd115;
11'd897:touch_string=7'd116;
11'd928:touch_string=7'd58;
11'd929:touch_string=7'd59;
11'd930:touch_string=7'd75;
11'd931:touch_string=7'd65;
11'd960:touch_string=7'd86;
11'd961:touch_string=7'd29;
11'd992:touch_string=7'd41;
11'd993:touch_string=7'd42;
11'd1024:touch_string=7'd84;
default:; endcase end endfunction
function [4:0] touch_string_len; input [5:0] id; begin case(id)
0:touch_string_len=5'd7;
1:touch_string_len=5'd8;
2:touch_string_len=5'd7;
3:touch_string_len=5'd2;
4:touch_string_len=5'd2;
5:touch_string_len=5'd2;
6:touch_string_len=5'd2;
7:touch_string_len=5'd2;
8:touch_string_len=5'd2;
9:touch_string_len=5'd2;
10:touch_string_len=5'd1;
11:touch_string_len=5'd1;
12:touch_string_len=5'd4;
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
28:touch_string_len=5'd2;
29:touch_string_len=5'd4;
30:touch_string_len=5'd2;
31:touch_string_len=5'd2;
32:touch_string_len=5'd1;
default:touch_string_len=0; endcase end endfunction
function [6:0] touch_digit; input [3:0] digit; begin case(digit)
0:touch_digit=7'd62;
1:touch_digit=7'd63;
2:touch_digit=7'd64;
3:touch_digit=7'd65;
4:touch_digit=7'd66;
5:touch_digit=7'd67;
6:touch_digit=7'd68;
7:touch_digit=7'd69;
8:touch_digit=7'd70;
9:touch_digit=7'd71;
default:touch_digit=0; endcase end endfunction
