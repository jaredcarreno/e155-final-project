// memory.sv - Scaled for 512-point FFT
// Fixes "Multiple Driver" errors and scales depth to 512

module ram (
    input  logic          clk, 
    input  logic          write,
    input  logic [8:0]    write_address, // 9 bits for 512 lines
    input  logic [8:0]    read_address,
    input  logic [31:0]   d,
    output logic [31:0]   q
);

    logic [31:0] mem [511:0]; // Depth 512

    // Unified process to prevent driver conflicts
    always_ff @(posedge clk) begin
        if (write) 
            mem[write_address] <= d;
        q <= mem[read_address];
    end

endmodule

module twiddle_rom (
    input  logic          clk,
    input  logic [7:0]    twiddle_address, // 8 bits for 256 twiddles (N/2)
    output logic [31:0]   twiddle
);

    logic [31:0] mem [0:255]; // Depth 256
    
    // Ensure "twiddle.vectors" has 256 lines!
    initial $readmemb("twiddle.vectors", mem);
    
    always_ff @(posedge clk) begin
        twiddle <= mem[twiddle_address];
    end

endmodule