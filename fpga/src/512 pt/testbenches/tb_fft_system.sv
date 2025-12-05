`timescale 1ns / 1ps

module tb_fft_system;

    // =============================================================
    // 1. Signals & Constants
    // =============================================================
    logic clk;          // 12 MHz System Clock
    logic reset;
    
    // SPI Interface Signals
    logic sck;
    logic sdi;          // MOSI (Data into FPGA)
    logic sdo;          // MISO (Data out of FPGA)
    
    // Debug/Status Signals
    logic done;         // FFT Done signal
    
    // Clock Periods
    localparam CLK_PERIOD = 83.33;  // 12 MHz (~83.33 ns)
    localparam SCK_PERIOD = 2000;   // 500 kHz (2000 ns) - SPI Clock

    // =============================================================
    // 2. DUT Instantiation
    // =============================================================
    fft dut (
        .clk(clk),
        .reset(reset),
        .full_reset(reset), // Connected to main reset
        .sck(sck),
        .sdi(sdi),
        .sdo(sdo),
        .done(done)
    );

    // =============================================================
    // 3. Clock Generation
    // =============================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =============================================================
    // 4. Main Stimulus
    // =============================================================
    initial begin
        // --- Initialize ---
        // Active Low Reset: Start at 0 (Reset Active)
        reset = 0;       
        sck = 0;
        sdi = 0;
        
        // --- Hold Reset ---
        #(10 * CLK_PERIOD); 
        
        // --- Release Reset ---
        reset = 1;       
        #(10 * CLK_PERIOD);

        $display("Starting Simulation: Filling Buffer with 512 samples...");

        // --- Send 512 Bytes of Dummy Data ---
        // Based on your RTL, the buffer takes 8-bit words
        for (int i = 0; i < 512; i++) begin
            // Send a sawtooth wave or simple counter value
            send_spi_byte(i[7:0]); 
        end

        $display("Buffer Filled. Waiting for FFT to start processing...");

        // --- Wait for FFT to Complete ---
        fork
            begin: wait_for_done
                wait(done);
                $display("SUCCESS: FFT Finished (done signal went high)!");
            end
            begin: timeout
                // Timeout safety net (Increased)
                repeat(500000) @(posedge clk);
                $display("ERROR: Timeout waiting for FFT to finish.");
                $stop;
            end
        join_any
        disable fork; // Kill the timeout if done triggers first

        // --- Post-Processing Readout Phase ---
        $display("Keeping simulation alive to observe data readout...");
        
        // 1. Wait for the FFT to write its results to RAM (Needs 512 cycles)
        // We wait 2000 cycles just to be absolutely sure the bus is released.
        repeat(2000) @(posedge clk); 

        $display("Starting SPI Readout (Toggling SCK)...");

        // 2. Toggle SCK to read out data via SDO
        // We will read 50 full 32-bit words to verify output stream.
        // (Increase 'k < 50' to 'k < 512' to read the full buffer)
        for (int k = 0; k < 50; k++) begin
            // Read one full 32-bit word
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                sck = 0;
                #(SCK_PERIOD/2);
                
                sck = 1; // Rising edge (FPGA shifts out next bit)
                #(SCK_PERIOD/2);
            end
            
            // Small gap between words to match microcontroller behavior
            #(SCK_PERIOD);
        end

        // Finish simulation (Extended buffer time)
        #(5000 * CLK_PERIOD);
        $stop;
    end

    // =============================================================
    // 5. Helper Task: Send SPI Byte
    // =============================================================
    task send_spi_byte(input logic [7:0] data);
        integer bit_idx;
        begin
            // Setup data before first rising edge
            for (bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                sdi = data[bit_idx]; // Set Data (MSB First)
                
                #(SCK_PERIOD/2);     // Wait half cycle
                sck = 1;             // SCK Rising Edge (RTL samples here)
                
                #(SCK_PERIOD/2);     // Wait half cycle
                sck = 0;             // SCK Falling Edge
            end
            
            // Small gap between words
            #(SCK_PERIOD); 
        end
    endtask

    // =============================================================
    // 6. BACKDOOR MONITOR (Prints Internal FFT Results)
    // =============================================================
    // This block spies on the internal signals to verify calculation correctness
    // independent of the SPI readout logic.
    initial begin
        wait(dut.done);
        
        // Wait a tiny bit for the output logic to settle
        @(posedge dut.slow_clk);
        
        $display("\n============================================================");
        $display(" PROOF OF LIFE: Internal FFT Results (Real + Imaginary) ");
        $display("============================================================");

        // Loop through the 512 output cycles
        for (int i = 0; i < 512; i++) begin
            logic signed [15:0] real_part;
            logic signed [15:0] imag_part;
            
            // Peek directly into the FFT unit's output wire
            real_part = dut.fft_unit.data_out[31:16];
            imag_part = dut.fft_unit.data_out[15:0];

            // Print all values (comment out 'if' to see zeros)
            if (real_part != 0 || imag_part != 0) begin
                $display("Bin %03d:  %6d  + j %6d", i, real_part, imag_part);
            end

            // Wait for the next value to appear
            @(posedge dut.slow_clk);
        end
        $display("============================================================\n");
    end

endmodule