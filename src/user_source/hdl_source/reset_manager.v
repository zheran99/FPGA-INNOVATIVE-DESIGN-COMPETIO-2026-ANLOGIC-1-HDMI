`timescale 1ns/1ps

module reset_manager #(
 parameter integer RELEASE_CYCLES=1000000
)(
 input wire ref_clk,sd_clk,mem_clk,pixel_clk,
 input wire key_n,sys_locked,video_locked,
 output wire rst_ref,rst_sd,rst_mem,rst_pixel,
 output wire request
);
 localparam CW=$clog2(RELEASE_CYCLES+1);
 reg [1:0] key_sync=0; /* fehdl keep="true" */
 reg [1:0] lock_meta=0,lock_sync=0; /* fehdl keep="true" */
 reg [CW-1:0] count=0;
 reg hold_reset=1;
 always @(posedge ref_clk or negedge key_n)begin
  if(!key_n)begin key_sync<=0;lock_meta<=0;lock_sync<=0;count<=0;hold_reset<=1;end
  else begin
   key_sync<={key_sync[0],1'b1};
   lock_meta<={video_locked,sys_locked};lock_sync<=lock_meta;
   if(!key_sync[1] || lock_sync!=2'b11)begin count<=0;hold_reset<=1;end
   else if(hold_reset)begin
    if(count==RELEASE_CYCLES-1)hold_reset<=0;
    else count<=count+1'b1;
   end
  end
 end
 assign request=!key_n || hold_reset;
 reset_domain_release u_ref(ref_clk,key_n,hold_reset,rst_ref);
 reset_domain_release u_sd(sd_clk,key_n,hold_reset,rst_sd);
 reset_domain_release u_mem(mem_clk,key_n,hold_reset,rst_mem);
 reset_domain_release u_pixel(pixel_clk,key_n,hold_reset,rst_pixel);

endmodule

module reset_domain_release(input wire clk,key_n,hold_reset,output wire rst);
 reg [2:0] pipe=3'b111; /* fehdl keep="true" */
 always @(posedge clk or negedge key_n)
  if(!key_n)pipe<=3'b111;
  else pipe<={pipe[1:0],hold_reset};

 reg reset_fall=1'b1; /* fehdl keep="true" */
 always @(negedge clk or negedge key_n)
  if(!key_n)reset_fall<=1'b1;
  else reset_fall<=pipe[2];
 assign rst=reset_fall;
endmodule
