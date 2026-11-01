`timescale 1ns/1ps

module spectrum_blob_loader #(
    parameter [31:0] BLOB_START_SECTOR=32'd0,
    parameter [13:0] TOTAL_SECTORS=14'd14454
)(
    input wire I_sd_clk,I_sd_rst,I_en,
    input wire [13:0] I_frame_no,
    output reg O_spec_read,
    output wire [31:0] O_spec_addr,
    input wire [7:0] I_sd_data,
    input wire I_sd_dv,I_sd_end,I_sd_err,I_sd_init_done,
    output reg [9:0] O_wr_addr,
    output reg [7:0] O_wr_data,
    output reg O_wr_en,
    output reg O_commit_toggle,
    input wire I_commit_ack
);
    localparam [1:0] S_IDLE=0,S_REQ=1,S_RX=2,S_PUBLISH=3;
    reg [1:0] state;
    reg [13:0] want,loaded;
    reg valid,discard;
    reg [9:0] byte_cnt;
    reg last_byte,sector_full;
    (* async_reg="true" *) reg [1:0] ack_sync;
    assign O_spec_addr=BLOB_START_SECTOR+{18'd0,want};

    wire complete=sector_full || (last_byte && I_sd_dv);
    always @(posedge I_sd_clk or posedge I_sd_rst)begin
        if(I_sd_rst)begin
            state<=S_IDLE;want<=0;loaded<=0;valid<=0;discard<=0;byte_cnt<=0;last_byte<=0;sector_full<=0;
            O_spec_read<=0;O_wr_addr<=0;O_wr_data<=0;O_wr_en<=0;
            O_commit_toggle<=0;ack_sync<=0;
        end else begin
            ack_sync<={ack_sync[0],I_commit_ack};
            O_wr_en<=0;
            if(!I_en)begin valid<=0;discard<=1;end
            case(state)
            S_IDLE:begin
                O_spec_read<=0;
                if(I_en && I_sd_init_done && I_frame_no<TOTAL_SECTORS && (!valid || I_frame_no!=loaded))begin
                    want<=I_frame_no;byte_cnt<=0;discard<=0;last_byte<=0;sector_full<=0;
                    O_spec_read<=1;state<=S_REQ;
                end
            end
            S_REQ,S_RX:begin

                if(I_sd_dv && !sector_full)begin
                    byte_cnt<=byte_cnt+10'd1;state<=S_RX;
                    last_byte<=byte_cnt==10'd510;
                    sector_full<=last_byte;
                    if(byte_cnt<10'd80 && I_en && !discard)begin
                        O_wr_addr<={2'd0,~O_commit_toggle,byte_cnt[6:0]};
                        O_wr_data<=I_sd_data;O_wr_en<=1;
                    end
                end
                if(I_sd_err)begin
                    O_spec_read<=0;O_wr_en<=0;valid<=0;state<=S_IDLE;
                end else if(I_sd_end)begin
                    O_spec_read<=0;
                    if(complete && I_en && !discard)begin
                        loaded<=want;valid<=1;O_commit_toggle<=~O_commit_toggle;state<=S_PUBLISH;
                    end else begin valid<=0;state<=S_IDLE;end
                end
            end
            S_PUBLISH:begin
                O_spec_read<=0;
                if(ack_sync[1]==O_commit_toggle)state<=S_IDLE;
            end
            default:begin state<=S_IDLE;O_spec_read<=0;valid<=0;end
            endcase
        end
    end
endmodule

module spectrum_level_ram(
    input wire I_wclk,I_wen,
    input wire [9:0] I_waddr,
    input wire [7:0] I_wdata,
    input wire I_rclk,
    input wire [9:0] I_raddr,
    output reg [7:0] O_rdata
);
    reg [7:0] mem[0:1023]; /* fehdl force_ram=1, ram_style="bram" */
    always @(posedge I_wclk)if(I_wen)mem[I_waddr]<=I_wdata;
    always @(posedge I_rclk)O_rdata<=mem[I_raddr];
endmodule
