`timescale 1ns/1ps

// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Simple testbench for fft_in_flop_4096
//          - Provide a 4096-bit frame made of 512 bytes
//          - Check that fft_in_flop_4096:
//                - moves from WAIT to SEND
//                - outputs 512 samples in order (via fft_in32)
//                - asserts fft_start after 512 samples

`timescale 1ns/1ps

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

    // Instantiate DUT
    fft_in_flop_4096 dut (
        .clk           (clk),
        .reset         (reset),
        .fft_in4096    (fft_in4096),
        .fft_processing(fft_processing),
        .fft_loaded    (fft_loaded),
        .fft_done      (fft_done),
        .out_buf_empty (out_buf_empty),
        .out_buf_ready (out_buf_ready),
        .fft_in32      (fft_in32),
        .fft_load      (fft_load),
        .fft_start     (fft_start),
        .idx           (idx)
    );

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // simple reset task
    task automatic apply_reset;
    begin
        reset          = 1'b1;
        fft_in4096     = '0;
        fft_processing = 1'b0;
        fft_loaded     = 1'b0;
        fft_done       = 1'b0;
        out_buf_empty  = 1'b0;
        out_buf_ready  = 1'b0;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
    end
    endtask

    // 512 expected bytes
    logic [7:0] expected_bytes [0:511];

    // Pack expected_bytes into fft_in4096, MSB-first:
    // sample 0 -> bits [4095:4088], sample 1 -> [4087:4080], etc.
    task automatic build_frame_from_expected;
        int i;
    begin
        fft_in4096 = '0;
        for (i = 0; i < 512; i = i + 1) begin
            fft_in4096[4095 - 8*i -: 8] = expected_bytes[i];
        end
    end
    endtask

    // Main stimulus
    initial begin
        int i;
        int k;
        int seen;
        logic [7:0] actual;

        // init
        reset          = 1'b0;
        fft_processing = 1'b0;
        fft_loaded     = 1'b0;
        fft_done       = 1'b0;
        out_buf_empty  = 1'b0;
        out_buf_ready  = 1'b0;
        fft_in4096     = '0;

        // 1) Reset
        $display("Applying reset...");
        apply_reset();
        $display("Reset deasserted.");

        // 2) Build expected 0x00, 0x01, ..., 0xFF, ...
        for (i = 0; i < 512; i = i + 1) begin
            expected_bytes[i] = i[7:0];
        end

        // 3) Pack into fft_in4096
        build_frame_from_expected();
        $display("Built 4096-bit frame from expected_bytes.");

        // 4) Pulse fft_loaded for one clock to kick the FSM
        @(posedge clk);
        fft_loaded = 1'b1;
        @(posedge clk);
        fft_loaded = 1'b0;
        $display("Pulsed fft_loaded; now watching outputs...");

        // 5) Bounded loop: watch 512 samples over at most 2000 cycles
        //    NOTE: we sample on **negedge** so the DUT has already updated
        //    its flops on the preceding posedge.
        seen = 0;
        for (k = 0; k < 2000; k = k + 1) begin
            @(negedge clk);  // <-- changed from posedge to negedge

            if (fft_load) begin
                // debug hook if needed:
                // if (seen < 10) begin
                //     $display("t=%0t idx=%0d fft_in32[23:16]=0x%0h expected=0x%0h",
                //              $time, idx, fft_in32[23:16], expected_bytes[idx]);
                // end

                if (idx >= 512) begin
                    $fatal(1, "ERROR: idx out of range (idx=%0d) while fft_load=1.", idx);
                end

                // Extend32 puts the 8-bit sample at bits [23:16]
                actual = fft_in32[23:16];

                // Compare against expected_bytes[idx]
                if (actual !== expected_bytes[idx]) begin
                    $display(1,
                        "ERROR: sample idx=%0d mismatch: got 0x%0h, expected 0x%0h",
                        idx, actual, expected_bytes[idx]
                    );
                end

                seen = seen + 1;
            end
        end

        if (seen != 512) begin
            $fatal(1,
                "TIMEOUT: expected 512 valid samples, only saw %0d fft_load pulses.",
                seen
            );
        end

        $display("All 512 samples matched expected sequence.");

        // 6) Check fft_start after data finished
        @(negedge clk);
        @(negedge clk);

        if (fft_start !== 1'b1) begin
            $fatal(1, "ERROR: fft_start was not asserted after 512 samples.");
        end else begin
            $display("fft_start asserted after 512 samples as expected.");
        end

        $display("fft_in_flop_4096 test PASSED.");
        $finish;
    end

endmodule





