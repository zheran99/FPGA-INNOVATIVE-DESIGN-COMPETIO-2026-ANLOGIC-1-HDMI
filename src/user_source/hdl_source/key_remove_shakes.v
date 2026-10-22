module key_remove_shakes(
	input wire      I_clk,
	input wire      I_rst_n,

	input wire      I_key_in,

	output reg      O_key_trig_out
);

	reg       S_key_in_sync_1d;
	reg       S_key_in_sync_2d;
	reg       S_key_in_sync_3d;
	reg	      S_key_in_sync_4d;
	wire      S_key_in_n_edge;

	reg       S_delay_en;
	reg       S_delay_en_1d;
	wire      S_delay_en_n_edge;
	reg[16:0] S_delay_cnt;

	always @ (posedge I_clk) begin
		S_key_in_sync_1d <= I_key_in;
		S_key_in_sync_2d <= S_key_in_sync_1d;
		S_key_in_sync_3d <= S_key_in_sync_2d;
		S_key_in_sync_4d <= S_key_in_sync_3d;
	end

	assign S_key_in_n_edge = ~S_key_in_sync_3d & S_key_in_sync_4d;

	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_delay_en <= 1'b0;
		else
			if(S_key_in_n_edge)
				S_delay_en <= 1'b1;
			else if(S_delay_cnt == 'd100000)
				S_delay_en <= 1'b0;
			else
				S_delay_en <= S_delay_en;
	end

	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_delay_cnt <= 'd0;
		else
			if(S_delay_en)
				S_delay_cnt <= S_delay_cnt + 1'b1;
			else
				S_delay_cnt <= 'd0;
	end

	always @ (posedge I_clk) begin
		S_delay_en_1d <= S_delay_en;
	end

	assign S_delay_en_n_edge = ~S_delay_en & S_delay_en_1d;

	always @ (posedge I_clk) begin
		if(S_delay_en_n_edge && !S_key_in_sync_4d)
			O_key_trig_out <= 1'b1;
		else
			O_key_trig_out <= 1'b0;
	end

endmodule

module ir_brightness #(
    parameter DEBOUNCE_CYCLES = 25'd1000000,   // 消抖 ~20ms @50MHz
    parameter ACTIVE_LOW      = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sensor,      // 高=有人
    output reg  dim          // 1=有人状态（全亮），0=没人状态（空亮度）
);
    reg [1:0]  sync;
    reg [24:0] db_cnt;       // 消抖计数
    reg        level;        // 消抖后的「有人」电平
    reg        level_d;      // level 延迟一拍，用于上升沿检测

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync <= 2'd0;
        else        sync <= {sync[0], ACTIVE_LOW ? ~sensor : sensor};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            db_cnt <= 25'd0;
            level  <= 1'b0;
        end else if (sync[1] != level) begin
            if (db_cnt >= DEBOUNCE_CYCLES) begin
                level  <= sync[1];
                db_cnt <= 25'd0;
            end else begin
                db_cnt <= db_cnt + 25'd1;
            end
        end else begin
            db_cnt <= 25'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dim     <= 1'b0;
            level_d <= 1'b0;
        end else begin
            level_d <= level;
            if (level != level_d)
                dim <= ~dim;
        end
    end
endmodule
