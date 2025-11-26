`timescale 1ns/1ps

module fft_testbench();

    // --- 1. Simulation Parameters ---
    localparam M = 9;              // 9 bits for 512 points
    localparam WIDTH = 16;         // 16-bit precision
    localparam POINTS = 512;       // 2^9

    // --- 2. Signals ---
    logic clk_fast; // Fast clock (Memory Muxing)
    logic clk_slow; // Slow clock (Logic)
    logic reset;
    logic start, load, done;
    
    // Data Signals
    logic [M-1:0]       rd_adr;
    logic [2*WIDTH-1:0] rd;        // Input to FFT (32-bit)
    logic [2*WIDTH-1:0] wd;        // Output from FFT (32-bit)
    
    // Testbench Variables
    integer             idx_counter;
    integer             out_idx;
    integer             f;
    integer             watchdog;  // Safety counter
    
    // Memory Arrays
    logic [7:0]         input_data_8bit [0:POINTS-1];
    logic [31:0]        expected_out [0:POINTS-1];
    logic [31:0]        expected_val;
    
    // Comparison Variables
    logic signed [15:0] exp_re, exp_im, got_re, got_im;

    // --- 3. DUT Instantiation ---
    // Connects to the new FFT Wrapper
    fft #(WIDTH, M) dut (
        .clk_fast(clk_fast),   
        .clk_slow(clk_slow),   
        .reset(reset),
        .start(start),
        .load(load),
        .rd_adr(rd_adr), 
        .rd(rd),         
        .wd(wd),         
        .done(done)
    );

// --- 4. Clock Generation (CORRECTED) ---
    // Fast Clock: 10ns period = 100 MHz
    initial begin
        clk_fast = 0;
        clk_slow = 0; // Initialize to 0 so it doesn't start as X
    end
    
    always #5 clk_fast = ~clk_fast; 

    // Slow Clock: Free running (Does NOT stop during reset)
    // This ensures the DUT sees clock edges while reset is high!
    always @(posedge clk_fast) begin
        #1 clk_slow <= ~clk_slow;
    end

    // --- 5. Setup & File Loading ---
    initial begin
        $display("Loading Simulation Files...");
        
        // Load files
        $readmemh("test_in.memh", input_data_8bit);
        $readmemh("ideal_test_out.memh", expected_out);
        
        // --- CRITICAL FILE CHECK ---
        if (input_data_8bit[0] === 8'bx) begin
            $display("FATAL ERROR: 'test_in.memh' failed to load! (Saw X). Stopping.");
            $stop;
        end
        if (expected_out[0] === 32'bx) begin
            $display("FATAL ERROR: 'ideal_test_out.memh' failed to load! (Saw X). Stopping.");
            $stop;
        end
        $display("Files Loaded Successfully.");

        f = $fopen("simulation_results.txt", "w");

        // Initialize signals
        idx_counter = 0;
        out_idx = 0;
        reset = 1; 
        
        // Hold reset for 200ns
        #200;
        reset = 0; 
    end

    // --- 6. The Driver Logic (Input Feeder) ---
    always @(posedge clk_slow) begin
        if (reset) begin
            idx_counter <= 0;
        end else begin
            if (idx_counter < POINTS) begin
                idx_counter <= idx_counter + 1;
            end
        end
    end

    // Drive Signals
    assign load  = (idx_counter < POINTS);
    assign start = (idx_counter == POINTS);  
    assign rd_adr = idx_counter[M-1:0];

    // Padding Logic: Matches 'spi.sv' padding
    assign rd = (idx_counter < POINTS) ? 
                {8'b0, input_data_8bit[idx_counter[M-1:0]], 16'b0} : 
                32'h0;

    // --- 7. Verification Logic ---
    always @(posedge clk_slow) begin
        if (done && !reset) begin
            if (out_idx < POINTS) begin
                expected_val = expected_out[out_idx];
                exp_re = expected_val[31:16];
                exp_im = expected_val[15:0];
                
                got_re = wd[31:16];
                got_im = wd[15:0];

                // Write to log
                $fwrite(f, "Idx %0d: Exp %d + j%d | Got %d + j%d\n", 
                        out_idx, exp_re, exp_im, got_re, got_im);
                
                // Only check if Expected is NOT X (avoids false failures)
                if (expected_val !== 32'bx) begin
                     // Check for mismatch (Tolerance +/- 5)
                    if ((got_re > exp_re + 5) || (got_re < exp_re - 5) ||
                        (got_im > exp_im + 5) || (got_im < exp_im - 5)) begin
                        
                        $display("ERROR @ Idx %0d: Exp %d+j%d, Got %d+j%d", 
                                 out_idx, exp_re, exp_im, got_re, got_im);
                    end 
                end else begin
                     $display("WARNING @ Idx %0d: Expected value is X (Check ideal_test_out.memh)", out_idx);
                end

                out_idx <= out_idx + 1;
            end else if (out_idx == POINTS) begin
                $display("FFT Simulation Complete. Check simulation_results.txt");
                $fclose(f);
                $stop;
            end
        end
    end
    
    // --- 8. Watchdog Timer ---
    // Failsafe: Stops simulation if it runs too long (e.g., infinite loop)
    initial begin
        watchdog = 0;
        forever begin
            #1000; // Check every 1us
            watchdog = watchdog + 1;
            // 512 points * log2(512) stages * clocks... roughly 1ms max
            if (watchdog > 5000) begin // 5ms timeout
                $display("TIMEOUT: Simulation ran too long without finishing. Check signals.");
                $stop;
            end
        end
    end

endmodule

// `timescale 1ns/1ps

