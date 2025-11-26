// dual_RAM.sv
// Matches the instantiation interface in fft_top.sv
// Infers Block RAM (EBR) on iCE40 Ultra Plus

module RAM 
    #(parameter bit_width = 16, 
      parameter M = 9) // Default M=9 for 512-point FFT
    (
    input  logic                   wr_clk_i,
    input  logic                   rd_clk_i,
    input  logic                   rst_i,        // Not strictly used for BRAM array, but kept for interface compatibility
    input  logic                   wr_clk_en_i,
    input  logic                   rd_en_i,
    input  logic                   rd_clk_en_i,
    input  logic                   wr_en_i,
    input  logic [2*bit_width-1:0] wr_data_i,
    input  logic [M-1:0]           wr_addr_i,
    input  logic [M-1:0]           rd_addr_i,
    output logic [2*bit_width-1:0] rd_data_o
    );

    // Memory Array (Infers BRAM)
    // 2*bit_width = 32 bits wide
    // 2^M = 512 depth
    logic [2*bit_width-1:0] mem [0:(2**M)-1];

    // Write Port
    always_ff @(posedge wr_clk_i) begin
        if (wr_clk_en_i && wr_en_i) begin
            mem[wr_addr_i] <= wr_data_i;
        end
    end

    // Read Port
    // iCE40 EBRs have synchronous reads.
    always_ff @(posedge rd_clk_i) begin
        if (rd_clk_en_i && rd_en_i) begin
            rd_data_o <= mem[rd_addr_i];
        end
    end

endmodule