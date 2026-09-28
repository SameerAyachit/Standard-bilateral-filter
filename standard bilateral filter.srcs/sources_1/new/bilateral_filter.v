`timescale 1ns/1ps

module bilateral_filter #(
    parameter IMAGE_WIDTH  = 256,
    parameter IMAGE_HEIGHT = 256,
    parameter PIXEL_WIDTH  = 8,
    parameter K = 5
)(
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     valid_in,
    input  wire [PIXEL_WIDTH-1:0]   pixel_in,
    output reg                      valid_out,
    output reg  [PIXEL_WIDTH-1:0]   pixel_out
);

    localparam WGT_SCALE = 1024;
    localparam WGT_BITS  = 11;
    localparam LB_ADDR_W = $clog2(IMAGE_WIDTH);
    localparam ROW_BITS  = $clog2(IMAGE_HEIGHT);

    // Line buffers (1 BRAM per row)
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] linebuf0 [0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] linebuf1 [0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] linebuf2 [0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] linebuf3 [0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] linebuf4 [0:IMAGE_WIDTH-1];

    // Row circular buffer index
    reg [2:0] row_ptr = 0;

    // Range LUT (in BRAM)
    (* ram_style = "block" *) reg [WGT_BITS-1:0] range_lut [0:255];

    // 5x5 Gaussian kernel (registers, no BRAM needed)
    reg [WGT_BITS-1:0] ws [0:K-1][0:K-1];

    // Coordinates
    reg [LB_ADDR_W-1:0] col_in;
    reg [ROW_BITS-1:0]  row_in;

    // Computation register arrays (pipelined to ensure DSP usage)
    reg [7:0] window  [0:K-1][0:K-1];
    reg [WGT_BITS-1:0] spatw_pipe [0:K*K-1];
    reg [WGT_BITS-1:0] rangew_pipe[0:K*K-1];
    (* use_dsp = "yes" *) reg [21:0] dweight[0:K*K-1];
    (* use_dsp = "yes" *) reg [31:0] dmul   [0:K*K-1];

    reg [PIXEL_WIDTH-1:0] center_pix;
    reg [31:0] numerator, denominator, result;
    reg compute_valid;
    reg [LB_ADDR_W-1:0] col_out;
    reg [ROW_BITS-1:0]  row_out;

    integer i, j, idx;

    // Gaussian weights initialization (normalized for 1024 sum)
    initial begin
        $readmemh("range_lut.mem", range_lut);
        // Your 5x5 Gaussian kernel initialization
        ws[0][0]=7;   ws[0][1]=26;  ws[0][2]=41;  ws[0][3]=26;  ws[0][4]=7;
        ws[1][0]=26;  ws[1][1]=100; ws[1][2]=159; ws[1][3]=100; ws[1][4]=26;
        ws[2][0]=41;  ws[2][1]=159; ws[2][2]=253; ws[2][3]=159; ws[2][4]=41;
        ws[3][0]=26;  ws[3][1]=100; ws[3][2]=159; ws[3][3]=100; ws[3][4]=26;
        ws[4][0]=7;   ws[4][1]=26;  ws[4][2]=41;  ws[4][3]=26;  ws[4][4]=7;
    end

    // Input pixel > Line buffer logic (rotating pointer BRAM)
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            row_in <= 0;
            col_in <= 0;
            row_ptr <= 0;
        end else if (valid_in) begin
            // Insert into circular buffer
            case (row_ptr)
                0: linebuf0[col_in] <= pixel_in;
                1: linebuf1[col_in] <= pixel_in;
                2: linebuf2[col_in] <= pixel_in;
                3: linebuf3[col_in] <= pixel_in;
                4: linebuf4[col_in] <= pixel_in;
            endcase

            // Advance input column and row
            if (col_in == IMAGE_WIDTH-1) begin
                col_in <= 0;
                row_in <= row_in + 1;
                row_ptr <= (row_ptr + 1) % K;
            end else begin
                col_in <= col_in + 1;
            end

            // Set valid pipeline for output (K/2 delay)
            if (row_in >= K-1 && col_in >= K-1) begin
                compute_valid <= 1;
                col_out <= col_in - (K/2);
                row_out <= row_in - (K/2);
            end else begin
                compute_valid <= 0;
            end
        end else begin
            compute_valid <= 0;
        end
    end

    // Extract window and process with pipelined multipliers (DSP usage)
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            valid_out <= 0;
            pixel_out <= 0;
        end else if (compute_valid) begin
            // Extract window in raster (with circular buffer addressing)
            for (i=0;i<K;i=i+1) begin
                for (j=0;j<K;j=j+1) begin
                    case ((row_ptr+K-i)%K)
                        0: window[i][j] = linebuf0[col_out-K/2+j];
                        1: window[i][j] = linebuf1[col_out-K/2+j];
                        2: window[i][j] = linebuf2[col_out-K/2+j];
                        3: window[i][j] = linebuf3[col_out-K/2+j];
                        4: window[i][j] = linebuf4[col_out-K/2+j];
                    endcase
                end
            end

            // Center pixel
            center_pix = window[K/2][K/2];

            numerator = 0;
            denominator = 0;

            // Form pipelined arrays for DSP usage
            idx = 0;
            for (i=0;i<K;i=i+1) begin
                for (j=0;j<K;j=j+1) begin
                    spatw_pipe[idx]  <= ws[i][j];
                    rangew_pipe[idx] <= range_lut[center_pix > window[i][j] ? center_pix - window[i][j] : window[i][j] - center_pix];
                    dweight[idx]     <= spatw_pipe[idx] * rangew_pipe[idx]; // DSP inference
                    dmul[idx]        <= dweight[idx] * window[i][j];        // DSP inference

                    numerator    = numerator    + dmul[idx];
                    denominator  = denominator  + dweight[idx];
                    idx = idx + 1;
                end
            end

            // Pixel calculation and saturation
            if (denominator == 0) result = center_pix;
            else result = (numerator + (denominator >> 1)) / denominator;

            pixel_out <= (result > 255) ? 8'd255 : result[7:0];
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end
    end

endmodule
