`timescale 1ns/1ps

module text_load #(

    parameter [31:0] SCAN_FIRST = 32'd8192,
    parameter [31:0] SCAN_LAST  = 32'd24576,
    // 各段在 blob 内的起始偏移
    parameter [12:0] OFF_CUE  = 13'd16,
    parameter [12:0] OFF_SCH  = 13'd528,
    parameter [12:0] OFF_LN   = 13'd1552,
    parameter [12:0] OFF_ACH  = 13'd2064,
    parameter [12:0] OFF_END  = 13'd4112
)(
    input  wire        clk,             // sd_card_clk
    input  wire        rst,
    input  wire        sd_init_done,

    output reg         O_sec_read,
    output reg  [31:0] O_sec_addr,
    input  wire [7:0]  I_sec_data,
    input  wire        I_sec_data_valid,
    input  wire        I_sec_read_end,
    input wire I_sec_error,

    output reg         O_cue_we,
    output reg  [5:0]  O_cue_wa,
    output reg  [63:0] O_cue_wd,

    output reg         O_sch_we,
    output reg  [9:0]  O_sch_wa,
    output reg  [7:0]  O_sch_wd,

    output reg         O_ln_we,
    output reg  [6:0]  O_ln_wa,
    output reg  [16:0] O_ln_wd,

    output reg         O_ach_we,
    output reg  [10:0] O_ach_wa,
    output reg  [7:0]  O_ach_wd,

    // 状态
    output reg         O_done,          // 1 = 已结束（载完，或确认卡上没有）
    output reg         O_found          // 1 = 卡上确实找到 TEXT.BIN
);

localparam S_IDLE = 2'd0,
           S_SCAN = 2'd1,          // 找魔数（命中后同扇区立即开始搬运）
           S_LOAD = 2'd2,          // 已命中，继续搬后续扇区
           S_DONE = 2'd3;

reg [1:0]  state;
reg [31:0] saddr;          // 当前扇区地址
reg [12:0] gcnt;           // blob 内全局字节偏移
reg [8:0] sector_byte;
reg header_ok;
reg [2:0]  mcnt;           // 魔数已匹配字节数 0..4
reg [63:0] cue_acc;        // 句表 8 字节拼装
reg [31:0] ln_acc;         // 行表4字节小端拼装，仅低17位有效

wire [63:0] cue_nxt = {I_sec_data, cue_acc[63:8]};
wire [31:0] ln_nxt  = {I_sec_data, ln_acc[31:8]};

wire [12:0] d_cue = gcnt - OFF_CUE;
wire [12:0] d_sch = gcnt - OFF_SCH;
wire [12:0] d_ln  = gcnt - OFF_LN;
wire [12:0] d_ach = gcnt - OFF_ACH;

wire in_cue = (gcnt >= OFF_CUE) && (gcnt < OFF_SCH);
wire in_sch = (gcnt >= OFF_SCH) && (gcnt < OFF_LN);
wire in_ln  = (gcnt >= OFF_LN ) && (gcnt < OFF_ACH);
wire in_ach = (gcnt >= OFF_ACH) && (gcnt < OFF_END);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= S_IDLE;
        saddr      <= SCAN_FIRST;
        gcnt       <= 13'd0;
        mcnt       <= 3'd0; sector_byte <= 0; header_ok <= 0;
        cue_acc    <= 64'd0;
        ln_acc     <= 32'd0;
        O_sec_read <= 1'b0;
        O_sec_addr <= SCAN_FIRST;
        O_cue_we   <= 1'b0;
        O_cue_wa   <= 6'd0;
        O_cue_wd   <= 64'd0;
        O_sch_we   <= 1'b0;
        O_sch_wa   <= 10'd0;
        O_sch_wd   <= 8'd0;
        O_ln_we    <= 1'b0;
        O_ln_wa    <= 7'd0;
        O_ln_wd    <= 17'd0;
        O_ach_we   <= 1'b0;
        O_ach_wa   <= 11'd0;
        O_ach_wd   <= 8'd0;
        O_done     <= 1'b0;
        O_found    <= 1'b0;
    end else begin
        O_cue_we <= 1'b0;
        O_sch_we <= 1'b0;
        O_ln_we  <= 1'b0;
        O_ach_we <= 1'b0;

        if (I_sec_read_end) sector_byte <= 0;
        else if (I_sec_data_valid) sector_byte <= sector_byte + 1'b1;
        if (I_sec_data_valid) begin
            cue_acc <= cue_nxt;
            ln_acc  <= ln_nxt;
        end

        case (state)

            S_IDLE: begin
                if (sd_init_done) begin
                    saddr      <= SCAN_FIRST;
                    O_sec_addr <= SCAN_FIRST;
                    O_sec_read <= 1'b1;
                    mcnt       <= 3'd0;
                    state      <= S_SCAN;
                end
            end

            S_SCAN: begin
                if (I_sec_data_valid) begin
                    if (mcnt != 3'd4) begin
                        case (mcnt)
                            3'd0: mcnt <= (sector_byte == 0 && I_sec_data == 8'h46) ? 3'd1 : 3'd0; // 'F'
                            3'd1: mcnt <= (I_sec_data == 8'h54) ? 3'd2 : 3'd0; // 'T'
                            3'd2: mcnt <= (I_sec_data == 8'h58) ? 3'd3 : 3'd0; // 'X'
                            default: begin                                     // 3
                                if (I_sec_data == 8'h54) begin                 // 'T'
                                    mcnt <= 3'd4;
                                    gcnt <= 13'd4; header_ok <= 0;
                                end else mcnt <= 3'd0;
                            end
                        endcase
                    end else begin

                        gcnt <= gcnt + 13'd1;
                        if (gcnt == 4) header_ok <= (I_sec_data == 8'd2);
                        if (header_ok && in_cue) begin
                            if (d_cue[2:0] == 3'd7) begin
                                O_cue_we <= 1'b1;
                                O_cue_wa <= d_cue[8:3];
                                O_cue_wd <= cue_nxt;
                            end
                        end else if (header_ok && in_sch) begin
                            O_sch_we <= 1'b1;
                            O_sch_wa <= d_sch[9:0];
                            O_sch_wd <= I_sec_data;
                        end else if (header_ok && in_ln) begin
                            if (d_ln[1:0] == 2'd3) begin
                                O_ln_we <= 1'b1;
                                O_ln_wa <= d_ln[8:2];
                                O_ln_wd <= ln_nxt[16:0];
                            end
                        end else if (header_ok && in_ach) begin
                            O_ach_we <= 1'b1;
                            O_ach_wa <= d_ach[10:0];
                            O_ach_wd <= I_sec_data[7:0];
                        end
                    end
                end

                if (I_sec_read_end) begin
                    O_sec_read <= 1'b0;
                    mcnt       <= 3'd0;
                    if (mcnt == 3'd4 && header_ok) begin
                        O_found    <= 1'b1;
                        saddr      <= saddr + 32'd1;
                        O_sec_addr <= saddr + 32'd1;
                        state      <= S_LOAD;
                    end else if (saddr >= SCAN_LAST) begin
                        O_done <= 1'b1;         // 扫完窗口仍没有 放弃
                        state  <= S_DONE;
                    end else begin
                        saddr      <= saddr + 32'd1;
                        O_sec_addr <= saddr + 32'd1;
                    end
                end else if (!O_sec_read) begin
                    O_sec_read <= 1'b1;         // 重新发起下一个扇区
                end
            end

            S_LOAD: begin
                if (I_sec_data_valid) begin
                    gcnt <= gcnt + 13'd1;
                    if (in_cue) begin
                        if (d_cue[2:0] == 3'd7) begin
                            O_cue_we <= 1'b1;
                            O_cue_wa <= d_cue[8:3];
                            O_cue_wd <= cue_nxt;
                        end
                    end else if (in_sch) begin
                        O_sch_we <= 1'b1;
                        O_sch_wa <= d_sch[9:0];
                        O_sch_wd <= I_sec_data;
                    end else if (in_ln) begin
                        if (d_ln[1:0] == 2'd3) begin
                            O_ln_we <= 1'b1;
                            O_ln_wa <= d_ln[8:2];
                            O_ln_wd <= ln_nxt[16:0];
                        end
                    end else if (in_ach) begin
                        O_ach_we <= 1'b1;
                        O_ach_wa <= d_ach[10:0];
                        O_ach_wd <= I_sec_data[7:0];
                    end
                end

                if (gcnt >= OFF_END && I_sec_read_end) begin
                    O_sec_read <= 1'b0;         // 放总线，允许 WAV 扫描
                    O_done     <= 1'b1;
                    state      <= S_DONE;
                end else if (I_sec_read_end) begin
                    O_sec_read <= 1'b0;
                    saddr      <= saddr + 32'd1;
                    O_sec_addr <= saddr + 32'd1;
                end else if (!O_sec_read) begin
                    O_sec_read <= 1'b1;
                end
            end

            S_DONE: begin
                O_sec_read <= 1'b0;
            end

            default: state <= S_IDLE;
        endcase
        if (I_sec_error) begin
            state <= S_DONE; O_sec_read <= 0; O_done <= 1; O_found <= 0;
            O_cue_we <= 0; O_sch_we <= 0; O_ln_we <= 0; O_ach_we <= 0;
        end
    end
end

endmodule
