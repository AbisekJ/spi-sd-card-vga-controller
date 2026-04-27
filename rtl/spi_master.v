// =============================================================================
// FILE: spi_master.v
// DESC: SPI Mode 0 Master (CPOL=0, CPHA=0), 8 bits per transfer, MSB first
//
// System clock: 50 MHz (DE2-115 board oscillator, used directly)
//
// Clock speeds:
//   fast_clk_i = 0  →  50MHz / (2 x 125) = 200 kHz   (SD card init phase)
//   fast_clk_i = 1  →  50MHz / (2 x 5)   =   5 MHz   (SD card data phase)
//
// Usage:
//   Put byte on tx_data_i, pulse start_i HIGH for ONE clock cycle.
//   Wait until done_o pulses HIGH (one cycle).
//   Read received byte from rx_data_o.
//   Do not assert start_i while busy_o is HIGH.
// =============================================================================
module spi_master (
    input  wire       sys_clk,     // 50 MHz
    input  wire       rst_n,

    input  wire       start_i,     // Pulse HIGH 1 cycle to start transfer
    input  wire       fast_clk_i,  // 0=200kHz, 1=5MHz
    input  wire [7:0] tx_data_i,
    output reg  [7:0] rx_data_o,
    output reg        busy_o,
    output reg        done_o,      // 1-cycle pulse when transfer complete

    output reg        sclk_o,
    output reg        mosi_o,
    input  wire       miso_i
);
    localparam SLOW_DIV = 8'd124;  // half-period count for 200kHz
    localparam FAST_DIV = 8'd4;    // half-period count for 5MHz

    reg [7:0] clk_cnt;
    reg [7:0] shreg;       // shift register
    reg [3:0] bit_cnt;     // counts bits 0..7
    reg       phase;       // 0=SCLK low half, 1=SCLK high half
    reg       active;

    wire [7:0] div = fast_clk_i ? FAST_DIV : SLOW_DIV;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_o   <= 0; done_o  <= 0;
            sclk_o   <= 0; mosi_o  <= 1;
            rx_data_o<= 0; shreg   <= 0;
            bit_cnt  <= 0; phase   <= 0;
            active   <= 0; clk_cnt <= 0;
        end else begin
            done_o <= 0;

            if (!active) begin
                sclk_o <= 0;
                if (start_i) begin
                    shreg   <= tx_data_i;
                    mosi_o  <= tx_data_i[7];  // MSB first
                    bit_cnt <= 0;
                    phase   <= 0;
                    clk_cnt <= 0;
                    busy_o  <= 1;
                    active  <= 1;
                end
            end else begin
                if (clk_cnt < div) begin
                    clk_cnt <= clk_cnt + 1'b1;
                end else begin
                    clk_cnt <= 0;
                    if (!phase) begin
                        // Rising edge: sample MISO
                        sclk_o <= 1;
                        shreg  <= {shreg[6:0], miso_i};
                        phase  <= 1;
                    end else begin
                        // Falling edge: shift out next MOSI bit
                        sclk_o  <= 0;
                        phase   <= 0;
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd7) begin
                            rx_data_o <= {shreg[6:0], miso_i};
                            busy_o    <= 0;
                            done_o    <= 1;
                            active    <= 0;
                        end else begin
                            mosi_o <= shreg[5]; // next bit after shift
                        end
                    end
                end
            end
        end
    end
endmodule
