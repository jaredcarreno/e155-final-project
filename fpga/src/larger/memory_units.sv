// memory_units.sv - Adapted for 512-point FFT

// 9-bit addresses for 512-point FFT
module ram (input logic          clk, write,
            input logic [8:0]    write_address, read_address,
            input logic [31:0]   d,
            output logic [31:0]  q);

    // 512 words deep
    logic [31:0] mem [511:0];

    always_ff @(posedge clk)
        if (write) begin
            mem[write_address] <= d;
        end

    always_ff @(posedge clk)
        q <= mem[read_address];

endmodule

// Twiddle ROM - 256 entries
module twiddle_rom (input logic clk,
                    input logic [7:0] twiddle_address,
                    output logic [31:0] twiddle);

    // 256 words deep
    logic [31:0] mem [0:255];
    
    // Ensure you regenerate 'twiddle.vectors' for 512 points!
    initial $readmemb("rom/twiddle.vectors", mem);
    
    always_ff @(posedge clk) begin
        twiddle <= mem[twiddle_address];
    end

endmodule