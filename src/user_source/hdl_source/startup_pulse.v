module startup_pulse #(
    parameter [19:0] CNT_MAX = 20'd100000
)(
    input  wire I_clk,
    input  wire I_rst,
    output reg  O_pulse
);

reg [19:0] S_cnt;
reg        S_done;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        S_cnt   <= 20'd0;
        S_done  <= 1'b0;
        O_pulse <= 1'b0;
    end
    else begin
        O_pulse <= 1'b0;

        if (!S_done) begin
            if (S_cnt == CNT_MAX - 1'b1) begin
                S_cnt   <= S_cnt;
                S_done  <= 1'b1;
                O_pulse <= 1'b1;
            end
            else begin
                S_cnt <= S_cnt + 1'b1;
            end
        end
    end
end

endmodule

module touch_xpt2046 #(
    parameter CLK_HZ=50000000, parameter SPI_HZ=1000000,
    parameter SAMPLE_HZ=100
)(
    input wire clk,rst_n,irq_n,miso,
    output wire sck,mosi,
    output reg cs_n,
    output reg sample,down,
    output reg [11:0] raw_x,raw_y
);
    reg [1:0] irq_sync,do_sync;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin irq_sync<=3;do_sync<=0;end
        else begin irq_sync<={irq_sync[0],irq_n};do_sync<={do_sync[0],miso};end
    reg send;
    reg [7:0] tx,hi;
    wire ready,done;
    wire [7:0] rx;
    touch_spi_byte #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ)) spi(
        clk,rst_n,send,tx,do_sync[1],ready,sck,mosi,done,rx);
    reg [$clog2(CLK_HZ/SAMPLE_HZ)-1:0] period;
    reg [$clog2(CLK_HZ/1000000*6+1)-1:0] wait_count;
    reg [3:0] state;
    reg [2:0] conversion;
    reg [11:0] x0,x1,y0,y1,mx,my;
    reg valid_last,release_last;
    function [11:0] median;
        input [11:0] a,b,c;
        begin median=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));end
    endfunction
    wire [11:0] result={hi[6:0],rx[7:3]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cs_n<=1;send<=0;tx<=0;hi<=0;state<=0;period<=0;wait_count<=0;
            conversion<=0;sample<=0;down<=0;raw_x<=0;raw_y<=0;
            x0<=0;x1<=0;y0<=0;y1<=0;mx<=0;my<=0;valid_last<=0;release_last<=0;
        end else begin
            send<=0;sample<=0;
            if(period!=0) period<=period-1'b1;
            case(state)
            0: if(period==0) begin
                period<=CLK_HZ/SAMPLE_HZ-1;
                if(!irq_sync[1]) begin conversion<=0;state<=1;release_last<=0;end
                else begin
                    valid_last<=0;release_last<=1;
                    if(release_last) begin down<=0;sample<=1;end
                end
            end

            1: begin cs_n<=0;tx<=conversion<4 ? 8'hD0 : 8'h90;send<=1;state<=2;end
            2: if(done) begin wait_count<=CLK_HZ/1000000*6;state<=3;end
            3: if(wait_count!=0) wait_count<=wait_count-1'b1;
               else begin tx<=0;send<=1;state<=4;end
            4: if(done) begin hi<=rx;tx<=0;send<=1;state<=5;end
            5: if(done) begin
                cs_n<=1;
                case(conversion)
                1:x0<=result;2:x1<=result;3:mx<=median(x0,x1,result);
                5:y0<=result;6:y1<=result;7:my<=median(y0,y1,result);
                default:;
                endcase
                if(conversion==7) begin wait_count<=CLK_HZ/1000000*6;state<=7;end
                else begin conversion<=conversion+1'b1;state<=6;end
            end
            6: state<=1;

            7: if(wait_count!=0) wait_count<=wait_count-1'b1;
               else begin
                   if(!irq_sync[1] && mx>32 && mx<4063 && my>32 && my<4063) begin
                       raw_x<=mx;raw_y<=my;valid_last<=1;
                       if(valid_last) begin sample<=1;down<=1;end
                   end else valid_last<=0;
                   state<=0;
               end
            default:state<=0;
            endcase
        end
    end
endmodule

module touch_spi_byte #(
    parameter CLK_HZ=50000000, parameter SPI_HZ=10000000
)(
    input wire clk, rst_n, valid,
    input wire [7:0] data,
    input wire miso,
    output wire ready,
    output reg sck, mosi, done,
    output reg [7:0] received
);
    reg busy;

    function integer gcd;input integer a,b;integer t;begin
        while(b!=0)begin t=a%b;a=b;b=t;end gcd=a;
    end endfunction
    localparam UNIT=gcd(CLK_HZ,2*SPI_HZ);
    localparam MODULUS=CLK_HZ/UNIT, INCREMENT=2*SPI_HZ/UNIT;
    localparam PHASE_BITS=MODULUS<2?1:$clog2(MODULUS);
    reg [PHASE_BITS-1:0] phase;
    reg [2:0] bit_no;
    reg [7:0] tx, rx;
    assign ready = !busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0; phase<=0; bit_no<=7; tx<=0; rx<=0;
            sck<=0; mosi<=0; done<=0; received<=0;
        end else begin
            done<=0;
            if(!busy) begin
                sck<=0;
                if(valid) begin
                    busy<=1; phase<=0; tx<=data; mosi<=data[7]; bit_no<=7;
                end
            end else if(phase >= MODULUS-INCREMENT) begin
                phase<=phase-(MODULUS-INCREMENT);
                sck<=!sck;
                if(!sck) rx<={rx[6:0],miso};
                else if(bit_no==0) begin
                    busy<=0; done<=1; received<=rx;
                end else begin
                    bit_no<=bit_no-1'b1; tx<={tx[6:0],1'b0}; mosi<=tx[6];
                end
            end else phase<=phase+INCREMENT;
        end
    end
endmodule

