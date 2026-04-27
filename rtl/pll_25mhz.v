// =============================================================================
// FILE: pll_25mhz.v  -  STUB - MUST BE REPLACED
// =============================================================================
// Replace this with the Quartus-generated ALTPLL.
// Steps:
//   1. Quartus → Tools → IP Catalog → type "PLL" → double-click ALTPLL
//   2. Save as: rtl/pll_25mhz (Verilog)
//   3. inclk0 frequency: 50 MHz
//   4. Enable areset input: YES
//   5. Enable locked output: YES
//   6. clk c0: 25.000 MHz
//   7. Finish → Generate
//   8. In project: remove this file, add generated pll_25mhz.qip
// =============================================================================
module pll_25mhz (
    input  wire areset,
    input  wire inclk0,
    output wire c0,
    output wire locked
);
`ifndef SYNTHESIS
    reg r = 0;
    always #10 r = ~r;        // 50MHz sim
    reg [4:0] cnt = 0;
    always @(posedge inclk0) if (!locked) cnt <= cnt + 1;
    assign c0     = r;
    assign locked = (cnt > 20);
`endif
endmodule
