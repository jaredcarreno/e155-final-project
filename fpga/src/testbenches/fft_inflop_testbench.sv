`timescale 1ns/1ps

// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Simple testbench for fft_in_flop_4096
//          - Provide a 4096-bit frame made of 512 bytes
//          - Check that fft_in_flop_4096:
//                - moves from WAIT to SEND
//                - outputs 512 samples in order (via fft_in32)
//                - asserts fft_start after 512 samples

module fft_in_flop_4096_tb;

    // DUT signals
    logic clk;
    logic reset;
    logic [4095:0] fft_in4096;
    logic fft_processing;
    logic fft_loaded;
    logic fft_done;
    logic out_buf_empty;
    logic out_buf_ready;

    logic [31:0] fft_in32;
    logic fft_load;
    logic fft_start;
    logic [8:0] idx;

    // instantiating the DUT
    fft_in_flop_4096 dut (
        .clk (clk),
        .reset (reset),
        .fft_in4096 (fft_in4096),
        .fft_processing (fft_processing),
        .fft_loaded (fft_loaded),
        .fft_done (fft_done),
        .out_buf_empty (out_buf_empty),
        .out_buf_ready (out_buf_ready),
        .fft_in32 (fft_in32),
        .fft_load (fft_load),
        .fft_start (fft_start),
        .idx (idx)
    );

    // generating a clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // creating a reset task
    task automatic apply_reset;
    begin
        reset = 1'b1;
        fft_in4096 = '0;
        fft_processing = 1'b0;
        fft_loaded = 1'b0;
        fft_done = 1'b0;
        out_buf_empty = 1'b0;
        out_buf_ready = 1'b0;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
    end
    endtask

    // expected data array for 512 samples, where expected_bytes[i] is the 8-bit sample we expect at index i
    logic [7:0] expected_bytes [0:511];

    // ----------------------------------------------------------------
    // building a 4096-bit frame from expected_bytes in the same way (MSB-first)
    // fft_in_flop_4096 uses it:
    //   - q <= fft_in4096
    //   - curr_8 = q[4095:4088]
    task automatic build_frame_from_expected;
        int i;
    begin
        fft_in4096 = 0;
        for (i = 0; i < 512; i = i + 1) begin
            // placing expected_bytes[i]
            fft_in4096[(4095 - 8*i) : (4095 - 8*i - 7)] = expected_bytes[i];
        end
    end
    endtask

    // main stimulus
    initial begin
        int i;
        logic [7:0] actual;

        // initialize signals controlled by testbench
        reset = 1'b0;
        fft_processing = 1'b0;   // FFT core not busy
        fft_loaded = 1'b0;
        fft_done = 1'b0;   // ignoring this on testbench
        out_buf_empty = 1'b0;
        out_buf_ready = 1'b0;
        fft_in4096 = 0;

        // reset test
        $display("Applying reset...");
        apply_reset();
        $display("Reset deasserted.");

        // making sure signals are what they need to be after the reset
        if (fft_load !== 1'b0 || fft_start !== 1'b0) begin
            $display("[TB][WARN] fft_load or fft_start not 0 right after reset.");
        end


        // building the expected pattern
        for (i = 0; i < 512; i = i + 1) begin
            expected_bytes[i] = i[7:0];
        end

        // packing expected_bytes[] into fft_in4096
        build_frame_from_expected();
        $display("Built 4096-bit frame from expected_bytes.");


        // asserting fft_loaded to start SEND behavior and make sure sendReady is true
        @(posedge clk);
        fft_loaded = 1'b1;  // like dataReady from SPI

        // Give a cycle or two for the FSM to move to SEND
        @(posedge clk);
        @(posedge clk);
        $display("fft_loaded asserted; starting to monitor outputs...");

        // 512 sample sequence check
        // when fft_load is high, look at fft_in32 and compare it against expected_bytes[i]
        i = 0;
        while (i < 512) begin
            @(posedge clk);

            if (fft_load) begin
                // Extend32 places the 8-bit sample at bits [23:16]
                actual = fft_in32[23:16];

                if (actual !== expected_bytes[i]) begin
                    $display("ERROR: Sample mismatch at index %0d: got 0x%0h, expected 0x%0h",
                             i, actual, expected_bytes[i]);
                    $fatal(1, "Stopping due to mismatch.");
                end

                i = i + 1;
            end
        end

        $display("All 512 samples matched expected sequence.");

        // fft_start assertion
        // Give a couple more cycles for fft_start to go high
        @(posedge clk);
        @(posedge clk);

        if (fft_start !== 1'b1) begin
            $display("ERROR: fft_start was not asserted after 512 samples.");
            $fatal(1, "Stopping due to missing fft_start.");
        end else begin
            $display("fft_start asserted after 512 samples as expected.");
        end

        // Done
        $display("fft_in_flop_4096 test PASSED.");
        $stop;
    end

endmodule
