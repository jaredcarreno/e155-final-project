module spi_fft_buffer (
    input  logic sck, 
    input  logic sdi, 
    input  logic reset,
    output logic sdo,
    input  logic clk, // System clock
    
    // Interface to FFT Controller
    output logic [31:0] data_to_fft,    // 32-bit output to FFT RAM
    input  logic [31:0] data_from_fft,  // 32-bit input from FFT RAM (for reading results)
    input  logic [8:0]  fft_read_addr,  
    input  logic [8:0]  fft_write_addr, 
    input  logic        fft_write_en,
    output logic        start_fft
);

    // 1. SPI Deserializer (Changed to 16-bit)
    // We only shift in 16 bits (Real part) per sample now.
    logic [15:0] spi_shift_reg; 
    logic [4:0]  bit_cnt;
    logic [8:0]  word_cnt;
    
    logic        buf_we;
    
    // 2. Data Padding
    // We take the 16-bit Real input and add 16 bits of Zeros for Imaginary
    // Format: {Real[15:0], Imag[15:0]}
    logic [31:0] ram_input_padded;
    assign ram_input_padded = {spi_shift_reg, 16'h0000}; 

    // 3. Input RAM (512 x 32)
    // Ensure 'ram' in memory_units.sv is sized for 512 words
    ram input_ram (
        .clk(clk), 
        .write(buf_we),
        .write_address(word_cnt), 
        .read_address(fft_read_addr), 
        .d(ram_input_padded), // Write the padded 32-bit value
        .q(data_to_fft)
    );

    // 4. SPI Input Logic
    always_ff @(posedge sck or posedge reset) begin
        if (reset) begin
            bit_cnt <= 0;
            word_cnt <= 0;
            start_fft <= 0;
            spi_shift_reg <= 0;
            buf_we <= 0;
        end else begin
            // Shift in MSB first
            spi_shift_reg <= {spi_shift_reg[14:0], sdi};
            
            // Check for 16th bit (Index 15)
            if (bit_cnt == 15) begin
                buf_we <= 1; // Pulse write enable
                
                // Manage Word Count
                if (word_cnt == 511) begin
                    start_fft <= 1; // Buffer full, trigger FFT
                    word_cnt <= 0;  // Wrap around (circular buffer)
                end else begin
                    word_cnt <= word_cnt + 1;
                    start_fft <= 0;
                end
                
                bit_cnt <= 0; // Reset bit counter for next word
            end else begin
                buf_we <= 0;
                bit_cnt <= bit_cnt + 1;
                start_fft <= 0;
            end
        end
    end
    
    // 5. Output RAM (For reading results back to MCU)
    // This part remains 32-bit because the FFT output is complex (Real + Imag)
    // You will need to read 32 bits per bin from the MCU to get the full result.
    logic [31:0] out_spi_data;
    
    ram output_ram (
        .clk(clk),
        .write(fft_write_en),
        .write_address(fft_write_addr),
        .read_address(word_cnt), // SPI reads using the same word counter
        .d(data_from_fft),
        .q(out_spi_data)
    );

    // Output Serializer
    // We send out the 32-bit complex result.
    // Note: If you only read 16 bits on the MCU, you'll get just the Real part,
    // which is a valid strategy if you don't care about phase.
    assign sdo = out_spi_data[31 - bit_cnt]; 

endmodule