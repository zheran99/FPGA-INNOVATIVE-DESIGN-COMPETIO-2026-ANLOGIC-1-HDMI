`timescale 1ns / 1ps

module uart_cmd #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter [31:0]  VERSION     = 32'd1003,       // VERS 回显
    parameter integer RPRT_MS     = 100,            // 主动回报周期
    parameter integer TIMEOUT_MS  = 100             // 帧超时（\r\n 之前无字节）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire [7:0]  I_rx_data,
    input  wire        I_rx_valid,
    output reg  [7:0]  O_rx_cnt,        // 收到的字节计数（低 8 位，数码管诊断）

    output reg  [7:0]  O_tx_data,
    output reg         O_tx_start,      // 1 拍脉冲
    input  wire        I_tx_busy,
    output reg  [7:0]  O_tx_cnt,        // 已发送的字节计数（低 8 位）

    input  wire [2:0]  I_mode_num,      // 0..7 回显 1..8
    input  wire [7:0]  I_bri,
    input  wire [7:0]  I_con,
    input  wire [7:0]  I_sat,
    input  wire [7:0]  I_vol,
    input  wire [2:0]  I_tran_type,
    input  wire        I_tran_en,
    input  wire [4:0]  I_img_idx,       // 当前图号 0..16
    input  wire [4:0]  I_img_total,     // 卡上张数 0..16
    input  wire        I_auto_on,       // 轮播开关（已同步到 clk 域）
    input  wire [1:0]  I_sub_mode,      // 字幕模式 0..3（0=关）
    input  wire [1:0]  I_sd_state,      // 0=OK 1=SCAN 2=NOIMG 3=NOSD
    input  wire [1:0]  I_ad_language,
    input  wire        I_ad_layout,

    output reg         O_wr,
    output reg  [3:0]  O_wr_sel,
    output reg  [7:0]  O_wr_val,
    output reg         O_rset,          // 恢复全部默认值（同时送往 p5/p6/p7）

    output reg         O_p5_wr,
    output reg  [2:0]  O_p5_sel,        // 0=SUB 1=SBG 2=MON 3=SIZE
    output reg  [1:0]  O_p5_val,
    output reg         O_p6_wr,
    output reg  [2:0]  O_p6_sel,        // 0=LOGO 1=广告 2=背景 3=语言 4=布局
    output reg  [2:0]  O_p6_val,
    output reg         O_p7_wr,         // SPEn / SPSn（ p7_reg）
    output reg  [1:0]  O_p7_sel,        // 0=SPE(频谱开关) 1=SPS(方向)
    output reg  [1:0]  O_p7_val,

    output reg         O_pause_set,     // PAUS
    output reg         O_pause_clr,     // RUNN

    output reg         O_next_pulse,    // NEXT
    output reg         O_prev_pulse,    // PREV
    output reg         O_auto_set,      // TRNn：1 = 本条要设置轮播开关
    output reg         O_auto_val
);

    localparam [3:0] S_BRI  = 4'd0,
                     S_CON  = 4'd1,
                     S_SAT  = 4'd2,
                     S_VOL  = 4'd3,
                     S_TRAN = 4'd4,
                     S_TE   = 4'd5;

    localparam [2:0] P5_SUB = 3'd0, P5_SBG = 3'd1, P5_MON = 3'd2,
                     P5_SIZE = 3'd3;
    localparam [1:0] P6_LOGO = 2'd0;

    localparam [1:0] P7_WAVE = 2'd0, P7_HORZ = 2'd1, P7_SHAPE = 2'd3;

    localparam [2:0] K_NONE = 3'd0, K_PONG = 3'd1, K_SET = 3'd2,
                     K_ACT  = 3'd3, K_VER  = 3'd4, K_ERR = 3'd5,
                     K_STAT = 3'd6, K_ADST = 3'd7;

    localparam [2:0] E_NONE = 3'd0, E_CMD = 3'd1, E_FMT = 3'd2, E_LONG = 3'd3,
                     E_TIME = 3'd4, E_MODE = 3'd5, E_IMPL = 3'd6;

    localparam [31:0] C_PING = 32'h50494E47, C_STAT = 32'h53544154,
                      C_RSET = 32'h52534554, C_VERS = 32'h56455253,
                      C_SYNC = 32'h53594E43, C_RPT  = 32'h52505400,
                      C_B    = 32'h42000000, C_C    = 32'h43000000,
                      C_S    = 32'h53000000, C_V    = 32'h56000000,
                      C_T    = 32'h54000000, C_TE   = 32'h54450000,
                      C_NEXT = 32'h4E455854, C_PREV = 32'h50524556,
                      C_IMG  = 32'h494D4700, C_TRN  = 32'h54524E00,
                      C_PAUS = 32'h50415553,
                      C_RUNN = 32'h52554E4E, C_SUB  = 32'h53554200,
                      C_SSP  = 32'h53535000, C_SSZ  = 32'h53535A00,
                      C_SBG  = 32'h53424700, C_LOG  = 32'h4C4F4700,
                      C_SPE  = 32'h53504500, C_SPS  = 32'h53505300,
                      C_SPM  = 32'h53504D00,
                      C_MON  = 32'h4D4F4E00,
                      C_ADL  = 32'h41444C00, C_ADP = 32'h41445000,
                      C_ADE  = 32'h41444500, C_ADB = 32'h41444200,
                      C_ADST = 32'h41445354;

    localparam [2:0] M_P8 = 3'd7;       // 串口调试（唯一允许串口命令的模式）

    localparam [3:0] S_LOCAL = 4'hF;

    localparam [7:0] V_D3 = 8'h30 + ((VERSION / 1000) % 10);
    localparam [7:0] V_D2 = 8'h30 + ((VERSION / 100) % 10);
    localparam [7:0] V_D1 = 8'h30 + ((VERSION / 10) % 10);
    localparam [7:0] V_D0 = 8'h30 + (VERSION % 10);

    function is_digit;
        input [7:0] c;
        begin
            is_digit = (c >= 8'h30) && (c <= 8'h39);
        end
    endfunction

    function is_alpha;
        input [7:0] c;
        begin
            is_alpha = ((c >= 8'h41) && (c <= 8'h5A)) ||   // A-Z
                       ((c >= 8'h61) && (c <= 8'h7A));      // a-z
        end
    endfunction

    function [7:0] to_upper;
        input [7:0] c;
        begin
            to_upper = ((c >= 8'h61) && (c <= 8'h7A)) ? (c - 8'h20) : c;
        end
    endfunction

    function [7:0] dec3;
        input [7:0] v;
        input [1:0] which;
        reg   [7:0] h, r, t;
        reg   [7:0] t10;
        reg   [3:0] digit;
        begin
            h = (v >= 8'd200) ? 8'd2 : (v >= 8'd100) ? 8'd1 : 8'd0;
            r = v - ((h == 8'd2) ? 8'd200 : (h == 8'd1) ? 8'd100 : 8'd0);
            t = (r >= 8'd90) ? 8'd9 : (r >= 8'd80) ? 8'd8 :
                (r >= 8'd70) ? 8'd7 : (r >= 8'd60) ? 8'd6 :
                (r >= 8'd50) ? 8'd5 : (r >= 8'd40) ? 8'd4 :
                (r >= 8'd30) ? 8'd3 : (r >= 8'd20) ? 8'd2 :
                (r >= 8'd10) ? 8'd1 : 8'd0;
            t10  = {1'b0, t[3:0], 3'd0} + {3'd0, t[3:0], 1'b0};

            digit = (which == 2'd0) ? h[3:0] :
                    (which == 2'd1) ? t[3:0] : (r[3:0] - t10[3:0]);
            dec3 = {4'h3, digit};
        end
    endfunction

    function [7:0] clamp8;
        input [15:0] v;
        input [7:0]  lo;
        input [7:0]  hi;
        begin
            if (v < {8'd0, lo})      clamp8 = lo;
            else if (v > {8'd0, hi}) clamp8 = hi;
            else                     clamp8 = v[7:0];
        end
    endfunction

    localparam integer TO_CLKS = (CLK_FREQ_HZ / 1000) * TIMEOUT_MS;

    reg [7:0]  fb0, fb1, fb2, fb3;         // 行缓冲（左对齐）
    reg [2:0]  flen;
    reg        ovfl;                       // 超过 4 字符
    reg [31:0] to_cnt;
    reg        rx_active;

    reg [7:0]  pb0, pb1, pb2, pb3;         // 定格副本（执行期间不被新帧覆盖）
    reg [2:0]  plen;
    reg        povfl;
    reg        req_pending;
    reg        req_timeout;
    reg        req_take;                   // 由状态机给出（此处只读）

    wire       is_term = (I_rx_data == 8'h0D) || (I_rx_data == 8'h0A);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            fb0 <= 8'd0; fb1 <= 8'd0; fb2 <= 8'd0; fb3 <= 8'd0;
            flen <= 3'd0; ovfl <= 1'b0; to_cnt <= 32'd0; rx_active <= 1'b0;
            pb0 <= 8'd0; pb1 <= 8'd0; pb2 <= 8'd0; pb3 <= 8'd0;
            plen <= 3'd0; povfl <= 1'b0; req_pending <= 1'b0; req_timeout <= 1'b0;
            O_rx_cnt <= 8'd0;
        end
        else begin
            if (I_rx_valid) O_rx_cnt <= O_rx_cnt + 8'd1;

            if (req_take) req_pending <= 1'b0;

            if (I_rx_valid && is_term) begin

                if (rx_active) begin
                    pb0 <= fb0; pb1 <= fb1; pb2 <= fb2; pb3 <= fb3;
                    plen <= flen; povfl <= ovfl;
                    req_timeout <= 1'b0;
                    req_pending <= 1'b1;
                end
                flen <= 3'd0; ovfl <= 1'b0; to_cnt <= 32'd0; rx_active <= 1'b0;
            end
            else if (I_rx_valid) begin
                rx_active <= 1'b1;
                to_cnt    <= 32'd0;
                if (!ovfl) begin
                    if      (flen == 3'd0) fb0 <= to_upper(I_rx_data);
                    else if (flen == 3'd1) fb1 <= to_upper(I_rx_data);
                    else if (flen == 3'd2) fb2 <= to_upper(I_rx_data);
                    else if (flen == 3'd3) fb3 <= to_upper(I_rx_data);
                    if (flen >= 3'd4) ovfl <= 1'b1;      // 第 5 个字符 ERR LONG
                    else              flen <= flen + 3'd1;
                end
            end
            else if (rx_active) begin
                if (to_cnt == (TO_CLKS - 1)) begin
                    pb0 <= fb0; pb1 <= fb1; pb2 <= fb2; pb3 <= fb3;
                    plen <= flen; povfl <= ovfl;
                    req_timeout <= 1'b1;
                    req_pending <= 1'b1;
                    flen <= 3'd0; ovfl <= 1'b0; to_cnt <= 32'd0; rx_active <= 1'b0;
                end
                else to_cnt <= to_cnt + 32'd1;
            end
        end
    end

    wire [7:0] r0 = pb3, r1 = pb2, r2 = pb1, r3 = pb0;

    wire        dg0 = is_digit(r0);
    wire        dg1 = dg0 & is_digit(r1);
    wire        dg2 = dg1 & is_digit(r2);
    wire        dg3 = dg2 & is_digit(r3);

    // x*10 = x*8 + x*2

    wire [7:0]  pd0 = r0 - 8'd48;
    wire [7:0]  pd1 = r1 - 8'd48;
    wire [7:0]  pd2 = r2 - 8'd48;
    wire [15:0] pv1 = {5'd0, pd1[3:0], 3'd0} + {7'd0, pd1[3:0], 1'b0};
    wire [15:0] pv2 = {3'd0, pd2[3:0], 6'd0} + {4'd0, pd2[3:0], 5'd0}
                    + {7'd0, pd2[3:0], 2'd0};

    wire [15:0] pval = (dg0 ? {8'd0, pd0} : 16'd0)
                     + (dg1 ? pv1        : 16'd0)
                     + (dg2 ? pv2        : 16'd0);

    wire [2:0]  n_dig = {2'd0, dg0} + {2'd0, dg1} + {2'd0, dg2} + {2'd0, dg3};
    wire [2:0]  n_ltr = plen - n_dig;

    wire [7:0]  cc0 = (n_ltr >= 3'd1) ? pb0 : 8'h00;
    wire [7:0]  cc1 = (n_ltr >= 3'd2) ? pb1 : 8'h00;
    wire [7:0]  cc2 = (n_ltr >= 3'd3) ? pb2 : 8'h00;
    wire [7:0]  cc3 = (n_ltr >= 3'd4) ? pb3 : 8'h00;

    wire [31:0] cmd_vec = {cc0, cc1, cc2, cc3};

    wire cmd_bad_fmt = (n_ltr >= 3'd1) & (is_digit(cc0) | is_digit(cc1) |
                                          is_digit(cc2) | is_digit(cc3));
    wire cmd_empty = (n_ltr == 3'd0);

    wire cmd_char_bad = ((n_ltr >= 3'd1) & ~is_alpha(cc0) & ~is_digit(cc0)) |
                        ((n_ltr >= 3'd2) & ~is_alpha(cc1) & ~is_digit(cc1)) |
                        ((n_ltr >= 3'd3) & ~is_alpha(cc2) & ~is_digit(cc2)) |
                        ((n_ltr >= 3'd4) & ~is_alpha(cc3) & ~is_digit(cc3));

    wire cmd_short = (plen != 3'd4);

    reg [2:0]  d_err;
    reg [2:0]  d_kind;
    reg [3:0]  d_wsel;
    reg [15:0] d_lval;
    reg        d_wr, d_rset, d_p5wr, d_p6wr, d_p7wr;
    reg        d_paus_set, d_paus_clr, d_next, d_prev, d_autoset, d_autoval;
    reg [2:0]  d_p5sel;
    reg [1:0]  d_p5val, d_p7sel, d_p7val;
    reg [2:0]  d_p6val;                 // 3 位：广告背景有 7 档（0..6）
    reg [2:0]  d_p6sel;

    wire [7:0] c_sub  = clamp8(pval, 8'd0, 8'd3);
    wire [7:0] c_sbg  = clamp8(pval, 8'd0, 8'd2);
    wire [7:0] c_logo = clamp8(pval, 8'd0, 8'd2);

    wire [7:0] c_abg  = clamp8(pval, 8'd0, 8'd6);
    wire [7:0] c_te   = clamp8(pval, 8'd0, 8'd1);

    wire [7:0] c_bin  = clamp8(pval, 8'd0, 8'd1);

    wire [7:0] c_ssz  = clamp8(pval, 8'd0, 8'd1);

    wire [7:0] c_sps  = clamp8(pval, 8'd1, 8'd2);
    wire [7:0] c_spm  = clamp8(pval, 8'd1, 8'd4);

    always @(*) begin
        d_err = E_NONE; d_kind = K_NONE; d_wsel = 4'd0; d_lval = 16'd0;
        d_wr = 1'b0; d_rset = 1'b0; d_p5wr = 1'b0; d_p6wr = 1'b0;
        d_p7wr = 1'b0;
        d_paus_set = 1'b0; d_paus_clr = 1'b0;
        d_p5sel = 3'd0; d_p5val = 2'd0; d_p6sel = 2'd0; d_p6val = 3'd0;
        d_p7sel = 2'd0; d_p7val = 2'd0;
        d_next = 1'b0; d_prev = 1'b0; d_autoset = 1'b0; d_autoval = 1'b0;

        if (req_timeout) begin
            d_err = E_TIME; d_kind = K_ERR;
        end

        else if (I_mode_num != M_P8) begin
            d_err = E_MODE; d_kind = K_ERR;
        end
        else if (povfl) begin

            d_err = E_LONG; d_kind = K_ERR;
        end
        else if (cmd_short) begin

            d_err = E_FMT; d_kind = K_ERR;
        end
        else if (cmd_empty || cmd_char_bad) begin
            d_err = E_CMD; d_kind = K_ERR;
        end
        else if (cmd_bad_fmt) begin
            d_err = E_FMT; d_kind = K_ERR;
        end
        else begin
            case (cmd_vec)
            C_PING: d_kind = K_PONG;
            C_STAT: d_kind = K_STAT;
            C_ADST: d_kind = K_ADST;
            C_ADL: begin d_wsel=S_LOCAL;d_p6wr=1'b1;d_p6sel=3'd3;
                         d_p6val=c_logo[1:0];d_lval={8'd0,c_logo};d_kind=K_SET;end
            C_ADP: begin d_wsel=S_LOCAL;d_p6wr=1'b1;d_p6sel=3'd4;
                         d_p6val=c_bin[1:0];d_lval={8'd0,c_bin};d_kind=K_SET;end
            C_ADE: begin d_wsel=S_LOCAL;d_p6wr=1'b1;d_p6sel=3'd1;
                         d_p6val=c_bin[1:0];d_lval={8'd0,c_bin};d_kind=K_SET;end
            C_ADB: begin d_wsel=S_LOCAL;d_p6wr=1'b1;d_p6sel=3'd2;
                         d_p6val=c_abg[2:0];d_lval={8'd0,c_abg};d_kind=K_SET;end
            C_VERS: d_kind = K_VER;
            C_RSET: begin d_rset = 1'b1; d_kind = K_ACT; end
            C_SYNC: begin d_err = E_IMPL; d_kind = K_ERR; end
            C_RPT : begin d_wsel = S_LOCAL; d_lval = {8'd0, c_bin}; d_kind = K_SET; end
            C_B: begin d_wsel = S_BRI; d_lval = clamp8(pval, 8'd0,  8'd100);
                       d_wr = 1'b1; d_kind = K_SET; end
            C_C: begin d_wsel = S_CON; d_lval = clamp8(pval, 8'd50, 8'd200);
                       d_wr = 1'b1; d_kind = K_SET; end
            C_S: begin d_wsel = S_SAT; d_lval = clamp8(pval, 8'd0,  8'd200);
                       d_wr = 1'b1; d_kind = K_SET; end
            C_V: begin d_wsel = S_VOL; d_lval = clamp8(pval, 8'd0,  8'd100);
                       d_wr = 1'b1; d_kind = K_SET; end
            C_T : begin d_wsel = S_TRAN; d_lval = clamp8(pval, 8'd0, 8'd5);
                        d_wr = 1'b1; d_kind = K_SET; end
            C_TE: begin d_wsel = S_TE;   d_lval = {8'd0, c_te};
                        d_wr = 1'b1; d_kind = K_SET; end

            C_NEXT: begin d_next = 1'b1; d_kind = K_ACT; end
            C_PREV: begin d_prev = 1'b1; d_kind = K_ACT; end
            C_TRN : begin

                        d_wsel = S_LOCAL;
                        d_autoset = (c_bin != {7'd0, I_auto_on});
                        d_autoval = c_bin[0];
                        d_lval = {8'd0, c_bin}; d_kind = K_SET;
                    end
            C_IMG : begin d_err = E_IMPL; d_kind = K_ERR; end
            C_PAUS: begin d_paus_set = 1'b1; d_kind = K_ACT; end
            C_RUNN: begin d_paus_clr = 1'b1; d_kind = K_ACT; end
            C_SUB: begin d_wsel = S_LOCAL; d_p5wr = 1'b1; d_p5sel = P5_SUB;
                        d_p5val = c_sub[1:0]; d_lval = {8'd0, c_sub}; d_kind = K_SET; end
            C_SBG: begin d_wsel = S_LOCAL; d_p5wr = 1'b1; d_p5sel = P5_SBG;
                        d_p5val = c_sbg[1:0]; d_lval = {8'd0, c_sbg}; d_kind = K_SET; end
            C_MON: begin d_wsel = S_LOCAL; d_p5wr = 1'b1; d_p5sel = P5_MON;
                        d_p5val = c_bin[1:0]; d_lval = {8'd0, c_bin}; d_kind = K_SET; end
            C_SSP: begin d_err = E_IMPL; d_kind = K_ERR; end   // 无速度字段

            C_SSZ: begin d_wsel = S_LOCAL; d_p5wr = 1'b1; d_p5sel = P5_SIZE;
                        d_p5val = c_ssz[1:0]; d_lval = {8'd0, c_ssz};
                        d_kind = K_SET; end

            C_LOG : begin d_wsel = S_LOCAL; d_p6wr = 1'b1; d_p6sel = P6_LOGO;
                         d_p6val = c_logo[1:0]; d_lval = {8'd0, c_logo};
                         d_kind = K_SET; end

            C_SPE: begin d_wsel = S_LOCAL; d_p7wr = 1'b1; d_p7sel = P7_WAVE;
                        d_p7val = c_bin[1:0]; d_lval = {8'd0, c_bin};
                        d_kind = K_SET; end
            C_SPS: begin d_wsel = S_LOCAL; d_p7wr = 1'b1; d_p7sel = P7_HORZ;
                        d_p7val = {1'b0, (c_sps == 8'd2)};
                        d_lval = {8'd0, c_sps}; d_kind = K_SET; end
            C_SPM: begin d_wsel = S_LOCAL; d_p7wr = 1'b1; d_p7sel = P7_SHAPE;
                        d_p7val = c_spm[1:0]-2'd1;
                        d_lval = {8'd0, c_spm}; d_kind = K_SET; end
            default: begin d_err = E_CMD; d_kind = K_ERR; end
            endcase
        end
    end

    reg [2:0]  r_kind;
    reg [2:0]  r_err;
    reg [3:0]  r_sel;
    reg [15:0] r_lval;
    reg [2:0]  r_nltr;
    reg [31:0] r_cmd;
    reg        r_hash;
    reg        r_rprt_en;
    reg [31:0] rprt_cnt;

    reg [6:0]  r_len;

    reg [7:0] rb_val;
    always @(*) begin
        case (r_sel)
            S_BRI : rb_val = I_bri;
            S_CON : rb_val = I_con;
            S_SAT : rb_val = I_sat;
            S_VOL : rb_val = I_vol;
            S_TRAN: rb_val = {5'd0, I_tran_type};
            S_TE  : rb_val = {7'd0, I_tran_en};
            default: rb_val = r_lval[7:0];
        endcase
    end

    function [7:0] r_cmd_char;
        input [1:0] p;
        begin
            r_cmd_char = (p == 2'd0) ? r_cmd[31:24] :
                         (p == 2'd1) ? r_cmd[23:16] :
                         (p == 2'd2) ? r_cmd[15:8]  : r_cmd[7:0];
        end
    endfunction

    localparam [5:0] RT_PONG = 6'd0,  RT_VER  = 6'd4,
                     RT_ERRH = 6'd16, RT_OK   = 6'd20,
                     RT_BODY = 6'd24;

    (* ram_style = "dram" *) reg [7:0] resp_tpl [0:63];

    integer rti;
    initial begin
        for (rti = 0; rti < 64; rti = rti + 1) resp_tpl[rti] = 8'h00;
        resp_tpl[RT_PONG + 6'd0] = "P";
        resp_tpl[RT_PONG + 6'd1] = "O";
        resp_tpl[RT_PONG + 6'd2] = "N";
        resp_tpl[RT_PONG + 6'd3] = "G";

        resp_tpl[RT_VER + 6'd0]  = "O";
        resp_tpl[RT_VER + 6'd1]  = "K";
        resp_tpl[RT_VER + 6'd2]  = 8'h20;
        resp_tpl[RT_VER + 6'd3]  = "V";
        resp_tpl[RT_VER + 6'd4]  = "E";
        resp_tpl[RT_VER + 6'd5]  = "R";
        resp_tpl[RT_VER + 6'd6]  = "S";
        resp_tpl[RT_VER + 6'd7]  = "=";
        resp_tpl[RT_VER + 6'd8]  = V_D3;
        resp_tpl[RT_VER + 6'd9]  = V_D2;
        resp_tpl[RT_VER + 6'd10] = V_D1;
        resp_tpl[RT_VER + 6'd11] = V_D0;
        resp_tpl[RT_ERRH + 6'd0] = "E";
        resp_tpl[RT_ERRH + 6'd1] = "R";
        resp_tpl[RT_ERRH + 6'd2] = "R";
        resp_tpl[RT_ERRH + 6'd3] = 8'h20;
        resp_tpl[RT_OK + 6'd0] = "O";
        resp_tpl[RT_OK + 6'd1] = "K";
        resp_tpl[RT_OK + 6'd2] = 8'h20;

        resp_tpl[RT_BODY + (E_CMD << 2)  + 0] = "C";
        resp_tpl[RT_BODY + (E_CMD << 2)  + 1] = "M";
        resp_tpl[RT_BODY + (E_CMD << 2)  + 2] = "D";
        resp_tpl[RT_BODY + (E_FMT << 2)  + 0] = "F";
        resp_tpl[RT_BODY + (E_FMT << 2)  + 1] = "M";
        resp_tpl[RT_BODY + (E_FMT << 2)  + 2] = "T";
        resp_tpl[RT_BODY + (E_LONG << 2) + 0] = "L";
        resp_tpl[RT_BODY + (E_LONG << 2) + 1] = "O";
        resp_tpl[RT_BODY + (E_LONG << 2) + 2] = "N";
        resp_tpl[RT_BODY + (E_LONG << 2) + 3] = "G";
        resp_tpl[RT_BODY + (E_TIME << 2) + 0] = "T";
        resp_tpl[RT_BODY + (E_TIME << 2) + 1] = "I";
        resp_tpl[RT_BODY + (E_TIME << 2) + 2] = "M";
        resp_tpl[RT_BODY + (E_TIME << 2) + 3] = "E";
        resp_tpl[RT_BODY + (E_MODE << 2) + 0] = "M";
        resp_tpl[RT_BODY + (E_MODE << 2) + 1] = "O";
        resp_tpl[RT_BODY + (E_MODE << 2) + 2] = "D";
        resp_tpl[RT_BODY + (E_MODE << 2) + 3] = "E";
        resp_tpl[RT_BODY + (E_IMPL << 2) + 0] = "I";
        resp_tpl[RT_BODY + (E_IMPL << 2) + 1] = "M";
        resp_tpl[RT_BODY + (E_IMPL << 2) + 2] = "P";
        resp_tpl[RT_BODY + (E_IMPL << 2) + 3] = "L";
    end

    function [7:0] st_char;
        input [2:0] p;
        begin
            st_char = 8'h00;
            case (I_sd_state)
            2'd0: if      (p == 3'd0) st_char = "O";       // OK
                  else if (p == 3'd1) st_char = "K";
            2'd1: if      (p == 3'd0) st_char = "S";       // SCAN
                  else if (p == 3'd1) st_char = "C";
                  else if (p == 3'd2) st_char = "A";
                  else if (p == 3'd3) st_char = "N";
            2'd2: if      (p == 3'd0) st_char = "N";       // NOIMG
                  else if (p == 3'd1) st_char = "O";
                  else if (p == 3'd2) st_char = "I";
                  else if (p == 3'd3) st_char = "M";
                  else if (p == 3'd4) st_char = "G";
            default: if   (p == 3'd0) st_char = "N";       // NOSD
                     else if (p == 3'd1) st_char = "O";
                     else if (p == 3'd2) st_char = "S";
                     else if (p == 3'd3) st_char = "D";
            endcase
        end
    endfunction

    // STAT 状态行的字段起点

    localparam [6:0] ST_MODE = 7'd2,  ST_BRI  = 7'd11, ST_CON  = 7'd20,
                     ST_SAT  = 7'd29, ST_VOL  = 7'd38, ST_TRAN = 7'd47,
                     ST_TE   = 7'd54, ST_IMG  = 7'd62, ST_TOT  = 7'd66,
                     ST_AUTO = 7'd75, ST_SUB  = 7'd83, ST_ST   = 7'd90;

    wire [3:0] st_len = (I_sd_state == 2'd0) ? 4'd2 :
                        (I_sd_state == 2'd1) ? 4'd4 :
                        (I_sd_state == 2'd2) ? 4'd5 : 4'd4;

    wire [6:0] d_len =
        (d_kind == K_ADST) ? 7'd24 :
        (d_kind == K_PONG) ? 7'd6  :
        (d_kind == K_VER ) ? 7'd14 :
        (d_kind == K_SET ) ? (7'd9 + {4'd0, n_ltr}) :
        (d_kind == K_ACT ) ? (7'd5 + {4'd0, n_ltr}) :
        (d_kind == K_ERR ) ? (7'd6 + ((d_err == E_FMT || d_err == E_CMD) ? 7'd3 : 7'd4)) :
        (d_kind == K_STAT) ? (ST_ST + {3'd0, st_len} + 7'd2) :
        7'd0;

    (* ram_style = "dram" *) reg [7:0] stat_tpl [0:127];

    integer ti;
    initial begin
        for (ti = 0; ti < 128; ti = ti + 1) stat_tpl[ti] = 8'h00;
        stat_tpl[  0] = 8'h50;   // 'P'
        stat_tpl[  1] = 8'h3D;   // '='
        stat_tpl[  5] = 8'h20;   // ' '
        stat_tpl[  6] = 8'h42;   // 'B'
        stat_tpl[  7] = 8'h52;   // 'R'
        stat_tpl[  8] = 8'h49;   // 'I'
        stat_tpl[  9] = 8'h54;   // 'T'
        stat_tpl[ 10] = 8'h3D;   // '='
        stat_tpl[ 14] = 8'h20;   // ' '
        stat_tpl[ 15] = 8'h43;   // 'C'
        stat_tpl[ 16] = 8'h4F;   // 'O'
        stat_tpl[ 17] = 8'h4E;   // 'N'
        stat_tpl[ 18] = 8'h53;   // 'S'
        stat_tpl[ 19] = 8'h3D;   // '='
        stat_tpl[ 23] = 8'h20;   // ' '
        stat_tpl[ 24] = 8'h53;   // 'S'
        stat_tpl[ 25] = 8'h41;   // 'A'
        stat_tpl[ 26] = 8'h54;   // 'T'
        stat_tpl[ 27] = 8'h53;   // 'S'
        stat_tpl[ 28] = 8'h3D;   // '='
        stat_tpl[ 32] = 8'h20;   // ' '
        stat_tpl[ 33] = 8'h56;   // 'V'
        stat_tpl[ 34] = 8'h4F;   // 'O'
        stat_tpl[ 35] = 8'h4C;   // 'L'
        stat_tpl[ 36] = 8'h55;   // 'U'
        stat_tpl[ 37] = 8'h3D;   // '='
        stat_tpl[ 41] = 8'h20;   // ' '
        stat_tpl[ 42] = 8'h54;   // 'T'
        stat_tpl[ 43] = 8'h52;   // 'R'
        stat_tpl[ 44] = 8'h41;   // 'A'
        stat_tpl[ 45] = 8'h4E;   // 'N'
        stat_tpl[ 46] = 8'h3D;   // '='
        stat_tpl[ 50] = 8'h20;   // ' '
        stat_tpl[ 51] = 8'h54;   // 'T'
        stat_tpl[ 52] = 8'h45;   // 'E'
        stat_tpl[ 53] = 8'h3D;   // '='
        stat_tpl[ 57] = 8'h20;   // ' '
        stat_tpl[ 58] = 8'h49;   // 'I'
        stat_tpl[ 59] = 8'h4D;   // 'M'
        stat_tpl[ 60] = 8'h47;   // 'G'
        stat_tpl[ 61] = 8'h3D;   // '='
        stat_tpl[ 65] = 8'h2F;   // '/'
        stat_tpl[ 69] = 8'h20;   // ' '
        stat_tpl[ 70] = 8'h41;   // 'A'
        stat_tpl[ 71] = 8'h55;   // 'U'
        stat_tpl[ 72] = 8'h54;   // 'T'
        stat_tpl[ 73] = 8'h4F;   // 'O'
        stat_tpl[ 74] = 8'h3D;   // '='
        stat_tpl[ 78] = 8'h20;   // ' '
        stat_tpl[ 79] = 8'h53;   // 'S'
        stat_tpl[ 80] = 8'h55;   // 'U'
        stat_tpl[ 81] = 8'h42;   // 'B'
        stat_tpl[ 82] = 8'h3D;   // '='
        stat_tpl[ 86] = 8'h20;   // ' '
        stat_tpl[ 87] = 8'h53;   // 'S'
        stat_tpl[ 88] = 8'h54;   // 'T'
        stat_tpl[ 89] = 8'h3D;   // '='
    end

    function [18:0] stat_token;
        input [6:0] i;
        reg [7:0] mv;
        reg [6:0] w;
        reg [7:0] number;
        reg number_en;
        begin
            stat_token = 8'h00;
            w = 0; number = 0; number_en = 0;
            mv = {5'd0, I_mode_num} + 8'd1;              // 1..8

            if (i >= ST_ST) stat_token = st_char(i[2:0] - ST_ST[2:0]);

            else if (i >= ST_MODE && i < ST_MODE + 7'd3) begin
                w = i - ST_MODE; number = mv; number_en = 1;
            end
            else if (i >= ST_BRI && i < ST_BRI + 7'd3) begin
                w = i - ST_BRI; number = I_bri; number_en = 1;
            end
            else if (i >= ST_CON && i < ST_CON + 7'd3) begin
                w = i - ST_CON; number = I_con; number_en = 1;
            end
            else if (i >= ST_SAT && i < ST_SAT + 7'd3) begin
                w = i - ST_SAT; number = I_sat; number_en = 1;
            end
            else if (i >= ST_VOL && i < ST_VOL + 7'd3) begin
                w = i - ST_VOL; number = I_vol; number_en = 1;
            end
            else if (i >= ST_TRAN && i < ST_TRAN + 7'd3) begin
                w = i - ST_TRAN; number = {5'd0, I_tran_type}; number_en = 1;
            end
            else if (i >= ST_TE && i < ST_TE + 7'd3) begin
                w = i - ST_TE; number = {7'd0, I_tran_en}; number_en = 1;
            end
            else if (i >= ST_IMG && i < ST_IMG + 7'd3) begin
                w = i - ST_IMG; number = {3'd0, I_img_idx}; number_en = 1;
            end
            else if (i >= ST_TOT && i < ST_TOT + 7'd3) begin
                w = i - ST_TOT; number = {3'd0, I_img_total}; number_en = 1;
            end
            else if (i >= ST_AUTO && i < ST_AUTO + 7'd3) begin
                w = i - ST_AUTO; number = {7'd0, I_auto_on}; number_en = 1;
            end
            else if (i >= ST_SUB && i < ST_SUB + 7'd3) begin
                w = i - ST_SUB; number = {6'd0, I_sub_mode}; number_en = 1;
            end

            else stat_token = stat_tpl[i];

            if (number_en) stat_token = {1'b1, w[1:0], number, 8'd0};
        end
    endfunction

    function [18:0] resp_token;
        input [6:0] i;
        reg [6:0] w;
        reg [5:0] ti;
        reg       tsel;
        begin
            resp_token = 8'h00;
            w = 0; ti = 6'd0; tsel = 1'b0;

            case (r_kind)
            K_PONG: begin tsel = (i < 7'd4);  ti = RT_PONG + i[5:0]; end
            K_VER : begin tsel = (i < 7'd12); ti = RT_VER  + i[5:0]; end
            K_SET,
            K_ACT : begin tsel = (i < 7'd3);  ti = RT_OK   + i[5:0]; end
            K_ERR : begin
                if (i < 7'd4) begin
                    tsel = 1'b1; ti = RT_ERRH + i[5:0];
                end
                else if ((i - 7'd4) < 7'd4) begin
                    tsel = 1'b1;
                    ti = RT_BODY + {r_err, 2'd0} + (i[5:0] - 6'd4);
                end
            end
            default: ;
            endcase

            if (tsel) resp_token = resp_tpl[ti];
            else begin

                case (r_kind)
                K_SET: begin
                    if (i < (7'd3 + {4'd0, r_nltr})) begin
                        resp_token = r_cmd_char(i[1:0] - 2'd3);
                    end
                    else if (i == (7'd3 + {4'd0, r_nltr})) begin
                        resp_token = "=";
                    end
                    else begin
                        w = i - 7'd4 - {4'd0, r_nltr};       // 0/1/2

                        if (w < 7'd3) resp_token = {1'b1,w[1:0],rb_val,8'd0};
                    end
                end
                K_ACT: begin
                    if (i < (7'd3 + {4'd0, r_nltr})) begin
                        resp_token = r_cmd_char(i[1:0] - 2'd3);
                    end
                end

                K_ADST: begin
                    case(i)
                        0:resp_token="A";1:resp_token="D";2:resp_token=" ";
                        3:resp_token="L";4:resp_token="A";5:resp_token="N";
                        6:resp_token="G";7:resp_token="=";
                        8,9,19,20:resp_token="0";
                        10:resp_token=8'd48+{6'd0,I_ad_language};
                        11:resp_token=" ";12:resp_token="L";13:resp_token="A";
                        14:resp_token="Y";15:resp_token="O";16:resp_token="U";
                        17:resp_token="T";18:resp_token="=";
                        default:resp_token=8'd48+{7'd0,I_ad_layout};
                    endcase
                end
                K_STAT: resp_token = (r_hash && (i == 7'd0)) ? "#"
                                     : stat_token(r_hash ? (i - 7'd1) : i);
                default: ;
                endcase
            end

            if      (i == (r_len - 7'd2)) resp_token = 8'h0D;   // \r
            else if (i == (r_len - 7'd1)) resp_token = 8'h0A;   // \n
        end
    endfunction

    localparam integer RPRT_CLKS = (CLK_FREQ_HZ / 1000) * RPRT_MS;
    localparam [4:0]   WAIT_N    = 5'd7;      // 让参数寄存器落定
    localparam [12:0]  SEND_TO   = 13'd6000;  // 单字节发送兜底（≈120 µs）

    localparam [2:0] Q_IDLE = 3'd0, Q_DEC = 3'd1, Q_WAIT = 3'd2,
                     Q_LOAD = 3'd3, Q_SEND = 3'd4, Q_PREP=3'd5, Q_BCD=3'd6, Q_EMIT=3'd7;

    reg [18:0] fmt_token;
    reg [7:0] fmt_binary;
    reg [11:0] fmt_bcd;
    reg [2:0] fmt_count;
    reg [11:0] fmt_adjusted;
    always @(*) begin
        fmt_adjusted=fmt_bcd;
        if(fmt_bcd[3:0]>=5) fmt_adjusted[3:0]=fmt_bcd[3:0]+4'd3;
        if(fmt_bcd[7:4]>=5) fmt_adjusted[7:4]=fmt_bcd[7:4]+4'd3;
        if(fmt_bcd[11:8]>=5) fmt_adjusted[11:8]=fmt_bcd[11:8]+4'd3;
    end
    reg [2:0]  q;
    reg [4:0]  wait_cnt;
    reg [12:0] send_to;
    reg [6:0]  tx_idx;
    reg        tx_started;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            fmt_token<=0;fmt_binary<=0;fmt_bcd<=0;fmt_count<=0;
            q <= Q_IDLE; wait_cnt <= 5'd0; send_to <= 13'd0;
            tx_idx <= 7'd0; tx_started <= 1'b0;
            req_take <= 1'b0;
            O_tx_data <= 8'd0; O_tx_start <= 1'b0; O_tx_cnt <= 8'd0;
            O_wr <= 1'b0; O_wr_sel <= 4'd0; O_wr_val <= 8'd0; O_rset <= 1'b0;
            O_p5_wr <= 1'b0; O_p5_sel <= 3'd0; O_p5_val <= 2'd0;
            O_p6_wr <= 1'b0; O_p6_sel <= 2'd0; O_p6_val <= 3'd0;
            O_p7_wr <= 1'b0; O_p7_sel <= 2'd0; O_p7_val <= 2'd0;
            O_pause_set <= 1'b0; O_pause_clr <= 1'b0;
            O_next_pulse <= 1'b0; O_prev_pulse <= 1'b0;
            O_auto_set <= 1'b0; O_auto_val <= 1'b0;
            r_kind <= K_NONE; r_err <= E_NONE; r_sel <= 4'd0; r_lval <= 16'd0;
            r_nltr <= 3'd0; r_cmd <= 32'd0; r_hash <= 1'b0;
            r_rprt_en <= 1'b0; rprt_cnt <= 32'd0; r_len <= 7'd0;
        end
        else begin
            O_wr <= 1'b0; O_rset <= 1'b0;
            O_p5_wr <= 1'b0; O_p6_wr <= 1'b0; O_p7_wr <= 1'b0;
            O_pause_set <= 1'b0; O_pause_clr <= 1'b0;
            O_next_pulse <= 1'b0; O_prev_pulse <= 1'b0; O_auto_set <= 1'b0;
            O_tx_start <= 1'b0;
            req_take <= 1'b0;

            if (r_rprt_en) begin
                if (rprt_cnt == (RPRT_CLKS - 1)) rprt_cnt <= 32'd0;
                else                             rprt_cnt <= rprt_cnt + 32'd1;
            end
            else rprt_cnt <= 32'd0;

            case (q)

            Q_IDLE: begin
                if (req_pending) begin
                    req_take <= 1'b1;
                    q <= Q_DEC;
                end
                else if (r_rprt_en && (rprt_cnt == (RPRT_CLKS - 1)) && !I_tx_busy) begin

                    r_hash <= 1'b1; r_kind <= K_STAT; r_sel <= 4'd0;
                    r_lval <= 16'd0; r_nltr <= 3'd0; r_cmd <= 32'd0;
                    r_len  <= ST_ST + {3'd0, st_len} + 7'd3;
                    tx_idx <= 7'd0; tx_started <= 1'b0; send_to <= 13'd0;
                    q <= Q_LOAD;
                end
            end

            Q_DEC: begin
                r_kind <= d_kind; r_err <= d_err; r_sel <= d_wsel;
                r_lval <= d_lval; r_nltr <= n_ltr; r_cmd <= cmd_vec;
                r_hash <= 1'b0;
                r_len  <= d_len;
                if ((d_kind == K_SET) && (cmd_vec == C_RPT))
                    r_rprt_en <= d_lval[0];
                O_wr     <= d_wr;
                O_wr_sel <= d_wsel;
                O_wr_val <= d_lval[7:0];
                O_rset   <= d_rset;
                O_p5_wr  <= d_p5wr; O_p5_sel <= d_p5sel; O_p5_val <= d_p5val;
                O_p6_wr  <= d_p6wr; O_p6_sel <= d_p6sel; O_p6_val <= d_p6val;
                O_p7_wr  <= d_p7wr; O_p7_sel <= d_p7sel; O_p7_val <= d_p7val;
                O_pause_set <= d_paus_set; O_pause_clr <= d_paus_clr;
                O_next_pulse <= d_next; O_prev_pulse <= d_prev;
                O_auto_set <= d_autoset; O_auto_val <= d_autoval;

                wait_cnt <= 5'd0; tx_idx <= 7'd0;
                tx_started <= 1'b0; send_to <= 13'd0;
                q <= Q_WAIT;
            end

            Q_WAIT: begin
                if (wait_cnt == WAIT_N) q <= Q_LOAD;
                else                    wait_cnt <= wait_cnt + 5'd1;
            end

            Q_LOAD: begin
                if (tx_idx >= r_len) begin
                    q <= Q_IDLE;          // 按显式长度结束（不再用 0x00 哨兵）
                end
                else begin
                    fmt_token<=resp_token(tx_idx);
                    q<=Q_PREP;
                end
            end
            Q_PREP: begin
                fmt_binary<=fmt_token[15:8];fmt_bcd<=0;fmt_count<=0;
                q<=fmt_token[18] ? Q_BCD : Q_EMIT;
            end
            Q_BCD: begin
                fmt_bcd<={fmt_adjusted[10:0],fmt_binary[7]};
                fmt_binary<={fmt_binary[6:0],1'b0};fmt_count<=fmt_count+1'b1;
                if(fmt_count==7) q<=Q_EMIT;
            end
            Q_EMIT: begin
                O_tx_data<=fmt_token[18] ?
                    {4'h3,(fmt_token[17:16]==0 ? fmt_bcd[11:8] :
                           fmt_token[17:16]==1 ? fmt_bcd[7:4] : fmt_bcd[3:0])} : fmt_token[7:0];
                O_tx_start<=1;tx_started<=0;send_to<=0;q<=Q_SEND;
            end
            Q_SEND: begin
                if (!tx_started) begin
                    if (I_tx_busy) tx_started <= 1'b1;
                    else if (send_to == SEND_TO) begin

                        tx_idx <= tx_idx + 7'd1;
                        q      <= Q_LOAD;
                    end
                    else send_to <= send_to + 13'd1;
                end
                else if (!I_tx_busy) begin
                    O_tx_cnt <= O_tx_cnt + 8'd1;
                    tx_idx   <= tx_idx + 7'd1;
                    q        <= Q_LOAD;
                end
            end

            default: q <= Q_IDLE;
            endcase
        end
    end

endmodule
