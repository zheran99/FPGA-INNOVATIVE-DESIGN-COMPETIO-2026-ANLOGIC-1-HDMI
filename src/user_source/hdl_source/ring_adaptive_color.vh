module ring_adaptive_color(
    input wire clk,rst,frame_start,de,
    input wire [11:0] x,y,
    input wire [23:0] rgb,
    output reg [23:0] color
);

    wire sample_point=de && x>=12'd384 && x<12'd896 &&
        y>=12'd104 && y<12'd616 && x[5:0]==6'd32 && y[5:0]==6'd8;
    reg [9:0] red_sum,green_sum,blue_sum;
    reg [6:0] sample_count;
    reg [3:0] red_mean,green_mean,blue_mean;
    reg apply_pending,dark_ink;

    wire [6:0] red_blue={2'b00,red_mean,1'b0}+{3'b000,blue_mean};
    wire [6:0] green_five={1'b0,green_mean,2'b00}+{3'b000,green_mean};
    wire [6:0] luma=red_blue+green_five;

    wire next_dark=luma>=7'd72 ? 1'b1 : luma<=7'd48 ? 1'b0 : dark_ink;
    wire [3:0] opposite_red=~red_mean,opposite_green=~green_mean,opposite_blue=~blue_mean;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            red_sum<=0;green_sum<=0;blue_sum<=0;sample_count<=0;
            red_mean<=0;green_mean<=0;blue_mean<=0;
            apply_pending<=0;dark_ink<=0;color<=24'hffffff;
        end else begin
            apply_pending<=frame_start && sample_count==7'd64;
            if(frame_start)begin

                if(sample_count==7'd64)begin
                    red_mean<=red_sum[9:6];green_mean<=green_sum[9:6];blue_mean<=blue_sum[9:6];
                end
                red_sum<=0;green_sum<=0;blue_sum<=0;sample_count<=0;
            end else if(sample_point && sample_count<7'd64)begin
                red_sum<=red_sum+{6'd0,rgb[23:20]};
                green_sum<=green_sum+{6'd0,rgb[15:12]};
                blue_sum<=blue_sum+{6'd0,rgb[7:4]};
                sample_count<=sample_count+1'b1;
            end
            if(apply_pending)begin
                dark_ink<=next_dark;

                color<=next_dark ? {2'b00,opposite_red,2'b00,2'b00,opposite_green,2'b00,2'b00,opposite_blue,2'b00} :
                                  {2'b11,opposite_red,2'b11,2'b11,opposite_green,2'b11,2'b11,opposite_blue,2'b11};
            end
        end
    end
endmodule
