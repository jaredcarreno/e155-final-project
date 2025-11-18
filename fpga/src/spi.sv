// Author(s): Shreya Jampana
// Date: 11/17/25
// Purpose: 1024-bit SPI interface between MCU and FFT on FPGA

module fft_spi(input logic sck,
               input logic reset,
               input logic sdi, //COPI (MCU -> FPGA)
               output logic sdo, //CIPO (FPGA -> MCU)
               output logic [1023:0] fft_input, //from sdi, to be fed into FFT
               output logic fft_loaded, //high when fill 1024-bit frame is received
               input  logic [1023:0] fft_output //1024-bit output from FFT, to be fed into sdo
               ); 

    // Counts how many bits have been shifted during the current frame
    // 11 bits to represent up to 1024
    logic [10:0] counter;

    // holds the next bit to drive on sdo
    logic cipo_next;

    // reset starts a new frame
    // doing this on negedge because counter increments on falling edge
    always_ff @(negedge sck) begin
        if (reset) begin
            counter <= 0;
        end else begin
            counter <= counter + 1;
        end
    end

    // shifting in data from the sdi on the posedge of the clock
    always_ff @(posedge sck) begin
        if (reset) begin
            fft_input <= 0;
        end else begin
            if (bit_count == 0) begin
                // for first bit of frame, copy fft_output[1022:0] into upper bits of
                // fft_input and bring the first sdi bit into the LSB
                fft_input <= {fft_output[1022:0], sdi};
            end else begin
                // for the rest of the bits, shift left and add new sdi bit at LSB
                fft_input <= {fft_input[1022:0], sdi};
            end
        end
    end

    // preparing the next cipo bit on the negedge of the clock
    always_ff @(negedge sck) begin
        if (reset) begin
            // default until first real bit is handled
            cipo_next <= 1'b0;
        end else begin
            // holding MSB so cipo_next can drive cipo on the next rising edge
            cipo_next <= fft_input[1023];
        end
    end

    // driving the sdo
    always_comb begin
        if (bit_count == 0) begin
            // very first bit out is the MSB of the previous FFT result
            sdo = fft_output[1023];
        end else begin
            // all subsequent bits are from the shifted fft_input
            sdo = cipo_next;  
        end
    end

    // goes high once we've seen 1024 bits, indicating fft_input holding a full 1024 bit frame
    assign fft_loaded = (bit_count == 11'd1024);

endmodule

