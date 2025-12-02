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

    // 1. SPI Deserializer (16-bit for Real-only input)
    logic [15:0] spi_shift_reg; 
    logic [4:0]  bit_cnt;
    logic [8:0]  word_cnt;
    
    // Write Control Signals
    logic        buf_we;
    logic [8:0]  ram_write_addr; // NEW: Explicit address to prevent race conditions
    
    // 2. Data Padding (Real -> Complex)
    logic [31:0] ram_input_padded;
    assign ram_input_padded = {spi_shift_reg, 16'h0000}; 

    // 3. Input RAM (512 x 32)
    // Uses the STABLE address signal (ram_write_addr) instead of the moving counter
    ram input_ram (
        .clk(clk), 
        .write(buf_we),
        .write_address(ram_write_addr), // <--- CHANGED THIS PORT
        .read_address(fft_read_addr), 
        .d(ram_input_padded), 
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
            ram_write_addr <= 0;
        end else begin
            // Shift in MSB first
            spi_shift_reg <= {spi_shift_reg[14:0], sdi};
            
            // Check for 16th bit (Index 15)
            if (bit_cnt == 15) begin
                buf_we <= 1;
                
                // CRITICAL FIX: Capture current address BEFORE incrementing
                ram_write_addr <= word_cnt; 
                
                // Manage Word Count
                if (word_cnt == 511) begin
                    start_fft <= 1; // Buffer full, trigger FFT
                    word_cnt <= 0;  // Wrap around
                end else begin
                    word_cnt <= word_cnt + 1;
                    start_fft <= 0;
                end
                
                bit_cnt <= 0; // Reset bit counter
            end else begin
                buf_we <= 0;
                bit_cnt <= bit_cnt + 1;
                start_fft <= 0;
            end
        end
    end
    
    // 5. Output RAM (For reading results back to MCU)
    logic [31:0] out_spi_data;
    
    ram output_ram (
        .clk(clk),
        .write(fft_write_en),
        .write_address(fft_write_addr),
        .read_address(word_cnt), // Reads follow the current word count
        .d(data_from_fft),
        .q(out_spi_data)
    );

    // Output Serializer (Sends full 32-bit complex result)
    assign sdo = out_spi_data[31 - bit_cnt]; 

endmodule