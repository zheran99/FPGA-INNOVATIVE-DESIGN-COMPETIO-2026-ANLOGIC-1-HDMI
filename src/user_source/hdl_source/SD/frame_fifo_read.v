`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128)
(
	input                            rst,
	input                            mem_clk,
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,

	input							 rd_peer_busy,
    output							 O_rd_busy,

	output							 O_rd_active,
	/*
    output reg                       rd_burst_req,               // to external memory controller,send out a burst read request
	output reg[BURST_BITS - 1:0]     rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read request data valid
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,

	input                            read_req,
	output reg                       read_req_ack,
	output                           read_finish,
	input[ADDR_BITS - 1:0]           read_addr_0,
	input[ADDR_BITS - 1:0]           read_addr_1,
	input[ADDR_BITS - 1:0]           read_addr_2,
	input[ADDR_BITS - 1:0]           read_addr_3,
	input[1:0]                       read_addr_index,
	input[ADDR_BITS - 1:0]           read_len,
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[10:0]                      wrusedw,                    // from fifo write used words

	output                           burst_err,
	output [7:0]                     burst_diff
);
localparam ONE                       = 256'd1;
localparam ZERO                      = 256'd0;                   // 256 bit '0'

localparam S_IDLE                    = 0;
localparam S_ACK                     = 1;                        // read request response
localparam S_CHECK_FIFO              = 2;
localparam S_READ_BURST              = 3;                        // begin a burst read
localparam S_READ_BURST_END          = 4;                        // a burst read complete
localparam S_END                     = 5;

reg                                  read_req_d0;
reg                                  read_req_d1;                // second
reg                                  read_req_d2;
reg[ADDR_BITS - 1:0]                 read_len_d0;
reg[ADDR_BITS - 1:0]                 read_len_d1;                // second
reg[ADDR_BITS - 1:0]                 read_len_latch;             // lock read data length
reg[ADDR_BITS - 1:0]                 read_cnt;                   // read data counter
reg[3:0]                             state;                      // state machine
reg[1:0]                             read_addr_index_d0;
reg[1:0]                             read_addr_index_d1;
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg App_rd_en_r;
reg App_rd_en_d0;

wire rd_vld;
reg [3:0] rd_delay;

reg [BURST_BITS:0] burst_wc;         // 本突发已收到的 word 数（多 1 位防溢出）
reg                dbg_burst_err;
reg [7:0]          dbg_burst_diff;   // 最后一次不符时的差值（BURST_SIZE - 实收）

assign App_rd_addr = {App_rd_addr_r[ADDR_BITS - 1:0]};
assign rd_vld = (state == S_READ_BURST && burst_cnt >= BURST_SIZE);

wire rd_about_to_burst = (state == S_CHECK_FIFO) &&
                         (read_req_d2 != 1'b1) &&
                         (wrusedw < (FIFO_DEPTH - BURST_SIZE));

assign O_rd_busy = (state == S_READ_BURST) || rd_about_to_burst;

assign O_rd_active = (state == S_READ_BURST);
// burst_cnt代表发送的读指令

assign rd_burst_finish = (rd_vld && rd_delay == 4'd10);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             // read finish at state 'S_END'
assign App_rd_en = App_rd_en_d0;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];
		read_addr_index_d0 <= 2'b00;
		read_addr_index_d1 <= 2'b00;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0;
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;

	end
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_wc       <= {(BURST_BITS+1){1'b0}};
		dbg_burst_err  <= 1'b0;
		dbg_burst_diff <= 8'd0;
	end
	else begin

		if(state == S_READ_BURST && burst_cnt == {BURST_BITS{1'b0}})
			burst_wc <= {(BURST_BITS+1){1'b0}};

		else if(Sdr_rd_en)
			burst_wc <= burst_wc + 1'b1;

		if(rd_burst_finish) begin
			if(burst_wc != BURST_SIZE[BURST_BITS:0]) begin
				dbg_burst_err  <= 1'b1;
				dbg_burst_diff <= BURST_SIZE[BURST_BITS:0] - burst_wc[7:0];
			end
		end
	end
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst || App_rd_en)begin
        rd_delay <= 4'd0;
    end
    else if(rd_delay < 4'd10)begin
    	rd_delay <= rd_delay + 1'b1;
    end
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
	end
	else begin

		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;

		if(state == S_ACK)
			begin
				if(read_addr_index_d1 == 2'd0)
					App_rd_addr_r <= read_addr_0;
				else if(read_addr_index_d1 == 2'd1)
					App_rd_addr_r <= read_addr_1;
				else if(read_addr_index_d1 == 2'd2)
					App_rd_addr_r <= read_addr_2;
				else if(read_addr_index_d1 == 2'd3)
					App_rd_addr_r <= read_addr_3;
			end
		else if(App_rd_en)
			App_rd_addr_r <= App_rd_addr_r + 1'b1;
		else
			App_rd_addr_r <= App_rd_addr_r;

		if(App_rd_en_r && burst_cnt + App_rd_en < BURST_SIZE)
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;

	end
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];

		App_rd_en_r <= 1'b0;

		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;

		read_req_ack <= 1'b0;
	end
	else
		case(state)

			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end

			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					read_req_ack <= 1'b1;
					fifo_aclr <= 1'b1;

					/*
					if(read_addr_index_d1 == 2'd0)
						App_rd_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						App_rd_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						App_rd_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						App_rd_addr <= read_addr_3;
					*/
					read_len_latch <= read_len_d1;
				end

				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin

				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end

		else if(wrusedw < (FIFO_DEPTH - BURST_SIZE) && ~App_wr_busy && ~rd_peer_busy)
				begin
					state <= S_READ_BURST;

					App_rd_en_r <= 1'b1;
				end
			end

			S_READ_BURST:
			begin
				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;

					read_cnt <= read_cnt + BURST_SIZE[ADDR_BITS - 1:0];

				end
			end
			S_READ_BURST_END:
			begin

				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end

				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
