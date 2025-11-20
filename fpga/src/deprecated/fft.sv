// Author(s): Jared Carreno, Shreya Jampana, Emma Angel
// Date:
// Purpose: FFT Core Module
// Very heavily based off of tutorial code available at https://doi.org/10.5281/zenodo.6219524

module fft
  #(parameter width=16, M=9)
   (input logic                clk_fast, // Fast Clock (Memory Muxing)
    input logic                clk_slow, // Slow Clock (Logic)
    input logic                reset,    // reset
    input logic                start,    // pulse to begin calculation
    input logic                load,     // high when loading data
    input logic [M - 1:0]      rd_adr,   // index of input sample
    input logic [2*width-1:0]  rd,       // read data in
    output logic [2*width-1:0] wd,       // complex write data out
    output logic               done);    // high when complete

   logic                       rdsel;
   logic                       we0, we1;
   logic [M - 1:0]             adr0a, adr0b, adr1a, adr1b;
   logic [M - 2:0]             twiddleadr;
   logic [2*width-1:0]         twiddle, a, b, writea, writeb, aout, bout;
   logic [2*width-1:0]         rd0a, rd0b, rd1a, rd1b, val_in;
   
   // load logic 
   assign val_in = rd;
   
   // complex input data real in top 16 bits, imaginary in bottom 16 bits
   assign writea = load ? val_in : aout; // write ram0 with input data or BFU output
   assign writeb = load ? val_in : bout;

   // output logic
   assign wd = M[0] ? rd1a : rd0a; // ram holding results depends on #fftLevels

   // ping-pong read (BFU input) logic
   assign a = rdsel ? rd1a : rd0a;
   assign b = rdsel ? rd1b : rd0b;

   // --- Submodules ---

   // Control Unit (Runs on Slow Logic Clock)
   fft_control control(clk_slow, start, reset, load, rd_adr, done, rdsel, 
                                      we0, adr0a, adr0b, we1, adr1a, adr1b, twiddleadr);

   // RAM 0 (Ping) - Shared Dual Port Wrapper
   twoport_RAM ram0(
       .clk_fast(clk_fast), .clk_slow(clk_slow), .we(we0), 
       .adra(adr0a), .wda(writea), .rda(rd0a),
       .adrb(adr0b), .wdb(writeb), .rdb(rd0b)
   );

   // RAM 1 (Pong) - Shared Dual Port Wrapper
   twoport_RAM ram1(
       .clk_fast(clk_fast), .clk_slow(clk_slow), .we(we1), 
       .adra(adr1a), .wda(aout),   .rda(rd1a),
       .adrb(adr1b), .wdb(bout),   .rdb(rd1b)
   );

   // Math Units
   fft_butterfly bgu(twiddle, a, b, aout, bout);
   fft_twiddleROM twiddlerom(twiddleadr, twiddle);

endmodule // fft