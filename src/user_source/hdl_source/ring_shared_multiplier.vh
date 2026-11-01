module ring_shared_multiplier(
    input wire clk,rst,start,
    input wire signed [23:0] a,
    input wire signed [21:0] b,
    output reg signed [45:0] product,
    output reg ready,
    output reg busy
);
    reg signed [23:0] held_a;
    reg signed [21:0] held_b;
    reg [2:0] phase;
    wire signed [17:0] a_low={1'b0,held_a[16:0]};
    wire signed [17:0] a_high={{11{held_a[23]}},held_a[23:17]};
    wire signed [17:0] b_low={1'b0,held_b[16:0]};
    wire signed [17:0] b_high={{13{held_b[21]}},held_b[21:17]};
    wire signed [17:0] operand_a=phase==1 || phase==3 ? a_high : a_low;
    wire signed [17:0] operand_b=phase>=2 ? b_high : b_low;
    reg signed [35:0] partial;
    wire signed [45:0] expanded={{10{partial[35]}},partial};
    reg signed [45:0] accumulated;
    always @(posedge clk)partial<=operand_a*operand_b;
    always @(posedge clk or posedge rst)begin
        if(rst)begin held_a<=0;held_b<=0;phase<=0;product<=0;ready<=0;busy<=0;accumulated<=0;end
        else begin
            ready<=0;
            if(start && !busy)begin held_a<=a;held_b<=b;phase<=0;busy<=1;end
            else if(busy)case(phase)
                0:phase<=1;
                1:begin accumulated<=expanded;phase<=2;end
                2:begin accumulated<=accumulated+(expanded<<<17);phase<=3;end
                3:begin accumulated<=accumulated+(expanded<<<17);phase<=4;end
                4:begin product<=accumulated+(expanded<<<34);ready<=1;busy<=0;end
                default:busy<=0;
            endcase
        end
    end
endmodule
