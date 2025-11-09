// adapted from HDL example 5.6 in 
// Harris, Digital Design and Computer Architecture
module twoport_RAM
  #(parameter width=16, M=5)
   (input logic                clk,
    input logic                we,
    input logic [M-1:0]      adra,
    input logic [M-1:0]      adrb,
    input logic [2*width-1:0]  wda,
    input logic [2*width-1:0]  wdb,
    output logic [2*width-1:0] rda,
    output logic [2*width-1:0] rdb);

   reg [2*width-1:0]           mem [2**M-1:0];

   always @(posedge clk)
     if (we)
       begin
          mem[adra] <= wda;
          mem[adrb] <= wdb;
       end

   assign rda = mem[adra];
   assign rdb = mem[adrb];

endmodule // twoport_RAM


module fft_twiddleROM
  #(parameter width=16, M=5)
   (input logic  [M-2:0] twiddleadr, // 0 - 1023 = 10 bits
    output logic [2*width-1:0] twiddle);

   // twiddle table pseudocode: w[k] = w[k-1] * w,
   // where w[0] = 1 and w = exp(-j 2pi/N)
   // for k=0... N/2-1

   logic [2*width-1:0]         vectors [0:2**(M-1)-1];
   initial $readmemb("rom/twiddle.vectors", vectors);
   assign twiddle = vectors[twiddleadr];

endmodule // fft_twiddleROM
