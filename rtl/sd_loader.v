// =============================================================================
// FILE: sd_loader.v
// DESC: Reads 300 sectors (sectors 2048..2347) from SD card into frame buffer
// =============================================================================
module sd_loader #(
    parameter [31:0] IMAGE_START_SECTOR = 32'd2048,
    parameter [9:0]  TOTAL_SECTORS      = 10'd300
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init_done_i,
    output reg         rd_req_o,
    output reg  [31:0] rd_addr_o,
    input  wire [7:0]  rd_data_i,
    input  wire        rd_valid_i,
    input  wire        rd_done_i,
    input  wire        sd_error_i,
    output reg         fb_wr_en_o,
    output reg  [16:0] fb_wr_addr_o,
    output reg  [7:0]  fb_wr_data_o,
    output reg         load_done_o,
    output reg         load_error_o
);
    localparam S_WAIT=0, S_NEXT=1, S_REQ=2, S_READ=3, S_DONE=4, S_ERR=5;
    reg [2:0]  state;
    reg [9:0]  sec_cnt;
    reg [16:0] byte_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_WAIT; sec_cnt<=0; byte_addr<=0;
            rd_req_o<=0; rd_addr_o<=0;
            fb_wr_en_o<=0; fb_wr_addr_o<=0; fb_wr_data_o<=0;
            load_done_o<=0; load_error_o<=0;
        end else begin
            rd_req_o   <= 0;
            fb_wr_en_o <= 0;
            load_done_o<= 0;

            if (sd_error_i) begin state <= S_ERR; load_error_o <= 1; end
            else case (state)
                S_WAIT: if (init_done_i) begin sec_cnt<=0; byte_addr<=0; state<=S_NEXT; end
                S_NEXT: begin
                    if (sec_cnt >= TOTAL_SECTORS) state <= S_DONE;
                    else begin rd_addr_o <= IMAGE_START_SECTOR + {22'd0,sec_cnt}; state <= S_REQ; end
                end
                S_REQ:  begin rd_req_o <= 1; state <= S_READ; end
                S_READ: begin
                    if (rd_valid_i) begin
                        fb_wr_en_o<=1; fb_wr_addr_o<=byte_addr;
                        fb_wr_data_o<=rd_data_i; byte_addr<=byte_addr+1;
                    end
                    if (rd_done_i) begin sec_cnt<=sec_cnt+1; state<=S_NEXT; end
                end
                S_DONE: load_done_o <= 1;
                S_ERR:  load_error_o<= 1;
            endcase
        end
    end
endmodule
