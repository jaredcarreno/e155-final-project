`timescale 1ns/1ps

module full_system_tb();

    // =========================================================================
    // 1. Signals & Setup
    // =========================================================================
    logic clk = 0;
    logic reset = 0;
    logic sck = 0;
    logic sdi = 0;
    logic sdo;
    logic done; // The "Interrupt" / LED signal

    // Memory Arrays to hold file data
    logic [31:0] input_file_data [0:511];
    logic [31:0] expected_out_data [0:511];
    
    // Counters
    integer i, j, errors;
    logic [15:0] sample_to_send;
    logic [31:0] received_sample;

    // Instantiate Top-Level FFT Module
    // (This contains both the SPI Buffer and the FFT Controller)
    fft dut (
        .clk(clk),
        .reset(reset),
        .full_reset(0),
        .sck(sck),
        .sdi(sdi),
        .sdo(sdo),
        .done(done)
    );

    // 48 MHz System Clock
    always #10.416 clk = ~clk; 

    // =========================================================================
    // 2. SPI Tasks (The "MCU Driver")
    // =========================================================================

    // Task to SEND 16 bits (Real part) to FPGA
    task mcu_send_sample(input logic [15:0] data);
        integer b;
        for (b = 15; b >= 0; b = b - 1) begin
            sdi = data[b];  // Setup Data
            #100;           // Setup time
            sck = 1;        // Clock High (FPGA captures)
            #100;
            sck = 0;        // Clock Low
            #100;
        end
    endtask

    // Task to READ 32 bits (Complex result) from FPGA
    task mcu_read_sample(output logic [31:0] data);
        integer b;
        for (b = 31; b >= 0; b = b - 1) begin
            sck = 0;        
            #100;
            sck = 1;        // Clock High (MCU reads)
            data[b] = sdo;  // Capture Data
            #100;
        end
        sck = 0;
        #100; // Gap between words
    endtask

    // =========================================================================
    // 3. The Main Test Routine
    // =========================================================================
    initial begin
        // --- Load Files ---
        $readmemh("test_in_512.memh", input_file_data);
        $readmemh("ideal_test_out_512.memh", expected_out_data);
        
        // --- Initialize ---
        $display("--- Starting Full System Simulation ---");
        reset = 1;
        sck = 0;
        sdi = 0;
        errors = 0;
        #200;
        reset = 0;
        #200;

        // -------------------------------------------------------
        // PHASE 1: UPLOAD (Time Domain)
        // Stream 512 samples into the FPGA via SPI
        // -------------------------------------------------------
        $display("[MCU] Uploading 512 samples...");
        
        for (i = 0; i < 512; i = i + 1) begin
            // The file has 32-bit hex: RRRRIIII (e.g., 00640000)
            // The FPGA now expects 16-bit inputs (Real only).
            // So we slice the top 16 bits [31:16].
            sample_to_send = input_file_data[i][31:16];
            
            mcu_send_sample(sample_to_send);
            
            // Small gap between words (optional, mimics real MCU)
            #200; 
        end
        
        $display("[MCU] Upload Complete. Waiting for FFT processing...");

        // -------------------------------------------------------
        // PHASE 2: PROCESSING
        // Wait for the 'done' signal to go high
        // -------------------------------------------------------
        
        // Timeout watchdog in case it hangs
        fork : wait_for_done
            begin
                wait(done == 1);
                $display("[FPGA] FFT Finished! 'done' signal received.");
                disable wait_for_done;
            end
            begin
                #1000000; // Wait 1ms (plenty of time for 2300 cycles @ 48MHz)
                $display("[ERROR] Timeout waiting for done signal!");
                $stop;
            end
        join

        // -------------------------------------------------------
        // PHASE 3: DOWNLOAD (Frequency Domain)
        // Read 512 results back via SPI
        // -------------------------------------------------------
        $display("[MCU] Downloading results...");
        
        // Give FPGA a moment to settle state
        #1000; 

        for (i = 0; i < 512; i = i + 1) begin
            mcu_read_sample(received_sample);
            
            // Compare with Golden Output
            // Note: Use a mask or tolerance if needed, but exact match is ideal for sim
            if (received_sample !== expected_out_data[i]) begin
                // Basic error printing (limiting spam to first 10 errors)
                if (errors < 10) begin
                    $display("Error at Bin %0d: Exp %h | Got %h", 
                             i, expected_out_data[i], received_sample);
                end
                errors = errors + 1;
            end
        end

        // -------------------------------------------------------
        // REPORTING
        // -------------------------------------------------------
        if (errors == 0) begin
            $display("---------------------------------------------------");
            $display("SUCCESS: Full System Verification Passed!");
            $display("SPI In -> RAM -> FFT -> RAM -> SPI Out works perfectly.");
            $display("---------------------------------------------------");
        end else begin
            $display("---------------------------------------------------");
            $display("FAILURE: Found %0d mismatches.", errors);
            $display("---------------------------------------------------");
        end
        
        $stop;
    end

endmodule