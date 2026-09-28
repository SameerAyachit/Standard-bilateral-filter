`timescale 1ns/1ps

module bilateral_filter_tb;

    // Parameters
    parameter IMAGE_WIDTH  = 256;
    parameter IMAGE_HEIGHT = 256;
    parameter PIXEL_WIDTH  = 8;
    parameter K = 5;
    parameter CLK_PERIOD = 10;  // 100MHz clock
    
    // Signals
    reg                     clk;
    reg                     rstn;
    reg                     valid_in;
    reg  [PIXEL_WIDTH-1:0]  pixel_in;
    wire                    valid_out;
    wire [PIXEL_WIDTH-1:0]  pixel_out;
    
    // Memory for input/output images
    reg [PIXEL_WIDTH-1:0] input_image [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1];
    reg [PIXEL_WIDTH-1:0] output_image [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1];
    
    // Test control
    integer i, j;
    integer input_row, input_col;
    integer output_row, output_col;
    integer output_count;
    integer file_handle;
    
    // Instantiate DUT
    bilateral_filter #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .K(K)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .valid_in(valid_in),
        .pixel_in(pixel_in),
        .valid_out(valid_out),
        .pixel_out(pixel_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Initialize input image (can load from file or generate synthetic)
    initial begin
        // Option 1: Load from file
        // $readmemh("input_image.hex", input_image);
        
        // Option 2: Generate synthetic test pattern
        for (i = 0; i < IMAGE_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMAGE_WIDTH; j = j + 1) begin
                // Simple gradient pattern with some edges
                if (i < IMAGE_HEIGHT/4)
                    input_image[i][j] = 8'd50;
                else if (i < IMAGE_HEIGHT/2)
                    input_image[i][j] = 8'd100 + (j % 50);
                else if (i < 3*IMAGE_HEIGHT/4)
                    input_image[i][j] = 8'd150;
                else
                    input_image[i][j] = 8'd200 + ((i+j) % 30);
            end
        end
        
        // Add some noise
        for (i = 0; i < 100; i = i + 1) begin
            input_image[$urandom % IMAGE_HEIGHT][$urandom % IMAGE_WIDTH] = $urandom % 256;
        end
    end
    
    // Capture output
    always @(posedge clk) begin
        if (valid_out) begin
            output_image[output_row][output_col] = pixel_out;
            
            // Advance output position
            if (output_col == IMAGE_WIDTH - 1) begin
                output_col = 0;
                output_row = output_row + 1;
            end else begin
                output_col = output_col + 1;
            end
            
            output_count = output_count + 1;
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize
        rstn = 0;
        valid_in = 0;
        pixel_in = 0;
        input_row = 0;
        input_col = 0;
        output_row = 0;
        output_col = 0;
        output_count = 0;
        
        // Create output files
        $display("==============================================");
        $display("Bilateral Filter Testbench");
        $display("Image size: %0dx%0d", IMAGE_WIDTH, IMAGE_HEIGHT);
        $display("Filter size: %0dx%0d", K, K);
        $display("==============================================");
        
        // Reset
        repeat(10) @(posedge clk);
        rstn = 1;
        repeat(5) @(posedge clk);
        
        $display("[%0t] Starting image streaming...", $time);
        
        // Stream input image
        for (i = 0; i < IMAGE_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMAGE_WIDTH; j = j + 1) begin
                @(posedge clk);
                valid_in = 1;
                pixel_in = input_image[i][j];
            end
        end
        
        @(posedge clk);
        valid_in = 0;
        
        $display("[%0t] Input streaming complete", $time);
        
        // Wait for all outputs (account for latency)
        // Expected outputs = (IMAGE_HEIGHT - K + 1) * (IMAGE_WIDTH - K + 1)
        while (output_count < (IMAGE_HEIGHT - K + 1) * (IMAGE_WIDTH - K + 1)) begin
            @(posedge clk);
        end
        
        $display("[%0t] Output capture complete", $time);
        $display("Total output pixels: %0d", output_count);
        
        // Save results
        $display("[%0t] Writing output files...", $time);
        
        // Write input image
        file_handle = $fopen("input_image.txt", "w");
        for (i = 0; i < IMAGE_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMAGE_WIDTH; j = j + 1) begin
                $fwrite(file_handle, "%3d ", input_image[i][j]);
            end
            $fwrite(file_handle, "\n");
        end
        $fclose(file_handle);
        
        // Write output image
        file_handle = $fopen("output_image.txt", "w");
        for (i = 0; i < IMAGE_HEIGHT - K + 1; i = i + 1) begin
            for (j = 0; j < IMAGE_WIDTH - K + 1; j = j + 1) begin
                $fwrite(file_handle, "%3d ", output_image[i][j]);
            end
            $fwrite(file_handle, "\n");
        end
        $fclose(file_handle);
        
        // Write hex format for easy loading
        file_handle = $fopen("output_image.hex", "w");
        for (i = 0; i < IMAGE_HEIGHT - K + 1; i = i + 1) begin
            for (j = 0; j < IMAGE_WIDTH - K + 1; j = j + 1) begin
                $fwrite(file_handle, "%02h\n", output_image[i][j]);
            end
        end
        $fclose(file_handle);
        
        $display("==============================================");
        $display("Simulation complete!");
        $display("Output files generated:");
        $display("  - input_image.txt");
        $display("  - output_image.txt");
        $display("  - output_image.hex");
        $display("==============================================");
        
        #1000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * IMAGE_WIDTH * IMAGE_HEIGHT * 4);  // 4x expected time
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // Monitor progress
    integer last_percentage = -1;
    integer current_percentage;
    always @(posedge clk) begin
        if (valid_in) begin
            current_percentage = (input_row * IMAGE_WIDTH + input_col) * 100 / (IMAGE_WIDTH * IMAGE_HEIGHT);
            if (current_percentage != last_percentage && current_percentage % 10 == 0) begin
                $display("[%0t] Input progress: %0d%%", $time, current_percentage);
                last_percentage = current_percentage;
            end
            
            // Track input position
            if (input_col == IMAGE_WIDTH - 1) begin
                input_col = 0;
                input_row = input_row + 1;
            end else begin
                input_col = input_col + 1;
            end
        end
    end
    
    // Generate VCD for waveform viewing
    initial begin
        $dumpfile("bilateral_filter.vcd");
        $dumpvars(0, bilateral_filter_tb);
    end

endmodule