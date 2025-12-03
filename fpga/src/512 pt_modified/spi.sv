module spi_fft_buffer (
    input  logic sck, 
    input  logic sdi, 
    input  logic reset,
    output logic sdo,
    input  logic clk,
    
    // Interface to FFT Controller
    output logic [31:0] data_to_fft,
    input  logic [31:0] data_from_fft,
    input  logic [8:0]  fft_read_addr,  
    input  logic [8:0]  fft_write_addr, 
    input  logic        fft_write_en,
    output logic        start_fft
);

    // --- 1. WRITE LOGIC (Input from MCU -> FPGA) ---
    // Increments every 16 bits
    logic [15:0] spi_shift_reg; 
    logic [4:0]  wr_bit_cnt;
    logic [8:0]  wr_word_cnt;
    logic        buf_we;
    logic [8:0]  ram_write_addr_latched;

    // Pad 16-bit input with zeros
    logic [31:0] ram_input_padded;
    assign ram_input_padded = {spi_shift_reg, 16'h0000}; 

    ram input_ram (
        .clk(clk), 
        .write(buf_we),
        .write_address(ram_write_addr_latched),
        .read_address(fft_read_addr), 
        .d(ram_input_padded), 
        .q(data_to_fft)
    );

    always_ff @(posedge sck or posedge reset) begin
        if (reset) begin
            wr_bit_cnt <= 0;
            wr_word_cnt <= 0;
            start_fft <= 0;
            spi_shift_reg <= 0;
            buf_we <= 0;
            ram_write_addr_latched <= 0;
        end else begin
            spi_shift_reg <= {spi_shift_reg[14:0], sdi};
            
            // Trigger on 16th bit (16-bit Input Mode)
            if (wr_bit_cnt == 15) begin
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
    
    // --- 2. READ LOGIC (Output from FPGA -> MCU) ---
    // Increments every 32 bits (Complex Output)
    logic [31:0] out_spi_data;
    logic [4:0]  rd_bit_cnt;
    logic [8:0]  rd_word_cnt;

    ram output_ram (
        .clk(clk),
        .write(fft_write_en),
        .write_address(fft_write_addr),
        .read_address(rd_word_cnt), // Driven by separate READ counter
        .d(data_from_fft),
        .q(out_spi_data)
    );

    // Read Counter Logic
    always_ff @(posedge sck or posedge reset) begin
        if (reset) begin
            rd_bit_cnt <= 0;
            rd_word_cnt <= 0;
        end else begin
            // Trigger on 32nd bit (32-bit Output Mode)
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

    // Output Serializer
    assign sdo = out_spi_data[31 - rd_bit_cnt]; 

endmodule