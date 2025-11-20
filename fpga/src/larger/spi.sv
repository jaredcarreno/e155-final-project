// spi.sv - Adapted for 8-bit In / 512 Points

module fft_spi(
    input logic sck, reset, sdi,
    output logic sdo,
    output logic [4095:0] fft_input,   // 4096 bits IN
    output logic fft_loaded,
    input  logic [16383:0] fft_output  // 16384 bits OUT
);
    logic [13:0] cnt; 
    logic [16383:0] out_shift_reg; 

    always_ff @(negedge sck) begin
        if (reset) cnt <= 0;
        else cnt <= cnt + 1;
    end

    // Input Path (4096 bits)
    always_ff @(posedge sck) begin
        if (reset) fft_input <= 0;
        else fft_input <= {fft_input[4094:0], sdi};
    end

    // Output Path (16384 bits)
    always_ff @(negedge sck) begin
        if (reset) begin
            out_shift_reg <= 0;
        end else if (cnt == 0) begin
            out_shift_reg <= fft_output; 
        end else begin
            out_shift_reg <= {out_shift_reg[16382:0], 1'b0};
        end
    end

    assign sdo = out_shift_reg[16383];
    assign fft_loaded = (cnt == 14'd4096);
endmodule


// Input Buffer: 4096 bits -> 32-bit Core
module fft_in_flop(
    input logic clk, reset,
    input logic [4095:0] fft_in_packet,
    input logic fft_processing, fft_loaded, fft_done,
    
    output logic [31:0] fft_in32,
    output logic fft_load, fft_start,
    output logic [8:0] idx
);
    typedef enum logic {WAIT, SEND} state;
    state currState, nextState;
    
    logic [9:0] count; 
    logic [4095:0] q, d, d_shift;
    logic [7:0] curr_8; // 8-bit chunk
    logic sendReady;

    assign curr_8 = q[4095:4088]; 
    assign idx = count[8:0]; 
    assign sendReady = (!fft_processing) && fft_loaded && (!fft_done);

    always_ff @(posedge clk) begin
        if (reset || currState == WAIT) count <= 0;
        else if (count < 10'd512) count <= count + 1;
    end

    always_ff @(posedge clk) begin
        if (reset) q <= 0;
        else if (currState == WAIT) q <= fft_in_packet;
        else q <= d;
    end

    always_comb begin
        d_shift = q; d = q;
        if (count < 10'd512) begin
            d_shift = q << 8; // Shift 8 bits
            d = d_shift;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) currState <= WAIT; else currState <= nextState;
    end

    always_comb begin
        nextState = currState;
        case (currState)
            WAIT: if (sendReady && count != 10'd512) nextState = SEND;
            SEND: if (count == 10'd511) nextState = WAIT;
        endcase
    end

    assign fft_start = (count == 10'd512);
    assign fft_load  = (currState == SEND) && (!fft_processing);

    // 8-bit to 32-bit PADDING
    Extend32 extend(.a(curr_8), .b(fft_in32));
endmodule

// Output Buffer: 32-bit Core -> 16384 bits
module fft_out_flop(
    input logic clk, reset,
    input logic [31:0] fft_out32, 
    input logic fft_start, fft_done, 

    output logic [16383:0] fft_out_packet, 
    output logic buf_ready
);
    logic [9:0] cnt; 
    logic [16383:0] q, d, d_shift;

    always_ff @(negedge clk) begin
        if (reset || fft_start) cnt <= 0;
        else if (fft_done && cnt < 10'd512) cnt <= cnt + 1;
    end

    always_ff @(negedge clk) begin
        if (reset) q <= 0; else q <= d;
    end

    always_comb begin
        d_shift = q; d = q;
        if (cnt < 10'd512) begin
            d_shift = q << 32;
            d = {d_shift[16383:32], fft_out32};
        end
    end

    assign fft_out_packet = q;
    assign buf_ready = (cnt == 10'd512);
endmodule

module Extend32(input logic [7:0] a, output logic [31:0] b);
    assign b = {8'b0, a, 16'b0};
endmodule