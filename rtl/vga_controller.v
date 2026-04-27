module vga_controller (
    input  wire        pclk,          // 25 MHz pixel clock
    input  wire        rst_n,

    // Frame buffer read interface
    output wire [15:0] fb_addr_o,     // pixel address
    input  wire [15:0] fb_data_i,     // RGB565 pixel (1-cycle latency)

    // VGA signals for DE2-115 ADV7123 DAC
    output reg         vga_hs_o,      // Horizontal sync (active LOW)
    output reg         vga_vs_o,      // Vertical sync   (active LOW)
    output wire        vga_blank_n_o, // Blanking: HIGH = active pixel region
    output wire        vga_sync_n_o,  // Composite sync: tie LOW (not used)
    output wire        vga_clk_o,     // Pixel clock to DAC
    output wire [7:0]  vga_r_o,       // Red   8 bits
    output wire [7:0]  vga_g_o,       // Green 8 bits
    output wire [7:0]  vga_b_o        // Blue  8 bits
);

    // =========================================================================
    // 640x480 @ 60Hz timing constants — do not change
    // =========================================================================
    localparam H_ACT  = 640;
    localparam H_FP   = 16;
    localparam H_SYNC = 96;
    localparam H_BP   = 48;
    localparam H_TOT  = 800;

    localparam V_ACT  = 480;
    localparam V_FP   = 10;
    localparam V_SYNC = 2;
    localparam V_BP   = 33;
    localparam V_TOT  = 525;

    // =========================================================================
    // Pixel counters
    // =========================================================================
    reg [9:0] hc;   // 0..799
    reg [9:0] vc;   // 0..524

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hc <= 10'd0;
            vc <= 10'd0;
        end else begin
            if (hc == H_TOT - 1) begin
                hc <= 10'd0;
                vc <= (vc == V_TOT - 1) ? 10'd0 : vc + 1'b1;
            end else begin
                hc <= hc + 1'b1;
            end
        end
    end

    // =========================================================================
    // Sync generation (active LOW for standard VGA)
    // =========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            vga_hs_o <= 1'b1;
            vga_vs_o <= 1'b1;
        end else begin
            vga_hs_o <= ~((hc >= H_ACT + H_FP) && (hc < H_ACT + H_FP + H_SYNC));
            vga_vs_o <= ~((vc >= V_ACT + V_FP) && (vc < V_ACT + V_FP + V_SYNC));
        end
    end

    // =========================================================================
    // Active region
    // =========================================================================
    wire active = (hc < H_ACT) && (vc < V_ACT);

    // Registered to align with the 1-cycle frame buffer read latency
    reg active_d;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) active_d <= 1'b0;
        else        active_d <= active;
    end

    // BLANK_N: HIGH during active pixel output, LOW during blanking
    assign vga_blank_n_o = active_d;

    // SYNC_N: not used in standard VGA, must be LOW
    assign vga_sync_n_o  = 1'b0;

    // CLK: the ADV7123 needs the pixel clock on its CLK input
    assign vga_clk_o = pclk;

    // =========================================================================
    // Frame buffer address
    // Image: 320x240, scaled 2x to 640x480
    // img_x = hc >> 1  (0..319)
    // img_y = vc >> 1  (0..239)
    // pixel_addr = img_y * 320 + img_x
    //   320 = 256 + 64  → addr = (y<<8) + (y<<6) + x
    // =========================================================================
    wire [8:0] img_x = hc[9:1];    // hc / 2
    wire [7:0] img_y = vc[8:1];    // vc / 2

    wire [15:0] px_addr = ({8'd0, img_y} << 8)
                        + ({8'd0, img_y} << 6)
                        + {7'd0, img_x};

    assign fb_addr_o = px_addr;

    // =========================================================================
    // RGB565 to 8-bit per channel
    //
    // RGB565 layout: [15:11]=R5, [10:5]=G6, [4:0]=B5
    //
    // Expand to 8 bits by replicating the MSBs into the empty LSBs:
    //   R5 → R8: {R5[4:0], R5[4:2]}  = 5 + 3 = 8 bits
    //   G6 → G8: {G6[5:0], G6[5:4]}  = 6 + 2 = 8 bits
    //   B5 → B8: {B5[4:0], B5[4:2]}  = 5 + 3 = 8 bits
    //
    // This ensures maximum value (0xFF) maps to full brightness,
    // and minimum value (0x00) maps to black — no truncation artifacts.
    // =========================================================================
    wire [4:0] px_r5 = fb_data_i[15:11];
    wire [5:0] px_g6 = fb_data_i[10:5];
    wire [4:0] px_b5 = fb_data_i[4:0];

    wire [7:0] r8 = {px_r5, px_r5[4:2]};   // 5-bit → 8-bit
    wire [7:0] g8 = {px_g6, px_g6[5:4]};   // 6-bit → 8-bit
    wire [7:0] b8 = {px_b5, px_b5[4:2]};   // 5-bit → 8-bit

    // Output black during blanking, pixel colour during active
    assign vga_r_o = active_d ? r8 : 8'd0;
    assign vga_g_o = active_d ? g8 : 8'd0;
    assign vga_b_o = active_d ? b8 : 8'd0;

endmodule
