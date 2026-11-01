module scaled_shared_menu(
    input wire clk,rst,de,hs,vs,
    input wire touch_clk,
    input wire [12:0] touch_text_addr,
    output wire [7:0] touch_text_bits,
    input wire [11:0] touch_font_addr,
    output wire [15:0] touch_font_bits,
    output wire legacy_suppress,
    input wire [23:0] rgb,
    input wire [2:0] mode,item4,item5,item6,
    input wire [1:0] item7,shape,
    input wire [7:0] bri,con,sat,vol,
    input wire [2:0] transition_type,
    input wire transition_on,sub_on,sub_size,monitor_on,
    input wire [1:0] sub_mode,sub_pos,sub_bg,logo_sel,logo_size,language,
    input wire [2:0] ad_bg,
    input wire [1:0] visual_mode,
    input wire ad_on,ad_layout,wave_on,horizontal,visual_on,pause_audio,
    input wire [2:0] audio_status,
    input wire [5:0] legacy_idx,
    input wire [4:0] legacy_row,
    output wire [31:0] legacy_word,
    output wire ode,ohs,ovs,
    output reg [23:0] orgb
);
    localparam [8:0] T_HINT=9'd1;
    localparam [8:0] T_HINT4=9'd2;
    localparam [8:0] T_READONLY=9'd3;
    localparam [8:0] T_TITLE3=9'd4;
    localparam [8:0] T_TITLE4=9'd5;
    localparam [8:0] T_TITLE5=9'd6;
    localparam [8:0] T_TITLE6=9'd7;
    localparam [8:0] T_TITLE7=9'd8;
    localparam [8:0] T_TITLE8=9'd9;
    localparam [8:0] T_TRANSITION_ON=9'd10;
    localparam [8:0] T_BRI=9'd11;
    localparam [8:0] T_CON=9'd12;
    localparam [8:0] T_SAT=9'd13;
    localparam [8:0] T_VOL=9'd14;
    localparam [8:0] T_SUB=9'd15;
    localparam [8:0] T_SENTENCE=9'd16;
    localparam [8:0] T_POSITION=9'd17;
    localparam [8:0] T_BACKGROUND=9'd18;
    localparam [8:0] T_SIZE=9'd19;
    localparam [8:0] T_MONITOR=9'd20;
    localparam [8:0] T_LOGO=9'd21;
    localparam [8:0] T_LOGOSIZE=9'd22;
    localparam [8:0] T_AD=9'd23;
    localparam [8:0] T_ADBG=9'd24;
    localparam [8:0] T_LANG=9'd25;
    localparam [8:0] T_LAYOUT=9'd26;
    localparam [8:0] T_WAVE=9'd27;
    localparam [8:0] T_DIRECTION=9'd28;
    localparam [8:0] T_VISUAL=9'd29;
    localparam [8:0] T_SHAPE=9'd30;
    localparam [8:0] T_VERSION=9'd31;
    localparam [8:0] T_UART=9'd32;
    localparam [8:0] T_AUDIO=9'd33;
    localparam [8:0] T_CONTROL=9'd34;
    localparam [8:0] T_V1=9'd35;
    localparam [8:0] T_BAUD=9'd36;
    localparam [8:0] T_ENTRY=9'd37;
    localparam [8:0] T_ROLL=9'd38;
    localparam [8:0] T_CUT=9'd39;
    localparam [8:0] T_TYPE=9'd40;
    localparam [8:0] T_BOTTOM=9'd41;
    localparam [8:0] T_TOP=9'd42;
    localparam [8:0] T_RIGHT=9'd43;
    localparam [8:0] T_NONE=9'd44;
    localparam [8:0] T_HALF=9'd45;
    localparam [8:0] T_SOLID=9'd46;
    localparam [8:0] T_SMALL=9'd47;
    localparam [8:0] T_LARGE=9'd48;
    localparam [8:0] T_OFF=9'd49;
    localparam [8:0] T_STATIC=9'd50;
    localparam [8:0] T_MOVE=9'd51;
    localparam [8:0] T_LOGOS=9'd52;
    localparam [8:0] T_LOGOM=9'd53;
    localparam [8:0] T_LOGOL=9'd54;
    localparam [8:0] T_CN=9'd55;
    localparam [8:0] T_EN=9'd56;
    localparam [8:0] T_BOTH=9'd57;
    localparam [8:0] T_LEFT=9'd58;
    localparam [8:0] T_CENTER=9'd59;
    localparam [8:0] T_VERTICAL=9'd60;
    localparam [8:0] T_HORIZONTAL=9'd61;
    localparam [8:0] T_CONE=9'd62;
    localparam [8:0] T_BARS=9'd63;
    localparam [8:0] T_PULSE=9'd64;
    localparam [8:0] T_LAMPS=9'd65;
    localparam [8:0] T_PLAYING=9'd66;
    localparam [8:0] T_PAUSED=9'd67;
    localparam [8:0] T_MISSING=9'd68;
    localparam [8:0] T_UNDERRUN=9'd69;
    localparam [8:0] T_WAITING=9'd70;
    localparam [8:0] T_EFFECT0=9'd71;
    localparam [8:0] T_EFFECT1=9'd72;
    localparam [8:0] T_EFFECT2=9'd73;
    localparam [8:0] T_EFFECT3=9'd74;
    localparam [8:0] T_EFFECT4=9'd75;
    localparam [8:0] T_EFFECT5=9'd76;
    localparam [8:0] T_COUNT4_0=9'd77;
    localparam [8:0] T_COUNT4_1=9'd78;
    localparam [8:0] T_COUNT4_2=9'd79;
    localparam [8:0] T_COUNT4_3=9'd80;
    localparam [8:0] T_COUNT6_0=9'd81;
    localparam [8:0] T_COUNT6_1=9'd82;
    localparam [8:0] T_COUNT6_2=9'd83;
    localparam [8:0] T_COUNT6_3=9'd84;
    localparam [8:0] T_COUNT6_4=9'd85;
    localparam [8:0] T_COUNT6_5=9'd86;
    localparam [8:0] T_NUM_BASE=9'd87;
    localparam [8:0] T_ACCENT=9'd288;
    localparam [8:0] T_CARD=9'd289;
    localparam [8:0] T_ULINE=9'd290;
    localparam [8:0] T_TEAL=9'd291;
    localparam [8:0] T_LIVE=9'd292;
    localparam [8:0] T_IMPORT=9'd293;
    localparam [8:0] T_COUNT2_0=9'd294;
    localparam [8:0] T_COUNT2_1=9'd295;
    localparam [8:0] T_FLAT=9'd296;
    localparam [23:0] C_BG=24'h101e28,C_ROW=24'h152630,C_SEL=24'h20434d,
        C_TEXT=24'heef7f6,C_DIM=24'hadc3cb,C_ACCENT=24'h67dfcc,C_LINE=24'h304651;
    reg previous_vs;
    reg [2:0] page,selected;
    reg [8:0] title_token,count_token,footer_token;
    reg [8:0] name0,name1,name2,name3,name4,name5;
    reg [8:0] value0,value1,value2,value3,value4,value5;
    reg [5:0] switches,switch_values;
    reg [8:0] meter0,meter1,meter2,meter3;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            previous_vs<=0;page<=0;selected<=0;title_token<=0;count_token<=0;footer_token<=0;
            name0<=0;name1<=0;name2<=0;name3<=0;name4<=0;name5<=0;
            value0<=0;value1<=0;value2<=0;value3<=0;value4<=0;value5<=0;
            switches<=0;switch_values<=0;meter0<=0;meter1<=0;meter2<=0;meter3<=0;
        end else begin
            previous_vs<=vs;
            if(vs && !previous_vs)begin
                page<=mode;selected<=0;title_token<=0;count_token<=0;footer_token<=T_HINT;
                name0<=0;name1<=0;name2<=0;name3<=0;name4<=0;name5<=0;
                value0<=0;value1<=0;value2<=0;value3<=0;value4<=0;value5<=0;
                switches<=0;switch_values<=0;
                case(mode)
                2:begin
                    title_token<=T_TITLE3;selected<=transition_type;count_token<=T_COUNT6_0+{6'd0,transition_type};
                    name0<=T_EFFECT0;name1<=T_EFFECT1;name2<=T_EFFECT2;name3<=T_EFFECT3;name4<=T_EFFECT4;name5<=T_EFFECT5;
                    switch_values<={5'd0,transition_on};
                end
                3:begin
                    title_token<=T_TITLE4;selected<=item4;count_token<=T_COUNT4_0+{6'd0,item4};footer_token<=T_HINT4;
                    name0<=T_BRI;name1<=T_CON;name2<=T_SAT;name3<=T_VOL;
                    value0<=T_NUM_BASE+{1'b0,bri};value1<=T_NUM_BASE+{1'b0,con};
                    value2<=T_NUM_BASE+{1'b0,sat};value3<=T_NUM_BASE+{1'b0,vol};
                    meter0<={1'b0,bri}+{bri,1'b0};meter1<={1'b0,con}+{2'd0,con[7:1]};
                    meter2<={1'b0,sat}+{2'd0,sat[7:1]};meter3<={1'b0,vol}+{vol,1'b0};
                end
                4:begin
                    title_token<=T_TITLE5;selected<=item5;count_token<=T_COUNT6_0+{6'd0,item5};
                    name0<=T_SUB;name1<=T_SENTENCE;name2<=T_POSITION;name3<=T_BACKGROUND;name4<=T_SIZE;name5<=T_MONITOR;
                    switches<=6'b100001;switch_values<={monitor_on,4'd0,sub_on};
                    value1<=sub_mode==0 ? T_ROLL : sub_mode==1 ? T_CUT : T_TYPE;
                    value2<=sub_pos==0 ? T_BOTTOM : sub_pos==1 ? T_TOP : T_RIGHT;
                    value3<=sub_bg==0 ? T_NONE : sub_bg==1 ? T_HALF : T_SOLID;
                    value4<=sub_size ? T_LARGE : T_SMALL;
                end
                5:begin
                    title_token<=T_TITLE6;
                    selected<=item6==0 ? 3'd0 : item6==5 ? 3'd1 : item6+1'b1;
                    count_token<=T_COUNT6_0+(item6==0 ? 9'd0 : item6==5 ? 9'd1 : {6'd0,item6}+1'b1);
                    name0<=T_LOGO;name1<=T_LOGOSIZE;name2<=T_AD;name3<=T_ADBG;name4<=T_LANG;name5<=T_LAYOUT;
                    value0<=logo_sel==0 ? T_OFF : logo_sel==1 ? T_STATIC : T_MOVE;
                    value1<=logo_size==0 ? T_LOGOS : logo_size==1 ? T_LOGOM : T_LOGOL;
                    switches<=6'b000100;switch_values<={3'd0,ad_on,2'd0};
                    value3<=ad_bg==0 ? T_NONE : ad_bg==1 ? T_HALF : ad_bg==2 ? T_SOLID : T_ACCENT+{6'd0,ad_bg}-9'd3;
                    value4<=language==0 ? T_CN : language==1 ? T_EN : T_BOTH;
                    value5<=ad_layout ? T_CENTER : T_LEFT;
                end
                6:begin
                    title_token<=T_TITLE7;selected<=item7==0 ? 3'd0 : 3'd1;
                    count_token<=item7==0 ? T_COUNT2_0 : T_COUNT2_1;
                    name0<=T_WAVE;name1<=T_SHAPE;
                    switches<=6'b000001;switch_values<={5'd0,wave_on};
                    value1<=visual_mode==2 ? T_FLAT : T_CONE+{7'd0,shape};
                end
                default:;
                endcase
            end
        end
    end
    wire [11:0] x,y;
    osd_position position(clk,rst,de,vs,x,y,);
    reg [2:0] row_pre;
    reg [11:0] top_pre;

    always @*begin
        row_pre=0;top_pre=84;
        if(page==2)begin
            if(y>=168)begin row_pre=4;top_pre=168;end
            else if(y>=126)begin row_pre=2;top_pre=126;end
            if(x>=1076)row_pre=row_pre+1'b1;
            if(y>=210)begin row_pre=6;top_pre=210;end
        end else begin
            if(y>=294)begin row_pre=5;top_pre=294;end
            else if(y>=252)begin row_pre=4;top_pre=252;end
            else if(y>=210)begin row_pre=3;top_pre=210;end
            else if(y>=168)begin row_pre=2;top_pre=168;end
            else if(y>=126)begin row_pre=1;top_pre=126;end
        end
    end

    wire header_pre=y>=40 && y<60;
    wire footer_pre=y>=352 && y<372;
    wire grid_pre=page==2 && row_pre<6;
    wire count_pre=header_pre && x>=(page==7 ? 12'd1188 : 12'd1198);
    wire value_pre=!grid_pre && x>=1108;
    wire prefix_pre=header_pre && !count_pre && x<938;
    wire [11:0] left_pre=grid_pre && row_pre[0] ? 12'd1076 : 12'd908;
    wire [11:0] start_pre=header_pre ? (count_pre ? (page==7 ? 12'd1188 : 12'd1198) :
        (prefix_pre ? 12'd908 : 12'd938)) : footer_pre ? 12'd908 :
        value_pre ? 12'd1108 : left_pre+12'd12;
    reg [11:0] text_offset;

    reg [11:0] x_geom,y_geom,row_top;
    reg [2:0] row_now;
    reg [26:0] pixel_geom;
    wire de_geom=pixel_geom[26],hs_geom=pixel_geom[25],vs_geom=pixel_geom[24];
    always @(posedge clk or posedge rst)begin
        if(rst)begin x_geom<=0;y_geom<=0;row_top<=0;row_now<=0;pixel_geom<=0;text_offset<=0;end
        else begin
            x_geom<=x;y_geom<=y;row_top<=top_pre;row_now<=row_pre;
            text_offset<=x-start_pre;
            pixel_geom<={de,hs,vs,rgb};
        end
    end
    `include "ui_capsule_geometry.vh"
    wire [11:0] row_y=y_geom-row_top;
    wire grid=page==2 && row_now<6;
    wire [11:0] cell_left=grid && row_now[0] ? 12'd1076 : 12'd908;
    wire [11:0] cell_right=grid && !row_now[0] ? 12'd1064 : 12'd1228;
    wire valid_row=page==2 ? row_now<=6 :
        (page==4 || page==5) ? row_now<6 : page==6 ? row_now<2 : row_now<4;
    wire row_hit=valid_row && x_geom>=cell_left && x_geom<cell_right &&
        y_geom>=row_top && row_y<12'd36;
    wire header=y_geom>=40 && y_geom<60;
    wire footer=y_geom>=352 && y_geom<372;
    wire count_area=header && x_geom>=(page==7 ? 12'd1188 : 12'd1198);
    wire value_area=!grid && x_geom>=1108;
    wire title_prefix=header && !count_area && x_geom<938;
    wire title_rest=header && !count_area && !title_prefix;
    wire [11:0] text_start=header ? (count_area ? (page==7 ? 12'd1188 : 12'd1198) : (title_prefix ? 12'd908 : 12'd938)) :
        footer ? 12'd908 : value_area ? 12'd1108 : cell_left+12'd12;

    wire narrow_text=title_prefix || (header && count_area) ||
        (!header && !footer && value_area &&
         (page==3 || (page==7 && row_now<=1)));
    wire [6:0] div5_input=narrow_text ? {1'b0,text_offset[6:1]} : text_offset[8:2];
    function [6:0] divide5;
        input [6:0] value;
        begin case(value)
        7'd0:divide5=7'd0;
        7'd1:divide5=7'd1;
        7'd2:divide5=7'd2;
        7'd3:divide5=7'd3;
        7'd4:divide5=7'd4;
        7'd5:divide5=7'd8;
        7'd6:divide5=7'd9;
        7'd7:divide5=7'd10;
        7'd8:divide5=7'd11;
        7'd9:divide5=7'd12;
        7'd10:divide5=7'd16;
        7'd11:divide5=7'd17;
        7'd12:divide5=7'd18;
        7'd13:divide5=7'd19;
        7'd14:divide5=7'd20;
        7'd15:divide5=7'd24;
        7'd16:divide5=7'd25;
        7'd17:divide5=7'd26;
        7'd18:divide5=7'd27;
        7'd19:divide5=7'd28;
        7'd20:divide5=7'd32;
        7'd21:divide5=7'd33;
        7'd22:divide5=7'd34;
        7'd23:divide5=7'd35;
        7'd24:divide5=7'd36;
        7'd25:divide5=7'd40;
        7'd26:divide5=7'd41;
        7'd27:divide5=7'd42;
        7'd28:divide5=7'd43;
        7'd29:divide5=7'd44;
        7'd30:divide5=7'd48;
        7'd31:divide5=7'd49;
        7'd32:divide5=7'd50;
        7'd33:divide5=7'd51;
        7'd34:divide5=7'd52;
        7'd35:divide5=7'd56;
        7'd36:divide5=7'd57;
        7'd37:divide5=7'd58;
        7'd38:divide5=7'd59;
        7'd39:divide5=7'd60;
        7'd40:divide5=7'd64;
        7'd41:divide5=7'd65;
        7'd42:divide5=7'd66;
        7'd43:divide5=7'd67;
        7'd44:divide5=7'd68;
        7'd45:divide5=7'd72;
        7'd46:divide5=7'd73;
        7'd47:divide5=7'd74;
        7'd48:divide5=7'd75;
        7'd49:divide5=7'd76;
        7'd50:divide5=7'd80;
        7'd51:divide5=7'd81;
        7'd52:divide5=7'd82;
        7'd53:divide5=7'd83;
        7'd54:divide5=7'd84;
        7'd55:divide5=7'd88;
        7'd56:divide5=7'd89;
        7'd57:divide5=7'd90;
        7'd58:divide5=7'd91;
        7'd59:divide5=7'd92;
        7'd60:divide5=7'd96;
        7'd61:divide5=7'd97;
        7'd62:divide5=7'd98;
        7'd63:divide5=7'd99;
        7'd64:divide5=7'd100;
        7'd65:divide5=7'd104;
        7'd66:divide5=7'd105;
        7'd67:divide5=7'd106;
        7'd68:divide5=7'd107;
        7'd69:divide5=7'd108;
        7'd70:divide5=7'd112;
        7'd71:divide5=7'd113;
        7'd72:divide5=7'd114;
        7'd73:divide5=7'd115;
        7'd74:divide5=7'd116;
        7'd75:divide5=7'd120;
        7'd76:divide5=7'd121;
        7'd77:divide5=7'd122;
        7'd78:divide5=7'd123;
        7'd79:divide5=7'd124;
        default:divide5=7'd0;
        endcase end
    endfunction
    wire [6:0] div5_result=divide5(div5_input);
    wire [3:0] column_now=div5_result[6:3]+(title_rest ? 4'd3 : 4'd0);
    wire [4:0] glyph_x_now={div5_result[2:0],2'b00} |
        (narrow_text ? {3'd0,text_offset[0],1'b0} : {3'd0,text_offset[1:0]});
    function [3:0] sample16;
        input [4:0] coordinate;
        begin case(coordinate)
        5'd0:sample16=4'd0;
        5'd1:sample16=4'd0;
        5'd2:sample16=4'd1;
        5'd3:sample16=4'd2;
        5'd4:sample16=4'd3;
        5'd5:sample16=4'd4;
        5'd6:sample16=4'd4;
        5'd7:sample16=4'd5;
        5'd8:sample16=4'd6;
        5'd9:sample16=4'd7;
        5'd10:sample16=4'd8;
        5'd11:sample16=4'd8;
        5'd12:sample16=4'd9;
        5'd13:sample16=4'd10;
        5'd14:sample16=4'd11;
        5'd15:sample16=4'd12;
        5'd16:sample16=4'd12;
        5'd17:sample16=4'd13;
        5'd18:sample16=4'd14;
        5'd19:sample16=4'd15;
        default:sample16=0;
        endcase end
    endfunction
    wire [11:0] text_y=header ? y_geom-12'd40 : footer ? y_geom-12'd352 :
        row_y-12'd8;
    wire selected_now=page!=7 && (page==2 ? row_now==selected : row_now==selected);
    wire switch_now=page==2 ? row_now==6 : switches[row_now];
    wire on_now=page==2 ? switch_values[0] : switch_values[row_now];
    wire text_now=(header || footer || row_hit) && x_geom>=text_start &&

        text_y<20 && text_offset<(header ? (count_area ? (page==7 ? 12'd80 : 12'd60) : 12'd260) : footer ? 12'd320 :
                                value_area ? 12'd120 : grid ? 12'd160 : 12'd180) &&
        !(switch_now && value_area && !header && !footer);

    wire [11:0] toggle_y=row_y-12'd4;
    wire [11:0] toggle_x=x_geom-12'd1108;
    wire toggle_body=switch_now && row_hit && ui_capsule_body(toggle_x,toggle_y);
    wire knob=toggle_body && ui_capsule_knob(toggle_x,toggle_y,on_now);
    reg [8:0] meter_now;
    always @*case(row_now)
        0:meter_now=meter0;1:meter_now=meter1;2:meter_now=meter2;default:meter_now=meter3;
    endcase
    wire meter_hit=page==3 && row_hit && row_y>=32 && row_y<35 && x_geom>=920 && x_geom<1220;
    reg [23:0] background_now,ink_now;
    always @*begin
        background_now=C_BG;ink_now=C_DIM;
        if(row_hit)begin background_now=selected_now ? C_SEL : C_ROW;ink_now=value_area ? C_ACCENT : selected_now ? C_TEXT : C_DIM;end
        if(header)ink_now=count_area ? C_DIM : C_TEXT;
        if(x_geom<890)background_now=C_ACCENT;
        if(y_geom==72 && x_geom>=906 && x_geom<1230)background_now=C_LINE;
        if(row_hit && selected_now && x_geom<cell_left+3)background_now=C_ACCENT;
        if(meter_hit)background_now=x_geom-920<meter_now ? C_ACCENT : C_LINE;
        if(toggle_body)background_now=on_now ? C_ACCENT : C_LINE;
        if(knob)background_now=on_now ? C_TEXT : C_DIM;
    end
    reg [2:0] row1;
    reg header1,footer1,count1,value1_flag,text1,panel1;
    reg [4:0] gx1;
    reg [3:0] column1,gy1,gx2,gx3,gy2;
    reg text2,text3,panel2,panel3;
    reg [23:0] bg1,bg2,bg3,ink1,ink2,ink3,rgb1,rgb2,rgb3;
    reg [3:0] de_pipe,hs_pipe,vs_pipe;
    reg [8:0] token;
    always @*begin
        case(row1)
            0:token=value1_flag ? value0 : name0;
            1:token=value1_flag ? value1 : name1;
            2:token=value1_flag ? value2 : name2;
            3:token=value1_flag ? value3 : name3;
            4:token=value1_flag ? value4 : name4;
            5:token=value1_flag ? value5 : name5;
            default:token=T_TRANSITION_ON;
        endcase
        if(header1)token=count1 ? count_token : title_token;
        if(footer1)token=footer_token;
    end
    wire [7:0] glyph_code;
    scaled_text_rom text_rom(clk,touch_clk,{token,column1},touch_text_addr,glyph_code,touch_text_bits);
    wire [15:0] font_bits,legacy_bits;
    wire [7:0] mapped_legacy;
    scaled_legacy_map legacy_map(legacy_idx,mapped_legacy);

    assign legacy_suppress=page!=1 || mode!=1;
    wire [11:0] hdmi_addr=page>=2 ? {glyph_code,gy2} : {mapped_legacy,legacy_row[4:1]};
    scaled_glyph_rom glyph_rom(clk,touch_clk,hdmi_addr,touch_font_addr,font_bits,touch_font_bits);
    assign legacy_bits=font_bits;
    genvar k;
    generate for(k=0;k<16;k=k+1)begin:legacy_expand
        assign legacy_word[31-2*k -: 2]={2{legacy_bits[15-k]}};
    end endgenerate
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            row1<=0;header1<=0;footer1<=0;count1<=0;value1_flag<=0;text1<=0;panel1<=0;
            column1<=0;gx1<=0;gy1<=0;gx2<=0;gx3<=0;gy2<=0;
            text2<=0;text3<=0;panel2<=0;panel3<=0;
            bg1<=0;bg2<=0;bg3<=0;ink1<=0;ink2<=0;ink3<=0;
            rgb1<=0;rgb2<=0;rgb3<=0;orgb<=0;de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
        end else begin
            row1<=row_now;header1<=header;footer1<=footer;count1<=count_area;value1_flag<=value_area;
            text1<=text_now;panel1<=de_geom && page>=2 && page<=6 && x_geom>=888 && x_geom<1248 && y_geom>=24 && y_geom<380;
            column1<=column_now;gx1<=glyph_x_now;gy1<=sample16(text_y[4:0]);
            gx2<=sample16(gx1);gx3<=gx2;gy2<=gy1;text2<=text1;text3<=text2 && panel2;panel2<=panel1;panel3<=panel2;
            bg1<=background_now;bg2<=bg1;bg3<=panel2 ? bg2 : rgb2;ink1<=ink_now;ink2<=ink1;ink3<=ink2;
            rgb1<=pixel_geom[23:0];rgb2<=rgb1;rgb3<=rgb2;
            orgb<=text3 && font_bits[15-gx3] ? ink3 : bg3;
            de_pipe<={de_pipe[2:0],de_geom};hs_pipe<={hs_pipe[2:0],hs_geom};vs_pipe<={vs_pipe[2:0],vs_geom};
        end
    end
    assign ode=de_pipe[3];assign ohs=hs_pipe[3];assign ovs=vs_pipe[3];
endmodule

module scaled_menu_delay(input wire clk,rst,de,hs,vs,input wire [23:0] rgb,
                         output wire ode,ohs,ovs,output wire [23:0] orgb);
    reg [26:0] d0,d1,d2,d3;
    always @(posedge clk or posedge rst)begin
        if(rst)begin d0<=0;d1<=0;d2<=0;d3<=0;end
        else begin d0<={de,hs,vs,rgb};d1<=d0;d2<=d1;d3<=d2;end
    end
    assign {ode,ohs,ovs,orgb}=d3;
endmodule

module scaled_text_rom(input wire clk,touch_clk,input wire [12:0] a,b,output wire [7:0] q,r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
      .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
      .IMPLEMENT("32K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("python/scaled_text.mif"),.FILL_ALL("NONE")) mem(
      .dia(8'd0),.dib(8'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(1'b0),.web(1'b0),
      .bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(touch_clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
module scaled_glyph_rom(input wire clk,touch_clk,input wire [11:0] a,b,output wire [15:0] q,r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),
      .DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
      .IMPLEMENT("32K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("python/scaled_glyph.mif"),.FILL_ALL("NONE")) mem(
      .dia(16'd0),.dib(16'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(1'b0),.web(1'b0),
      .bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(touch_clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
module scaled_legacy_map(input wire [5:0] index,output reg [7:0] code);
    always @*case(index)
    6'd43:code=8'd136;
    6'd44:code=8'd86;
    6'd45:code=8'd137;
    6'd46:code=8'd138;
    6'd47:code=8'd139;
    6'd48:code=8'd140;
    6'd49:code=8'd90;
    6'd50:code=8'd91;
    6'd51:code=8'd141;
    6'd52:code=8'd98;
    6'd53:code=8'd142;
    6'd54:code=8'd143;
    6'd55:code=8'd144;
    6'd56:code=8'd92;
    6'd57:code=8'd145;
    6'd58:code=8'd146;
    6'd59:code=8'd147;
    default:code=0;
    endcase
endmodule
