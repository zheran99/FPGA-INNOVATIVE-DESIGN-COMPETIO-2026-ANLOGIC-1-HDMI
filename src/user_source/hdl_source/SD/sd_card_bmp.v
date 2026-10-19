module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,

    parameter integer AUTO_INTERVAL_MS  = 5000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,

    parameter [4:0]   SCAN_TARGET_COUNT = 5'd16,

    parameter         DISABLE_PRELOAD   = 1'b0,

    parameter [31:0]  SCAN_HIT_LIMIT    = 32'd100000
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_prev,        // Step2：上一张（按下=0）
    input                       key_auto,
    output [3:0]                state_code,

    output                      scan_warn_o,
    output [4:0]                img_found_cnt_o,

    output [2:0]                ctrl_diag_o,
    output reg                  auto_play_en_o,

    output reg [4:0]            img_idx_o,        // 当前显示图片的 1-based 序号
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output reg [1:0]            prev_disp_idx,
    output reg                  transition_tgl,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,

    input                       sd_init_done,     // 由顶层从 sd_card_mgr 引入
    output                      sd_sec_read,
    output [31:0]               sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end
);

wire key_next_press;
wire key_prev_press;
wire key_auto_press;

wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             bmp_ready;
wire             scan_done;
wire             scan_warn;          // 扫描触上限警告（粘滞）
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [4:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;

reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [4:0]        img_found_count;
reg [3:0]        img_idx;              // 图号 0..15 4 位
reg [3:0]        load_idx;             // 图号 0..15 4 位
reg [1:0]        pending_buf_idx;      // 槽号 0..2（保持 2 位）

reg [31:0]       img_sector [0:15];
reg              next_req_pending;
reg              prev_req_pending;
reg              load_busy;

reg              source_done_seen;
reg              finish_seen;

reg [28:0]       load_wdog;
reg              load_timeout;
wire             load_wdog_fire;

reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [3:0] next_from_current;

integer i;

localparam [4:0] SLOT_INVALID = 5'd31;

reg [4:0] slot_pic0, slot_pic1, slot_pic2;

function [4:0] slot_pic_lut;
    input [1:0] s;
    begin
        case (s)
            2'd0:    slot_pic_lut = slot_pic0;
            2'd1:    slot_pic_lut = slot_pic1;
            2'd2:    slot_pic_lut = slot_pic2;
            default: slot_pic_lut = SLOT_INVALID;
        endcase
    end
endfunction

// 角色槽号
wire [1:0] cur_slot  = disp_buf_idx;
wire [1:0] next_slot = (disp_buf_idx == 2'd0) ? 2'd1 :
                       (disp_buf_idx == 2'd1) ? 2'd2 : 2'd0;
wire [1:0] prev_slot = (disp_buf_idx == 2'd0) ? 2'd2 :
                       (disp_buf_idx == 2'd1) ? 2'd0 : 2'd1;

wire [3:0] next_pic = next_from_current;                 // 已有的下一个
wire [3:0] prev_pic = prev_index_limited(img_idx, img_found_count);

function [1:0] find_slot;
    input [4:0] pic5;
    begin
        if      (slot_pic0 == pic5) find_slot = 2'd0;
        else if (slot_pic1 == pic5) find_slot = 2'd1;
        else if (slot_pic2 == pic5) find_slot = 2'd2;
        else                        find_slot = 2'd3;
    end
endfunction

wire [1:0] next_found_c = find_slot({1'b0, next_pic});
wire [1:0] prev_found_c = find_slot({1'b0, prev_pic});

wire next_valid_c = (next_found_c != 2'd3) && (next_found_c != cur_slot);
wire prev_valid_c = (prev_found_c != 2'd3) && (prev_found_c != cur_slot);

// 7 级优先级链条件 load_idx

reg [1:0] next_found_r, prev_found_r;
reg       next_valid_r, prev_valid_r;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        next_found_r <= 2'd3;      // 3 = 无效（安全初值）
        prev_found_r <= 2'd3;
        next_valid_r <= 1'b0;
        prev_valid_r <= 1'b0;
    end else begin
        next_found_r <= next_found_c;
        prev_found_r <= prev_found_c;
        next_valid_r <= next_valid_c;
        prev_valid_r <= prev_valid_c;
    end
end

wire [1:0] next_found = next_found_r;
wire [1:0] prev_found = prev_found_r;
wire       next_valid = next_valid_r;
wire       prev_valid = prev_valid_r;

reg [3:0] next_pic_r, prev_pic_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        next_pic_r <= 4'd0;
        prev_pic_r <= 4'd0;
    end else begin
        next_pic_r <= next_pic;
        prev_pic_r <= prev_pic;
    end
end

reg last_dir;          // 0 = 上次是“下一张”，1 = 上次是“上一张”

wire [3:0] pf_pic_r = last_dir ? prev_pic_r : next_pic_r;   // 寄存版预加载目标图号
wire [1:0] pf_slot = last_dir ? prev_slot : next_slot;
wire [1:0] pf_found = last_dir ? prev_found : next_found;

wire pf_valid = (pf_found != 2'd3) && (pf_found != cur_slot);

function [31:0] pf_sector_of;
    input [3:0] idx;
    begin
        pf_sector_of = img_sector[idx];
    end
endfunction

reg pending_is_switch;

reg        load_start_d;
reg [31:0] load_sector_q;       // 下一个扇区值（由 load_idx 查表）

always @(posedge clk or posedge rst) begin
    if (rst) begin
        load_start_d  <= 1'b0;
        load_sector_q <= 32'd0;
    end else begin
        load_start_d  <= load_start_pulse;

        load_sector_q <= pf_sector_of(load_idx);
    end
end

wire [31:0] load_sector = load_sector_q;

function [15:0] to565;
    input [23:0] rgb;
    begin
        to565 = {rgb[23:19], rgb[15:10], rgb[7:3]};   // 5-6-5
    end
endfunction

reg        rgb565_phase;       // 0=等待偶像素, 1=已存偶像素等奇像素
reg [15:0] pix_even;
reg [31:0] wdata565;
reg        wdata565_en;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rgb565_phase <= 1'b0;
        pix_even     <= 16'd0;
        wdata565     <= 32'd0;
        wdata565_en  <= 1'b0;
    end else begin
        wdata565_en <= 1'b0;

if (load_start_d)
            rgb565_phase <= 1'b0;

        if (bmp_data_wr_en) begin
            if (!rgb565_phase) begin
                pix_even     <= to565(bmp_data);
                rgb565_phase <= 1'b1;
            end else begin
                wdata565     <= {to565(bmp_data), pix_even};
                wdata565_en  <= 1'b1;
                rgb565_phase <= 1'b0;
            end
        end
    end
end

assign write_en   = wdata565_en;
assign write_data = wdata565;

localparam [31:0] AUTO_TICK_MAX = (CLK_FREQ_HZ / 1000) * AUTO_INTERVAL_MS - 1;
assign auto_tick  = (auto_cnt == AUTO_TICK_MAX);
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

assign load_wdog_fire = load_busy && (load_wdog >= 29'd500000000);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_prev (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_prev),
    .press_pulse(key_prev_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [3:0] next_index_limited;
    input [3:0] cur;
    input [4:0] cnt;          // 0..16（完整 5 位）
    reg [4:0] cur5;
    begin
        cur5 = {1'b0, cur};                     // 零扩展到 5 位
        if (cnt == 5'd0)
            next_index_limited = 4'd0;
        else if (cur5 + 5'd1 >= cnt)
            next_index_limited = 4'd0;          // 回绕
        else
            next_index_limited = cur + 4'd1;
    end
endfunction

function [3:0] prev_index_limited;
    input [3:0] cur;
    input [4:0] cnt;          // 0..16（完整 5 位）
    begin
        if (cnt == 5'd0)
            prev_index_limited = 4'd0;
        else if (cur == 4'd0)
            prev_index_limited = cnt[3:0] - 4'd1;   // cur=0 末张（cnt-1）
        else
            prev_index_limited = cur - 4'd1;
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图写槽 0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else if (cur_disp_buf == 2'd1)
            next_buf_lut = 2'd2;
        else
            next_buf_lut = 2'd0;                 // 2 0（3 槽环形）
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;

        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 5'd0;
        img_idx               <= 4'd0;
        load_idx              <= 4'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        prev_disp_idx         <= 2'd0;       // 转场旧图槽
        transition_tgl        <= 1'b0;       // 切图事件 toggle

        for (i = 0; i < 16; i = i + 1)
            img_sector[i] <= 32'd0;
        next_req_pending      <= 1'b0;
        prev_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        finish_seen           <= 1'b0;
        load_wdog             <= 29'd0;
        load_timeout          <= 1'b0;
        display_valid         <= 1'b0;
        auto_play_en_o        <= 1'b0;
        img_idx_o             <= 5'd1;
        slot_pic0             <= SLOT_INVALID;
        slot_pic1             <= SLOT_INVALID;
        slot_pic2             <= SLOT_INVALID;
        pending_is_switch     <= 1'b0;
        last_dir              <= 1'b0;      // 默认“前进”方向
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 5'd0;
            img_idx               <= 4'd0;
            load_idx              <= 4'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            prev_disp_idx         <= 2'd0;
            transition_tgl        <= 1'b0;
            for (i = 0; i < 16; i = i + 1)
                img_sector[i] <= 32'd0;
            next_req_pending      <= 1'b0;
            prev_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            finish_seen           <= 1'b0;
            display_valid         <= 1'b0;
            auto_play_en_o        <= 1'b0;
            img_idx_o             <= 5'd1;
            slot_pic0             <= SLOT_INVALID;
            slot_pic1             <= SLOT_INVALID;
            slot_pic2             <= SLOT_INVALID;
            pending_is_switch     <= 1'b0;
            last_dir              <= 1'b0;      // 默认“前进”方向
        end else begin

            if (scan_found_valid) begin
                img_sector[img_found_count[3:0]] <= scan_found_sector;

                if (img_found_count < 5'd16)
                    img_found_count <= img_found_count + 5'd1;
            end

            if (!load_busy) begin
                source_done_seen <= 1'b0;
                finish_seen      <= 1'b0;
            end else begin
                if (bmp_ready)          source_done_seen <= 1'b1;  // 源把图送完
                if (write_finish_pulse) finish_seen      <= 1'b1;
            end

            if (load_busy && source_done_seen && finish_seen) begin
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                finish_seen           <= 1'b0;

                case (pending_buf_idx)
                    2'd0: slot_pic0 <= {1'b0, load_idx};
                    2'd1: slot_pic1 <= {1'b0, load_idx};
                    2'd2: slot_pic2 <= {1'b0, load_idx};
                    default: ;
                endcase

                if (pending_is_switch) begin
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;

                    if (first_image_committed) begin
                        prev_disp_idx  <= disp_buf_idx;
                        transition_tgl <= ~transition_tgl;
                    end
                end else begin

                    if (!first_image_committed)
                        first_image_committed <= 1'b1;
                end
            end

            if (!load_busy || bmp_data_wr_en)
                load_wdog <= 29'd0;
            else if (!load_wdog_fire)
                load_wdog <= load_wdog + 29'd1;

            if (load_wdog_fire) begin
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                finish_seen      <= 1'b0;
                load_timeout     <= 1'b1;
            end

            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 5'd0;
                img_idx               <= 4'd0;
                load_idx              <= 4'd0;
                pending_buf_idx       <= 2'd0;      // 槽号仍 2 位
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                prev_disp_idx         <= 2'd0;
                transition_tgl        <= 1'b0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin

                if (key_next_press && scan_done && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                if (key_prev_press && scan_done && (img_found_count > 3'd0))
                    prev_req_pending <= 1'b1;

                if (key_auto_press && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                auto_play_en_o <= auto_play_en;
                img_idx_o      <= img_idx + 5'd1;   // 0-based 1-based（5 位）

                if (scan_done && auto_play_en && display_valid && !load_busy
                    && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                if (scan_done && !first_image_committed && bmp_ready && !load_busy
                    && (img_found_count != 3'd0)) begin
                    load_idx          <= 4'd0;

                    pending_buf_idx   <= 2'd0;
                    write_buf_idx     <= 2'd0;
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    next_req_pending  <= 1'b0;
                    prev_req_pending  <= 1'b0;
                    pending_is_switch <= 1'b1;   // 首图 = 切换（要置 display_valid）
                    auto_cnt          <= 32'd0;
                end

                else if (display_valid && !load_busy && prev_req_pending && prev_valid
                         && (img_found_count > 3'd1)) begin
                    prev_req_pending <= 1'b0;
                    next_req_pending <= 1'b0;
                    disp_buf_idx     <= prev_found;
                    img_idx          <= prev_pic_r;
                    last_dir         <= 1'b1;    // 记住：用户往回看
                    auto_cnt         <= 32'd0;   // 手动操作 复位轮播计时
                    prev_disp_idx    <= disp_buf_idx;
                    transition_tgl   <= ~transition_tgl;
                end

                else if (display_valid && !load_busy && next_req_pending && next_valid
                         && (img_found_count > 3'd0)) begin
                    next_req_pending <= 1'b0;
                    prev_req_pending <= 1'b0;
                    disp_buf_idx     <= next_found;
                    img_idx          <= next_pic_r;
                    last_dir         <= 1'b0;    // 记住：用户往前看
                    auto_cnt         <= 32'd0;
                    prev_disp_idx    <= disp_buf_idx;
                    transition_tgl   <= ~transition_tgl;
                end

                else if (scan_done && bmp_ready && display_valid && !load_busy
                         && prev_req_pending && !prev_valid && (img_found_count > 3'd1)) begin
                    load_idx          <= prev_pic_r;

                    pending_buf_idx   <= prev_slot;   // 写 prev 槽（不碰 next）
                    write_buf_idx     <= prev_slot;
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    prev_req_pending  <= 1'b0;
                    pending_is_switch <= 1'b1;
                    last_dir          <= 1'b1;        // 记住方向
                    auto_cnt          <= 32'd0;
                end

                else if (scan_done && bmp_ready && display_valid && !load_busy
                         && next_req_pending && !next_valid && (img_found_count > 3'd0)) begin
                    load_idx          <= next_pic_r;

                    pending_buf_idx   <= next_slot;
                    write_buf_idx     <= next_slot;
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    next_req_pending  <= 1'b0;
                    pending_is_switch <= 1'b1;
                    last_dir          <= 1'b0;        // 记住方向
                    auto_cnt          <= 32'd0;
                end

                else if (scan_done && bmp_ready && display_valid && !load_busy
                         && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    auto_cnt <= 32'd0;               // 到点即复位计时
                    last_dir <= 1'b0;                // 轮播=前进方向
                    if (next_valid) begin
                        disp_buf_idx     <= next_found;
                        img_idx          <= next_pic_r;
                        pending_is_switch<= 1'b0;    // 本拍没启动加载
                        prev_disp_idx    <= disp_buf_idx;
                        transition_tgl   <= ~transition_tgl;
                    end else begin
                        load_idx          <= next_pic_r;

                        pending_buf_idx   <= next_slot;
                        write_buf_idx     <= next_slot;
                        load_start_pulse  <= 1'b1;
                        load_busy         <= 1'b1;
                        source_done_seen  <= 1'b0;
                        pending_is_switch <= 1'b1;
                    end
                end

                else if (!DISABLE_PRELOAD
                         && scan_done && bmp_ready && display_valid && !load_busy
                         && !next_req_pending && !prev_req_pending
                         && !pf_valid && !auto_play_en
                         && (img_found_count > 3'd1)) begin
                    load_idx          <= pf_pic_r;              // 跟随方向

                    pending_buf_idx   <= pf_slot;             // 跟随方向
                    write_buf_idx     <= pf_slot;
                    load_start_pulse  <= 1'b1;
                    load_busy         <= 1'b1;
                    source_done_seen  <= 1'b0;
                    pending_is_switch <= 1'b0;       // 预加载 不切显示
                end
            end
        end
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_hit_limit         (SCAN_HIT_LIMIT),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_warn              (scan_warn),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_d),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

// 诊断输出
assign scan_warn_o      = scan_warn;
assign img_found_cnt_o  = img_found_count;

assign ctrl_diag_o      = {load_busy, scan_done, load_timeout};

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
