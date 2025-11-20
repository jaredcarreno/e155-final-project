// address_gen.sv - Adapted for 512-point FFT

module agu (input logic load, processing, done,
            input logic [8:0] fft_level, // Changed size
            input logic [8:0] butterfly_iter, // Changed size
            input logic [8:0] load_address, // Changed size
            input logic [8:0] out_address, // Changed size
            output logic [8:0] address_0_a, address_1_a, address_0_b, address_1_b,
            output logic [7:0] twiddle_address); // Changed to 8 bits (256 factors)

    // first deal with loading address
    logic [8:0] load_address_rev;
    reverse_bits load_logic(load_address, load_address_rev);

    // then deal with standard processing address
    logic [8:0] address_a, address_b;
    processing_agu standard_logic(fft_level, butterfly_iter,
                                  address_a, address_b, twiddle_address);

    // comb logic to choose from the addresses
    always_comb begin
        if (done) address_0_a = out_address;
        else if (load) address_0_a = load_address_rev;
        else address_0_a = address_a;

        if (load) address_0_b = load_address_rev;
        else address_0_b = address_b;

        if (done) address_1_a = out_address;
        else address_1_a = address_a;

        address_1_b = address_b;
    end

endmodule


module processing_agu (input logic [8:0] fft_level, 
                       input logic [8:0] butterfly_iter,
                       output logic [8:0] address_a, address_b,
                       output logic [7:0] twiddle_address);

    // intermediate for shifting (9 bits)
    logic [8:0] temp_a, temp_b;
    // must be signed for sign extending
    logic signed [8:0] mask, mask_shift;

    always_comb begin
        // j * 2
        temp_a = butterfly_iter << 1;
        
        // Circular shift for M=9
        address_a  = ((temp_a << fft_level) | (temp_a >> (9 - fft_level)));

        // j * 2 + 1
        temp_b = temp_a + 9'b1;
        address_b  = ((temp_b << fft_level) | (temp_b >> (9 - fft_level)));

        // zero out 9 - 1 - i
        mask = 9'b100000000; // 9th bit set
        mask_shift = mask >>> fft_level;

        // mask j
        twiddle_address = mask_shift[7:0] & butterfly_iter[7:0];
    end
endmodule

// reverse bits for address ordering (9-bit version)
module reverse_bits (input logic [8:0] bits_in,
                     output logic [8:0] bits_out);
    
    logic b0, b1, b2, b3, b4, b5, b6, b7, b8;

    assign {b8, b7, b6, b5, b4, b3, b2, b1, b0} = bits_in;
    assign bits_out = {b0, b1, b2, b3, b4, b5, b6, b7, b8};

endmodule