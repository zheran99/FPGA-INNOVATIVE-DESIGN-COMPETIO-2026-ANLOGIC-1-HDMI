module shared_touch_painter(
    input wire clk,
    input wire [8:0] input_x,input_y,
    input wire [2:0] page,
    input wire enabled,
    input wire [255:0] values,
    input wire [7:0] pressed,
    input wire [2:0] cal_step,mode,
    output wire [11:0] font_addr,
    input wire [15:0] font_bits,
    output reg [23:0] rgb,
    output wire [12:0] text_addr,
    input wire [7:0] text_bits
);
    `include "touch_layout.vh"
    `include "ui_capsule_geometry.vh"

    reg [7:0] glyph;
    reg [3:0] gx,gy;
    reg [23:0] background,foreground;

    reg [8:0] x_s,y_s,x,y;
    reg [8:0] cy_s,cy;
    reg [2:0] page_s,page_q;
    reg [7:0] geometry_row;

    reg [5:0] relative_y_q;
    wire [8:0] relative_y_next=cy_s<9'd44 ? cy_s : cy_s<9'd88 ? cy_s-9'd44 :
        cy_s<9'd132 ? cy_s-9'd88 : cy_s<9'd176 ? cy_s-9'd132 :
        cy_s<9'd220 ? cy_s-9'd176 : cy_s-9'd220;
    always @(posedge clk)relative_y_q<=relative_y_next[5:0];
    wire [7:0] decoded_row=touch_row(page_s,cy_s,x_s);

    wire [8:0] slider_pos_input=input_x<=192 ? 9'd0 : (input_x>=448 ? 9'd256 : input_x-9'd192);
    wire [12:0] slider_pos_ext={4'd0,slider_pos_input};
    reg [12:0] slider_p25_s;
    wire [14:0] rounded100={slider_p25_s,2'd0}+15'd128;
    wire [14:0] rounded75={1'b0,slider_p25_s,1'b0}+{2'd0,slider_p25_s}+15'd128;
    wire [13:0] rounded50={slider_p25_s,1'b0}+14'd128;
    reg [6:0] slider100_q,slider75_q;
    reg [5:0] slider50_q;
    always @(posedge clk)begin
        slider_p25_s<=(slider_pos_ext<<4)+(slider_pos_ext<<3)+slider_pos_ext;
        slider100_q<=rounded100[14:8];slider75_q<=rounded75[14:8];
        slider50_q<=rounded50[13:8];
    end
    always @(posedge clk) begin
        x_s<=input_x;y_s<=input_y;cy_s<=input_y-9'd32;page_s<=page;
        x<=x_s;y<=y_s;cy<=cy_s;geometry_row<=decoded_row;page_q<=page_s;
    end

    reg [31:0] value_select_q;
    integer select_index;

    always @(posedge clk)begin
        for(select_index=0;select_index<32;select_index=select_index+1)
            value_select_q[select_index]<=decoded_row==select_index;
    end
    reg [7:0] selected_value;
    integer value_index;
    always @* begin
        selected_value=8'd0;
        for(value_index=0;value_index<32;value_index=value_index+1)
            selected_value=selected_value |
                (values[value_index*8+:8] & {8{value_select_q[value_index]}});
    end

    function [7:0] shape_character;input [1:0] shape;input [1:0] column;
    begin case({shape,column})
    4'd0:shape_character=8'd133;
    4'd1:shape_character=8'd154;
    4'd2:shape_character=8'd155;
    4'd3:shape_character=8'd156;
    4'd4:shape_character=8'd13;
    4'd5:shape_character=8'd157;
    4'd6:shape_character=8'd49;
    4'd7:shape_character=8'd158;
    4'd8:shape_character=8'd133;
    4'd9:shape_character=8'd51;
    4'd10:shape_character=8'd159;
    4'd11:shape_character=8'd160;
    4'd12:shape_character=8'd161;
    4'd13:shape_character=8'd162;
    4'd14:shape_character=8'd163;
    4'd15:shape_character=8'd156;
    default:shape_character=0;endcase end endfunction

    function [8:0] style_text_origin;
        input [5:0] value;
        begin case(value)
            6'd12:style_text_origin=9'd328;
            6'd46:style_text_origin=9'd336;
            6'd44,6'd45,6'd47,6'd48,6'd49,6'd50:style_text_origin=9'd352;
            6'd0,6'd1,6'd2,6'd24,6'd40,6'd57,6'd58,6'd63:style_text_origin=9'd360;
            6'd5,6'd59:style_text_origin=9'd368;
            6'd3,6'd4,6'd6,6'd7,6'd8,6'd28,6'd29,6'd30,6'd31,6'd32,6'd33,6'd34,6'd37,6'd38,6'd41,6'd51,6'd52,6'd53,6'd54,6'd55,6'd56,6'd60,6'd61:style_text_origin=9'd376;
            6'd25,6'd26,6'd27,6'd35,6'd36,6'd43,6'd62:style_text_origin=9'd384;
            6'd9,6'd10,6'd11,6'd13,6'd14,6'd15,6'd16,6'd17,6'd18,6'd19,6'd20,6'd21,6'd22,6'd23,6'd39,6'd42:style_text_origin=9'd392;
            default:style_text_origin=9'd392;
        endcase end
    endfunction
    function [8:0] value_text_origin;
        input [7:0] row,value;
        begin
            value_text_origin=9'd376;
            case(row)
                6,7,9,10,14,15,16,17,21,25:value_text_origin=9'd384;
                8:case(value)
                    1,2:value_text_origin=9'd360;
                    3:value_text_origin=9'd368;
                    default:value_text_origin=9'd376;
                endcase
                13,26:value_text_origin=value==0 ? 9'd384 : 9'd376;
                18:value_text_origin=value==0 ? 9'd384 : value<3 ? 9'd376 : style_text_origin(value[5:0]);
                23:value_text_origin=9'd360;
                24:value_text_origin=9'd328;
                default:;
            endcase
        end
    endfunction
    reg label_en;
    reg [7:0] label_id;
    reg [3:0] label_column;
    reg string_en;
    reg [5:0] string_id;
    reg [4:0] string_ch;
    reg [7:0] row,value;
    reg [11:0] decimal_value;
    reg [7:0] track_value;
    reg chosen;
    reg toggle_row;
    always @*case(geometry_row)
        6,7,9,10,15,17,21:toggle_row=1;
        default:toggle_row=0;
    endcase
    wire [11:0] toggle_x={3'd0,x}-12'd360;
    wire [11:0] toggle_y={6'd0,relative_y_q}-12'd9;
    wire toggle_body=ui_capsule_body(toggle_x,toggle_y);
    wire toggle_knob=ui_capsule_knob(toggle_x,toggle_y,selected_value!=0);
    reg [5:0] sid;
    reg [8:0] text_left,hx0,hx1,hty,hty1,h_lx,h_ly;
    reg [9:0] h_adx,h_ady;
    reg [11:0] h_cap_x,h_cap_y;
    integer col,r,button,relative_y,char_no,preview_col,tx,ty;
    always @* begin
        glyph=0;gx=0;gy=0;background=24'h122632;foreground=enabled?24'heef7f6:24'h80909c;
        label_en=0;label_id=0;label_column=0;
        row=255;string_en=0;string_id=0;string_ch=0;value=0;sid=0;decimal_value=0;
        track_value=0;chosen=0;text_left=0;
        hx0=0;hx1=0;hty=0;hty1=0;h_lx=0;h_ly=0;h_cap_x=0;h_cap_y=0;
        h_adx=0;h_ady=0;
        col=0;r=0;button=0;relative_y=0;char_no=0;preview_col=0;tx=0;ty=0;
        if(y<32 && cal_step==0) begin
            background=24'h122632;
            if(x>=16 && x<304 && y>=8 && y<24) begin

                string_en=1;string_id=6'd33+{3'd0,page_q};
                string_ch=(x-16)>>4;gx=x[3:0];gy=y-8;
            end
        end else if(cal_step!=0) begin
            tx=cal_step==1 || cal_step==4?32:(cal_step==5?240:447);
            ty=cal_step==1 || cal_step==2?32:(cal_step==5?160:287);
            if((x>=tx-12 && x<=tx+12 && y>=ty-1 && y<=ty+1) ||
               (x>=tx-1 && x<=tx+1 && y>=ty-12 && y<=ty+12)) background=24'h28e0c0;
            if(x>=160 && x<320 && y>=112 && y<128) begin
                string_en=1;string_id=13;string_ch=(x-160)>>4;gx=x[3:0];gy=y[3:0];
            end
            if(x>=232 && x<248 && y>=192 && y<208) begin glyph=touch_digit({1'b0,cal_step});gx=x-232;gy=y-192;end
        end else if(y>=296) begin
            background=24'h122632;
            if(!enabled && x>=16 && x<288 && y>=300 && y<316) begin
                string_en=1;string_id=6'd1;string_ch=(x-16)>>4;gx=x[3:0];gy=y-300;
            end
            if(enabled) begin

                for(button=0;button<TOUCH_PAGES;button=button+1)
                    if(x>=192+button*16 && x<200+button*16 && y>=304 && y<312)
                        background=page_q==button?24'h67dfcc:24'h405868;
                if(y>=302 && y<=314 &&
                   ((x>=24 && x<=30 && (y>=308?y-308:308-y)==x-24) ||
                    (x>=450 && x<=456 && (y>=308?y-308:308-y)==456-x)))
                    background=((x<64 && page_q!=0) || (x>=416 && page_q!=TOUCH_PAGES-1))?24'h67dfcc:24'h405868;
            end
        end else if(page_q==3'd0) begin

            row=geometry_row;
            background=24'h122632;
            chosen=pressed!=255 && pressed[7:1]==row;
            if(row==8'd4 || row==8'd5 || row==8'd6 || row==8'd7) begin

                hx0 =(row==8'd4)?TOUCH_H_L_X0 :(row==8'd5)?TOUCH_H_R_X0 :TOUCH_H_M1_X0;
                hx1 =(row==8'd4)?TOUCH_H_L_X1 :(row==8'd5)?TOUCH_H_R_X1 :TOUCH_H_M1_X1;
                hty =(row==8'd4)?TOUCH_H_L_Y0 :(row==8'd5)?TOUCH_H_R_Y0
                    :(row==8'd6)?TOUCH_H_M1_Y0 :TOUCH_H_M2_Y0;
                hty1=(row==8'd4)?TOUCH_H_L_Y1 :(row==8'd5)?TOUCH_H_R_Y1
                    :(row==8'd6)?TOUCH_H_M1_Y1 :TOUCH_H_M2_Y1;
                if(x>=hx0 && x<hx1 && cy>=hty && cy<hty1) begin
                    background=chosen?24'h203d48:24'h152c38;
                    if(x==hx0 || x==hx1-9'd1 || cy==hty || cy==hty1-9'd1)
                        background=enabled?24'h67dfcc:24'h405868;
                end

                h_lx=(row==8'd4)?TOUCH_H_LB_XL :(row==8'd5)?TOUCH_H_LB_XR :TOUCH_H_LB_XM;
                h_ly=(row==8'd4 || row==8'd5)?TOUCH_H_LB_YS
                    :(row==8'd6)?TOUCH_H_LB_YM1 :TOUCH_H_LB_YM2;
                if(cy>=h_ly && cy<h_ly+9'd16 && x>=h_lx && x<h_lx+9'd64) begin
                    label_en=1;label_id=row;label_column=(x-h_lx)>>4;
                    glyph=0;gx=x-h_lx;gy=cy-h_ly;
                    foreground=chosen?24'heef7f6:(enabled?24'hb4c9ce:24'h80909c);
                end
            end

            if(row==8'd4 || row==8'd5) begin
                h_adx=(row==8'd4)?(10'd66 - {1'b0,x}):({1'b0,x} - 10'd414);
                h_ady=(cy>9'd176)?({1'b0,cy} - 10'd176):(10'd176 - {1'b0,cy});
                if(h_adx<10'd13 && h_adx+h_ady<=10'd13)
                    background=enabled?24'h67dfcc:24'h80909c;
            end

            if(row==8'd6 || row==8'd7) begin
                h_cap_x={3'd0,x}-{3'd0,TOUCH_H_CAP_X};
                h_cap_y=(row==8'd6)?({3'd0,cy}-{3'd0,TOUCH_H_CAP_Y})
                                  :({3'd0,cy}-{3'd0,TOUCH_H_CAP2_Y});
                if(ui_capsule_body(h_cap_x,h_cap_y)) begin
                    background=selected_value!=0?(enabled?24'h67dfcc:24'h80909c):24'h405868;
                    if(ui_capsule_knob(h_cap_x,h_cap_y,selected_value!=0))
                        background=selected_value!=0?(enabled?24'heef7f6:24'h80909c):24'hb4c9ce;
                end
            end
        end else begin
            row=geometry_row;
            if(row==255) background=24'h122632;
            else begin
                value=selected_value;relative_y={26'd0,relative_y_q};
                chosen=pressed!=255 && pressed[7:1]==row;
                if(x>=8 && x<472 && relative_y>=4 && relative_y<40) begin
                    background=24'h152c38;
                    if(chosen)begin
                        background=x<11 ? 24'h67dfcc : 24'h203d48;
                    end
                end
                foreground=row==24 ? 24'h80909c : (enabled?24'h67dfcc:24'h80909c);
                if(relative_y>=14 && relative_y<30) begin
                    gy=relative_y-14;gx=x[3:0];
                    if(touch_step(row)!=0) begin
                        if(x>=368 && x<416) begin
                            char_no=(x-368)>>4;
                            decimal_value=touch_bcd(value);
                            glyph=touch_digit(char_no==0?decimal_value[11:8]:(char_no==1?decimal_value[7:4]:decimal_value[3:0]));
                        end
                    end else if(x>=320 && x<464) begin
                        sid=30;
                        case(row)
                        8:sid=6'd45+(value>5 ? 3'd0 : value[2:0]);
                        6,7,9,10,15,17,21: sid=value==0?15:14;
                        11:sid=value==0?19:20;
                        12:sid=value==0?21:(value==1?22:23);
                        13:sid=value==0?16:(value==1?17:18);
                        18:sid=value<3 ? 6'd16+value[1:0] : 6'd56+value-3;
                        26:sid=value==0 ? 6'd15 : value==1 ? 6'd60 : 6'd61;
                        14:sid=value==0?24:25;
                        16:sid=value==0?15:(value==1?14:32);
                        25:sid=value==0?24:(value==1?25:51);
                        19:sid=value==0?40:(value==1?41:42);20:sid=value==0?43:44;22:sid=value==0?27:26;23:sid=13;24:sid=29;
                        default:sid=30;
                        endcase

                        text_left=value_text_origin(row,value);
                        if(x>=text_left)begin
                            string_en=1;string_id=sid;string_ch=(x-text_left)>>4;gx=x-text_left;
                        end
                        if(row==31)begin
                            string_en=0;glyph=0;
                            if(x>=360 && x<424)begin
                                string_en=1;string_id=value>=4 ? 6'd62 : 6'd52+{4'd0,value[1:0]};string_ch=(x-9'd360)>>4;gx=x-9'd360;
                            end
                        end
                        if(row==24 && x>=400 && x<448) begin
                            string_en=0;gx=x[3:0];
                            glyph=touch_digit(x<416?value[3:0]:(x<432?{1'b0,value[6:4]}:{3'd0,value[7]}));
                        end
                    end
                end
                if(touch_step(row)!=0) begin
                    case(row)
                        0,27:track_value={1'b0,slider100_q};
                        1,28:track_value=8'd50+{slider75_q,1'b0};
                        2,29:track_value={slider100_q,1'b0};
                        3,30:track_value={1'b0,slider50_q,1'b0};
                        default:track_value=0;
                    endcase
                    if(x>=TOUCH_SLIDER_LEFT && x<=TOUCH_SLIDER_RIGHT) begin
                        if(relative_y>=34 && relative_y<38)
                            background=track_value<value?(enabled?24'h67dfcc:24'h80909c):24'h405868;
                        if(track_value>=value && {1'b0,track_value}<{1'b0,value}+{1'b0,touch_step(row)} && relative_y>=30 && relative_y<40)
                            background=enabled?24'h7ce0b0:24'h80909c;
                    end
                end else begin

                    if(toggle_row)begin
                        string_en=0;glyph=0;
                        if(toggle_body)background=selected_value!=0 ?
                            (enabled?24'h67dfcc:24'h80909c) : 24'h405868;
                        if(toggle_body && toggle_knob)background=selected_value!=0 ?
                            (enabled?24'heef7f6:24'h80909c) : 24'hb4c9ce;
                    end
                end
            end
            if(x>=20 && x<180 && row!=255 && row!=4 && row!=5 && relative_y>=14 && relative_y<30) begin
                string_en=0;label_en=1;label_id=row;label_column=(x-20)>>4;glyph=0;gx=x-20;gy=relative_y-14;
                foreground=enabled ? (chosen?24'heef7f6:24'hb4c9ce) : 24'h80909c;
            end

            if(row==4 || row==5) begin
                background=24'h122632;string_en=0;glyph=0;
                if(relative_y>=4 && relative_y<40) begin
                    background=24'h152c38;
                    if(chosen && (x<10 || (x>=234 && x<236) || (x>=244 && x<246) || x>=470 || relative_y<6 || relative_y>=38))
                        background=24'h67dfcc;
                    if(relative_y>=14 && relative_y<30 &&
                       ((row==4 && x>=88 && x<136) || (row==5 && x>=344 && x<392))) begin
                        label_en=1;label_id=row;label_column=row==4?(x-88)>>4:(x-344)>>4;glyph=0;
                        gx=row==4?x-88:x-344;gy=relative_y-14;
                    end
                    if(relative_y>=16 && relative_y<=28 &&
                       ((row==4 && x>=40 && x<=46 && (relative_y>=22?relative_y-22:22-relative_y)==x-40) ||
                        (row==5 && x>=432 && x<=438 && (relative_y>=22?relative_y-22:22-relative_y)==438-x)))
                        background=24'h67dfcc;
                end
            end
        end
        if(x<3)begin background=24'h67dfcc;glyph=0;string_en=0;label_en=0;end
    end

    reg [7:0] glyph_q,glyph_lookup;
    reg string_en_q;
    reg [5:0] string_id_q;
    reg [4:0] string_ch_q;

    wire query_valid=label_en || (string_en && string_ch<16);
    wire [8:0] query_token=label_en ? 9'd384+{1'b0,label_id} : 9'd416+{3'd0,string_id};

    assign text_addr={query_token,label_en ? label_column : string_ch[3:0]};
    reg query_valid_q;
    reg [3:0] gx_lookup,gy_lookup;
    reg [23:0] bg_lookup,fg_lookup;
    reg [3:0] gx_q,gy_q,gx_qq;
    reg [23:0] bg_q,fg_q,bg_qq,fg_qq;
    assign font_addr={glyph_lookup,gy_lookup};
    always @(posedge clk) begin
        glyph_q<=glyph;gx_q<=gx;gy_q<=gy;
        bg_q<=background;fg_q<=foreground;
        string_en_q<=string_en;string_id_q<=string_id;string_ch_q<=string_ch;
        query_valid_q<=query_valid;
        glyph_lookup<=query_valid_q?text_bits:glyph_q;
        gx_lookup<=gx_q;gy_lookup<=gy_q;
        bg_lookup<=bg_q;fg_lookup<=fg_q;
        gx_qq<=gx_lookup;bg_qq<=bg_lookup;fg_qq<=fg_lookup;
        rgb<=font_bits[15-gx_qq]?fg_qq:bg_qq;
    end
endmodule
