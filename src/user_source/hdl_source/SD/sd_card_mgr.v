module sd_card_mgr #(
    parameter SPI_LOW_SPEED_DIV=248, SPI_HIGH_SPEED_DIV=0,

    parameter TIMEOUT_CYCLES=1000000, TOKEN_BYTES=65535
)(
    input clk,rst, input SD_MISO,
    output SD_nCS,SD_DCLK,SD_MOSI, output sd_init_done,
    input V_sec_read, input [31:0] V_sec_read_addr, input V_cancel,
    output [7:0] V_sec_read_data,
    output V_sec_read_data_valid,V_sec_read_end,V_sec_error,V_idle,
    input A_sec_read, input [31:0] A_sec_read_addr, input A_owner_text,
    input A_cancel, output [7:0] A_sec_read_data,
    output A_sec_read_data_valid,A_sec_read_end,A_sec_error,
    output A_result_text, output [2:0] error_code
);
wire spi_idle,shared_ack,spi_sample,raw_payload;
wire [7:0] spi_data_out;
wire read_mode=sd_init_done;
wire raw_start,raw_cancel,raw_idle,raw_valid,raw_done,raw_error;
wire [31:0] raw_address;
wire [7:0] raw_data,raw_transmit,data;
wire raw_cs,raw_request,sector_ready,sector_busy,done,error,valid;
wire [1:0] result_owner;
wire request=read_mode && sector_ready && (A_sec_read || (V_sec_read && !V_cancel));
wire [1:0] selected_owner=A_sec_read ? {A_owner_text,1'b1} : 2'b00;
wire cancel=result_owner[0] ? A_cancel : V_cancel;
sd_verified_sector #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAX_RETRIES(2),.REPLAY_GAP(40),.SERIAL_CRC(1)) sector(
    .clk(clk),.rst(rst),.request(request),.cancel(cancel),
    .address(A_sec_read ? A_sec_read_addr : V_sec_read_addr),.owner(selected_owner),
    .ready(sector_ready),.busy(sector_busy),.done(done),.error(error),.error_code(error_code),
    .result_owner(result_owner),.data(data),.valid(valid),.raw_start(raw_start),.raw_cancel(raw_cancel),
    .raw_address(raw_address),.raw_idle(raw_idle),.raw_valid(raw_valid),.raw_done(raw_done),
    .raw_error(raw_error),.raw_data(raw_data),
    .raw_bit_valid(spi_sample && raw_payload),.raw_bit(SD_MISO));
sd_read_raw_bytes #(.TOKEN_BYTES(TOKEN_BYTES)) raw(
    .clk(clk),.rst(rst),.start(raw_start),.cancel(raw_cancel),.address(raw_address),
    .payload_active(raw_payload),.idle(raw_idle),.init_done(sd_init_done),.valid(raw_valid),.done(raw_done),.error(raw_error),.data(raw_data),
    .cs_out(raw_cs),.request_out(raw_request),.transmit_out(raw_transmit),
    .ack(shared_ack),.receive(spi_data_out));
spi_master spi(
    .sys_clk(clk),.rst(rst),.sample_valid(spi_sample),.idle(spi_idle),.nCS(SD_nCS),.DCLK(SD_DCLK),
    .MOSI(SD_MOSI),.MISO(SD_MISO),.CPOL(1'b1),.CPHA(1'b1),
    .nCS_ctrl(raw_cs),
    .clk_div(read_mode ? SPI_HIGH_SPEED_DIV[15:0] : SPI_LOW_SPEED_DIV[15:0]),
    .wr_req(raw_request),.wr_ack(shared_ack),
    .data_in(raw_transmit),.data_out(spi_data_out));
assign V_sec_read_data=data;
assign A_sec_read_data=data;
assign V_sec_read_data_valid=valid && !result_owner[0];
assign V_sec_read_end=done && !result_owner[0];
assign V_sec_error=error && !result_owner[0];
assign V_idle=!(sector_busy && !result_owner[0]);
assign A_sec_read_data_valid=valid && result_owner[0];
assign A_sec_read_end=done && result_owner[0];
assign A_sec_error=error && result_owner[0];
assign A_result_text=result_owner[1];
endmodule
