// Author(s):
// Date:
// Purpose:
// Based off of tutorial code available at https://doi.org/10.5281/zenodo.6219524

module fft_control
  #(parameter width=16, M=9)
   (input logic             clk,
    input logic             start,
    input logic             reset,
    input logic             load,
    input logic [M-1:0]   rd_adr, 
    output logic            done,
    output logic            rdsel,
    output logic            we0,
    output logic [M-1:0]  adr0a, 
    output logic [M-1:0]  adr0b,
    output logic            we1,
    output logic [M-1:0]  adr1a,
    output logic [M-1:0]  adr1b,
    output logic [M-2:0]  twiddleadr);

   logic                    enable;
   always_ff @(posedge clk) begin
	if      (start) enable <= 1;
    else if (done || reset)  enable <= 0;
   end

   // normal operation logic
   logic [M-1:0]         adrA, adrB;
   logic                   we0_agu;
   fft_agu #(width, M) fft_agu(clk, enable, reset, load,
                                 done, rdsel, we0_agu, we1,
                                 adrA, adrB, twiddleadr);
   // load logic
   logic [M - 1:0]     adr_load;
   bit_reverse #(M) reverseaddr(rd_adr, adr_load);

   // done state/output logic
   logic [M-1:0]       out_idx;
   always_ff @(posedge clk)
     if      (reset) out_idx <= 0;
     else if (done)  out_idx <= out_idx + 1'b1;

   always_comb begin
      if      (done) adr0a = out_idx;
      else if (load) adr0a = adr_load;
      else           adr0a = adrA;
      
      if      (done) adr1a = out_idx;
      else           adr1a = adrA;
      
      if      (load) adr0b = adr_load;
      else           adr0b = adrB;

      adr1b = adrB;
      we0   = load | we0_agu;
   end
endmodule 

module fft_agu
  #(parameter width=16, M=9)
   (input logic            clk,
    input logic            enable,
    input logic            reset,
    input logic            load,
    output logic           done,
    output logic           rdsel,
    output logic           we0,
    output logic           we1,
    output logic [M-1:0] adrA,
    output logic [M-1:0] adrB,
    output logic [M-2:0] twiddleadr);
   
   logic [M-1:0]         fftLevel = 0;
   logic [M-1:0]         flyInd = 0;

   always_ff @(posedge clk) begin
      if (reset) begin
         fftLevel <= 0;
         flyInd <= 0;
      end
      else if(enable === 1 & ~done) begin
         if(flyInd < 2**(M - 1) - 1) begin
            flyInd <= flyInd + 1'd1;
         end else begin
            flyInd <= 0;
            fftLevel <= fftLevel + 1'd1;
         end
      end
   end

   assign done = (fftLevel == (M));
   fft_agu_adrcalc #(width, M) adrcalc(fftLevel, flyInd, adrA, adrB, twiddleadr);

   assign rdsel = fftLevel[0];
   assign we0 =   fftLevel[0] & enable;
   assign we1 =  ~fftLevel[0] & enable;
endmodule 

module fft_agu_adrcalc
  #(parameter width=16, M=9)
   (input logic  [M-1:0] fftLevel,
    input logic  [M-1:0] flyInd,
    output logic [M-1:0] adrA,
    output logic [M-1:0] adrB,
    output logic [M-2:0] twiddleadr);
   
   logic [M-1:0]         tempA, tempB;
   logic signed [M-1:0]  mask, smask;

   always_comb begin
      tempA = flyInd << 1'd1;
      tempB = tempA  +  1'd1;
      adrA  = ((tempA << fftLevel) | (tempA >> (M - fftLevel)));
      adrB  = ((tempB << fftLevel) | (tempB >> (M - fftLevel)));
      
      mask       = {1'b1, {M-1{1'b0}} };
      smask      = mask >>> fftLevel;
      twiddleadr = smask & flyInd;
   end
endmodule