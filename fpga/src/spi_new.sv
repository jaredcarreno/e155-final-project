// Author(s): Shreya Jampana
// Date: 11/XX/25
// Purpose: SPI <-> FFT buffer
// - Receives 8-bit real samples over SPI (sdi, sck)
// - Packs each 8-bit sample into a 32-bit word: {8'b0, sample, 16'b0}
// - Stores 512 such words in a 512x32 RAM
// - Exposes them to the FFT controller via data_to_fft / fft_read_addr
// - Asserts start_fft when 512 samples have been captured
//
// NOTE: This module replaces the old 4096-bit shift-register SPI scheme.
//       Port list matches fft.sv's instantiation exactly, so no changes
//       are needed in fft.sv or fft_controller.sv.

module spi_fft_buffer (
    input  logic sck,        // SPI clock
    input  logic sdi,        // SPI data in (MCU -> FPGA)
    input  logic reset,      // async reset for SPI domain
    output logic sdo,        // SPI data out (FPGA -> MCU), currently unused
    input  logic clk,        // system clock (same domain as FFT)

    // Interface to FFT controller
    output logic [31:0] data_to_fft,
    input  logic [31:0] data_from_fft,  // unused for now
    input  logic [8:0]  fft_read_addr,  // FFT read address into this RAM
    input  logic [8:0]  fft_write_addr, // unused for now
    input  logic        fft_write_en,   // unused for now
    output logic        start_fft       // goes high when 512 samples captured
);

    // ================================================================
    // 1. SPI domain: shift in 8-bit samples, count them
    // ================================================================

    // We collect 8 bits per sample.
    logic [7:0] spi_shift_reg;     // holds current assembling byte
    logic [2:0] bit_cnt_sck;       // 0..7 within a sample
    logic [8:0] sample_cnt_sck;    // 0..511 samples in a frame

    // One-cycle strobe in SPI clock domain: "a sample has just completed"
    logic       sample_we_sck;

    // Latches for the just-completed sample (in SPI domain)
    logic [7:0] sample_byte_sck;
    logic [8:0] sample_index_sck;

    // Goes high once a full frame (512 samples) has been received
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
            // Shift in 1 bit per SPI clock
            spi_shift_reg <= {spi_shift_reg[6:0], sdi};
            sample_we_sck <= 1'b0;   // default

            if (bit_cnt_sck == 3'd7) begin
                // Just collected 8 bits -> 1 byte sample complete
                bit_cnt_sck      <= 3'd0;
                sample_we_sck    <= 1'b1;
                sample_byte_sck  <= {spi_shift_reg[6:0], sdi}; // full assembled byte
                sample_index_sck <= sample_cnt_sck;             // address for this sample

                // Increment sample count (0..511), wrap around at 512
                if (sample_cnt_sck == 9'd511) begin
                    sample_cnt_sck <= 9'd0;
                    frame_full_sck <= 1'b1; // one full frame captured
                end else begin
                    sample_cnt_sck <= sample_cnt_sck + 9'd1;
                end
            end else begin
                bit_cnt_sck <= bit_cnt_sck + 3'd1;
            end
        end
    end

    // ================================================================
    // 2. Cross to system clock domain: write samples into 512x32 RAM
    // ================================================================

    // Synchronizers for "sample_we" and "frame_full"
    logic sample_we_meta, sample_we_sync, sample_we_prev;
    logic frame_full_meta, frame_full_sync;

    // Sample index and byte in clk domain
    logic [7:0] sample_byte_clk;
    logic [8:0] sample_index_clk;

    // Treat these as "latest valid sample at clk edge" when strobe fires
    wire sample_we_clk;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_we_meta     <= 1'b0;
            sample_we_sync     <= 1'b0;
            sample_we_prev     <= 1'b0;
            frame_full_meta    <= 1'b0;
            frame_full_sync    <= 1'b0;
            sample_byte_clk    <= 8'd0;
            sample_index_clk   <= 9'd0;
        end else begin
            // Simple 2-flop synchronization for the strobe
            sample_we_meta  <= sample_we_sck;
            sample_we_sync  <= sample_we_meta;
            sample_we_prev  <= sample_we_sync;

            // Sync frame_full as well (it can be level-based)
            frame_full_meta <= frame_full_sck;
            frame_full_sync <= frame_full_meta;

            // On a rising edge of the synchronized strobe, capture sample data
            if (sample_we_clk) begin
                sample_byte_clk  <= sample_byte_sck;
                sample_index_clk <= sample_index_sck;
            end
        end
    end

    // Rising edge detect of sample_we_sync
    assign sample_we_clk = sample_we_sync & ~sample_we_prev;

    // We keep start_fft high once a full frame is available
    assign start_fft = frame_full_sync;

    // ================================================================
    // 3. 512x32 RAM: holds 32-bit words for the FFT
    // ================================================================

    // We mimic your old Extend32 behavior:
    //   extended = {8'b0, data[7:0], 16'b0};
    // So real = {8'b0, sample}, imag = 16'b0.
    logic [31:0] extended_word;

    always_comb begin
        extended_word = { 8'b0, sample_byte_clk, 16'b0 };
    end

    // This RAM is defined in memory_units.sv:
    //   module ram(
    //       input  logic        clk, write,
    //       input  logic [8:0]  write_address, read_address,
    //       input  logic [31:0] d,
    //       output logic [31:0] q
    //   );
    //
    // We use sample_index_clk as write address when a sample is ready.
    ram input_ram (
        .clk          (clk),
        .write        (sample_we_clk),
        .write_address(sample_index_clk),
        .read_address (fft_read_addr),
        .d            (extended_word),
        .q            (data_to_fft)
    );

    // ================================================================
    // 4. Output path (FFT -> MCU over SDO)
    // ================================================================
    // For now, we are not using the FFT's output data in this module.
    // The ports data_from_fft, fft_write_addr, and fft_write_en are
    // kept for compatibility with fft.sv, but not implemented here.
    // You can later add a second RAM and a serializer if you want to
    // stream FFT results back to the MCU over sdo.

    assign sdo = 1'b0;  // placeholder; MCU will just see zeros for now

endmodule