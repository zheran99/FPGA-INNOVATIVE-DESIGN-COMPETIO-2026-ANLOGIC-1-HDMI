module sd_read_raw_bytes #(
    parameter [15:0] SPI_DIV=0,
    parameter integer TOKEN_BYTES=65535
)(
    input wire clk,rst,start,cancel,
    input wire [31:0] address,
    output wire idle,
    output reg init_done,
    output reg valid,done,error,
    output wire [7:0] data,
    output wire payload_active,
    output wire cs_out,request_out,
    output wire [7:0] transmit_out,
    input wire ack,
    input wire [7:0] receive
);
    localparam IDLE=0,PRE=1,COMMAND=2,RESPONSE=3,TOKEN=4,
               PAYLOAD=5,TAIL=6,COMPLETE=7,INIT_CLOCKS=8,INIT_EXTRA=9;
    reg [3:0] state;
    reg [2:0] init_step;
    reg [15:0] count;
    reg cs,request,pending,abort_pending,failed;
    reg [7:0] transmit;
    reg [7:0] command_byte;
    wire [31:0] argument=init_done ? address :
        init_step==1 ? 32'h000001aa : init_step==3 ? 32'h40000000 : init_step==4 ? 32'd512 : 32'd0;
    always @* begin
        if(init_done)command_byte=8'h51;
        else case(init_step)
            0:command_byte=8'h40;
            1:command_byte=8'h48;
            2:command_byte=8'h77;
            3:command_byte=8'h69;
            default:command_byte=8'h50;
        endcase
    end
    assign data=receive;
    assign payload_active=state==PAYLOAD;
    assign idle=init_done && state==IDLE;
    assign cs_out=cs;
    assign request_out=request;
    assign transmit_out=transmit;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=INIT_CLOCKS;init_step<=0;init_done<=0;count<=0;
            cs<=1;request<=0;pending<=0;abort_pending<=0;failed<=0;
            transmit<=8'hff;valid<=0;done<=0;error<=0;
        end else begin
            valid<=0;done<=0;error<=0;
            if(cancel && init_done && state!=IDLE)abort_pending<=1;
            if(state==IDLE)begin
                request<=0;pending<=0;cs<=1;abort_pending<=0;
                if(start && !cancel)begin count<=0;failed<=0;state<=PRE;end
            end else if(state==COMPLETE)begin
                if(!init_done)begin

                    if(failed)begin if(init_step==3)init_step<=2;end
                    else if(init_step==4)begin init_done<=1;state<=IDLE;end
                    else init_step<=init_step+1'b1;
                    if(failed || init_step!=4)state<=PRE;
                    failed<=0;count<=0;
                end else begin
                    if(!abort_pending && !cancel)begin done<=!failed;error<=failed;end
                    state<=IDLE;
                end
            end else if(!pending)begin
                if((cancel || abort_pending) && init_done && state!=TAIL)begin
                    cs<=1;state<=TAIL;count<=0;
                end else begin
                    pending<=1;request<=1;transmit<=8'hff;
                    if(state==COMMAND)case(count)
                        0:transmit<=command_byte;
                        1:transmit<=argument[31:24];
                        2:transmit<=argument[23:16];
                        3:transmit<=argument[15:8];
                        4:transmit<=argument[7:0];
                        5:transmit<=!init_done && init_step==0 ? 8'h95 :
                                    !init_done && init_step==1 ? 8'h87 : 8'hff;
                        default:transmit<=8'hff;
                    endcase
                end
            end else if(ack)begin
                pending<=0;request<=0;
                if((cancel || abort_pending) && init_done && state!=TAIL)begin
                    cs<=1;state<=TAIL;count<=0;
                end else case(state)
                    INIT_CLOCKS:if(count==10)begin state<=PRE;count<=0;end
                                else count<=count+1'b1;
                    PRE:begin cs<=0;state<=COMMAND;count<=0;end
                    COMMAND:if(count==5)begin state<=RESPONSE;count<=0;end
                            else count<=count+1'b1;
                    RESPONSE:begin
                        if(receive==(init_done || init_step>=3 ? 8'd0 : 8'd1))begin
                            count<=0;
                            if(init_done)state<=TOKEN;
                            else if(init_step==1)state<=INIT_EXTRA;
                            else begin cs<=1;state<=TAIL;end
                        end else if(!receive[7] || count==15)begin
                            failed<=1;cs<=1;state<=TAIL;
                        end else count<=count+1'b1;
                    end
                    INIT_EXTRA:if(count==3)begin cs<=1;state<=TAIL;end
                               else count<=count+1'b1;
                    TOKEN:begin
                        if(receive==8'hfe)begin state<=PAYLOAD;count<=0;end
                        else if(receive!=8'hff || count==TOKEN_BYTES-1)begin
                            failed<=1;cs<=1;state<=TAIL;
                        end else count<=count+1'b1;
                    end
                    PAYLOAD:begin
                        valid<=1;
                        if(count==513)begin cs<=1;state<=TAIL;end
                        else count<=count+1'b1;
                    end
                    TAIL:state<=COMPLETE;
                    default:begin failed<=1;cs<=1;state<=TAIL;end
                endcase
            end
        end
    end
endmodule
