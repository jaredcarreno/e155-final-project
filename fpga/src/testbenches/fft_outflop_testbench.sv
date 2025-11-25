`timescale 1ns/1ps

// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Testbench for shreya's out flop

`timescale 1ns/1ps

module fft_out_flop_8192_tb;

    // DUT signals
    logic clk;
    logic reset;

    logic [31:0] fft_out32;
    logic fft_start;
    logic fft_done;

    logic [8191:0] fft_out8192;
    logic buf_ready;
    logic buf_empty;

    // ----------------------
    // Instantiate DUT
    // ----------------------
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

    // ----------------------
    // Clock generator
    // ----------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------
    // Reset task
    // ----------------------
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

    // ----------------------
    // Expected 16-bit data words
    // ----------------------
    logic [15:0] expected_words [0:511];

    // ----------------------
    // Main Test Logic
    // ----------------------
    initial begin
        int i;

        // Initialize
        reset     = 0;
        fft_start = 0;
        fft_done  = 0;
        fft_out32 = 32'h0;

        $display("[TB] Applying reset...");
        apply_reset();
        $display("[TB] Reset complete.");

        // ----------------------
        // Prepare expected data
        // ----------------------
        for (i = 0; i < 512; i++) begin
            logic [7:0] real8 = i[7:0];
            logic [7:0] imag8 = (255 - i)[7:0];

            expected_words[i] = {real8, imag8};
        end

        // ----------------------
        // Start new frame
        // ----------------------
        @(posedge clk);
        fft_start = 1;
        @(posedge clk);
        fft_start = 0;

        $display("[TB] Sending 512 samples...");

        // ----------------------
        // Drive 512 FFT outputs
        // ----------------------
        for (i = 0; i < 512; i++) begin
            logic [7:0] real8 = i[7:0];
            logic [7:0] imag8 = (255 - i)[7:0];

            // Construct fft_out32 so DUT extracts [31:24] and [15:8]
            fft_out32 = {real8, 8'h00, imag8, 8'h00};

            fft_done = 1;
            @(negedge clk);   // DUT samples at NEG edge
            fft_done = 0;

            $display("[TB %0t] Sent index %0d, packed16 = 0x%04h",
                     $time, i, expected_words[i]);

            @(posedge clk);
        end

        // Allow time for buffer_ready
        @(posedge clk);
        @(posedge clk);

        if (!buf_ready) begin
            $display("[TB][ERROR] buf_ready did NOT assert!");
            $fatal;
        end else begin
            $display("[TB] buf_ready asserted correctly.");
        end

        // ----------------------
        // Verify buffer contents
        // ----------------------
        $display("[TB] Checking output buffer...");

        for (i = 0; i < 512; i++) begin
            logic [15:0] extracted;

            // Extract MSB-first shifted 16-bit chunks
            extracted = fft_out8192[(8191 - 16*i) -: 16];

            if (extracted !== expected_words[i]) begin
                $display("[TB][ERROR] Mismatch at index %0d", i);
                $display("   Got      = 0x%04h", extracted);
                $display("   Expected = 0x%04h", expected_words[i]);
                $fatal;
            end
        end

        $display("[TB] Buffer verified correctly.");
        $display("[TB] TEST PASSED.");
        $stop;
    end

endmodule
