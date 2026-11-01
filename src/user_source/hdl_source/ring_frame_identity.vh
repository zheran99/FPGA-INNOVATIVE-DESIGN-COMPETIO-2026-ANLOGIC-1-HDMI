`ifndef RING_FRAME_IDENTITY_VH
`define RING_FRAME_IDENTITY_VH

module ring_frame_identity(
    input wire src_clk,src_rst,
    input wire [6:0] src_identity,
    input wire video_clk,video_rst,read_request,
    output reg [1:0] frame_slot,
    output reg [4:0] frame_ad
);
    reg [6:0] identity_payload;
    reg request_toggle,ack_toggle;
    (* async_reg="true" *) reg ack_s1,ack_s2,req_v1,req_v2;
    reg [6:0] latest_identity;
    reg read_q;
    always @(posedge src_clk or posedge src_rst)begin
        if(src_rst)begin identity_payload<=7'd4;request_toggle<=0;ack_s1<=0;ack_s2<=0;end
        else begin
            ack_s1<=ack_toggle;ack_s2<=ack_s1;
            if(ack_s2==request_toggle && src_identity!=identity_payload)begin
                identity_payload<=src_identity;request_toggle<=~request_toggle;
            end
        end
    end
    always @(posedge video_clk or posedge video_rst)begin
        if(video_rst)begin
            req_v1<=0;req_v2<=0;ack_toggle<=0;latest_identity<=7'd4;
            frame_slot<=0;frame_ad<=1;read_q<=0;
        end else begin
            req_v1<=request_toggle;req_v2<=req_v1;read_q<=read_request;
            if(req_v2!=ack_toggle)begin latest_identity<=identity_payload;ack_toggle<=req_v2;end
            if(read_request && !read_q)begin
                frame_slot<=latest_identity[1:0];frame_ad<=latest_identity[6:2];
            end
        end
    end
endmodule
`endif