module touch_calibrate #(
    parameter DEFAULT_SWAP=0,
    parameter DEFAULT_X0=200, DEFAULT_Y0=200,
    parameter DEFAULT_X_GAIN=8484, DEFAULT_Y_GAIN=5650
)(
    input wire clk,rst_n,enabled,start,
    input wire raw_sample,raw_down,
    input wire [11:0] raw_x,raw_y,
    output reg sample,down,
    output reg [8:0] x,y,
    output reg [2:0] step,
    output reg failed
);
    reg swap,old_swap;
    reg signed [12:0] origin_x,origin_y,old_x,old_y;

    reg signed [16:0] gain_x,gain_y,old_gx,old_gy;
    reg [11:0] cx[0:3],cy[0:3];
    reg [11:0] last_x,last_y;
    reg held;
    reg [2:0] state;
    reg [24:0] dividend,quotient;
    reg [12:0] divisor,range_x,range_y;
    reg [13:0] remainder;
    reg [5:0] count;
    reg negative_x,negative_y;
    reg signed [12:0] left_x,right_x,top_y,bottom_y;
    reg signed [29:0] product_x,product_y;
    reg [1:0] valid_pipe,down_pipe;
    wire signed [12:0] mapped_raw_x=$signed({1'b0,swap?raw_y:raw_x});
    wire signed [12:0] mapped_raw_y=$signed({1'b0,swap?raw_x:raw_y});
    wire signed [14:0] px=$signed(product_x[29:16])+15'sd32;
    wire signed [14:0] py=$signed(product_y[29:16])+15'sd32;
    wire [13:0] shifted_rem={remainder[12:0],dividend[24]};
    function [12:0] distance;input [11:0] a,b;begin distance=a>b?a-b:b-a;end endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            swap<=DEFAULT_SWAP;origin_x<=DEFAULT_X0;origin_y<=DEFAULT_Y0;
            gain_x<=DEFAULT_X_GAIN;gain_y<=DEFAULT_Y_GAIN;
            old_swap<=DEFAULT_SWAP;old_x<=DEFAULT_X0;old_y<=DEFAULT_Y0;
            old_gx<=DEFAULT_X_GAIN;old_gy<=DEFAULT_Y_GAIN;
            sample<=0;down<=0;x<=0;y<=0;step<=0;failed<=0;held<=0;
            state<=0;last_x<=0;last_y<=0;dividend<=0;quotient<=0;divisor<=1;
            range_x<=1;range_y<=1;remainder<=0;count<=0;negative_x<=0;negative_y<=0;
            left_x<=0;right_x<=0;top_y<=0;bottom_y<=0;
            product_x<=0;product_y<=0;valid_pipe<=0;down_pipe<=0;
        end else begin
            valid_pipe<={valid_pipe[0],raw_sample};down_pipe<={down_pipe[0],raw_down};
            if(raw_sample) begin
                product_x<=(mapped_raw_x-origin_x)*gain_x;
                product_y<=(mapped_raw_y-origin_y)*gain_y;
            end
            if(valid_pipe[0]) begin
                x<=px<0?9'd0:(px>479?9'd479:px[8:0]);
                y<=py<0?9'd0:(py>319?9'd319:py[8:0]);
            end
            sample<=valid_pipe[1];down<=down_pipe[1];
            if(!enabled && step!=0) begin
                step<=0;state<=0;held<=0;
                swap<=old_swap;origin_x<=old_x;origin_y<=old_y;gain_x<=old_gx;gain_y<=old_gy;
            end else if(start && step==0) begin
                old_swap<=swap;old_x<=origin_x;old_y<=origin_y;old_gx<=gain_x;old_gy<=gain_y;
                step<=1;failed<=0;held<=0;state<=0;
            end else if(step!=0) begin
                if(raw_sample && state==0) begin
                    if(raw_down) begin held<=1;last_x<=raw_x;last_y<=raw_y;end
                    else if(held) begin
                        held<=0;
                        if(step<5) begin
                            cx[step-1]<=last_x;cy[step-1]<=last_y;
                            if(step==4) state<=1;
                            else step<=step+1'b1;
                        end else begin
                            if(x>=220 && x<=260 && y>=140 && y<=180) begin step<=0;failed<=0;end
                            else begin
                                failed<=1;step<=1;
                                swap<=old_swap;origin_x<=old_x;origin_y<=old_y;gain_x<=old_gx;gain_y<=old_gy;
                            end
                        end
                    end
                end
                case(state)
                1: begin
                    swap<=distance(cx[0],cx[1])<distance(cy[0],cy[1]);state<=2;
                end
                2: begin
                    left_x<=swap?({1'b0,cy[0]}+{1'b0,cy[3]})>>1:({1'b0,cx[0]}+{1'b0,cx[3]})>>1;
                    right_x<=swap?({1'b0,cy[1]}+{1'b0,cy[2]})>>1:({1'b0,cx[1]}+{1'b0,cx[2]})>>1;
                    top_y<=swap?({1'b0,cx[0]}+{1'b0,cx[1]})>>1:({1'b0,cy[0]}+{1'b0,cy[1]})>>1;
                    bottom_y<=swap?({1'b0,cx[2]}+{1'b0,cx[3]})>>1:({1'b0,cy[2]}+{1'b0,cy[3]})>>1;
                    state<=3;
                end
                3: begin
                    origin_x<=left_x;origin_y<=top_y;
                    negative_x<=right_x<left_x;negative_y<=bottom_y<top_y;
                    range_x<=right_x<left_x?left_x-right_x:right_x-left_x;
                    range_y<=bottom_y<top_y?top_y-bottom_y:bottom_y-top_y;
                    state<=4;
                end
                4: begin
                    if(range_x<512 || range_y<512) begin failed<=1;step<=1;state<=0;end
                    else begin
                        dividend<=25'd27197440;divisor<=range_x; // 415 << 16
                        quotient<=0;remainder<=0;count<=25;state<=5;
                    end
                end
                5,7: begin
                    dividend<={dividend[23:0],1'b0};
                    if(shifted_rem>=divisor) begin
                        remainder<=shifted_rem-divisor;quotient<={quotient[23:0],1'b1};
                    end else begin remainder<=shifted_rem;quotient<={quotient[23:0],1'b0};end
                    count<=count-1'b1;
                    if(count==1) state<=state==5?6:0;
                    if(count==1 && state==7) begin
                        gain_y<=negative_y?-$signed({1'b0,quotient[14:0],shifted_rem>=divisor}):
                                                 $signed({1'b0,quotient[14:0],shifted_rem>=divisor});
                        step<=5;
                    end
                end
                6: begin
                    gain_x<=negative_x?-$signed(quotient[16:0]):$signed(quotient[16:0]);
                    dividend<=25'd16711680;divisor<=range_y; // 255 << 16
                    quotient<=0;remainder<=0;count<=25;state<=7;
                end
                default:;
                endcase
            end
        end
    end
endmodule

module touch_gesture #(
    parameter MAX_SCROLL=1176
)(
    input wire clk, rst_n, enabled, sample, down, settled, allow_scroll,
    input wire [8:0] x,y,
    input wire [7:0] hit,
    output reg [10:0] scroll,
    output reg click,
    output reg [7:0] clicked,
    output reg dragging,
    output reg [7:0] pressed,
    input wire numeric_hit,
    output reg slider_update,
    output reg [7:0] slider_id,
    output reg [8:0] slider_x,
    input wire accept_start
);
    reg active, eligible, scrollable;
    reg [8:0] start_x,start_y;
    reg [10:0] start_scroll;
    reg numeric_start;
    reg [1:0] direction;
    wire [8:0] dx=x>start_x?x-start_x:start_x-x;
    wire [8:0] dy=y>start_y?y-start_y:start_y-y;
    wire horizontal=direction==2 || (direction==0 && numeric_start && dx>8 && dx>=dy);
    wire moved = (x>start_x ? x-start_x : start_x-x)>9'd8 ||
                 (y>start_y ? y-start_y : start_y-y)>9'd8;
    wire signed [12:0] wanted = $signed({2'b0,start_scroll}) +
        $signed({4'b0,start_y}) - $signed({4'b0,y});
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scroll<=0; click<=0; clicked<=255; dragging<=0; pressed<=255;
            active<=0; eligible<=0; scrollable<=0; start_x<=0;start_y<=0;start_scroll<=0;
            numeric_start<=0;direction<=0;slider_update<=0;slider_id<=255;slider_x<=0;
        end else begin
            click<=0;slider_update<=0;
            if(!enabled) begin active<=0; dragging<=0; pressed<=255; eligible<=0; end
            else if(sample) begin
                if(down && !active) begin
                    active<=1; eligible<=settled && accept_start; pressed<=hit;
                    start_x<=x; start_y<=y; start_scroll<=scroll;
                    scrollable<=allow_scroll && y>=32 && y<296; dragging<=0;
                    numeric_start<=numeric_hit;direction<=0;
                end else if(active) begin
                    if(direction==0 && moved) direction<=horizontal?2:1;
                    if(numeric_start && eligible && settled &&
                       (horizontal || (!down && !dragging && !moved && hit==pressed))) begin
                        slider_update<=1;slider_id<=pressed;slider_x<=x;
                    end
                    if(down) begin
                        if(moved) dragging<=1;
                    end else begin
                        if((dragging || moved) && scrollable && !horizontal) begin
                            if(wanted<0) scroll<=0;
                            else if(wanted>MAX_SCROLL) scroll<=MAX_SCROLL;
                            else scroll<=wanted[10:0];
                        end
                        if(!numeric_start && !dragging && !moved && eligible && settled && hit==pressed && hit!=255) begin
                            click<=1; clicked<=hit;
                        end
                        active<=0; dragging<=0; pressed<=255;
                    end
                end
            end
        end
    end
endmodule

module touch_ili9488 #(
    parameter CLK_HZ=50000000, SPI_HZ=10000000,
    parameter RESET_CYCLES=CLK_HZ/10, RECOVER_CYCLES=CLK_HZ/20,
    parameter SLEEP_CYCLES=CLK_HZ*12/100
)(
    input wire clk,rst_n,
    input wire [10:0] requested_scroll,
    input wire [15:0] revision,
    input wire [8:0] dirty_first,dirty_last,
    input wire [23:0] rgb,
    output reg [8:0] x,y,
    output reg [10:0] draw_scroll,
    output reg begin_frame,
    output wire settled,
    output reg initialized,
    output reg cs_n,reset_n,dc,
    output wire mosi,sck,
    output wire geometry_settled
);
    reg send;
    reg [7:0] tx;
    wire ready,done;
    wire [7:0] unused_rx;
    touch_spi_byte #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ)) spi(
        clk,rst_n,send,tx,1'b0,ready,sck,mosi,done,unused_rx);
    reg [4:0] state;
    localparam MAX_WAIT=RESET_CYCLES>RECOVER_CYCLES ?
        (RESET_CYCLES>SLEEP_CYCLES?RESET_CYCLES:SLEEP_CYCLES) :
        (RECOVER_CYCLES>SLEEP_CYCLES?RECOVER_CYCLES:SLEEP_CYCLES);
    reg [$clog2(MAX_WAIT+1)-1:0] wait_count;
    reg [6:0] init_index;
    reg [3:0] window_index;
    reg [8:0] stripe_end,draw_end;
    reg [1:0] component;

    reg [2:0] pixel_wait;
    reg [23:0] pixel;
    reg [15:0] painting_revision,drawn_revision;
    reg first_frame;
    reg geometry_busy;
    function [8:0] init_byte;
        input [6:0] a;
        begin case(a)
        0:init_byte=9'h0f7;1:init_byte=9'h1a9;2:init_byte=9'h151;
        3:init_byte=9'h12c;4:init_byte=9'h182;5:init_byte=9'h0c0;
        6:init_byte=9'h111;7:init_byte=9'h109;8:init_byte=9'h0c1;
        9:init_byte=9'h141;10:init_byte=9'h0c5;11:init_byte=9'h100;
        12:init_byte=9'h10a;13:init_byte=9'h180;14:init_byte=9'h0b1;
        15:init_byte=9'h1b0;16:init_byte=9'h111;17:init_byte=9'h0b4;
        18:init_byte=9'h102;19:init_byte=9'h0b6;20:init_byte=9'h102;
        21:init_byte=9'h142;22:init_byte=9'h0b7;23:init_byte=9'h1c6;
        24:init_byte=9'h0be;25:init_byte=9'h100;26:init_byte=9'h104;
        27:init_byte=9'h0e9;28:init_byte=9'h100;29:init_byte=9'h036;
        30:init_byte=9'h168;31:init_byte=9'h03a;32:init_byte=9'h166;
        33:init_byte=9'h0e0;34:init_byte=9'h100;35:init_byte=9'h107;
        36:init_byte=9'h110;37:init_byte=9'h109;38:init_byte=9'h117;
        39:init_byte=9'h10b;40:init_byte=9'h141;41:init_byte=9'h189;
        42:init_byte=9'h14b;43:init_byte=9'h10a;44:init_byte=9'h10c;
        45:init_byte=9'h10e;46:init_byte=9'h118;47:init_byte=9'h11b;
        48:init_byte=9'h10f;49:init_byte=9'h0e1;50:init_byte=9'h100;
        51:init_byte=9'h117;52:init_byte=9'h11a;53:init_byte=9'h104;
        54:init_byte=9'h10e;55:init_byte=9'h106;56:init_byte=9'h12f;
        57:init_byte=9'h145;58:init_byte=9'h143;59:init_byte=9'h102;
        60:init_byte=9'h10a;61:init_byte=9'h109;62:init_byte=9'h132;
        63:init_byte=9'h136;64:init_byte=9'h10f;65:init_byte=9'h011;
        66:init_byte=9'h029;
        default:init_byte=9'h029;
        endcase end
    endfunction
    wire [8:0] ib=init_byte(init_index);
    assign settled=initialized && !first_frame && state==6 &&
        draw_scroll==requested_scroll && drawn_revision==revision;

    assign geometry_settled=initialized && !first_frame && !geometry_busy && draw_scroll==requested_scroll;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0;wait_count<=RESET_CYCLES;init_index<=0;send<=0;tx<=0;
            cs_n<=1;reset_n<=0;dc<=0;initialized<=0;begin_frame<=0;
            x<=0;y<=0;draw_scroll<=0;window_index<=0;stripe_end<=7;draw_end<=319;
            component<=0;pixel_wait<=0;pixel<=0;painting_revision<=0;
            drawn_revision<=0;first_frame<=1;geometry_busy<=1;
        end else begin
            send<=0;begin_frame<=0;
            case(state)
            0: if(wait_count!=0) wait_count<=wait_count-1'b1;
               else begin reset_n<=1;wait_count<=RECOVER_CYCLES;state<=1;end
            1: if(wait_count!=0) wait_count<=wait_count-1'b1;
               else begin cs_n<=0;state<=2;end
            2: begin dc<=ib[8];tx<=ib[7:0];send<=1;state<=3;end
            3: if(done) begin
                if(init_index==65) begin wait_count<=SLEEP_CYCLES;state<=4;end
                else if(init_index==66) begin cs_n<=1;initialized<=1;state<=6;end
                else begin init_index<=init_index+1'b1;state<=2;end
            end
            4: if(wait_count!=0) wait_count<=wait_count-1'b1;
               else begin init_index<=66;state<=2;end
            6: if(first_frame || requested_scroll!=draw_scroll || revision!=drawn_revision) begin
                geometry_busy<=first_frame || requested_scroll!=draw_scroll ||
                    (dirty_first==0 && dirty_last==319);
                draw_scroll<=requested_scroll;painting_revision<=revision;begin_frame<=1;
                if(!first_frame && revision==drawn_revision) begin y<=32;stripe_end<=39;draw_end<=295;end
                else if(!first_frame && requested_scroll==draw_scroll && dirty_first<=dirty_last) begin
                    y<={dirty_first[8:3],3'b000};stripe_end<={dirty_first[8:3],3'b111};
                    draw_end<={dirty_last[8:3],3'b111};
                end else begin y<=0;stripe_end<=7;draw_end<=319;end
                x<=0;window_index<=0;state<=7;
            end
            7: begin
                cs_n<=0;send<=1;dc<=1;
                case(window_index)
                0:begin tx<=8'h2a;dc<=0;end
                1:tx<=0;2:tx<=0;3:tx<=1;4:tx<=8'hdf;
                5:begin tx<=8'h2b;dc<=0;end
                6:tx<={7'd0,y[8]};7:tx<=y[7:0];
                8:tx<={7'd0,stripe_end[8]};9:tx<=stripe_end[7:0];
                10:begin tx<=8'h2c;dc<=0;end
                default:tx<=0;
                endcase
                state<=8;
            end
            8: if(done) begin
                if(window_index==10) begin pixel_wait<=6;state<=9;end
                else begin window_index<=window_index+1'b1;state<=7;end
            end
            9: if(pixel_wait!=0) pixel_wait<=pixel_wait-1'b1;
               else begin pixel<=rgb;component<=0;state<=10;end
            10: begin
                dc<=1;send<=1;state<=11;
                case(component)
                0:tx<={pixel[23:18],2'b0};1:tx<={pixel[15:10],2'b0};
                2:tx<={pixel[7:2],2'b0};default:tx<=0;
                endcase
            end
            11: if(done) begin
                if(component!=2) begin component<=component+1'b1;state<=10;end
                else if(x!=479) begin x<=x+1'b1;pixel_wait<=6;state<=9;end
                else if(y!=stripe_end) begin x<=0;y<=y+1'b1;pixel_wait<=6;state<=9;end
                else begin
                    cs_n<=1;x<=0;
                    if(y==draw_end) begin drawn_revision<=painting_revision;first_frame<=0;geometry_busy<=0;state<=6;end
                    else begin y<=y+1'b1;stripe_end<=stripe_end+9'd8;window_index<=0;state<=7;end
                end
            end
            default:state<=0;
            endcase
        end
    end
endmodule

module touch_font_rom(input wire ref_clk, input wire [10:0] ref_addr,
 output reg [15:0] ref_bits, input wire pixel_clk, input wire [10:0] pixel_addr,
 output reg [15:0] pixel_bits);
reg [15:0] mem[0:2047];
initial begin
mem[0]=16'h0000;
mem[1]=16'h0000;
mem[2]=16'h0000;
mem[3]=16'h0000;
mem[4]=16'h0000;
mem[5]=16'h0000;
mem[6]=16'h0000;
mem[7]=16'h0000;
mem[8]=16'h0000;
mem[9]=16'h0000;
mem[10]=16'h0000;
mem[11]=16'h0000;
mem[12]=16'h0000;
mem[13]=16'h0000;
mem[14]=16'h0000;
mem[15]=16'h0000;
mem[16]=16'h0000;
mem[17]=16'h0000;
mem[18]=16'h3ffc;
mem[19]=16'h0000;
mem[20]=16'h07f0;
mem[21]=16'h0db0;
mem[22]=16'h6db6;
mem[23]=16'h6ff6;
mem[24]=16'h6db6;
mem[25]=16'h6db6;
mem[26]=16'h6db6;
mem[27]=16'h67f6;
mem[28]=16'h6006;
mem[29]=16'h7ffe;
mem[30]=16'h0006;
mem[31]=16'h0000;
mem[32]=16'h0000;
mem[33]=16'h0000;
mem[34]=16'h7ffe;
mem[35]=16'h0100;
mem[36]=16'h0300;
mem[37]=16'h3ffc;
mem[38]=16'h2644;
mem[39]=16'h2644;
mem[40]=16'h27c4;
mem[41]=16'h2644;
mem[42]=16'h27c4;
mem[43]=16'h2644;
mem[44]=16'h2644;
mem[45]=16'h3ffc;
mem[46]=16'h200c;
mem[47]=16'h0000;
mem[48]=16'h0000;
mem[49]=16'h0080;
mem[50]=16'h3ffe;
mem[51]=16'h0080;
mem[52]=16'h0180;
mem[53]=16'h1ffc;
mem[54]=16'h0000;
mem[55]=16'h1ffc;
mem[56]=16'h108c;
mem[57]=16'h108c;
mem[58]=16'h1ffc;
mem[59]=16'h100c;
mem[60]=16'h3000;
mem[61]=16'h2000;
mem[62]=16'h6000;
mem[63]=16'h0000;
mem[64]=16'h0000;
mem[65]=16'h0100;
mem[66]=16'h3ffc;
mem[67]=16'h0420;
mem[68]=16'h0c30;
mem[69]=16'h0420;
mem[70]=16'h7ffe;
mem[71]=16'h0000;
mem[72]=16'h0ff0;
mem[73]=16'h1ff8;
mem[74]=16'h1818;
mem[75]=16'h1ff8;
mem[76]=16'h1818;
mem[77]=16'h1ff8;
mem[78]=16'h1818;
mem[79]=16'h0000;
mem[80]=16'h0000;
mem[81]=16'h0180;
mem[82]=16'h3ffe;
mem[83]=16'h0000;
mem[84]=16'h0ff0;
mem[85]=16'h0810;
mem[86]=16'h0ff0;
mem[87]=16'h0000;
mem[88]=16'h7ffe;
mem[89]=16'h6006;
mem[90]=16'h47c2;
mem[91]=16'h0660;
mem[92]=16'h0460;
mem[93]=16'h0c62;
mem[94]=16'h383e;
mem[95]=16'h0000;
mem[96]=16'h0000;
mem[97]=16'h0080;
mem[98]=16'h1ffc;
mem[99]=16'h3010;
mem[100]=16'h2210;
mem[101]=16'h2ffc;
mem[102]=16'h2330;
mem[103]=16'h2210;
mem[104]=16'h23f0;
mem[105]=16'h2000;
mem[106]=16'h27f0;
mem[107]=16'h2130;
mem[108]=16'h21e0;
mem[109]=16'h41e0;
mem[110]=16'h4f3e;
mem[111]=16'h0000;
mem[112]=16'h0000;
mem[113]=16'h0008;
mem[114]=16'h0008;
mem[115]=16'h7e08;
mem[116]=16'h020c;
mem[117]=16'h02fe;
mem[118]=16'h2408;
mem[119]=16'h3488;
mem[120]=16'h1c88;
mem[121]=16'h0c48;
mem[122]=16'h0c48;
mem[123]=16'h1208;
mem[124]=16'h3308;
mem[125]=16'h6008;
mem[126]=16'h0038;
mem[127]=16'h0000;
mem[128]=16'h0000;
mem[129]=16'h2080;
mem[130]=16'h2080;
mem[131]=16'h2080;
mem[132]=16'h208c;
mem[133]=16'h2098;
mem[134]=16'h3ee0;
mem[135]=16'h20c0;
mem[136]=16'h2080;
mem[137]=16'h2080;
mem[138]=16'h2080;
mem[139]=16'h2680;
mem[140]=16'h3c86;
mem[141]=16'h30fe;
mem[142]=16'h007c;
mem[143]=16'h0000;
mem[144]=16'h0000;
mem[145]=16'h1040;
mem[146]=16'h30c0;
mem[147]=16'h3cfe;
mem[148]=16'h2586;
mem[149]=16'h4504;
mem[150]=16'h43f4;
mem[151]=16'h3194;
mem[152]=16'h3194;
mem[153]=16'h31f4;
mem[154]=16'h318c;
mem[155]=16'h3d88;
mem[156]=16'h3980;
mem[157]=16'h3182;
mem[158]=16'h00fc;
mem[159]=16'h0000;
mem[160]=16'h0000;
mem[161]=16'h0000;
mem[162]=16'h3f00;
mem[163]=16'h0c7e;
mem[164]=16'h0c66;
mem[165]=16'h0c46;
mem[166]=16'h7f46;
mem[167]=16'h0c46;
mem[168]=16'h1e46;
mem[169]=16'h1d46;
mem[170]=16'h3d46;
mem[171]=16'h6c7e;
mem[172]=16'h4c66;
mem[173]=16'h0c42;
mem[174]=16'h0c00;
mem[175]=16'h0000;
mem[176]=16'h0000;
mem[177]=16'h1ff8;
mem[178]=16'h1008;
mem[179]=16'h1ff8;
mem[180]=16'h1ff8;
mem[181]=16'h0000;
mem[182]=16'h7ffe;
mem[183]=16'h1ff8;
mem[184]=16'h1188;
mem[185]=16'h1ff8;
mem[186]=16'h1998;
mem[187]=16'h0180;
mem[188]=16'h1ff8;
mem[189]=16'h0180;
mem[190]=16'h7ffe;
mem[191]=16'h0000;
mem[192]=16'h0000;
mem[193]=16'h101c;
mem[194]=16'h13f8;
mem[195]=16'h112c;
mem[196]=16'h7928;
mem[197]=16'h17fe;
mem[198]=16'h10f8;
mem[199]=16'h192c;
mem[200]=16'h3f26;
mem[201]=16'h57fc;
mem[202]=16'h1324;
mem[203]=16'h13fc;
mem[204]=16'h1324;
mem[205]=16'h13fc;
mem[206]=16'h730c;
mem[207]=16'h0000;
mem[208]=16'h0000;
mem[209]=16'h1020;
mem[210]=16'h0860;
mem[211]=16'h0040;
mem[212]=16'h7f7e;
mem[213]=16'h10cc;
mem[214]=16'h10cc;
mem[215]=16'h1fc8;
mem[216]=16'h1268;
mem[217]=16'h1228;
mem[218]=16'h1238;
mem[219]=16'h2230;
mem[220]=16'h2238;
mem[221]=16'h666c;
mem[222]=16'h4586;
mem[223]=16'h0000;
mem[224]=16'h0000;
mem[225]=16'h1020;
mem[226]=16'h1020;
mem[227]=16'h7dfc;
mem[228]=16'h2060;
mem[229]=16'h2840;
mem[230]=16'h69fe;
mem[231]=16'h6840;
mem[232]=16'h7cc0;
mem[233]=16'h08fc;
mem[234]=16'h0e08;
mem[235]=16'h7c18;
mem[236]=16'h08f0;
mem[237]=16'h0830;
mem[238]=16'h0818;
mem[239]=16'h0000;
mem[240]=16'h0000;
mem[241]=16'h11fc;
mem[242]=16'h1018;
mem[243]=16'h1030;
mem[244]=16'h1060;
mem[245]=16'h7cc0;
mem[246]=16'h11fe;
mem[247]=16'h1052;
mem[248]=16'h10d2;
mem[249]=16'h1092;
mem[250]=16'h1db2;
mem[251]=16'h3f26;
mem[252]=16'h6066;
mem[253]=16'h00c6;
mem[254]=16'h018c;
mem[255]=16'h0000;
mem[256]=16'h0000;
mem[257]=16'h0100;
mem[258]=16'h0100;
mem[259]=16'h0100;
mem[260]=16'h0100;
mem[261]=16'h0100;
mem[262]=16'h01fc;
mem[263]=16'h0100;
mem[264]=16'h0100;
mem[265]=16'h0100;
mem[266]=16'h0100;
mem[267]=16'h0100;
mem[268]=16'h0100;
mem[269]=16'h7ffe;
mem[270]=16'h0000;
mem[271]=16'h0000;
mem[272]=16'h0000;
mem[273]=16'h0000;
mem[274]=16'h0000;
mem[275]=16'h0000;
mem[276]=16'h0000;
mem[277]=16'h0000;
mem[278]=16'h0000;
mem[279]=16'h7ffe;
mem[280]=16'h7ffe;
mem[281]=16'h0000;
mem[282]=16'h0000;
mem[283]=16'h0000;
mem[284]=16'h0000;
mem[285]=16'h0000;
mem[286]=16'h0000;
mem[287]=16'h0000;
mem[288]=16'h0000;
mem[289]=16'h0080;
mem[290]=16'h7c8c;
mem[291]=16'h0498;
mem[292]=16'h0490;
mem[293]=16'h3ca0;
mem[294]=16'h6080;
mem[295]=16'h63fe;
mem[296]=16'h60b0;
mem[297]=16'h3c90;
mem[298]=16'h0490;
mem[299]=16'h0498;
mem[300]=16'h04ac;
mem[301]=16'h0ce6;
mem[302]=16'h1882;
mem[303]=16'h0000;
mem[304]=16'h0000;
mem[305]=16'h0000;
mem[306]=16'h7ffe;
mem[307]=16'h0100;
mem[308]=16'h0100;
mem[309]=16'h0100;
mem[310]=16'h0100;
mem[311]=16'h0160;
mem[312]=16'h0130;
mem[313]=16'h0118;
mem[314]=16'h010c;
mem[315]=16'h0100;
mem[316]=16'h0100;
mem[317]=16'h0100;
mem[318]=16'h0100;
mem[319]=16'h0000;
mem[320]=16'h0000;
mem[321]=16'h1820;
mem[322]=16'h1060;
mem[323]=16'h7e50;
mem[324]=16'h3088;
mem[325]=16'h2186;
mem[326]=16'h2902;
mem[327]=16'h6c80;
mem[328]=16'h7e8c;
mem[329]=16'h08f0;
mem[330]=16'h0cc0;
mem[331]=16'h7e80;
mem[332]=16'h0880;
mem[333]=16'h08c6;
mem[334]=16'h087c;
mem[335]=16'h0000;
mem[336]=16'h0000;
mem[337]=16'h080c;
mem[338]=16'h3f70;
mem[339]=16'h1040;
mem[340]=16'h347c;
mem[341]=16'h3f58;
mem[342]=16'h0458;
mem[343]=16'h7c98;
mem[344]=16'h0480;
mem[345]=16'h1ff0;
mem[346]=16'h1018;
mem[347]=16'h1ff8;
mem[348]=16'h1018;
mem[349]=16'h1ff8;
mem[350]=16'h1018;
mem[351]=16'h0000;
mem[352]=16'h0000;
mem[353]=16'h1860;
mem[354]=16'h17fe;
mem[355]=16'h3000;
mem[356]=16'h33f8;
mem[357]=16'h7208;
mem[358]=16'h73f8;
mem[359]=16'h5000;
mem[360]=16'h17fe;
mem[361]=16'h1402;
mem[362]=16'h13fc;
mem[363]=16'h1020;
mem[364]=16'h1020;
mem[365]=16'h1020;
mem[366]=16'h10e0;
mem[367]=16'h0000;
mem[368]=16'h0000;
mem[369]=16'h0888;
mem[370]=16'h0c90;
mem[371]=16'h04a0;
mem[372]=16'h3ffe;
mem[373]=16'h03a0;
mem[374]=16'h06b0;
mem[375]=16'h188c;
mem[376]=16'h3084;
mem[377]=16'h0080;
mem[378]=16'h7ffe;
mem[379]=16'h01c0;
mem[380]=16'h0360;
mem[381]=16'h0e38;
mem[382]=16'h380e;
mem[383]=16'h0000;
mem[384]=16'h0000;
mem[385]=16'h0004;
mem[386]=16'h3fa4;
mem[387]=16'h0924;
mem[388]=16'h0924;
mem[389]=16'h7fa4;
mem[390]=16'h1b24;
mem[391]=16'h1124;
mem[392]=16'h310c;
mem[393]=16'h610c;
mem[394]=16'h0180;
mem[395]=16'h1ffc;
mem[396]=16'h0180;
mem[397]=16'h0180;
mem[398]=16'h7ffe;
mem[399]=16'h0000;
mem[400]=16'h0000;
mem[401]=16'h3ffc;
mem[402]=16'h3ffc;
mem[403]=16'h0620;
mem[404]=16'h0620;
mem[405]=16'h0620;
mem[406]=16'h0620;
mem[407]=16'h7ffe;
mem[408]=16'h0620;
mem[409]=16'h0620;
mem[410]=16'h0420;
mem[411]=16'h0c20;
mem[412]=16'h0820;
mem[413]=16'h3820;
mem[414]=16'h3020;
mem[415]=16'h0000;
mem[416]=16'h0000;
mem[417]=16'h0420;
mem[418]=16'h0420;
mem[419]=16'h0260;
mem[420]=16'h3ffc;
mem[421]=16'h0180;
mem[422]=16'h0180;
mem[423]=16'h0180;
mem[424]=16'h3ffc;
mem[425]=16'h0180;
mem[426]=16'h01c0;
mem[427]=16'h0360;
mem[428]=16'h0630;
mem[429]=16'h181c;
mem[430]=16'h3004;
mem[431]=16'h0000;
mem[432]=16'h0000;
mem[433]=16'h0100;
mem[434]=16'h0180;
mem[435]=16'h3ffe;
mem[436]=16'h2006;
mem[437]=16'h0ff0;
mem[438]=16'h0ff0;
mem[439]=16'h0060;
mem[440]=16'h0080;
mem[441]=16'h3ffe;
mem[442]=16'h3ffe;
mem[443]=16'h0080;
mem[444]=16'h0080;
mem[445]=16'h0080;
mem[446]=16'h0380;
mem[447]=16'h0000;
mem[448]=16'h0000;
mem[449]=16'h0460;
mem[450]=16'h7ffc;
mem[451]=16'h0460;
mem[452]=16'h1ff8;
mem[453]=16'h1ff8;
mem[454]=16'h1018;
mem[455]=16'h1ff0;
mem[456]=16'h0300;
mem[457]=16'h0c60;
mem[458]=16'h19b8;
mem[459]=16'h7ffe;
mem[460]=16'h0990;
mem[461]=16'h0990;
mem[462]=16'h01b0;
mem[463]=16'h0000;
mem[464]=16'h0000;
mem[465]=16'h10c0;
mem[466]=16'h1080;
mem[467]=16'h11f8;
mem[468]=16'h7f10;
mem[469]=16'h13fc;
mem[470]=16'h1164;
mem[471]=16'h1124;
mem[472]=16'h1924;
mem[473]=16'h7364;
mem[474]=16'h13fe;
mem[475]=16'h1070;
mem[476]=16'h10d8;
mem[477]=16'h118c;
mem[478]=16'h3606;
mem[479]=16'h0000;
mem[480]=16'h0000;
mem[481]=16'h0c00;
mem[482]=16'h0800;
mem[483]=16'h1ffc;
mem[484]=16'h3004;
mem[485]=16'h2004;
mem[486]=16'h4fc4;
mem[487]=16'h1fc4;
mem[488]=16'h1844;
mem[489]=16'h1844;
mem[490]=16'h1844;
mem[491]=16'h1fc4;
mem[492]=16'h1844;
mem[493]=16'h000c;
mem[494]=16'h003c;
mem[495]=16'h0000;
mem[496]=16'h0000;
mem[497]=16'h0840;
mem[498]=16'h1860;
mem[499]=16'h1040;
mem[500]=16'h33fe;
mem[501]=16'h3000;
mem[502]=16'h7108;
mem[503]=16'h5118;
mem[504]=16'h1118;
mem[505]=16'h1190;
mem[506]=16'h1090;
mem[507]=16'h1090;
mem[508]=16'h1030;
mem[509]=16'h17fe;
mem[510]=16'h1000;
mem[511]=16'h0000;
mem[512]=16'h0000;
mem[513]=16'h1ffc;
mem[514]=16'h3244;
mem[515]=16'h3ffc;
mem[516]=16'h0180;
mem[517]=16'h3ffc;
mem[518]=16'h0180;
mem[519]=16'h0ff0;
mem[520]=16'h0810;
mem[521]=16'h0ff0;
mem[522]=16'h0810;
mem[523]=16'h0ff0;
mem[524]=16'h0ff0;
mem[525]=16'h0818;
mem[526]=16'h7ffe;
mem[527]=16'h0000;
mem[528]=16'h0000;
mem[529]=16'h0240;
mem[530]=16'h3e4c;
mem[531]=16'h0660;
mem[532]=16'h0640;
mem[533]=16'h7e62;
mem[534]=16'h023c;
mem[535]=16'h0ff8;
mem[536]=16'h1808;
mem[537]=16'h1808;
mem[538]=16'h1ff8;
mem[539]=16'h1808;
mem[540]=16'h1ff8;
mem[541]=16'h1808;
mem[542]=16'h1838;
mem[543]=16'h0000;
mem[544]=16'h0000;
mem[545]=16'h1ff8;
mem[546]=16'h1008;
mem[547]=16'h1ff8;
mem[548]=16'h1008;
mem[549]=16'h1ff8;
mem[550]=16'h0180;
mem[551]=16'h7ffe;
mem[552]=16'h0000;
mem[553]=16'h1ff8;
mem[554]=16'h1818;
mem[555]=16'h0ff0;
mem[556]=16'h0490;
mem[557]=16'h189c;
mem[558]=16'h3384;
mem[559]=16'h0000;
mem[560]=16'h0000;
mem[561]=16'h0ff0;
mem[562]=16'h0818;
mem[563]=16'h0818;
mem[564]=16'h0818;
mem[565]=16'h0ff0;
mem[566]=16'h0000;
mem[567]=16'h7ffe;
mem[568]=16'h0400;
mem[569]=16'h0400;
mem[570]=16'h0ff8;
mem[571]=16'h0018;
mem[572]=16'h0018;
mem[573]=16'h0010;
mem[574]=16'h00f0;
mem[575]=16'h0000;
mem[576]=16'h0000;
mem[577]=16'h0220;
mem[578]=16'h3260;
mem[579]=16'h327e;
mem[580]=16'h3240;
mem[581]=16'h32d0;
mem[582]=16'h3298;
mem[583]=16'h320c;
mem[584]=16'h0000;
mem[585]=16'h3ffc;
mem[586]=16'h366c;
mem[587]=16'h3244;
mem[588]=16'h3244;
mem[589]=16'h324c;
mem[590]=16'h7ffe;
mem[591]=16'h0000;
mem[592]=16'h0000;
mem[593]=16'h1000;
mem[594]=16'h19fc;
mem[595]=16'h0104;
mem[596]=16'h7d24;
mem[597]=16'h0924;
mem[598]=16'h1924;
mem[599]=16'h1124;
mem[600]=16'h3d24;
mem[601]=16'h7564;
mem[602]=16'h5070;
mem[603]=16'h10f0;
mem[604]=16'h10b2;
mem[605]=16'h1112;
mem[606]=16'h121e;
mem[607]=16'h0000;
mem[608]=16'h0000;
mem[609]=16'h3e7c;
mem[610]=16'h22c4;
mem[611]=16'h22cc;
mem[612]=16'h3e78;
mem[613]=16'h0110;
mem[614]=16'h7ffe;
mem[615]=16'h03c0;
mem[616]=16'h0e70;
mem[617]=16'h701e;
mem[618]=16'h3e7c;
mem[619]=16'h224c;
mem[620]=16'h2244;
mem[621]=16'h3e7c;
mem[622]=16'h2244;
mem[623]=16'h0000;
mem[624]=16'h0000;
mem[625]=16'h0180;
mem[626]=16'h0080;
mem[627]=16'h1ffe;
mem[628]=16'h3ffe;
mem[629]=16'h3000;
mem[630]=16'h1000;
mem[631]=16'h1000;
mem[632]=16'h3000;
mem[633]=16'h3000;
mem[634]=16'h3000;
mem[635]=16'h3000;
mem[636]=16'h2000;
mem[637]=16'h6000;
mem[638]=16'h4000;
mem[639]=16'h0000;
mem[640]=16'h0000;
mem[641]=16'h0080;
mem[642]=16'h1880;
mem[643]=16'h1ff8;
mem[644]=16'h3180;
mem[645]=16'h2080;
mem[646]=16'h0180;
mem[647]=16'h7ffe;
mem[648]=16'h0000;
mem[649]=16'h1ff8;
mem[650]=16'h1008;
mem[651]=16'h1008;
mem[652]=16'h1008;
mem[653]=16'h1ff8;
mem[654]=16'h1008;
mem[655]=16'h0000;
mem[656]=16'h0000;
mem[657]=16'h1000;
mem[658]=16'h11fc;
mem[659]=16'h1000;
mem[660]=16'h7c00;
mem[661]=16'h1800;
mem[662]=16'h13fe;
mem[663]=16'h3c20;
mem[664]=16'h3c20;
mem[665]=16'h75ac;
mem[666]=16'h5124;
mem[667]=16'h1126;
mem[668]=16'h1322;
mem[669]=16'h1020;
mem[670]=16'h1060;
mem[671]=16'h0000;
mem[672]=16'h0000;
mem[673]=16'h0180;
mem[674]=16'h0180;
mem[675]=16'h7ffe;
mem[676]=16'h0180;
mem[677]=16'h0180;
mem[678]=16'h0180;
mem[679]=16'h3ffc;
mem[680]=16'h0000;
mem[681]=16'h0180;
mem[682]=16'h348c;
mem[683]=16'h2404;
mem[684]=16'h6412;
mem[685]=16'h4430;
mem[686]=16'h07f0;
mem[687]=16'h0000;
mem[688]=16'h0000;
mem[689]=16'h1020;
mem[690]=16'h11fc;
mem[691]=16'h2104;
mem[692]=16'h2104;
mem[693]=16'h6dfc;
mem[694]=16'h7900;
mem[695]=16'h13fe;
mem[696]=16'h237a;
mem[697]=16'h3b4a;
mem[698]=16'h77fe;
mem[699]=16'h057a;
mem[700]=16'h194a;
mem[701]=16'h614a;
mem[702]=16'h0106;
mem[703]=16'h0000;
mem[704]=16'h0000;
mem[705]=16'h1800;
mem[706]=16'h10fc;
mem[707]=16'h7e84;
mem[708]=16'h10fc;
mem[709]=16'h2000;
mem[710]=16'h29fe;
mem[711]=16'h6884;
mem[712]=16'h7efc;
mem[713]=16'h0884;
mem[714]=16'h0afc;
mem[715]=16'h3c8c;
mem[716]=16'h688e;
mem[717]=16'h09fc;
mem[718]=16'h0804;
mem[719]=16'h0000;
mem[720]=16'h0000;
mem[721]=16'h10c0;
mem[722]=16'h1080;
mem[723]=16'h13fe;
mem[724]=16'h5480;
mem[725]=16'h5590;
mem[726]=16'h5530;
mem[727]=16'h51f4;
mem[728]=16'h52b4;
mem[729]=16'h12bc;
mem[730]=16'h1430;
mem[731]=16'h1c78;
mem[732]=16'h10c8;
mem[733]=16'h1186;
mem[734]=16'h1302;
mem[735]=16'h0000;
mem[736]=16'h0000;
mem[737]=16'h0c00;
mem[738]=16'h0ffc;
mem[739]=16'h1000;
mem[740]=16'h3ff8;
mem[741]=16'h4808;
mem[742]=16'h0ff8;
mem[743]=16'h0808;
mem[744]=16'h0ff8;
mem[745]=16'h0400;
mem[746]=16'h0ff0;
mem[747]=16'h1e30;
mem[748]=16'h2360;
mem[749]=16'h01e0;
mem[750]=16'h3e3e;
mem[751]=16'h0000;
mem[752]=16'h0000;
mem[753]=16'h0180;
mem[754]=16'h0180;
mem[755]=16'h3ffc;
mem[756]=16'h2184;
mem[757]=16'h2104;
mem[758]=16'h2104;
mem[759]=16'h21c4;
mem[760]=16'h2264;
mem[761]=16'h2634;
mem[762]=16'h2c14;
mem[763]=16'h2004;
mem[764]=16'h2004;
mem[765]=16'h2004;
mem[766]=16'h201c;
mem[767]=16'h0000;
mem[768]=16'h0000;
mem[769]=16'h0800;
mem[770]=16'h28fe;
mem[771]=16'h2f30;
mem[772]=16'h2830;
mem[773]=16'h287e;
mem[774]=16'h7f46;
mem[775]=16'h0856;
mem[776]=16'h2856;
mem[777]=16'h2b56;
mem[778]=16'h4e56;
mem[779]=16'h0c52;
mem[780]=16'h0c20;
mem[781]=16'h3064;
mem[782]=16'h6182;
mem[783]=16'h0000;
mem[784]=16'h0000;
mem[785]=16'h0198;
mem[786]=16'h2090;
mem[787]=16'h17fe;
mem[788]=16'h0294;
mem[789]=16'h0294;
mem[790]=16'h7090;
mem[791]=16'h37fe;
mem[792]=16'h3000;
mem[793]=16'h31fc;
mem[794]=16'h3104;
mem[795]=16'h31fc;
mem[796]=16'h3904;
mem[797]=16'h310c;
mem[798]=16'h01fc;
mem[799]=16'h0000;
mem[800]=16'h0000;
mem[801]=16'h0100;
mem[802]=16'h0180;
mem[803]=16'h0000;
mem[804]=16'h7ffe;
mem[805]=16'h0400;
mem[806]=16'h0400;
mem[807]=16'h07f8;
mem[808]=16'h07f8;
mem[809]=16'h0408;
mem[810]=16'h0c08;
mem[811]=16'h0808;
mem[812]=16'h1818;
mem[813]=16'h3018;
mem[814]=16'h6070;
mem[815]=16'h0000;
mem[816]=16'h0000;
mem[817]=16'h0200;
mem[818]=16'h0600;
mem[819]=16'h3ffc;
mem[820]=16'h3ffe;
mem[821]=16'h2006;
mem[822]=16'h2006;
mem[823]=16'h27e6;
mem[824]=16'h2426;
mem[825]=16'h2426;
mem[826]=16'h27e6;
mem[827]=16'h23e6;
mem[828]=16'h2006;
mem[829]=16'h2006;
mem[830]=16'h200c;
mem[831]=16'h0000;
mem[832]=16'h0000;
mem[833]=16'h007c;
mem[834]=16'h3f80;
mem[835]=16'h0300;
mem[836]=16'h0630;
mem[837]=16'h0c60;
mem[838]=16'h0f80;
mem[839]=16'h0318;
mem[840]=16'h1c1c;
mem[841]=16'h1ff6;
mem[842]=16'h0080;
mem[843]=16'h1898;
mem[844]=16'h308c;
mem[845]=16'h6086;
mem[846]=16'h0380;
mem[847]=16'h0000;
mem[848]=16'h0000;
mem[849]=16'h1060;
mem[850]=16'h1020;
mem[851]=16'h33fe;
mem[852]=16'h2440;
mem[853]=16'h6c40;
mem[854]=16'h7888;
mem[855]=16'h118c;
mem[856]=16'h31fe;
mem[857]=16'h7cd0;
mem[858]=16'h70d0;
mem[859]=16'h0090;
mem[860]=16'h0c90;
mem[861]=16'h7192;
mem[862]=16'h031e;
mem[863]=16'h0000;
mem[864]=16'h0000;
mem[865]=16'h1010;
mem[866]=16'h1c10;
mem[867]=16'h2410;
mem[868]=16'h44fc;
mem[869]=16'h7e94;
mem[870]=16'h2a94;
mem[871]=16'h3e94;
mem[872]=16'h2afc;
mem[873]=16'h2ad4;
mem[874]=16'h3e90;
mem[875]=16'h2a14;
mem[876]=16'h2a16;
mem[877]=16'h4afe;
mem[878]=16'h4282;
mem[879]=16'h0000;
mem[880]=16'h0000;
mem[881]=16'h1090;
mem[882]=16'h13fe;
mem[883]=16'h13fe;
mem[884]=16'h7cd8;
mem[885]=16'h11fc;
mem[886]=16'h1104;
mem[887]=16'h19fc;
mem[888]=16'h3904;
mem[889]=16'h71fc;
mem[890]=16'h1060;
mem[891]=16'h13fe;
mem[892]=16'h1050;
mem[893]=16'h118c;
mem[894]=16'h7706;
mem[895]=16'h0000;
mem[896]=16'h0000;
mem[897]=16'h1020;
mem[898]=16'h1020;
mem[899]=16'h13fe;
mem[900]=16'h7c00;
mem[901]=16'h10c8;
mem[902]=16'h1184;
mem[903]=16'h3d02;
mem[904]=16'h3c88;
mem[905]=16'h7488;
mem[906]=16'h5050;
mem[907]=16'h1070;
mem[908]=16'h1070;
mem[909]=16'h11dc;
mem[910]=16'h1306;
mem[911]=16'h0000;
mem[912]=16'h0000;
mem[913]=16'h0120;
mem[914]=16'h4330;
mem[915]=16'h23fc;
mem[916]=16'h13fc;
mem[917]=16'h0620;
mem[918]=16'h0f30;
mem[919]=16'h03fc;
mem[920]=16'h1220;
mem[921]=16'h1320;
mem[922]=16'h23fc;
mem[923]=16'h2220;
mem[924]=16'h6220;
mem[925]=16'h43fe;
mem[926]=16'h0200;
mem[927]=16'h0000;
mem[928]=16'h0000;
mem[929]=16'h2404;
mem[930]=16'h24fc;
mem[931]=16'h2480;
mem[932]=16'h2480;
mem[933]=16'h2cfc;
mem[934]=16'h3ee4;
mem[935]=16'h20e4;
mem[936]=16'h20a4;
mem[937]=16'h3cac;
mem[938]=16'h24a8;
mem[939]=16'h2518;
mem[940]=16'h2518;
mem[941]=16'h473c;
mem[942]=16'h44c6;
mem[943]=16'h0000;
mem[944]=16'h0000;
mem[945]=16'h0180;
mem[946]=16'h0180;
mem[947]=16'h0180;
mem[948]=16'h7ffe;
mem[949]=16'h03c0;
mem[950]=16'h03c0;
mem[951]=16'h05e0;
mem[952]=16'h05a0;
mem[953]=16'h0990;
mem[954]=16'h1998;
mem[955]=16'h37ee;
mem[956]=16'h6180;
mem[957]=16'h0180;
mem[958]=16'h0180;
mem[959]=16'h0000;
mem[960]=16'h0000;
mem[961]=16'h0c20;
mem[962]=16'h0c28;
mem[963]=16'h4c24;
mem[964]=16'h6c20;
mem[965]=16'h2dfe;
mem[966]=16'h0dfe;
mem[967]=16'h0c60;
mem[968]=16'h1c60;
mem[969]=16'h3c70;
mem[970]=16'h6c50;
mem[971]=16'h4c98;
mem[972]=16'h0d88;
mem[973]=16'h0d06;
mem[974]=16'h0f06;
mem[975]=16'h0000;
mem[976]=16'h0000;
mem[977]=16'h0100;
mem[978]=16'h0100;
mem[979]=16'h7ffe;
mem[980]=16'h0240;
mem[981]=16'h0660;
mem[982]=16'h0e30;
mem[983]=16'h1b18;
mem[984]=16'h7006;
mem[985]=16'h0000;
mem[986]=16'h0488;
mem[987]=16'h2484;
mem[988]=16'h2416;
mem[989]=16'h6630;
mem[990]=16'h07e0;
mem[991]=16'h0000;
mem[992]=16'h0000;
mem[993]=16'h0000;
mem[994]=16'h0000;
mem[995]=16'h03c0;
mem[996]=16'h0660;
mem[997]=16'h0420;
mem[998]=16'h0420;
mem[999]=16'h0420;
mem[1000]=16'h0420;
mem[1001]=16'h0420;
mem[1002]=16'h0420;
mem[1003]=16'h0660;
mem[1004]=16'h03c0;
mem[1005]=16'h0000;
mem[1006]=16'h0000;
mem[1007]=16'h0000;
mem[1008]=16'h0000;
mem[1009]=16'h0000;
mem[1010]=16'h0000;
mem[1011]=16'h0180;
mem[1012]=16'h0380;
mem[1013]=16'h0780;
mem[1014]=16'h0180;
mem[1015]=16'h0180;
mem[1016]=16'h0180;
mem[1017]=16'h0180;
mem[1018]=16'h0180;
mem[1019]=16'h0180;
mem[1020]=16'h0180;
mem[1021]=16'h0000;
mem[1022]=16'h0000;
mem[1023]=16'h0000;
mem[1024]=16'h0000;
mem[1025]=16'h0000;
mem[1026]=16'h0000;
mem[1027]=16'h03c0;
mem[1028]=16'h0460;
mem[1029]=16'h0020;
mem[1030]=16'h0060;
mem[1031]=16'h0040;
mem[1032]=16'h00c0;
mem[1033]=16'h0180;
mem[1034]=16'h0100;
mem[1035]=16'h0200;
mem[1036]=16'h07e0;
mem[1037]=16'h0000;
mem[1038]=16'h0000;
mem[1039]=16'h0000;
mem[1040]=16'h0000;
mem[1041]=16'h0000;
mem[1042]=16'h0000;
mem[1043]=16'h03c0;
mem[1044]=16'h0460;
mem[1045]=16'h0020;
mem[1046]=16'h0060;
mem[1047]=16'h01c0;
mem[1048]=16'h00c0;
mem[1049]=16'h0020;
mem[1050]=16'h0020;
mem[1051]=16'h0460;
mem[1052]=16'h03c0;
mem[1053]=16'h0000;
mem[1054]=16'h0000;
mem[1055]=16'h0000;
mem[1056]=16'h0000;
mem[1057]=16'h0000;
mem[1058]=16'h0000;
mem[1059]=16'h0040;
mem[1060]=16'h00c0;
mem[1061]=16'h01c0;
mem[1062]=16'h0140;
mem[1063]=16'h0240;
mem[1064]=16'h0640;
mem[1065]=16'h0c40;
mem[1066]=16'h0ff0;
mem[1067]=16'h0040;
mem[1068]=16'h0040;
mem[1069]=16'h0000;
mem[1070]=16'h0000;
mem[1071]=16'h0000;
mem[1072]=16'h0000;
mem[1073]=16'h0000;
mem[1074]=16'h0000;
mem[1075]=16'h03e0;
mem[1076]=16'h0600;
mem[1077]=16'h0400;
mem[1078]=16'h0780;
mem[1079]=16'h06c0;
mem[1080]=16'h0060;
mem[1081]=16'h0020;
mem[1082]=16'h0020;
mem[1083]=16'h0c60;
mem[1084]=16'h07c0;
mem[1085]=16'h0100;
mem[1086]=16'h0000;
mem[1087]=16'h0000;
mem[1088]=16'h0000;
mem[1089]=16'h0000;
mem[1090]=16'h0000;
mem[1091]=16'h0080;
mem[1092]=16'h0180;
mem[1093]=16'h0100;
mem[1094]=16'h0300;
mem[1095]=16'h07e0;
mem[1096]=16'h0420;
mem[1097]=16'h0430;
mem[1098]=16'h0430;
mem[1099]=16'h0420;
mem[1100]=16'h07e0;
mem[1101]=16'h0180;
mem[1102]=16'h0000;
mem[1103]=16'h0000;
mem[1104]=16'h0000;
mem[1105]=16'h0000;
mem[1106]=16'h0000;
mem[1107]=16'h07e0;
mem[1108]=16'h0020;
mem[1109]=16'h0040;
mem[1110]=16'h0040;
mem[1111]=16'h0080;
mem[1112]=16'h0080;
mem[1113]=16'h0180;
mem[1114]=16'h0100;
mem[1115]=16'h0100;
mem[1116]=16'h0300;
mem[1117]=16'h0000;
mem[1118]=16'h0000;
mem[1119]=16'h0000;
mem[1120]=16'h0000;
mem[1121]=16'h0000;
mem[1122]=16'h0000;
mem[1123]=16'h03c0;
mem[1124]=16'h0460;
mem[1125]=16'h0420;
mem[1126]=16'h0460;
mem[1127]=16'h03c0;
mem[1128]=16'h06e0;
mem[1129]=16'h0420;
mem[1130]=16'h0c20;
mem[1131]=16'h0420;
mem[1132]=16'h07c0;
mem[1133]=16'h0180;
mem[1134]=16'h0000;
mem[1135]=16'h0000;
mem[1136]=16'h0000;
mem[1137]=16'h0000;
mem[1138]=16'h0000;
mem[1139]=16'h07c0;
mem[1140]=16'h0460;
mem[1141]=16'h0c20;
mem[1142]=16'h0c20;
mem[1143]=16'h0460;
mem[1144]=16'h07c0;
mem[1145]=16'h00c0;
mem[1146]=16'h0080;
mem[1147]=16'h0180;
mem[1148]=16'h0100;
mem[1149]=16'h0000;
mem[1150]=16'h0000;
mem[1151]=16'h0000;
mem[1152]=16'h0000;
mem[1153]=16'h0000;
mem[1154]=16'h0000;
mem[1155]=16'h07c0;
mem[1156]=16'h0460;
mem[1157]=16'h0420;
mem[1158]=16'h0420;
mem[1159]=16'h0460;
mem[1160]=16'h07c0;
mem[1161]=16'h0400;
mem[1162]=16'h0400;
mem[1163]=16'h0400;
mem[1164]=16'h0400;
mem[1165]=16'h0000;
mem[1166]=16'h0000;
mem[1167]=16'h0000;
mem[1168]=16'h0000;
mem[1169]=16'h0000;
mem[1170]=16'h0000;
mem[1171]=16'h0000;
mem[1172]=16'h0000;
mem[1173]=16'h0100;
mem[1174]=16'h0100;
mem[1175]=16'h07e0;
mem[1176]=16'h0180;
mem[1177]=16'h0100;
mem[1178]=16'h0100;
mem[1179]=16'h0000;
mem[1180]=16'h0000;
mem[1181]=16'h0000;
mem[1182]=16'h0000;
mem[1183]=16'h0000;
mem[1184]=16'h0000;
mem[1185]=16'h0000;
mem[1186]=16'h0000;
mem[1187]=16'h0000;
mem[1188]=16'h0000;
mem[1189]=16'h0000;
mem[1190]=16'h0000;
mem[1191]=16'h07e0;
mem[1192]=16'h0000;
mem[1193]=16'h0000;
mem[1194]=16'h0000;
mem[1195]=16'h0000;
mem[1196]=16'h0000;
mem[1197]=16'h0000;
mem[1198]=16'h0000;
mem[1199]=16'h0000;
mem[1200]=16'h0000;
mem[1201]=16'h0000;
mem[1202]=16'h0000;
mem[1203]=16'h0000;
mem[1204]=16'h0000;
mem[1205]=16'h0000;
mem[1206]=16'h0100;
mem[1207]=16'h0100;
mem[1208]=16'h0000;
mem[1209]=16'h0000;
mem[1210]=16'h0000;
mem[1211]=16'h0000;
mem[1212]=16'h0180;
mem[1213]=16'h0000;
mem[1214]=16'h0000;
mem[1215]=16'h0000;
mem[1216]=16'h0000;
mem[1217]=16'h0000;
mem[1218]=16'h1ff8;
mem[1219]=16'h0100;
mem[1220]=16'h0100;
mem[1221]=16'h0100;
mem[1222]=16'h0300;
mem[1223]=16'h3ffe;
mem[1224]=16'h0340;
mem[1225]=16'h0240;
mem[1226]=16'h0240;
mem[1227]=16'h0440;
mem[1228]=16'h0c42;
mem[1229]=16'h387e;
mem[1230]=16'h603c;
mem[1231]=16'h0000;
mem[1232]=16'h0000;
mem[1233]=16'h0180;
mem[1234]=16'h3188;
mem[1235]=16'h1998;
mem[1236]=16'h0990;
mem[1237]=16'h0180;
mem[1238]=16'h3ffc;
mem[1239]=16'h3ffc;
mem[1240]=16'h0180;
mem[1241]=16'h0180;
mem[1242]=16'h7ffe;
mem[1243]=16'h0180;
mem[1244]=16'h0180;
mem[1245]=16'h0180;
mem[1246]=16'h0180;
mem[1247]=16'h0000;
mem[1248]=16'h0000;
mem[1249]=16'h2038;
mem[1250]=16'h23c0;
mem[1251]=16'h1040;
mem[1252]=16'h07fc;
mem[1253]=16'h01f0;
mem[1254]=16'h734c;
mem[1255]=16'h3644;
mem[1256]=16'h33f0;
mem[1257]=16'h309c;
mem[1258]=16'h3184;
mem[1259]=16'h310c;
mem[1260]=16'h3218;
mem[1261]=16'h6e00;
mem[1262]=16'h41fe;
mem[1263]=16'h0000;
mem[1264]=16'h0000;
mem[1265]=16'h0180;
mem[1266]=16'h0180;
mem[1267]=16'h3ffc;
mem[1268]=16'h2004;
mem[1269]=16'h2c44;
mem[1270]=16'h0640;
mem[1271]=16'h1040;
mem[1272]=16'h1c40;
mem[1273]=16'h00c0;
mem[1274]=16'h7ffe;
mem[1275]=16'h0080;
mem[1276]=16'h0370;
mem[1277]=16'h0e18;
mem[1278]=16'h3806;
mem[1279]=16'h0000;
mem[1280]=16'h0000;
mem[1281]=16'h0080;
mem[1282]=16'h1ffe;
mem[1283]=16'h1000;
mem[1284]=16'h1008;
mem[1285]=16'h17fc;
mem[1286]=16'h1660;
mem[1287]=16'h1660;
mem[1288]=16'h17fc;
mem[1289]=16'h37fc;
mem[1290]=16'h3620;
mem[1291]=16'h26a0;
mem[1292]=16'h2792;
mem[1293]=16'h669e;
mem[1294]=16'h40ce;
mem[1295]=16'h0000;
mem[1296]=16'h0000;
mem[1297]=16'h0180;
mem[1298]=16'h0180;
mem[1299]=16'h0180;
mem[1300]=16'h0180;
mem[1301]=16'h0990;
mem[1302]=16'h1998;
mem[1303]=16'h1188;
mem[1304]=16'h118c;
mem[1305]=16'h3184;
mem[1306]=16'h2186;
mem[1307]=16'h2180;
mem[1308]=16'h0180;
mem[1309]=16'h0180;
mem[1310]=16'h0300;
mem[1311]=16'h0000;
mem[1312]=16'h0000;
mem[1313]=16'h0180;
mem[1314]=16'h0180;
mem[1315]=16'h0180;
mem[1316]=16'h3ffc;
mem[1317]=16'h2184;
mem[1318]=16'h2184;
mem[1319]=16'h2184;
mem[1320]=16'h2184;
mem[1321]=16'h3ffc;
mem[1322]=16'h2184;
mem[1323]=16'h0180;
mem[1324]=16'h0180;
mem[1325]=16'h0180;
mem[1326]=16'h0180;
mem[1327]=16'h0000;
mem[1328]=16'h0000;
mem[1329]=16'h0040;
mem[1330]=16'h37fe;
mem[1331]=16'h1108;
mem[1332]=16'h010c;
mem[1333]=16'h46c6;
mem[1334]=16'h6490;
mem[1335]=16'h1118;
mem[1336]=16'h03fc;
mem[1337]=16'h00a0;
mem[1338]=16'h11a4;
mem[1339]=16'h2798;
mem[1340]=16'h2598;
mem[1341]=16'h61cc;
mem[1342]=16'h4182;
mem[1343]=16'h0000;
mem[1344]=16'h0000;
mem[1345]=16'h0030;
mem[1346]=16'h0030;
mem[1347]=16'h3e30;
mem[1348]=16'h00fe;
mem[1349]=16'h0036;
mem[1350]=16'h7f32;
mem[1351]=16'h1822;
mem[1352]=16'h1022;
mem[1353]=16'h1222;
mem[1354]=16'h2222;
mem[1355]=16'h6f62;
mem[1356]=16'h7146;
mem[1357]=16'h00c6;
mem[1358]=16'h019c;
mem[1359]=16'h0000;
mem[1360]=16'h0000;
mem[1361]=16'h0180;
mem[1362]=16'h3ffc;
mem[1363]=16'h0180;
mem[1364]=16'h0100;
mem[1365]=16'h1ff8;
mem[1366]=16'h1818;
mem[1367]=16'h1ff8;
mem[1368]=16'h1818;
mem[1369]=16'h1ff8;
mem[1370]=16'h1818;
mem[1371]=16'h1ff8;
mem[1372]=16'h1818;
mem[1373]=16'h7ffe;
mem[1374]=16'h7ffe;
mem[1375]=16'h0000;
mem[1376]=16'h0000;
mem[1377]=16'h1000;
mem[1378]=16'h11fe;
mem[1379]=16'h1066;
mem[1380]=16'h1066;
mem[1381]=16'h1e66;
mem[1382]=16'h7866;
mem[1383]=16'h1044;
mem[1384]=16'h1044;
mem[1385]=16'h1044;
mem[1386]=16'h16c4;
mem[1387]=16'h1c84;
mem[1388]=16'h1184;
mem[1389]=16'h031c;
mem[1390]=16'h0618;
mem[1391]=16'h0000;
mem[1392]=16'h0000;
mem[1393]=16'h0000;
mem[1394]=16'h7dfc;
mem[1395]=16'h1060;
mem[1396]=16'h1060;
mem[1397]=16'h11fc;
mem[1398]=16'h1104;
mem[1399]=16'h1124;
mem[1400]=16'h1124;
mem[1401]=16'h1164;
mem[1402]=16'h1164;
mem[1403]=16'h1144;
mem[1404]=16'h10d8;
mem[1405]=16'h718c;
mem[1406]=16'h0706;
mem[1407]=16'h0000;
mem[1408]=16'h0000;
mem[1409]=16'h0c00;
mem[1410]=16'h0c3e;
mem[1411]=16'h3fa4;
mem[1412]=16'h1124;
mem[1413]=16'h1224;
mem[1414]=16'h1228;
mem[1415]=16'h7fac;
mem[1416]=16'h0024;
mem[1417]=16'h3f22;
mem[1418]=16'h3122;
mem[1419]=16'h2122;
mem[1420]=16'h212e;
mem[1421]=16'h3f20;
mem[1422]=16'h2120;
mem[1423]=16'h0000;
mem[1424]=16'h0000;
mem[1425]=16'h0100;
mem[1426]=16'h0100;
mem[1427]=16'h0300;
mem[1428]=16'h7ffe;
mem[1429]=16'h0200;
mem[1430]=16'h0600;
mem[1431]=16'h0400;
mem[1432]=16'h0ff8;
mem[1433]=16'h1c08;
mem[1434]=16'h3c08;
mem[1435]=16'h6c08;
mem[1436]=16'h4c08;
mem[1437]=16'h0ff8;
mem[1438]=16'h0c08;
mem[1439]=16'h0000;
mem[1440]=16'h0000;
mem[1441]=16'h0180;
mem[1442]=16'h0180;
mem[1443]=16'h0180;
mem[1444]=16'h018c;
mem[1445]=16'h7d98;
mem[1446]=16'h05f0;
mem[1447]=16'h0de0;
mem[1448]=16'h09e0;
mem[1449]=16'h19b0;
mem[1450]=16'h1190;
mem[1451]=16'h318c;
mem[1452]=16'h6186;
mem[1453]=16'h0180;
mem[1454]=16'h0300;
mem[1455]=16'h0000;
mem[1456]=16'h0000;
mem[1457]=16'h0000;
mem[1458]=16'h3ffc;
mem[1459]=16'h0180;
mem[1460]=16'h1188;
mem[1461]=16'h1998;
mem[1462]=16'h0db0;
mem[1463]=16'h01a0;
mem[1464]=16'h0180;
mem[1465]=16'h7ffe;
mem[1466]=16'h0180;
mem[1467]=16'h0180;
mem[1468]=16'h0180;
mem[1469]=16'h0180;
mem[1470]=16'h0180;
mem[1471]=16'h0000;
mem[1472]=16'h0000;
mem[1473]=16'h25fc;
mem[1474]=16'h248c;
mem[1475]=16'h24c8;
mem[1476]=16'h2450;
mem[1477]=16'h2470;
mem[1478]=16'h24f8;
mem[1479]=16'h050e;
mem[1480]=16'h0100;
mem[1481]=16'h3ffc;
mem[1482]=16'h0800;
mem[1483]=16'h0830;
mem[1484]=16'h0420;
mem[1485]=16'h0460;
mem[1486]=16'h7ffe;
mem[1487]=16'h0000;
mem[1488]=16'h0000;
mem[1489]=16'h0000;
mem[1490]=16'h3f7c;
mem[1491]=16'h2244;
mem[1492]=16'h2244;
mem[1493]=16'h3e64;
mem[1494]=16'h2224;
mem[1495]=16'h222c;
mem[1496]=16'h3e28;
mem[1497]=16'h3238;
mem[1498]=16'h2318;
mem[1499]=16'h37b8;
mem[1500]=16'h7a2c;
mem[1501]=16'h0246;
mem[1502]=16'h0242;
mem[1503]=16'h0000;
mem[1504]=16'h0000;
mem[1505]=16'h2020;
mem[1506]=16'h3226;
mem[1507]=16'h1324;
mem[1508]=16'h0020;
mem[1509]=16'h43fc;
mem[1510]=16'h7306;
mem[1511]=16'h1206;
mem[1512]=16'h03fe;
mem[1513]=16'h1306;
mem[1514]=16'h1206;
mem[1515]=16'h33fe;
mem[1516]=16'h2206;
mem[1517]=16'h6206;
mem[1518]=16'h620c;
mem[1519]=16'h0000;
mem[1520]=16'h0000;
mem[1521]=16'h0040;
mem[1522]=16'h7cf8;
mem[1523]=16'h1998;
mem[1524]=16'h1110;
mem[1525]=16'h10fe;
mem[1526]=16'h3cb2;
mem[1527]=16'h34b2;
mem[1528]=16'h64fe;
mem[1529]=16'h24b2;
mem[1530]=16'h24fe;
mem[1531]=16'h3cb6;
mem[1532]=16'h35b2;
mem[1533]=16'h2132;
mem[1534]=16'h0306;
mem[1535]=16'h0000;
mem[1536]=16'h0000;
mem[1537]=16'h1060;
mem[1538]=16'h1860;
mem[1539]=16'h0860;
mem[1540]=16'h0060;
mem[1541]=16'h0060;
mem[1542]=16'h7060;
mem[1543]=16'h1060;
mem[1544]=16'h1060;
mem[1545]=16'h10f0;
mem[1546]=16'h1690;
mem[1547]=16'h1d98;
mem[1548]=16'h1908;
mem[1549]=16'h120c;
mem[1550]=16'h0406;
mem[1551]=16'h0000;
mem[1552]=16'h0000;
mem[1553]=16'h39c2;
mem[1554]=16'h2942;
mem[1555]=16'h295a;
mem[1556]=16'h295a;
mem[1557]=16'h295a;
mem[1558]=16'h7fda;
mem[1559]=16'h7fda;
mem[1560]=16'h295a;
mem[1561]=16'h295a;
mem[1562]=16'h295a;
mem[1563]=16'h2b42;
mem[1564]=16'h6a42;
mem[1565]=16'h4e42;
mem[1566]=16'h58ce;
mem[1567]=16'h0000;
mem[1568]=16'h0000;
mem[1569]=16'h0060;
mem[1570]=16'h7c60;
mem[1571]=16'h6c90;
mem[1572]=16'h6988;
mem[1573]=16'h6b8e;
mem[1574]=16'h7afa;
mem[1575]=16'h6820;
mem[1576]=16'h65fc;
mem[1577]=16'h65fc;
mem[1578]=16'h6c20;
mem[1579]=16'h79a8;
mem[1580]=16'h6324;
mem[1581]=16'h6226;
mem[1582]=16'h60e0;
mem[1583]=16'h0000;
mem[1584]=16'h0000;
mem[1585]=16'h0040;
mem[1586]=16'h37fc;
mem[1587]=16'h1860;
mem[1588]=16'h03fc;
mem[1589]=16'h4060;
mem[1590]=16'h77fe;
mem[1591]=16'h1000;
mem[1592]=16'h03fc;
mem[1593]=16'h020c;
mem[1594]=16'h13fc;
mem[1595]=16'h120c;
mem[1596]=16'h23fc;
mem[1597]=16'h620c;
mem[1598]=16'h420c;
mem[1599]=16'h0000;
mem[1600]=16'h0000;
mem[1601]=16'h0180;
mem[1602]=16'h0180;
mem[1603]=16'h3ffe;
mem[1604]=16'h2006;
mem[1605]=16'h2c24;
mem[1606]=16'h1838;
mem[1607]=16'h300e;
mem[1608]=16'h2000;
mem[1609]=16'h1ff8;
mem[1610]=16'h0180;
mem[1611]=16'h0180;
mem[1612]=16'h0180;
mem[1613]=16'h0180;
mem[1614]=16'h7ffe;
mem[1615]=16'h0000;
mem[1616]=16'h0000;
mem[1617]=16'h1800;
mem[1618]=16'h11fc;
mem[1619]=16'h2000;
mem[1620]=16'h6000;
mem[1621]=16'h0800;
mem[1622]=16'h1bfe;
mem[1623]=16'h3018;
mem[1624]=16'h3010;
mem[1625]=16'h5010;
mem[1626]=16'h1010;
mem[1627]=16'h1010;
mem[1628]=16'h1010;
mem[1629]=16'h1010;
mem[1630]=16'h1030;
mem[1631]=16'h0000;
mem[1632]=16'h0000;
mem[1633]=16'h0410;
mem[1634]=16'h0420;
mem[1635]=16'h7ffe;
mem[1636]=16'h0000;
mem[1637]=16'h1e04;
mem[1638]=16'h3364;
mem[1639]=16'h2164;
mem[1640]=16'h3f64;
mem[1641]=16'h2164;
mem[1642]=16'h3364;
mem[1643]=16'h3f64;
mem[1644]=16'h2104;
mem[1645]=16'h2104;
mem[1646]=16'h271c;
mem[1647]=16'h0000;
mem[1648]=16'h0000;
mem[1649]=16'h0018;
mem[1650]=16'h1ff8;
mem[1651]=16'h1000;
mem[1652]=16'h1000;
mem[1653]=16'h1ffe;
mem[1654]=16'h1000;
mem[1655]=16'h1000;
mem[1656]=16'h17f8;
mem[1657]=16'h360c;
mem[1658]=16'h240c;
mem[1659]=16'h240c;
mem[1660]=16'h240c;
mem[1661]=16'h67fc;
mem[1662]=16'h040c;
mem[1663]=16'h0000;
mem[1664]=16'h0000;
mem[1665]=16'h0000;
mem[1666]=16'h7ffe;
mem[1667]=16'h0180;
mem[1668]=16'h0100;
mem[1669]=16'h1ff8;
mem[1670]=16'h1808;
mem[1671]=16'h1908;
mem[1672]=16'h1908;
mem[1673]=16'h1908;
mem[1674]=16'h1908;
mem[1675]=16'h1300;
mem[1676]=16'h0670;
mem[1677]=16'h0c18;
mem[1678]=16'h700c;
mem[1679]=16'h0000;
mem[1680]=16'h0000;
mem[1681]=16'h0180;
mem[1682]=16'h0180;
mem[1683]=16'h1188;
mem[1684]=16'h1998;
mem[1685]=16'h0990;
mem[1686]=16'h0180;
mem[1687]=16'h7ffe;
mem[1688]=16'h0240;
mem[1689]=16'h0240;
mem[1690]=16'h0640;
mem[1691]=16'h0440;
mem[1692]=16'h0c42;
mem[1693]=16'h3866;
mem[1694]=16'h603c;
mem[1695]=16'h0000;
mem[1696]=16'h0000;
mem[1697]=16'h3ffc;
mem[1698]=16'h2004;
mem[1699]=16'h2304;
mem[1700]=16'h23e4;
mem[1701]=16'h2664;
mem[1702]=16'h2bc4;
mem[1703]=16'h21c4;
mem[1704]=16'h2e74;
mem[1705]=16'h21c4;
mem[1706]=16'h2044;
mem[1707]=16'h2384;
mem[1708]=16'h20c4;
mem[1709]=16'h3ffc;
mem[1710]=16'h2004;
mem[1711]=16'h0000;
mem[1712]=16'h0000;
mem[1713]=16'h1820;
mem[1714]=16'h1820;
mem[1715]=16'h1820;
mem[1716]=16'h1820;
mem[1717]=16'h1ffe;
mem[1718]=16'h1800;
mem[1719]=16'h1800;
mem[1720]=16'h1800;
mem[1721]=16'h1ff0;
mem[1722]=16'h1010;
mem[1723]=16'h1010;
mem[1724]=16'h3010;
mem[1725]=16'h2010;
mem[1726]=16'h6010;
mem[1727]=16'h0000;
mem[1728]=16'h0000;
mem[1729]=16'h1060;
mem[1730]=16'h1060;
mem[1731]=16'h13fe;
mem[1732]=16'h7a02;
mem[1733]=16'h30d8;
mem[1734]=16'h118c;
mem[1735]=16'h1306;
mem[1736]=16'h3800;
mem[1737]=16'h71fc;
mem[1738]=16'h1020;
mem[1739]=16'h1020;
mem[1740]=16'h1020;
mem[1741]=16'h1060;
mem[1742]=16'h33fe;
mem[1743]=16'h0000;
mem[1744]=16'h0000;
mem[1745]=16'h0c06;
mem[1746]=16'h2c06;
mem[1747]=16'h7fb6;
mem[1748]=16'h4c36;
mem[1749]=16'h0c36;
mem[1750]=16'h7fb6;
mem[1751]=16'h0c36;
mem[1752]=16'h0c36;
mem[1753]=16'h7fb6;
mem[1754]=16'h6cb6;
mem[1755]=16'h6cb6;
mem[1756]=16'h6d86;
mem[1757]=16'h4d06;
mem[1758]=16'h0c0c;
mem[1759]=16'h0000;
mem[1760]=16'h0000;
mem[1761]=16'h2020;
mem[1762]=16'h33fe;
mem[1763]=16'h1820;
mem[1764]=16'h03fc;
mem[1765]=16'h0020;
mem[1766]=16'h77fe;
mem[1767]=16'h1000;
mem[1768]=16'h11fc;
mem[1769]=16'h110c;
mem[1770]=16'h11fc;
mem[1771]=16'h1d0c;
mem[1772]=16'h19fc;
mem[1773]=16'h3104;
mem[1774]=16'h010c;
mem[1775]=16'h0000;
mem[1776]=16'h0000;
mem[1777]=16'h0006;
mem[1778]=16'h7f86;
mem[1779]=16'h0826;
mem[1780]=16'h1b26;
mem[1781]=16'h31a6;
mem[1782]=16'h7fa6;
mem[1783]=16'h2ca6;
mem[1784]=16'h0c26;
mem[1785]=16'h3f26;
mem[1786]=16'h0c26;
mem[1787]=16'h0c26;
mem[1788]=16'h0d86;
mem[1789]=16'h7f06;
mem[1790]=16'h401c;
mem[1791]=16'h0000;
mem[1792]=16'h0000;
mem[1793]=16'h11f8;
mem[1794]=16'h1108;
mem[1795]=16'h11f8;
mem[1796]=16'h7c00;
mem[1797]=16'h139c;
mem[1798]=16'h12d6;
mem[1799]=16'h1a52;
mem[1800]=16'h3bde;
mem[1801]=16'h5020;
mem[1802]=16'h17fe;
mem[1803]=16'h10f0;
mem[1804]=16'h11a8;
mem[1805]=16'h1326;
mem[1806]=16'h3220;
mem[1807]=16'h0000;
mem[1808]=16'h0000;
mem[1809]=16'h08c0;
mem[1810]=16'h0880;
mem[1811]=16'h19fe;
mem[1812]=16'h11fe;
mem[1813]=16'h3340;
mem[1814]=16'h7240;
mem[1815]=16'h507c;
mem[1816]=16'h1040;
mem[1817]=16'h1040;
mem[1818]=16'h1040;
mem[1819]=16'h107e;
mem[1820]=16'h1040;
mem[1821]=16'h1040;
mem[1822]=16'h1040;
mem[1823]=16'h0000;
mem[1824]=16'h0000;
mem[1825]=16'h1080;
mem[1826]=16'h1180;
mem[1827]=16'h11fe;
mem[1828]=16'h7f00;
mem[1829]=16'h1220;
mem[1830]=16'h1024;
mem[1831]=16'h1d3c;
mem[1832]=16'h39e4;
mem[1833]=16'h7724;
mem[1834]=16'h112c;
mem[1835]=16'h1120;
mem[1836]=16'h1100;
mem[1837]=16'h1102;
mem[1838]=16'h31fe;
mem[1839]=16'h0000;
mem[1840]=16'h0000;
mem[1841]=16'h09f8;
mem[1842]=16'h190c;
mem[1843]=16'h110c;
mem[1844]=16'h110c;
mem[1845]=16'h31fc;
mem[1846]=16'h7060;
mem[1847]=16'h5060;
mem[1848]=16'h17fe;
mem[1849]=16'h10f0;
mem[1850]=16'h11f0;
mem[1851]=16'h1168;
mem[1852]=16'h126e;
mem[1853]=16'h1462;
mem[1854]=16'h1060;
mem[1855]=16'h0000;
mem[1856]=16'h0000;
mem[1857]=16'h0300;
mem[1858]=16'h0300;
mem[1859]=16'h3ffc;
mem[1860]=16'h0600;
mem[1861]=16'h0400;
mem[1862]=16'h19fc;
mem[1863]=16'h1818;
mem[1864]=16'h3830;
mem[1865]=16'h6820;
mem[1866]=16'h0bfe;
mem[1867]=16'h0820;
mem[1868]=16'h0820;
mem[1869]=16'h0820;
mem[1870]=16'h08e0;
mem[1871]=16'h0000;
mem[1872]=16'h0000;
mem[1873]=16'h00c0;
mem[1874]=16'h00c0;
mem[1875]=16'h7ec0;
mem[1876]=16'h04fc;
mem[1877]=16'h0584;
mem[1878]=16'h3524;
mem[1879]=16'h1c20;
mem[1880]=16'h1820;
mem[1881]=16'h1c60;
mem[1882]=16'h1470;
mem[1883]=16'h3650;
mem[1884]=16'h2088;
mem[1885]=16'h6186;
mem[1886]=16'h0202;
mem[1887]=16'h0000;
mem[1888]=16'h0000;
mem[1889]=16'h2180;
mem[1890]=16'h263c;
mem[1891]=16'h2624;
mem[1892]=16'h0624;
mem[1893]=16'h0624;
mem[1894]=16'h7624;
mem[1895]=16'h3624;
mem[1896]=16'h3624;
mem[1897]=16'h37a4;
mem[1898]=16'h372c;
mem[1899]=16'h3020;
mem[1900]=16'h3020;
mem[1901]=16'h3e00;
mem[1902]=16'h43fe;
mem[1903]=16'h0000;
mem[1904]=16'h0000;
mem[1905]=16'h1860;
mem[1906]=16'h1060;
mem[1907]=16'h17fe;
mem[1908]=16'h3040;
mem[1909]=16'h33fc;
mem[1910]=16'h7264;
mem[1911]=16'h5244;
mem[1912]=16'h13fc;
mem[1913]=16'h1040;
mem[1914]=16'h1340;
mem[1915]=16'h11c0;
mem[1916]=16'h10c0;
mem[1917]=16'h11f0;
mem[1918]=16'h161e;
mem[1919]=16'h0000;
mem[1920]=16'h0000;
mem[1921]=16'h1ff8;
mem[1922]=16'h118c;
mem[1923]=16'h118c;
mem[1924]=16'h118c;
mem[1925]=16'h1ffc;
mem[1926]=16'h118c;
mem[1927]=16'h118c;
mem[1928]=16'h118c;
mem[1929]=16'h1ffc;
mem[1930]=16'h318c;
mem[1931]=16'h218c;
mem[1932]=16'h218c;
mem[1933]=16'h619c;
mem[1934]=16'h4018;
mem[1935]=16'h0000;
mem[1936]=16'h0000;
mem[1937]=16'h0d20;
mem[1938]=16'h2d20;
mem[1939]=16'h0c60;
mem[1940]=16'h7ffe;
mem[1941]=16'h1c4c;
mem[1942]=16'h3fc4;
mem[1943]=16'h48cc;
mem[1944]=16'h08c8;
mem[1945]=16'h7f28;
mem[1946]=16'h1338;
mem[1947]=16'h3a30;
mem[1948]=16'h0f38;
mem[1949]=16'h0c6c;
mem[1950]=16'h30c6;
mem[1951]=16'h0000;
mem[1952]=16'h0000;
mem[1953]=16'h1ffc;
mem[1954]=16'h3004;
mem[1955]=16'h3004;
mem[1956]=16'h3ffc;
mem[1957]=16'h3210;
mem[1958]=16'h3110;
mem[1959]=16'h37fc;
mem[1960]=16'h3110;
mem[1961]=16'h2110;
mem[1962]=16'h2ffe;
mem[1963]=16'h2110;
mem[1964]=16'h6310;
mem[1965]=16'h4210;
mem[1966]=16'h0410;
mem[1967]=16'h0000;
mem[1968]=16'h0000;
mem[1969]=16'h1810;
mem[1970]=16'h1890;
mem[1971]=16'h1898;
mem[1972]=16'h7c88;
mem[1973]=16'h190c;
mem[1974]=16'h1906;
mem[1975]=16'h3f62;
mem[1976]=16'h3c40;
mem[1977]=16'h3a40;
mem[1978]=16'h58c8;
mem[1979]=16'h588c;
mem[1980]=16'h198c;
mem[1981]=16'h19fe;
mem[1982]=16'h1802;
mem[1983]=16'h0000;
mem[1984]=16'h0000;
mem[1985]=16'h0008;
mem[1986]=16'h3ff8;
mem[1987]=16'h0180;
mem[1988]=16'h0080;
mem[1989]=16'h0180;
mem[1990]=16'h1ffc;
mem[1991]=16'h0080;
mem[1992]=16'h0080;
mem[1993]=16'h7ffe;
mem[1994]=16'h0080;
mem[1995]=16'h0080;
mem[1996]=16'h0080;
mem[1997]=16'h0180;
mem[1998]=16'h0300;
mem[1999]=16'h0000;
mem[2000]=16'h0000;
mem[2001]=16'h1f82;
mem[2002]=16'h3092;
mem[2003]=16'h2092;
mem[2004]=16'h3f92;
mem[2005]=16'h3012;
mem[2006]=16'h2212;
mem[2007]=16'h2212;
mem[2008]=16'h2fd2;
mem[2009]=16'h2a52;
mem[2010]=16'h2a52;
mem[2011]=16'h6a52;
mem[2012]=16'h4ac2;
mem[2013]=16'h4a86;
mem[2014]=16'h020c;
mem[2015]=16'h0000;
mem[2016]=16'h0000;
mem[2017]=16'h0c1e;
mem[2018]=16'h7f60;
mem[2019]=16'h3f60;
mem[2020]=16'h2260;
mem[2021]=16'h1260;
mem[2022]=16'h7ffe;
mem[2023]=16'h0c64;
mem[2024]=16'h0c64;
mem[2025]=16'h7f64;
mem[2026]=16'h0844;
mem[2027]=16'h2b44;
mem[2028]=16'h6944;
mem[2029]=16'h48c4;
mem[2030]=16'h1884;
mem[2031]=16'h0000;
mem[2032]=16'h0000;
mem[2033]=16'h0000;
mem[2034]=16'h0000;
mem[2035]=16'h0000;
mem[2036]=16'h0000;
mem[2037]=16'h0000;
mem[2038]=16'h0000;
mem[2039]=16'h0000;
mem[2040]=16'h0000;
mem[2041]=16'h0000;
mem[2042]=16'h0000;
mem[2043]=16'h0000;
mem[2044]=16'h0000;
mem[2045]=16'h0000;
mem[2046]=16'h0000;
mem[2047]=16'h0000;
end
always @(posedge ref_clk) ref_bits<=mem[ref_addr];
always @(posedge pixel_clk) pixel_bits<=mem[pixel_addr];
endmodule

module touch_painter(
    input wire clk,
    input wire [8:0] input_x,input_y,
    input wire [10:0] scroll,
    input wire enabled,
    input wire [199:0] values,
    input wire [7:0] pressed,
    input wire [2:0] cal_step,mode,
    output wire [10:0] font_addr,
    input wire [15:0] font_bits,
    output reg [23:0] rgb
);
    `include "touch_layout.vh"

    reg [6:0] glyph;
    reg [3:0] gx,gy;
    reg [23:0] background,foreground;

    reg [8:0] x_s,y_s,x,y;
    reg [10:0] cy_s,cy;
    reg [7:0] geometry_row;
    wire [7:0] decoded_row=touch_row(cy_s);
    always @(posedge clk) begin
        x_s<=input_x;y_s<=input_y;cy_s<=input_y-9'd32+scroll;
        x<=x_s;y<=y_s;cy<=cy_s;geometry_row<=decoded_row;
    end
    reg string_en;
    reg [5:0] string_id;
    reg [4:0] string_ch;
    reg [7:0] row,value;
    reg [7:0] track_value;
    reg chosen,lamp;
    reg [5:0] sid;
    reg [8:0] text_left;
    integer col,r,button,relative_y,char_no,preview_col,tx,ty;
    always @* begin
        glyph=0;gx=0;gy=0;background=24'h0c141c;foreground=enabled?24'hf0f4f8:24'h80909c;
        row=255;string_en=0;string_id=0;string_ch=0;value=0;sid=0;
        track_value=0;chosen=0;lamp=0;text_left=0;
        col=0;r=0;button=0;relative_y=0;char_no=0;preview_col=0;tx=0;ty=0;
        if(y<32) begin
            background=24'h142430;
            if(x>=16 && x<304 && y>=8 && y<24) begin
                string_en=1;string_id=6'd0;string_ch=(x-16)>>4;gx=x[3:0];gy=y-8;
            end
            if(x>=32 && x<48 && y>=8 && y<24) begin
                string_en=0;glyph=touch_digit({1'b0,mode}+4'd1);gx=x[3:0];gy=y-8;
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
            background=24'h142430;
            if(x>=16 && y>=300 && y<316) begin
                string_en=1;string_id=enabled?6'd2:6'd1;string_ch=(x-16)>>4;gx=x[3:0];gy=y-300;
            end
        end else begin
            row=geometry_row;
            if(row==255) background=24'h142430;
            else begin
                value=values[row*8+:8];relative_y=cy-touch_top(row);
                chosen=pressed!=255 && pressed[7:1]==row;
                if(x>=8 && x<472 && relative_y>=2 && relative_y<46) begin
                    background=24'h203440;
                    if(chosen && (x<10 || x>=470 || relative_y<4 || relative_y>=44)) background=24'h5cdce4;
                    if(chosen && x>=16 && x<=22 && relative_y>=18 && relative_y<=30 &&
                       (relative_y>=24?relative_y-24:24-relative_y)<=22-x) background=24'h5cdce4;
                end
                if(row==24) foreground=24'h80909c;
                if(relative_y>=16 && relative_y<32) begin
                    gy=relative_y-16;gx=x[3:0];
                    if(touch_step(row)!=0) begin
                        if(x>=368 && x<416) begin
                            char_no=(x-368)>>4;
                            glyph=touch_digit(char_no==0?value/100:(char_no==1?(value/10)%10:value%10));
                        end
                    end else if(x>=320 && x<464) begin
                        sid=30;
                        case(row)
                        6,7,9,10,15,17,21: sid=value==0?15:14;
                        11:sid=value==0?19:20;
                        12:sid=value==0?21:(value==1?22:23);
                        13,18:sid=value==0?16:(value==1?17:18);
                        14:sid=value==0?24:25;
                        16:sid=value==0?15:(value==1?14:32);
                        19:sid=12;20:sid=30;22:sid=value==0?27:26;23:sid=13;24:sid=29;
                        default:sid=30;
                        endcase

                        text_left=9'd392-({4'd0,touch_string_len(sid)}<<3);
                        if(row==24)text_left=328; // version + gap + diagnostics
                        if(x>=text_left)begin
                            string_en=1;string_id=sid;string_ch=(x-text_left)>>4;gx=x-text_left;
                        end
                        if(row==8)begin
                            string_en=0;gx=x-384;
                            if(x>=384 && x<400)glyph=touch_digit(value[3:0]);
                        end
                        if(row==24 && x>=400 && x<448) begin
                            string_en=0;gx=x[3:0];
                            glyph=touch_digit(x<416?value[3:0]:(x<432?{1'b0,value[6:4]}:{3'd0,value[7]}));
                        end
                    end
                end
                if(touch_step(row)!=0) begin
                    track_value=touch_slider_value(row,x);
                    if(x>=TOUCH_SLIDER_LEFT && x<=TOUCH_SLIDER_RIGHT) begin
                        if(relative_y>=38 && relative_y<42)
                            background=track_value<value?(enabled?24'h5cdce4:24'h80909c):24'h405868;
                        if(track_value>=value && {1'b0,track_value}<{1'b0,value}+{1'b0,touch_step(row)} && relative_y>=34 && relative_y<44)
                            background=enabled?24'h7ce0b0:24'h80909c;
                    end
                end else begin

                    case(row) 6,7,9,10,13,15,16,17,18,21:lamp=1;default:lamp=0;endcase
                    if(lamp && x>=300 && x<308 && relative_y>=20 && relative_y<28 &&
                       !((x==300 || x==307) && (relative_y==20 || relative_y==27))) begin
                        if(value!=0) background=enabled?24'h7ce0b0:24'h80909c;
                        else if(x<=301 || x>=306 || relative_y<=21 || relative_y>=26) background=24'ha4b8c4;
                    end
                end
            end
            if(x>=32 && x<192) begin
                string_en=0;glyph=touch_label(cy,(x-32)>>4);gx=x[3:0];gy=touch_label_y(cy);
            end
        end
    end

    reg [6:0] glyph_q,glyph_lookup;
    reg string_en_q;
    reg [5:0] string_id_q;
    reg [4:0] string_ch_q;
    wire [6:0] decoded_string=touch_string(string_id_q,string_ch_q);
    reg [3:0] gx_lookup,gy_lookup;
    reg [23:0] bg_lookup,fg_lookup;
    reg [3:0] gx_q,gy_q,gx_qq;
    reg [23:0] bg_q,fg_q,bg_qq,fg_qq;
    assign font_addr={glyph_lookup,gy_lookup};
    always @(posedge clk) begin
        glyph_q<=glyph;gx_q<=gx;gy_q<=gy;
        bg_q<=background;fg_q<=foreground;
        string_en_q<=string_en;string_id_q<=string_id;string_ch_q<=string_ch;
        glyph_lookup<=string_en_q?decoded_string:glyph_q;
        gx_lookup<=gx_q;gy_lookup<=gy_q;
        bg_lookup<=bg_q;fg_lookup<=fg_q;
        gx_qq<=gx_lookup;bg_qq<=bg_lookup;fg_qq<=fg_lookup;
        rgb<=font_bits[15-gx_qq]?fg_qq:bg_qq;
    end
endmodule

module touch_panel #(
    parameter CLK_HZ=50000000
)(
    input wire clk,rst_n,enabled,
    input wire [199:0] values,
    input wire [2:0] mode,
    output reg valid,
    input wire ready,
    output reg [2:0] target,
    output reg [3:0] field,
    output reg [7:0] value,
    output wire tft_cs_n,tft_reset_n,tft_dc,tft_mosi,tft_sck,
    output wire touch_cs_n,touch_mosi,touch_sck,
    input wire touch_miso,touch_irq_n
);
    `include "touch_layout.vh"

    wire raw_sample,raw_down;
    wire [11:0] raw_x,raw_y;
    touch_xpt2046 #(.CLK_HZ(CLK_HZ)) sampler(clk,rst_n,touch_irq_n,touch_miso,
        touch_sck,touch_mosi,touch_cs_n,raw_sample,raw_down,raw_x,raw_y);
    wire sample,down,cal_failed;
    wire [8:0] tx,ty;
    wire [2:0] cal_step;
    reg cal_start;
    wire settled,geometry_settled,initialized,begin_frame,click,dragging;
    reg draw_enabled;
    reg [2:0] draw_cal;
    touch_calibrate calibration(clk,rst_n,enabled,cal_start,raw_sample && (cal_step==0 || settled),raw_down,
        raw_x,raw_y,sample,down,tx,ty,cal_step,cal_failed);
    wire [10:0] scroll,draw_scroll;
    wire [8:0] px,py;
    reg calibrated;
    reg [2:0] previous_cal;
    wire [7:0] clicked,pressed;
    wire slider_update;
    wire [7:0] slider_id;
    wire [8:0] slider_x;
    reg pending_request;
    reg [2:0] pending_target;
    reg [3:0] pending_field;
    reg [7:0] pending_value;
    reg [7:0] hit;
    reg [7:0] row;
    reg [10:0] content_y;
    integer cell_no;
    always @* begin
        hit=255;row=255;content_y=0;cell_no=0;
        if(ty>=32 && ty<296) begin
            content_y=ty-32+draw_scroll;row=touch_row(content_y);
            if(row!=255 && tx>=8 && tx<472 && content_y-touch_top(row)>=4 && content_y-touch_top(row)<44) begin
                if(touch_step(row)==0 || tx>=TOUCH_SLIDER_LEFT) hit={row[6:0],1'b0};
            end
            if(row==24) hit=255;
        end
    end
    touch_gesture #(.MAX_SCROLL(TOUCH_HEIGHT-264)) gesture(clk,rst_n,
        enabled && calibrated && cal_step==0 && !cal_start,sample,down,
        geometry_settled && draw_cal==cal_step && draw_enabled==enabled,1'b1,
        tx,ty,hit,scroll,click,clicked,dragging,pressed,
        hit!=255 && touch_step(row)!=0,slider_update,slider_id,slider_x,!valid && !pending_request);
    reg [15:0] revision;
    reg [7:0] selected,draw_selected;
    reg [199:0] observed_values,draw_values;
    reg observed_enabled;
    reg [2:0] observed_mode,draw_mode;
    reg [2:0] observed_cal;
    reg [8:0] dirty_first,dirty_last;
    reg [8:0] changed_first,changed_last;
    reg [4:0] scan_id;
    reg [24:0] observed_selection;
    reg [24:0] pending_values;
    wire [24:0] changed_values;
    genvar value_index;
    generate for(value_index=0;value_index<25;value_index=value_index+1) begin: value_changes
        assign changed_values[value_index]=values[value_index*8+:8]!=observed_values[value_index*8+:8];
    end endgenerate
    wire selected_here=selected!=255 && selected[7:1]==scan_id;
    wire scan_changed=(pending_values[scan_id] || changed_values[scan_id]) ||
        selected_here!=observed_selection[scan_id];
    wire signed [12:0] dirty_y0=$signed({2'b0,touch_top({3'd0,scan_id})})+13'sd32-$signed({2'b0,scroll});
    wire signed [12:0] dirty_y1=dirty_y0+13'sd47;
    always @* begin
        changed_first=319;changed_last=0;
        if(scan_changed && dirty_y0<296 && dirty_y1>=32) begin
            changed_first=dirty_y0<32 ? 9'd32 : dirty_y0[8:0];
            changed_last=dirty_y1>295 ? 9'd295 : dirty_y1[8:0];
        end
        if(enabled!=observed_enabled || cal_step!=observed_cal || mode!=observed_mode) begin
            changed_first=0;changed_last=319;
        end
    end
    wire [7:0] control_id={1'b0,clicked[7:1]};
    wire [7:0] current_value=values[control_id*8+:8];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid<=0;target<=0;field<=0;value<=0;cal_start<=0;
            pending_request<=0;pending_target<=0;pending_field<=0;pending_value<=0;draw_selected<=255;
            calibrated<=0;previous_cal<=0;observed_mode<=0;draw_mode<=0;
            revision<=0;selected<=255;dirty_first<=0;dirty_last<=319;
            scan_id<=0;pending_values<=0;observed_selection<=0;observed_values<=0;observed_enabled<=0;observed_cal<=0;
            draw_values<=0;draw_enabled<=0;draw_cal<=0;
        end else begin
            cal_start<=0;previous_cal<=cal_step;
            if(enabled && !calibrated && cal_step==0 && !cal_start && previous_cal==0) cal_start<=1;
            if(enabled && previous_cal==5 && cal_step==0 && !cal_failed) calibrated<=1;
            if(!enabled) begin valid<=0;pending_request<=0;end
            else begin
                if(valid && ready) valid<=0;
                if((!valid || ready) && pending_request) begin
                    valid<=1;target<=pending_target;field<=pending_field;value<=pending_value;pending_request<=0;
                end

                if(slider_update && cal_step==0) begin
                    selected<=slider_id;pending_request<=1;
                    pending_target<=0;pending_field<={1'b0,slider_id[3:1]};
                    pending_value<=touch_slider_value({1'b0,slider_id[7:1]},slider_x);
                end
            end
            if(scan_changed || enabled!=observed_enabled || cal_step!=observed_cal || mode!=observed_mode)
                revision<=revision+1'b1;
            scan_id<=scan_id==24 ? 5'd0 : scan_id+1'b1;
            observed_values<=values;
            pending_values<=(pending_values | changed_values) & ~(25'b1<<scan_id);
            observed_selection[scan_id]<=selected_here;
            observed_enabled<=enabled;observed_cal<=cal_step;observed_mode<=mode;
            if(begin_frame)begin dirty_first<=changed_first;dirty_last<=changed_last;end
            else begin
                if(changed_first<dirty_first)dirty_first<=changed_first;
                if(changed_last>dirty_last)dirty_last<=changed_last;
            end
            if(begin_frame) begin
                draw_values<=values;draw_enabled<=enabled;draw_cal<=cal_step;draw_mode<=mode;draw_selected<=selected;
            end
            if(enabled && click && !valid && !pending_request && cal_step==0) begin
                selected<=clicked;
                if(touch_target(control_id)==5) begin
                    if(touch_field(control_id)==2) cal_start<=1;
                end else begin
                    pending_request<=1;pending_target<=touch_target(control_id);pending_field<=touch_field(control_id);
                    pending_value<=current_value>=touch_max(control_id)?touch_min(control_id):current_value+1'b1;
                end
            end
        end
    end
    wire [10:0] font_addr;
    wire [15:0] font_bits;
    wire [23:0] rgb;
    wire [15:0] unused_font;
    touch_font_rom font(clk,font_addr,font_bits,clk,11'd0,unused_font);
    touch_painter painter(clk,px,py,draw_scroll,draw_enabled,draw_values,
        draw_selected,draw_cal,draw_mode,font_addr,font_bits,rgb);
    touch_ili9488 #(.CLK_HZ(CLK_HZ)) display(clk,rst_n,scroll,revision,dirty_first,dirty_last,rgb,px,py,
        draw_scroll,begin_frame,settled,initialized,tft_cs_n,tft_reset_n,tft_dc,tft_mosi,tft_sck,geometry_settled);
endmodule

module touch_control_bus(
    input wire enabled, uart_busy, playback_ready,
    input wire valid,
    input wire [2:0] target,
    output wire ready,
    output wire base_wr, sub_wr, ad_wr, spectrum_wr, play_wr
);
    assign ready=enabled && !uart_busy && (target!=4 || playback_ready);
    wire accept=valid && ready;
    assign base_wr=accept && target==0;
    assign sub_wr=accept && target==1;
    assign ad_wr=accept && target==2;
    assign spectrum_wr=accept && target==3;
    assign play_wr=accept && target==4;
endmodule
