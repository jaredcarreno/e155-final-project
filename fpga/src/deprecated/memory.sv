// Author(s):
// Date:
// Purpose: Memory Units

// Emulates a True Dual-Port RAM using Single-Port Block RAM (EBR)
// by running at 2x speed (Time Multiplexing).
module twoport_RAM #(parameter width=16, M=9) (
    input logic                clk_fast, // Fast Clock (48 MHz)
    input logic                clk_slow, // Logic Clock (24 MHz)
    input logic                we,       
    
    // Port A
    input logic [M-1:0]      adra,
    input logic [2*width-1:0]  wda,
    output logic [2*width-1:0] rda,
    
    // Port B
    input logic [M-1:0]      adrb,
    input logic [2*width-1:0]  wdb,
    output logic [2*width-1:0] rdb
);
    // Shared Memory Array
    reg [2*width-1:0] mem [0:2**M-1];
    logic phase;

    // --- CRITICAL FIX: Initialize Memory to 0 ---
    // This prevents 'x' from propagating if the FFT reads before writing
    integer i;
    initial begin
        for (i=0; i < 2**M; i=i+1) begin
            mem[i] = 0;
        end
    end

    // Phase synchronization
    always_ff @(posedge clk_fast) begin
        if (clk_slow) phase <= 0; 
        else          phase <= 1;
    end

    // Double-Pumped Access
    always_ff @(posedge clk_fast) begin
        if (phase == 0) begin
            // Phase 0: Port A
            if (we) mem[adra] <= wda;
            rda <= mem[adra];
        end else begin
            // Phase 1: Port B
            if (we) mem[adrb] <= wdb;
            rdb <= mem[adrb];
        end
    end
endmodule

module fft_twiddleROM
  #(parameter width=16, M=9)
   (input logic  [M-2:0] twiddleadr, 
    output logic [2*width-1:0] twiddle);

   logic [2*width-1:0] vectors [0:2**(M-1)-1];
   
   // Ensure 'twiddle.vectors' is in your project root or simulation folder
   initial $readmemb("twiddle.vectors", vectors);
   
   assign twiddle = vectors[twiddleadr];

endmodule