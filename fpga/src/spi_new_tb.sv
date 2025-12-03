// Author(s): Shreya Jampana
// Date: 11/xx/25
// Purpose: Testbench for spi_fft_buffer
//          - Send 4096 bits (512 "bytes") on SDI
//          - Let spi_fft_buffer pack them into its internal 512x32 RAM
//          - Wait for start_fft to assert
//          - Read back all 512 words and verify that data_to_fft[23:16]
//            matches the byte sequence reconstructed with the same shift
//            logic used inside spi_fft_buffer.

`timescale 1ns/1ps

module spi_fft_buffer_tb;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam int FRAME_BITS  = 4096; // 512 * 8
    localparam int NUM_BYTES   = 512;

    // ----------------------------------------------------------------
    // DUT I/O
    // ----------------------------------------------------------------
    logic sck;
    logic sdi;
    logic reset;
    logic clk;

    logic sdo;

    logic [31:0] data_to_fft;
    logic [31:0] data_from_fft;
    logic [8:0]  fft_read_addr;
    logic [8:0]  fft_write_addr;
    logic        fft_write_en;
    logic        start_fft;

    // ----------------------------------------------------------------
    // DUT Instance
    // NOTE: This assumes your module is named spi_fft_buffer with
    // the ports we discussed.
    // ----------------------------------------------------------------
    spi_fft_buffer dut (
        .sck          (sck),
        .sdi          (sdi),
        .reset        (reset),
        .sdo          (sdo),
        .clk          (clk),
        .data_to_fft  (data_to_fft),
        .data_from_fft(data_from_fft),
        .fft_read_addr(fft_read_addr),
        .fft_write_addr(fft_write_addr),
        .fft_write_en (fft_write_en),
        .start_fft    (start_fft)
    );

    // ----------------------------------------------------------------
    // System clock (for RAM and synchronizers)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // We'll drive sck manually in a task so we have full control over
    // exactly when each bit is clocked in.

    // ----------------------------------------------------------------
    // Shadow reconstruction of bytes using SAME shift logic
    // as in spi_fft_buffer (for checking correctness).
    // ----------------------------------------------------------------
    logic [7:0] expected_bytes [0:NUM_BYTES-1];

    // local shadow of SPI shift behavior (SCK domain)
    logic [7:0] tb_shift_reg;
    logic [2:0] tb_bit_cnt;
    int         tb_byte_index;

    // ----------------------------------------------------------------
    // Utility task: send one SPI bit (mode 0 style: sample on posedge)
    // ----------------------------------------------------------------
    task automatic send_one_bit(input logic bit_val);
        begin
            // Set up SDI before rising edge (setup time)
            sdi = bit_val;

            // Rising edge of SCK
            #2;
            sck = 1'b1;
            #3;  // total 5 ns high time

            // At this point, on real hardware, spi_fft_buffer's always_ff
            // @ (posedge sck) will have just executed.

            // Mirror the same shift logic locally:
            // In your code you do:
            //   spi_shift_reg <= {spi_shift_reg[6:0], sdi};
            //   if (bit_cnt_sck == 3'd7)
            //      sample_byte_sck <= {spi_shift_reg[6:0], sdi};
            //   if (bit_cnt_sck == 3'd7) bit_cnt_sck <= 0;
            //   else bit_cnt_sck <= bit_cnt_sck + 1;
            //
            // Because of non-blocking semantics, sample_byte uses
            // the "old" shift_reg. We mirror that here.

            if (tb_bit_cnt == 3'd7) begin
                // capture the "byte" the DUT will see
                expected_bytes[tb_byte_index] = {tb_shift_reg[6:0], bit_val};
                tb_byte_index++;
                tb_bit_cnt = 3'd0;
            end
            else begin
                tb_bit_cnt = tb_bit_cnt + 3'd1;
            end

            tb_shift_reg = {tb_shift_reg[6:0], bit_val};

            // Falling edge of SCK
            sck = 1'b0;
            #5;  // 5 ns low time
        end
    endtask

    // ----------------------------------------------------------------
    // Task: send an entire 4096-bit frame on SDI
    // Here we just use a simple pattern on the bit stream, e.g. i[0]
    // or $urandom, and let the shadow logic figure out what bytes
    // the DUT will see.
    // ----------------------------------------------------------------
    task automatic send_frame;
        int bit_index;
        logic bit_val;
        begin
            $display("[%0t] TB: Starting to send 4096 bits...", $time);

            tb_shift_reg  = 8'h00;
            tb_bit_cnt    = 3'd0;
            tb_byte_index = 0;

            for (bit_index = 0; bit_index < FRAME_BITS; bit_index++) begin
                // Example pattern: alternating bits (bit_index[0])
                bit_val = bit_index[0];
                send_one_bit(bit_val);
            end

            $display("[%0t] TB: Finished sending 4096 bits.", $time);
        end
    endtask

    // ----------------------------------------------------------------
    // Main Stimulus
    // ----------------------------------------------------------------
    initial begin
        int i;
        logic [7:0] actual_byte;

        // Default values
        sck           = 1'b0;
        sdi           = 1'b0;
        reset         = 1'b1;
        data_from_fft = 32'h0;
        fft_write_en  = 1'b0;
        fft_write_addr= 9'd0;
        fft_read_addr = 9'd0;

        $display("[%0t] TB: Applying reset...", $time);

        // Let reset propagate for a few cycles
        repeat (5) @(posedge clk);
        reset = 1'b0;

        $display("[%0t] TB: Reset deasserted.", $time);

        // ----------------------------------------------------------------
        // 1) Send a full 4096-bit frame on SDI
        // ----------------------------------------------------------------
        send_frame();

        // ----------------------------------------------------------------
        // 2) Wait for start_fft to assert in the clk domain
        //     (This means the internal word counter hit 511.)
        // ----------------------------------------------------------------
        $display("[%0t] TB: Waiting for start_fft...", $time);

        int timeout_cycles;
        timeout_cycles = 0;
        while (!start_fft && timeout_cycles < 2000) begin
            @(posedge clk);
            timeout_cycles++;
        end

        if (!start_fft) begin
            $fatal(1, "[%0t] ERROR: start_fft did not assert (timeout).", $time);
        end
        else begin
            $display("[%0t] TB: start_fft asserted.", $time);
        end

        // ----------------------------------------------------------------
        // 3) Read back all 512 words from the input RAM via data_to_fft.
        //    We expect data_to_fft = {8'h00, expected_bytes[i], 16'h0000}.
        //    Note: RAM has one-cycle read latency.
        // ----------------------------------------------------------------
        $display("[%0t] TB: Reading back 512 words from input RAM...", $time);

        // Prime address 0, let data_to_fft pipe in
        fft_read_addr = 9'd0;
        @(posedge clk);  // first read (data for addr 0 appears now)

        for (i = 0; i < NUM_BYTES; i++) begin
            // At this point, data_to_fft corresponds to address fft_read_addr.
            actual_byte = data_to_fft[23:16];

            if (actual_byte !== expected_bytes[i]) begin
                $display("[%0t] ERROR: Mismatch at index %0d", $time, i);
                $display("  Got byte      = 0x%02h", actual_byte);
                $display("  Expected byte = 0x%02h", expected_bytes[i]);
                $fatal(1, "TB: DATA MISMATCH.");
            end

            // Move to next address
            fft_read_addr = i + 1;
            @(posedge clk);
        end

        $display("[%0t] TB: All 512 words matched expected bytes.", $time);
        $display("[%0t] TB: TEST PASSED.", $time);

        #50;
        $finish;
    end

endmodule
