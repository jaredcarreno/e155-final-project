`timescale 1ns/1ps

// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Simple testbench for fft_in_flop_4096
//          - Provide a 4096-bit frame made of 512 bytes
//          - Check that fft_in_flop_4096:
//                - moves from WAIT to SEND
//                - outputs 512 samples in order (via fft_in32)
//                - asserts fft_start after 512 samples

module fft_out_flop_tb;
    // DUT signals
    logic clk;
    logic reset;

    logic [31:0] fft_out32;
    logic fft_start;
    logic fft_done;

    logic [16383:0] fft_out_packet;
    logic buf_ready;

    // instantiate DUT
    fft_out_flop dut (
        .clk(clk),
        .reset(reset),
        .fft_out32(fft_out32),
        .fft_start(fft_start),
        .fft_done(fft_done),
        .fft_out_packet(fft_out_packet),
        .buf_ready(buf_ready)
    );

    // clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // reset task
    task automatic apply_reset;
    begin
        reset = 1'b1;
        fft_out32 = 32'h0;
        fft_start = 1'b0;
        fft_done  = 1'b0;
        @(posedge clk); 
        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
    end
    endtask

    // expected 32-bit words
    logic [31:0] expected_words [0:511];


    initial begin
        int i;

        // init signals
        reset = 0;
        fft_start = 0;
        fft_done  = 0;
        fft_out32 = 32'h0;

        $display("[TB] Applying reset...");
        apply_reset();
        $display("[TB] Reset deasserted.");

        // generate test pattern (word = index)
        for (i = 0; i < 512; i++)
            expected_words[i] = i;

        // start new packet
        @(posedge clk);
        fft_start = 1;
        @(posedge clk);
        fft_start = 0;

        $display("[TB] Sending 512 samples to DUT...");

        // feed 512 words
        for (i = 0; i < 512; i++) begin
            
            fft_out32 = expected_words[i];
            fft_done  = 1;
            @(negedge clk);        // DUT samples on NEG edge

            fft_done = 0;
            $display("[TB][%0t] Sent word %0d = 0x%08h", 
                      $time, i, fft_out32);

            @(posedge clk);        // complete cycle
        end

        // wait 2 cycles for buf_ready
        @(posedge clk);
        @(posedge clk);

        if (!buf_ready) begin
            $display("[TB][ERROR] buf_ready NOT asserted after 512 samples!");
            $fatal(1);
        end else begin
            $display("[TB] buf_ready asserted correctly.");
        end

        // verify packet content (MSB-first shifting)
        $display("[TB] Checking output packet contents...");
        for (i = 0; i < 512; i++) begin
            logic [31:0] extracted;
            extracted = fft_out_packet[(16383 - 32*i) -: 32];

            if (extracted !== expected_words[i]) begin
                $display("[TB][ERROR] Packet mismatch at index %0d:", i);
                $display("       Got      = 0x%08h", extracted);
                $display("       Expected = 0x%08h", expected_words[i]);
                $fatal(1);
            end
        end

        $display("[TB] Packet verified successfully.");
        $display("[TB] TEST PASSED.");
        $stop;
    end

endmodule

