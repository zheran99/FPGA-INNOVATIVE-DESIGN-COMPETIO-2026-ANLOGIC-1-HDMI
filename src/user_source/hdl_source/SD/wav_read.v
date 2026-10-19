`timescale 1ns/1ps

module wav_read(
    input                       clk,                // sd_card_clk 100 MHz
    input                       rst,

    output                      ready,

    // 扫描
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,

    input  [31:0]               scan_hit_limit,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,

    // 播放控制
    input                       play_start,
    input                       loop_en,
    output reg                  eof,

    // 系统
    input                       sd_init_done,
    output reg [3:0]            state_code,

    output wire                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    // 背压
    input                       fifo_almost_full,

    // PCM 输出
    output wire                  pcm_wr_en,
    output reg [47:0]           pcm_lr,

    // 调试观察
    output [31:0]               o_sample_rate,
    output [7:0]                o_channels,
    output [7:0]                o_bits,
    output [31:0]               o_data_size,
    output [31:0]               o_data_offset
);

// 状态编码

localparam S_IDLE      = 5'd0;
localparam S_SCAN      = 5'd1;
localparam S_HDR       = 5'd2;
localparam S_PREFILL   = 5'd3;
localparam S_DATA      = 5'd4;
localparam S_LOOP      = 5'd5;
localparam S_EOF       = 5'd6;

localparam P_PRE   = 3'd0;    // 丢弃 12 字节容器头
localparam P_ID    = 3'd1;    // 收 4 字节 chunk id
localparam P_SZ    = 3'd2;    // 收 4 字节 chunk size（小端）+ 末拍分派
localparam P_FMTB  = 3'd3;    // 收 fmt body
localparam P_SKIP  = 3'd4;    // 跳过 body
localparam P_DONE  = 3'd5;    // 完成
localparam P_RSV6  = 3'd6;    // 保留（旧编码占位，未使用）
localparam P_RSV7  = 3'd7;    // 保留（旧编码占位，未使用）

reg [4:0]  state;             // 块1 私有

// 块1 私有信号

reg [31:0] scan_sector;
reg [31:0] riff_sector;
reg [31:0] data_start_sector;
reg [8:0]  data_skip;
reg        hdr_go;
reg        data_go;

reg [9:0]  sc_cnt;                 // 从 4 位扩到 10 位（0..511 不回绕）
reg [7:0]  sc_b0, sc_b1, sc_b2, sc_b3, sc_b8;
wire sc_is_riff = (sc_b0==8'h52)&&(sc_b1==8'h49)&&(sc_b2==8'h46)&&(sc_b3==8'h46);
wire sc_is_wave = (sc_b8==8'h57);

reg [2:0]  pstate;
reg [31:0] fpos;              // 已消费字节数（自 RIFF 起，0-based）
reg [3:0]  pre_cnt;           // 容器头丢弃计数
reg [31:0] cid;               // chunk id（滚动，先收到的在高位）
reg [1:0]  cnt4;
reg [31:0] csz;               // chunk size（小端拼接）
reg [31:0] body_rem;
reg [31:0] skip_rem;
reg [3:0]  fcnt;

reg [15:0] f_audio_format;
reg [15:0] f_channels;
reg [31:0] f_sample_rate;
reg [15:0] f_bits;

reg [31:0] data_offset;
reg [31:0] data_size;
reg        hdr_done;

wire cid_is_fmt  = (cid == 32'h666D7420);   // "fmt "
wire cid_is_data = (cid == 32'h64617461);   // "data"

wire cid_is_fmt_p  = (cid[31:8] == 24'h666D74);   // "fmt"
wire cid_is_data_p = (cid[31:8] == 24'h646174);   // "dat"

reg [1:0]  byte_idx;
reg [15:0] l16, r16;
reg [31:0] data_byte_cnt;
reg [31:0] data_skip_rem;     // 首扇区文件头剩余跳过量
wire       mono = (f_channels == 16'd1);

wire byte_in = sd_sec_read_data_valid;

wire data_done      = (data_size != 32'd0) && (data_byte_cnt >= data_size);
wire can_start_read = (~fifo_almost_full) && (~data_done);

assign ready         = (state == S_IDLE);
assign o_sample_rate = f_sample_rate;
assign o_channels    = f_channels[7:0];
assign o_bits        = f_bits[7:0];
assign o_data_size   = data_size;
assign o_data_offset = data_offset;

reg sd_read_command;
assign sd_sec_read=sd_read_command && !rst;
reg pcm_write_command;
assign pcm_wr_en=pcm_write_command && !rst;

reg riff_hit_r;
wire addr_scan_start = state==S_IDLE && scan_start;
wire addr_play_start = state==S_IDLE && !scan_start && play_start && hdr_done;
wire addr_scan_hit = state==S_SCAN && sd_sec_read_end && riff_hit_r;
wire addr_scan_next = state==S_SCAN && sd_sec_read_end && !riff_hit_r &&
    scan_sector<scan_max_sector && (scan_hit_limit==0 || scan_sector<scan_hit_limit);
wire addr_hdr_next = state==S_HDR && sd_sec_read_end && !hdr_done && sd_sec_read_addr<scan_max_sector;
wire addr_data_next = state==S_DATA && sd_sec_read_end && !data_done;
wire addr_restart = (state==S_PREFILL && !fifo_almost_full) || state==S_LOOP || state==S_EOF;
wire addr_update = addr_scan_start || addr_play_start || addr_scan_hit ||
    addr_scan_next || addr_hdr_next || addr_data_next || addr_restart;
wire [31:0] addr_value = ({32{addr_scan_start}} & scan_start_sector) |
    ({32{addr_play_start}} & (riff_sector+{23'd0,data_offset[31:9]})) |
    ({32{addr_scan_hit}} & scan_sector) |
    ({32{addr_scan_next}} & (scan_sector+32'd1)) |
    ({32{addr_hdr_next || addr_data_next}} & (sd_sec_read_addr+32'd1)) |
    ({32{addr_restart}} & data_start_sector);

always @(posedge clk) begin
    if(rst) sd_sec_read_addr<=0;
    else if(!sd_init_done || addr_update)
        sd_sec_read_addr<=sd_init_done ? addr_value : 32'd0;
end

always @(posedge clk) begin
    if (rst) begin
        state             <= S_IDLE;
        state_code        <= 4'd0;
        sd_read_command       <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_sector       <= 32'd0;
        riff_sector       <= 32'd0;
        data_start_sector <= 32'd0;
        data_skip         <= 9'd0;
        eof               <= 1'b0;
        hdr_go            <= 1'b0;
        data_go           <= 1'b0;
    end else if (!sd_init_done) begin
        state             <= S_IDLE;
        state_code        <= 4'd0;
        sd_read_command       <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_sector       <= 32'd0;
        riff_sector       <= 32'd0;
        data_start_sector <= 32'd0;
        data_skip         <= 9'd0;
        eof               <= 1'b0;
        hdr_go            <= 1'b0;
        data_go           <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        hdr_go           <= 1'b0;      // 默认收回脉冲
        data_go          <= 1'b0;

        case (state)

            S_IDLE: begin
                state_code  <= 4'd1;
                sd_read_command <= 1'b0;
                eof         <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_sector      <= scan_start_sector;
                    state            <= S_SCAN;
                end else if (play_start && hdr_done) begin
                    data_start_sector <= riff_sector + {23'd0, data_offset[31:9]};
                    data_skip         <= data_offset[8:0];
                    state             <= S_PREFILL;
                end
            end

            S_SCAN: begin
                state_code  <= 4'd2;
                sd_read_command <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_read_command <= 1'b0;

                    if (riff_hit_r) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        riff_sector       <= scan_sector;
                        scan_done         <= 1'b1;
                        hdr_go            <= 1'b1;          // 通知块3
                        state             <= S_HDR;
                    end else if ((scan_sector >= scan_max_sector) ||

                                 (scan_hit_limit != 32'd0 &&
                                  scan_sector >= scan_hit_limit)) begin
                        scan_done <= 1'b1;
                        state     <= S_IDLE;
                    end else begin
                        scan_sector      <= scan_sector + 32'd1;
                    end
                end
            end

            S_HDR: begin
                state_code  <= 4'd3;
                sd_read_command <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_read_command <= 1'b0;
                    if (hdr_done) begin
                        data_start_sector <= riff_sector + {23'd0, data_offset[31:9]};
                        data_skip         <= data_offset[8:0];
                        state             <= S_PREFILL;
                    end else if (sd_sec_read_addr >= scan_max_sector) begin
                        state <= S_IDLE;                // 头异常
                    end else begin
                    end
                end
            end

            S_PREFILL: begin
                state_code <= 4'd4;
                if (~fifo_almost_full) begin
                    sd_read_command      <= 1'b1;
                    data_go          <= 1'b1;           // 通知块4
                    state            <= S_DATA;
                end
            end

            S_DATA: begin
                state_code <= 4'd5;

                if (sd_sec_read_end) begin
                    sd_read_command <= 1'b0;

                    if (data_done) begin
                        eof   <= 1'b1;
                        state <= loop_en ? S_LOOP : S_EOF;
                    end else begin
                    end
                end
                else if (~sd_sec_read && can_start_read) begin
                    sd_read_command <= 1'b1;                // 唯一检查背压处
                end
            end

            S_LOOP: begin
                state_code       <= 4'd7;
                eof              <= 1'b0;
                data_go          <= 1'b1;               // 通知块4 复位重来
                state            <= S_DATA;
            end

            S_EOF: begin
                state_code       <= 4'd8;
                sd_read_command      <= 1'b0;

                if (play_start) begin
                    eof    <= 1'b0;
                    state  <= S_PREFILL;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if (rst) begin
        sc_cnt <= 10'd0;
        sc_b0  <= 8'd0;
        sc_b1  <= 8'd0;
        sc_b2  <= 8'd0;
        sc_b3  <= 8'd0;
        sc_b8  <= 8'd0;
    end else if (!sd_init_done) begin
        sc_cnt <= 10'd0;
    end else if (state == S_SCAN) begin
        if (byte_in) begin
            case (sc_cnt)

                10'd0: sc_b0 <= sd_sec_read_data;
                10'd1: sc_b1 <= sd_sec_read_data;
                10'd2: sc_b2 <= sd_sec_read_data;
                10'd3: sc_b3 <= sd_sec_read_data;
                10'd8: sc_b8 <= sd_sec_read_data;
                default: ;
            endcase
            sc_cnt <= sc_cnt + 10'd1;      // 扩到 10 位 数到 511 才回绕
        end

        if (sd_sec_read_end)
            sc_cnt <= 10'd0;
    end else begin
        sc_cnt <= 10'd0;         // 离开 S_SCAN 就归零，下次扫描重新开始
    end
end

always @(posedge clk) begin
    if (rst || !sd_init_done) begin
        riff_hit_r <= 1'b0;
    end else if (state == S_SCAN) begin
        if (sd_sec_read_end)
            riff_hit_r <= 1'b0;                 // 扇区结束清标志，下一扇区重新检测
        else if (sc_is_riff && sc_is_wave)
            riff_hit_r <= 1'b1;                 // 本扇区命中 RIFF+WAVE
    end else begin
        riff_hit_r <= 1'b0;
    end
end

always @(posedge clk) begin
    if (rst) begin
        pstate         <= P_PRE;
        fpos           <= 32'd0;
        pre_cnt        <= 4'd0;
        cid            <= 32'd0;
        cnt4           <= 2'd0;
        csz            <= 32'd0;
        body_rem       <= 32'd0;
        skip_rem       <= 32'd0;
        fcnt           <= 4'd0;
        f_audio_format <= 16'd0;
        f_channels     <= 16'd0;
        f_sample_rate  <= 32'd0;
        f_bits         <= 16'd0;
        data_offset    <= 32'd0;
        data_size      <= 32'd0;
        hdr_done       <= 1'b0;
    end else if (!sd_init_done) begin
        pstate         <= P_PRE;
        fpos           <= 32'd0;
        pre_cnt        <= 4'd0;
        cid            <= 32'd0;
        cnt4           <= 2'd0;
        csz            <= 32'd0;
        body_rem       <= 32'd0;
        skip_rem       <= 32'd0;
        fcnt           <= 4'd0;
        hdr_done       <= 1'b0;
    end else if (hdr_go) begin
        pstate         <= P_PRE;
        fpos           <= 32'd0;
        pre_cnt        <= 4'd0;
        cid            <= 32'd0;
        cnt4           <= 2'd0;
        csz            <= 32'd0;
        body_rem       <= 32'd0;
        skip_rem       <= 32'd0;
        fcnt           <= 4'd0;
        f_audio_format <= 16'd0;
        f_channels     <= 16'd0;
        f_sample_rate  <= 32'd0;
        f_bits         <= 16'd0;
        data_offset    <= 32'd0;
        data_size      <= 32'd0;
        hdr_done       <= 1'b0;
    end else if ((state == S_HDR) && byte_in) begin

        fpos <= fpos + 32'd1;

        case (pstate)

            P_PRE: begin
                pre_cnt <= pre_cnt + 4'd1;
                if (pre_cnt == 4'd11)
                    pstate <= P_ID;
            end

            P_ID: begin
                cid <= {cid[23:0], sd_sec_read_data};
                if (cnt4 == 2'd3) begin
                    cnt4   <= 2'd0;
                    csz    <= 32'd0;
                    pstate <= P_SZ;        // 下一拍开始收 size
                end else begin
                    cnt4 <= cnt4 + 2'd1;
                end
            end

            P_SZ: begin
                case (cnt4)
                    2'd0: csz[7:0]   <= sd_sec_read_data;
                    2'd1: csz[15:8]  <= sd_sec_read_data;
                    2'd2: csz[23:16] <= sd_sec_read_data;
                    2'd3: csz[31:24] <= sd_sec_read_data;
                endcase

                if (cnt4 == 2'd3) begin
                    cnt4 <= 2'd0;

                    if (cid_is_data_p) begin

                        data_offset <= fpos + 32'd1;
                        data_size   <= {sd_sec_read_data, csz[23:0]};
                        hdr_done    <= 1'b1;
                        pstate      <= P_DONE;
                    end else if (cid_is_fmt_p) begin
                        body_rem <= {sd_sec_read_data, csz[23:0]};  // fmt body 长
                        fcnt     <= 4'd0;
                        pstate   <= P_FMTB;
                    end else begin

                        skip_rem <= {sd_sec_read_data, csz[23:0]}
                                    + {31'd0, sd_sec_read_data[0]};
                        pstate   <= P_SKIP;
                    end
                end else begin
                    cnt4 <= cnt4 + 2'd1;
                end
            end

            P_FMTB: begin
                case (fcnt)
                    4'd0 : f_audio_format[7:0]  <= sd_sec_read_data;
                    4'd1 : f_audio_format[15:8] <= sd_sec_read_data;
                    4'd2 : f_channels[7:0]      <= sd_sec_read_data;
                    4'd3 : f_channels[15:8]     <= sd_sec_read_data;
                    4'd4 : f_sample_rate[7:0]   <= sd_sec_read_data;
                    4'd5 : f_sample_rate[15:8]  <= sd_sec_read_data;
                    4'd6 : f_sample_rate[23:16] <= sd_sec_read_data;
                    4'd7 : f_sample_rate[31:24] <= sd_sec_read_data;
                    4'd14: f_bits[7:0]          <= sd_sec_read_data;
                    4'd15: f_bits[15:8]         <= sd_sec_read_data;
                    default: ;
                endcase
                fcnt     <= fcnt + 4'd1;
                body_rem <= body_rem - 32'd1;
                if (body_rem == 32'd1)
                    pstate <= P_ID;             // 直接回 P_ID 收下一个 chunk id
            end

            P_SKIP: begin
                if (skip_rem <= 32'd1) begin
                    skip_rem <= 32'd0;
                    pstate   <= P_ID;
                end else begin
                    skip_rem <= skip_rem - 32'd1;
                end
            end

            P_DONE: ;    // 停在此，等主状态机收尾
            default: pstate <= P_PRE;
        endcase
    end
end

always @(posedge clk) begin
    if (rst) begin
        byte_idx      <= 2'd0;
    end else if (!sd_init_done) begin
        byte_idx      <= 2'd0;
    end else if (data_go) begin
        byte_idx      <= 2'd0;
    end else if (state == S_DATA) begin

        if (byte_in && data_skip_rem == 0 && !data_done) begin

            byte_idx <= (mono && (byte_idx == 2'd1)) ? 2'd0 : (byte_idx + 2'd1);
        end
    end else begin
        byte_idx <= 2'd0;
    end
end

always @(posedge clk) begin
    if (rst) begin
        l16           <= 16'd0;
        r16           <= 16'd0;
        data_byte_cnt <= 32'd0;
        pcm_write_command     <= 1'b0;
        pcm_lr        <= 48'd0;
    end else if (!sd_init_done) begin
        data_byte_cnt <= 32'd0;
        pcm_write_command     <= 1'b0;
    end else if (data_go) begin
        l16           <= 16'd0;
        r16           <= 16'd0;
        data_byte_cnt <= 32'd0;
        pcm_write_command     <= 1'b0;
    end else begin
        pcm_write_command <= 1'b0;               // 默认收回脉冲

        if ((state == S_DATA) && byte_in && (data_skip_rem == 32'd0)
            && ~data_done) begin
            case (byte_idx)
                2'd0: begin
                    l16[7:0] <= sd_sec_read_data;
                end
                2'd1: begin
                    l16[15:8] <= sd_sec_read_data;
                    if (mono) begin
                        pcm_write_command <= 1'b1;
                        pcm_lr <= {sd_sec_read_data, l16[7:0], 8'h00,
                                   sd_sec_read_data, l16[7:0], 8'h00};
                    end
                end
                2'd2: begin
                    r16[7:0] <= sd_sec_read_data;
                end
                2'd3: begin
                    r16[15:8] <= sd_sec_read_data;

                    pcm_write_command <= 1'b1;
                    pcm_lr <= {l16[15:8], l16[7:0], 8'h00,
                               sd_sec_read_data, r16[7:0], 8'h00};
                end
                default: ;
            endcase
            data_byte_cnt <= data_byte_cnt + 32'd1;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        data_skip_rem <= 32'd0;
    end else if (!sd_init_done) begin
        data_skip_rem <= 32'd0;
    end else if (data_go) begin
        data_skip_rem <= {23'd0, data_skip};
    end else if ((state == S_DATA) && byte_in && (data_skip_rem != 32'd0)) begin
        data_skip_rem <= data_skip_rem - 32'd1;
    end
end

endmodule

module wav_scan_control #(
    parameter [31:0] PRIMARY_FIRST = 32'd110592,
    parameter [31:0] PRIMARY_LAST = 32'd118592,
    parameter [31:0] COMPAT_FIRST = 32'd0,
    parameter [31:0] COMPAT_LAST = 32'd0,
    parameter [31:0] FALLBACK_FIRST = 32'd8192,
    parameter [31:0] FALLBACK_LAST = 32'd131071
)(
    input clk, input rst, input sd_init_done,

    input start_ok,
    input scan_done, input scan_found_valid,
    output scan_start,
    output [31:0] scan_first, output [31:0] scan_limit
);
localparam WAIT_SD=3'd0, KICK=3'd1, WAIT_CLEAR=3'd2,
           WAIT_DONE=3'd3, FINISHED=3'd4;
reg [2:0] state;
reg fallback, compat;

assign scan_start = (state == KICK);
assign scan_first = fallback ? FALLBACK_FIRST : compat ? COMPAT_FIRST : PRIMARY_FIRST;
assign scan_limit = fallback ? FALLBACK_LAST : compat ? COMPAT_LAST : PRIMARY_LAST;
always @(posedge clk) begin
    if (rst) begin
        state <= WAIT_SD;
        fallback <= 1'b0;
        compat <= 1'b0;
    end else if (!sd_init_done || !start_ok) begin
        state <= WAIT_SD;
        fallback <= 1'b0;
        compat <= 1'b0;
    end else begin
        case (state)
            WAIT_SD: state <= KICK;
            KICK: state <= WAIT_CLEAR;
            WAIT_CLEAR: if (!scan_done) state <= WAIT_DONE;
            WAIT_DONE: if (scan_done) begin
                if (scan_found_valid || fallback) state <= FINISHED;
                else begin
                    if (COMPAT_FIRST != 0 && !compat) compat <= 1'b1;
                    else fallback <= 1'b1;
                    state <= KICK;
                end
            end
            FINISHED: state <= FINISHED;
            default: state <= WAIT_SD;
        endcase
    end
end
endmodule
