module fft_controller (
    input logic 				clk, ram_clk, slow_clk, reset, start, load,
    input logic [8:0] 		    load_address,      // [8:0] for 512
    input logic [31:0] 	        data_in,
    output logic 			    done,
    output logic                processing,
    output logic [31:0] 	    data_out
);
    logic			    write_0, write_1;
    // Addresses scaled to 9 bits
    logic [8:0]		    fft_level, butterfly_iter, address_0_a, address_0_b, write_address_0, address_1_a, address_1_b, write_address_1, out_address;
    // Twiddle scaled to 8 bits
    logic [7:0]		    twiddle_address;
    logic [31:0]	    twiddle, a, b, a_out, b_out, write_data_a, write_data_b, write_data;
    logic [31:0]	    read_data_0_a, read_data_0_b, read_data_1_a, read_data_1_b;

    // Start processing logic
    always_ff @(posedge slow_clk) begin
        if      (start) processing <= 1;
        else if (reset || done)  processing <= 0;
    end

    fft_counter counter(slow_clk, processing, reset, done, fft_level, butterfly_iter);

    // output logic
    assign data_out = a;
    assign done = fft_level == 9; // 9 stages for 512 points (2^9)

    // Output counter
    always_ff @(posedge slow_clk) begin
        if      (reset) out_address <= 0;
        else if (done)  out_address <= out_address + 1'b1;
    end

    agu address_generator(load, processing, done, fft_level, butterfly_iter, load_address, out_address,
                          address_0_a, address_1_a, address_0_b, address_1_b, twiddle_address);

    // Write Muxing
    assign write_data_a = load ? data_in : a_out;
    assign write_data_b = load ? data_in : b_out;
   
    assign write_data = ram_clk ? write_data_a : write_data_b;
    assign write_address_0 = ram_clk ? address_0_a : address_0_b;
    assign write_address_1 = ram_clk ? address_1_a : address_1_b;

    // RAM Instantiations
    ram ram0_a(clk, write_0, write_address_0, address_0_a, write_data, read_data_0_a);
    ram ram0_b(clk, write_0, write_address_0, address_0_b, write_data, read_data_0_b);
    ram ram1_a(clk, write_1, write_address_1, address_1_a, write_data, read_data_1_a);
    ram ram1_b(clk, write_1, write_address_1, address_1_b, write_data, read_data_1_b);

    // Butterfly Input Mux
    assign a = fft_level[0] ? read_data_1_a : read_data_0_a;
    assign b = fft_level[0] ? read_data_1_b : read_data_0_b;

    // Twiddle ROM
    twiddle_rom twiddle_gen(ram_clk, twiddle_address, twiddle);

    // Butterfly Unit (Fixed Name to match multiplication.sv)
    fft_butterfly butt(twiddle, a, b, a_out, b_out);

    assign write_0 =  (fft_level[0] & processing) | load;
    assign write_1 =  ~fft_level[0] & processing;

endmodule

// Counters Module
module fft_counter (
    input logic clk, processing, reset, done,
    output logic [8:0] fft_level, butterfly_iter
);
    always_ff @(posedge clk) begin
        if (reset) begin
            fft_level <= 0;
            butterfly_iter <= 0;
        end
        else if(processing == 1 & ~done) begin
            if(butterfly_iter < 255) begin 
                butterfly_iter <= butterfly_iter + 1'd1;
            end else begin
                butterfly_iter <= 0;
                fft_level <= (fft_level == 9) ? fft_level : fft_level + 1'd1;
            end
        end
    end
endmodule

// --- AGU MODULES (Originally in address_gen.sv) ---

module agu (
    input logic load, processing, done,
    input logic [8:0] fft_level, butterfly_iter, load_address, out_address,
    output logic [8:0] address_0_a, address_1_a, address_0_b, address_1_b,
    output logic [7:0] twiddle_address
);
    // Bit Reverse Load Address
    logic [8:0] load_address_rev;
    reverse_bits load_logic(load_address, load_address_rev);

    // Standard Processing Addresses
    logic [8:0] address_a, address_b;
    processing_agu standard_logic(fft_level, butterfly_iter, address_a, address_b, twiddle_address);

    // Muxing Logic
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

module processing_agu (
    input logic [8:0] 	fft_level, butterfly_iter,
    output logic [8:0]  address_a, address_b,
    output logic [7:0]  twiddle_address
);
    logic [8:0]         temp_a, temp_b;
    logic signed [8:0]  mask, mask_shift;

    always_comb begin
        // j * 2
        temp_a = butterfly_iter << 1;
        // Address A: bit insert 0
        address_a  = ((temp_a << fft_level) | (temp_a >> (9 - fft_level))); 
        
        // j * 2 + 1
        temp_b = temp_a + 9'b1;
        // Address B: bit insert 1
        address_b  = ((temp_b << fft_level) | (temp_b >> (9 - fft_level)));

        // Masking for Twiddle Factors
        // Start with 1 at MSB (9th bit) -> 9'b100000000
        mask = 9'b100000000;
        mask_shift = mask >>> fft_level;

        // Mask j
        twiddle_address = mask_shift[7:0] & butterfly_iter[7:0];
    end
endmodule

module reverse_bits (
    input logic [8:0]    bits_in,
    output logic [8:0]   bits_out
);
    assign bits_out[0] = bits_in[8];
    assign bits_out[1] = bits_in[7];
    assign bits_out[2] = bits_in[6];
    assign bits_out[3] = bits_in[5];
    assign bits_out[4] = bits_in[4];
    assign bits_out[5] = bits_in[3];
    assign bits_out[6] = bits_in[2];
    assign bits_out[7] = bits_in[1];
    assign bits_out[8] = bits_in[0];
endmodule