`timescale 1ns / 1ps

module key_ctrl #(
    parameter CLK_FREQ_HZ    = 50_000_000,
    parameter DEBOUNCE_MS    = 20,     // 消抖时间
    parameter LONG_MS        = 500,    // 长按判定阈值（同时是短按上限）
    parameter REPEAT_SLOW_MS = 120,    // 连发慢档间隔（500..800ms 之间）
    parameter REPEAT_FAST_MS = 40,     // 连发快档间隔（800ms 之后）
    parameter FAST_AFTER_MS  = 800     // 累计按住多久后切到快档
)(
    input  wire        I_clk,          // 50 MHz
    input  wire        I_rst_n,        // 低有效复位（外部已同步化）

    input  wire        I_key_l,        // C1 板 KEY4 左
    input  wire        I_key_m,        // B1 板 KEY3 中
    input  wire        I_key_r,        // B2 板 KEY2 右

    output wire [2:0]  O_short,        // {r, m, l} 短按单拍
    output wire        O_long_start,   // 长按起始单拍（任一键）
    output wire [2:0]  O_repeat,       // {r, m, l} 长按连发单拍（one-hot）
    output wire [2:0]  O_held          // {r, m, l} 按住电平（消抖后）
);

    // 参数换算

    localparam DEBOUNCE_MAX   = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;
    localparam LONG_MAX       = CLK_FREQ_HZ / 1000 * LONG_MS;
    localparam REP_SLOW_MAX   = CLK_FREQ_HZ / 1000 * REPEAT_SLOW_MS;
    localparam REP_FAST_MAX   = CLK_FREQ_HZ / 1000 * REPEAT_FAST_MS;
    localparam FAST_AFTER_MAX = CLK_FREQ_HZ / 1000 * FAST_AFTER_MS;

    localparam DB_W = $clog2(DEBOUNCE_MAX + 1);
    localparam HL_W = $clog2(FAST_AFTER_MAX + 1);   // 累计按住时长（到快档后饱和）
    localparam IS_W = $clog2(REP_SLOW_MAX + 1);     // 连发间隔计数（取慢档宽度）

    wire [2:0] key_raw = {I_key_r, I_key_m, I_key_l};   // 原始（按下=0）
    wire [2:0] key_act = ~key_raw;                      // 按下=1

    reg  [2:0] sync_1d, sync_2d;
    always @(posedge I_clk) begin
        sync_1d <= key_act;
        sync_2d <= sync_1d;
    end

    reg  [2:0] key_stable;                 // 消抖后的电平（按下=1）
    reg  [DB_W-1:0] db_cnt [2:0];          // 每个键一个消抖计数器
    reg  [2:0] key_press;                  // 按下瞬间的单拍脉冲

    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            key_stable <= 3'b000;
            key_press  <= 3'b000;
            for (i = 0; i < 3; i = i + 1)
                db_cnt[i] <= {DB_W{1'b0}};
        end
        else begin
            for (i = 0; i < 3; i = i + 1) begin
                if (sync_2d[i] != key_stable[i]) begin
                    if (db_cnt[i] >= DEBOUNCE_MAX[DB_W-1:0]) begin
                        key_stable[i] <= sync_2d[i];   // 稳定，采纳新值
                        db_cnt[i]     <= {DB_W{1'b0}};
                        if (sync_2d[i])
                            key_press[i] <= 1'b1;      // 按下沿
                        else
                            key_press[i] <= 1'b0;      // 释放，无脉冲
                    end
                    else begin
                        db_cnt[i] <= db_cnt[i] + 1'b1;
                    end
                end
                else begin
                    db_cnt[i]  <= {DB_W{1'b0}};
                    key_press[i] <= 1'b0;
                end
            end
        end
    end

    assign O_held = key_stable;

    localparam S_IDLE       = 2'd0,
               S_PRESS_HOLD = 2'd1,
               S_REPEAT     = 2'd2;

    reg [1:0]  st;
    reg [2:0]  active_key;      // one-hot：当前跟踪的键
    reg [HL_W-1:0] hold_cnt;    // 累计按住时长（到快档阈值后饱和）
    reg [IS_W-1:0] int_cnt;     // 连发间隔计数

    reg [2:0]  short_r;
    reg        long_start_r;
    reg [2:0]  repeat_r;

    wire [IS_W-1:0] cur_int = (hold_cnt >= FAST_AFTER_MAX[HL_W-1:0])
                              ? REP_FAST_MAX[IS_W-1:0]
                              : REP_SLOW_MAX[IS_W-1:0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st           <= S_IDLE;
            active_key   <= 3'b000;
            hold_cnt     <= {HL_W{1'b0}};
            int_cnt      <= {IS_W{1'b0}};
            short_r      <= 3'b000;
            long_start_r <= 1'b0;
            repeat_r     <= 3'b000;
        end
        else begin
            short_r      <= 3'b000;
            long_start_r <= 1'b0;
            repeat_r     <= 3'b000;

            case (st)

            S_IDLE: begin
                if (key_press != 3'b000) begin
                    if      (key_press[0]) active_key <= 3'b001;
                    else if (key_press[1]) active_key <= 3'b010;
                    else                   active_key <= 3'b100;

                    hold_cnt <= {HL_W{1'b0}};
                    st       <= S_PRESS_HOLD;
                end
            end

            S_PRESS_HOLD: begin

                if ((key_stable & active_key) == 3'b000) begin
                    short_r  <= active_key;
                    st       <= S_IDLE;
                end

                else if (hold_cnt >= LONG_MAX[HL_W-1:0]) begin
                    long_start_r <= 1'b1;
                    repeat_r     <= active_key;         // 首发
                    int_cnt      <= {IS_W{1'b0}};
                    st           <= S_REPEAT;
                end
                else begin
                    hold_cnt <= hold_cnt + 1'b1;
                end
            end

            S_REPEAT: begin
                if ((key_stable & active_key) == 3'b000) begin
                    st <= S_IDLE;               // 松开，结束
                end
                else begin
                    if (hold_cnt < FAST_AFTER_MAX[HL_W-1:0])
                        hold_cnt <= hold_cnt + 1'b1;

                    if (int_cnt >= (cur_int - 1'b1)) begin
                        repeat_r <= active_key;     // one-hot：指明是哪个键
                        int_cnt  <= {IS_W{1'b0}};
                    end
                    else begin
                        int_cnt <= int_cnt + 1'b1;
                    end
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    assign O_short      = short_r;
    assign O_long_start = long_start_r;
    assign O_repeat     = repeat_r;

endmodule
