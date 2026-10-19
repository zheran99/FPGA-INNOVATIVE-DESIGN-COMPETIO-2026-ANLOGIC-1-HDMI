`timescale 1ns/1ps

module audio_volume (
    input wire I_clk,I_rst,I_valid,
    input wire [23:0] I_left,I_right,
    input wire [7:0] I_volume,
    output reg O_valid,
    output reg [23:0] O_left,O_right
);
    reg [7:0] volume_d1,volume_d2,volume_stable;
    reg [7:0] index;
    reg [15:0] coefficient,target,gain;
    reg [6:0] remainder;
    wire [7:0] bounded_volume=I_volume>100 ? 8'd100 : I_volume;

    wire carry_fraction=remainder>=7'd32;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            volume_d1<=100;volume_d2<=100;volume_stable<=100;
            index<=0;coefficient<=0;remainder<=50;target<=32768;
        end else begin
            volume_d1<=bounded_volume;volume_d2<=volume_d1;

            volume_stable<=volume_d2;
            if(index<100) begin
                index<=index+1'b1;
                coefficient<=coefficient+(carry_fraction ? 16'd328 : 16'd327);
                remainder<=carry_fraction ? remainder-7'd32 : remainder+7'd68;
            end else begin index<=0;coefficient<=0;remainder<=50;end
            if(index==volume_d2 && volume_d2==volume_stable)target<=coefficient;
        end
    end

    wire [15:0] gain_next=target>gain ?
        ((target-gain)>32 ? gain+16'd32 : target) :
        ((gain-target)>32 ? gain-16'd32 : target);
    reg [23:0] pcm_l,pcm_r,scaled_l,scaled_r;
    reg [4:0] phase;
    wire signed [23:0] selected_pcm=phase[0] ? pcm_r : pcm_l;
    reg signed [40:0] product,rounded;
    reg busy;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            gain<=32768;pcm_l<=0;pcm_r<=0;product<=0;rounded<=0;
            phase<=0;busy<=0;scaled_l<=0;scaled_r<=0;
            O_valid<=0;O_left<=0;O_right<=0;
        end else begin
            O_valid<=0;
            if(I_valid && !busy)begin
                gain<=gain_next;pcm_l<=I_left;pcm_r<=I_right;
                phase<=0;busy<=1;
            end else if(busy)begin
                if(phase<2)product<=selected_pcm*$signed({1'b0,gain});
                if(phase==1 || phase==2)
                    rounded<=product+(product[40] ? 41'sd32767 : 41'sd0);

                if(phase==2)scaled_l<=rounded[38:15];
                if(phase==3)scaled_r<=rounded[38:15];
                if(phase==18)begin
                    O_left<=scaled_l;O_right<=scaled_r;O_valid<=1;busy<=0;
                end else begin
                    phase<=phase+1'b1;
                end
            end
        end
    end
endmodule
