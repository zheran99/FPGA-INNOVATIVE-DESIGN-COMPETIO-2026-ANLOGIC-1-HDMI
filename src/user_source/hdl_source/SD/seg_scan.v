module seg_scan(
	input           clk,
	input           rst_n,
	output reg[5:0] seg_sel,      // digital led chip select
	output reg[7:0] seg_data,
	input[7:0]      seg_data_0,
	input[7:0]      seg_data_1,
	input[7:0]      seg_data_2,
	input[7:0]      seg_data_3,
	input[7:0]      seg_data_4,
	input[7:0]      seg_data_5
);
parameter INPUT_TOKENS = 0;
parameter SCAN_FREQ = 200;     // scan frequency
parameter CLK_FREQ = 50000000; // clock frequency

parameter SCAN_COUNT = CLK_FREQ /(SCAN_FREQ * 6) - 1;

localparam integer TIMER_WIDTH = (SCAN_COUNT < 0 || SCAN_COUNT >= 32'h7fffffff) ? 32 :
    (SCAN_COUNT < 1 ? 1 : $clog2(SCAN_COUNT + 1));
reg[TIMER_WIDTH-1:0] scan_timer;  // scan time counter
reg[2:0] scan_sel;     // Scan select counter
    function [7:0] status_segments;
        input [4:0] token;
        begin
            case(token)
                5'd0: status_segments=8'hc0;
                5'd1: status_segments=8'hf9;
                5'd2: status_segments=8'ha4;
                5'd3: status_segments=8'hb0;
                5'd4: status_segments=8'h99;
                5'd5: status_segments=8'h92;
                5'd6: status_segments=8'h82;
                5'd7: status_segments=8'hf8;
                5'd8: status_segments=8'h80;
                5'd9: status_segments=8'h90;
                5'd10: status_segments=8'h88;
                5'd11: status_segments=8'h83;
                5'd12: status_segments=8'hc6;
                5'd13: status_segments=8'ha1;
                5'd14: status_segments=8'h86;
                5'd15: status_segments=8'h8e;
                5'd16: status_segments=8'hbf;
                5'd17: status_segments=8'h8c;
                5'd18: status_segments=8'haf;
                5'd19: status_segments=8'h8f;
                5'd20: status_segments=8'hab;
                5'd21: status_segments=8'hc1;
                5'd22: status_segments=8'hc7;
                5'd23: status_segments=8'h79;
                default: status_segments=8'hff;
            endcase
        end
    endfunction
    reg [7:0] selected;
    always @(*) begin
        case(scan_sel)
            0:selected=seg_data_0;
            1:selected=seg_data_1;
            2:selected=seg_data_2;
            3:selected=seg_data_3;
            4:selected=seg_data_4;
            5:selected=seg_data_5;
            default:selected=INPUT_TOKENS ? 8'd31 : 8'hff;
        endcase
    end
always@(posedge clk or negedge rst_n)
begin
	if(rst_n == 1'b0)
	begin
		scan_timer <= 32'd0;
		scan_sel <= 3'd0;
	end
	else if(scan_timer >= SCAN_COUNT)
	begin
		scan_timer <= 32'd0;
		if(scan_sel == 3'd5)
			scan_sel <= 3'd0;
		else
			scan_sel <= scan_sel + 3'd1;
	end
	else
		begin
			scan_timer <= scan_timer + 32'd1;
		end
end
always@(posedge clk or negedge rst_n)
begin
	if(rst_n == 1'b0)
	begin
		seg_sel <= 6'b111111;
		seg_data <= 8'hff;
	end
	else
	begin
		case(scan_sel)
			3'd0:
			begin
				seg_sel <= 6'b11_1110;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			3'd1:
			begin
				seg_sel <= 6'b11_1101;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			3'd2:
			begin
				seg_sel <= 6'b11_1011;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			3'd3:
			begin
				seg_sel <= 6'b11_0111;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			3'd4:
			begin
				seg_sel <= 6'b10_1111;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			3'd5:
			begin
				seg_sel <= 6'b01_1111;
				seg_data <= INPUT_TOKENS ? status_segments(selected[4:0]) : selected;
			end
			default:
			begin
				seg_sel <= 6'b11_1111;
				seg_data <= 8'hff;
			end
		endcase
	end
end

endmodule
