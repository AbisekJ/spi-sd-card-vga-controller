// =============================================================================
// FILE: top.v
// DESC: Top-level for DE2-115 — SD Card → Frame Buffer → VGA
//
// DE2-115 SPECIFICS:
//   FPGA    : EP4CE115F29C7
//   Clock   : 50MHz on PIN_Y2
//   Reset   : KEY[0] on PIN_M23 (active LOW push button)
//   VGA     : ADV7123 DAC, 8 bits per channel (R[7:0], G[7:0], B[7:0])
//   LEDs    : LEDR[17:0] active HIGH, LEDG[8:0] active HIGH
//   GPIO    : 36-pin expansion header for SD SPI module
// =============================================================================
module top (
    // ── Clock ─────────────────────────────────────────────────────────────────
    input  wire        CLOCK_50,      // PIN_Y2

    // ── Reset (KEY[0], active LOW) ────────────────────────────────────────────
    input  wire [3:0]  KEY,           // KEY[0] = PIN_M23

    // ── SD Card SPI (wired to GPIO header) ────────────────────────────────────
    output wire        SD_CS_N,       // GPIO[0] = PIN_AB22
    output wire        SD_SCLK,       // GPIO[1] = PIN_AC15
    output wire        SD_MOSI,       // GPIO[2] = PIN_AB21
    input  wire        SD_MISO,       // GPIO[3] = PIN_Y17

    // ── VGA (ADV7123, 8-bit per channel) ─────────────────────────────────────
    output wire [7:0]  VGA_R,         // Red   8 bits
    output wire [7:0]  VGA_G,         // Green 8 bits
    output wire [7:0]  VGA_B,         // Blue  8 bits
    output wire        VGA_HS,        // Horizontal sync → PIN_G13
    output wire        VGA_VS,        // Vertical sync   → PIN_C13
    output wire        VGA_BLANK_N,   // Blanking        → PIN_F11
    output wire        VGA_SYNC_N,    // Comp sync       → PIN_C10 (tied LOW)
    output wire        VGA_CLK,       // Pixel clock     → PIN_A12

    // ── Status LEDs ───────────────────────────────────────────────────────────
    output wire [17:0] LEDR,          // Red LEDs
    output wire [8:0]  LEDG           // Green LEDs
);

    // =========================================================================
    // PLL: 50MHz → 25MHz
    // !! Generate via: Tools → IP Catalog → ALTPLL !!
    // !! 50MHz in, 25MHz out, areset+locked enabled !!
    // !! Remove this stub, add generated .qip file   !!
    // =========================================================================
    wire clk_25m;
    wire pll_locked;

    pll_25mhz u_pll (
        .areset (~KEY[0]),    // PLL reset = active HIGH (inverted from KEY)
        .inclk0 (CLOCK_50),
        .c0     (clk_25m),
        .locked (pll_locked)
    );

    // =========================================================================
    // Reset synchroniser — hold in reset until PLL is locked
    // =========================================================================
    reg [1:0] rst_pipe;
    always @(posedge clk_25m or negedge pll_locked) begin
        if (!pll_locked) rst_pipe <= 2'b00;
        else             rst_pipe <= {rst_pipe[0], 1'b1};
    end
    wire rst_n = rst_pipe[1];

    // =========================================================================
    // SPI Master
    // =========================================================================
    wire       spi_start, spi_fast, spi_done, spi_busy;
    wire [7:0] spi_tx, spi_rx;

    spi_master u_spi (
        .sys_clk    (clk_25m),
        .rst_n      (rst_n),
        .start_i    (spi_start),
        .fast_clk_i (spi_fast),
        .tx_data_i  (spi_tx),
        .rx_data_o  (spi_rx),
        .busy_o     (spi_busy),
        .done_o     (spi_done),
        .sclk_o     (SD_SCLK),
        .mosi_o     (SD_MOSI),
        .miso_i     (SD_MISO)
    );

    // =========================================================================
    // SD Card Controller
    // =========================================================================
    wire        sd_init_done, sd_error;
    wire        sd_rd_req;
    wire [31:0] sd_rd_addr;
    wire [7:0]  sd_rd_data;
    wire        sd_rd_valid, sd_rd_done;
    wire        sd_cs_int;

    assign SD_CS_N = sd_cs_int;

    sd_controller u_sd (
        .clk         (clk_25m),
        .rst_n       (rst_n),
        .init_done_o (sd_init_done),
        .error_o     (sd_error),
        .rd_req_i    (sd_rd_req),
        .rd_addr_i   (sd_rd_addr),
        .rd_data_o   (sd_rd_data),
        .rd_valid_o  (sd_rd_valid),
        .rd_done_o   (sd_rd_done),
        .spi_start_o (spi_start),
        .spi_tx_o    (spi_tx),
        .spi_rx_i    (spi_rx),
        .spi_done_i  (spi_done),
        .spi_busy_i  (spi_busy),
        .spi_fast_o  (spi_fast),
        .sd_cs_o     (sd_cs_int)
    );

    // =========================================================================
    // SD Loader
    // =========================================================================
    wire        fb_wr_en;
    wire [16:0] fb_wr_addr;
    wire [7:0]  fb_wr_data;
    wire        load_done, load_error;

    sd_loader #(
        .IMAGE_START_SECTOR (32'd2048),
        .TOTAL_SECTORS      (10'd300)
    ) u_loader (
        .clk          (clk_25m),
        .rst_n        (rst_n),
        .init_done_i  (sd_init_done),
        .rd_req_o     (sd_rd_req),
        .rd_addr_o    (sd_rd_addr),
        .rd_data_i    (sd_rd_data),
        .rd_valid_i   (sd_rd_valid),
        .rd_done_i    (sd_rd_done),
        .sd_error_i   (sd_error),
        .fb_wr_en_o   (fb_wr_en),
        .fb_wr_addr_o (fb_wr_addr),
        .fb_wr_data_o (fb_wr_data),
        .load_done_o  (load_done),
        .load_error_o (load_error)
    );

    // =========================================================================
    // Frame Buffer (320x240 RGB565 in on-chip block RAM)
    // =========================================================================
    wire [15:0] fb_rd_addr, fb_rd_data;

    frame_buffer u_fb (
        .wr_clk        (clk_25m),
        .wr_en         (fb_wr_en),
        .wr_byte_addr  (fb_wr_addr),
        .wr_data       (fb_wr_data),
        .rd_clk        (clk_25m),
        .rd_pixel_addr (fb_rd_addr),
        .rd_pixel_data (fb_rd_data)
    );

    // =========================================================================
    // VGA Controller (8-bit output for DE2-115 ADV7123)
    // =========================================================================
    vga_controller u_vga (
        .pclk          (clk_25m),
        .rst_n         (rst_n),
        .fb_addr_o     (fb_rd_addr),
        .fb_data_i     (fb_rd_data),
        .vga_hs_o      (VGA_HS),
        .vga_vs_o      (VGA_VS),
        .vga_blank_n_o (VGA_BLANK_N),
        .vga_sync_n_o  (VGA_SYNC_N),
        .vga_clk_o     (VGA_CLK),
        .vga_r_o       (VGA_R),
        .vga_g_o       (VGA_G),
        .vga_b_o       (VGA_B)
    );

    // =========================================================================
    // Status LEDs
    // LEDR[0] ON = SD card initialised
    // LEDR[1] ON = image fully loaded and on screen
    // LEDR[2] ON = error (check SD wiring)
    // LEDG[0] ON = PLL locked
    // =========================================================================
    assign LEDR[0]    = sd_init_done;
    assign LEDR[1]    = load_done;
    assign LEDR[2]    = sd_error | load_error;
    assign LEDR[17:3] = 15'd0;
    assign LEDG[0]    = pll_locked;
    assign LEDG[8:1]  = 8'd0;

endmodule
