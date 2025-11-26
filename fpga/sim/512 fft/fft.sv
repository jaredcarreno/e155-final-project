// Author(s): Jared Carreno, Shreya Jampana, Emma Angel
// Purpose: FFT Core Wrapper
// This module wraps the 'fft_controller' to match the interface expected by the testbench.

module fft #(parameter width=16, M=9) (
    input logic                clk_fast, // Fast Clock (Memory Muxing)
    input logic                clk_slow, // Slow Clock (Logic)
    input logic                reset,  
    input logic                start,    // pulse to begin calculation
    input logic                load,     // high when loading data
    input logic [M - 1:0]      rd_adr,   // index of input sample
    input logic [2*width-1:0]  rd,       // read data in
    output logic [2*width-1:0] wd,       // complex write data out
    output logic               done      // high when complete
);

    // Unused output from controller
    logic processing;

    // Instantiate the Controller
    // This module contains the RAMs, AGU, and Butterfly units internally.
    fft_controller controller (
        .clk(clk_fast),         // System Clock
        .ram_clk(clk_fast),     // Used for Muxing (Same as Fast Clock)
        .slow_clk(clk_slow),    // Logic Clock
        .reset(reset),
        .start(start),
        .load(load),
        .load_address(rd_adr),  // Connect Testbench Address
        .data_in(rd),           // Connect Testbench Input
        .done(done),
        .processing(processing),
        .data_out(wd)           // Connect Testbench Output
    );

endmodule