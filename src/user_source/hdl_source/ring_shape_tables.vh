    function [11:0] lobe_slope;
        input [4:0] index;
        begin case(index)
            5'd0: lobe_slope=12'h0;
            5'd1: lobe_slope=12'h484;
            5'd2: lobe_slope=12'h41e;
            5'd3: lobe_slope=12'h3c9;
            5'd4: lobe_slope=12'h380;
            5'd5: lobe_slope=12'h341;
            5'd6: lobe_slope=12'h30b;
            5'd7: lobe_slope=12'h2db;
            5'd8: lobe_slope=12'h2b1;
            5'd9: lobe_slope=12'h28c;
            5'd10: lobe_slope=12'h26a;
            5'd11: lobe_slope=12'h24c;
            5'd12: lobe_slope=12'h230;
            5'd13: lobe_slope=12'h217;
            5'd14: lobe_slope=12'h200;
            5'd15: lobe_slope=12'h1eb;
            5'd16: lobe_slope=12'h1d8;
            5'd17: lobe_slope=12'h1c6;
            5'd18: lobe_slope=12'h1b5;
            5'd19: lobe_slope=12'h1a6;
            5'd20: lobe_slope=12'h197;
            5'd21: lobe_slope=12'h18a;
            5'd22: lobe_slope=12'h17d;
            5'd23: lobe_slope=12'h171;
            5'd24: lobe_slope=12'h166;
            5'd25: lobe_slope=12'h15c;
            5'd26: lobe_slope=12'h152;
            5'd27: lobe_slope=12'h149;
            5'd28: lobe_slope=12'h140;
            default: lobe_slope=0;
        endcase end
    endfunction
