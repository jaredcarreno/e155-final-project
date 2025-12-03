module fft_controller (
    input logic         clk, ram_clk, slow_clk, reset, start, load,
    input logic [8:0]   load_address,
    input logic [31:0]  data_in,
    output logic        done,
    output logic        processing,
    output logic [31:0] data_out,
    output logic [8:0]  out_addr_probe // NEW: Expose internal address
);

    logic           write_0, write_1;
    logic [5:0]     fft_level; // 6 bits is enough for 9 levels
    
    // CRITICAL FIX: All address signals must be 9 bits [8:0] for 512 points
    logic [8:0]     butterfly_iter, address_0_a, address_0_b, write_address_0, address_1_a, address_1_b, write_address_1, out_address;
    logic [8:0]     twiddle_address;
    
    logic [31:0]    twiddle, a, b, a_out, b_out, write_data_a, write_data_b, write_data;
    logic [31:0]    read_data_0_a, read_data_0_b, read_data_1_a, read_data_1_b;

    // Start processing logic
    always_ff @(posedge slow_clk) begin
        if (start) processing <= 1;
        else if ((~reset) || done)  processing <= 0;
    end

    // Instantiate Counter
    fft_counter counter(slow_clk, processing, reset, done, fft_level, butterfly_iter);

    // Output Logic
    assign data_out = a;
    assign done = (fft_level == 9); // 9 levels for 512 points

    // Output Address Counter
    always_ff @(posedge slow_clk) begin
        if (~reset) out_address <= 0;
        else if (done) out_address <= out_address + 1'b1;
    end

    // Connect Probe
    assign out_addr_probe = out_address; 

    // Address Generator
    agu address_generator(load, processing, done, fft_level, butterfly_iter, load_address, out_address,
                                 address_0_a, address_1_a, address_0_b, address_1_b, twiddle_address);

    // RAM Muxing Logic
    assign write_data_a = load ? data_in : a_out;
    assign write_data_b = load ? data_in : b_out;
   
    assign write_data = ram_clk ? write_data_a : write_data_b;
    assign write_address_0 = ram_clk ? address_0_a : address_0_b;
    assign write_address_1 = ram_clk ? address_1_a : address_1_b;

    // Memory Instantiation
    ram ram0_a(clk, write_0, write_address_0, address_0_a, write_data, read_data_0_a);
    ram ram0_b(clk, write_0, write_address_0, address_0_b, write_data, read_data_0_b);
    ram ram1_a(clk, write_1, write_address_1, address_1_a, write_data, read_data_1_a);
    ram ram1_b(clk, write_1, write_address_1, address_1_b, write_data, read_data_1_b);

    // Butterfly Inputs
    assign a = fft_level[0] ? read_data_1_a : read_data_0_a;
    assign b = fft_level[0] ? read_data_1_b : read_data_0_b;

    // Twiddle Factor
    twiddle_rom twiddle_gen(ram_clk, twiddle_address, twiddle);

    // Butterfly Unit
    butterfly_unit butt(a, b, twiddle, a_out, b_out);

    // Write Enables
    assign write_0 =  (fft_level[0] & processing) | load;
    assign write_1 =  ~fft_level[0] & processing;

endmodule

// CRITICAL FIX: butterfly_iter must be [8:0] to count past 63
module fft_counter (
    input logic clk, processing, reset, done,
    output logic [5:0] fft_level, 
    output logic [8:0] butterfly_iter 
);
    always_ff @(posedge clk) begin
        if (~reset) begin
            fft_level <= 0;
            butterfly_iter <= 0;
        end else if(processing == 1 & ~done) begin
            // Count to 255 (N/2 - 1)
            if(butterfly_iter < 255) begin 
                butterfly_iter <= butterfly_iter + 1'd1;
            end else begin
                butterfly_iter <= 0;
                // Stop at level 9
                fft_level <= (fft_level == 9) ? fft_level : fft_level + 1'd1; 
            end
        end
    end
endmodule