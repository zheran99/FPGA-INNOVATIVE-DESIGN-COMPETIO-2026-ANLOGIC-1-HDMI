`timescale 1ns/1ps

module video_delay
#(
	parameter DATA_WIDTH = 24,
	parameter PIX565     = 1
)
(
	input                       video_clk,
	input                       rst,
	output                      read_en,
	input[31:0]                 read_data,

 input                       rd_fifo_empty,
	input                       hs,
	input                       vs,
	input                       de,
	output                      hs_r,
	output                      vs_r,
	output                      de_r,
	output[DATA_WIDTH - 1:0]    vout_data
);

	reg [20:0] hs_d;
	reg [20:0] vs_d;
	reg [20:0] de_d;

	assign hs_r = hs_d[20];
	assign vs_r = vs_d[20];
	assign de_r = de_d[20];

	always @(posedge video_clk or posedge rst) begin
		if (rst == 1'b1) begin
			hs_d <= 21'b0;
			vs_d <= 21'b0;
			de_d <= 21'b0;
		end
		else begin
			hs_d <= {hs_d[19:0], hs};
			vs_d <= {vs_d[19:0], vs};
			de_d <= {de_d[19:0], de};
		end
	end

	generate
	if (PIX565 == 1) begin : g_565

		reg [10:0] x_d18;

		always @(posedge video_clk or posedge rst) begin
			if (rst == 1'b1)
				x_d18 <= 11'd0;
			else if (!de_d[18])
				x_d18 <= 11'd0;            // 与 read_en 同域复位

			else
				x_d18 <= x_d18 + 1'b1;
		end

		assign read_en = de_d[18] & ~x_d18[0];

		reg read_en_d1;
		reg [31:0] word_r;

		reg word_valid;

		always @(posedge video_clk or posedge rst) begin
			if (rst == 1'b1) begin
				read_en_d1 <= 1'b0;
				word_r     <= 32'd0;
				word_valid <= 1'b0;
			end
			else begin
				read_en_d1 <= read_en;
				if (read_en_d1) begin
					word_r     <= read_data;            // read_en 后一拍命中数据
					word_valid <= 1'b1;
				end else if (!de_d[20]) begin
					word_valid <= 1'b0;                 // 行末清掉
				end
			end
		end

		reg out_phase;                 // 0=偶像素(取低16位) 1=奇像素(取高16位)

		always @(posedge video_clk or posedge rst) begin
			if (rst == 1'b1)
				out_phase <= 1'b0;
			else if (!de_d[20])
				out_phase <= 1'b0;             // 消隐期复位
			else if (de_d[20])
				out_phase <= ~out_phase;       // 每个活跃像素翻转
		end

		wire [15:0] pix16 = out_phase ? word_r[31:16] : word_r[15:0];

		wire [4:0] r5 = pix16[15:11];
		wire [5:0] g6 = pix16[10:5];
		wire [4:0] b5 = pix16[4:0];

		wire [7:0] r8 = {r5, r5[4:2]};
		wire [7:0] g8 = {g6, g6[5:4]};
		wire [7:0] b8 = {b5, b5[4:2]};

		assign vout_data = (de_d[20] && word_valid) ? {r8, g8, b8} : {DATA_WIDTH{1'b0}};
	end
	else begin : g_888

		assign read_en = de_d[18];

		reg [DATA_WIDTH-1:0] vout_data_r;
		always @(posedge video_clk or posedge rst) begin
			if (rst == 1'b1)
				vout_data_r <= {DATA_WIDTH{1'b0}};
			else if (de_d[19])
				vout_data_r <= read_data[DATA_WIDTH-1:0];
			else
				vout_data_r <= {DATA_WIDTH{1'b0}};
		end

		assign vout_data = vout_data_r;
	end
	endgenerate

endmodule
