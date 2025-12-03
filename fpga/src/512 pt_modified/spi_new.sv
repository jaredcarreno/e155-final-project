module spi_fft_buffer (
    input  logic sck, sdi, reset,
    output logic sdo,
    input  logic clk,
    
    output logic [31:0] data_to_fft,
    input  logic [31:0] data_from_fft,
    input  logic [8:0]  fft_read_addr,  
    input  logic [8:0]  fft_write_addr, 
    input  logic        fft_write_en,
    output logic        start_fft 
);

    // --- 1. WRITE LOGIC (16-bit Input for Audio) ---
    // We count to 16 bits (0..15) before writing to RAM
    logic [15:0] spi_shift_reg; 
    logic [4:0]  wr_bit_cnt;
    logic [8:0]  wr_word_cnt;
    logic        buf_we;
    logic [8:0]  ram_write_addr_latched;

    // Pad 16-bit input (Real) with 16-bit Zeros (Imag)
    logic [31:0] ram_input_padded;
    assign ram_input_padded = {8'h00, spi_shift_reg, 16'h0000}; 

    ram input_ram (
        .clk(clk), 
        .write(buf_we),
        .write_address(ram_write_addr_latched),
        .read_address(fft_read_addr), 
        .d(ram_input_padded), 
        .q(data_to_fft)
    );

    always_ff @(posedge sck) begin
        if (~reset) begin
            wr_bit_cnt <= 0;
            wr_word_cnt <= 0;
            start_fft <= 0;
            spi_shift_reg <= 0;
            buf_we <= 0;
            ram_write_addr_latched <= 0;
        end else begin
            spi_shift_reg <= {spi_shift_reg[14:0], sdi};
            
            // Trigger on 16th bit (Index 15)
            if (wr_bit_cnt == 5'd15) begin
                buf_we <= 1;
                ram_write_addr_latched <= wr_word_cnt;
                
                if (wr_word_cnt == 511) begin
                    start_fft <= 1;
                    wr_word_cnt <= 0;
                end else begin
                    wr_word_cnt <= wr_word_cnt + 1;
                    start_fft <= 0;
                end
                wr_bit_cnt <= 0;
            end else begin
                buf_we <= 0;
                wr_bit_cnt <= wr_bit_cnt + 1;
                start_fft <= 0;
            end
        end
    end
    
    // --- 2. READ LOGIC (32-bit Output for Complex Result) ---
    // Counts to 32 bits (0..31) before incrementing address
    logic [31:0] out_spi_data;
    logic [4:0]  rd_bit_cnt;
    logic [8:0]  rd_word_cnt;

    ram output_ram (
        .clk(clk),
        .write(fft_write_en),
        .write_address(fft_write_addr),
        .read_address(rd_word_cnt), // Driven by Read Counter
        .d(data_from_fft),
        .q(out_spi_data)
    );

    // Read Counter Logic
    always_ff @(posedge sck) begin
        if (~reset) begin
            rd_bit_cnt <= 0;
            rd_word_cnt <= 0;
        end else begin
            if (rd_bit_cnt == 31) begin
                rd_bit_cnt <= 0;
                if (rd_word_cnt == 511) 
                    rd_word_cnt <= 0;
                else 
                    rd_word_cnt <= rd_word_cnt + 1;
            end else begin
                rd_bit_cnt <= rd_bit_cnt + 1;
            end
        end
    end

    assign sdo = out_spi_data[31 - rd_bit_cnt]; 

endmodule