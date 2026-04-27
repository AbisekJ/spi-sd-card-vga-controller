// =============================================================================
// FILE: sd_controller.v
// DESC: SD Card SPI-mode controller
//
// Initialization sequence (SD Physical Layer Spec v4.10):
//   1. 1ms power-up delay
//   2. 80 dummy clocks with CS=HIGH
//   3. CMD0  (GO_IDLE)      → expect R1 = 0x01
//   4. CMD8  (SEND_IF_COND) → expect R1 = 0x01, then 4 trailer bytes
//   5. CMD55 + CMD41 (ACMD41 with HCS=1) → repeat until R1 = 0x00
//   6. CMD58 (READ_OCR)     → detect SDHC via CCS bit
//   7. Switch to fast SPI clock, assert init_done_o
//
// Block read (called repeatedly by sd_loader):
//   CMD17 → R1=0x00 → data token 0xFE → 512 bytes → 2 CRC bytes
//
// System clock: 50 MHz
// =============================================================================
module sd_controller (
    input  wire        clk,
    input  wire        rst_n,

    output reg         init_done_o,
    output reg         error_o,

    // Block read interface
    input  wire        rd_req_i,
    input  wire [31:0] rd_addr_i,
    output reg  [7:0]  rd_data_o,
    output reg         rd_valid_o,
    output reg         rd_done_o,

    // SPI master interface
    output reg         spi_start_o,
    output reg  [7:0]  spi_tx_o,
    input  wire [7:0]  spi_rx_i,
    input  wire        spi_done_i,
    input  wire        spi_busy_i,
    output reg         spi_fast_o,

    output reg         sd_cs_o    // active LOW
);

    localparam [5:0]
        S_PWRUP      = 0,
        S_DUMMYCLK   = 1,
        S_CMD0_S     = 2,  S_CMD0_R  = 3,
        S_CMD8_S     = 4,  S_CMD8_R  = 5,  S_CMD8_T  = 6,
        S_CMD55_S    = 7,  S_CMD55_R = 8,
        S_CMD41_S    = 9,  S_CMD41_R = 10, S_CMD41_W = 11,
        S_CMD58_S    = 12, S_CMD58_R = 13, S_CMD58_T = 14,
        S_IDLE       = 15,
        S_RD17_S     = 16, S_RD17_R  = 17,
        S_RD_TOKEN   = 18, S_RD_DATA = 19,
        S_RD_CRC     = 20, S_RD_DONE = 21,
        S_ERROR      = 22;

    reg [5:0]  state;
    reg [23:0] wait_cnt;
    reg [7:0]  tries;
    reg [3:0]  cidx;
    reg [7:0]  cmd[0:5];
    reg [9:0]  dcnt;
    reg [7:0]  tcnt;
    reg [15:0] retry;
    reg        is_hc;

    // 1ms at 50MHz
    localparam PU_CYCLES = 24'd50000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_PWRUP; wait_cnt <= 0; tries <= 0;
            cidx  <= 0; dcnt  <= 0; tcnt  <= 0; retry <= 0; is_hc <= 0;
            init_done_o <= 0; error_o <= 0;
            rd_data_o   <= 0; rd_valid_o <= 0; rd_done_o <= 0;
            spi_start_o <= 0; spi_tx_o   <= 8'hFF; spi_fast_o <= 0;
            sd_cs_o     <= 1;
            cmd[0]<=0; cmd[1]<=0; cmd[2]<=0; cmd[3]<=0; cmd[4]<=0; cmd[5]<=0;
        end else begin
            spi_start_o <= 0;
            rd_valid_o  <= 0;
            rd_done_o   <= 0;

            case (state)

            // ------------------------------------------------------------------
            S_PWRUP: begin
                sd_cs_o <= 1; spi_fast_o <= 0;
                if (wait_cnt >= PU_CYCLES) begin wait_cnt <= 0; state <= S_DUMMYCLK; end
                else wait_cnt <= wait_cnt + 1;
            end

            // 10 x 0xFF = 80 clock pulses, CS=HIGH
            S_DUMMYCLK: begin
                sd_cs_o <= 1;
                if (!spi_busy_i && !spi_start_o) begin
                    if (wait_cnt < 10) begin
                        spi_tx_o <= 8'hFF; spi_start_o <= 1;
                        wait_cnt <= wait_cnt + 1;
                    end else begin
                        wait_cnt  <= 0;
                        cmd[0]<=8'h40; cmd[1]<=8'h00; cmd[2]<=8'h00;
                        cmd[3]<=8'h00; cmd[4]<=8'h00; cmd[5]<=8'h95;
                        cidx <= 0; sd_cs_o <= 0; state <= S_CMD0_S;
                    end
                end
            end

            // CMD0 send
            S_CMD0_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_CMD0_R; end
                end
            end
            // CMD0 response: wait for 0x01
            S_CMD0_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if      (spi_rx_i == 8'h01) begin
                        cmd[0]<=8'h48; cmd[1]<=8'h00; cmd[2]<=8'h00;
                        cmd[3]<=8'h01; cmd[4]<=8'hAA; cmd[5]<=8'h87;
                        cidx <= 0; state <= S_CMD8_S;
                    end
                    else if (spi_rx_i != 8'hFF) state <= S_ERROR;
                    else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end

            // CMD8 send
            S_CMD8_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_CMD8_R; end
                end
            end
            // CMD8 R1 byte
            S_CMD8_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (spi_rx_i != 8'hFF) begin tcnt <= 0; state <= S_CMD8_T; end
                    else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end
            // CMD8 discard 4 trailer bytes
            S_CMD8_T: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (tcnt == 3) begin
                        cmd[0]<=8'h77; cmd[1]<=8'h00; cmd[2]<=8'h00;
                        cmd[3]<=8'h00; cmd[4]<=8'h00; cmd[5]<=8'h65;
                        cidx <= 0; retry <= 0; state <= S_CMD55_S;
                    end else tcnt <= tcnt+1;
                end
            end

            // CMD55 send
            S_CMD55_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_CMD55_R; end
                end
            end
            // CMD55 response
            S_CMD55_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (spi_rx_i != 8'hFF) begin
                        cmd[0]<=8'h69; cmd[1]<=8'h40; cmd[2]<=8'h00;
                        cmd[3]<=8'h00; cmd[4]<=8'h00; cmd[5]<=8'h77;
                        cidx <= 0; state <= S_CMD41_S;
                    end else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end

            // CMD41 send
            S_CMD41_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_CMD41_R; end
                end
            end
            // CMD41 response
            S_CMD41_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if      (spi_rx_i == 8'h00) begin   // ready
                        cmd[0]<=8'h7A; cmd[1]<=8'h00; cmd[2]<=8'h00;
                        cmd[3]<=8'h00; cmd[4]<=8'h00; cmd[5]<=8'hFD;
                        cidx <= 0; state <= S_CMD58_S;
                    end
                    else if (spi_rx_i == 8'h01) state <= S_CMD41_W;  // still busy
                    else if (spi_rx_i != 8'hFF) state <= S_ERROR;
                    else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end
            // CMD41 retry wait (~1ms)
            S_CMD41_W: begin
                if (retry >= 16'd50000) begin
                    retry <= 0;
                    cmd[0]<=8'h77; cmd[1]<=8'h00; cmd[2]<=8'h00;
                    cmd[3]<=8'h00; cmd[4]<=8'h00; cmd[5]<=8'h65;
                    cidx <= 0; state <= S_CMD55_S;
                end else retry <= retry + 1;
            end

            // CMD58 send
            S_CMD58_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_CMD58_R; end
                end
            end
            // CMD58 R1
            S_CMD58_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (spi_rx_i != 8'hFF) begin tcnt <= 0; state <= S_CMD58_T; end
                    else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end
            // CMD58 4 OCR bytes
            S_CMD58_T: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (tcnt == 0) is_hc <= spi_rx_i[6];  // CCS bit
                    if (tcnt == 3) begin
                        sd_cs_o    <= 1;
                        spi_fast_o <= 1;
                        init_done_o<= 1;
                        state      <= S_IDLE;
                    end else tcnt <= tcnt+1;
                end
            end

            // ------------------------------------------------------------------
            S_IDLE: begin
                sd_cs_o <= 1;
                if (rd_req_i) begin
                    begin
                        reg [31:0] a;
                        a = is_hc ? rd_addr_i : (rd_addr_i << 9);
                        cmd[0] <= 8'h51;
                        cmd[1] <= a[31:24]; cmd[2] <= a[23:16];
                        cmd[3] <= a[15:8];  cmd[4] <= a[7:0];
                        cmd[5] <= 8'h01;
                    end
                    cidx    <= 0;
                    dcnt    <= 0;
                    sd_cs_o <= 0;
                    state   <= S_RD17_S;
                end
            end

            // CMD17 send
            S_RD17_S: begin
                if (!spi_busy_i && !spi_start_o) begin
                    if (cidx < 6) begin spi_tx_o <= cmd[cidx]; spi_start_o <= 1; cidx <= cidx+1; end
                    else begin tries <= 0; state <= S_RD17_R; end
                end
            end
            // CMD17 R1
            S_RD17_R: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if      (spi_rx_i == 8'h00) begin tries <= 0; state <= S_RD_TOKEN; end
                    else if (spi_rx_i != 8'hFF) state <= S_ERROR;
                    else begin tries <= tries+1; if (tries >= 20) state <= S_ERROR; end
                end
            end
            // Wait for data token 0xFE
            S_RD_TOKEN: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if      (spi_rx_i == 8'hFE) begin dcnt <= 0; state <= S_RD_DATA; end
                    else if (spi_rx_i != 8'hFF) state <= S_ERROR;
                    else begin tries <= tries+1; if (tries >= 8'hFF) state <= S_ERROR; end
                end
            end
            // Read 512 data bytes
            S_RD_DATA: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    rd_data_o  <= spi_rx_i;
                    rd_valid_o <= 1;
                    if (dcnt == 511) begin tcnt <= 0; state <= S_RD_CRC; end
                    else dcnt <= dcnt + 1;
                end
            end
            // Discard 2 CRC bytes
            S_RD_CRC: begin
                if (!spi_busy_i && !spi_start_o) begin spi_tx_o <= 8'hFF; spi_start_o <= 1; end
                else if (spi_done_i) begin
                    if (tcnt == 1) state <= S_RD_DONE;
                    else tcnt <= tcnt + 1;
                end
            end
            S_RD_DONE: begin sd_cs_o <= 1; rd_done_o <= 1; state <= S_IDLE; end

            // ------------------------------------------------------------------
            S_ERROR: begin error_o <= 1; sd_cs_o <= 1; end
            default:  state <= S_PWRUP;
            endcase
        end
    end
endmodule
