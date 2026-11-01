module ring_contour_launch(
    input wire clk,rst,start,cancel,sample_valid,finish,
    input wire [4:0] sample_band,sample_height,
    input wire signed [9:0] sample_x,sample_y,
    output reg done,
    output reg [1:0] count,
    output reg [29:0] launch_x,launch_y,
    output reg [14:0] launch_height
);

    reg [29:0] contour[0:31]; /* fehdl force_ram=1, ram_style="bram" */
    reg [29:0] contour_q;
    reg sample_pending,pending_seen,last_write_valid;
    reg [4:0] pending_band,pending_height,last_write_band;
    reg [19:0] pending_point;
    reg [29:0] last_write_data;
    reg [23:0] seen,history_valid;
    reg [4:0] scan;
    reg [3:0] state;
    reg [4:0] rank_band0,rank_band1,rank_band2;
    reg [1:0] fetch_slot;
    reg [4:0] h,left_h,right_h,old_h;
    reg old_valid,valid;
    reg [6:0] score0,score1,score2,rank_score;
    reg rank_eligible;
    wire [4:0] left_index=scan==0 ? 5'd23 : scan-5'd1;
    wire [4:0] right_index=scan==23 ? 5'd0 : scan+5'd1;
    wire [4:0] rise=old_valid && h>old_h ? h-old_h : 5'd0;
    wire [4:0] neighbour=left_h<right_h ? left_h : right_h;
    wire [4:0] prominence=h>neighbour ? h-neighbour : 5'd0;
    wire [6:0] score={2'd0,h}+{1'b0,rise,1'b0}+{2'd0,prominence};

    wire eligible=valid && h>=6 && h>left_h && h>=right_h;
    wire [4:0] winner_band=fetch_slot==0 ? rank_band0 : fetch_slot==1 ? rank_band1 : rank_band2;
    wire [4:0] read_address=state==8 ? winner_band : state==2 ? left_index : state==3 ? scan :
        state==4 ? right_index : sample_band;

    wire [29:0] compare_data=last_write_valid && last_write_band==pending_band ?
        last_write_data : contour_q;

    wire [29:0] sample_data={pending_seen ? compare_data[29:25] :
        compare_data[24:20],pending_height,pending_point};
    wire write_sample=sample_pending && (!pending_seen || pending_height>compare_data[24:20]);
    always @(posedge clk)begin
        contour_q<=contour[read_address];
        if(!rst && !cancel && !start && write_sample)
            contour[pending_band]<=sample_data;
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            seen<=0;history_valid<=0;state<=0;scan<=0;done<=0;count<=0;
            launch_x<=0;launch_y<=0;launch_height<=0;
            h<=0;left_h<=0;right_h<=0;old_h<=0;old_valid<=0;valid<=0;rank_band0<=0;rank_band1<=0;rank_band2<=0;fetch_slot<=0;
            score0<=0;score1<=0;score2<=0;rank_score<=0;rank_eligible<=0;
            sample_pending<=0;pending_seen<=0;pending_band<=0;pending_height<=0;pending_point<=0;
            last_write_valid<=0;last_write_band<=0;last_write_data<=0;
        end else begin
            done<=0;
            sample_pending<=!cancel && !start && state==0 && sample_valid && sample_band<24;
            if(state==0 && sample_valid && sample_band<24)begin
                pending_seen<=seen[sample_band];pending_band<=sample_band;
                pending_height<=sample_height;pending_point<={sample_x,sample_y};
            end
            if(write_sample)begin
                last_write_valid<=1;last_write_band<=pending_band;
                last_write_data<=sample_data;
            end
            if(cancel)begin
                seen<=0;history_valid<=0;state<=0;count<=0;last_write_valid<=0;
            end else if(start)begin
                seen<=0;state<=0;count<=0;last_write_valid<=0;score0<=0;score1<=0;score2<=0;
                launch_x<=0;launch_y<=0;launch_height<=0;
            end else case(state)
                0:begin
                    if(sample_valid && sample_band<24)seen[sample_band]<=1;
                    if(finish)begin scan<=0;state<=1;end
                end

                1:state<=2;
                2:state<=3;
                3:begin left_h<=contour_q[24:20];state<=4;end
                4:begin h<=contour_q[24:20];old_h<=contour_q[29:25];state<=5;end
                5:begin
                    right_h<=contour_q[24:20];
                    old_valid<=history_valid[scan];
                    valid<=seen[scan] && seen[left_index] && seen[right_index];state<=6;
                end

                6:begin
                    history_valid[scan]<=seen[scan];
                    rank_score<=score;rank_eligible<=eligible;state<=7;
                end
                7:begin
                    if(rank_eligible)begin
                        if(count<3)count<=count+2'd1;
                        if(count==0 || rank_score>score0)begin
                            score2<=score1;score1<=score0;score0<=rank_score;
                            rank_band2<=rank_band1;rank_band1<=rank_band0;rank_band0<=scan;
                        end else if(count==1 || rank_score>score1)begin
                            score2<=score1;score1<=rank_score;
                            rank_band2<=rank_band1;rank_band1<=scan;
                        end else if(count==2 || rank_score>score2)begin
                            score2<=rank_score;rank_band2<=scan;
                        end
                    end
                    if(scan==23)begin fetch_slot<=0;state<=8;end
                    else begin scan<=scan+5'd1;state<=2;end
                end

                8:state<=9;
                9:begin
                    if(fetch_slot<count)case(fetch_slot)
                        0:begin launch_x[9:0]<=contour_q[19:10];launch_y[9:0]<=contour_q[9:0];launch_height[4:0]<=contour_q[24:20];end
                        1:begin launch_x[19:10]<=contour_q[19:10];launch_y[19:10]<=contour_q[9:0];launch_height[9:5]<=contour_q[24:20];end
                        2:begin launch_x[29:20]<=contour_q[19:10];launch_y[29:20]<=contour_q[9:0];launch_height[14:10]<=contour_q[24:20];end
                    endcase
                    if(fetch_slot==2)begin done<=1;state<=0;end
                    else begin fetch_slot<=fetch_slot+1'b1;state<=8;end
                end
                default:state<=0;
            endcase
        end
    end
endmodule
