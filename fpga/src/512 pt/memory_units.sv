// Authors: Jared Carreno, Shreya Jampana, Emma Angel
// Purpose: Defines a synchronous RAM for data storage 
// and a ROM for storing pre-computed twiddle factors.

module ram (
    input logic          clk, write,
    input logic [8:0]    write_address, read_address,
    input logic [31:0]   d,
    output logic [31:0]  q
);
    logic [31:0] mem [511:0]; 

   always_ff @(posedge clk)
		if (write) begin
			mem[write_address] <= d;
		end

   always_ff @(posedge clk)
		q <= mem[read_address];

endmodule

module twiddle_rom (input logic clk,
                    input logic [8:0] twiddle_address,
                    output logic [31:0] twiddle);
            
   // twiddle factors are generated with msb on left side
   logic [31:0] mem [0:255];

   initial   $readmemb("twiddle.vectors", mem);
	
	// Synchronous version
	always_ff @(posedge clk) begin
		twiddle <= mem[twiddle_address];
	end

endmodule
