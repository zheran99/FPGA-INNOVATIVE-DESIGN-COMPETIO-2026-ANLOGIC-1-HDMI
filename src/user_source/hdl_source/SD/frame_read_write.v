`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter BURST_SIZE             = 256,
	parameter WRITE_V_FLIP           = 1,
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480,
	parameter PIX_PER_WORD           = 1
)
(
    input refresh_admission_block,
    input abort_write, output abort_ack,
	input                            rst,
	input                            mem_clk,
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,

    /*
    output                           rd_burst_req,               // to external memory controller,send out a burst read request
	output[BURST_BITS - 1:0]         rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read data valid
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // from external memory controller,read request data
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,					 // read_data_valid
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,

	input                            read_clk,                   // data read module clock
	input                            read_req,
	output                           read_req_ack,
	output                           read_finish,
	input[ADDR_BITS - 1:0]           read_addr_0,
	input[ADDR_BITS - 1:0]           read_addr_1,
	input[ADDR_BITS - 1:0]           read_addr_2,
	input[ADDR_BITS - 1:0]           read_addr_3,
	input[1:0]                       read_addr_index,
	input[ADDR_BITS - 1:0]           read_len,
	input                            read_en,
	output[READ_DATA_BITS  - 1:0]    read_data,                  // read data
	/*
	output                           wr_burst_req,               // to external memory controller,send out a burst write request
	output[BURST_BITS - 1:0]         wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // to external memory controller,base address of the burst write request
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // to external memory controller,write data
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,

	input                            write_clk,                  // data write module clock
	input                            write_req,
	output                           write_req_ack,
	output                           write_finish,
	input[ADDR_BITS - 1:0]           write_addr_0,
	input[ADDR_BITS - 1:0]           write_addr_1,
	input[ADDR_BITS - 1:0]           write_addr_2,
	input[ADDR_BITS - 1:0]           write_addr_3,
	input[1:0]                       write_addr_index,
	input[ADDR_BITS - 1:0]           write_len,
	input                            write_en,
 input[WRITE_DATA_BITS - 1:0]     write_data,                // write data

 output                           rd_fifo_empty,

 output                           rd_fifo_full,

 input [ADDR_BITS - 1:0]          read_addr_b_0,
 input [ADDR_BITS - 1:0]          read_addr_b_1,
 input [ADDR_BITS - 1:0]          read_addr_b_2,
 input [ADDR_BITS - 1:0]          read_addr_b_3,
 input [1:0]                      read_addr_b_index,
 output[READ_DATA_BITS  - 1:0]    read_data_b,               // B 通道读出数据（32bit = 2×RGB565）
 output                           rd_fifo_empty_b,           // B 通道读 FIFO 空标志

 output                           wr_busy,

 output                           burst_err,
 output [7:0]                     burst_diff,

 output                           wr_cnt_err,
 output [7:0]                     wr_last_addr

);

wire[10:0]                                       wrusedw;                    // 读 FIFO used（深度 1024 11 位）
wire[10:0]                                       wrusedw_b;                  // B 通道读 FIFO used（11 位）
wire[9:0]                                        rdusedw;

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire                                 read_fifo_aclr;             // fifo Asynchronous clear
wire                                 read_fifo_aclr_b;           // B 通道读 FIFO aclr
wire                                 write_fifo_aclr;            // fifo Asynchronous clear

wire                                 RDFIFO_FULL_W;

wire                                 RDFIFO_FULL_B_W;

wire O_wr_busy;
wire O_rd_busy;
wire O_rd_busy_b;    // B 通道 busy
wire O_rd_active_b;

wire        rd_burst_err;
wire [7:0]  rd_burst_diff;

wire        wr_cnt_err_i;
wire [7:0]  wr_last_addr_i;

wire        App_rd_en_a, App_rd_en_b;
wire [ADDR_BITS-1:0] App_rd_addr_a, App_rd_addr_b;
reg         burst_owner;       // 0=A 数据回 A，1=B 数据回 B
reg         en_a_d1, en_b_d1;  // 各通道 App_rd_en 的 1 拍延迟（边沿检测）

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        burst_owner <= 1'b0;
        en_a_d1     <= 1'b0;
        en_b_d1     <= 1'b0;
    end else begin
        en_a_d1 <= App_rd_en_a;
        en_b_d1 <= App_rd_en_b;
        if (App_rd_en_a && !en_a_d1)      burst_owner <= 1'b0;   // A 突发开始
        else if (App_rd_en_b && !en_b_d1) burst_owner <= 1'b1;   // B 突发开始
    end
end

wire rd_we_a = Sdr_rd_en && ~burst_owner;
wire rd_we_b = Sdr_rd_en &&  burst_owner;

assign App_rd_en   = App_rd_en_a | App_rd_en_b;
assign App_rd_addr = App_rd_en_a ? App_rd_addr_a : App_rd_addr_b;

assign App_wr_busy = O_wr_busy;// 下个时钟写指令拉高

assign App_rd_busy = O_rd_busy | O_rd_busy_b;
assign App_wr_dm = 4'b0000;

assign wr_busy       = O_wr_busy;
assign rd_fifo_full  = RDFIFO_FULL_W;   // 见下方 rfifo 例化处的连线
assign burst_err     = rd_burst_err;    // 读突发字数校验（从 frame_fifo_read 来）
assign burst_diff    = rd_burst_diff;
assign wr_cnt_err    = wr_cnt_err_i;    // 写侧字数校验（从 frame_fifo_write 来）
assign wr_last_addr  = wr_last_addr_i;

wfifo_32_32_512 write_buf
		(
		.clkr                      	(mem_clk                  ),          // Read side clock
		.clkw                      	(write_clk                ),          // Write side clock
		.rst                       	(write_fifo_aclr          ),          // Asynchronous clear
		.we                      	(write_en                 ),          // Write Request
		.re                      	(App_wr_en        		  ),          // Read Request
		.di                       	(write_data               ),          // Input Data
		.empty_flag                 (                         ),          // Read side Empty flag
		.full_flag                  (                         ),          // Write side Full flag
		.wrusedw                	(              	  		  ),          // Read Used Words
		.rdusedw                	(rdusedw                  ),          // Write Used Words
		.dout                       (App_wr_din		          )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             ),
	.PIX_PER_WORD               (PIX_PER_WORD             )
)
frame_fifo_write_m0
(
    .abort_write(abort_write), .abort_ack(abort_ack),
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .refresh_admission_block(refresh_admission_block),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .O_wr_busy					(O_wr_busy),

	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),
	.write_len                  (write_len                ),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                 	(rdusedw                  ),

	.wr_cnt_err                 (wr_cnt_err_i             ),   // 内部线（不是端口名！）
	.wr_last_addr               (wr_last_addr_i           )
);

afifo_32_32_1024 read_buf
		(
		.clkr                     	(read_clk                   ),          // Read side clock
		.clkw                     	(mem_clk                    ),          // Write side clock
		.rst                      	(read_fifo_aclr             ),          // Asynchronous clear
		.we                     	(rd_we_a       			    ),          // Write Request A 通道数据回送
		.re                     	(read_en                    ),          // Read Request
		.di                      	(Sdr_rd_dout                ),          // Input Data
		.empty_flag					(rd_fifo_empty              ),          // Read side Empty flag 已接出
		.full_flag					(RDFIFO_FULL_W              ),
		.wrusedw                	(wrusedw         	  		),          // Read Used Words（ 11 位）
		.rdusedw                	(                  			),          // Write Used Words
		.dout						(read_data                  )
);

afifo_32_32_1024 read_buf_b
		(
		.clkr                     	(read_clk                   ),          // Read side clock
		.clkw                     	(mem_clk                    ),          // Write side clock
		.rst                      	(read_fifo_aclr_b           ),          // Asynchronous clear
		.we                     	(rd_we_b       			    ),          // Write Request B 通道数据回送
		.re                     	(read_en                    ),          // Read Request（与 A 通道同拍）
		.di                      	(Sdr_rd_dout                ),          // Input Data
		.empty_flag					(rd_fifo_empty_b            ),          // Read side Empty flag 已接出
		.full_flag					(RDFIFO_FULL_B_W            ),          // Write side Full flag
		.wrusedw                	(wrusedw_b         	  		),          // Read Used Words（11 位）
		.rdusedw                	(                  			),          // Write Used Words
		.dout						(read_data_b                )
);

frame_fifo_read
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.FIFO_DEPTH                 (1024                     ),
	.BURST_SIZE                 (BURST_SIZE               )
)
frame_fifo_read_m0
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .refresh_admission_block(refresh_admission_block),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.App_wr_busy				(App_wr_busy),
	.rd_peer_busy				(O_rd_active_b             ),   // A 优先：只让路给 B 的"正在突发"
    .O_rd_busy					(O_rd_busy),
    .O_rd_active				(                          ),   // A 的 active 未使用

    .App_rd_en					(App_rd_en_a               ),   // 经仲裁后输出
    .App_rd_addr				(App_rd_addr_a             ),
	.read_req                   (read_req                 ),
	.read_req_ack               (read_req_ack             ),
	.read_finish                (read_finish              ),
	.read_addr_0                (read_addr_0              ),
	.read_addr_1                (read_addr_1              ),
	.read_addr_2                (read_addr_2              ),
	.read_addr_3                (read_addr_3              ),
	.read_addr_index            (read_addr_index          ),
	.read_len                   (read_len                 ),
	.fifo_aclr                  (read_fifo_aclr           ),
	.wrusedw                	(wrusedw                  ),

	.burst_err                  (rd_burst_err             ),
	.burst_diff                 (rd_burst_diff            )
);

frame_fifo_read
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.FIFO_DEPTH                 (1024                     ),
	.BURST_SIZE                 (BURST_SIZE               )
)
frame_fifo_read_m1
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .refresh_admission_block(refresh_admission_block),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.App_wr_busy				(App_wr_busy),
	.rd_peer_busy				(O_rd_busy                 ),   // B 让路：让给 A 的"即将/正在突发"
    .O_rd_busy					(O_rd_busy_b               ),
    .O_rd_active				(O_rd_active_b             ),   // B 的"正在突发"给 A 做互斥

    .App_rd_en					(App_rd_en_b               ),   // 经仲裁后输出
    .App_rd_addr				(App_rd_addr_b             ),
	.read_req                   (read_req                 ),
	.read_req_ack               (                          ),
	.read_finish                (                          ),
	.read_addr_0                (read_addr_b_0             ),
	.read_addr_1                (read_addr_b_1             ),
	.read_addr_2                (read_addr_b_2             ),
	.read_addr_3                (read_addr_b_3             ),
	.read_addr_index            (read_addr_b_index         ),
	.read_len                   (read_len                 ),
	.fifo_aclr                  (read_fifo_aclr_b          ),
	.wrusedw                	(wrusedw_b                 ),
	.burst_err                  (                          ),
	.burst_diff                 (                          )
);

endmodule
