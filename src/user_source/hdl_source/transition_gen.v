`timescale 1ns / 1ps

module transition_gen #(
    parameter OUT_W       = 1280,
    parameter OUT_H       = 720,
    parameter TRAN_FRAMES = 20       // 转场时长（帧）
)(
    input  wire        I_clk,
    input  wire        I_rst,

    input  wire        I_hs,
    input  wire        I_vs,
    input  wire        I_de,

    input  wire [31:0] I_rd_a,
    input  wire        I_empty_a,

    input  wire [31:0] I_rd_b,
    input  wire        I_empty_b,

    input  wire [2:0]  I_tran_type,   // 1..5（0=瞬切）
    input  wire        I_tran_en,     // 转场总开关
    input  wire        I_tran_start,  // 切图脉冲（触发一次转场）

    output wire        O_read_en,
    output wire        O_de,
    output wire        O_hs,
    output wire        O_vs,
    output wire [23:0] O_rgb,

    output wire        O_tran_act,
    output wire [7:0]  O_tran_prog
);

    localparam LATENCY = 24;
    reg [LATENCY-1:0] de_d, hs_d, vs_d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            de_d <= {LATENCY{1'b0}};
            hs_d <= {LATENCY{1'b0}};
            vs_d <= {LATENCY{1'b0}};
        end else begin
            de_d <= {de_d[LATENCY-2:0], I_de};
            hs_d <= {hs_d[LATENCY-2:0], I_hs};
            vs_d <= {vs_d[LATENCY-2:0], I_vs};
        end
    end
    assign O_de = de_d[LATENCY-1];
    assign O_hs = hs_d[LATENCY-1];
    assign O_vs = vs_d[LATENCY-1];

    reg [10:0] x_d18;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)      x_d18 <= 11'd0;
        else if (!de_d[18]) x_d18 <= 11'd0;
        else            x_d18 <= x_d18 + 1'b1;
    end
    assign O_read_en = de_d[18] & ~x_d18[0];

    reg        read_en_d1;
    reg [31:0] word_a, word_b;
    reg        wvalid_a, wvalid_b;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            read_en_d1 <= 1'b0;
            word_a     <= 32'd0;
            word_b     <= 32'd0;
            wvalid_a   <= 1'b0;
            wvalid_b   <= 1'b0;
        end else begin
            read_en_d1 <= O_read_en;
            if (read_en_d1) begin
                word_a     <= I_rd_a;
                word_b     <= I_rd_b;
                wvalid_a   <= 1'b1;
                wvalid_b   <= 1'b1;
            end else if (!de_d[20]) begin
                wvalid_a   <= 1'b0;
                wvalid_b   <= 1'b0;
            end
        end
    end

    reg out_phase;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst)        out_phase <= 1'b0;
        else if (!de_d[20]) out_phase <= 1'b0;
        else if (de_d[20])  out_phase <= ~out_phase;
    end

    wire [15:0] pix_a = out_phase ? word_a[31:16] : word_a[15:0];
    wire [15:0] pix_b = out_phase ? word_b[31:16] : word_b[15:0];

    wire [7:0] a_r = {pix_a[15:11], pix_a[15:13]};
    wire [7:0] a_g = {pix_a[10:5],  pix_a[10:9]};
    wire [7:0] a_b = {pix_a[4:0],   pix_a[4:2]};
    wire [7:0] b_r = {pix_b[15:11], pix_b[15:13]};
    wire [7:0] b_g = {pix_b[10:5],  pix_b[10:9]};
    wire [7:0] b_b = {pix_b[4:0],   pix_b[4:2]};

    wire [7:0] na_r = (de_d[20] && wvalid_a) ? a_r : 8'd0;
    wire [7:0] na_g = (de_d[20] && wvalid_a) ? a_g : 8'd0;
    wire [7:0] na_b = (de_d[20] && wvalid_a) ? a_b : 8'd0;
    wire [7:0] nb_r = (de_d[20] && wvalid_b) ? b_r : 8'd0;
    wire [7:0] nb_g = (de_d[20] && wvalid_b) ? b_g : 8'd0;
    wire [7:0] nb_b = (de_d[20] && wvalid_b) ? b_b : 8'd0;

    reg        vs_d1;
    wire       vs_fall = vs_d1 & ~I_vs;   // 场同步结束沿 = 帧边界
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) vs_d1 <= 1'b0;
        else       vs_d1 <= I_vs;
    end

    reg        trans_active;
    reg        trans_pending;
    reg [4:0]  frame_cnt;    // 0..TRAN_FRAMES-1
    reg [7:0]  progress;     // 帧级寄存器（原来是组合，每像素都乘一遍 时序爆）

    assign O_tran_act  = trans_active;
    assign O_tran_prog = progress;

    wire [8:0] nx_p1   = {1'b0, frame_cnt} + 6'd2;
    wire [8:0] nx_px13 = nx_p1 * 9'd13;
    wire [7:0] nx_prog = (nx_px13 > 9'd255) ? 8'd255 : nx_px13[7:0];

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            trans_active  <= 1'b0;
            trans_pending <= 1'b0;
            frame_cnt     <= 5'd0;
            progress      <= 8'd0;
        end else begin
            if (I_tran_start && I_tran_en && (I_tran_type != 3'd0))
                trans_pending <= 1'b1;

            if (vs_fall) begin
                if (trans_pending && !trans_active) begin
                    trans_active  <= 1'b1;
                    trans_pending <= 1'b0;
                    frame_cnt     <= 5'd0;
                    progress      <= 8'd13;      // (0+1)*13
                end else if (trans_active) begin
                    if (frame_cnt >= (TRAN_FRAMES - 1)) begin
                        trans_active <= 1'b0;
                        progress     <= 8'd255;   // 结束帧全显新图
                    end else begin
                        frame_cnt <= frame_cnt + 5'd1;
                        progress  <= nx_prog;
                    end
                end
            end
        end
    end

    reg [10:0] p_slide_h;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            p_slide_h  <= 11'd0;
        end else if (vs_fall) begin

            if (trans_pending && !trans_active)
                p_slide_h <= 11'd0;
            else
                p_slide_h <= {3'b0, progress} * 3'd5;             // progress*5 0..1275
        end
    end

    reg [10:0] ox;
    reg [9:0]  oy;
    reg        de20_d1;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin ox <= 11'd0; oy <= 10'd0; de20_d1 <= 1'b0; end
        else begin
            de20_d1 <= de_d[20];
            if (!de_d[20]) ox <= 11'd0;
            else           ox <= ox + 1'b1;
            if (vs_d[LATENCY-1]) oy <= 10'd0;
            else if (de_d[20] && !de20_d1) oy <= oy + 1'b1;
        end
    end

    wire [11:0] wipe_sum = {1'b0, ox} + {1'b0, p_slide_h};   // ox + s（12 位，0..2554）

    wire [3:0] bar_d       = ox[4] ? ox[3:0] : (4'd15 - ox[3:0]);   // 到条中心距离 0..15
    wire [3:0] bar_scale   = (8'd255 - progress) >> 4;              // 150，梯度摊平

    wire [7:0] bar_pp0={4'd0,bar_d} & {8{bar_scale[0]}};
    wire [7:0] bar_pp1={3'd0,bar_d,1'd0} & {8{bar_scale[1]}};
    wire [7:0] bar_pp2={2'd0,bar_d,2'd0} & {8{bar_scale[2]}};
    wire [7:0] bar_pp3={1'd0,bar_d,3'd0} & {8{bar_scale[3]}};
    wire [7:0] bar_sum1=bar_pp0 ^ bar_pp1 ^ bar_pp2;
    wire [7:0] bar_carry1=((bar_pp0 & bar_pp1) | (bar_pp0 & bar_pp2) | (bar_pp1 & bar_pp2)) << 1;
    wire [7:0] bar_sum2=bar_sum1 ^ bar_carry1 ^ bar_pp3;
    wire [7:0] bar_carry2=((bar_sum1 & bar_carry1) | (bar_sum1 & bar_pp3) | (bar_carry1 & bar_pp3)) << 1;
    wire [7:0] bar_dxscale=bar_sum2 + bar_carry2; // 0..225
    wire [7:0] bar_w       = (progress >= bar_dxscale) ? (progress - bar_dxscale) : 8'd0;

    wire [8:0] chk_p2 = {1'b0, progress} << 1;                             // progress*2, 0..510
    wire [7:0] chk_ev = (chk_p2 > 9'd255) ? 8'd255 : chk_p2[7:0];          // 偶块 0255（前半）
    wire [8:0] chk_od9 = (chk_p2 > 9'd255) ? (chk_p2 - 9'd255) : 9'd0;     // 奇块 ramp 0..255（9 位，MSB 恒 0）
    wire [7:0] chk_od  = chk_od9[7:0];                                     // 奇块 0255（后半）
    wire [7:0] chk_w  = (oy[6] ^ ox[6]) ? chk_od : chk_ev;                 // (行+列)&1 分奇偶

    reg [7:0] w_comb;
    always @(*) begin
        case (I_tran_type)
            3'd1: w_comb = progress;                                            // 真交叉淡化
            3'd2: w_comb = (wipe_sum < 12'd1280) ? 8'd0 : 8'd255;               // 水平擦除（新从右滑入）
            3'd3: w_comb = (oy[4:0] < progress[7:3]) ? 8'd255 : 8'd0;           // 百叶窗（水平 32px 条带同时展开）
            3'd4: w_comb = bar_w;           // 竖条（每条自中心向两侧黑新淡入）
            3'd5: w_comb = chk_w;           // 网格（20×12 棋盘格两波溶解）
            default: w_comb = 8'd255;                                           // 瞬切/关闭
        endcase
    end

    wire [7:0] w_eff = trans_active ? w_comb : 8'd255;

    reg [7:0]  old_r, old_g, old_b;
    reg [7:0]  new_r, new_g, new_b;
    reg [7:0]  w_r;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            old_r <= 8'd0; old_g <= 8'd0; old_b <= 8'd0;
            new_r <= 8'd0; new_g <= 8'd0; new_b <= 8'd0;
            w_r   <= 8'd0;
        end else begin
            old_r <= (I_tran_type == 3'd4) ? 8'd0 : nb_r; old_g <= (I_tran_type == 3'd4) ? 8'd0 : nb_g; old_b <= (I_tran_type == 3'd4) ? 8'd0 : nb_b;   // 旧图 = B；竖条(4)门控为黑 黑新淡入
            new_r <= na_r; new_g <= na_g; new_b <= na_b;   // 新图 = A
            w_r   <= w_eff;
        end
    end

    wire [8:0]  w_inv = 9'd256 - {1'b0, w_r};                 // 1..256
    reg [16:0]  m_or_r, m_og_r, m_ob_r;
    reg [15:0]  m_nr_r, m_ng_r, m_nb_r;
    reg [7:0]   old_r2, old_g2, old_b2;
    reg [7:0]   new_r2, new_g2, new_b2;
    reg [7:0]   w_r2;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            m_or_r <= 17'd0; m_og_r <= 17'd0; m_ob_r <= 17'd0;
            m_nr_r <= 16'd0; m_ng_r <= 16'd0; m_nb_r <= 16'd0;
            old_r2 <= 8'd0; old_g2 <= 8'd0; old_b2 <= 8'd0;
            new_r2 <= 8'd0; new_g2 <= 8'd0; new_b2 <= 8'd0;
            w_r2   <= 8'd0;
        end else begin
            m_or_r <= old_r * w_inv;    // 8×9 = 17 bit
            m_og_r <= old_g * w_inv;
            m_ob_r <= old_b * w_inv;
            m_nr_r <= new_r * w_r;      // 8×8 = 16 bit
            m_ng_r <= new_g * w_r;
            m_nb_r <= new_b * w_r;
            old_r2 <= old_r; old_g2 <= old_g; old_b2 <= old_b;
            new_r2 <= new_r; new_g2 <= new_g; new_b2 <= new_b;
            w_r2   <= w_r;
        end
    end

    wire [16:0] s_r = m_or_r + {1'b0, m_nr_r};
    wire [16:0] s_g = m_og_r + {1'b0, m_ng_r};
    wire [16:0] s_b = m_ob_r + {1'b0, m_nb_r};
    wire [7:0] bl_r = (w_r2 == 8'd0)   ? old_r2 :
                      (w_r2 == 8'd255) ? new_r2 : s_r[16:8];
    wire [7:0] bl_g = (w_r2 == 8'd0)   ? old_g2 :
                      (w_r2 == 8'd255) ? new_g2 : s_g[16:8];
    wire [7:0] bl_b = (w_r2 == 8'd0)   ? old_b2 :
                      (w_r2 == 8'd255) ? new_b2 : s_b[16:8];

    reg [23:0] rgb_out;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) rgb_out <= 24'd0;
        else       rgb_out <= {bl_r, bl_g, bl_b};
    end

    // 消隐期输出干净黑
    assign O_rgb = de_d[LATENCY-1] ? rgb_out : 24'd0;

endmodule
