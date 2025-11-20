// Author(s): Shreya Jampana
// Date: 11/17/25
// Purpose: 1024-bit SPI interface between MCU and FFT on FPGA

module fft_spi(input logic sck,
               input logic reset,
               input logic sdi, //COPI (MCU -> FPGA)
               output logic sdo, //CIPO (FPGA -> MCU)
               output logic [4095:0] fft_input, //from sdi, to be fed into FFT
               output logic fft_loaded, //high when fill 4096-bit frame is received
               input  logic [8191:0] fft_output //8191-bit output from FFT, to be fed into sdo
               ); 

    // Counts how many bits have been shifted during the current frame
    // 12 bits to represent up to 4096
    logic [11:0] counter;

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
            if (counter == 0) begin
                // for first bit of frame, copy fft_output[1022:0] into upper bits of
                // fft_input and bring the first sdi bit into the LSB
                fft_input <= {fft_output[4094:0], sdi};
            end else begin
                // for the rest of the bits, shift left and add new sdi bit at LSB
                fft_input <= {fft_output[8190:0], sdi};
            end
        end
    end

    // preparing the next cipo bit on the negedge of the clock
    always_ff @(negedge sck) begin
        if (reset) begin
            // just sending a default bit until the first bit is ready
            cipo_next <= 1'b0;
        end else begin
            // holding MSB so cipo_next can drive cipo on the next rising edge
            cipo_next <= fft_input[4095];
        end
    end

    // driving the sdo
    always_comb begin
        if (counter == 0) begin
            // very first bit out is the MSB of the previous FFT result
            sdo = fft_output[8191];
        end else begin
            // all subsequent bits are from the shifted fft_input
            sdo = cipo_next;  
        end
    end

    // goes high once we've seen 1024 bits, indicating fft_input holding a full 4096 bit frame
    assign fft_loaded = (counter == 12'd4096);

endmodule


// Every time the FFT core produces a new 32-bit output word, we pack it into a 4096-bit buffer.
// We only keep 16 bits per FFT output (real[31:24], imag[15:8])
// 512 complex outputs → 512 × 16 = 8192 bits total.module fft_out_flop_8192
    input logic clk, // from FPGA
    input logic [31:0] fft_out32, // from FFT
    input logic fft_start, // to reset cnt at start of a new frame
    input logic fft_done, // to indicate that the 32-bit word is valid (from FFT)
    input logic reset, 

    output logic [8191:0] fft_out8192, // to SPI
    output logic buf_ready, // indicating buffer is full (256 words stored)
    output logic buf_empty // indicating buffer is empty (0 words stored)
);

    logic [8:0] cnt; // counts how many 16-bit {real8,imag8} values we stored
    logic [8191:0] q; // main 4096-bit buffer
    logic [8191:0] d; // next value for q
    logic [8191:0] d_shift; // shifted buffer

    // we now only care about 8-bit real and 8-bit imag parts from fft_out32
    logic [7:0] fft_real8;     
    logic [7:0] fft_imag8;     
    logic [15:0] fft_packed16; 

    // slicing and packing the meaningful bits from fft_out32
    assign fft_real8 = fft_out32[31:24];  
    assign fft_imag8 = fft_out32[15:8];    
    assign fft_packed16 = {fft_real8, fft_imag8};

    // counter code
    always_ff @(negedge clk) begin
        if (reset || fft_start) begin
            cnt <= 0; // new frame
        end else if (fft_done) begin
            if (cnt < 8'd512) begin
                cnt <= cnt + 1; // count another word
            end else begin
                cnt <= cnt; // hold at 512
            end
        end else begin
            cnt <= cnt; // no change
        end
    end

    // dealing with data register q
    always_ff @(negedge clk) begin
        if (reset) begin
            q <= 0;
        end else begin
            q <= d; // take the next packed value
        end
    end

    // logic for next value
    always_comb begin
        
        // default: hold current value
        d_shift = q;
        d = q;

        // only shift if we have not yet stored 512 words
        if (cnt < 8'd512) begin
            // shift left by 16 bits
            d_shift = q << 16;

            // insert the 16-bit {real8, imag8} into the lowest 16 bits
            d = {d_shift[8191:16], fft_packed16};
        end
        else begin
            // if cnt == 512: hold q unchanged
            d = q;
            d_shift = q;
        end
    end

    // outputs
    assign fft_out8192 = q;
    assign buf_ready = (cnt == 8'd512); // buffer is full
    assign buf_empty = (cnt == 0); // buffer is empty

endmodule




// Some points about what this module does with the new 4096 bit frames we get from the MCU: 
// - waits in WAIT state until fft_loaded says a 4096-bit frame is ready
// - in SEND state, shifts out 8-bit samples from fft_in4096
// - extends each 8-bit sample to 32 bits via Extend32
// - asserts fft_load while sending samples to the FFT core
// - after 512 samples, asserts fft_start once and returns to WAIT

module fft_in_flop_4096(
    input logic clk,   
    input logic reset,
    input logic [4095:0] fft_in4096, // frame from SPI
    input logic fft_processing, // FFT core is busy
    input logic fft_loaded, // frame is ready from SPI (like dataReady)
    input logic fft_done, // FFT finished (optional, for handshakes)
    input logic out_buf_empty, // from fft_out_flop_4096 (not used here)
    input logic out_buf_ready, // from fft_out_flop_4096 (not used here)

    output logic [31:0] fft_in32, // to FFT core
    output logic fft_load, // telling the FFT core the next sample is valid
    output logic fft_start, // telling FFT it has sent all the samples
    output logic [8:0] idx  // sample index currently sending into FFT core
);

    typedef enum logic {WAIT, SEND} state;
    state currState;
    state nextState;
    logic [8:0] count; // counts how many 8-bit samples have been sent 
    logic [4095:0] q;  // local copy of the 4096-bit frame that we shift
    logic [4095:0] d; // next value for q
    logic [4095:0] d_shift; // shifted version of q
    logic [7:0] curr_8; // current 8-bit sample from q that will be expanded
    logic sendReady; // condition for leaving WAIT and entering SEND state

    assign curr_8 = q[4095:4088]; // next 8-bit sample is always the 8 MSBs of q
    assign idx = count; // expose the sample index for debugging

    // conditions at which to send samples
    assign sendReady = (!fft_processing) && fft_loaded && (!fft_done);

    // flip flop for the counter
    always_ff @(posedge clk) begin
        if (reset) begin
            count <= 0;
        end else begin
            if (currState == WAIT) begin
                count <= 0; // keeping count the same
            end else begin
                // In SEND: count how many samples we have sent
                if (count < 9'd512) begin
                    count <= count + 1;
                end else begin
                    count <= count; // hold at 512 if reached
                end
            end
        end
    end


    // flip flop for the data
    always_ff @(posedge clk) begin
        if (reset) begin
            q <= 0;
        end else begin
            if (currState == WAIT) begin
                // in WAIT: latch the whole 4096-bit frame from SPI
                q <= fft_in4096;
            end else begin
                // in SEND: use the shifted version
                q <= d;
            end
        end
    end

    // for the next q value, shift left by 8 bits while sending
    always_comb begin
        // defaults: hold q as-is
        d_shift = q;
        d = q;

        // only shift while we have not yet sent all 512 samples.
        if (count < 9'd512) begin
            // shift left by 8 bits, moving the next sample into MSB position
            d_shift = q << 8;
            d = d_shift;
        end else begin
            // keep q unchanged if count = 512
            d_shift = q;
            d = q;
        end
    end

    // flip flop for the state
    always_ff @(posedge clk) begin
        if (reset) begin
            currState <= WAIT;
        end else begin
            currState <= nextState;
        end
    end

    // next state logic
    always_comb begin
        // default: stay where we are
        nextState = currState;

        case (currState)
            WAIT: begin
                // if ready and not already "done", start sending samples.
                if (sendReady && (count != 9'd512)) begin
                    nextState = SEND;
                end else begin
                    nextState = WAIT;
                end
            end

            SEND: begin
                // go back to WAIT after sending the last sample
                if (count == 9'd511) begin
                    nextState = WAIT;
                end else begin
                    nextState = SEND;
                end
            end

            default: begin
                nextState = WAIT;
            end
        endcase
    end

    // asserting that all samples from this frame have been sent
    assign fft_start = (count == 9'd512);

    // valid whenever we are in SEND and the core is not currently processing.
    assign fft_load  = (currState == SEND) && (!fft_processing);


    // using Extend32 to map the 8-bit real sample into a 32-bit FFT input word
    Extend32 extend(.data(curr_8), .extended(fft_in32));

endmodule


module Extend32(
    input logic [7:0] data,
    output logic [31:0] extended);

    assign extended = {{8'b0}, data, {16'b0}};
endmodule