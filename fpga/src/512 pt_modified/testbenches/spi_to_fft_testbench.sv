`timescale 1ns/1ps

module spi_to_fft_testbench(); // Renamed to match your file
    // 1. SPI Signals (MCU Side)
    logic sck = 0;
    logic sdi = 0;
    logic reset = 0;
    logic clk = 0; 
    logic sdo;
    
    // 2. FFT Signals (FFT Side)
    logic [31:0] tb_data_from_fft;
    logic [8:0]  tb_fft_write_addr;
    logic        tb_fft_write_en;

    // 3. Probes
    logic [31:0] data_to_fft;
    logic        start_fft;
    
    // 4. Test Variable (MOVED UP HERE)
    logic [15:0] received_val;  // <--- MOVED THIS UP FROM LINE 85

    // 5. Instantiate DUT
    spi_fft_buffer dut (
        .sck(sck), .sdi(sdi), .reset(reset), .sdo(sdo), .clk(clk),
        .data_to_fft(data_to_fft),
        .start_fft(start_fft),
        .data_from_fft(tb_data_from_fft), 
        .fft_write_addr(tb_fft_write_addr),
        .fft_write_en(tb_fft_write_en),
        .fft_read_addr(9'h0) 
    );

    // Clock
    always #10.4 clk = ~clk; 

    // Helper Task
    task read_spi_word(output logic [15:0] result);
        integer i;
        for (i=15; i>=0; i=i-1) begin
            sck = 0; 
            #100;
            sck = 1; // Rising Edge: MCU reads SDO
            result[i] = sdo; // Capture bit
            #100;
        end
        sck = 0;
    endtask

    initial begin
        // --- 1. INITIALIZE ---
        $display("Starting Output Test...");
        reset = 1; 
        tb_fft_write_en = 0;
        #100; 
        reset = 0; 
        #100;

        // --- 2. MOCK THE FFT ---
        $display("FFT Writing 0xAABBCCDD to Output RAM...");
        
        @(posedge clk);
        tb_fft_write_addr = 9'h0;
        tb_data_from_fft  = 32'hAABBCCDD;
        tb_fft_write_en   = 1; // Pulse Write
        @(posedge clk);
        tb_fft_write_en   = 0;
        
        // Wait for RAM to latch
        repeat(4) @(posedge clk);

        // --- 3. MOCK THE MCU ---
        // Variable declaration removed from here
        read_spi_word(received_val);
        
        // --- 4. VERIFY ---
        if (received_val === 16'hAABB) begin
            $display("SUCCESS: Read back correct Upper 16 bits!");
            $display("Sent: AABBCCDD -> Received: %h", received_val);
        end else begin
            $display("FAILURE: Expected AABB, Got %h", received_val);
        end

        $stop;
    end
endmodule