`timescale 1ns/1ps

`include "audio_ring_filter.vh"
`include "ring_gradient_color.vh"
`include "ring_emergence.vh"
`include "ring_contour_launch.vh"
module audio_spectrum_overlay #(

    parameter integer CONE_REST_GAP=2
)(
    input wire I_clk,I_rst,I_sample_valid,
    input wire [23:0] I_sample_left,
    input wire I_en,I_de,I_hs,I_vs,
    input wire [23:0] I_rgb,
    output wire O_de,O_hs,O_vs,O_debug_active,O_debug_bank,
    output reg [23:0] O_rgb,
    input wire I_horizontal,
    input wire [1:0] I_shape,
    input wire [4:0] I_ad_id,
    input wire I_transition_active
);
`include "ring_shape_tables.vh"
    localparam IDLE=0,CLEAR=1,LOAD=2,LOBE_SET=3,MUL_WAIT=4,LOBE_USE=5,
               BRIDGE_SET=6,BRIDGE_USE=7,TRIG_WAIT=8,COORD_SET=9,COORD_USE=10,
               LINE_START=11,ROW_WAIT=12,ROW_USE=13,MASK_WAIT=14,MASK_WRITE=15,
               LINE_DONE=16,ADVANCE=17,FINISH=18,LOBE_READ=19,LINE_ERROR=20,LOBE_FETCH=21,GAP_SET=22,BRUSH_NEXT=23,LAUNCH_WAIT=24,LINE_DELTA=25,LINE_STEP=26;
    reg [4:0] state,after_multiply;
    reg vs_previous,active,horizontal,front_valid,front_bank,render_bank,pending;
    reg [1:0] shape_active;
    wire frame_start=I_vs && !vs_previous;
    wire cancel=frame_start && (!I_en || !active);
    wire filter_busy,filter_initialized,filter_overrun;
    reg [1:0] lobe_index,coordinate_index,line_kind;
    wire snapshot_request=state==IDLE && frame_start && I_en && active && filter_initialized && !cancel;
    reg [4:0] snapshot_band;
    wire [4:0] snapshot_index=lobe_index==0 ? (snapshot_band==0 ? 5'd23 : snapshot_band-1'b1) :
        lobe_index==1 ? snapshot_band :
        lobe_index==2 ? (snapshot_band==23 ? 5'd0 : snapshot_band+1'b1) :
                       (snapshot_band>=22 ? snapshot_band-5'd22 : snapshot_band+5'd2);
    wire [4:0] lobe_height;
    reg [4:0] lobe_height_q;
    wire [11:0] lobe_slope_q;
    audio_ring_filter analyzer(.clk(I_clk),.rst(I_rst),.en(1'b1),.sample_valid(I_sample_valid),.sample_left(I_sample_left),
        .levels(),.busy(filter_busy),.overrun(filter_overrun),.initialized(filter_initialized),
        .shape_height(lobe_height),.shape_slope(lobe_slope_q),
        .snapshot_request(snapshot_request),.snapshot_index(snapshot_index),.snapshot_height(lobe_height));
    reg [10:0] angle_index;
    reg [8:0] phase;
    wire [8:0] phase_advance = {1'b0,phase[7:0]} +
                               (shape_active==0 ? 9'd3 : 9'd48);
    reg [5:0] segment_step;

    reg [1:0] brush_column,brush_row;
    reg brush_probe,brush_valid,brush_vertical,brush_negative;
    reg [4:0] maximum_height,half_gap;
    reg [4:0] final_height_q;
    reg [4:0] render_peak,pending_peak;
    reg [9:0] render_energy,pending_energy;
    reg [4:0] energy_band;
    wire launch_done;
    wire [1:0] launch_count;
    wire [29:0] launch_x,launch_y;
    wire [14:0] launch_height;
    reg [1:0] pending_launch_count;
    reg [29:0] pending_launch_x,pending_launch_y;
    reg [14:0] pending_launch_height;
    reg signed [9:0] launch_tip_x,launch_tip_y;
    reg launch_tip_valid;

    reg signed [17:0] multiply_a,multiply_b;
    reg signed [35:0] multiply_result;
    always @(posedge I_clk)multiply_result<=multiply_a*multiply_b;

    reg [4:0] h_current,h_next;
    reg [9:0] lobe_distance;
    always @*begin
        case(lobe_index)
            0:lobe_distance=10'd256+{1'b0,phase};
            1:lobe_distance={1'b0,phase};
            2:lobe_distance=10'd256-{1'b0,phase};
            default:lobe_distance=10'd512-{1'b0,phase};
        endcase
    end
    wire [17:0] lobe_peak={1'b0,lobe_height_q,12'd0};
    wire [17:0] lobe_difference=lobe_peak-multiply_result[17:0];
    wire [4:0] lobe_value=multiply_result>=lobe_peak ? 5'd0 : lobe_difference[16:12];
    wire [4:0] valley=(h_current<h_next ? h_current : h_next)>>1;
    wire bridge_active=h_current>1 && h_next>1;
    wire signed [17:0] bridge_delta=phase<128 ?
        $signed({13'd0,valley})-$signed({13'd0,h_current}) :
        $signed({13'd0,h_next})-$signed({13'd0,valley});
    wire signed [35:0] bridge_height=$signed({31'd0,(phase<128 ? h_current : valley)})+(multiply_result>>>7);
    wire [4:0] final_height=(bridge_active && bridge_height>$signed({31'd0,maximum_height})) ?
                                bridge_height[4:0] : maximum_height;

    wire [8:0] trig_offset=angle_index[8:0];
    wire [8:0] trig_complement=9'd0-trig_offset;
    wire [15:0] sine_low,sine_high;
    ring_sine_rom trig(I_clk,trig_offset,sine_low,trig_complement,sine_high);
    wire [15:0] complement_value=trig_offset==0 ? 16'h8000 : sine_high;
    wire [15:0] sine=angle_index[9] ? complement_value : sine_low;
    wire [15:0] cosine=angle_index[9] ? sine_low : complement_value;
    wire x_negative=angle_index[10];
    wire y_negative=!(angle_index[10]^angle_index[9]);
    reg signed [9:0] inner_x,inner_y,outer_x,outer_y;
    reg signed [9:0] previous_inner_x,previous_inner_y,previous_outer_x,previous_outer_y;
    reg signed [9:0] first_inner_x,first_inner_y,first_outer_x,first_outer_y;
    reg closing;

    wire outward_only=shape_active==2'd1 || shape_active==2'd3;

    wire [4:0] inner_gap=(CONE_REST_GAP==1 && shape_active==2'd0) ?
        half_gap-5'd1 : half_gap;
    wire [7:0] radius=coordinate_index[1] ? 8'd168+{3'd0,half_gap} :
                      outward_only ? 8'd168 : 8'd168-{3'd0,inner_gap};
    wire coordinate_negative=coordinate_index[0] ? y_negative : x_negative;
    wire signed [9:0] coordinate_integer=coordinate_negative ?
        -10'sd1-$signed({2'b0,multiply_result[22:15]}) : $signed({2'b0,multiply_result[22:15]});

    reg signed [9:0] line_x,line_y,end_x,end_y;
    reg [8:0] dx,dy;
    reg sx,sy;
    reg signed [10:0] error;

    reg signed [9:0] negative_dy;
    reg signed [10:0] diagonal_stride;
    function [4:0] visible_gap;
        input [4:0] height;
        input [1:0] shape_code;
        begin

            if(shape_code==2'd0)
                visible_gap=height>=5'd28 ? 5'd29 : height+5'd1;
            else
                visible_gap=height>=5'd25 ? 5'd29 : height+5'd4;
        end
    endfunction
    reg signed [9:0] line_start_x,line_start_y,line_end_x,line_end_y;
    always @*begin
        if(line_kind==0)begin
            line_start_x=angle_index==0 && !closing ? inner_x : previous_inner_x;
            line_start_y=angle_index==0 && !closing ? inner_y : previous_inner_y;
            line_end_x=closing ? first_inner_x : inner_x;
            line_end_y=closing ? first_inner_y : inner_y;
        end else if(line_kind==1)begin
            line_start_x=angle_index==0 && !closing ? outer_x : previous_outer_x;
            line_start_y=angle_index==0 && !closing ? outer_y : previous_outer_y;
            line_end_x=closing ? first_outer_x : outer_x;
            line_end_y=closing ? first_outer_y : outer_y;
        end else begin
            line_start_x=inner_x;line_start_y=inner_y;
            line_end_x=outer_x;line_end_y=outer_y;
        end
    end
    wire [8:0] new_dx=end_x>=line_x ? end_x-line_x : line_x-end_x;
    wire [8:0] new_dy=end_y>=line_y ? end_y-line_y : line_y-end_y;
    wire signed [11:0] twice_error={error,1'b0};
    wire step_x=twice_error> $signed(negative_dy);
    wire step_y=twice_error< $signed({3'd0,dx});
    wire signed [10:0] error_stride=step_x ?
        (step_y ? diagonal_stride : $signed({negative_dy[9],negative_dy})) :
        (step_y ? $signed({2'd0,dx}) : 11'sd0);

    reg step_x_q,step_y_q;
    wire signed [10:0] error_stride_q=step_x_q ?
        (step_y_q ? diagonal_stride : $signed({negative_dy[9],negative_dy})) :
        (step_y_q ? $signed({2'd0,dx}) : 11'sd0);
    wire lamp_shape=shape_active==2'd3;
    wire stroke_shape=shape_active==2'd1 || shape_active==2'd2;
    wire signed [9:0] brush_shift=brush_negative ? -10'sd1 : 10'sd1;
    wire signed [9:0] brush_dx=lamp_shape ? $signed({8'd0,brush_column}) :
        (stroke_shape && brush_column[0] && !brush_vertical ? brush_shift : 10'sd0);
    wire signed [9:0] brush_dy=lamp_shape ? $signed({8'd0,brush_row}) :
        (stroke_shape && brush_column[0] && brush_vertical ? brush_shift : 10'sd0);
    wire signed [9:0] brush_x=line_x+brush_dx,brush_y=line_y+brush_dy;
    wire [7:0] paint_x=brush_x[9] ? ~brush_x[7:0] : brush_x[7:0];
    wire [7:0] paint_y=brush_y[9] ? ~brush_y[7:0] : brush_y[7:0];
    wire [1:0] paint_quadrant={brush_y[9],brush_x[9]};
    wire paint_in_bounds=row_hi[15] && paint_x>=row_lo[7:0] && paint_x<=row_lo[15:8];
    wire brush_last=brush_column==2 && brush_row==2;
    wire [15:0] row_lo,row_hi,video_row_lo,video_row_hi;
    wire [7:0] video_y;
    ring_row_rom #(.FILE("python/ring_rows_lo.mif")) rows_lo(I_clk,paint_y,row_lo,video_y,video_row_lo);
    ring_row_rom #(.FILE("python/ring_rows_hi.mif")) rows_hi(I_clk,paint_y,row_hi,video_y,video_row_hi);
    wire [13:0] paint_bit_address=row_hi[13:0]+{6'd0,paint_x};
    reg [11:0] mask_address;
    reg [2:0] paint_bit;
    reg [1:0] paint_quadrant_saved;
    reg [10:0] clear_address;
    wire [11:0] write_address=state==CLEAR ? {render_bank,clear_address} : mask_address;
    wire [7:0] paint_bytes[0:3];
    wire [7:0] video_bytes[0:3];
    wire [7:0] paint_byte=paint_bytes[paint_quadrant_saved];
    wire [7:0] write_data=state==CLEAR ? 8'd0 : paint_byte|(8'd1<<paint_bit);
    wire [11:0] video_address;
    genvar q;
    generate for(q=0;q<4;q=q+1)begin:masks
        wire we=!I_rst && !cancel && (state==CLEAR || (state==MASK_WRITE && paint_quadrant_saved==q));
        ring_mask_ram ram(I_clk,we,write_address,write_data,paint_bytes[q],video_address,video_bytes[q]);
    end endgenerate

    ring_contour_launch launch_selector(.clk(I_clk),.rst(I_rst),
        .start(snapshot_request),.cancel(cancel),
        .sample_valid(state==ADVANCE && !closing && launch_tip_valid),.finish(state==FINISH),
        .sample_band(snapshot_band),.sample_height(half_gap),.sample_x(launch_tip_x),.sample_y(launch_tip_y),
        .done(launch_done),.count(launch_count),.launch_x(launch_x),.launch_y(launch_y),
        .launch_height(launch_height));
    always @(posedge I_clk or posedge I_rst)begin
        if(I_rst)begin
            state<=IDLE;after_multiply<=IDLE;vs_previous<=0;active<=0;horizontal<=0;shape_active<=0;
            front_valid<=0;front_bank<=0;render_bank<=1;pending<=0;snapshot_band<=0;h_current<=0;h_next<=0;
            angle_index<=0;phase<=0;lobe_index<=0;coordinate_index<=0;line_kind<=0;segment_step<=0;
            brush_column<=0;brush_row<=0;brush_probe<=0;brush_valid<=1;brush_vertical<=0;brush_negative<=0;
            lobe_height_q<=0;maximum_height<=0;half_gap<=5'd1;final_height_q<=0;multiply_a<=0;multiply_b<=0;
            render_peak<=0;pending_peak<=0;
            render_energy<=0;pending_energy<=0;energy_band<=31;
            pending_launch_count<=0;pending_launch_x<=0;pending_launch_y<=0;pending_launch_height<=0;
            launch_tip_x<=0;launch_tip_y<=0;launch_tip_valid<=0;
            inner_x<=0;inner_y<=0;outer_x<=0;outer_y<=0;
            previous_inner_x<=0;previous_inner_y<=0;previous_outer_x<=0;previous_outer_y<=0;
            first_inner_x<=0;first_inner_y<=0;first_outer_x<=0;first_outer_y<=0;
            closing<=0;line_x<=0;line_y<=0;end_x<=0;end_y<=0;dx<=0;dy<=0;sx<=0;sy<=0;error<=0;negative_dy<=0;diagonal_stride<=0;step_x_q<=0;step_y_q<=0;
            mask_address<=0;paint_bit<=0;paint_quadrant_saved<=0;clear_address<=0;
        end else begin
            vs_previous<=I_vs;
            if(frame_start)begin
                active<=I_en;horizontal<=I_horizontal;
                if(pending && I_en && active)begin front_bank<=render_bank;front_valid<=1;pending<=0;end
            end
            case(state)
                IDLE:if(frame_start && I_en && active && filter_initialized)begin
                    shape_active<=I_shape;
                    render_peak<=0;
                    render_energy<=0;energy_band<=31;
                    render_bank<=pending ? front_bank : ~front_bank;
                    clear_address<=0;state<=CLEAR;
                end
                CLEAR:if(clear_address==2047)begin
                    angle_index<=0;phase<=0;snapshot_band<=0;closing<=0;state<=LOAD;
                end else clear_address<=clear_address+1'b1;

                LOAD:begin
                    launch_tip_valid<=0;
                    lobe_index<=shape_active==2'd1 ? 2'd1 : 2'd0;
                    maximum_height<=0;state<=LOBE_FETCH;
                end
                LOBE_FETCH:state<=LOBE_READ;
                LOBE_READ:begin lobe_height_q<=lobe_height;state<=LOBE_SET;end
                LOBE_SET:begin
                    if(lobe_height_q>render_peak)render_peak<=lobe_height_q;
                    if(lobe_index==1 && energy_band!=snapshot_band)begin
                        render_energy<=render_energy+{5'd0,lobe_height_q};
                        energy_band<=snapshot_band;
                    end
                    if(shape_active==2'd1)begin

                        half_gap<=visible_gap(lobe_height_q,shape_active);coordinate_index<=0;state<=TRIG_WAIT;
                    end else begin
                        if(lobe_index==1)h_current<=lobe_height_q;
                        if(lobe_index==2)h_next<=lobe_height_q;
                        multiply_a<={8'd0,lobe_distance};multiply_b<={6'd0,lobe_slope_q};
                        after_multiply<=LOBE_USE;state<=MUL_WAIT;
                    end
                end
                MUL_WAIT:state<=after_multiply;
                LOBE_USE:begin
                    if(lobe_value>maximum_height)maximum_height<=lobe_value;
                    if(lobe_index==3)state<=BRIDGE_SET;
                    else begin lobe_index<=lobe_index+1'b1;state<=LOBE_FETCH;end
                end
                BRIDGE_SET:begin
                    multiply_a<=bridge_delta;multiply_b<={11'd0,phase[6:0]};
                    after_multiply<=BRIDGE_USE;state<=MUL_WAIT;
                end

                BRIDGE_USE:begin final_height_q<=final_height;state<=GAP_SET;end
                GAP_SET:begin half_gap<=visible_gap(final_height_q,shape_active);coordinate_index<=0;state<=TRIG_WAIT;end
                TRIG_WAIT:state<=COORD_SET;
                COORD_SET:begin
                    multiply_a<={10'd0,radius};multiply_b<={2'd0,(coordinate_index[0] ? cosine : sine)};
                    after_multiply<=COORD_USE;state<=MUL_WAIT;
                end
                COORD_USE:begin
                    case(coordinate_index)
                        0:inner_x<=coordinate_integer;1:inner_y<=coordinate_integer;
                        2:outer_x<=coordinate_integer;3:outer_y<=coordinate_integer;
                    endcase
                    if(coordinate_index==3)begin
                        line_kind<=shape_active==0 ? 2'd0 : 2'd2;
                        state<=LINE_START;
                    end
                    else begin coordinate_index<=coordinate_index+1'b1;state<=COORD_SET;end
                end
                LINE_START:begin
                    line_x<=line_start_x;line_y<=line_start_y;end_x<=line_end_x;end_y<=line_end_y;
                    segment_step<=0;
                    brush_column<=0;brush_row<=0;brush_probe<=lamp_shape;brush_valid<=1;
                    state<=LINE_DELTA;
                end
                LINE_DELTA:begin

                    dx<=new_dx;dy<=new_dy;sx<=end_x>line_x;sy<=end_y>line_y;
                    state<=LINE_ERROR;
                end
                LINE_ERROR:begin

                    brush_vertical<=dx>=dy;
                    brush_negative<=dx>=dy ? end_x[9] : !end_y[9];
                    error<=$signed({2'd0,dx})-$signed({2'd0,dy});
                    diagonal_stride<=$signed({2'd0,dx})-$signed({2'd0,dy});
                    negative_dy<=-$signed({1'b0,dy});state<=ROW_WAIT;
                end
                ROW_WAIT:state<=ROW_USE;
                ROW_USE:begin
                    if(lamp_shape && segment_step[1:0]!=0)state<=LINE_DONE;
                    else if(lamp_shape && brush_probe)begin
                        brush_valid<=brush_valid && paint_in_bounds;
                        if(brush_last)begin
                            brush_column<=0;brush_row<=0;brush_probe<=0;
                            state<=brush_valid && paint_in_bounds ? ROW_WAIT : LINE_DONE;
                        end else begin
                            if(brush_column==2)begin brush_column<=0;brush_row<=brush_row+1'b1;end
                            else brush_column<=brush_column+1'b1;
                            state<=ROW_WAIT;
                        end
                    end else if(paint_in_bounds)begin
                        mask_address<={render_bank,paint_bit_address[13:3]};paint_bit<=paint_bit_address[2:0];
                        paint_quadrant_saved<=paint_quadrant;state<=MASK_WAIT;
                    end else state<=BRUSH_NEXT;
                end
                MASK_WAIT:state<=MASK_WRITE;
                MASK_WRITE:begin

                    if(line_kind!=0)begin
                        launch_tip_x<=brush_x;launch_tip_y<=brush_y;launch_tip_valid<=1;
                    end
                    state<=shape_active==0 ? LINE_DONE : BRUSH_NEXT;
                end
                BRUSH_NEXT:begin
                    if(lamp_shape)begin
                        if(brush_last)state<=LINE_DONE;
                        else begin
                            if(brush_column==2)begin brush_column<=0;brush_row<=brush_row+1'b1;end
                            else brush_column<=brush_column+1'b1;
                            state<=ROW_WAIT;
                        end
                    end else if(stroke_shape && !brush_column[0])begin
                        brush_column<=1;state<=ROW_WAIT;
                    end else state<=LINE_DONE;
                end
                LINE_DONE:if(line_x==end_x && line_y==end_y)begin
                    if(line_kind==0)begin line_kind<=1;state<=LINE_START;end
                    else if(line_kind==1 && !closing && angle_index[3:0]==0)begin line_kind<=2;state<=LINE_START;end
                    else state<=ADVANCE;
                end else begin
                    step_x_q<=step_x;step_y_q<=step_y;
                    state<=LINE_STEP;
                end
                LINE_STEP:begin
                    if(step_x_q)line_x<=sx ? line_x+1'b1 : line_x-1'b1;
                    if(step_y_q)line_y<=sy ? line_y+1'b1 : line_y-1'b1;
                    brush_column<=0;brush_row<=0;brush_probe<=lamp_shape;brush_valid<=1;
                    segment_step<=segment_step+1'b1;
                    error<=error+error_stride_q;
                    state<=ROW_WAIT;
                end
                ADVANCE:begin
                    previous_inner_x<=inner_x;previous_inner_y<=inner_y;
                    previous_outer_x<=outer_x;previous_outer_y<=outer_y;
                    if(angle_index==0)begin
                        first_inner_x<=inner_x;first_inner_y<=inner_y;first_outer_x<=outer_x;first_outer_y<=outer_y;
                    end
                    if(closing || (shape_active!=0 && angle_index==11'd2032))state<=FINISH;
                    else if(angle_index==2047)begin closing<=1;line_kind<=0;state<=LINE_START;end
                    else begin
                        angle_index<=angle_index+(shape_active==0 ? 11'd1 : 11'd16);
                        phase<={1'b0,phase_advance[7:0]};
                        if(phase_advance[8])snapshot_band<=snapshot_band==23 ? 5'd0 : snapshot_band+1'b1;
                        state<=LOAD;
                    end
                end
                FINISH:state<=LAUNCH_WAIT;
                LAUNCH_WAIT:if(launch_done)begin
                    pending<=1;pending_peak<=render_peak;pending_energy<=render_energy;
                    pending_launch_count<=launch_count;pending_launch_x<=launch_x;pending_launch_y<=launch_y;
                    pending_launch_height<=launch_height;state<=IDLE;
                end
                default:state<=IDLE;
            endcase

            if(cancel)begin state<=IDLE;front_valid<=0;pending<=0;end
        end
    end
    assign O_debug_active=active;
    assign O_debug_bank=front_valid;
    wire [11:0] x,y;
    osd_position position(.clk(I_clk),.rst(I_rst),.de(I_de),.vs(I_vs),.x(x),.y(y),.pos_vld());
    wire [23:0] ring_color;
    wire emergence_hit;
    ring_emergence emergence(.clk(I_clk),.rst(I_rst),.frame_start(frame_start),
        .en(I_en && active),.publish(pending),.peak(pending_peak),.energy(pending_energy),.de(I_de),
        .launch_count(pending_launch_count),.launch_x(pending_launch_x),
        .launch_y(pending_launch_y),.launch_height(pending_launch_height),
        .x(x),.y(y),.hit(emergence_hit));
    ring_gradient_color gradient(.clk(I_clk),.rst(I_rst),.vs(I_vs),.de(I_de),
        .x(x),.y(y),.ad_id(I_ad_id),.transition_active(I_transition_active),.color(ring_color));
    wire [8:0] lx=x[8:0]-9'd384,ly=y[8:0]-9'd104;
    wire [7:0] folded_x=lx[8] ? lx[7:0] : ~lx[7:0];
    wire [7:0] folded_y=ly[8] ? ly[7:0] : ~ly[7:0];
    wire [7:0] video_x=horizontal ? folded_y : folded_x;
    assign video_y=horizontal ? folded_x : folded_y;
    wire [1:0] video_quadrant=horizontal ? {lx[8],~ly[8]} : {~ly[8],~lx[8]};
    reg [7:0] video_x1;
    reg box1,box2,bank1,bank2;
    reg [1:0] quadrant1,quadrant2;
    reg [2:0] bit2;
    reg [3:0] de_pipe,hs_pipe,vs_pipe;
    reg [23:0] rgb1,rgb2,rgb3;
    reg display3;
    wire [13:0] video_bit_address=video_row_hi[13:0]+{6'd0,video_x1};
    assign video_address={bank1,video_bit_address[13:3]};
    wire [7:0] display_byte=video_bytes[quadrant2];
    always @(posedge I_clk or posedge I_rst)begin
        if(I_rst)begin
            video_x1<=0;box1<=0;box2<=0;bank1<=0;bank2<=0;quadrant1<=0;quadrant2<=0;
            bit2<=0;rgb1<=0;rgb2<=0;rgb3<=0;display3<=0;O_rgb<=0;
            de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
        end else begin
            de_pipe<={de_pipe[2:0],I_de};hs_pipe<={hs_pipe[2:0],I_hs};vs_pipe<={vs_pipe[2:0],I_vs};
            rgb1<=I_rgb;rgb2<=rgb1;rgb3<=rgb2;video_x1<=video_x;
            box1<=I_de && active && front_valid && x>=384 && x<896 && y>=104 && y<616;
            box2<=box1 && video_row_hi[15] && video_x1>=video_row_lo[7:0] && video_x1<=video_row_lo[15:8];
            quadrant1<=video_quadrant;quadrant2<=quadrant1;bank1<=front_bank;bank2<=bank1;
            bit2<=video_bit_address[2:0];
            display3<=box2 && display_byte[bit2];
            O_rgb<=(display3 || emergence_hit) ? ring_color : rgb3;
        end
    end
    assign O_de=de_pipe[3];assign O_hs=hs_pipe[3];assign O_vs=vs_pipe[3];
endmodule

module ring_row_rom #(parameter FILE="")(
    input wire clk,input wire [7:0] a,output wire [15:0] q,input wire [7:0] b,output wire [15:0] r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(256),.DATA_DEPTH_B(256),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE(FILE),.FILL_ALL("NONE")) mem(
        .dia(16'd0),.dib(16'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(1'b0),.web(1'b0),
        .bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
module ring_sine_rom(input wire clk,input wire [8:0] a,output wire [15:0] q,
                     input wire [8:0] b,output wire [15:0] r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("python/ring_sine.mif"),.FILL_ALL("NONE")) mem(
        .dia(16'd0),.dib(16'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(1'b0),.web(1'b0),
        .bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
module ring_mask_ram(input wire clk,we,input wire [11:0] a,input wire [7:0] d,
                     output wire [7:0] q,input wire [11:0] b,output wire [7:0] r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),
        .DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("32K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(d),.dib(8'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(we),.web(1'b0),
        .bea(1'b1),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
