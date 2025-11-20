`timescale 1ns/1ps

module fft_tb #(parameter M = 9, WIDTH = 16, POINTS = 2**M)();

    logic clk, reset;
    logic start, load, done;
    
    // Data signals
    logic [M-1:0]       rd_adr;
    logic [2*WIDTH-1:0] rd;      // Input to FFT
    logic [2*WIDTH-1:0] wd;      // Output from FFT
    
    // Testbench variables
    logic [31:0]        idx, out_idx;
    logic [31:0]        idx_counter;
    
    logic [7:0]         input_data_8bit [0:POINTS-1]; 
    logic [31:0]        expected_out [0:POINTS-1];
    logic [31:0]        expected_val;

    logic signed [15:0] expected_re, expected_im;
    logic signed [15:0] wd_re, wd_im;
    integer f;

    fft #(WIDTH, M) dut (.clk(clk), .reset(reset), .start(start), .load(load), .rd_adr(rd_adr), .rd(rd), .wd(wd), .done(done));


    always begin
        clk = 1; #5; clk = 0; #5; 
    end


    initial begin
        $readmemh("simulation/test_in_512.memh", input_data_8bit);
        $readmemh("simulation/test_out_512.memh", expected_out);
        
        f = $fopen("simulation/simulation_results.txt", "w");
        idx_counter = 0; 
        out_idx = 0;
        reset = 1; 
        #100; 
        reset = 0;
    end

    // --- 6. Load / Start Logic ---
    // We simulate the behavior of your SPI adapter here.
    // It drives 'load' high for 512 cycles, then pulses 'start'.
    always @(posedge clk) begin
        if (!reset) begin
            if (idx_counter <= POINTS) begin
                idx_counter <= idx_counter + 1;
            end
        end
    end

    assign load = (idx_counter < POINTS); // High for 0 to 511
    assign start = (idx_counter == POINTS); // High at 512

    // Drive Input Data
    // We simulate the padding: {9'b0, data[7:1], 16'b0} (The "Safe" Shift)
    // Or standard padding: {8'b0, data, 16'b0}
    assign rd_adr = idx_counter[M-1:0];
    assign rd = {8'b0, input_data_8bit[idx_counter], 16'b0}; 

    // --- 7. Verification Logic ---
    
    // Compare outputs when 'done' is high
    always @(posedge clk) begin
        if (done) begin
            if (out_idx < POINTS) begin
                // Fetch expected value
                expected_val = expected_out[out_idx];
                expected_re = expected_val[31:16];
                expected_im = expected_val[15:0];
                
                // Fetch actual value
                wd_re = wd[31:16];
                wd_im = wd[15:0];

                // Write to log
                $fwrite(f, "Idx %d: Expected %d + j%d | Got %d + j%d\n", 
                        out_idx, expected_re, expected_im, wd_re, wd_im);

                // Simple Check (Allowing for small rounding errors +/- 2)
                if ((wd_re > expected_re + 2) || (wd_re < expected_re - 2) ||
                    (wd_im > expected_im + 2) || (wd_im < expected_im - 2)) begin
                    
                    $display("ERROR @ %d: Exp %d+j%d, Got %d+j%d", 
                             out_idx, expected_re, expected_im, wd_re, wd_im);
                end

                out_idx <= out_idx + 1;
            end else begin
                $display("FFT Simulation Complete. Results written to file.");
                $fclose(f);
                $stop;
            end
        end
    end

endmodule