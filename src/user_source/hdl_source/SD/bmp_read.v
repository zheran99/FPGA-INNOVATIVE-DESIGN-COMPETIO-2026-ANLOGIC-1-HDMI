module bmp_read(
    input                       clk,
    input                       rst,
    output                      ready,

    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    // 防呆扫描扇区数硬上限

    input  [31:0]               scan_hit_limit,
    input  [4:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [4:0]            scan_found_total,       // 计数需 5 位

    output reg                  scan_warn,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;

localparam SF_DEPTH = 256;    // Source FIFO depth (BRAM)
localparam SF_PAUSE = 64;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

reg header_match;
wire header_match_d;
reg hdr_byte_valid;
reg [7:0] hdr_byte;
reg [9:0] hdr_byte_index;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;

reg [31:0] file_sector_count_r;

always @(posedge clk or posedge rst) begin
    if (rst)
        file_sector_count_r <= 32'd1;
    else
        file_sector_count_r <= (file_len == 32'd0) ? 32'd1
                                                  : ((file_len + 32'd511) >> 9);
end

assign ready = (state == ST_IDLE);

assign header_match_d = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (width  != 32'd0) &&
                      (height != 32'd0) &&
                      (width  <= 32'd8191) &&
                      (height <= 32'd8191) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        hdr_byte_valid <= 1'b0;
        hdr_byte <= 8'd0;
        hdr_byte_index <= 10'd0;
        header_match <= 1'b0;
    end else begin
        hdr_byte_valid <= ((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid;
        hdr_byte <= sd_sec_read_data;
        hdr_byte_index <= rd_cnt;
        header_match <= header_match_d;
    end
end
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = file_sector_count_r;
assign next_scan_sector_if_match = scan_sector + file_sector_count_r;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

reg [12:0] sw, sh, sw_last;
reg [16:0] sw9, sh16;
reg [23:0] sw720_a, sw720_b, swx720, shx1280;
reg [14:0] sw3, row_size;
reg bind_x, upscale;
reg [12:0] num, fit_den;
reg [10:0] den;
reg [12:0] step_work;
reg [3:0] step_q, base_q;
reg [10:0] base_rem;
reg [23:0] fit_rem;
reg [10:0] fit_q, fit_r;
reg [10:0] ow, oh, x0, x_end;
reg [9:0] y0, y_end;
reg geo_ready;
localparam GEO_CAPTURE = 4'd0, GEO_CONST_A = 4'd1,
           GEO_CONST_B = 4'd2, GEO_DIV_INIT = 4'd3,
           GEO_DIV = 4'd4, GEO_SIZE = 4'd5,
           GEO_BEGIN = 4'd6, GEO_END = 4'd7, GEO_DONE = 4'd8,
           GEO_DDA_DIV = 4'd9;
reg [3:0] geo_phase;
wire load_launch = (state == ST_LOAD_WAIT) && geo_ready && write_req_ack;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sw <= 0; sh <= 0; sw_last <= 0;
        sw9 <= 0; sh16 <= 0;
        sw720_a <= 0; sw720_b <= 0; swx720 <= 0; shx1280 <= 0;
        sw3 <= 0; row_size <= 0;
        bind_x <= 0; upscale <= 0; num <= 0; den <= 0;
        step_work <= 0; step_q <= 0; base_q <= 0; base_rem <= 0;
        fit_den <= 0; fit_rem <= 0; fit_q <= 0; fit_r <= 0;
        ow <= 0; oh <= 0; x0 <= 0; y0 <= 0; x_end <= 0; y_end <= 0;
        geo_phase <= GEO_CAPTURE;
        geo_ready <= 1'b0;
    end else if (!sd_init_done || (state == ST_IDLE && load_start)) begin
        geo_phase <= GEO_CAPTURE;
        geo_ready <= 1'b0;
    end else if (state == ST_LOAD_WAIT) begin
        case (geo_phase)
            GEO_CAPTURE: begin
                sw <= width[12:0];
                sh <= height[12:0];
                geo_ready <= 1'b0;
                geo_phase <= GEO_CONST_A;
            end
            GEO_CONST_A: begin

                sw9 <= {1'b0, sw, 3'b0} + {4'b0, sw};
                sh16 <= {sh, 4'b0};
                sw720_a <= {2'b0, sw, 9'b0} + {4'b0, sw, 7'b0};
                sw720_b <= {5'b0, sw, 6'b0} + {7'b0, sw, 4'b0};
                shx1280 <= {1'b0, sh, 10'b0} + {3'b0, sh, 8'b0};
                sw3 <= {1'b0, sw, 1'b0} + {2'b0, sw};
                sw_last <= sw - 13'd1;
                geo_phase <= GEO_CONST_B;
            end
            GEO_CONST_B: begin
                bind_x <= (sw9 >= sh16);
                swx720 <= sw720_a + sw720_b;
                upscale <= (sw < 13'd1280) && (sh < 13'd720);
                row_size <= (sw3 + 15'd3) & 15'h7ffc;
                geo_phase <= GEO_DIV_INIT;
            end
            GEO_DIV_INIT: begin
                num <= bind_x ? sw : sh;
                den <= bind_x ? 11'd1280 : 11'd720;
                step_work <= bind_x ? sw : sh;
                step_q <= 4'd0;
                base_q <= 4'd1;
                base_rem <= 11'd0;
                fit_den <= bind_x ? sw : sh;
                fit_rem <= bind_x ? shx1280 : swx720;
                fit_q <= 11'd0;

                geo_phase <= GEO_DDA_DIV;
            end
            GEO_DDA_DIV: begin

                if (step_work >= {2'd0, den}) begin
                    step_work <= step_work - {2'd0, den};
                    step_q <= step_q + 4'd1;
                end else begin
                    base_q <= step_q;
                    base_rem <= step_work[10:0];
                    geo_phase <= GEO_DIV;
                end
            end
            GEO_DIV: begin
                if (fit_rem >= {11'd0, fit_den}) begin
                    fit_rem <= fit_rem - {11'd0, fit_den};
                    fit_q <= fit_q + 11'd1;
                end else begin
                    fit_r <= fit_q;
                    geo_phase <= GEO_SIZE;
                end
            end
            GEO_SIZE: begin

                ow <= bind_x ? 11'd1280 : fit_r;
                oh <= bind_x ? fit_r : 11'd720;
                geo_phase <= GEO_BEGIN;
            end
            GEO_BEGIN: begin
                x0 <= (11'd1280 - ow) >> 1;
                y0 <= (11'd720 - oh) >> 1;
                geo_phase <= GEO_END;
            end
            GEO_END: begin
                x_end <= x0 + ow;
                y_end <= {1'b0, y0} + oh;
                geo_ready <= 1'b1;
                geo_phase <= GEO_DONE;
            end
            default: ;
        endcase
    end
end

reg [23:0] px_rgb;
reg [23:0] sfifo [0:SF_DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0]  sf_wp, sf_rp;
reg [8:0]  sf_cnt;                            // 0..256
wire       sf_full  = (sf_cnt == 9'd256);
wire       sf_empty = (sf_cnt == 9'd0);
reg [23:0] sf_dout;
reg sf_data_valid;
wire sf_rd;

always @(posedge clk) begin
    sf_dout <= sfifo[sf_rp];
end
always @(posedge clk or posedge rst) begin
    if (rst)
        sf_data_valid <= 1'b0;
    else if (load_launch || state != ST_LOAD_DATA)
        sf_data_valid <= 1'b0;
    else
        sf_data_valid <= !sf_empty && !sf_rd;
end

reg        sf_wr;                             // 源装配推入（寄存器脉冲）

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sf_wp <= 8'd0;
        sf_rp <= 8'd0;
        sf_cnt <= 9'd0;
    end else if (load_launch) begin

        sf_wp <= 8'd0;
        sf_rp <= 8'd0;
        sf_cnt <= 9'd0;
    end else begin
        case ({sf_wr && !sf_full, sf_rd && !sf_empty})
            2'b10: begin sf_wp <= sf_wp + 8'd1; sf_cnt <= sf_cnt + 9'd1; end
            2'b01: begin sf_rp <= sf_rp + 8'd1; sf_cnt <= sf_cnt - 9'd1; end
            2'b11: begin sf_wp <= sf_wp + 8'd1; sf_rp <= sf_rp + 8'd1; end
            default: ;
        endcase
    end
end

always @(posedge clk) begin
    if (sf_wr && !sf_full)
        sfifo[sf_wp] <= px_rgb;
end

reg  [14:0] row_byte;                         // 当前源行内的字节位置 0..row_size-1

wire px_byte = bmp_data_valid && (row_byte < sw3);        // 该字节是像素字节
wire px_done = px_byte && (bmp_byte_idx == 2'd2);         // 第 3 字节 像素齐

always @(posedge clk or posedge rst) begin
    if (rst)
        row_byte <= 15'd0;
    else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            if (row_byte + 15'd1 >= row_size)
                row_byte <= 15'd0;
            else
                row_byte <= row_byte + 15'd1;
        end
    end else
        row_byte <= 15'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        bmp_byte_idx <= 2'd0;
    else if (state == ST_LOAD_DATA) begin
        if (px_byte)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else
        bmp_byte_idx <= 2'd0;
end

always @(posedge clk or posedge rst) begin
    if (rst)
        px_rgb <= 24'd0;
    else if (px_byte) begin
        case (bmp_byte_idx)
            2'd0: px_rgb[7:0]   <= sd_sec_read_data;
            2'd1: px_rgb[15:8]  <= sd_sec_read_data;
            2'd2: px_rgb[23:16] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        sf_wr <= 1'b0;
    else
        sf_wr <= px_done;
end

reg [10:0] acc_x, acc_y;                      // DDA remainder < den <= 1280
reg [12:0] need_sx, need_sy;                  // 当前输出像素所需的源列/行
reg [12:0] cons_sx, cons_sy;                  // 源流已消费到的列/行
reg [11:0] outx;                              // 0..1279
reg [10:0] outy;                              // 0..719
reg        out_done;
reg [4:0]  out_tick;                          // 输出节流计数器（0..31）

reg [3:0] dda_valid;
reg [11:0] sum_x_q, sum_y_q, sum_x_dist, sum_y_dist;
reg [3:0] adv_x_q, adv_y_q, adv_x_dist, adv_y_dist;
reg [3:0] adv_x, adv_y;
reg carry_x_q, carry_y_q;
reg [11:0] distance_x, distance_y;
reg [11:0] rem_x, rem_y;
wire do_action;

always @(posedge clk or posedge rst) begin
    if (rst)
        dda_valid <= 4'b0;
    else if (state != ST_LOAD_DATA || do_action)
        dda_valid <= 4'b0;
    else
        dda_valid <= {dda_valid[2:0], 1'b1};
end

reg [11:0] sum_x_r, sum_y_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sum_x_r <= 12'd0;
        sum_y_r <= 12'd0;
    end else begin

        sum_x_r <= {1'b0, acc_x} + {1'b0, base_rem};
        sum_y_r <= {1'b0, acc_y} + {1'b0, base_rem};
    end
end

wire carry_x = sum_x_r >= {1'b0, den};
wire carry_y = sum_y_r >= {1'b0, den};
wire [3:0] adv_x_calc = base_q + {3'd0, carry_x};
wire [3:0] adv_y_calc = base_q + {3'd0, carry_y};
wire [11:0] adv_x_den = carry_x_q ? {1'b0, den} : 12'd0;
wire [11:0] adv_y_den = carry_y_q ? {1'b0, den} : 12'd0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sum_x_q <= 0; sum_y_q <= 0;
        sum_x_dist <= 0; sum_y_dist <= 0;
        adv_x_q <= 0; adv_y_q <= 0;
        carry_x_q <= 0; carry_y_q <= 0;
        adv_x_dist <= 0; adv_y_dist <= 0;
        distance_x <= 0; distance_y <= 0;
        rem_x <= 0; rem_y <= 0;
        adv_x <= 0; adv_y <= 0;
    end else begin
        sum_x_q <= sum_x_r;
        sum_y_q <= sum_y_r;
        adv_x_q <= adv_x_calc;
        adv_y_q <= adv_y_calc;
        carry_x_q <= carry_x;
        carry_y_q <= carry_y;
        sum_x_dist <= sum_x_q;
        sum_y_dist <= sum_y_q;
        adv_x_dist <= adv_x_q;
        adv_y_dist <= adv_y_q;
        distance_x <= adv_x_den;
        distance_y <= adv_y_den;
        rem_x <= sum_x_dist - distance_x;
        rem_y <= sum_y_dist - distance_y;
        adv_x <= adv_x_dist;
        adv_y <= adv_y_dist;
    end
end

wire [11:0] outx_p1 = {1'b0, outx} + 12'd1;
wire [11:0] outy_p1 = {1'b0, outy} + 12'd1;
wire [11:0] x0w     = {1'b0, x0};
wire [11:0] y0w     = {2'b0, y0};
wire in_x      = ({1'b0, outx} >= x0w) && ({1'b0, outx} < {1'b0, x_end});
wire in_y      = ({1'b0, outy} >= y0w) && ({1'b0, outy} < {2'b0, y_end});
wire in_img    = in_x && in_y;
wire in_x_next = (outx_p1 >= x0w) && (outx_p1 < {1'b0, x_end});
wire in_y_next = (outy_p1 >= y0w) && (outy_p1 < {2'b0, y_end});

// 源光标是否已到达所需位置

reg at_need;
always @(posedge clk or posedge rst) begin
    if (rst)
        at_need <= 1'b0;
    else
        at_need <= (cons_sy == need_sy) && (cons_sx == need_sx);
end

assign do_action = (state == ST_LOAD_DATA) && !out_done && !up_filling && dda_valid[3] && (out_tick == 5'd0);
wire act_skip_dn = !upscale && do_action && in_img && !sf_empty && sf_data_valid && !at_need;

assign sf_rd = act_skip_dn || up_fill_consume;

reg src_done_r;
reg src_fifo_full_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        src_done_r      <= 1'b0;
        src_fifo_full_r <= 1'b0;
    end else begin
        src_done_r      <= (bmp_len_cnt >= file_len);
        src_fifo_full_r <= (sf_cnt >= SF_PAUSE);
    end
end

wire src_want = !out_done && !src_done_r && !src_fifo_full_r;

reg [23:0] lbuf [0:2047]; /* fehdl force_ram=1, ram_style="bram" */
reg        up_filling;                          // 1 = 正在填充行缓冲
reg        up_preload;                          // 1 = 填充预载拍（读第一个源像素）
reg [10:0] up_wp;                               // 填充写指针 0..ow-1
reg [11:0] up_xacc;                             // 填充横向 DDA 累加器（<2*den）
reg [23:0] up_pix;                              // 填充当前源像素（888）
reg [23:0] lbuf_dout;                           // lbuf 读预取

reg [9:0]  ds_sum_r;      // 组内红通道累加（≤3×255=765）
reg [9:0]  ds_sum_g;      // 组内绿通道累加
reg [9:0]  ds_sum_b;      // 组内蓝通道累加
reg [1:0]  ds_cnt;        // 组内已累加像素数 0..3

function [7:0] ds_avg;
    input [9:0] sum;
    input [1:0] cnt;
    reg [31:0] prod;
    begin
        case (cnt)
            2'd1: ds_avg = sum[7:0];
            2'd2: ds_avg = sum[9:1];
            2'd3: begin
                prod = sum * 32'd43691;
                ds_avg = prod[24:17];   // (sum*43691)>>17，取低 8 位
            end
            default: ds_avg = sum[7:0];
        endcase
    end
endfunction

wire [10:0] lbuf_addr = ({1'b0, outx} >= x0w) ? ({1'b0, outx} - x0w) : 11'd0;

wire        up_need_new = (up_xacc + {1'b0, num[10:0]} >= {1'b0, den}) && (up_wp != ow - 11'd1);
wire        up_write_ok = !up_preload && !(up_need_new && (sf_empty || !sf_data_valid));

wire        up_fill_consume = up_filling && (
                  (up_preload && !sf_empty && sf_data_valid) ||
                  (up_write_ok && up_need_new));

always @(posedge clk) begin
    lbuf_dout <= lbuf[lbuf_addr];
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        outx          <= 12'd0;
        outy          <= 11'd0;
        out_done      <= 1'b0;
        need_sx       <= 13'd0;
        need_sy       <= 13'd0;
        acc_x         <= 11'd0;
        acc_y         <= 11'd0;
        cons_sx       <= 13'd0;
        cons_sy       <= 13'd0;
        out_tick      <= 5'd16;
        bmp_data_wr_en <= 1'b0;
        bmp_data      <= 24'd0;
        up_filling    <= 1'b0;
        up_preload    <= 1'b0;
        up_wp         <= 11'd0;
        up_xacc       <= 12'd0;
        up_pix        <= 24'd0;
        ds_sum_r      <= 10'd0;
        ds_sum_g      <= 10'd0;
        ds_sum_b      <= 10'd0;
        ds_cnt        <= 2'd0;
    end else if (load_launch || state != ST_LOAD_DATA) begin
        outx          <= 12'd0;
        outy          <= 11'd0;
        out_done      <= 1'b0;
        need_sx       <= 13'd0;
        need_sy       <= 13'd0;
        acc_x         <= 11'd0;
        acc_y         <= 11'd0;
        cons_sx       <= 13'd0;
        cons_sy       <= 13'd0;
        out_tick      <= 5'd16;
        bmp_data_wr_en <= 1'b0;
        bmp_data      <= 24'd0;

        up_filling    <= upscale && (ow != 11'd0);
        up_preload    <= upscale && (ow != 11'd0);
        up_wp         <= 11'd0;
        up_xacc       <= 12'd0;
        up_pix        <= 24'd0;
        ds_sum_r      <= 10'd0;
        ds_sum_g      <= 10'd0;
        ds_sum_b      <= 10'd0;
        ds_cnt        <= 2'd0;
    end else if (upscale) begin
        if (up_filling) begin

            bmp_data_wr_en <= 1'b0;
            if (up_preload) begin
                if (!sf_empty && sf_data_valid) begin
                    up_pix      <= sf_dout;
                    up_preload  <= 1'b0;
                    up_wp       <= 11'd0;
                    up_xacc     <= 12'd0;
                end
            end else if (up_write_ok) begin

                lbuf[up_wp] <= up_pix;
                if (up_need_new) begin
                    up_xacc <= up_xacc + {1'b0, num[10:0]} - {1'b0, den};
                    up_pix  <= sf_dout;                 // 读下一个源像素
                end else begin
                    up_xacc <= up_xacc + {1'b0, num[10:0]};
                end
                if (up_wp == ow - 11'd1)
                    up_filling <= 1'b0;                 // 填满 ow 个条目
                else
                    up_wp <= up_wp + 11'd1;
            end
        end else begin

            out_tick       <= out_tick + 5'd1;
            bmp_data_wr_en <= 1'b0;
            if (do_action) begin
                if (!in_img) begin
                    bmp_data_wr_en <= 1'b1;
                    bmp_data      <= 24'd0;
                end else begin
                    bmp_data_wr_en <= 1'b1;
                    bmp_data      <= lbuf_dout;
                end
                if (outx == 12'd1279) begin
                    outx    <= 12'd0;
                    need_sx <= 13'd0;
                    acc_x   <= 11'd0;
                    if (outy == 11'd719) begin
                        out_done <= 1'b1;
                    end else begin
                        outy <= outy + 11'd1;
                        if (in_y && in_y_next) begin
                            acc_y   <= rem_y[10:0];
                            need_sy <= need_sy + {9'd0, adv_y};
                            if (adv_y != 4'd0 && (ow != 11'd0)) begin
                                up_filling <= 1'b1;
                                up_preload <= 1'b1;
                            end
                        end
                    end
                end else begin
                    outx <= outx + 12'd1;
                end
            end
        end
    end else begin
        out_tick       <= out_tick + 5'd1;
        bmp_data_wr_en <= 1'b0;

        if (do_action) begin
            if (!in_img) begin
                bmp_data_wr_en <= 1'b1;
                bmp_data      <= 24'd0;
                if (outx == 12'd1279) begin
                    outx    <= 12'd0;
                    need_sx <= 13'd0;
                    acc_x   <= 11'd0;
                    if (outy == 11'd719) begin
                        out_done <= 1'b1;
                    end else begin
                        outy <= outy + 11'd1;
                        if (in_y && in_y_next) begin
                            acc_y   <= rem_y[10:0];
                            need_sy <= need_sy + {9'd0, adv_y};
                        end
                    end
                end else begin
                    outx <= outx + 12'd1;
                end
            end else begin
                if (!sf_empty && sf_data_valid) begin
                    if (at_need) begin

                        bmp_data_wr_en <= 1'b1;
                        bmp_data      <= {ds_avg(ds_sum_r, ds_cnt),
                                          ds_avg(ds_sum_g, ds_cnt),
                                          ds_avg(ds_sum_b, ds_cnt)};
                        ds_sum_r      <= 10'd0;
                        ds_sum_g      <= 10'd0;
                        ds_sum_b      <= 10'd0;
                        ds_cnt        <= 2'd0;
                        if (outx == 12'd1279) begin
                            outx    <= 12'd0;
                            need_sx <= 13'd0;
                            acc_x   <= 11'd0;
                            if (outy == 11'd719) begin
                                out_done <= 1'b1;
                            end else begin
                                outy <= outy + 11'd1;
                                if (in_y && in_y_next) begin
                                    acc_y   <= rem_y[10:0];
                                    need_sy <= need_sy + {9'd0, adv_y};
                                end
                            end
                        end else begin
                            outx <= outx + 12'd1;
                            if (in_x_next) begin
                                acc_x   <= rem_x[10:0];
                                need_sx <= need_sx + {9'd0, adv_x};
                            end
                        end
                    end else begin

                        ds_sum_r <= ds_sum_r + {2'b00, sf_dout[23:16]};
                        ds_sum_g <= ds_sum_g + {2'b00, sf_dout[15:8]};
                        ds_sum_b <= ds_sum_b + {2'b00, sf_dout[7:0]};
                        ds_cnt   <= ds_cnt + 2'd1;
                        if (cons_sx == sw_last) begin
                            cons_sx <= 13'd0;
                            cons_sy <= cons_sy + 13'd1;

                            ds_sum_r <= 10'd0;
                            ds_sum_g <= 10'd0;
                            ds_sum_b <= 10'd0;
                            ds_cnt   <= 2'd0;
                        end else begin
                            cons_sx <= cons_sx + 13'd1;
                        end
                    end
                end
            end
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (hdr_byte_valid) begin
        case (hdr_byte_index)
            10'd0 : header_0 <= hdr_byte;
            10'd1 : header_1 <= hdr_byte;

            10'd2 : file_len[7:0] <= hdr_byte;
            10'd3 : file_len[15:8] <= hdr_byte;
            10'd4 : file_len[23:16] <= hdr_byte;
            10'd5 : file_len[31:24] <= hdr_byte;

            10'd10: pixel_offset[7:0] <= hdr_byte;
            10'd11: pixel_offset[15:8] <= hdr_byte;
            10'd12: pixel_offset[23:16] <= hdr_byte;
            10'd13: pixel_offset[31:24] <= hdr_byte;

            10'd18: width[7:0] <= hdr_byte;
            10'd19: width[15:8] <= hdr_byte;
            10'd20: width[23:16] <= hdr_byte;
            10'd21: width[31:24] <= hdr_byte;

            10'd22: height[7:0] <= hdr_byte;
            10'd23: height[15:8] <= hdr_byte;
            10'd24: height[23:16] <= hdr_byte;
            10'd25: height[31:24] <= hdr_byte;

            10'd28: bit_count[7:0] <= hdr_byte;
            10'd29: bit_count[15:8] <= hdr_byte;

            10'd30: compression[7:0] <= hdr_byte;
            10'd31: compression[15:8] <= hdr_byte;
            10'd32: compression[23:16] <= hdr_byte;
            10'd33: compression[31:24] <= hdr_byte;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

// 主状态机

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_warn         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 5'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;

        state_code        <= 4'd8;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_warn         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 5'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_warn        <= 1'b0;
                    scan_found_total <= 5'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 5'd1;

                        if ((scan_found_total + 5'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else if (scan_hit_limit != 32'd0 &&
                                     next_scan_sector_if_match >= scan_hit_limit) begin
                            scan_done        <= 1'b1;
                            scan_warn        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if ((scan_sector >= scan_max_sector) ||
                            (scan_hit_limit != 32'd0 &&
                             scan_sector >= scan_hit_limit)) begin
                            scan_done <= 1'b1;
                            scan_warn <= (scan_hit_limit != 32'd0) &&
                                         (scan_sector < scan_max_sector);
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;

                if (load_launch) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code <= 4'd4;

                if (out_done && !sd_sec_read) begin
                    sd_sec_read <= 1'b0;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin

                    sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    if (out_done) begin
                        sd_sec_read <= 1'b0;
                        state       <= ST_IDLE;
                    end else if (src_done_r) begin
                        sd_sec_read <= 1'b0;    // 源读完，等输出收尾
                    end else if (src_want) begin
                        sd_sec_read <= 1'b1;    // 继续读下一扇区（地址已推进）
                    end else begin
                        sd_sec_read <= 1'b0;    // 背压暂停（FIFO 满；恢复时读下一扇区）
                    end
                end else begin

                    sd_sec_read <= sd_sec_read ? 1'b1 : src_want;
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
