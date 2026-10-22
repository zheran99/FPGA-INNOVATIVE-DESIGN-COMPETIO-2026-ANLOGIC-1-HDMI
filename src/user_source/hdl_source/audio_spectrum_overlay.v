`timescale 1ns/1ps

module audio_spectrum_overlay (
    input wire I_clk, I_rst, I_sample_valid,
    input wire [23:0] I_sample_left,
    input wire I_en, I_de, I_hs, I_vs,
    input wire [23:0] I_rgb,
    output wire O_de, O_hs, O_vs,
    output wire O_debug_active, O_debug_bank,
    output reg [23:0] O_rgb,
    input wire I_horizontal
);
    reg horizontal;
    reg vs_prev, active, front_valid, ready;
    wire frame_start=I_vs && !vs_prev;
    wire fft_valid;
    wire [127:0] fft_levels;

    wire [127:0] filtered_levels=fft_levels;
    wire filtered_valid=fft_valid && active;
    wire clear_filter=frame_start && (!I_en || !active);
    genvar lane;
    reg [127:0] latest;
    reg [7:0] front [0:15];
    reg [7:0] pending_front [0:15];
    reg [127:0] envelope_targets;
    reg [3:0] envelope_lane;
    reg [15:0] envelope_select;
    reg [2:0] envelope_state;
    reg [7:0] envelope_current,envelope_target,envelope_next;
    wire start_envelope=frame_start && I_en && active && (ready || filtered_valid);
    function [7:0] smooth_height;
        input [7:0] current_height, target_height;
        reg [7:0] delta;
        begin
            if (target_height >= current_height) begin
                delta=target_height-current_height;
                smooth_height=delta>4 ? current_height+8'd4 : target_height;
            end else begin
                delta=current_height-target_height;
                smooth_height=delta>2 ? current_height-8'd2 : target_height;
            end
        end
    endfunction

    generate for(lane=0;lane<16;lane=lane+1) begin: envelope_banks
        always @(posedge I_clk or posedge I_rst) begin
            if(I_rst) begin front[lane]<=0;pending_front[lane]<=0;end
            else if(clear_filter) begin front[lane]<=0;pending_front[lane]<=0;end
            else begin
                if(envelope_state==3 && envelope_select[lane])pending_front[lane]<=envelope_next;
                if(envelope_state==4 && !start_envelope)front[lane]<=pending_front[lane];
            end
        end
    end endgenerate
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            envelope_state<=0;envelope_lane<=0;envelope_select<=0;envelope_targets<=0;
            envelope_current<=0;envelope_target<=0;envelope_next<=0;
        end else if(clear_filter) begin envelope_state<=0;envelope_select<=0;end
        else if(start_envelope) begin
            envelope_targets<=filtered_valid ? filtered_levels : latest;
            envelope_lane<=0;envelope_state<=1;
        end else case(envelope_state)
            1:begin
                envelope_current<=front[envelope_lane];envelope_target<=envelope_targets[envelope_lane*8+:8];
                envelope_select<=16'b1<<envelope_lane;envelope_state<=2;
            end
            2:begin envelope_next<=smooth_height(envelope_current,envelope_target);envelope_state<=3;end
            3:if(envelope_lane==15)envelope_state<=4;
              else begin envelope_lane<=envelope_lane+1'b1;envelope_state<=1;end
            4:envelope_state<=0;
            default:envelope_state<=0;
        endcase
    end
    audio_spectrum_fft u_fft(I_clk,I_rst,active,I_sample_valid,I_sample_left,fft_valid,fft_levels);
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            vs_prev<=0; active<=0; front_valid<=0; ready<=0; latest<=0; horizontal<=0;
        end else begin
            vs_prev<=I_vs;
            if (filtered_valid && active) begin latest<=filtered_levels; ready<=1; end
            if(envelope_state==4 && !start_envelope)front_valid<=1;
            if (frame_start) begin
                active<=I_en;
                horizontal<=I_horizontal;
                if (!I_en || !active) begin
                    front_valid<=0; ready<=0; latest<=0;
                end
            end
        end
    end
    assign O_debug_active=active;
    assign O_debug_bank=front_valid;
    wire [11:0] x,y;
    osd_position #(.H_ACTIVE(1280),.V_ACTIVE(720)) u_pos(
        .clk(I_clk),.rst(I_rst),.de(I_de),.vs(I_vs),.x(x),.y(y),.pos_vld()
    );

    wire [11:0] row_offset=y-12'd414;
    wire [11:0] column_offset=x-12'd10;
    wire in_box=I_de && active && (horizontal ?
        (x>=12 && x<93 && y>=414 && y<670) : (x<320 && y>=585 && y<675));

    wire bar_column=horizontal ? (row_offset[3:0]>=2 && row_offset[3:0]<14) :
                                (column_offset<256 && column_offset[3:0]>=2 && column_offset[3:0]<14);
    wire [3:0] column_index=horizontal ? row_offset[7:4] : column_offset[7:4];
    wire [11:0] distance=horizontal ? x-12'd12 : 12'd670-y;
    reg [2:0] de_d,hs_d,vs_d;
    reg [23:0] rgb1,rgb2;
    reg [11:0] y1,y2;
    reg box1,box2,col1,col2,valid1,valid2;
    reg [7:0] height1,height2;
    wire [3:0] bar_lane=horizontal ? row_offset[3:0] : column_offset[3:0];
    reg edge1,edge2;
    wire bar_hit=col2 && valid2 && height2!=0 && y2!=0 && y2<={4'b0,height2};
    wire tip_hit=y2=={4'b0,height2} || y2+12'd1=={4'b0,height2};
    wire [23:0] bar_color=tip_hit ? 24'hecfff8 :
        (edge2 || y2==1) ? 24'h244c50 :
        y2>60 ? 24'hb5ecd4 : y2>30 ? 24'h5ccebc : 24'h359fa5;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d<=0; hs_d<=0; vs_d<=0; rgb1<=0; rgb2<=0; O_rgb<=0;
            y1<=0; y2<=0; box1<=0; box2<=0; col1<=0; col2<=0;
            valid1<=0; valid2<=0; height1<=0; height2<=0;
            edge1<=0; edge2<=0;
        end else begin
            de_d<={de_d[1:0],I_de}; hs_d<={hs_d[1:0],I_hs}; vs_d<={vs_d[1:0],I_vs};
            rgb1<=I_rgb; rgb2<=rgb1; y1<=distance; y2<=y1;
            box1<=in_box; box2<=box1; col1<=bar_column; col2<=col1;
            valid1<=front_valid; valid2<=valid1;
            height1<=front[column_index]; height2<=height1;
            edge1<=bar_lane==2 || bar_lane==13; edge2<=edge1;
            if (!box2) O_rgb<=rgb2;
            else if (bar_hit) O_rgb<=bar_color;
            else if (y2==0 && col2) O_rgb<=24'h244c50;
            else O_rgb<=rgb2;
        end
    end
    assign O_de=de_d[2]; assign O_hs=hs_d[2]; assign O_vs=vs_d[2];
endmodule
