module audio_ring_filter(
    input wire clk,rst,en,sample_valid,
    input wire [23:0] sample_left,
    output reg [119:0] levels,
    output wire busy,
    output reg overrun,
    output reg initialized,
    input wire [4:0] shape_height,
    output wire [11:0] shape_slope,

    input wire snapshot_request,
    input wire [4:0] snapshot_index,
    output wire [4:0] snapshot_height
);
`include "ring_filter_tables.vh"
    localparam INIT=0,IDLE=1,READ_REQ=2,READ_USE=3,
               MUL0=4,WAIT0=5,USE0=6,MUL1=7,WAIT1=8,USE1=9,
               MUL2=10,WAIT2=11,USE2=12,SCALE=13,ENV=14,LINEAR=15,HEIGHT=16,
               WRITE=17,NEXT=18,PRODUCT_WAIT=19,HEIGHT_WAIT=20,MAGNITUDE=21,
               ENV_SELECT=22;
    reg [4:0] state;
    reg [7:0] init_address;
    reg [4:0] band;
    reg [2:0] byte_index;

    reg [63:0] channel_state;
    reg signed [23:0] previous_input,previous_input2,input_delta,filtered;
    reg signed [23:0] mul_a;
    reg signed [21:0] mul_b;
    wire signed [45:0] product;
    wire product_ready,product_busy;
    reg [1:0] product_stage;
    reg [4:0] linear_height,linear_bit;
    wire [4:0] linear_candidate=linear_height | linear_bit;

    function [15:0] height_threshold;
        input [4:0] candidate;
        begin
            case(candidate)
                5'd0: height_threshold=16'd1336;
                5'd1: height_threshold=16'd1600;
                5'd2: height_threshold=16'd2392;
                5'd3: height_threshold=16'd2920;
                5'd4: height_threshold=16'd3448;
                5'd5: height_threshold=16'd3976;
                5'd6: height_threshold=16'd4504;
                5'd7: height_threshold=16'd5032;
                5'd8: height_threshold=16'd5560;
                5'd9: height_threshold=16'd6088;
                5'd10: height_threshold=16'd6616;
                5'd11: height_threshold=16'd7144;
                5'd12: height_threshold=16'd7672;
                5'd13: height_threshold=16'd8200;
                5'd14: height_threshold=16'd8728;
                5'd15: height_threshold=16'd9256;
                5'd16: height_threshold=16'd9784;
                5'd17: height_threshold=16'd10312;
                5'd18: height_threshold=16'd10840;
                5'd19: height_threshold=16'd11368;
                5'd20: height_threshold=16'd11896;
                5'd21: height_threshold=16'd12424;
                5'd22: height_threshold=16'd12952;
                5'd23: height_threshold=16'd13480;
                5'd24: height_threshold=16'd14008;
                5'd25: height_threshold=16'd14536;
                5'd26: height_threshold=16'd15064;
                5'd27: height_threshold=16'd15592;
                5'd28: height_threshold=16'd16120;
                5'd29: height_threshold=16'd16648;
                5'd30: height_threshold=16'd17176;
                5'd31: height_threshold=16'd17704;
                default: height_threshold=16'd0;
            endcase
        end
    endfunction
    wire [15:0] linear_threshold=height_threshold(linear_candidate);
    reg signed [21:0] stored_b0,stored_a1,stored_a2;
    wire [15:0] table_q,shape_q;
    wire [8:0] table_address={1'b0,band,byte_index};
    ring_filter_geometry_rom tables(clk,table_address,table_q,9'd384+{4'd0,shape_height},shape_q);
    assign shape_slope=shape_q[11:0];
    reg signed [47:0] accumulator;
    reg [15:0] envelope;
    reg [15:0] magnitude_registered,release_registered;
    reg envelope_high_gt,envelope_high_eq,envelope_low_gt;
    reg [119:0] working_levels;
    reg [1:0] level_write_bank,level_latest_bank,level_held_bank;
    wire [1:0] effective_held_bank=snapshot_request ? level_latest_bank : level_held_bank;
    wire [1:0] next_write_bank=(level_write_bank!=0 && effective_held_bank!=0) ? 2'd0 :
                               (level_write_bank!=1 && effective_held_bank!=1) ? 2'd1 : 2'd2;
    wire level_init=state==INIT && init_address<96;
    wire [6:0] level_write_address=state==INIT ? init_address[6:0] : {level_write_bank,band};
    wire [7:0] level_q;
    ring_level_ram level_store(clk,level_init || state==HEIGHT,level_write_address,
        level_init ? 8'd0 : {3'd0,linear_height},
        {level_held_bank,snapshot_index},level_q);
    assign snapshot_height=level_q[4:0];
    always @(posedge clk or posedge rst)begin
        if(rst)begin level_write_bank<=1;level_latest_bank<=0;level_held_bank<=2;end
        else begin
            if(snapshot_request)level_held_bank<=level_latest_bank;
            if(state==NEXT && band==23)begin
                level_latest_bank<=level_write_bank;
                level_write_bank<=next_write_bank;
            end
        end
    end
    wire [7:0] state_address=state==INIT ? init_address : {band,byte_index};
    wire [7:0] state_data=state==INIT ? 8'd0 : channel_state[7:0];
    wire state_we=state==INIT || state==WRITE;
    wire [7:0] state_q;
    ring_state_ram states(clk,state_we,state_address,state_data,state_q);
    wire signed [23:0] input_fixed={{2{sample_left[23]}},sample_left[23:8],6'b0};
    wire signed [23:0] old_y1=channel_state[23:0];
    wire signed [23:0] old_y2=channel_state[47:24];
    wire [15:0] old_envelope=channel_state[63:48];
    wire [23:0] absolute_filtered=filtered[23] ? -filtered : filtered;
    wire [17:0] magnitude_wide=absolute_filtered[23:6];
    wire [15:0] magnitude=(|magnitude_wide[17:16]) ? 16'hffff : magnitude_wide[15:0];
    wire [15:0] release_step=(old_envelope>>11)==0 ? 16'd1 : (old_envelope>>11);
    wire [15:0] released=old_envelope>release_step ? old_envelope-release_step : 16'd0;
    wire [15:0] next_envelope=magnitude>released ? magnitude : released;
    assign busy=state!=IDLE;
    wire product_start=state==WAIT0 || state==WAIT1 || state==WAIT2;
    ring_shared_multiplier multiplier(clk,rst,product_start,mul_a,mul_b,product,product_ready,product_busy);
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=INIT;init_address<=0;band<=0;byte_index<=0;
            channel_state<=0;previous_input<=0;previous_input2<=0;
            input_delta<=0;filtered<=0;mul_a<=0;mul_b<=0;accumulator<=0;
            envelope<=0;linear_height<=0;linear_bit<=0;levels<=0;working_levels<=0;overrun<=0;initialized<=0;
            product_stage<=0;stored_b0<=0;stored_a1<=0;stored_a2<=0;
            magnitude_registered<=0;release_registered<=0;
            envelope_high_gt<=0;envelope_high_eq<=0;envelope_low_gt<=0;
        end else begin
            if(sample_valid && en && initialized && state!=IDLE)overrun<=1;
            case(state)
                INIT:if(init_address==191)begin initialized<=1;state<=IDLE;end
                     else init_address<=init_address+1'b1;
                IDLE:if(sample_valid && en)begin
                    input_delta<=input_fixed-previous_input2;
                    previous_input2<=previous_input;previous_input<=input_fixed;
                    band<=0;byte_index<=0;state<=READ_REQ;
                end
                READ_REQ:state<=READ_USE;
                READ_USE:begin
                    channel_state<={state_q,channel_state[63:8]};
                    case(byte_index)
                        0:stored_b0[15:0]<=table_q;1:stored_b0[21:16]<=table_q[5:0];
                        2:stored_a1[15:0]<=table_q;3:stored_a1[21:16]<=table_q[5:0];
                        4:stored_a2[15:0]<=table_q;5:stored_a2[21:16]<=table_q[5:0];
                    endcase
                    if(byte_index==7)state<=MUL0;
                    else begin byte_index<=byte_index+1'b1;state<=READ_REQ;end
                end
                MUL0:begin mul_a<=input_delta;mul_b<=stored_b0;state<=WAIT0;end
                WAIT0:begin product_stage<=0;state<=PRODUCT_WAIT;end
                USE0:begin accumulator<=product;state<=MUL1;end
                MUL1:begin mul_a<=old_y1;mul_b<=stored_a1;state<=WAIT1;end
                WAIT1:begin product_stage<=1;state<=PRODUCT_WAIT;end
                USE1:begin accumulator<=accumulator-product;state<=MUL2;end
                MUL2:begin mul_a<=old_y2;mul_b<=stored_a2;state<=WAIT2;end
                WAIT2:begin product_stage<=2;state<=PRODUCT_WAIT;end
                USE2:begin accumulator<=accumulator-product;state<=SCALE;end
                PRODUCT_WAIT:if(product_ready)case(product_stage)
                    0:begin accumulator<=product;state<=MUL1;end
                    1:begin accumulator<=accumulator-product;state<=MUL2;end
                    2:begin accumulator<=accumulator-product;state<=SCALE;end
                endcase
                SCALE:begin
                    if(accumulator>48'sd8796091973632)filtered<=24'sh7fffff;
                    else if(accumulator< -48'sd8796093022208)filtered<=24'sh800000;
                    else filtered<=accumulator>>>20;
                    state<=MAGNITUDE;
                end
                MAGNITUDE:begin magnitude_registered<=magnitude;release_registered<=released;state<=ENV;end
                ENV:begin
                    envelope_high_gt<=magnitude_registered[15:8]>release_registered[15:8];
                    envelope_high_eq<=magnitude_registered[15:8]==release_registered[15:8];
                    envelope_low_gt<=magnitude_registered[7:0]>release_registered[7:0];
                    state<=ENV_SELECT;
                end
                ENV_SELECT:begin
                    envelope<=(envelope_high_gt || (envelope_high_eq && envelope_low_gt)) ?
                              magnitude_registered : release_registered;
                    state<=LINEAR;
                end
                LINEAR:begin
                    linear_height<=0;
                    linear_bit<=5'd16;
                    state<=envelope>=1600 ? HEIGHT_WAIT : HEIGHT;
                end
                HEIGHT_WAIT:begin
                    if(linear_candidate<=28 && envelope>=linear_threshold)
                        linear_height<=linear_candidate;
                    linear_bit<=linear_bit>>1;
                    if(linear_bit==1)state<=HEIGHT;
                end
                HEIGHT:begin
                    working_levels<={linear_height,working_levels[119:5]};
                    channel_state<={envelope,old_y1,filtered};byte_index<=0;state<=WRITE;
                end
                WRITE:begin
                    channel_state<={8'd0,channel_state[63:8]};
                    if(byte_index==7)state<=NEXT;
                    else byte_index<=byte_index+1'b1;
                end
                NEXT:if(band==23)begin levels<=working_levels;state<=IDLE;end
                     else begin band<=band+1'b1;byte_index<=0;state<=READ_REQ;end
                default:state<=INIT;
            endcase
        end
    end
endmodule

`include "ring_shared_multiplier.vh"

module ring_filter_geometry_rom(input wire clk,input wire [8:0] a,output wire [15:0] q,
                               input wire [8:0] b,output wire [15:0] r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("32K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("python/ring_filter_geometry.mif"),.FILL_ALL("NONE")) mem(
        .dia(16'd0),.dib(16'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(1'b0),.web(1'b0),
        .bea(1'b0),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule

module ring_state_ram(input wire clk,we,input wire [7:0] a,input wire [7:0] d,output wire [7:0] q);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(256),.DATA_DEPTH_B(256),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(d),.dib(8'd0),.addra(a),.addrb(8'd0),.cea(1'b1),.ceb(1'b0),.wea(we),.web(1'b0),
        .bea(1'b1),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(1'b0),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob());
endmodule

module ring_level_ram(input wire clk,we,input wire [6:0] a,input wire [7:0] d,
                      input wire [6:0] b,output wire [7:0] q);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(7),.ADDR_WIDTH_B(7),
        .DATA_DEPTH_A(128),.DATA_DEPTH_B(128),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(d),.dib(8'd0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(we),.web(1'b0),
        .bea(1'b1),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(),.dob(q));
endmodule
