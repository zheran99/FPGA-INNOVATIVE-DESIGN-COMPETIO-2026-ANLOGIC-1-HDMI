`ifndef RING_GRADIENT_COLOR_VH
`define RING_GRADIENT_COLOR_VH

module ring_gradient_color(
    input wire clk,rst,vs,de,
    input wire [11:0] x,y,
    input wire [4:0] ad_id,
    input wire transition_active,
    output wire [23:0] color
);
    reg vs_q;
    reg [4:0] blank_delay;
    reg [4:0] current_ad;
    reg [9:0] palette_base;
    reg [6:0] rotation_phase;
    reg [10:0] rotation_accumulator;
    wire [11:0] rotation_sum={1'b0,rotation_accumulator}+12'd96;

    wire commit_blank=blank_delay==5'd1 && !de;
    wire [4:0] safe_ad=(ad_id>=1 && ad_id<=9) ? ad_id : 5'd1;
    function [9:0] base_of;
        input [4:0] id;
        begin
            case(id)
                2:base_of=96;3:base_of=192;4:base_of=288;
                5:base_of=384;6:base_of=480;7:base_of=576;
                8:base_of=672;9:base_of=768;default:base_of=0;
            endcase
        end
    endfunction
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            vs_q<=0;blank_delay<=0;current_ad<=1;palette_base<=0;
            rotation_phase<=0;rotation_accumulator<=0;
        end else begin
            vs_q<=vs;
            if(vs_q && !vs)blank_delay<=16;
            else if(blank_delay!=0)blank_delay<=blank_delay-1'b1;
            if(commit_blank)begin
                if(!transition_active && safe_ad!=current_ad)begin
                    current_ad<=safe_ad;palette_base<=base_of(safe_ad);
                    rotation_phase<=0;rotation_accumulator<=0;
                end else if(rotation_sum>=1212)begin
                    rotation_accumulator<=rotation_sum-12'd1212;
                    rotation_phase<=rotation_phase==95 ? 7'd0 : rotation_phase+1'b1;
                end else rotation_accumulator<=rotation_sum[10:0];
            end
        end
    end

    wire [8:0] local_x=x[8:0]-9'd384,local_y=y[8:0]-9'd104;
    wire [7:0] abs_x=local_x[8] ? local_x[7:0] : ~local_x[7:0];
    wire [7:0] abs_y=local_y[8] ? local_y[7:0] : ~local_y[7:0];
    wire [7:0] angle_q;
    reg [1:0] quadrant_q;
    ring_gradient_rom #(.AW(12),.DEPTH(4096),.KIND("32K"),
        .FILE("python/ring_angle.mif")) angle_rom(clk,{abs_y[7:2],abs_x[7:2]},angle_q);
    reg [6:0] circle_angle;
    always @*begin
        case(quadrant_q)
            2'b00:circle_angle=7'd47-{2'd0,angle_q[4:0]};
            2'b01:circle_angle=7'd48+{2'd0,angle_q[4:0]};
            2'b10:circle_angle={2'd0,angle_q[4:0]};
            default:circle_angle=7'd95-{2'd0,angle_q[4:0]};
        endcase
    end
    wire [7:0] angle_plus={1'b0,circle_angle}+
        (circle_angle<rotation_phase ? 8'd96 : 8'd0);
    wire [7:0] rotated_angle=angle_plus-{1'b0,rotation_phase};
    reg [9:0] palette_address;
    always @(posedge clk or posedge rst)begin
        if(rst)begin quadrant_q<=0;palette_address<=0;end
        else begin
            quadrant_q<={~local_y[8],~local_x[8]};
            palette_address<=palette_base+{2'd0,rotated_angle};
        end
    end
    ring_gradient_rom #(.FILE("python/ring_palette_r.mif")) red_rom(clk,palette_address,color[23:16]);
    ring_gradient_rom #(.FILE("python/ring_palette_g.mif")) green_rom(clk,palette_address,color[15:8]);
    ring_gradient_rom #(.FILE("python/ring_palette_b.mif")) blue_rom(clk,palette_address,color[7:0]);
endmodule

module ring_gradient_rom #(
    parameter AW=10,DEPTH=1024,KIND="9K",FILE=""
)(input wire clk,input wire [AW-1:0] address,output wire [7:0] data);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
        .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT(KIND),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE(FILE),.FILL_ALL("NONE")) mem(
        .dia(8'd0),.dib(8'd0),.addra(address),.addrb({AW{1'b0}}),.cea(1'b1),.ceb(1'b0),
        .wea(1'b0),.web(1'b0),.bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),
        .clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(data),.dob());
endmodule
`endif
