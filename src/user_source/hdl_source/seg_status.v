`timescale 1ns / 1ps

module seg_status #(
    parameter OUTPUT_TOKENS = 0,
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BLINK_HZ    = 4              // 闪烁频率
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    // 来自 mode_decode
    input  wire [2:0]  I_mode_num,         // 0..7（内部 +1 显示为 1..8）

    // 来自 param_reg
    input  wire [2:0]  I_param_item,       // 0..5
    input  wire [15:0] I_param_val,

    input  wire [2:0]  I_tran_type,
    input  wire        I_tran_en,

    input  wire        I_auto_on,          // P2 轮播开关状态
    input  wire [4:0]  I_img_idx,

    input  wire        I_sd_warn,
    input  wire [4:0]  I_sd_found,

    input  wire [2:0]  I_aud_stat,
    input  wire        I_aud_mute,

    input  wire [2:0]  I_fsm_sel,
    input  wire [3:0]  I_aud_fsm,
    input  wire [3:0]  I_vid_fsm,
    input  wire [3:0]  I_load_cnt,       // 累计整图加载次数（低 4 位）
    input  wire [3:0]  I_sdram_flags,    // SDRAM 冲突锁存位 {C3,C2,-,C0}

 input  wire [3:0]  I_wr_diag,
 input  wire [3:0]  I_fifo_flags,

 input  wire [7:0]  I_uart_rx_cnt,
 input  wire [7:0]  I_uart_tx_cnt,

 input  wire [2:0]  I_ctrl_diag,
    output reg  [7:0]  O_seg_5,
    output reg  [7:0]  O_seg_4,
    output reg  [7:0]  O_seg_3,
    output reg  [7:0]  O_seg_2,
    output reg  [7:0]  O_seg_1,
    output reg  [7:0]  O_seg_0
);

    localparam [4:0] CH_BLANK = 5'd31;   // 全灭
    localparam [4:0] CH_DASH = 5'd16;   // '-' (g 亮)
    localparam [4:0] CH_P = 5'd17;   // 'P'
    localparam [4:0] CH_B = 5'd11;   // 'B'
    localparam [4:0] CH_S = 5'd5;   // 'S' (与 5 同形，可接受)
    localparam [4:0] CH_r = 5'd18;   // 'r'
    localparam [4:0] CH_t = 5'd19;   // 't'
    localparam [4:0] CH_O = 5'd0;   // 'O'（用于 OFF）
    localparam [4:0] CH_E = 5'd14;   // 'E' SD 诊断：常量填错
    localparam [4:0] CH_n = 5'd20;   // 'n' SD 诊断：未找到（备用）
    localparam [4:0] CH_u = 5'd21;   // 'u' 音频诊断：FIFO 欠载
    localparam [4:0] CH_PAUSE = 5'd17;   // 'P' 音频诊断：被静音开关关闭
    localparam [4:0] CH_F = 5'd15;   // 'F' 音频诊断：没找到 WAV

    localparam [4:0] CH_L = 5'd22;   // 'L' 加载在途（卡住时恒亮）
    localparam [4:0] CH_C = 5'd12;

    function [4:0] num_char;
        input [3:0] d;
        begin num_char=d<4'd10 ? {1'b0,d} : CH_BLANK; end
    endfunction

    function [4:0] CH_hexA_to_F;
        input [3:0] d;
        begin CH_hexA_to_F=d>=4'd10 ? {1'b0,d} : CH_BLANK; end
    endfunction

    function [7:0] status_segments;
        input [4:0] token;
        begin
            case(token)
                5'd0: status_segments=8'hc0;
                5'd1: status_segments=8'hf9;
                5'd2: status_segments=8'ha4;
                5'd3: status_segments=8'hb0;
                5'd4: status_segments=8'h99;
                5'd5: status_segments=8'h92;
                5'd6: status_segments=8'h82;
                5'd7: status_segments=8'hf8;
                5'd8: status_segments=8'h80;
                5'd9: status_segments=8'h90;
                5'd10: status_segments=8'h88;
                5'd11: status_segments=8'h83;
                5'd12: status_segments=8'hc6;
                5'd13: status_segments=8'ha1;
                5'd14: status_segments=8'h86;
                5'd15: status_segments=8'h8e;
                5'd16: status_segments=8'hbf;
                5'd17: status_segments=8'h8c;
                5'd18: status_segments=8'haf;
                5'd19: status_segments=8'h8f;
                5'd20: status_segments=8'hab;
                5'd21: status_segments=8'hc1;
                5'd22: status_segments=8'hc7;
                5'd23: status_segments=8'h79;
                default: status_segments=8'hff;
            endcase
        end
    endfunction

    reg [4:0] ch5, ch4, ch3, ch2, ch1, ch0;

    reg        sd_bad;
    reg [3:0]  sd_f_ten, sd_f_one;

    wire [3:0] item_disp = {1'b0, I_param_item} + 4'd1;

    function [11:0] decimal_lookup;
        input [7:0] value;
        begin
            case(value)
                8'd0: decimal_lookup=12'h000;
                8'd1: decimal_lookup=12'h001;
                8'd2: decimal_lookup=12'h002;
                8'd3: decimal_lookup=12'h003;
                8'd4: decimal_lookup=12'h004;
                8'd5: decimal_lookup=12'h005;
                8'd6: decimal_lookup=12'h006;
                8'd7: decimal_lookup=12'h007;
                8'd8: decimal_lookup=12'h008;
                8'd9: decimal_lookup=12'h009;
                8'd10: decimal_lookup=12'h010;
                8'd11: decimal_lookup=12'h011;
                8'd12: decimal_lookup=12'h012;
                8'd13: decimal_lookup=12'h013;
                8'd14: decimal_lookup=12'h014;
                8'd15: decimal_lookup=12'h015;
                8'd16: decimal_lookup=12'h016;
                8'd17: decimal_lookup=12'h017;
                8'd18: decimal_lookup=12'h018;
                8'd19: decimal_lookup=12'h019;
                8'd20: decimal_lookup=12'h020;
                8'd21: decimal_lookup=12'h021;
                8'd22: decimal_lookup=12'h022;
                8'd23: decimal_lookup=12'h023;
                8'd24: decimal_lookup=12'h024;
                8'd25: decimal_lookup=12'h025;
                8'd26: decimal_lookup=12'h026;
                8'd27: decimal_lookup=12'h027;
                8'd28: decimal_lookup=12'h028;
                8'd29: decimal_lookup=12'h029;
                8'd30: decimal_lookup=12'h030;
                8'd31: decimal_lookup=12'h031;
                8'd32: decimal_lookup=12'h032;
                8'd33: decimal_lookup=12'h033;
                8'd34: decimal_lookup=12'h034;
                8'd35: decimal_lookup=12'h035;
                8'd36: decimal_lookup=12'h036;
                8'd37: decimal_lookup=12'h037;
                8'd38: decimal_lookup=12'h038;
                8'd39: decimal_lookup=12'h039;
                8'd40: decimal_lookup=12'h040;
                8'd41: decimal_lookup=12'h041;
                8'd42: decimal_lookup=12'h042;
                8'd43: decimal_lookup=12'h043;
                8'd44: decimal_lookup=12'h044;
                8'd45: decimal_lookup=12'h045;
                8'd46: decimal_lookup=12'h046;
                8'd47: decimal_lookup=12'h047;
                8'd48: decimal_lookup=12'h048;
                8'd49: decimal_lookup=12'h049;
                8'd50: decimal_lookup=12'h050;
                8'd51: decimal_lookup=12'h051;
                8'd52: decimal_lookup=12'h052;
                8'd53: decimal_lookup=12'h053;
                8'd54: decimal_lookup=12'h054;
                8'd55: decimal_lookup=12'h055;
                8'd56: decimal_lookup=12'h056;
                8'd57: decimal_lookup=12'h057;
                8'd58: decimal_lookup=12'h058;
                8'd59: decimal_lookup=12'h059;
                8'd60: decimal_lookup=12'h060;
                8'd61: decimal_lookup=12'h061;
                8'd62: decimal_lookup=12'h062;
                8'd63: decimal_lookup=12'h063;
                8'd64: decimal_lookup=12'h064;
                8'd65: decimal_lookup=12'h065;
                8'd66: decimal_lookup=12'h066;
                8'd67: decimal_lookup=12'h067;
                8'd68: decimal_lookup=12'h068;
                8'd69: decimal_lookup=12'h069;
                8'd70: decimal_lookup=12'h070;
                8'd71: decimal_lookup=12'h071;
                8'd72: decimal_lookup=12'h072;
                8'd73: decimal_lookup=12'h073;
                8'd74: decimal_lookup=12'h074;
                8'd75: decimal_lookup=12'h075;
                8'd76: decimal_lookup=12'h076;
                8'd77: decimal_lookup=12'h077;
                8'd78: decimal_lookup=12'h078;
                8'd79: decimal_lookup=12'h079;
                8'd80: decimal_lookup=12'h080;
                8'd81: decimal_lookup=12'h081;
                8'd82: decimal_lookup=12'h082;
                8'd83: decimal_lookup=12'h083;
                8'd84: decimal_lookup=12'h084;
                8'd85: decimal_lookup=12'h085;
                8'd86: decimal_lookup=12'h086;
                8'd87: decimal_lookup=12'h087;
                8'd88: decimal_lookup=12'h088;
                8'd89: decimal_lookup=12'h089;
                8'd90: decimal_lookup=12'h090;
                8'd91: decimal_lookup=12'h091;
                8'd92: decimal_lookup=12'h092;
                8'd93: decimal_lookup=12'h093;
                8'd94: decimal_lookup=12'h094;
                8'd95: decimal_lookup=12'h095;
                8'd96: decimal_lookup=12'h096;
                8'd97: decimal_lookup=12'h097;
                8'd98: decimal_lookup=12'h098;
                8'd99: decimal_lookup=12'h099;
                8'd100: decimal_lookup=12'h100;
                8'd101: decimal_lookup=12'h101;
                8'd102: decimal_lookup=12'h102;
                8'd103: decimal_lookup=12'h103;
                8'd104: decimal_lookup=12'h104;
                8'd105: decimal_lookup=12'h105;
                8'd106: decimal_lookup=12'h106;
                8'd107: decimal_lookup=12'h107;
                8'd108: decimal_lookup=12'h108;
                8'd109: decimal_lookup=12'h109;
                8'd110: decimal_lookup=12'h110;
                8'd111: decimal_lookup=12'h111;
                8'd112: decimal_lookup=12'h112;
                8'd113: decimal_lookup=12'h113;
                8'd114: decimal_lookup=12'h114;
                8'd115: decimal_lookup=12'h115;
                8'd116: decimal_lookup=12'h116;
                8'd117: decimal_lookup=12'h117;
                8'd118: decimal_lookup=12'h118;
                8'd119: decimal_lookup=12'h119;
                8'd120: decimal_lookup=12'h120;
                8'd121: decimal_lookup=12'h121;
                8'd122: decimal_lookup=12'h122;
                8'd123: decimal_lookup=12'h123;
                8'd124: decimal_lookup=12'h124;
                8'd125: decimal_lookup=12'h125;
                8'd126: decimal_lookup=12'h126;
                8'd127: decimal_lookup=12'h127;
                8'd128: decimal_lookup=12'h128;
                8'd129: decimal_lookup=12'h129;
                8'd130: decimal_lookup=12'h130;
                8'd131: decimal_lookup=12'h131;
                8'd132: decimal_lookup=12'h132;
                8'd133: decimal_lookup=12'h133;
                8'd134: decimal_lookup=12'h134;
                8'd135: decimal_lookup=12'h135;
                8'd136: decimal_lookup=12'h136;
                8'd137: decimal_lookup=12'h137;
                8'd138: decimal_lookup=12'h138;
                8'd139: decimal_lookup=12'h139;
                8'd140: decimal_lookup=12'h140;
                8'd141: decimal_lookup=12'h141;
                8'd142: decimal_lookup=12'h142;
                8'd143: decimal_lookup=12'h143;
                8'd144: decimal_lookup=12'h144;
                8'd145: decimal_lookup=12'h145;
                8'd146: decimal_lookup=12'h146;
                8'd147: decimal_lookup=12'h147;
                8'd148: decimal_lookup=12'h148;
                8'd149: decimal_lookup=12'h149;
                8'd150: decimal_lookup=12'h150;
                8'd151: decimal_lookup=12'h151;
                8'd152: decimal_lookup=12'h152;
                8'd153: decimal_lookup=12'h153;
                8'd154: decimal_lookup=12'h154;
                8'd155: decimal_lookup=12'h155;
                8'd156: decimal_lookup=12'h156;
                8'd157: decimal_lookup=12'h157;
                8'd158: decimal_lookup=12'h158;
                8'd159: decimal_lookup=12'h159;
                8'd160: decimal_lookup=12'h160;
                8'd161: decimal_lookup=12'h161;
                8'd162: decimal_lookup=12'h162;
                8'd163: decimal_lookup=12'h163;
                8'd164: decimal_lookup=12'h164;
                8'd165: decimal_lookup=12'h165;
                8'd166: decimal_lookup=12'h166;
                8'd167: decimal_lookup=12'h167;
                8'd168: decimal_lookup=12'h168;
                8'd169: decimal_lookup=12'h169;
                8'd170: decimal_lookup=12'h170;
                8'd171: decimal_lookup=12'h171;
                8'd172: decimal_lookup=12'h172;
                8'd173: decimal_lookup=12'h173;
                8'd174: decimal_lookup=12'h174;
                8'd175: decimal_lookup=12'h175;
                8'd176: decimal_lookup=12'h176;
                8'd177: decimal_lookup=12'h177;
                8'd178: decimal_lookup=12'h178;
                8'd179: decimal_lookup=12'h179;
                8'd180: decimal_lookup=12'h180;
                8'd181: decimal_lookup=12'h181;
                8'd182: decimal_lookup=12'h182;
                8'd183: decimal_lookup=12'h183;
                8'd184: decimal_lookup=12'h184;
                8'd185: decimal_lookup=12'h185;
                8'd186: decimal_lookup=12'h186;
                8'd187: decimal_lookup=12'h187;
                8'd188: decimal_lookup=12'h188;
                8'd189: decimal_lookup=12'h189;
                8'd190: decimal_lookup=12'h190;
                8'd191: decimal_lookup=12'h191;
                8'd192: decimal_lookup=12'h192;
                8'd193: decimal_lookup=12'h193;
                8'd194: decimal_lookup=12'h194;
                8'd195: decimal_lookup=12'h195;
                8'd196: decimal_lookup=12'h196;
                8'd197: decimal_lookup=12'h197;
                8'd198: decimal_lookup=12'h198;
                8'd199: decimal_lookup=12'h199;
                8'd200: decimal_lookup=12'h1a0;
                8'd201: decimal_lookup=12'h1a1;
                8'd202: decimal_lookup=12'h1a2;
                8'd203: decimal_lookup=12'h1a3;
                8'd204: decimal_lookup=12'h1a4;
                8'd205: decimal_lookup=12'h1a5;
                8'd206: decimal_lookup=12'h1a6;
                8'd207: decimal_lookup=12'h1a7;
                8'd208: decimal_lookup=12'h1a8;
                8'd209: decimal_lookup=12'h1a9;
                8'd210: decimal_lookup=12'h1b0;
                8'd211: decimal_lookup=12'h1b1;
                8'd212: decimal_lookup=12'h1b2;
                8'd213: decimal_lookup=12'h1b3;
                8'd214: decimal_lookup=12'h1b4;
                8'd215: decimal_lookup=12'h1b5;
                8'd216: decimal_lookup=12'h1b6;
                8'd217: decimal_lookup=12'h1b7;
                8'd218: decimal_lookup=12'h1b8;
                8'd219: decimal_lookup=12'h1b9;
                8'd220: decimal_lookup=12'h1c0;
                8'd221: decimal_lookup=12'h1c1;
                8'd222: decimal_lookup=12'h1c2;
                8'd223: decimal_lookup=12'h1c3;
                8'd224: decimal_lookup=12'h1c4;
                8'd225: decimal_lookup=12'h1c5;
                8'd226: decimal_lookup=12'h1c6;
                8'd227: decimal_lookup=12'h1c7;
                8'd228: decimal_lookup=12'h1c8;
                8'd229: decimal_lookup=12'h1c9;
                8'd230: decimal_lookup=12'h1d0;
                8'd231: decimal_lookup=12'h1d1;
                8'd232: decimal_lookup=12'h1d2;
                8'd233: decimal_lookup=12'h1d3;
                8'd234: decimal_lookup=12'h1d4;
                8'd235: decimal_lookup=12'h1d5;
                8'd236: decimal_lookup=12'h1d6;
                8'd237: decimal_lookup=12'h1d7;
                8'd238: decimal_lookup=12'h1d8;
                8'd239: decimal_lookup=12'h1d9;
                8'd240: decimal_lookup=12'h1e0;
                8'd241: decimal_lookup=12'h1e1;
                8'd242: decimal_lookup=12'h1e2;
                8'd243: decimal_lookup=12'h1e3;
                8'd244: decimal_lookup=12'h1e4;
                8'd245: decimal_lookup=12'h1e5;
                8'd246: decimal_lookup=12'h1e6;
                8'd247: decimal_lookup=12'h1e7;
                8'd248: decimal_lookup=12'h1e8;
                8'd249: decimal_lookup=12'h1e9;
                8'd250: decimal_lookup=12'h1f0;
                8'd251: decimal_lookup=12'h1f1;
                8'd252: decimal_lookup=12'h1f2;
                8'd253: decimal_lookup=12'h1f3;
                8'd254: decimal_lookup=12'h1f4;
                8'd255: decimal_lookup=12'h1f5;
                default: decimal_lookup=12'd0;
            endcase
        end
    endfunction
    reg [11:0] decimal_value;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) decimal_value<=12'd0;
        else decimal_value<=decimal_lookup(I_param_val[7:0]);
    end
    wire [3:0] v_hund=decimal_value[11:8];
    wire val_ge100=decimal_value[8];
    wire [3:0] v_ten=decimal_value[7:4];
    wire [3:0] v_one=decimal_value[3:0];

    wire [4:0] img_disp = I_img_idx;
    wire [3:0] img_ten  = (img_disp >= 5'd10) ? 4'd1 : 4'd0;   // 只有 10..16 有十位
    wire [3:0] img_one  = img_disp - (img_ten * 4'd10);        // 个位

    wire       img_2dig = (img_disp >= 5'd10);

    always @(*) begin
        ch5 = num_char({1'b0, I_mode_num} + 4'd1);

        if (I_fsm_sel == 2'd1)
            ch4 = num_char(I_aud_fsm);
        else if (I_fsm_sel == 2'd2)
            ch4 = num_char(I_vid_fsm);
        else if (I_fsm_sel == 2'd3)
            ch4 = (I_load_cnt < 4'd10) ? num_char(I_load_cnt)
                                       : CH_hexA_to_F(I_load_cnt);
        else if (I_fsm_sel == 3'd4)
            ch4 = (I_sdram_flags < 4'd10) ? num_char(I_sdram_flags)
                                          : CH_hexA_to_F(I_sdram_flags);

        else if (I_fsm_sel == 3'd5)
            ch4 = (I_fifo_flags < 4'd10) ? num_char(I_fifo_flags)
                                         : CH_hexA_to_F(I_fifo_flags);

        else if (I_fsm_sel == 3'd6)
            ch4 = (I_wr_diag < 4'd10) ? num_char(I_wr_diag)
                                      : CH_hexA_to_F(I_wr_diag);
        else
            ch4 = I_aud_mute           ? CH_PAUSE :
                  (I_aud_stat == 3'd4) ? CH_F     :
                  (I_aud_stat == 3'd3) ? CH_u     :
                  num_char({1'b0, I_aud_stat[1:0]});

        case (I_mode_num)

        3'd0: begin                       // P1 关闭
            ch3 = CH_DASH;  ch2 = CH_BLANK;  ch1 = CH_DASH;  ch0 = CH_BLANK;
        end

        3'd1: begin                       // P2 纯净显示
            ch3 = I_auto_on ? CH_P : CH_DASH;      // P=轮播中 / -=停止

            ch2 = I_ctrl_diag[2] ? CH_L :
                  (!I_ctrl_diag[1]) ? CH_C :
                  I_ctrl_diag[0] ? CH_t : CH_BLANK;

            ch1 = img_2dig ? num_char(img_ten) : num_char(img_one);
            ch0 = img_2dig ? num_char(img_one) : CH_BLANK;
        end

        3'd2: begin
            ch3 = num_char({1'b0, I_tran_type} + 4'd1);
            ch2 = CH_BLANK;
            ch1 = I_tran_en ? num_char(4'd1) : num_char(4'd0);
            ch0 = CH_BLANK;
        end

        3'd3: begin
            ch3 = num_char(item_disp);             // 参数项 1..6
            ch2 = val_ge100 ? num_char(v_hund) : CH_BLANK;
            ch1 = num_char(v_ten);
            ch0 = num_char(v_one);
        end

        3'd4: begin                       // P5 字幕设置
            ch3 = num_char(4'd1);   ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd5: begin                       // P6 Logo 设置
            ch3 = CH_B;             ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd6: begin                       // P7 音频可视化
            ch3 = num_char(4'd1);   ch2 = CH_BLANK;
            ch1 = num_char(v_one);  ch0 = CH_BLANK;
        end

        3'd7: begin                       // P8 release version: 8 r1.0
            ch4 = CH_BLANK;
            ch3 = CH_r;
            ch2 = 5'd23;
            ch1 = num_char(4'd0);
            ch0 = CH_BLANK;
        end

        default: begin
            ch3 = CH_DASH;  ch2 = CH_BLANK;  ch1 = CH_DASH;  ch0 = CH_BLANK;
        end
        endcase

        sd_bad = (I_sd_found == 5'd0) || I_sd_warn;

        sd_f_ten = (I_sd_found >= 5'd10) ? 4'd1 : 4'd0;
        sd_f_one = (I_sd_found >= 5'd10) ? (I_sd_found[3:0] - 4'd10)
                                         : I_sd_found[3:0];

        if (sd_bad && (I_mode_num == 3'd0 || I_mode_num == 3'd1)) begin
            ch3 = I_sd_warn ? CH_E : CH_S;   // 'E'=常量填错 / 'S'=SD 标志

            ch2 = num_char(I_vid_fsm);
            ch1 = num_char(sd_f_ten);        // 十位
            ch0 = num_char(sd_f_one);        // 个位
        end
    end

    localparam HALF_MAX = CLK_FREQ_HZ / (BLINK_HZ * 2);   // 125ms
    localparam HP_W = $clog2(HALF_MAX + 1);

    reg [HP_W-1:0] half_cnt;
    reg            blink_phase;        // 1 = 灭相

    reg [1:0] blink_cnt [5:0];         // 每位剩余闪烁次数
    reg [4:0] ch_last  [5:0];          // 每位上次的字符

    // 把合成字符装进数组便于循环
    wire [4:0] ch_now [5:0];
    assign ch_now[5] = ch5;
    assign ch_now[4] = ch4;
    assign ch_now[3] = ch3;
    assign ch_now[2] = ch2;
    assign ch_now[1] = ch1;
    assign ch_now[0] = ch0;

    integer j;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            half_cnt    <= {HP_W{1'b0}};
            blink_phase <= 1'b0;
            for (j = 0; j < 6; j = j + 1) begin
                blink_cnt[j] <= 2'd0;
                ch_last[j]   <= CH_BLANK;
            end
        end
        else begin

            if (half_cnt >= HALF_MAX[HP_W-1:0]) begin
                half_cnt <= {HP_W{1'b0}};
                if (blink_phase) begin
                    for (j = 0; j < 6; j = j + 1)
                        if (blink_cnt[j] != 2'd0)
                            blink_cnt[j] <= blink_cnt[j] - 1'b1;
                end
                blink_phase <= ~blink_phase;
            end
            else begin
                half_cnt <= half_cnt + 1'b1;
            end

            for (j = 0; j < 6; j = j + 1) begin
                if (ch_now[j] != ch_last[j]) begin
                    ch_last[j]   <= ch_now[j];
                    if ((j == 1) && (I_mode_num == 3'd1) && I_auto_on)
                        blink_cnt[j] <= 2'd0;
                    else
                        blink_cnt[j] <= 2'd3;    // 其余情况：闪 3 次
                end
            end
        end
    end

    wire [5:0] blank_mask = {
        (blink_cnt[5] != 2'd0) && blink_phase,
        (blink_cnt[4] != 2'd0) && blink_phase,
        (blink_cnt[3] != 2'd0) && blink_phase,
        (blink_cnt[2] != 2'd0) && blink_phase,
        (blink_cnt[1] != 2'd0) && blink_phase,
        (blink_cnt[0] != 2'd0) && blink_phase
    };

    always @(*) begin

        O_seg_5 = OUTPUT_TOKENS ? {3'd0,(blank_mask[5] ? CH_BLANK : ch_last[5])} : status_segments(blank_mask[5] ? CH_BLANK : ch_last[5]);
        O_seg_4 = OUTPUT_TOKENS ? {3'd0,(blank_mask[4] ? CH_BLANK : ch_last[4])} : status_segments(blank_mask[4] ? CH_BLANK : ch_last[4]);
        O_seg_3 = OUTPUT_TOKENS ? {3'd0,(blank_mask[3] ? CH_BLANK : ch_last[3])} : status_segments(blank_mask[3] ? CH_BLANK : ch_last[3]);
        O_seg_2 = OUTPUT_TOKENS ? {3'd0,(blank_mask[2] ? CH_BLANK : ch_last[2])} : status_segments(blank_mask[2] ? CH_BLANK : ch_last[2]);
        O_seg_1 = OUTPUT_TOKENS ? {3'd0,(blank_mask[1] ? CH_BLANK : ch_last[1])} : status_segments(blank_mask[1] ? CH_BLANK : ch_last[1]);
        O_seg_0 = OUTPUT_TOKENS ? {3'd0,(blank_mask[0] ? CH_BLANK : ch_last[0])} : status_segments(blank_mask[0] ? CH_BLANK : ch_last[0]);
    end

endmodule
