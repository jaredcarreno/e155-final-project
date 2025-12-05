// Author(s): Jared Carreno, Shreya Jampana, Emma Angel
// Date:
// Purpose: Top-level module for UPduino v3.1.
//          Connects SPI interface to the 512-point FFT core.

module top #(parameter M = 9, WIDTH = 16)(
    input logic sck,    // SPI Clock
    input logic sdi,    // SPI Data In
    input logic reset,  // System Reset
    output logic sdo    // SPI Data Out
);

    // ============================================================
    // 1. CLOCK GENERATION
    // ============================================================
    logic clk_fast; // 48 MHz (Used for RAM Multiplexing)
    logic clk_slow; // 24 MHz (Used for FFT Logic)
    
    // HSOSC "0b00" = 48 MHz
    HSOSC #("0b00") hf_osc (1'b1, 1'b1, clk_fast);
    
    // Generate clean Divide-by-2 Slow Clock
    always_ff @(posedge clk_fast) begin
        if (reset) clk_slow <= 0;
        else       clk_slow <= ~clk_slow;
    end


    // ============================================================
    // 2. INTERNAL WIRES
    // ============================================================
    
    // FFT Control & Data
    logic core_start;       
    logic core_load;        
    logic core_done;        
    logic [M-1:0]       core_rd_adr;  
    logic [2*WIDTH-1:0] core_rd_data; 
    logic [2*WIDTH-1:0] core_wd_data; 

    // SPI & Buffer signals
    logic dataReady;       // High when input packet is full
    logic buf_ready;       // High when output buffer is full
    logic buf_empty;       // High when output buffer is empty
    
    // Packet Wires
    // Input: 512 samples * 8 bits = 4096 bits
    logic [4095:0]  spi_in_packet;
    // Output: 512 samples * 16 bits (Truncated) = 8192 bits
    logic [8191:0]  spi_out_packet;


    // ============================================================
    // 3. INSTANTIATIONS
    // ============================================================

    // 1. SPI Physical Interface
    // Handles SCK/SDI/SDO and shift registers
    fft_spi spi_phy (
        .sck(sck), 
        .reset(reset), 
        .sdi(sdi), 
        .sdo(sdo), 
        .fft_input(spi_in_packet), 
        .fft_loaded(dataReady), 
        .fft_output(spi_out_packet)
    );

    // 2. Input Buffer (Adapter)
    // Pads 8-bit SPI data to 32-bit Complex for the Core
    fft_in_flop_4096 input_buf (
        .clk(clk_slow), 
        .reset(reset),
        .fft_in4096(spi_in_packet),
        .fft_processing(1'b0), 
        .fft_loaded(dataReady),
        .fft_done(core_done),
        .out_buf_empty(1'b0), 
        .out_buf_ready(1'b0),
        .fft_in32(core_rd_data),
        .fft_load(core_load),
        .fft_start(core_start),
        .idx(core_rd_adr)
    );

    // 3. Output Buffer (Adapter)
    // Truncates 32-bit Core result to 16-bit (8 Re + 8 Im) for SPI
    fft_out_flop_truncating output_buf (
        .clk(clk_slow), 
        .reset(reset),
        .fft_out32(core_wd_data),
        .fft_start(core_start), 
        .fft_done(core_done),
        .fft_out_packet(spi_out_packet),
        .buf_ready(buf_ready),
        .buf_empty(buf_empty)
    );

    // 4. FFT Core
    // Runs on clk_slow (Logic) but uses clk_fast for RAM access
    fft #(WIDTH, M) fft_core (
        .clk_fast(clk_fast), 
        .clk_slow(clk_slow), 
        .reset(reset), 
        .start(core_start), 
        .load(core_load), 
        .rd_adr(core_rd_adr), 
        .rd(core_rd_data), 
        .wd(core_wd_data), 
        .done(core_done)
    );

endmodule