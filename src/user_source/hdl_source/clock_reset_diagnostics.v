`timescale 1ns/1ps

module clock_reset_diagnostics #(
    parameter HEART_BITS=16,
    parameter WINDOW_BITS=20
)(
    input wire ref_clk, sd_clk, mem_clk, pixel_clk,
    input wire raw_rst_n, sys_locked, video_locked,
    input wire sd_ready, mem_ready, display_ready,
    input wire [3:0] video_state,
    output wire [3:0] locks, clocks, status, video
);
    reg [HEART_BITS-1:0] sd_count=0,mem_count=0,pixel_count=0;
    always @(posedge sd_clk) sd_count<=sd_count+1'b1;
    always @(posedge mem_clk) mem_count<=mem_count+1'b1;
    always @(posedge pixel_clk) pixel_count<=pixel_count+1'b1;
    reg [2:0] heart_meta=0,heart_sync=0,heart_prev=0,seen=0,alive=0;
    reg [WINDOW_BITS-1:0] window_count=0;
    reg [1:0] lock_meta=0,lock_sync=0;
    reg [3:0] status_meta=0,status_sync=0,video_meta=0,video_sync=0;
    wire [2:0] changed=heart_sync^heart_prev;
    always @(posedge ref_clk) begin
        heart_meta<={pixel_count[HEART_BITS-1],mem_count[HEART_BITS-1],sd_count[HEART_BITS-1]};
        heart_sync<=heart_meta;
        heart_prev<=heart_sync;
        lock_meta<={video_locked,sys_locked};lock_sync<=lock_meta;
        status_meta<={display_ready,mem_ready,sd_ready,raw_rst_n};status_sync<=status_meta;
        video_meta<=video_state;video_sync<=video_meta;
        window_count<=window_count+1'b1;
        if(&window_count)begin alive<=seen|changed;seen<=0;end
        else seen<=seen|changed;
    end
    assign locks={2'b0,lock_sync};
    assign clocks={1'b0,alive};
    assign status=status_sync;
    assign video=video_sync;
endmodule
