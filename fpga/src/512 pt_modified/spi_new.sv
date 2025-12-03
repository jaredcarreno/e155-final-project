// Merged SPI Buffer
// Input: 8-bit samples (Fast Upload) -> Pads to 32-bit for FFT
// Output: 32-bit complex results (Standard Download) -> Serialized to MCU

module spi_fft_buffer (
    input  logic sck,        // SPI clock
    input  logic sdi,        // SPI data in (MCU -> FPGA)
    input  logic reset,      // async reset
    output logic sdo,        // SPI data out (FPGA -> MCU)
    input  logic clk,        // system clock
    
    // Interface to FFT controller
    output logic [31:0] data_to_fft,
    input  logic [31:0] data_from_fft,
    input  logic [8:0]  fft_read_addr,  // FFT reading INPUT RAM
    input  logic [8:0]  fft_write_addr, // FFT writing OUTPUT RAM
    input  logic        fft_write_en,
    output logic        start_fft       // goes high when 512 samples captured
);

    // ================================================================
    // 1. INPUT PATH (8-bit Optimized)
    //    Based on Shreya Jampana's logic
    // ================================================================

    // SPI domain signals
    logic [7:0] spi_shift_reg;
    logic [2:0] bit_cnt_sck;      // 0..7
    logic [8:0] sample_cnt_sck;   // 0..511
    logic       sample_we_sck;
    logic [7:0] sample_byte_sck;
    logic [8:0] sample_index_sck;
    logic       frame_full_sck;

    always_ff @(posedge sck or posedge reset) begin
        if (reset) begin
            spi_shift_reg   <= 8'd0;
            bit_cnt_sck     <= 3'd0;
            sample_cnt_sck  <= 9'd0;
            sample_we_sck   <= 1'b0;
            sample_byte_sck <= 8'd0;
            sample_index_sck<= 9'd0;
            frame_full_sck  <= 1'b0;
        end else begin
            // Shift in MSB first
            spi_shift_reg <= {spi_shift_reg[6:0], sdi};
            sample_we_sck <= 1'b0;

            if (bit_cnt_sck == 3'd7) begin
                // Byte complete
                bit_cnt_sck      <= 3'd0;
                sample_we_sck    <= 1'b1;
                sample_byte_sck  <= {spi_shift_reg[6:0], sdi};
                sample_index_sck <= sample_cnt_sck;

                // Frame management
                if (sample_cnt_sck == 9'd511) begin
                    sample_cnt_sck <= 9'd0;
                    frame_full_sck <= 1'b1; 
                end else begin
                    sample_cnt_sck <= sample_cnt_sck + 9'd1;
                end
            end else begin
                bit_cnt_sck <= bit_cnt_sck + 3'd1;
            end
        end
    end

    // --- Clock Domain Crossing (SPI -> System Clock) ---
    logic sample_we_meta, sample_we_sync, sample_we_prev;
    logic frame_full_meta, frame_full_sync;
    logic [7:0] sample_byte_clk;
    logic [8:0] sample_index_clk;
    wire sample_we_clk;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_we_meta <= 0; sample_we_sync <= 0; sample_we_prev <= 0;
            frame_full_meta <= 0; frame_full_sync <= 0;
            sample_byte_clk <= 0; sample_index_clk <= 0;
        end else begin
            // Sync Strobe
            sample_we_meta <= sample_we_sck;
            sample_we_sync <= sample_we_meta;
            sample_we_prev <= sample_we_sync;
            
            // Sync Frame Full
            frame_full_meta <= frame_full_sck;
            frame_full_sync <= frame_full_meta;

            if (sample_we_clk) begin
                sample_byte_clk <= sample_byte_sck;
                sample_index_clk <= sample_index_sck;
            end
        end
    end

    assign sample_we_clk = sample_we_sync & ~sample_we_prev;
    assign start_fft = frame_full_sync;

    // --- Input RAM ---
    // Pad 8-bit sample to 32-bit complex word {8'b0, sample, 16'b0}
    // This puts the sample in the "Low Byte of the Real Part" which is 
    // functionally valid (just quiet). 
    // To match your previous 16-bit logic (LOUD), use: {sample, 8'b0, 16'b0}
    
    logic [31:0] extended_word;
    // Current setting: Matches Shreya's logic (Quiet / Unscaled)
    // To make it louder (left shift by 8), change to: {sample_byte_clk, 24'b0}
    assign extended_word = {8'b0, sample_byte_clk, 16'b0};

    ram input_ram (
        .clk(clk),
        .write(sample_we_clk),
        .write_address(sample_index_clk),
        .read_address(fft_read_addr),
        .d(extended_word),
        .q(data_to_fft)
    );

    // ================================================================
    // 2. OUTPUT PATH (32-bit Complex)
    //    Restored from your working spi.sv
    // ================================================================

    logic [31:0] out_spi_data;
    logic [4:0]  rd_bit_cnt;
    logic [8:0]  rd_word_cnt;

    // Output RAM (Stores results from FFT)
    ram output_ram (
        .clk(clk),
        .write(fft_write_en),
        .write_address(fft_write_addr),
        .read_address(rd_word_cnt), // Driven by read counter
        .d(data_from_fft),
        .q(out_spi_data)
    );

    // Read Counter Logic (Runs on SPI Clock)
    always_ff @(posedge sck or posedge reset) begin
        if (reset) begin
            rd_bit_cnt <= 0;
            rd_word_cnt <= 0;
        end else begin
            // Count 32 bits per word
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

    // Output Serializer (Streams 32 bits MSB first)
    assign sdo = out_spi_data[31 - rd_bit_cnt];

endmodule