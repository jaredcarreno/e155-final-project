//
// top.sv
//
module top #(parameter M = 9, WIDTH = 16)(
    input logic sck,    // SPI Clock
    input logic sdi,    // SPI Data In
    input logic reset,  // System Reset
    output logic sdo    // SPI Data Out
);

    logic clk;
    // HSOSC order: CLKHFPU, CLKHFEN, CLKHF
    HSOSC #("0b01") hf_osc (1'b1, 1'b1, clk);
    
    // FFT Control & Data
    logic core_start;       
    logic core_load;        
    logic core_done;        
    logic [M-1:0]       core_rd_adr;  
    logic [2*WIDTH-1:0] core_rd_data; 
    logic [2*WIDTH-1:0] core_wd_data; 

    // SPI & Buffer signals
    logic dataReady;       // High when input packet is full
    logic buf_ready;       // High when output buffer is full (unused)
    logic buf_empty;       // High when output buffer is empty (unused)
    
    logic [4095:0]  spi_in_packet;   // 4096 bits IN
    logic [8191:0]  spi_out_packet;  // 8192 bits OUT

    // SPI
    // Port Order from spi.sv:
    // (sck, reset, sdi, sdo, fft_input, fft_loaded, fft_output)
    fft_spi spi(sck, reset, sdi, sdo, spi_in_packet, dataReady, spi_out_packet);

    // Input Buffer (4096-bit -> 32-bit)
    // Port Order from spi.sv:
    // (clk, reset, fft_in4096, fft_processing, fft_loaded, fft_done, 
    //  out_buf_empty, out_buf_ready, fft_in32, fft_load, fft_start, idx)
    fft_in_flop_4096 input_buffer(clk, reset, spi_in_packet, 1'b0, dataReady, core_done, 1'b0, 1'b0, core_rd_data, core_load, core_start, core_rd_adr);

    // Output Buffer (32-bit -> 8192-bit)
    // Port Order from spi.sv:
    // (clk, fft_out32, fft_start, fft_done, reset, fft_out8192, buf_ready, buf_empty)
    fft_out_flop_8192 output_buffer(clk, core_wd_data, core_start, core_done, reset, spi_out_packet, buf_ready, buf_empty);

    // FFT Core
    // Port Order from fft.sv:
    // (clk, reset, start, load, rd_adr, rd, wd, done)
    fft fft1(clk, reset, core_start, core_load, core_rd_adr, core_rd_data, core_wd_data, core_done);

endmodule