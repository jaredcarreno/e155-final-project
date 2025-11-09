// Multiplication.
// This performs `width`-bit multiplication on fixed point signed
// integers, returning `width`-bit outputs, with rounding of the lsb.
module mult
  #(parameter width=16)
   (input logic signed [width-1:0]  a,
    input logic signed [width-1:0]  b,
    output logic signed [width-1:0] out);

   logic [2*width-1:0]              untruncated_out;

   assign untruncated_out = a * b;
   assign out = untruncated_out[2*width-2:width-1] + untruncated_out[width-2];
   // We can discard the msb as long as we're not
   // multiplying two maximum mag. negative numbers.

endmodule // mult

// Complex multiplication.
module complex_mult
  #(parameter width=16)
   (input logic [2*width-1:0]  a,
    input logic [2*width-1:0]  b,
    output logic [2*width-1:0] out);

   logic signed [width-1:0]    a_re, a_im, b_re, b_im, out_re, out_im;
   assign a_re = a[2*width-1:width]; assign a_im = a[width-1:0];
   assign b_re = b[2*width-1:width]; assign b_im = b[width-1:0];

   logic signed [width-1:0]    a_re_be_re, a_im_b_im, a_re_b_im, a_im_b_re;
   mult #(width) m1 (a_re, b_re, a_re_be_re);
   mult #(width) m2 (a_im, b_im, a_im_b_im);
   mult #(width) m3 (a_re, b_im, a_re_b_im);
   mult #(width) m4 (a_im, b_re, a_im_b_re);

   assign out_re = (a_re_be_re) - (a_im_b_im);
   assign out_im = (a_re_b_im) + (a_im_b_re);
   assign out = {out_re, out_im};
endmodule // complex_mult

// Parameterized bit reversal.
module bit_reverse
  #(parameter M=5)
   (input logic [M-1:0] in,
    output logic [M-1:0] out);

   genvar                  i;
   generate
      for(i=0; i<M; i=i+1) begin : BIT_REVERSE
	 assign out[i] = in[M-i-1];
      end
   endgenerate

endmodule // bit_reverse

