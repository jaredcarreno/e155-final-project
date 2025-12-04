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
    
    // Debug/Status Signals (Add any others from your top module)
    logic done;         // FFT Done signal
    
    // Clock Periods
    localparam CLK_PERIOD = 83.33;  // 12 MHz (~83.33 ns)
    localparam SCK_PERIOD = 2000;   // 500 kHz (2000 ns) - SPI Clock

    // =============================================================
    // 2. DUT Instantiation
    // =============================================================
    // Make sure port names match your TOP LEVEL module exactly!

    fft dut (
        .clk(clk),
        .reset(reset),
        .full_reset(reset), // <--- CONNECT THIS (tie it to the main reset)
        .sck(sck),
        .sdi(sdi),
        .sdo(sdo),
        .done(done)
    );

    // fft dut (
    //     .clk(clk),
    //     .reset(reset),
    //     .sck(sck),
    //     .sdi(sdi),
    //     .sdo(sdo),
    //     .done(done) 
    //     // Add .full_reset(full_reset) if you have it
    // );

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
        reset = 0;
        sck = 0;
        sdi = 0;
        
        // --- Reset Pulse ---
        #(10 * CLK_PERIOD); 
        reset = 1;
        #(10 * CLK_PERIOD);

        $display("Starting Simulation: Filling Buffer with 512 samples...");

        // --- Send 512 Bytes of Dummy Data ---
        // Based on your RTL, the buffer takes 8-bit words (spi_in_shift is [7:0])
        for (int i = 0; i < 512; i++) begin
            // Send a sawtooth wave or simple counter value
            send_spi_byte(i[7:0]); 
        end

        $display("Buffer Filled. Waiting for FFT to start processing...");

        // --- Wait for FFT to Complete ---
        // The FFT takes many cycles. Wait for 'done' or a timeout.
        fork
            begin: wait_for_done
                wait(done);
                $display("SUCCESS: FFT Finished (done signal went high)!");
            end
            begin: timeout
                // Wait enough time for FFT (e.g., 512 * log2(512) cycles + overhead)
                // 100,000 clk cycles is usually plenty for a small FFT
                repeat(100000) @(posedge clk);
                $display("ERROR: Timeout waiting for FFT to finish.");
                $stop;
            end
        join_any
        disable fork; // Kill the timeout if done triggers first

        // Finish simulation
        #(100 * CLK_PERIOD);
        $stop;
    end

    // =============================================================
    // 5. Helper Task: Send SPI Byte
    // =============================================================
    task send_spi_byte(input logic [7:0] data);
        integer bit_idx;
        begin
            // Setup data before first rising edge (Mode 0 behavior)
            // Your RTL samples on RISING edge of SCK.
            
            for (bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                sdi = data[bit_idx]; // Set Data (MSB First)
                
                #(SCK_PERIOD/2);     // Wait half cycle
                sck = 1;             // SCK Rising Edge (RTL samples here)
                
                #(SCK_PERIOD/2);     // Wait half cycle
                sck = 0;             // SCK Falling Edge
            end
            
            // Small gap between words (optional, but realistic)
            #(SCK_PERIOD); 
        end
    endtask

    // =============================================================
    // 6. BACKDOOR MONITOR (Prints FFT Results directly)
    // =============================================================
    initial begin
        // 1. Wait until the FFT indicates it is done
        wait(dut.done);
        
        // 2. Wait a tiny bit for the output logic to settle
        // The FFT unloads 1 result per 'slow_clk' edge
        @(posedge dut.slow_clk);
        
        $display("\n============================================================");
        $display(" PROOF OF LIFE: Internal FFT Results (Real + Imaginary) ");
        $display("============================================================");

        // 3. Loop through the 512 output cycles
        for (int i = 0; i < 512; i++) begin
            // We peek directly into the FFT unit's output wire
            // Hierarchy: dut -> fft_unit -> data_out
            logic signed [15:0] real_part;
            logic signed [15:0] imag_part;
            
            real_part = dut.fft_unit.data_out[31:16];
            imag_part = dut.fft_unit.data_out[15:0];

            // Only print non-zero values to keep the log readable (optional)
            if (real_part != 0 || imag_part != 0) begin
                $display("Bin %03d:  %6d  + j %6d", i, real_part, imag_part);
            end

            // Wait for the next value to appear
            @(posedge dut.slow_clk);
        end
        $display("============================================================\n");
    end

endmodule