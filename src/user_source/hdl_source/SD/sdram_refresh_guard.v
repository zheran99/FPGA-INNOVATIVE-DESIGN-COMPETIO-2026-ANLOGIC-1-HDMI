module sdram_refresh_guard (
    input wire clk,
    input wire rst,
    input wire init_done,
    input wire app_active,
    input wire refresh_active,
    input wire refresh_command,
    output wire admission_block,
    output wire refresh_request
);
    localparam [1:0] IDLE=0, DRAIN=1, REQUEST=2, SERVICE=3;
    reg [1:0] state;
    reg [11:0] period_count;
    reg [3:0] quiet_count;
    reg command_seen;
    wire due = period_count == 12'd3890;
    assign admission_block = !init_done || state != IDLE || due;
    assign refresh_request = state == REQUEST;
    always @(posedge clk) begin
        if(rst || !init_done) begin
            state <= IDLE;
            period_count <= 0;
            quiet_count <= 0;
            command_seen <= 0;
        end else begin

            period_count <= period_count == 12'd3905 ? 12'd0 : period_count + 1'b1;
            case(state)
                IDLE: begin
                    quiet_count <= 0;
                    command_seen <= 0;
                    if(due) state <= DRAIN;
                end
                DRAIN: begin
                    if(app_active) quiet_count <= 0;
                    else if(quiet_count == 4'd11) state <= REQUEST;
                    else quiet_count <= quiet_count + 1'b1;
                end

                REQUEST: state <= SERVICE;
                SERVICE: begin
                    if(refresh_command) command_seen <= 1;
                    if(command_seen && !refresh_active) state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