// module fft_testbench();

//     // --- 1. Simulation Parameters ---
//     localparam M = 9;              // 512 Points
//     localparam WIDTH = 16;         // 16-bit precision
//     localparam POINTS = 512;       // 2^9

//     // --- 2. Signals ---
//     logic clk_fast; // Fast clock (Memory Muxing)
//     logic clk_slow; // Slow clock (Logic)
//     logic reset;
//     logic start, load, done;
    
//     // Data Signals
//     logic [M-1:0]       rd_adr;
//     logic [2*WIDTH-1:0] rd;        // Input to FFT (32-bit)
//     logic [2*WIDTH-1:0] wd;        // Output from FFT (32-bit)
    
//     // Testbench Variables
//     integer             idx_counter; 
//     integer             out_idx;     
//     integer             f;           
    
//     // Memory Arrays
//     logic [7:0]         input_data_8bit [0:POINTS-1]; 
//     logic [31:0]        expected_out [0:POINTS-1];
//     logic [31:0]        expected_val;

//     // Comparison Variables
//     logic signed [15:0] exp_re, exp_im, got_re, got_im;

//     // --- 3. DUT Instantiation ---
//     // Connects to your Time-Multiplexed FFT Core
//     fft #(WIDTH, M) dut (
//         .clk_fast(clk_fast),   
//         .clk_slow(clk_slow),   
//         .reset(reset),
//         .start(start),
//         .load(load),
//         .rd_adr(rd_adr), 
//         .rd(rd),         
//         .wd(wd),         
//         .done(done)
//     );

//     // --- 4. Clock Generation ---
//     // Fast Clock: 10ns period = 100 MHz
//     initial clk_fast = 0;
//     always #5 clk_fast = ~clk_fast; 

//     // Slow Clock: Derived from Fast Clock (Divide by 2)
//     // CRITICAL FIX: The '#1' delay offsets the logic clock from the RAM clock
//     // to prevent race conditions during the memory phase switch.
//     always @(posedge clk_fast) begin
//         if (reset) 
//             clk_slow <= 0;
//         else       
//             #1 clk_slow <= ~clk_slow; 
//     end

//     // --- 5. Setup & File Loading ---
//     initial begin
//         // Ensure files are in the simulation directory!
//         $readmemh("test_in.memh", input_data_8bit);
//         $readmemh("ideal_test_out.memh", expected_out);
        
//         f = $fopen("simulation_results.txt", "w");

//         // Initialize signals
//         idx_counter = 0; 
//         out_idx = 0;
//         reset = 1; 
        
//         // Hold reset for 200ns to clear all RAMs/Counters
//         #200;       
//         reset = 0; 
//     end

//     // --- 6. The Driver Logic (Runs on SLOW CLOCK) ---
//     // We drive inputs on the same clock domain the logic uses.
//     always @(posedge clk_slow) begin
//         if (reset) begin
//             idx_counter <= 0;
//         end else begin
//             if (idx_counter <= POINTS) begin
//                 idx_counter <= idx_counter + 1;
//             end
//         end
//     end

//     // Signals
//     assign load  = (idx_counter < POINTS);   
//     assign start = (idx_counter == POINTS);  

//     assign rd_adr = idx_counter[M-1:0];
    
//     // Padding logic: {8'b0, data, 16'b0}
//     // Ternary operator prevents driving X during idle states
//     assign rd = (idx_counter < POINTS) ? 
//                 {8'b0, input_data_8bit[idx_counter[M-1:0]], 16'b0} : 
//                 32'h0;


//     // --- 7. Verification Logic (Runs on SLOW CLOCK) ---
//     always @(posedge clk_slow) begin
//         if (done && !reset) begin
//             if (out_idx < POINTS) begin
//                 expected_val = expected_out[out_idx];
//                 exp_re = expected_val[31:16];
//                 exp_im = expected_val[15:0];
                
//                 got_re = wd[31:16];
//                 got_im = wd[15:0];

//                 $fwrite(f, "Idx %0d: Exp %d + j%d | Got %d + j%d\n", 
//                         out_idx, exp_re, exp_im, got_re, got_im);

//                 // Check for mismatch (Tolerance +/- 5)
//                 if ((got_re > exp_re + 5) || (got_re < exp_re - 5) ||
//                     (got_im > exp_im + 5) || (got_im < exp_im - 5)) begin
                    
//                     $display("ERROR @ Idx %0d: Exp %d+j%d, Got %d+j%d", 
//                              out_idx, exp_re, exp_im, got_re, got_im);
//                 end 

//                 out_idx <= out_idx + 1;
                
//             end else if (out_idx == POINTS) begin
//                 $display("FFT Simulation Complete. Check simulation_results.txt");
//                 $fclose(f);
//                 $stop;
//             end
//         end
//     end

// endmodule