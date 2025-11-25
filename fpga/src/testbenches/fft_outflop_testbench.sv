// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Testbench for shreya's out flop

// Clean, minimal, race-free testbench for fft_out_flop_8192

`timescale 1ns/1ps

module fft_out_flop_8192_tb;

    logic clk;
    logic reset;

    logic [31:0] fft_out32;
    logic fft_start;
    logic fft_done;

    logic [8191:0] fft_out8192;
    logic buf_ready;
    logic buf_empty;

    // DUT
    fft_out_flop_8192 dut (
        .clk(clk),
        .reset(reset),
        .fft_out32(fft_out32),
        .fft_start(fft_start),
        .fft_done(fft_done),
        .fft_out8192(fft_out8192),
        .buf_ready(buf_ready),
        .buf_empty(buf_empty)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset
    task automatic apply_reset;
    begin
        reset     = 1;
        fft_out32 = 32'h0;
        fft_start = 0;
        fft_done  = 0;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
    end
    endtask

    // Expected 16-bit words
    logic [15:0] expected_words [0:511];

    // Temp vars must be declared WITHOUT initialization
    logic [7:0] real8;
    logic [7:0] imag8;

    logic [15:0] extracted;

    initial begin
        int i;

        reset = 0;
        fft_start = 0;
        fft_done = 0;
        fft_out32 = 32'h0;

        $display("[TB] Applying reset...");
        apply_reset();
        $display("[TB] Reset released.");

        // Build expected array
        for (i = 0; i < 512; i++) begin
            real8 = i[7:0];
            imag8 = (255 - i) & 8'hFF;
            expected_words[i] = {real8, imag8};
        end

        // Start frame
        fft_start = 1;
        @(negedge clk);
        @(posedge clk);
        fft_start = 0;

        @(posedge clk);

        $display("[TB] Sending 512 samples...");

        // Send samples
        for (i = 0; i < 512; i++) begin
            real8 = i[7:0];
            imag8 = (255 - i) & 8'hFF;

            fft_out32 = {real8, 8'h00, imag8, 8'h00};

            fft_done = 1;
            @(negedge clk);
            fft_done = 0;

            @(posedge clk);
        end

        @(posedge clk);
        @(posedge clk);

        if (!buf_ready) begin
            $display("[TB][ERROR] buf_ready did NOT assert!");
            $fatal;
        end else begin
            $display("[TB] buf_ready asserted!");
        end

        // Verify
        for (i = 0; i < 512; i++) begin
            extracted = fft_out8192[(16*i) +: 16]; // LSB-first
            // extracted = fft_out8192[(8191 - 16*i) -: 16]; // MSB-first extraction

            if (extracted !== expected_words[i]) begin
                $display("[TB][ERROR] mismatch @ index %0d", i);
                $display("Got      = 0x%04h", extracted);
                $display("Expected = 0x%04h", expected_words[i]);
                $fatal;
            end
        end

        $display("[TB] Buffer verified!");
        $display("[TB] TEST PASSED.");
        $stop;
    end

endmodule
