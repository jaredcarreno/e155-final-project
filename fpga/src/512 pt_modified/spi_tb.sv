`timescale 1ns/1ps

module spi_tb();
    // 1. Signals
    logic sck = 0;
    logic sdi = 0;
    logic reset = 0;
    logic clk = 0; // System clock
    logic sdo;
    
    // Internal probes to see into the module
    logic [31:0] data_to_fft;
    logic        start_fft;

    // 2. Instantiate Your SPI Module
    // Ensure this matches your file (spi_fft_buffer.sv)
    spi_fft_buffer dut (
        .sck(sck), 
        .sdi(sdi), 
        .reset(reset), 
        .sdo(sdo), 
        .clk(clk),
        
        // We probe these to check if the write happened
        .data_to_fft(data_to_fft),
        .start_fft(start_fft),
        
        // Dummy connections for unused ports in this test
        .data_from_fft(32'hDEADBEEF), 
        .fft_read_addr(9'h0),  // Important: We are reading from address 0
        .fft_write_addr(9'h0), 
        .fft_write_en(0)
    );

    // 3. Clock Generation (e.g., 48 MHz)
    // 48MHz = ~20.8ns period -> Toggle every 10.4ns
    always #10.4 clk = ~clk; 

    // 4. SPI Task: Sends 8 bits (MSB First)
    task send_spi_byte(input logic [7:0] byte_in);
        integer i;
        for (i=7; i>=0; i=i-1) begin
            sdi = byte_in[i]; // Set Data
            #100;             // Setup time (slow SPI clock for safety)
            sck = 1;          // Clock High
            #100;
            sck = 0;          // Clock Low (FPGA captures on rising edge usually, let's toggle safely)
            #100;
        end
    endtask

    // 5. The Test Sequence
    initial begin
        // --- INITIALIZATION ---
        $display("Starting Simulation...");
        reset = 1; 
        #100; 
        reset = 0; 
        #100;

        // --- TEST CASE: Send Value 100 (0x64) Left-Shifted ---
        // We want to send 16 bits total: 0x6400
        // High Byte: 0x64
        // Low Byte:  0x00
        
        $display("Sending 0x6400 via SPI...");
        
        send_spi_byte(8'h64); // Send High Byte
        send_spi_byte(8'h00); // Send Low Byte
        
        // --- CRITICAL FIX: WAIT FOR RAM ---
        // The write enable (buf_we) happens on the fast system clock (clk).
        // We need to wait a few system clock cycles for the data to latch into RAM.
        repeat(10) @(posedge clk); 
        
        // --- VERIFY ---
        // The DUT is hardwired to read from addr 0 (.fft_read_addr(0)).
        // Since we just wrote the first word, it should be at address 0.
        // Expected Logic:
        // Input: 16'h6400
        // Padding: 16'h0000
        // Result: 32'h64000000
        
        if (data_to_fft === 32'h64000000) begin
            $display("---------------------------------------------------");
            $display("SUCCESS: FPGA captured 0x6400 and padded it correctly!");
            $display("Read Back: %h", data_to_fft);
            $display("---------------------------------------------------");
        end else begin
            $display("---------------------------------------------------");
            $display("FAILURE: FPGA got %h", data_to_fft);
            $display("Expected: 64000000");
            
            if (data_to_fft === 32'bx) 
                $display("Debug Hint: Output is 'x'. RAM might not be initialized or write enable failed.");
            else 
                $display("Debug Hint: Data is wrong. Check bit ordering or shift logic.");
            $display("---------------------------------------------------");
        end

        $stop;
    end
endmodule