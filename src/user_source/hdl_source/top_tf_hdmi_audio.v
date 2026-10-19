module top(
    input                       clk,
    input                       rst_n,          // KEY1 / A2（按下=0）

    input                       key_l,          // C1 板 KEY4 左
    input                       key_m,          // B1 板 KEY3 中
    input                       key_r,          // B2 板 KEY2 右

    input  [3:0]                sw,             // C8/C7/C6/C5 = sw0/s1/s2/s3

    input                       uart_rx,
    output                      uart_tx,

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso,

    output tft_cs_n, tft_reset_n, tft_dc, tft_mosi, tft_sck,
    output touch_cs_n, touch_mosi, touch_sck,
    input touch_miso, touch_irq_n
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;

parameter FRAME_PIXELS  = 24'd460800;   // 1280*720/2 （RGB565 两像素/word）

parameter BUF0_ADDR     = 24'd0;                       // 0 × 460800
parameter BUF1_ADDR     = 24'd460800;                  // 1 × 460800
parameter BUF2_ADDR     = 24'd921600;                  // 2 × 460800

parameter SCAN_BMP_START = 32'd8192;

parameter SCAN_WAV_START = 32'd95104;

parameter SCAN_BMP_COUNT = 5'd9;

parameter SCAN_HIT_LIMIT = 32'd120000;

parameter [31:0] WAV_SCAN_SPAN = 32'd8000;

parameter [2:0] DEBUG_FSM_SEL = 3'd2;

parameter DISABLE_PRELOAD = 1'b0;          // 0 = 启用预加载（生产值）

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire        sd_auto_play;      // 轮播开关状态（来自 sd_card_bmp）
wire [4:0]  sd_img_idx;
wire        sd_scan_warn;
wire [4:0]  sd_img_found_cnt;

wire [2:0]  sd_ctrl_diag;

wire        sd_key_next;       // 经过模式门控的“下一张”
wire        sd_key_prev;       // Step2：经过模式门控的“上一张”
wire        sd_key_auto;       // 经过模式门控的“轮播开关”

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        rd_fifo_empty;

wire        rd_fifo_empty_b;
wire [31:0] video_read_data_b;

wire        rd_fifo_full;

wire        rd_burst_err;
wire [7:0]  rd_burst_diff;

wire        rd_wr_cnt_err;
wire [7:0]  rd_wr_last_addr;

wire        App_wr_busy;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [1:0]  prev_disp_idx;
wire        transition_tgl;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关

wire        audio_valid;
wire volume_valid;
wire [23:0] volume_left,volume_right;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

wire diag_sys_lock,diag_video_lock;
wire rst_ref,rst_sd,rst_mem,rst_pixel,reset_request;
wire rst_ref_n=~rst_ref;
reset_manager u_reset_manager(
 .ref_clk(clk),.sd_clk(sd_card_clk),.mem_clk(ext_mem_clk),.pixel_clk(video_clk),
 .key_n(rst_n),.sys_locked(diag_sys_lock),.video_locked(diag_video_lock),
 .rst_ref(rst_ref),.rst_sd(rst_sd),.rst_mem(rst_mem),.rst_pixel(rst_pixel),
 .request(reset_request));

wire        sd_init_done;
wire        v_sd_sec_read;
wire [31:0] v_sd_sec_read_addr;
wire [7:0]  v_sd_sec_read_data;
wire        v_sd_sec_read_dv;      // data_valid
wire        v_sd_sec_read_end;

wire        a_sd_sec_read;
wire [31:0] a_sd_sec_read_addr;

wire        a_mux_sec_read;
wire [31:0] a_mux_sec_addr;

wire        a_txt_done;
wire        a_txt_found;
wire [7:0]  a_sd_sec_read_data;
wire        a_sd_sec_read_dv;
wire        a_sd_sec_read_end;

wire        a_pcm_wr_en;
wire [47:0] a_pcm_lr;
wire        a_fifo_full;
wire        a_fifo_empty;
wire [10:0] a_fifo_wr_used;
wire [47:0] a_fifo_rd_data;
wire        a_fifo_rd_en;
wire        a_underrun;

wire [31:0] a_sample_cnt;

wire        a_fifo_almost_full = (a_fifo_wr_used >= 11'd896);

wire      audio_pause;            // sw[3]=1 暂停/静音（clk 域）

reg       uart_pause_lvl;
wire      audio_pause_eff = audio_pause | uart_pause_lvl;
reg [1:0] a_pause_sync;
wire      a_play_en = ~a_pause_sync[1];

sys_pll sys_pll_m0(
    .locked(diag_sys_lock),
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .locked(diag_video_lock),
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

reg  dbg_burst_ok;

reg [3:0]  dbg_wr_end_cnt;      // W0：写完成次数（ext_mem_clk 域）
reg        dbg_wr_end_ec;       // 同步前：ext_mem_clk 域边沿检测

wire       frame_write_finish_w = frame_write_finish;

always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem) begin
        dbg_wr_end_cnt <= 4'd0;
        dbg_wr_end_ec  <= 1'b0;
    end else begin
        dbg_wr_end_ec <= frame_write_finish_w;
        if (frame_write_finish_w && !dbg_wr_end_ec)
            dbg_wr_end_cnt <= dbg_wr_end_cnt + 4'd1;
    end
end

always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem) begin
        dbg_burst_ok <= 1'b0;
    end else begin

        dbg_burst_ok <= 1'b1;
    end
end

reg [3:0] dbg_ss_cnt;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        dbg_ss_cnt <= 4'd0;
    else if (dbg_ss_hit && dbg_ss_cnt != 4'hF)
        dbg_ss_cnt <= dbg_ss_cnt + 4'd1;   // 饱和（16 次封顶）
end

wire dbg_ss_hit = (state_code == 4'd4) && display_valid &&
                  (write_buf_idx == disp_buf_idx);

reg [3:0] dbg_ss_c1, dbg_ss_c2;
always @(posedge clk) begin
    dbg_ss_c1 <= dbg_ss_cnt;
    dbg_ss_c2 <= dbg_ss_c1;
end

reg [3:0] dbg_wc_c1, dbg_wc_c2;
always @(posedge clk) begin
    dbg_wc_c1 <= dbg_wr_end_cnt;
    dbg_wc_c2 <= dbg_wc_c1;
end

wire [3:0] dbg_wr_diag = rd_wr_cnt_err ? 4'hE : rd_wr_last_addr[3:0];

wire [3:0] dbg_sdram_flags = rd_burst_err ? rd_burst_diff[3:0] : 4'd0;

sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (SCAN_BMP_START),   // 跳过 FAT 区（省 ~1.5s）
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_HIT_LIMIT    (SCAN_HIT_LIMIT),   // 防呆：扫描硬上限
    .SCAN_TARGET_COUNT (SCAN_BMP_COUNT),
    .DISABLE_PRELOAD   (DISABLE_PRELOAD)  // 1 = 关闭预加载（即时加载模式）
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .key_next          (sd_key_next),    // 经过模式屏蔽的"下一张"
    .key_prev          (sd_key_prev),    // Step2：经过模式屏蔽的"上一张"
    .key_auto          (sd_key_auto),    // 经过模式屏蔽的"轮播开关"
    .state_code        (state_code),
    .scan_warn_o       (sd_scan_warn),   // 诊断
    .img_found_cnt_o   (sd_img_found_cnt),// 诊断

    .ctrl_diag_o        (sd_ctrl_diag),
    .auto_play_en_o    (sd_auto_play),
    .img_idx_o         (sd_img_idx),
    .bmp_width         (16'd1280),
    .bmp_height        (16'd720),
    .display_valid     (display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .prev_disp_idx     (prev_disp_idx),
    .transition_tgl    (transition_tgl),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),

    .sd_init_done           (sd_init_done      ),
    .sd_sec_read            (v_sd_sec_read     ),
    .sd_sec_read_addr       (v_sd_sec_read_addr),
    .sd_sec_read_data       (v_sd_sec_read_data),
    .sd_sec_read_data_valid (v_sd_sec_read_dv  ),
    .sd_sec_read_end        (v_sd_sec_read_end )
);

sd_card_mgr sd_card_mgr_m0 (
    .clk                    (sd_card_clk         ),
    .rst                    (rst_sd             ),

    .SD_nCS                 (sd_ncs              ),
    .SD_DCLK                (sd_dclk             ),
    .SD_MOSI                (sd_mosi             ),
    .SD_MISO                (sd_miso             ),
    .sd_init_done           (sd_init_done        ),

    .V_sec_read             (v_sd_sec_read       ),
    .V_sec_read_addr        (v_sd_sec_read_addr  ),
    .V_sec_read_data        (v_sd_sec_read_data  ),
    .V_sec_read_data_valid  (v_sd_sec_read_dv    ),
    .V_sec_read_end         (v_sd_sec_read_end   ),

    .A_sec_read             (a_mux_sec_read      ),
    .A_sec_read_addr        (a_mux_sec_addr      ),
    .A_sec_read_data        (a_sd_sec_read_data  ),
    .A_sec_read_data_valid  (a_sd_sec_read_dv    ),
    .A_sec_read_end         (a_sd_sec_read_end   )
);

always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        a_pause_sync <= 2'b00;
    else
        a_pause_sync <= {a_pause_sync[0], audio_pause_eff};
end

wire        txt_cue_we, txt_sch_we, txt_ln_we, txt_ach_we;
wire [5:0]  txt_cue_wa;
wire [5:0]  txt_ln_wa;
wire [9:0]  txt_sch_wa, txt_ach_wa;
wire [63:0] txt_cue_wd;
wire [7:0]  txt_sch_wd;
wire [15:0] txt_ln_wd;
wire [7:0]  txt_ach_wd;

wire        a_txt_sec_read;
wire [31:0] a_txt_sec_addr;

text_load text_load_m0 (
    .clk                (sd_card_clk        ),
    .rst                (rst_sd             ),
    .sd_init_done       (sd_init_done       ),

    .O_sec_read         (a_txt_sec_read     ),
    .O_sec_addr         (a_txt_sec_addr     ),
    .I_sec_data         (a_sd_sec_read_data ),
    .I_sec_data_valid   (a_sd_sec_read_dv   ),
    .I_sec_read_end     (a_sd_sec_read_end  ),

    .O_cue_we           (txt_cue_we         ),
    .O_cue_wa           (txt_cue_wa         ),
    .O_cue_wd           (txt_cue_wd         ),
    .O_sch_we           (txt_sch_we         ),
    .O_sch_wa           (txt_sch_wa         ),
    .O_sch_wd           (txt_sch_wd         ),
    .O_ln_we            (txt_ln_we          ),
    .O_ln_wa            (txt_ln_wa          ),
    .O_ln_wd            (txt_ln_wd          ),
    .O_ach_we           (txt_ach_we         ),
    .O_ach_wa           (txt_ach_wa         ),
    .O_ach_wd           (txt_ach_wd         ),

    .O_done             (a_txt_done         ),
    .O_found            (a_txt_found        )
);

wire a_owner_txt = ~a_txt_done;

assign a_mux_sec_read = a_owner_txt ? a_txt_sec_read : a_sd_sec_read;
assign a_mux_sec_addr = a_owner_txt ? a_txt_sec_addr : a_sd_sec_read_addr;

wire a_wav_scan_done;
wire a_wav_found_valid;
wire [31:0] a_wav_found_sector;
wire a_wav_ready;          // wav_read 空闲
wire a_wav_eof;

wire [3:0] a_wav_state_code;

wire       a_scan_start_pulse;
wire [31:0] a_scan_first, a_scan_limit;
wav_scan_control #(

    .PRIMARY_FIRST(SCAN_WAV_START),
    .PRIMARY_LAST(SCAN_WAV_START + WAV_SCAN_SPAN),

    .COMPAT_FIRST(32'd57728), .COMPAT_LAST(32'd57728 + WAV_SCAN_SPAN),
    .FALLBACK_FIRST(32'd8192), .FALLBACK_LAST(32'd131071)
) wav_scan_control_m0 (
    .clk(sd_card_clk), .rst(rst_sd), .sd_init_done(sd_init_done),

    .start_ok(a_txt_done),
    .scan_done(a_wav_scan_done), .scan_found_valid(a_wav_found_valid),
    .scan_start(a_scan_start_pulse), .scan_first(a_scan_first),
    .scan_limit(a_scan_limit)
);

reg        a_play_start_r;
reg        a_play_done;

wire       a_play_go = a_play_en & a_wav_scan_done & a_wav_found_valid &
                       (~a_play_done) & (~a_play_start_r);

always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        a_play_start_r <= 1'b0;
        a_play_done    <= 1'b0;
    end else begin
        if (a_play_start_r) begin
            a_play_start_r <= 1'b0;          // play_start 收窄为 1 拍
            a_play_done    <= 1'b1;          // 标记已启动（不再重发）
        end else if (a_play_go) begin
            a_play_start_r <= 1'b1;
        end
    end
end

wire a_play_start = a_play_start_r;

wav_read wav_read_m0 (
    .clk                    (sd_card_clk        ),
    .rst                    (rst_sd            ),
    .ready                  (a_wav_ready        ),

    .scan_start             (a_scan_start_pulse ),
    .scan_start_sector      (a_scan_first       ),
    .scan_max_sector        (32'd131071         ),

    .scan_hit_limit         (a_scan_limit       ),
    .scan_done              (a_wav_scan_done    ),
    .scan_found_valid       (a_wav_found_valid  ),
    .scan_found_sector      (a_wav_found_sector ),

    .play_start             (a_play_start       ),
    .loop_en                (1'b1               ),
    .eof                    (a_wav_eof          ),

    .sd_init_done           (sd_init_done       ),
    .state_code             (a_wav_state_code   ),   // 接出来显示到数码管位4

    .sd_sec_read            (a_sd_sec_read      ),
    .sd_sec_read_addr       (a_sd_sec_read_addr ),
    .sd_sec_read_data       (a_sd_sec_read_data ),
    .sd_sec_read_data_valid (a_sd_sec_read_dv   ),
    .sd_sec_read_end        (a_sd_sec_read_end  ),

    .fifo_almost_full       (a_fifo_almost_full ),

    .pcm_wr_en              (a_pcm_wr_en        ),
    .pcm_lr                 (a_pcm_lr           ),

    .o_sample_rate          (                   ),
    .o_channels             (                   ),
    .o_bits                 (                   ),
    .o_data_size            (                   ),
    .o_data_offset          (                   )
);

afifo_48_1024 afifo_audio_m0 (
    .wr_clk                 (sd_card_clk        ),
    .wr_rst                 (rst_sd            ),
    .wr_en                  (a_pcm_wr_en        ),
    .wr_data                (a_pcm_lr           ),

    .rd_clk                 (video_clk          ),
    .rd_rst                 (rst_pixel            ),
    .rd_en                  (a_fifo_rd_en       ),
    .rd_data                (a_fifo_rd_data     ),

    .full                   (a_fifo_full        ),
    .empty                  (a_fifo_empty       ),
    .wr_used                (a_fifo_wr_used     )
);

reg  [1:0] pause_vid_sync;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel)
        pause_vid_sync <= 2'b00;
    else
        pause_vid_sync <= {pause_vid_sync[0], audio_pause_eff};
end

audio_stream_gen #(
    .CLK_FREQ_HZ    (75_000_000),
    .SAMPLE_RATE_HZ (48_000)
) audio_stream_gen_m0 (
    .I_clk                (video_clk         ),
    .I_rst                (rst_pixel           ),

    .I_fifo_empty         (a_fifo_empty      ),
    .I_fifo_dout          (a_fifo_rd_data    ),
    .O_fifo_rd_en         (a_fifo_rd_en      ),

    .O_audio_valid        (audio_valid       ),
    .O_audio_left_data    (audio_left_data   ),
    .O_audio_right_data   (audio_right_data  ),

    .I_mute               (pause_vid_sync[1]), // sw[3] 真暂停（冻结时间轴）
    .O_underrun           (a_underrun        ),
    .O_sample_cnt         (a_sample_cnt      )
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

localparam [23:0] AUDIO_TOTAL_FRAME = 24'd14453;

// 'u' = 有数据后发生过欠载

reg        aud_err_latch;      // 欠载粘滞
reg        aud_seen_data;
reg        aud_starved;

reg a_wav_found_lvl;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)            a_wav_found_lvl <= 1'b0;
    else if (a_wav_found_valid) a_wav_found_lvl <= 1'b1;
end

reg a_wav_found_c1, a_wav_found_c2;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        a_wav_found_c1 <= 1'b0;
        a_wav_found_c2 <= 1'b0;
    end else begin
        a_wav_found_c1 <= a_wav_found_lvl;
        a_wav_found_c2 <= a_wav_found_c1;
    end
end

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        aud_err_latch <= 1'b0;
        aud_seen_data <= 1'b0;
        aud_starved   <= 1'b0;
    end else begin
        if (!a_fifo_empty)
            aud_seen_data <= 1'b1;          // 见到数据了

        if (a_underrun && aud_seen_data)
            aud_err_latch <= 1'b1;

        if (a_fifo_empty && aud_seen_data)
            aud_starved   <= 1'b1;          // 有过后又空 断粮
    end
end

reg [2:0] aud_stat_v;

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel)
        aud_stat_v <= 3'd0;
    else
        aud_stat_v <= (~a_wav_found_c2) ? 3'd4 :      // 没找到 WAV
                      aud_err_latch     ? 3'd3 :
                      aud_starved       ? 3'd2 :
                      aud_seen_data     ? 3'd1 : 3'd0;
end

reg [2:0] aud_stat_c1, aud_stat_c2;

reg [3:0] a_wav_state_code_c1, a_wav_state_code_c2;

reg [3:0] v_state_code_c1, v_state_code_c2;

reg [3:0] dbg_flags_c1, dbg_flags_c2;

reg [4:0] v_load_cnt;
always @(posedge clk) begin
    if (v_state_code_c2 == 4'd4 && v_state_code_c1 != 4'd4)
        v_load_cnt <= v_load_cnt + 5'd1;       // 上升沿（进入 ST_LOAD_DATA）

end

reg dbg_u_empty;     // bit0：稳态扫描期间 FIFO 空（读侧欠载）
reg dbg_u_wrbusy;    // bit1：欠载时写侧正忙（ 写抢占读）
reg dbg_u_nonfirst;  // bit2：行内停顿（行已开始才空）
reg dbg_de_d;        // de 延时一拍（判"行内"用）
reg [1:0] dbg_row_cnt;   // 本帧已过的行数（饱和到 2）

reg dbg_wrbusy_v1, dbg_wrbusy_v2;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        dbg_wrbusy_v1 <= 1'b0;
        dbg_wrbusy_v2 <= 1'b0;
    end else begin
        dbg_wrbusy_v1 <= App_wr_busy;
        dbg_wrbusy_v2 <= dbg_wrbusy_v1;
    end
end

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        dbg_u_empty    <= 1'b0;
        dbg_u_wrbusy   <= 1'b0;
        dbg_u_nonfirst <= 1'b0;
        dbg_de_d       <= 1'b0;
        dbg_row_cnt    <= 2'd0;
    end else begin
        dbg_de_d <= de;

        if (!vs)
            dbg_row_cnt <= 2'd0;
        else if (de && !dbg_de_d && dbg_row_cnt != 2'd2)
            dbg_row_cnt <= dbg_row_cnt + 2'd1;

        if (de && dbg_row_cnt == 2'd2) begin
            if (rd_fifo_empty) begin
                dbg_u_empty <= 1'b1;
                if (dbg_wrbusy_v2) dbg_u_wrbusy <= 1'b1;

                if (dbg_de_d)
                    dbg_u_nonfirst <= 1'b1;
            end
        end
    end
end

wire [3:0] dbg_fifo_flags = {1'b0, dbg_u_nonfirst, dbg_u_wrbusy, dbg_u_empty};

reg [3:0] dbg_fifo_c1, dbg_fifo_c2;
always @(posedge clk) begin
    dbg_fifo_c1 <= dbg_fifo_flags;
    dbg_fifo_c2 <= dbg_fifo_c1;
end

wire [2:0]  mode_num;       // 0..7
wire [7:0]  mode_oh;        // one-hot {P8,...,P1}

mode_decode mode_decode_m0 (
    .I_clk          (clk),
    .I_rst_n        (rst_ref_n),
    .I_sw           (sw),
    .O_mode_num     (mode_num),
    .O_mode_oh      (mode_oh),
    .O_audio_pause  (audio_pause)
);

wire img_ctrl_off = (mode_num != 3'd1) && (mode_num != 3'd7);   // clk 域：P2 或 P8 允许切图

reg img_ctrl_off_sd1, img_ctrl_off_sd2;      // 同步到 sd_card_clk 域
always @(posedge sd_card_clk) begin
    img_ctrl_off_sd1 <= img_ctrl_off;
    img_ctrl_off_sd2 <= img_ctrl_off_sd1;
end

wire [2:0]  key_short;      // {key_r, key_m, key_l}
wire        key_long_start;
wire [2:0]  key_repeat;
wire [2:0]  key_held;

key_ctrl key_ctrl_m0 (
    .I_clk          (clk),
    .I_rst_n        (rst_ref_n),
    .I_key_l        (key_l),
    .I_key_m        (key_m),
    .I_key_r        (key_r),
    .O_short        (key_short),
    .O_long_start   (key_long_start),
    .O_repeat       (key_repeat),
    .O_held         (key_held)
);

// 串口链路信号
wire [7:0]  u_rx_data;
wire        u_rx_valid;
wire [7:0]  u_tx_data;
wire        u_tx_start;
wire        u_tx_busy;
wire        u_tx_pin;
wire [7:0]  u_rx_cnt;
wire [7:0]  u_tx_cnt;

wire        u_wr;                 // param_reg
wire [3:0]  u_wr_sel;
wire [7:0]  u_wr_val;
wire        u_rset;
wire        u_p5_wr, u_p6_wr, u_p7_wr;     // p5_reg / p6_reg / p7_reg
wire [2:0]  u_p5_sel;
wire [1:0]  u_p5_val, u_p6_sel, u_p6_val, u_p7_sel, u_p7_val;
wire        u_pause_set, u_pause_clr;
wire        u_next_pulse, u_prev_pulse, u_auto_set;
wire        u_auto_val;

wire t_valid,t_ready,t_base_wr,t_sub_wr,t_ad_wr,t_spectrum_wr,t_play_wr;
wire [2:0] t_target;
wire [3:0] t_field;
wire [7:0] t_value;

wire uart_next_lvl, uart_prev_lvl, uart_auto_lvl;
wire t_uart_busy=u_rset || u_wr || u_p5_wr || u_p6_wr || u_p7_wr ||
    u_pause_set || u_pause_clr || u_next_pulse || u_prev_pulse || u_auto_set;
reg [21:0] t_play_gap;
always @(posedge clk or negedge rst_ref_n) begin
    if(!rst_ref_n) t_play_gap<=0;
    else if(t_play_wr || u_next_pulse || u_prev_pulse || u_auto_set || |key_held)
        t_play_gap<=22'd3000000;
    else if(t_play_gap!=0) t_play_gap<=t_play_gap-1'b1;
end
touch_control_bus touch_arbiter(.enabled(mode_oh[7]),.uart_busy(t_uart_busy),
    .playback_ready(t_play_gap==0 && !uart_next_lvl && !uart_prev_lvl && !uart_auto_lvl),
    .valid(t_valid),.target(t_target),.ready(t_ready),.base_wr(t_base_wr),
    .sub_wr(t_sub_wr),.ad_wr(t_ad_wr),.spectrum_wr(t_spectrum_wr),.play_wr(t_play_wr));
wire [199:0] t_values;

assign t_values={{audio_pause_eff,aud_stat_c2,a_wav_state_code_c2},8'd0,{7'd0,p7_horizontal},{7'd0,p7_wave_on},
    8'd0,8'd0,{6'd0,p6_ad_bg},{7'd0,p6_ad_on},{6'd0,p6_logo_sel},
    {7'd0,p5_monitor},{7'd0,p5_size},{6'd0,p5_bg},{6'd0,p5_pos},{6'd0,p5_mode},
    {7'd0,p5_sub_on},{7'd0,p_tran_en},{5'd0,p_tran_type},
    {7'd0,audio_pause_eff},{7'd0,sd_auto_play_c2},8'd0,8'd0,p_vol,p_sat,p_con,p_bri};
touch_panel touch_panel_m0(
    .clk(clk),.rst_n(rst_ref_n),.enabled(mode_oh[7]),.values(t_values),
    .mode(mode_num),
    .valid(t_valid),.ready(t_ready),.target(t_target),.field(t_field),.value(t_value),
    .tft_cs_n(tft_cs_n),.tft_reset_n(tft_reset_n),.tft_dc(tft_dc),.tft_mosi(tft_mosi),.tft_sck(tft_sck),
    .touch_cs_n(touch_cs_n),.touch_mosi(touch_mosi),.touch_sck(touch_sck),
    .touch_miso(touch_miso),.touch_irq_n(touch_irq_n));

wire [1:0]  u_sd_state;           // STAT 的 ST 字段

localparam [20:0] UART_STRETCH = 21'd1_500_000;

reg [20:0] ustr_next_cnt, ustr_prev_cnt, ustr_auto_cnt;
assign uart_next_lvl = (ustr_next_cnt != 21'd0);
assign uart_prev_lvl = (ustr_prev_cnt != 21'd0);
assign uart_auto_lvl = (ustr_auto_cnt != 21'd0);

always @(posedge clk or negedge rst_ref_n) begin
    if (!rst_ref_n) begin
        ustr_next_cnt <= 21'd0;
        ustr_prev_cnt <= 21'd0;
        ustr_auto_cnt <= 21'd0;
    end
    else begin
        if (u_next_pulse || (t_play_wr && t_field==4'd1))                         ustr_next_cnt <= UART_STRETCH;
        else if (ustr_next_cnt != 21'd0)          ustr_next_cnt <= ustr_next_cnt - 21'd1;

        if (u_prev_pulse || (t_play_wr && t_field==4'd0))                         ustr_prev_cnt <= UART_STRETCH;
        else if (ustr_prev_cnt != 21'd0)          ustr_prev_cnt <= ustr_prev_cnt - 21'd1;

        if (u_auto_set || (t_play_wr && t_field==4'd2 && t_value[0]!=sd_auto_play_c2))                           ustr_auto_cnt <= UART_STRETCH;
        else if (ustr_auto_cnt != 21'd0)          ustr_auto_cnt <= ustr_auto_cnt - 21'd1;
    end
end

reg u_next_sd1, u_next_sd2;
reg u_prev_sd1, u_prev_sd2;
reg u_auto_sd1, u_auto_sd2;
always @(posedge sd_card_clk) begin
    u_next_sd1 <= uart_next_lvl;
    u_next_sd2 <= u_next_sd1;
    u_prev_sd1 <= uart_prev_lvl;
    u_prev_sd2 <= u_prev_sd1;
    u_auto_sd1 <= uart_auto_lvl;
    u_auto_sd2 <= u_auto_sd1;
end

reg [2:0] key_held_sd1, key_held_sd2;
always @(posedge sd_card_clk) begin
    key_held_sd1 <= key_held;
    key_held_sd2 <= key_held_sd1;
end

assign sd_key_next = img_ctrl_off_sd2 ? 1'b1 : (~key_held_sd2[2] & ~u_next_sd2);  // key_r
assign sd_key_prev = img_ctrl_off_sd2 ? 1'b1 : (~key_held_sd2[0] & ~u_prev_sd2);  // key_l
assign sd_key_auto = img_ctrl_off_sd2 ? 1'b1 : (~key_held_sd2[1] & ~u_auto_sd2);  // key_m

wire [7:0]  p_bri, p_con, p_sat, p_vol;
wire [2:0]  p_rot;
wire [2:0]  p_item;
wire [15:0] p_val;

wire [2:0]  p_tran_type;
wire        p_tran_en;
wire        act_next_img, act_prev_img, act_auto_toggle;

param_reg param_reg_m0 (
    .I_clk          (clk),
    .I_rst_n        (rst_ref_n),
    .I_key_short    (key_short),
    .I_key_repeat   (key_repeat),
    .I_mode_oh      (mode_oh),
    .O_next_img     (act_next_img),
    .O_prev_img     (act_prev_img),
    .O_auto_toggle  (act_auto_toggle),
    .O_bri          (p_bri),
    .O_con          (p_con),
    .O_sat          (p_sat),
    .O_vol          (p_vol),
    .O_rot          (p_rot),
    .O_tran_type    (p_tran_type),     // 转场类型
    .O_tran_en      (p_tran_en),       // 转场开关
    .O_param_item   (p_item),
    .O_param_val    (p_val),
    .I_u_wr         (u_wr | t_base_wr),
    .I_u_sel        (u_wr ? u_wr_sel : t_field[3:0]),
    .I_u_val        (u_wr ? u_wr_val : t_value),
    .I_u_rset       (u_rset)
);

wire p7_wave_on;
wire p7_item, p7_horizontal;
p7_reg p7_reg_m0 (
    .I_clk(clk), .I_rst_n(rst_ref_n), .I_key_short(key_short),
    .I_mode_oh(mode_oh), .O_wave_on(p7_wave_on),
    .O_item(p7_item), .O_horizontal(p7_horizontal),

    .I_u_wr(u_p7_wr | t_spectrum_wr), .I_u_sel(u_p7_wr ? u_p7_sel : t_field[1:0]), .I_u_val(u_p7_wr ? u_p7_val : t_value[1:0]),
    .I_u_rst(u_rset)
);
wire p7_wave_en = ~mode_oh[0] & p7_wave_on;
reg [1:0] p7_en_sync;
reg [3:0] p7_ui_meta,p7_ui_sync;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) p7_en_sync <= 2'b00;
    else p7_en_sync <= {p7_en_sync[0], p7_wave_en};
end
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin p7_ui_meta<=4'b0010; p7_ui_sync<=4'b0010; end
    else begin
        p7_ui_meta<={mode_oh[6],p7_item,p7_wave_on,p7_horizontal};
        p7_ui_sync<=p7_ui_meta;
    end
end

wire [2:0] p5_item;
wire       p5_sub_on, p5_size, p5_monitor, p5_changed;
wire [1:0] p5_mode, p5_pos, p5_bg;

p5_reg p5_reg_m0 (
    .I_clk        (clk),
    .I_rst_n      (rst_ref_n),
    .I_key_short  (key_short),
    .I_key_repeat (key_repeat),
    .I_mode_oh    (mode_oh),
    .O_item       (p5_item),
    .O_sub_on     (p5_sub_on),
    .O_mode       (p5_mode),
    .O_pos        (p5_pos),
    .O_bg         (p5_bg),
    .O_size       (p5_size),
    .O_monitor    (p5_monitor),
    .O_changed    (p5_changed),
    .I_u_wr       (u_p5_wr | t_sub_wr),
    .I_u_sel      (u_p5_wr ? u_p5_sel : t_field[2:0]),
    .I_u_val      (u_p5_wr ? u_p5_val : t_value[1:0]),
    .I_u_rst      (u_rset)
);

// key_m 切换当前项的状态

wire [1:0] p6_item, p6_logo_sel, p6_logo_mode, p6_ad_bg;
wire       p6_logo_en, p6_ad_on;

p6_reg p6_reg_m0 (
    .I_clk        (clk),
    .I_rst_n      (rst_ref_n),
    .I_key_short  (key_short),
    .I_key_repeat (key_repeat),
    .I_mode_oh    (mode_oh),
    .O_item       (p6_item),
    .O_logo_sel   (p6_logo_sel),
    .O_ad_on      (p6_ad_on),
    .O_ad_bg      (p6_ad_bg),
    .O_logo_en    (p6_logo_en),
    .O_logo_mode  (p6_logo_mode),
    .O_changed    (              ),    // 未使用（数码管不显示 P6 状态）
    .I_u_wr       (u_p6_wr | t_ad_wr),
    .I_u_sel      (u_p6_wr ? u_p6_sel : t_field[1:0]),
    .I_u_val      (u_p6_wr ? u_p6_val : t_value[1:0]),
    .I_u_rst      (u_rset)
);

wire [7:0]  st_seg_5, st_seg_4, st_seg_3, st_seg_2, st_seg_1, st_seg_0;

reg        sd_auto_play_c1, sd_auto_play_c2;
reg [4:0]  sd_img_idx_c1,   sd_img_idx_c2;      // 5 位（1..16）

reg        sd_scan_warn_c1, sd_scan_warn_c2;
reg [4:0]  sd_img_found_c1, sd_img_found_c2;

reg [2:0]  sd_ctrl_diag_c1, sd_ctrl_diag_c2;

always @(posedge clk) begin
    sd_auto_play_c1 <= sd_auto_play;
    sd_auto_play_c2 <= sd_auto_play_c1;

    sd_img_idx_c1   <= sd_img_idx;
    sd_img_idx_c2   <= sd_img_idx_c1;

    sd_ctrl_diag_c1 <= sd_ctrl_diag;
    sd_ctrl_diag_c2 <= sd_ctrl_diag_c1;

    sd_scan_warn_c1 <= sd_scan_warn;
    sd_scan_warn_c2 <= sd_scan_warn_c1;

    sd_img_found_c1 <= sd_img_found_cnt;
    sd_img_found_c2 <= sd_img_found_c1;

    aud_stat_c1     <= aud_stat_v;         // 音频诊断（video_clk clk）
    aud_stat_c2     <= aud_stat_c1;

    a_wav_state_code_c1 <= a_wav_state_code;
    a_wav_state_code_c2 <= a_wav_state_code_c1;

    v_state_code_c1     <= state_code;
    v_state_code_c2     <= v_state_code_c1;

    dbg_flags_c1        <= dbg_sdram_flags;    // SDRAM 冲突位（ext_mem_clk clk）
    dbg_flags_c2        <= dbg_flags_c1;
end

assign u_sd_state = (sd_img_found_c2 == 5'd0)
                    ? ((v_state_code_c2 == 4'd1) ? 2'd3 : 2'd2)
                    : ((sd_img_idx_c2  == 5'd0)  ? 2'd1 : 2'd0);

wire [1:0] uart_sub_mode = p5_sub_on ? (p5_mode + 2'd1) : 2'd0;

uart_rx u_uart_rx (
    .I_clk      (clk),
    .I_rst_n    (rst_ref_n),
    .I_rx       (uart_rx),
    .O_data     (u_rx_data),
    .O_valid    (u_rx_valid)
);

uart_tx u_uart_tx (
    .I_clk      (clk),
    .I_rst_n    (rst_ref_n),
    .I_data     (u_tx_data),
    .I_start    (u_tx_start),
    .O_tx       (u_tx_pin),
    .O_busy     (u_tx_busy)
);

assign uart_tx = u_tx_pin;

uart_cmd u_uart_cmd (
    .I_clk          (clk),
    .I_rst_n        (rst_ref_n),
    .I_rx_data      (u_rx_data),
    .I_rx_valid     (u_rx_valid),
    .O_rx_cnt       (u_rx_cnt),
    .O_tx_data      (u_tx_data),
    .O_tx_start     (u_tx_start),
    .I_tx_busy      (u_tx_busy),
    .O_tx_cnt       (u_tx_cnt),
    .I_mode_num     (mode_num),
    .I_bri          (p_bri),
    .I_con          (p_con),
    .I_sat          (p_sat),
    .I_vol          (p_vol),
    .I_tran_type    (p_tran_type),
    .I_tran_en      (p_tran_en),
    .I_img_idx      (sd_img_idx_c2),
    .I_img_total    (sd_img_found_c2),
    .I_auto_on      (sd_auto_play_c2),
    .I_sub_mode     (uart_sub_mode),
    .I_sd_state     (u_sd_state),
    .O_wr           (u_wr),
    .O_wr_sel       (u_wr_sel),
    .O_wr_val       (u_wr_val),
    .O_rset         (u_rset),
    .O_p5_wr        (u_p5_wr),
    .O_p5_sel       (u_p5_sel),
    .O_p5_val       (u_p5_val),
    .O_p6_wr        (u_p6_wr),
    .O_p6_sel       (u_p6_sel),
    .O_p6_val       (u_p6_val),
    .O_p7_wr        (u_p7_wr),
    .O_p7_sel       (u_p7_sel),
    .O_p7_val       (u_p7_val),
    .O_pause_set    (u_pause_set),
    .O_pause_clr    (u_pause_clr),
    .O_next_pulse   (u_next_pulse),
    .O_prev_pulse   (u_prev_pulse),
    .O_auto_set     (u_auto_set),
    .O_auto_val     (u_auto_val)
);

always @(posedge clk or negedge rst_ref_n) begin
    if (!rst_ref_n)           uart_pause_lvl <= 1'b0;
    else if (u_pause_set) uart_pause_lvl <= 1'b1;
    else if (u_pause_clr) uart_pause_lvl <= 1'b0;
    else if(t_play_wr && t_field==4'd3) uart_pause_lvl<=t_value[0];
end

seg_status seg_status_m0 (
    .I_clk          (clk),
    .I_rst_n        (rst_ref_n),
    .I_mode_num     (mode_num),
    .I_param_item   (p_item),
    .I_param_val    (p_val),
    .I_tran_type    (p_tran_type),     // P3 转场序号显示（clk 域，同域无需同步）
    .I_tran_en      (p_tran_en),       // P3 转场开关显示
    .I_auto_on      (sd_auto_play_c2),     // 已同步到 clk 域
    .I_img_idx      (sd_img_idx_c2),       // 已同步到 clk 域
    .I_sd_warn      (sd_scan_warn_c2),     // SD 诊断（已同步）
    .I_sd_found     (sd_img_found_c2),     // SD 诊断（已同步）

    .I_ctrl_diag    (sd_ctrl_diag_c2),     // 已同步到 clk 域
    .I_aud_stat     (aud_stat_c2),         // 音频诊断（已同步到 clk 域）
    .I_aud_mute     (audio_pause),         // 静音开关 sw[3]（同 clk 域，无需同步）
    .I_fsm_sel      (DEBUG_FSM_SEL),
    .I_aud_fsm      (a_wav_state_code_c2), // wav_read 状态机号（已同步）
    .I_vid_fsm      (v_state_code_c2),     // bmp_read 状态机号（已同步）
    .I_load_cnt     (v_load_cnt[3:0]),     // 累计加载次数低 4 位
    .I_sdram_flags  (dbg_flags_c2),        // SDRAM 冲突锁存位
    .I_fifo_flags   (dbg_fifo_c2),
    .I_wr_diag      (dbg_wr_diag),

    .I_uart_rx_cnt  (u_rx_cnt),
    .I_uart_tx_cnt  (u_tx_cnt),
    .O_seg_5        (st_seg_5),
    .O_seg_4        (st_seg_4),
    .O_seg_3        (st_seg_3),
    .O_seg_2        (st_seg_2),
    .O_seg_1        (st_seg_1),
    .O_seg_0        (st_seg_0)
);

wire [3:0] diag_locks,diag_clocks,diag_status,diag_video;
wire [6:0] diag_l_seg,diag_h_seg,diag_r_seg,diag_v_seg;
clock_reset_diagnostics u_reset_diagnostics(
 .ref_clk(clk),.sd_clk(sd_card_clk),.mem_clk(ext_mem_clk),.pixel_clk(video_clk),
 .raw_rst_n(rst_n),.sys_locked(diag_sys_lock),.video_locked(diag_video_lock),
 .sd_ready(sd_init_done),.mem_ready(Sdr_init_done),.display_ready(display_valid),
 .video_state(state_code),.locks(diag_locks),.clocks(diag_clocks),
 .status(diag_status),.video(diag_video));
seg_decoder diag_l(.bin_data(diag_locks),.seg_data(diag_l_seg));
seg_decoder diag_h(.bin_data(diag_clocks),.seg_data(diag_h_seg));
seg_decoder diag_r(.bin_data(diag_status),.seg_data(diag_r_seg));
seg_decoder diag_v(.bin_data(diag_video),.seg_data(diag_v_seg));
wire diag_mode=mode_num==3'd7;
seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_ref_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),

    .seg_data_0        (diag_mode ? 8'hA1 : st_seg_5),   // 最左 模式号
    .seg_data_1        (diag_mode ? 8'h80 : st_seg_4),   // 空白
    .seg_data_2        (diag_mode ? {1'b1,diag_l_seg} : st_seg_3),   // 细分
    .seg_data_3        (diag_mode ? {1'b1,diag_h_seg} : st_seg_2),   // 空白
    .seg_data_4        (diag_mode ? {1'b1,diag_r_seg} : st_seg_1),   // 值
    .seg_data_5        (diag_mode ? {1'b1,diag_v_seg} : st_seg_0)    // 最右 空白
);

video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_pixel),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

reg [2:0] tt_c1, tt_c2;
reg       te_c1, te_c2;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin tt_c1<=3'd0; tt_c2<=3'd0; te_c1<=1'b0; te_c2<=1'b0; end
    else begin
        tt_c1 <= p_tran_type; tt_c2 <= tt_c1;
        te_c1 <= p_tran_en;   te_c2 <= te_c1;
    end
end

reg tgl_v1, tgl_v2, tgl_v3;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin tgl_v1<=1'b0; tgl_v2<=1'b0; tgl_v3<=1'b0; end
    else begin tgl_v1 <= transition_tgl; tgl_v2 <= tgl_v1; tgl_v3 <= tgl_v2; end
end
wire tran_start_v = tgl_v2 ^ tgl_v3;   // 单拍脉冲

transition_gen transition_gen_m0(
    .I_clk          (video_clk),
    .I_rst          (rst_pixel),
    .I_hs           (hs_0),
    .I_vs           (vs_0),
    .I_de           (de_0),
    .I_rd_a         (video_read_data),      // A 通道 = 当前显示槽（新图）
    .I_empty_a      (rd_fifo_empty),
    .I_rd_b         (video_read_data_b),    // B 通道 = 上一显示槽（旧图）
    .I_empty_b      (rd_fifo_empty_b),
    .I_tran_type    (tt_c2),
    .I_tran_en      (te_c2),
    .I_tran_start   (tran_start_v),
    .O_read_en      (video_read_en),        // 驱动两个读 FIFO
    .O_de           (de),
    .O_hs           (hs),
    .O_vs           (vs),
    .O_rgb          (vout_data_raw)
);

reg [7:0] pb_c1, pb_c2;      // bri 同步（clk video_clk）
reg [7:0] pc_c1, pc_c2;      // con 同步
reg [7:0] ps_c1, ps_c2;      // sat 同步

always @(posedge video_clk) begin
    pb_c1 <= p_bri;   pb_c2 <= pb_c1;
    pc_c1 <= p_con;   pc_c2 <= pc_c1;
    ps_c1 <= p_sat;   ps_c2 <= ps_c1;
end

wire [23:0] vout_effected;
wire        de_eff, hs_eff, vs_eff;      // 效果层输出的延迟 6 拍后时序

param_effect param_effect_m0 (
    .I_clk          (video_clk),
    .I_rst          (rst_pixel),
    .I_de           (de),                // 来自 video_delay
    .I_hs           (hs),
    .I_vs           (vs),
    .I_rgb          (vout_data_raw),     // 来自 video_delay（已 565 解包）
    .I_bri          (pb_c2),             // 已同步到 video_clk 域
    .I_con          (pc_c2),
    .I_sat          (ps_c2),
    .O_de           (de_eff),            // 延迟 6 拍后的 de
    .O_hs           (hs_eff),
    .O_vs           (vs_eff),
    .O_rgb          (vout_effected)
);

wire [23:0] wave_rgb;
wire wave_de, wave_hs, wave_vs;
audio_spectrum_overlay audio_wave_overlay_m0 (
    .I_clk(video_clk), .I_rst(rst_pixel),
    .I_sample_valid(volume_valid), .I_sample_left(volume_left),
    .I_en(p7_en_sync[1]),
    .I_horizontal(p7_ui_sync[0]),
    .O_debug_active(), .O_debug_bank(),
    .I_de(de_eff), .I_hs(hs_eff), .I_vs(vs_eff), .I_rgb(vout_effected),
    .O_de(wave_de), .O_hs(wave_hs), .O_vs(wave_vs), .O_rgb(wave_rgb)
);

reg        p5_on_c1,  p5_on_c2;
reg        p5_sz_c1,  p5_sz_c2;
reg        p5_mo_c1,  p5_mo_c2;
reg [1:0]  p5_md_c1,  p5_md_c2;
reg [1:0]  p5_ps_c1,  p5_ps_c2;
reg [1:0]  p5_bg_c1,  p5_bg_c2;
reg [2:0]  p5_it_c1,  p5_it_c2;

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        p5_on_c1 <= 1'b1; p5_on_c2 <= 1'b1;      // 默认字幕开（与 p5_reg 一致）
        p5_sz_c1 <= 1'b0; p5_sz_c2 <= 1'b0;
        p5_mo_c1 <= 1'b0; p5_mo_c2 <= 1'b0;
        p5_md_c1 <= 2'd0; p5_md_c2 <= 2'd0;
        p5_ps_c1 <= 2'd0; p5_ps_c2 <= 2'd0;
        p5_bg_c1 <= 2'd1; p5_bg_c2 <= 2'd1;      // 默认半透黑
        p5_it_c1 <= 3'd0; p5_it_c2 <= 3'd0;
    end else begin
        p5_on_c1 <= p5_sub_on;   p5_on_c2 <= p5_on_c1;
        p5_sz_c1 <= p5_size;     p5_sz_c2 <= p5_sz_c1;
        p5_mo_c1 <= p5_monitor;  p5_mo_c2 <= p5_mo_c1;
        p5_md_c1 <= p5_mode;     p5_md_c2 <= p5_md_c1;
        p5_ps_c1 <= p5_pos;      p5_ps_c2 <= p5_ps_c1;
        p5_bg_c1 <= p5_bg;       p5_bg_c2 <= p5_bg_c1;
        p5_it_c1 <= p5_item;     p5_it_c2 <= p5_it_c1;
    end
end

wire p5_en_c = (mode_num == 3'd4);
reg  p5_en_c1, p5_en_c2;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        p5_en_c1 <= 1'b0; p5_en_c2 <= 1'b0;
    end else begin
        p5_en_c1 <= p5_en_c; p5_en_c2 <= p5_en_c1;
    end
end

reg        mon_undr_c1, mon_undr_c2;
reg [3:0]  mon_afsm_c1, mon_afsm_c2;
reg [3:0]  mon_vfsm_c1, mon_vfsm_c2;
reg [2:0]  mon_mode_c1, mon_mode_c2;
reg [4:0]  mon_img_c1,  mon_img_c2;

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        mon_undr_c1 <= 1'b0; mon_undr_c2 <= 1'b0;
        mon_afsm_c1 <= 4'd0; mon_afsm_c2 <= 4'd0;
        mon_vfsm_c1 <= 4'd0; mon_vfsm_c2 <= 4'd0;
        mon_mode_c1 <= 3'd0; mon_mode_c2 <= 3'd0;
        mon_img_c1  <= 5'd0; mon_img_c2  <= 5'd0;
    end else begin
        mon_undr_c1 <= a_underrun;
        mon_undr_c2 <= mon_undr_c1;
        mon_afsm_c1 <= a_wav_state_code_c2;     // wav_read FSM 号（已在 clk 域）
        mon_afsm_c2 <= mon_afsm_c1;
        mon_vfsm_c1 <= v_state_code_c2;         // bmp_read FSM 号（已在 clk 域）
        mon_vfsm_c2 <= mon_vfsm_c1;
        mon_mode_c1 <= mode_num;                // clk 域模式号
        mon_mode_c2 <= mon_mode_c1;
        mon_img_c1  <= sd_img_idx_c2[4:0];      // 图片序号（已在 clk 域）
        mon_img_c2  <= mon_img_c1;
    end
end

// 字幕 ROM 接口
wire [9:0]  sub_cue_idx;
wire [23:0] sub_cue_frame, sub_cue_dur;
wire [15:0] sub_cue_coff, sub_cue_len, sub_char_addr;
wire [7:0]  sub_char_code;
wire [7:0]  sub_font_code;
wire [3:0]  sub_font_row;
wire [15:0] sub_font_word;
wire [23:0] sub_frame_now;      // 给 sync_monitor 的帧号（同一个帧基）

subtitle_rom u_subtitle_rom (
    .clk        (video_clk),
    .cue_idx    (sub_cue_idx),
    .cue_frame  (sub_cue_frame),
    .cue_coff   (sub_cue_coff),
    .cue_len    (sub_cue_len),
    .cue_dur    (sub_cue_dur),   // 已引出；引擎消费见 subtitle_engine

    .I_wr_clk   (sd_card_clk),
    .I_wr_en    (txt_cue_we),
    .I_wr_addr  (txt_cue_wa),
    .I_wr_data  (txt_cue_wd)
);

subtitle_char_rom u_subtitle_char_rom (
    .clk        (video_clk),
    .char_addr  (sub_char_addr),
    .char_code  (sub_char_code),
    .I_wr_clk   (sd_card_clk),
    .I_wr_en    (txt_sch_we),
    .I_wr_addr  (txt_sch_wa),
    .I_wr_data  (txt_sch_wd)
);

sub_font_rom u_sub_font (
    .clk       (video_clk),
    .char_code (sub_font_code),
    .row       (sub_font_row),
    .rom_row   (sub_font_word)
);

wire [23:0] sub_rgb;
wire        sub_de, sub_hs, sub_vs;
subtitle_engine subtitle_engine_m0 (
    .I_clk        (video_clk),
    .I_rst        (rst_pixel),
    .I_de         (wave_de),
    .I_hs         (wave_hs),
    .I_vs         (wave_vs),
    .I_rgb        (wave_rgb),
    .I_sample_cnt (a_sample_cnt),        // video_clk 域，32 位，无需 CDC
    .I_sub_on     (p5_on_c2),
    .I_mode       (p5_md_c2),
    .I_pos        (p5_ps_c2),
    .I_bg         (p5_bg_c2),
    .I_size       (p5_sz_c2),
    .I_preview    (p5_en_c2),            // P5 模式下强制预览（便于调设置）

    .I_loop_pulse (1'b0),
    .I_loop_frame (AUDIO_TOTAL_FRAME),
    .O_cue_idx    (sub_cue_idx),
    .I_cue_frame  (sub_cue_frame),
    .I_cue_coff   (sub_cue_coff),
    .I_cue_len    (sub_cue_len),
    .O_char_addr  (sub_char_addr),
    .I_char_code  (sub_char_code),
    .O_font_code  (sub_font_code),
    .O_font_row   (sub_font_row),
    .I_font_row   (sub_font_word),
    .O_frame_now  (sub_frame_now),        // 监视器用（同一个帧基）
    .O_de         (sub_de),
    .O_hs         (sub_hs),
    .O_vs         (sub_vs),
    .O_rgb        (sub_rgb)
);

reg [1:0] p6_lm_c1, p6_lm_c2;      // 弹移/静止
reg [1:0] p6_it_c1, p6_it_c2;      // 设置项（面板用）
reg [1:0] p6_ls_c1, p6_ls_c2;      // 标志状态（面板显示 关/开/动）
reg       p6_ad_c1, p6_ad_c2;      // 广告开关（面板显示 + 广告文字总开关）
reg [1:0] p6_bg_c1, p6_bg_c2;      // 广告文字背景（0=无 1=半透 2=实底）
reg       p6_sh_c1, p6_sh_c2;      // Logo 是否叠加（模式 ∩ 标志开关）
reg       p6_md_c1, p6_md_c2;      // 是否处于 P6 模式（面板显示门控）

reg [4:0] ad_img_c1, ad_img_c2;

wire p6_md_c = (mode_num == 3'd5);
wire p2_md_c = (mode_num == 3'd1);

wire p8_md_c = (mode_num == 3'd7);

wire logo_show_c = (p2_md_c | p6_md_c | p8_md_c) & p6_logo_en;

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        p6_lm_c1 <= 2'd0; p6_lm_c2 <= 2'd0;
        p6_it_c1 <= 2'd0; p6_it_c2 <= 2'd0;
        p6_ls_c1 <= 2'd0; p6_ls_c2 <= 2'd0;
        p6_ad_c1 <= 1'b0; p6_ad_c2 <= 1'b0;
        p6_bg_c1 <= 2'd0; p6_bg_c2 <= 2'd0;
        p6_sh_c1 <= 1'b0; p6_sh_c2 <= 1'b0;
        p6_md_c1 <= 1'b0; p6_md_c2 <= 1'b0;
        ad_img_c1 <= 5'd0; ad_img_c2 <= 5'd0;
    end else begin
        p6_lm_c1 <= p6_logo_mode; p6_lm_c2 <= p6_lm_c1;
        p6_it_c1 <= p6_item;      p6_it_c2 <= p6_it_c1;
        p6_ls_c1 <= p6_logo_sel;  p6_ls_c2 <= p6_ls_c1;
        p6_ad_c1 <= p6_ad_on;     p6_ad_c2 <= p6_ad_c1;
        p6_bg_c1 <= p6_ad_bg;     p6_bg_c2 <= p6_bg_c1;
        p6_sh_c1 <= logo_show_c;  p6_sh_c2 <= p6_sh_c1;
        p6_md_c1 <= p6_md_c;      p6_md_c2 <= p6_md_c1;
        ad_img_c1 <= sd_img_idx_c2;  ad_img_c2 <= ad_img_c1;
    end
end

// Logo ROM 接口

wire [11:0] logo_addr;  // 64×64（2×AW=12 位）
wire [15:0] logo_q;
wire [23:0] logo_rgb;
wire        logo_de, logo_hs, logo_vs;
wire [23:0] logo_rgb;
wire        logo_de, logo_hs, logo_vs;

logo_rom u_logo_rom (
    .clk   (video_clk),
    .addr  (logo_addr),
    .q     (logo_q)
);

logo_overlay logo_overlay_m0 (
    .I_clk      (video_clk),
    .I_rst      (rst_pixel),
    .I_de       (sub_de),
    .I_hs       (sub_hs),
    .I_vs       (sub_vs),
    .I_rgb      (sub_rgb),
    .I_en       (p6_sh_c2),                // P2 / P6 / P8，且"标志"≠关
    .I_mode     (p6_lm_c2),
    .O_rom_addr (logo_addr),
    .I_rom_q    (logo_q),
    .O_de       (logo_de),
    .O_hs       (logo_hs),
    .O_vs       (logo_vs),
    .O_rgb      (logo_rgb)
);

wire [23:0] pn5_rgb;
wire        pn5_de, pn5_hs, pn5_vs;
wire [23:0] pn6_rgb;
wire        pn6_de, pn6_hs, pn6_vs;

wire [5:0]  cn5_idx, cn6_idx;
wire [4:0]  cn5_row, cn6_row;
wire [5:0] cn7_idx;
wire [4:0] cn7_row;
wire [31:0] cn_font_word;

wire [5:0]  tl_idx;
wire [4:0]  tl_row;
wire        tl_label_on;
wire [5:0] cn3_idx;
wire [4:0] cn3_row;
reg p3_en_c1,p3_en_c2;
always @(posedge video_clk or posedge rst_pixel) begin
    if(rst_pixel)begin p3_en_c1<=0;p3_en_c2<=0;end
    else begin p3_en_c1<=mode_num==3'd2;p3_en_c2<=p3_en_c1;end
end

wire font_p3=p3_en_c2;
wire font_tl=!p3_en_c2 && tl_label_on;
wire font_p7=!p3_en_c2 && !tl_label_on && p7_ui_sync[3];
wire font_p6=!p3_en_c2 && !tl_label_on && !p7_ui_sync[3] && p6_md_c2;
wire font_p5=!p3_en_c2 && !tl_label_on && !p7_ui_sync[3] && !p6_md_c2;
wire [5:0] cn_font_idx=({6{font_p3}} & cn3_idx) | ({6{font_tl}} & tl_idx) |
    ({6{font_p7}} & cn7_idx) | ({6{font_p6}} & cn6_idx) | ({6{font_p5}} & cn5_idx);
wire [4:0] cn_font_row=({5{font_p3}} & cn3_row) | ({5{font_tl}} & tl_row) |
    ({5{font_p7}} & cn7_row) | ({5{font_p6}} & cn6_row) | ({5{font_p5}} & cn5_row);

p5_cn_font_rom u_cn_font (
    .clk       (video_clk),
    .char_idx  (cn_font_idx),      // 6 位索引（模式 mux 后）
    .row       (cn_font_row),      // 5 位行号（模式 mux 后）
    .rom_row   (cn_font_word)      // 1 拍后有效 与面板的 D3 同拍
);

p5_panel p5_panel_m0 (
    .I_clk      (video_clk),
    .I_rst      (rst_pixel),
    .I_de       (logo_de),
    .I_hs       (logo_hs),
    .I_vs       (logo_vs),
    .I_rgb      (logo_rgb),
    .I_panel_en (p5_en_c2),              // 仅 P5
    .I_item     (p5_it_c2),
    .I_sub_on   (p5_on_c2),
    .I_mode     (p5_md_c2),
    .I_pos      (p5_ps_c2),
    .I_bg       (p5_bg_c2),
    .I_size     (p5_sz_c2),
    .I_monitor  (p5_mo_c2),
    .O_font_idx (cn5_idx),
    .O_font_row (cn5_row),
    .I_font_word(cn_font_word),
    .O_de       (pn5_de),
    .O_hs       (pn5_hs),
    .O_vs       (pn5_vs),
    .O_rgb      (pn5_rgb)
);

p6_panel p6_panel_m0 (
    .I_clk      (video_clk),
    .I_rst      (rst_pixel),
    .I_de       (logo_de),
    .I_hs       (logo_hs),
    .I_vs       (logo_vs),
    .I_rgb      (logo_rgb),
    .I_panel_en (p6_md_c2),              // 仅 P6
    .I_item     (p6_it_c2),
    .I_logo_sel (p6_ls_c2),
    .I_ad_on    (p6_ad_c2),
    .I_ad_bg    (p6_bg_c2),
    .O_font_idx (cn6_idx),
    .O_font_row (cn6_row),
    .I_font_word(cn_font_word),
    .O_de       (pn6_de),
    .O_hs       (pn6_hs),
    .O_vs       (pn6_vs),
    .O_rgb      (pn6_rgb)
);

wire [23:0] p5_rgb    = p6_md_c2 ? pn6_rgb : pn5_rgb;
wire        p5p_de    = p6_md_c2 ? pn6_de  : pn5_de;
wire        p5p_hs    = p6_md_c2 ? pn6_hs  : pn5_hs;
wire        p5p_vs    = p6_md_c2 ? pn6_vs  : pn5_vs;
wire [23:0] pn7_rgb;
wire pn7_de,pn7_hs,pn7_vs;
p7_panel p7_panel_m0 (
    .I_clk(video_clk),.I_rst(rst_pixel),
    .I_de(logo_de),.I_hs(logo_hs),.I_vs(logo_vs),.I_rgb(logo_rgb),
    .I_panel_en(p7_ui_sync[3] & ~tl_label_on),.I_item(p7_ui_sync[2]),
    .I_on(p7_ui_sync[1]),.I_horizontal(p7_ui_sync[0]),
    .O_font_idx(cn7_idx),.O_font_row(cn7_row),.I_font_word(cn_font_word),
    .O_de(pn7_de),.O_hs(pn7_hs),.O_vs(pn7_vs),.O_rgb(pn7_rgb)
);
wire [23:0] menu_rgb=p7_ui_sync[3] ? pn7_rgb : p5_rgb;
wire menu_de=p7_ui_sync[3] ? pn7_de : p5p_de;
wire menu_hs=p7_ui_sync[3] ? pn7_hs : p5p_hs;
wire menu_vs=p7_ui_sync[3] ? pn7_vs : p5p_vs;

wire [23:0] ad_rgb;
wire        ad_de, ad_hs, ad_vs;

ad_text ad_text_m0 (
    .I_clk  (video_clk),
    .I_rst  (rst_pixel),
    .I_de   (menu_de),
    .I_hs   (menu_hs),
    .I_vs   (menu_vs),
    .I_rgb  (menu_rgb),
    .I_en   (p6_ad_c2),
    .I_bg   (p6_bg_c2),
    .I_img  (ad_img_c2),                // 图片序号 1..9（>9 不显示）

    .I_txt_wr_clk    (sd_card_clk),
    .I_txt_wr_en     (txt_ln_we),
    .I_txt_wr_addr   (txt_ln_wa),
    .I_txt_wr_data   (txt_ln_wd),
    .I_ach_wr_en     (txt_ach_we),
    .I_ach_wr_addr   (txt_ach_wa),
    .I_ach_wr_data   (txt_ach_wd),
    .O_de   (ad_de),
    .O_hs   (ad_hs),
    .O_vs   (ad_vs),
    .O_rgb  (ad_rgb)
);

wire [23:0] tl_rgb;
wire        tl_de, tl_hs, tl_vs;

wire [23:0] tl_legacy_rgb, p3_rgb;
tran_label tran_label_m0 (
    .I_suppress  (p3_en_c2),
    .I_clk       (video_clk),
    .I_rst       (rst_pixel),
    .I_de        (ad_de),
    .I_hs        (ad_hs),
    .I_vs        (ad_vs),
    .I_rgb       (ad_rgb),
    .I_tran_type (tt_c2),               // 已 2 拍同步到 video_clk 的转场方式
    .I_font_word (cn_font_word),        // 共享字库输出（1 拍同步读）
    .O_font_idx  (tl_idx),
    .O_font_row  (tl_row),
    .O_label_on  (tl_label_on),
    .O_de        (tl_de),
    .O_hs        (tl_hs),
    .O_vs        (tl_vs),
    .O_rgb       (tl_legacy_rgb)
);
p3_panel p3_panel_m0 (
    .I_clk(video_clk),.I_rst(rst_pixel),.I_de(ad_de),.I_hs(ad_hs),.I_vs(ad_vs),.I_rgb(ad_rgb),
    .I_panel_en(p3_en_c2),.I_on(te_c2),.I_type(tt_c2),
    .O_font_idx(cn3_idx),.O_font_row(cn3_row),.I_font_word(cn_font_word),
    .O_de(),.O_hs(),.O_vs(),.O_rgb(p3_rgb)
);
assign tl_rgb=p3_en_c2 ? p3_rgb : tl_legacy_rgb;

reg        pan_en_c1, pan_en_c2;
reg [2:0]  pan_it_c1, pan_it_c2;
reg [7:0]  pan_br_c1, pan_br_c2;
reg [7:0]  pan_co_c1, pan_co_c2;
reg [7:0]  pan_sa_c1, pan_sa_c2;
reg [7:0]  pan_vo_c1, pan_vo_c2;

always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        pan_en_c1 <= 1'b0;  pan_en_c2 <= 1'b0;
        pan_it_c1 <= 3'd0;  pan_it_c2 <= 3'd0;
        pan_br_c1 <= 8'd100; pan_br_c2 <= 8'd100;
        pan_co_c1 <= 8'd100; pan_co_c2 <= 8'd100;
        pan_sa_c1 <= 8'd100; pan_sa_c2 <= 8'd100;
        pan_vo_c1 <= 8'd100; pan_vo_c2 <= 8'd100;
    end else begin
        pan_en_c1 <= (mode_num == 3'd3);   // P4 参数设置
        pan_en_c2 <= pan_en_c1;
        pan_it_c1 <= p_item;  pan_it_c2 <= pan_it_c1;
        pan_br_c1 <= p_bri;   pan_br_c2 <= pan_br_c1;
        pan_co_c1 <= p_con;   pan_co_c2 <= pan_co_c1;
        pan_sa_c1 <= p_sat;   pan_sa_c2 <= pan_sa_c1;
        pan_vo_c1 <= p_vol;   pan_vo_c2 <= pan_vo_c1;
    end
end

audio_volume audio_volume_m0 (
    .I_clk(video_clk),.I_rst(rst_pixel),.I_valid(audio_valid),
    .I_left(audio_left_data),.I_right(audio_right_data),.I_volume(pan_vo_c2),
    .O_valid(volume_valid),.O_left(volume_left),.O_right(volume_right)
);

wire [23:0] panel_rgb;
wire        panel_de, panel_hs, panel_vs;

osd_param_panel osd_param_panel_m0 (
    .I_clk       (video_clk),
    .I_rst       (rst_pixel),
    .I_de        (tl_de),                // 转场字幕的输出（管线再 +4 拍 共 35 拍）
    .I_hs        (tl_hs),
    .I_vs        (tl_vs),
    .I_rgb       (tl_rgb),
    .I_panel_en  (pan_en_c2),            // 已同步到 video_clk 域
    .I_sel_idx   (pan_it_c2),            // P4 当前选中项 0..5
    .I_bri       (pan_br_c2),
    .I_con       (pan_co_c2),
    .I_sat       (pan_sa_c2),
    .I_vol       (pan_vo_c2),
    .O_de        (panel_de),             // 延迟 4 拍后的 de
    .O_hs        (panel_hs),
    .O_vs        (panel_vs),
    .O_rgb       (panel_rgb)
);

wire [23:0] mon_rgb;
wire        mon_de, mon_hs, mon_vs;

wire mon_md_c = p5_en_c | p8_md_c;      // P5 或 P8
reg  mon_md_c1, mon_md_c2;
always @(posedge video_clk or posedge rst_pixel) begin
    if (rst_pixel) begin
        mon_md_c1 <= 1'b0; mon_md_c2 <= 1'b0;
    end else begin
        mon_md_c1 <= mon_md_c; mon_md_c2 <= mon_md_c1;
    end
end

wire mon_en = mon_md_c2 & p5_mo_c2;     // （P5 或 P8）且"监视"=开

sync_monitor sync_monitor_m0 (
    .I_clk          (video_clk),
    .I_rst          (rst_pixel),
    .I_de           (panel_de),
    .I_hs           (panel_hs),
    .I_vs           (panel_vs),
    .I_rgb          (panel_rgb),
    .I_en           (mon_en),
    .I_frame        (sub_frame_now),
    .I_sample_cnt   (a_sample_cnt),
    .I_aud_fsm      ({4'd0, mon_afsm_c2}),
    .I_aud_undr     (mon_undr_c2),
    .I_vid_fsm      ({4'd0, mon_vfsm_c2}),
    .I_img_idx      (mon_img_c2[3:0]),
    .I_mode_num     ({5'd0, mon_mode_c2}),
    .I_item         (p5_it_c2),
    .O_de           (mon_de),
    .O_hs           (mon_hs),
    .O_vs           (mon_vs),
    .O_rgb          (mon_rgb)
);

assign vout_data = display_valid ? mon_rgb : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (1280),
    .FRAME_HEIGHT     (720),
    .PIX_PER_WORD     (2)                 // RGB565：每 word 2 像素
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),

    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),     // 槽号 0/1/2（两位，值域 0~2）
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),
    .rd_fifo_empty     (rd_fifo_empty),
    .read_addr_b_0     (BUF0_ADDR),
    .read_addr_b_1     (BUF1_ADDR),
    .read_addr_b_2     (BUF2_ADDR),
    .read_addr_b_3     (24'd0),
    .read_addr_b_index (prev_disp_idx),     // 旧图槽 = 上一显示槽
    .read_data_b       (video_read_data_b),
    .rd_fifo_empty_b   (rd_fifo_empty_b),
    .rd_fifo_full      (rd_fifo_full),
    .wr_busy           (App_wr_busy),

    .burst_err         (rd_burst_err),
    .burst_diff        (rd_burst_diff),     // 差值（256 - 实收）

    .wr_cnt_err        (rd_wr_cnt_err),     // 写帧结束 write_cnt != write_len
    .wr_last_addr      (rd_wr_last_addr),   // 帧尾写地址低 8 位

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),    // 槽号 0/1/2
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_pixel),
    .I_audio_valid (volume_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

video_rgb_to_axis_1280x720 #(
    .H_ACTIVE      (1280)
) u_video_rgb_to_axis_1280x720(
    .I_clk         (video_clk),
    .I_rst         (rst_pixel),
    .I_vs          (mon_vs),             // 延迟 28 拍后（与 vout_data 对齐）
    .I_de          (mon_de),
    .I_rgb         (vout_data),          // 已含 6+4+4+4+4 拍延迟
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_pixel),
    .O_pulse (edid_trig)
);

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 1650       ),
    .HSA                    ( 40         ),
    .HFP                    ( 110        ),
    .HBP                    ( 220        ),
    .HACTIVE                ( 1280       ),
    .VTOTAL                 ( 750        ),
    .VSA                    ( 5          ),
    .VFP                    ( 5          ),
    .VBP                    ( 20         ),
    .VACTIVE                ( 720        ),
    .VIDEO_VIC              ( 69         ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 750        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_pixel),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (volume_valid),
    .I_audio_left_data  (volume_left),
    .I_audio_right_data (volume_right),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst(~rst_n),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
