// multiplication.sv - Adapted for 512-point FFT (Brian's Architecture)

// Renamed from 'fft_butterfly' to match 'fft_controller' instantiation
module butterfly_unit #(parameter width=16)
   (input logic [2*width-1:0]  a,       // Input A (Upper Leg)
    input logic [2*width-1:0]  b,       // Input B (Lower Leg)
    input logic [2*width-1:0]  twiddle, // Twiddle Factor
    output logic [2*width-1:0] aout,    // Output A
    output logic [2*width-1:0] bout);   // Output B
   
   logic signed [width-1:0]    a_re, a_im, aout_re, aout_im, bout_re, bout_im;
   logic signed [width-1:0]    b_re_mult, b_im_mult;
   logic [2*width-1:0]         b_mult;

   // Unpack the 32-bit complex inputs
   assign a_re = a[2*width-1:width];
   assign a_im = a[width-1:0];

   // Multiply Lower Leg (b) by Twiddle Factor
   complex_mult #(width) twiddle_mult(b, twiddle, b_mult);
   
   assign b_re_mult = b_mult[2*width-1:width];
   assign b_im_mult = b_mult[width-1:0];

   // Butterfly "Criss-Cross" Additions/Subtractions
   // A_out = A + (B * W)
   assign aout_re = a_re + b_re_mult;
   assign aout_im = a_im + b_im_mult;
   
   // B_out = A - (B * W)
   assign bout_re = a_re - b_re_mult;
   assign bout_im = a_im - b_im_mult;

   // Repack into 32-bit complex outputs
   assign aout = {aout_re, aout_im};
   assign bout = {bout_re, bout_im};

endmodule 


// Standard Signed Multiplier with Truncation
module mult #(parameter width=16)
   (input logic signed [width-1:0]  a,
    input logic signed [width-1:0]  b,
    output logic signed [width-1:0] out);
   
   logic [2*width-1:0]              untruncated_out;
   
   // Perform full precision multiply
   assign untruncated_out = a * b;
   
   // Truncate back to 16 bits (divide by 2^15 to keep fixed point scale)
   // This keeps the decimal point in the correct place for Q1.15 format
   assign out = untruncated_out[2*width-2:width-1] + untruncated_out[width-2];
   
endmodule 


// Complex Multiplier: (a + ji) * (c + jd)
module complex_mult #(parameter width=16)
   (input logic [2*width-1:0]  a,
    input logic [2*width-1:0]  b,
    output logic [2*width-1:0] out);
   
   logic signed [width-1:0]    a_re, a_im, b_re, b_im, out_re, out_im;
   
   assign a_re = a[2*width-1:width]; 
   assign a_im = a[width-1:0];
   assign b_re = b[2*width-1:width]; 
   assign b_im = b[width-1:0];

   logic signed [width-1:0]    a_re_b_re, a_im_b_im, a_re_b_im, a_im_b_re;

   // Four Real Multiplications
   mult #(width) m1 (a_re, b_re, a_re_b_re); // Real * Real
   mult #(width) m2 (a_im, b_im, a_im_b_im); // Imag * Imag
   mult #(width) m3 (a_re, b_im, a_re_b_im); // Real * Imag
   mult #(width) m4 (a_im, b_re, a_im_b_re); // Imag * Real

   // Complex Math: 
   // Real = (ac - bd)
   assign out_re = (a_re_b_re) - (a_im_b_im);
   // Imag = (ad + bc)
   assign out_im = (a_re_b_im) + (a_im_b_re);
   
   assign out = {out_re, out_im};

endmodule