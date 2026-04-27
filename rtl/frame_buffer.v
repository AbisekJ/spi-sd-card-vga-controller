// =============================================================================
// FILE: frame_buffer.v
// DESC: Dual-port block RAM, 320x240 RGB565 image
//       76,800 x 16-bit words = 153,600 bytes
//       Inferred as M9K blocks by Quartus (EP4CE115 has 432 M9K blocks)
// =============================================================================
module frame_buffer (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [16:0] wr_byte_addr,   // 0..153599
    input  wire [7:0]  wr_data,

    input  wire        rd_clk,
    input  wire [15:0] rd_pixel_addr,  // 0..76799
    output reg  [15:0] rd_pixel_data
);
    reg [15:0] mem [0:76799];
    reg [7:0]  hi_byte;

    // Write port: pair bytes into 16-bit words
    always @(posedge wr_clk) begin
        if (wr_en) begin
            if (wr_byte_addr[0] == 1'b0)
                hi_byte <= wr_data;
            else
                mem[wr_byte_addr[16:1]] <= {hi_byte, wr_data};
        end
    end

    // Read port: 1-cycle registered latency
    always @(posedge rd_clk)
        rd_pixel_data <= mem[rd_pixel_addr];

endmodule
