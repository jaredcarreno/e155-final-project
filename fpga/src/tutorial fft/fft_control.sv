// FFT control unit.
// Contains the address generation unit
// and handles loading and output logic.
module fft_control
  #(parameter width=16, M=5)
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

   // pulsed start -> enable hold logic
   logic                    enable;
   always_ff @(posedge clk)
     begin
	if      (start) enable <= 1;
	else if (done || reset)  enable <= 0;
     end

   // normal operation logic (generate butterfly addresses for RAM)
   logic [M-1:0]         adrA, adrB;
   logic                   we0_agu;
   fft_agu #(width, M) fft_agu(clk, enable, reset, load,
                                 done, rdsel, we0_agu, we1,
                                 adrA, adrB, twiddleadr);

   // load logic (generate bit-reversed indexes for RAM)
   logic [M - 1:0]     adr_load; // if loading, use addr from loader to load RAM0
   bit_reverse #(M) reverseaddr(rd_adr, adr_load);

   // done state/output logic (counter to address ram to write out on `rd`)
   logic [M-1:0]       out_idx;
   always_ff @(posedge clk)
     if      (reset) out_idx <= 0;
     else if (done)  out_idx <= out_idx + 1'b1;

   // assign output based on load/done state:
   // done state has priority and addresses ram0/ram1 a port for read on `wd`.
   //      (a mux in `fft` controls which ram `wd` reads from, depending on M)
   // load state has secondary priority and addresses ram0 a/b ports for write from `rd`.
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
  
endmodule // fft_control


// address generation unit (AGU).
// counts the fft level and butterfly index within each level
// and generates ram addresses for each butterfly operation.
// also handles ping-pong control based on fft level.
module fft_agu
  #(parameter width=16, M=5)
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
   
   // count fftLevel and flyInd
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
   end // always_ff @ (posedge clk)

   // sets done when we are finished with the FFT
   assign done = (fftLevel == (M));
   fft_agu_adrcalc #(width, M) adrcalc(fftLevel, flyInd, adrA, adrB, twiddleadr);

   // ping-pong logic that flips every level:
   assign rdsel = fftLevel[0];
   assign we0 =   fftLevel[0] & enable;
   assign we1 =  ~fftLevel[0] & enable;

endmodule // fft_agu


// AGU address calculation unit.
// given FFT level and butterfly index, performs the proper
// rotations to generate the BFU input A and B addresses,
// and the masking to generate the twiddle addresses.
module fft_agu_adrcalc
  #(parameter width=16, M=5)
   (input logic  [M-1:0] fftLevel,
    input logic  [M-1:0] flyInd,
    output logic [M-1:0] adrA,
    output logic [M-1:0] adrB,
    output logic [M-2:0] twiddleadr);

   logic [M-1:0]         tempA, tempB;
   logic signed [M-1:0]  mask, smask; // signed for sign extension
   
   always_comb begin
      // implement the rotations with shifting:
      //     adrA = ROTATE_{M}(2*flyInd,     fftLevel)
      //     adrB = ROTATE_{M}(2*flyInd + 1, fftLevel)
      tempA = flyInd << 1'd1;
      tempB = tempA  +  1'd1;
      adrA  = ((tempA << fftLevel) | (tempA >> (M - fftLevel)));
      adrB  = ((tempB << fftLevel) | (tempB >> (M - fftLevel)));

      // replication operator to create the mask that gets shifted
      // (mask out the last n-1-i least significant bits of flyInd)
      mask       = {1'b1, {M-1{1'b0}} };
      smask      = mask >>> fftLevel;
      twiddleadr = smask & flyInd;
   end
   
endmodule // fft_agu_adrcalc
