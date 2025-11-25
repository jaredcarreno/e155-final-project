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
                // for first bit of frame, copy fft_output[4094:0] into upper bits of
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

    // goes high once we've seen 4096 bits, indicating fft_input holding a full 4096 bit frame
    assign fft_loaded = (counter == 12'd4096);

endmodule


// Every time the FFT core produces a new 32-bit output word, we pack it into a 4096-bit buffer.
// We only keep 16 bits per FFT output (real[31:24], imag[15:8])
// 512 complex outputs → 512 × 16 = 8192 bits total.
module fft_out_flop_8192 (
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
            if (cnt < 512) begin
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
        if (cnt < 512) begin
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
    assign buf_ready = (cnt == 512); // buffer is full
    assign buf_empty = (cnt == 0); // buffer is empty

endmodule

// Some points about what this module does with the new 4096 bit frames we get from the MCU: 
// - waits in WAIT state until fft_loaded says a 4096-bit frame is ready
// - in SEND state, shifts out 8-bit samples from fft_in4096
// - extends each 8-bit sample to 32 bits via Extend32
// - asserts fft_load while sending samples to the FFT core
// - after 512 samples, asserts fft_start once and returns to WAIT

module fft_in_flop_4096(
    input  logic        clk,   
    input  logic        reset,
    input  logic [4095:0] fft_in4096,   // frame from SPI
    input  logic        fft_processing, // FFT core is busy
    input  logic        fft_loaded,     // pulse: new 4096-bit frame ready
    input  logic        fft_done,       // FFT finished (not really used here)
    input  logic        out_buf_empty,  // from fft_out_flop_4096 (unused)
    input  logic        out_buf_ready,  // from fft_out_flop_4096 (unused)

    output logic [31:0] fft_in32,       // to FFT core
    output logic        fft_load,       // next sample is valid
    output logic        fft_start,      // last sample has been sent
    output logic [8:0]  idx             // sample index (0..511)
);

    typedef enum logic {WAIT, SEND} state_t;
    state_t currState;
    state_t nextState;

    logic [8:0]  count;       // how many 8-bit samples have been sent (0..511)
    logic [4095:0] q;         // 4096-bit shift register
    logic [7:0]  curr_8;      // current 8-bit sample
    logic        frame_valid; // we have a valid frame latched

    assign curr_8 = q[4095:4088]; // always take the MSB 8 bits as current sample
    assign idx    = count;        // expose index for debugging / testbench

    // Map 8-bit sample into 32-bit word
    Extend32 extend (.data(curr_8), .extended(fft_in32));

    // Valid when in SEND and FFT is not busy
    assign fft_load  = (currState == SEND) && !fft_processing;

    // Assert start on the last sample (sample 511) while actively sending
    assign fft_start = (currState == SEND) && !fft_processing && (count == 9'd511);

    // next state logic
    always_comb begin
        nextState = currState;

        case (currState)
            WAIT: begin
                // Move to SEND only when a new frame arrives
                if (fft_loaded && !frame_valid) begin
                    nextState = SEND;
                end
            end

            SEND: begin
                // When we've just sent sample 511, go back to WAIT
                if (!fft_processing && (count == 9'd511)) begin
                    nextState = WAIT;
                end
            end

            default: begin
                nextState = WAIT;
            end
        endcase
    end

    // sequential logic
    always_ff @(posedge clk) begin
        if (reset) begin
            currState   <= WAIT;
            count       <= 9'd0;
            q           <= '0;
            frame_valid <= 1'b0;
        end else begin
            currState <= nextState;

            case (currState)
                WAIT: begin
                    // In WAIT, if a new frame arrives, latch it and get ready.
                    if (fft_loaded && !frame_valid) begin
                        q           <= fft_in4096;
                        frame_valid <= 1'b1;
                        count       <= 9'd0;
                    end
                    else begin
                        // stay idle
                        count <= 9'd0;
                    end
                end

                SEND: begin
                    if (!fft_processing) begin
                        // We are sending one sample per cycle.
                        // Current sample is curr_8; after this, shift.
                        if (count < 9'd511) begin
                            // shift left by 8 bits so the next sample moves into MSB position
                            q     <= q << 8;
                            count <= count + 9'd1;
                        end
                        else begin
                            // Just sent sample 511 (last one)
                            // Next cycle we will transition back to WAIT.
                            q           <= q;        // no more shifting needed
                            count       <= count;    // hold at 511
                            frame_valid <= 1'b0;     // frame has been fully consumed
                        end
                    end
                    else begin
                        // FFT is busy; hold everything
                        q     <= q;
                        count <= count;
                    end
                end

                default: begin
                    currState   <= WAIT;
                    count       <= 9'd0;
                    q           <= '0;
                    frame_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule


module Extend32(
    input logic [7:0] data,
    output logic [31:0] extended);

    assign extended = {{8'b0}, data, {16'b0}};
endmodule