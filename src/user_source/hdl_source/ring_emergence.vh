module ring_emergence #(
    parameter [15:0] RANDOM_SEED=16'hb4d3
)(
    input wire clk,rst,frame_start,en,publish,
    input wire [4:0] peak,
    input wire [9:0] energy,
    input wire [1:0] launch_count,
    input wire [29:0] launch_x,launch_y,
    input wire [14:0] launch_height,
    input wire de,
    input wire [11:0] x,y,
    output reg hit
);
    reg [15:0] random_state;
    reg [9:0] last_energy,slow_energy;
    reg [4:0] last_peak,cadence;
    reg [2:0] cooldown,cursor;
    reg [15:0] births;
    reg [7:0] alive;
    reg signed [11:0] center_x[0:7],center_y[0:7];
    wire audible=peak>=6 && energy>=24;
    wire [10:0] adaptive_threshold={1'b0,slow_energy}+{4'd0,slow_energy[9:3]}+11'd12;
    wire attack=audible && cooldown==0 && {1'b0,energy}>=adaptive_threshold &&
        ({1'b0,energy}>={1'b0,last_energy}+11'd18 ||
         {1'b0,peak}>={1'b0,last_peak}+6'd3);
    wire [4:0] interval=energy>=300 ? 5'd1 : energy>=180 ? 5'd3 :
                              energy>=80 ? 5'd6 : 5'd13;
    wire spawn=frame_start && en && publish && audible && launch_count!=0 && (attack || cadence>=interval);
    wire [1:0] requested_count=attack ? (energy>=160 && peak>=20 ? 2'd3 :
                                     energy>=80 ? 2'd2 : 2'd1) :
                                   (energy>=300 ? 2'd3 : energy>=180 ? 2'd2 : 2'd1);
    wire [1:0] spawn_count=requested_count<launch_count ? requested_count : launch_count;
    wire [2:0] cursor1=cursor+3'd1,cursor2=cursor+3'd2;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            random_state<=RANDOM_SEED==0 ? 16'h1 : RANDOM_SEED;
            last_energy<=0;slow_energy<=0;last_peak<=0;cadence<=0;
            cooldown<=0;cursor<=0;births<=0;
        end
        else if(frame_start)begin
            random_state<={random_state[14:0],random_state[15]^random_state[13]^
                           random_state[12]^random_state[10]};
            if(!en)begin
                last_energy<=0;slow_energy<=0;last_peak<=0;
                cadence<=0;cooldown<=0;cursor<=0;
            end else if(publish)begin
                last_energy<=energy;last_peak<=peak;
                slow_energy<=slow_energy-(slow_energy>>3)+(energy>>3);
                if(cooldown!=0)cooldown<=cooldown-1'b1;
                if(!audible)cadence<=0;
                else if(spawn)begin
                    cadence<=0;cursor<=cursor+{1'b0,spawn_count};
                    births<=births+{14'd0,spawn_count};
                    if(attack)cooldown<=3'd3;
                end else if(cadence<31)cadence<=cadence+1'b1;
            end
        end
    end

    reg [29:0] frame_launch_x,frame_launch_y;
    reg [14:0] frame_launch_height;
    reg [2:0] update_slot,frame_cursor;
    wire [2:0] birth_rank=update_slot-frame_cursor;
    wire signed [9:0] ox=birth_rank==1 ? frame_launch_x[19:10] :
        birth_rank==2 ? frame_launch_x[29:20] : frame_launch_x[9:0];
    wire signed [9:0] oy=birth_rank==1 ? frame_launch_y[19:10] :
        birth_rank==2 ? frame_launch_y[29:20] : frame_launch_y[9:0];
    wire [4:0] birth_height=birth_rank==1 ? frame_launch_height[9:5] :
        birth_rank==2 ? frame_launch_height[14:10] : frame_launch_height[4:0];
    function [2:0] radial_speed;
        input signed [9:0] coordinate;
        input extra;
        reg [9:0] magnitude;
        begin
            magnitude=coordinate<0 ? -coordinate : coordinate;
            radial_speed=magnitude<32 ? 3'd0 : magnitude<96 ? 3'd1 :
                magnitude<160 ? 3'd2+{2'd0,extra} : 3'd3+{2'd0,extra};
        end
    endfunction
    reg updating,frame_spawn,frame_enabled,initialized;
    reg [2:0] init_slot;
    reg [1:0] update_phase,frame_count;
    reg [4:0] frame_peak;
    reg [15:0] frame_random,seed;
    reg signed [11:0] birth_base_x,birth_base_y;
    reg signed [3:0] birth_vx,birth_vy;
    wire [2:0] frame_cursor1=frame_cursor+3'd1,frame_cursor2=frame_cursor+3'd2;
    reg selected,moving;
    wire selected_next=frame_spawn && (frame_cursor==update_slot ||
        (frame_count>=2 && frame_cursor1==update_slot) ||
        (frame_count==3 && frame_cursor2==update_slot));
    reg [15:0] slot_seed;
    always @*begin
        case(update_slot)
            0:slot_seed={frame_random[0+:8],frame_random[15-:8]}^16'h9e37;
            1:slot_seed={frame_random[1+:8],frame_random[14-:8]}^16'h3c6e;
            2:slot_seed={frame_random[2+:8],frame_random[13-:8]}^16'hdaa5;
            3:slot_seed={frame_random[3+:8],frame_random[12-:8]}^16'h78dc;
            4:slot_seed={frame_random[4+:8],frame_random[11-:8]}^16'h1713;
            5:slot_seed={frame_random[5+:8],frame_random[10-:8]}^16'hb54a;
            6:slot_seed={frame_random[6+:8],frame_random[9-:8]}^16'h5381;
            default:slot_seed={frame_random[7+:8],frame_random[8-:8]}^16'hf1b8;
        endcase
    end
    wire [2:0] speed_x=radial_speed(ox,seed[11]);
    wire [2:0] speed_y=radial_speed(oy,seed[11]);
    reg building;
    reg [2:0] draw_slot;
    wire [31:0] state_q;
    wire signed [3:0] old_vx=state_q[28:25],old_vy=state_q[24:21];
    wire [5:0] old_life=state_q[20:15],old_age=state_q[14:9];
    wire [4:0] old_size=state_q[8:4];
    wire moving_next=alive[update_slot] && old_age<old_life;
    wire [5:0] next_age=old_age+6'd1;
    wire [4:0] next_size=old_age[2:0]==7 && old_size<27 ? old_size+5'd1 : old_size;
    wire [4:0] born_size=5'd5+{2'd0,seed[6:4]}+{2'd0,birth_height[4:2]};
    wire [5:0] born_life=6'd28+{1'b0,seed[12:8]};
    wire [31:0] updated_state=selected ?
        {3'd0,birth_vx,birth_vy,born_life,6'd0,born_size,seed[15:14],seed[9:8]} :
        {3'd0,old_vx,old_vy,old_life,(!frame_enabled ? 6'd0 : moving ? next_age : old_age),
         (frame_enabled && moving ? next_size : old_size),state_q[3:0]};
    wire state_write=!rst && (!initialized || (updating && update_phase==2 && !frame_start));
    ring_sprite_state_ram metadata(.clk(clk),.we(state_write),
        .a(!initialized ? init_slot : update_slot),.b(building ? draw_slot : update_slot),
        .d(!initialized ? 32'd0 : updated_state),.q(state_q));
    always @(posedge clk or posedge rst)begin
        if(rst)begin initialized<=0;init_slot<=0;end
        else if(!initialized)begin
            init_slot<=init_slot+1'b1;
            if(init_slot==7)initialized<=1;
        end
    end

    wire [2:0] center_slot=building ? draw_slot : update_slot;
    wire signed [11:0] stored_x=center_x[center_slot],stored_y=center_y[center_slot];
    wire signed [11:0] next_x=selected ? birth_base_x : stored_x+{{8{old_vx[3]}},old_vx};
    wire signed [11:0] next_y=selected ? birth_base_y : stored_y+{{8{old_vy[3]}},old_vy};
    wire update_done=updating && update_phase==2 && update_slot==7 && frame_enabled;

    always @(posedge clk)begin
        if(!rst && !frame_start && updating && initialized && update_phase==2 && frame_enabled &&
           (selected || moving))begin
            center_x[update_slot]<=next_x;center_y[update_slot]<=next_y;
        end
    end

    always @(posedge clk or posedge rst)begin
        if(rst)begin
            updating<=0;frame_spawn<=0;frame_enabled<=0;update_phase<=0;frame_count<=0;
            update_slot<=0;frame_cursor<=0;frame_peak<=0;frame_random<=0;seed<=0;
            birth_base_x<=0;birth_base_y<=0;birth_vx<=0;birth_vy<=0;alive<=0;
            selected<=0;moving<=0;
            frame_launch_x<=0;frame_launch_y<=0;frame_launch_height<=0;
        end else if(frame_start)begin
            updating<=1;frame_enabled<=en;update_slot<=0;update_phase<=0;
            frame_random<=random_state;frame_peak<=peak;frame_spawn<=spawn;
            frame_count<=spawn_count;frame_cursor<=cursor;
            frame_launch_x<=launch_x;frame_launch_y<=launch_y;frame_launch_height<=launch_height;
            if(!en)alive<=0;
        end else if(updating && initialized)begin
            case(update_phase)
                0:begin seed<=slot_seed;update_phase<=1;end
                1:begin

                    selected<=selected_next;moving<=moving_next;
                    birth_base_x<=12'sd640+{{2{ox[9]}},ox};
                    birth_base_y<=12'sd360+{{2{oy[9]}},oy};
                    birth_vx<=ox<0 ? -$signed({1'b0,speed_x}) : $signed({1'b0,speed_x});
                    birth_vy<=oy<0 ? -$signed({1'b0,speed_y}) : $signed({1'b0,speed_y});
                    update_phase<=2;
                end
                default:begin
                    if(selected)begin
                        alive[update_slot]<=1;
                    end else if(frame_enabled && alive[update_slot])begin
                        if(!moving)alive[update_slot]<=0;
                    end
                    update_phase<=0;update_slot<=update_slot+1'b1;
                    if(update_slot==7)updating<=0;
                end
            endcase
        end
    end

    localparam DRAW_IDLE=0,DRAW_WAIT=1,DRAW_FETCH=2,DRAW_ROW=3,DRAW_PIXELS=4,DRAW_DRAIN=5;
    reg cache_ready,clearing,build_valid1,build_valid2;
    reg [9:0] clear_index;
    reg [2:0] draw_state;
    reg [1:0] drain_count,line_ready;
    reg [11:0] target_y;
    reg [5:0] draw_x;
    reg signed [11:0] draw_center_x,draw_center_y;
    reg signed [6:0] draw_relative_y;
    reg [4:0] draw_size;
    reg [1:0] draw_kind,draw_orientation;
    reg draw_alive,draw_row_valid;
    wire signed [13:0] row_delta=$signed({2'd0,target_y})-
        $signed({{2{draw_center_y[11]}},draw_center_y});
    reg [5:0] ax1,ay1;
    reg signed [6:0] vertical1;
    reg [4:0] size1;
    reg [1:0] kind1;
    reg build_bit2;
    wire signed [6:0] local_x=$signed({1'b0,draw_x})-7'sd32;
    wire signed [6:0] local_y=draw_relative_y;
    wire signed [6:0] u=draw_orientation[0] ? local_y : local_x;
    wire signed [6:0] v0=draw_orientation[0] ? local_x : local_y;
    wire signed [6:0] v=draw_orientation[1] ? -v0 : v0;
    wire [6:0] abs_u=u[6] ? -u : u;
    wire [6:0] abs_v=v[6] ? -v : v;
    wire [7:0] doubled_x={1'b0,ax1,1'b0};
    wire [7:0] doubled_size={2'd0,size1,1'b0};
    wire signed [7:0] triangle_y=$signed({vertical1[6],vertical1})+$signed({3'd0,size1});
    wire [7:0] diagonal=doubled_x+{2'd0,ay1};
    wire [6:0] diamond={1'b0,ax1}+{1'b0,ay1};
    wire [5:0] edge_size={1'b0,size1}-6'd1;
    reg outline;
    always @*begin
        case(kind1)
            0:outline=triangle_y>=0 && triangle_y<=$signed(doubled_size) &&
                $signed({1'b0,doubled_x})<=$signed({triangle_y[7],triangle_y}) &&
                ($signed({1'b0,doubled_x})+9'sd2>=$signed({triangle_y[7],triangle_y}) ||
                 vertical1>=$signed({1'b0,edge_size}));
            1:outline=ax1<={1'b0,size1} && ay1<={1'b0,size1} &&
                (ax1>=edge_size || ay1>=edge_size);
            2:outline=ay1<={1'b0,size1} && diagonal<=doubled_size &&
                (diagonal+8'd2>=doubled_size || ay1>=edge_size);
            default:outline=diamond>={2'd0,size1} && diamond<={2'd0,size1}+7'd1;
        endcase
    end
    wire signed [12:0] draw_screen_x=$signed({draw_center_x[11],draw_center_x})+
        $signed({{6{local_x[6]}},local_x});
    reg [11:0] write_address1,write_address2;
    wire cache_write=build_valid2 && build_bit2 && !frame_start && !rst && !clearing;

    always @(posedge clk)begin
        ax1<=abs_u[5:0];ay1<=abs_v[5:0];vertical1<=v;
        size1<=draw_size;kind1<=draw_kind;build_bit2<=outline;
        write_address1<={target_y[0],draw_screen_x[10:0]};
        write_address2<=write_address1;
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            building<=0;cache_ready<=0;clearing<=0;clear_index<=0;
            build_valid1<=0;build_valid2<=0;draw_state<=DRAW_IDLE;
            draw_slot<=0;draw_x<=0;target_y<=0;drain_count<=0;line_ready<=0;
        end else begin
            build_valid1<=draw_state==DRAW_PIXELS && draw_alive && draw_row_valid &&
                draw_screen_x>=0 && draw_screen_x<1280;
            build_valid2<=build_valid1;
            if(frame_start)begin
                clearing<=1;clear_index<=0;building<=0;cache_ready<=0;
                draw_state<=DRAW_IDLE;line_ready<=0;build_valid1<=0;build_valid2<=0;
            end else if(clearing)begin
                clear_index<=clear_index+1'b1;
                if(clear_index==1023)begin
                    clearing<=0;building<=1;draw_slot<=0;draw_x<=0;
                    target_y<=0;draw_state<=DRAW_WAIT;
                end
            end else if(de && x==0 && y<719 && cache_ready)begin
                line_ready[y[0]]<=0;
                building<=1;target_y<=y+12'd1;draw_slot<=0;draw_x<=0;
                draw_state<=DRAW_WAIT;
            end else begin
                if(de && x==0 && y==719)line_ready[y[0]]<=0;
                case(draw_state)
                    DRAW_WAIT:draw_state<=DRAW_FETCH;
                    DRAW_FETCH:begin
                        draw_center_x<=stored_x;draw_center_y<=stored_y;
                        draw_size<=state_q[8:4];draw_kind<=state_q[3:2];
                        draw_orientation<=state_q[1:0];draw_alive<=alive[draw_slot];
                        draw_state<=DRAW_ROW;
                    end
                    DRAW_ROW:begin
                        draw_relative_y<=row_delta[6:0];
                        draw_row_valid<=row_delta>=-32 && row_delta<32;
                        draw_x<=0;draw_state<=DRAW_PIXELS;
                    end
                    DRAW_PIXELS:begin
                        draw_x<=draw_x+1'b1;
                        if(draw_x==63)begin
                            if(draw_slot==7)begin draw_state<=DRAW_DRAIN;drain_count<=0;end
                            else begin draw_slot<=draw_slot+1'b1;draw_state<=DRAW_WAIT;end
                        end
                    end
                    DRAW_DRAIN:begin
                        drain_count<=drain_count+1'b1;
                        if(drain_count==2)begin
                            building<=0;draw_state<=DRAW_IDLE;
                            line_ready[target_y[0]]<=1;
                            if(target_y==0)cache_ready<=1;
                        end
                    end
                    default:;
                endcase
            end
        end
    end
    reg previous_valid;
    reg [11:0] previous_address;
    wire [11:0] read_address={y[0],x[10:0]};
    always @(posedge clk or posedge rst)begin
        if(rst)begin previous_valid<=0;previous_address<=0;end
        else begin
            previous_valid<=de && cache_ready && !clearing && !frame_start;
            previous_address<=read_address;
        end
    end
    wire [1:0] cache_bits;
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1)begin:cache
        wire read_bank=de && x[0]==bank;
        wire clear_previous=previous_valid && previous_address[0]==bank && !read_bank;
        ring_sprite_line_ram mask(.clk(clk),
            .wea(clearing || clear_previous),.web(clearing || (cache_write && write_address2[0]==bank)),
            .db(!clearing),
            .a(clearing ? {2'd0,clear_index,1'b0} :
                read_bank ? {2'd0,read_address[11:1]} : {2'd0,previous_address[11:1]}),
            .b(clearing ? {2'd0,clear_index,1'b1} : {2'd0,write_address2[11:1]}),
            .q(cache_bits[bank]));
    end endgenerate
    reg valid1,valid2,parity1,pixel_hit2;
    always @(posedge clk)begin
        parity1<=x[0];pixel_hit2<=parity1 ? cache_bits[1] : cache_bits[0];
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin hit<=0;valid1<=0;valid2<=0;end
        else begin
            valid1<=de && en && cache_ready && !clearing && !frame_start;
            valid2<=valid1;hit<=pixel_hit2 && valid2;
        end
    end
endmodule

module ring_sprite_line_ram(input wire clk,wea,web,db,input wire [12:0] a,b,output wire q);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(1),.DATA_WIDTH_B(1),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
        .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(1'b0),.dib(db),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(wea),.web(web),
        .bea(1'b1),.beb(1'b1),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob());
endmodule

module ring_sprite_state_ram(input wire clk,we,input wire [2:0] a,b,
    input wire [31:0] d,output wire [31:0] q);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("32K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(d),.dib(32'd0),.addra({7'd0,a}),.addrb({7'd0,b}),.cea(1'b1),.ceb(1'b1),.wea(we),.web(1'b0),
        .bea(1'b1),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(),.dob(q));
endmodule

module ring_sprite_ram(input wire clk,we,d,input wire [12:0] a,b,output wire q,r);
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(1),.DATA_WIDTH_B(1),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
        .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K"),.DEBUGGABLE("NO"),.PACKABLE("NO"),.INIT_FILE("NONE"),.FILL_ALL("NONE")) mem(
        .dia(d),.dib(1'b0),.addra(a),.addrb(b),.cea(1'b1),.ceb(1'b1),.wea(we),.web(1'b0),
        .bea(1'b1),.beb(1'b0),.ocea(1'b0),.oceb(1'b0),.clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.doa(q),.dob(r));
endmodule
