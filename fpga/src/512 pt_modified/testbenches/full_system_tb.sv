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
    logic done; 

    // Memory Arrays to hold file data
    logic [31:0] input_file_data [0:511];
    logic [31:0] expected_out_data [0:511];
    
    // DEBUG: Array to capture the "Raw" output directly from the FFT Core
    logic [31:0] fft_core_capture [0:511]; 
    
    // File Handles
    integer f_dump;
    
    // Counters
    integer i, errors;
    logic [15:0] sample_to_send;
    logic [31:0] received_sample;

    // Instantiate Top-Level FFT Module
    fft dut (
        .clk(clk),
        .reset(reset),
        .full_reset(1'b0), // Tied to 0 (1-bit) to avoid warnings
        .sck(sck),
        .sdi(sdi),
        .sdo(sdo),
        .done(done)
    );

    // 48 MHz System Clock
    always #10.416 clk = ~clk; 

    // =========================================================================
    // 2. DEBUG SNOOPING (Capture FFT Core Output)
    // =========================================================================
    always @(posedge clk) begin
        // When the FFT asserts 'done', it streams data out.
        // We capture it into our testbench array using the Controller's address probe.
        // Note: This relies on the 'out_addr_probe' port we added to fft_controller.sv
        if (dut.fft_unit.done) begin
            fft_core_capture[dut.fft_unit.out_addr_probe] <= dut.fft_unit.data_out;
        end
    end

    // =========================================================================
    // 3. SPI Tasks (The "MCU Driver")
    // =========================================================================

    // Task to SEND 16 bits (Real part) to FPGA
    task mcu_send_sample(input logic [15:0] data);
        integer b;
        for (b = 15; b >= 0; b = b - 1) begin
            sdi = data[b];  // Set Data
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
    // 4. Main Test Routine
    // =========================================================================
    initial begin
        // --- Load Files ---
        // Ensure these files exist in your simulation directory!
        $readmemh("test_in_512.memh", input_file_data);
        $readmemh("ideal_test_out_512.memh", expected_out_data);
        
        // --- Open Debug File ---
        f_dump = $fopen("fft_debug_dump.txt", "w");
        $fwrite(f_dump, "Bin | Expected (Py) | FFT Core (Raw) | SPI Rx (Final) | Status\n");
        $fwrite(f_dump, "----|---------------|----------------|----------------|-------\n");

        // --- Initialize ---
        $display("--- Starting Full System Simulation ---");
        reset = 1;
        sck = 0;
        sdi = 0;
        errors = 0;
        
        // Clear capture array
        for (i=0; i<512; i=i+1) fft_core_capture[i] = 32'hDEADBEEF;

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
            
            // Small gap between words (mimics MCU processing time)
            #200; 
        end
        
        // -------------------------------------------------------
        // DEBUG CHECK: Verify RAM Contents
        // -------------------------------------------------------
        $display("[MCU] Upload Complete. Checking Input RAM contents...");
        // Peek into the RAM to ensure SPI wrote correctly
        // Note: Adjust 'dut.spi_inst.input_ram.mem' if your hierarchy names differ
        for (i = 0; i < 5; i++) begin
            $display("RAM[%0d]: %h", i, dut.spi_inst.input_ram.mem[i]);
        end

        $display("[MCU] Waiting for FFT processing...");

        // -------------------------------------------------------
        // PHASE 2: PROCESSING
        // Wait for the 'done' signal to go high
        // -------------------------------------------------------
        fork : wait_for_done
            begin
                wait(done == 1);
                $display("[FPGA] FFT Finished! 'done' signal received.");
                disable wait_for_done;
            end
            begin
                #2000000; // Timeout (approx 2ms simulation time)
                $display("[ERROR] Timeout waiting for done signal!");
                $stop;
            end
        join

        // -------------------------------------------------------
        // PHASE 3: DOWNLOAD (Frequency Domain)
        // Read 512 results back via SPI
        // -------------------------------------------------------
        $display("[MCU] Downloading results...");
        
        // Give FPGA a moment to settle state before reading
        #1000; 

        for (i = 0; i < 512; i = i + 1) begin
            mcu_read_sample(received_sample);
            
            // Log everything to file
            $fwrite(f_dump, "%3d | %h | %h | %h | %s\n", 
                    i, 
                    expected_out_data[i], 
                    fft_core_capture[i], 
                    received_sample,
                    (received_sample === expected_out_data[i]) ? "OK" : "ERR"
            );

            // Compare with Golden Output
            if (received_sample !== expected_out_data[i]) begin
                if (errors < 5) begin
                    $display("Error at Bin %0d: Exp %h | Core %h | SPI %h", 
                             i, expected_out_data[i], fft_core_capture[i], received_sample);
                end
                errors = errors + 1;
            end
        end

        // -------------------------------------------------------
        // REPORTING
        // -------------------------------------------------------
        $fclose(f_dump);

        if (errors == 0) begin
            $display("---------------------------------------------------");
            $display("SUCCESS: Full System Verification Passed!");
            $display("See fft_debug_dump.txt for full log.");
            $display("---------------------------------------------------");
        end else begin
            $display("---------------------------------------------------");
            $display("FAILURE: Found %0d mismatches.", errors);
            $display("See fft_debug_dump.txt for details.");
            $display("---------------------------------------------------");
        end
        
        $stop;
    end

endmodule