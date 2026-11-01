module frame_snapshot_cdc #(parameter WIDTH=14)(
    input wire source_clk,source_rst,
    input wire [WIDTH-1:0] source_data,
    input wire dest_clk,dest_rst,
    output reg [WIDTH-1:0] dest_data
);
    reg [WIDTH-1:0] held_data;
    reg request,acknowledge;
    (* async_reg="true" *) reg [1:0] ack_sync,request_sync;
    always @(posedge source_clk or posedge source_rst)begin
        if(source_rst)begin held_data<=0;request<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(request==ack_sync[1] && held_data!=source_data)begin
                held_data<=source_data;request<=~request;
            end
        end
    end
    always @(posedge dest_clk or posedge dest_rst)begin
        if(dest_rst)begin dest_data<=0;acknowledge<=0;request_sync<=0;end
        else begin
            request_sync<={request_sync[0],request};
            if(request_sync[1]!=acknowledge)begin
                dest_data<=held_data;acknowledge<=request_sync[1];
            end
        end
    end
endmodule
