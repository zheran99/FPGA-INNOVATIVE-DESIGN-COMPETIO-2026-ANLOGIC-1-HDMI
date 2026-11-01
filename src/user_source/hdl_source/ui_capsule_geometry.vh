function ui_capsule_body;
    input [11:0] cx,cy;
    begin
        ui_capsule_body=cx<12'd48 && cy<12'd26 &&
            !((cx==0 || cx==47) && (cy==0 || cy==25));
    end
endfunction
function ui_capsule_knob;
    input [11:0] cx,cy;
    input on;
    reg [11:0] kx,ky;
    begin
        kx=cx-(on ? 12'd26 : 12'd4);
        ky=cy-12'd4;
        ui_capsule_knob=kx<12'd18 && ky<12'd18 &&
            !((kx==0 || kx==17) && (ky==0 || ky==17));
    end
endfunction
