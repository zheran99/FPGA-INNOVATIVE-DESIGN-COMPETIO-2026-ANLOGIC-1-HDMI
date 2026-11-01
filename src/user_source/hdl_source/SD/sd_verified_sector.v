module sd_verified_sector #(
    parameter integer TIMEOUT_CYCLES=1000000,
    parameter integer MAX_RETRIES=2,
    parameter integer REPLAY_GAP=40,
    parameter integer SERIAL_CRC=0
)(
    input wire clk,rst,request,cancel,
    input wire [31:0] address,
    input wire [1:0] owner,
    output wire ready,busy,
    output reg done,error,
    output reg [2:0] error_code,
    output reg [1:0] result_owner,
    output wire [7:0] data,
    output reg valid,raw_start,raw_cancel,
    output reg [31:0] raw_address,
    input wire raw_idle,raw_valid,raw_done,raw_error,
    input wire raw_bit_valid,raw_bit,
    input wire [7:0] raw_data
);
    localparam IDLE=0,RECEIVE=1,CHECK=2,DRAIN=3,REPLAY=4,FINISH=5,FAILURE=6,WAIT_LOW=7;
    localparam E_TIMEOUT=1,E_RAW=2,E_CRC=3,E_LENGTH=4,E_CANCEL=5;
    reg [2:0] state;
    reg [9:0] count;
    reg [15:0] crc;
    reg [$clog2(TIMEOUT_CYCLES+1)-1:0] timer;
    reg [$clog2(MAX_RETRIES+2)-1:0] retries;
    reg [$clog2(REPLAY_GAP+1)-1:0] gap;
    reg terminal;
    reg [7:0] buffer[0:511]; /* fehdl force_ram=1, ram_style="bram" */
    reg [7:0] read_data;
    assign data=read_data;
    assign ready=state==IDLE && raw_idle;
    assign busy=state!=IDLE && state!=WAIT_LOW;
    wire accept=ready && request;
    wire cancelling=cancel && busy && state!=DRAIN && state!=FAILURE;
    wire retry_start=state==DRAIN && raw_idle && !terminal && !cancel && retries!=MAX_RETRIES;
    wire attempt_start=accept || retry_start;
    wire receive_byte=state==RECEIVE && raw_valid && count<514 && !cancel;
    wire receive_fault=raw_error || (raw_valid && count>=514) || timer==TIMEOUT_CYCLES-1;
    wire checked=state==CHECK && count==514 && crc==0;
    wire replay_start=checked && raw_idle && !cancel;
    wire replay_byte=state==REPLAY && gap==0 && !cancel;

    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] value;
        reg [15:0] c;
        integer i;
        begin
            c=previous ^ {value,8'd0};
            for(i=0;i<8;i=i+1)c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction

    always @(posedge clk or posedge rst)begin
        if(rst)result_owner<=2'b00;
        else if(accept)result_owner<=owner;
    end
    always @(posedge clk) begin
        if(accept)raw_address<=address;
        if(receive_byte && !count[9])buffer[count[8:0]]<=raw_data;
        read_data<=buffer[count[8:0]];
        if(state==IDLE || state==DRAIN)crc<=0;
        else if(SERIAL_CRC)begin
            if(state==RECEIVE && raw_bit_valid && !cancel)
                crc<={crc[14:0],1'b0} ^ ((crc[15]^raw_bit) ? 16'h1021 : 16'd0);
        end else if(receive_byte)crc<=crc_byte(crc,raw_data);
        if(state==IDLE || state==DRAIN)timer<=0;
        else if(state==RECEIVE || state==CHECK)timer<=timer+1'b1;

        if(state==IDLE || state==DRAIN || replay_start)count<=0;
        else if(receive_byte || replay_byte)count<=count+1'b1;
        if(replay_start || replay_byte)gap<=REPLAY_GAP-1;
        else if(state==REPLAY)gap<=gap-1'b1;
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;retries<=0;terminal<=0;error_code<=0;
            done<=0;error<=0;valid<=0;raw_start<=0;raw_cancel<=0;
        end else begin
            done<=0;error<=0;valid<=0;raw_start<=0;raw_cancel<=0;
            if(cancelling)begin
                raw_cancel<=1;terminal<=1;error_code<=E_CANCEL;state<=DRAIN;
            end else case(state)
                IDLE:if(accept)begin
                    raw_start<=1;retries<=0;terminal<=0;error_code<=0;state<=RECEIVE;
                end
                RECEIVE:begin
                    if(receive_fault)begin
                        error_code<=raw_error ? E_RAW : (raw_valid && count>=514) ? E_LENGTH : E_TIMEOUT;
                        raw_cancel<=1;state<=DRAIN;
                    end else if(raw_done)state<=CHECK;
                end
                CHECK:begin
                    if(count!=514 || crc!=0)begin
                        error_code<=count!=514 ? E_LENGTH : E_CRC;raw_cancel<=1;state<=DRAIN;
                    end else if(raw_idle)state<=REPLAY;
                    else if(timer==TIMEOUT_CYCLES-1)begin
                        error_code<=E_TIMEOUT;raw_cancel<=1;state<=DRAIN;
                    end
                end
                DRAIN:begin
                    raw_cancel<=1;
                    if(cancel)begin terminal<=1;error_code<=E_CANCEL;end
                    if(raw_idle)begin
                        if(terminal || cancel || retries==MAX_RETRIES)state<=FAILURE;
                        else begin retries<=retries+1'b1;raw_start<=1;raw_cancel<=0;state<=RECEIVE;end
                    end
                end
                REPLAY:if(gap==0)begin valid<=1;if(count==511)state<=FINISH;end
                FINISH:begin done<=1;error_code<=0;state<=WAIT_LOW;end
                FAILURE:begin error<=1;state<=WAIT_LOW;end
                WAIT_LOW:if(!request)state<=IDLE;
                default:begin raw_cancel<=1;terminal<=1;error_code<=E_RAW;state<=DRAIN;end
            endcase
        end
    end
endmodule
