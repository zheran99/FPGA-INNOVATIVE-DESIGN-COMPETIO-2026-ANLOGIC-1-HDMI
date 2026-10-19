`timescale 1ns/1ps

module sd_card_mgr
#(
    parameter  SPI_LOW_SPEED_DIV  = 248,        // SD 初始化低速档
    parameter  SPI_HIGH_SPEED_DIV = 0           // 高速档：100M/((0+2)*2) = 25 MHz
)
(
    input               clk,                    // sd_card_clk 100 MHz
    input               rst,

    output              SD_nCS,
    output              SD_DCLK,
    output              SD_MOSI,
    input               SD_MISO,

    // 全局状态
    output              sd_init_done,           // SD 初始化完成

    input               V_sec_read,
    input  [31:0]       V_sec_read_addr,
    output [7:0]        V_sec_read_data,
    output              V_sec_read_data_valid,
    output              V_sec_read_end,

    input               A_sec_read,
    input  [31:0]       A_sec_read_addr,
    output [7:0]        A_sec_read_data,
    output              A_sec_read_data_valid,
    output              A_sec_read_end
);

// 所有者锁存

reg owner_audio;
reg busy;

reg owner_latch;               // 当前事务的归属（事务发起时锁存）

wire m_sec_read;
wire [31:0] m_sec_read_addr;
wire [7:0]  m_sec_read_data;
wire        m_sec_read_data_valid;
wire        m_sec_read_end;

assign m_sec_read      = owner_audio ? A_sec_read      : V_sec_read;
assign m_sec_read_addr = owner_audio ? A_sec_read_addr : V_sec_read_addr;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        owner_audio <= 1'b0;
        owner_latch <= 1'b0;
        busy        <= 1'b0;
    end else begin
        if (m_sec_read_end)
            busy <= 1'b0;                  // 扇区读完 释放
        else if (m_sec_read && !busy)
            busy <= 1'b1;                  // 已发起 占用

        if (m_sec_read && !busy)
            owner_latch <= owner_audio;

        if (!busy) begin
            if (A_sec_read)
                owner_audio <= 1'b1;       // 音频优先
            else
                owner_audio <= 1'b0;
        end
    end
end

assign V_sec_read_data       = m_sec_read_data;
assign V_sec_read_data_valid = m_sec_read_data_valid & (~owner_latch);
assign V_sec_read_end        = m_sec_read_end        & (~owner_latch);

assign A_sec_read_data       = m_sec_read_data;
assign A_sec_read_data_valid = m_sec_read_data_valid &   owner_latch;
assign A_sec_read_end        = m_sec_read_end        &   owner_latch;

sd_card_top
#(
    .SPI_LOW_SPEED_DIV  (SPI_LOW_SPEED_DIV ),
    .SPI_HIGH_SPEED_DIV (SPI_HIGH_SPEED_DIV)
)
sd_card_top_m0
(
    .clk                    (clk                    ),
    .rst                    (rst                    ),
    .SD_nCS                 (SD_nCS                 ),
    .SD_DCLK                (SD_DCLK                ),
    .SD_MOSI                (SD_MOSI                ),
    .SD_MISO                (SD_MISO                ),
    .sd_init_done           (sd_init_done           ),
    .sd_sec_read            (m_sec_read             ),
    .sd_sec_read_addr       (m_sec_read_addr        ),
    .sd_sec_read_data       (m_sec_read_data        ),
    .sd_sec_read_data_valid (m_sec_read_data_valid  ),
    .sd_sec_read_end        (m_sec_read_end         ),
    .sd_sec_write           (1'b0                   ),
    .sd_sec_write_addr      (32'd0                  ),
    .sd_sec_write_data      (                       ),
    .sd_sec_write_data_req  (                       ),
    .sd_sec_write_end       (                       )
);

endmodule
