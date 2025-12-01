
// Author(s): Shreya Jampana
// Date: 11/18/25
// Purpose: Simple testbench for fft_spi
//          - Send 4096 bits on SDI
//          - Observe that fft_input fills as expected
//          - Observe that fft_loaded asserts after one full frame
//          - Capture SDO bits and (optionally) compare against fft_output preamble

`timescale 1ns/1ps

module fft_spi_tb;

  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------
  localparam int FRAME_BITS = 4096;
  localparam int FFT_WIDTH  = 4096;

  // ------------------------------------------------------------
  // DUT I/O
  // ------------------------------------------------------------
  logic                 sck;
  logic                 reset;
  logic                 sdi;
  logic                 sdo;
  logic [FRAME_BITS-1:0] fft_input;
  logic                 fft_loaded;
  logic [FFT_WIDTH-1:0] fft_output;

  // ------------------------------------------------------------
  // DUT Instance
  // ------------------------------------------------------------
  fft_spi dut (
    .sck(sck),
    .reset(reset),
    .sdi(sdi),
    .sdo(sdo),
    .fft_input(fft_input),
    .fft_loaded(fft_loaded),
    .fft_output(fft_output)
  );

  // ------------------------------------------------------------
  // Clock Generation
  // ------------------------------------------------------------
  initial begin
    sck = 0;
    forever #5 sck = ~sck;
  end

  // ------------------------------------------------------------
  // Pre-declare all variables used in initial blocks and tasks
  // ------------------------------------------------------------
  int i;
  logic [FRAME_BITS-1:0] frame_in_0;
  logic [FRAME_BITS-1:0] frame_out_0;
  logic [FRAME_BITS-1:0] frame_in_1;
  logic [FRAME_BITS-1:0] frame_out_1;

  // ------------------------------------------------------------
  // Task: Send a 4096-bit frame
  // ------------------------------------------------------------
  task send_frame(
    input  logic [FRAME_BITS-1:0] mosi,
    output logic [FRAME_BITS-1:0] miso,
    input  string label
  );
    begin
      $display("[%0t] === Start Sending %s ===", $time, label);

      for (i = 0; i < FRAME_BITS; i++) begin

        // Drive SDI BEFORE posedge (LSB-first)
        sdi = mosi[FRAME_BITS-1-i];

        @(posedge sck);
        miso[i] = sdo;

        $display("[%0t] %s POS bit=%0d SDI=%0b SDO=%0b loaded=%0b counter=%0d",
                 $time, label, i, sdi, sdo, fft_loaded, dut.counter);

        @(negedge sck);

        $display("[%0t] %s NEG bit=%0d SDI=%0b SDO=%0b loaded=%0b counter=%0d",
                 $time, label, i, sdi, sdo, fft_loaded, dut.counter);

      end

      $display("[%0t] === End Sending %s ===", $time, label);
    end
  endtask

  // ------------------------------------------------------------
  // Main Stimulus
  // ------------------------------------------------------------
  initial begin
    reset = 1;
    sdi   = 0;

    // Initialize FFT output
    fft_output = '0;
    fft_output[63:32] = 32'hDEADBEEF;
    fft_output[31:16] = 16'h5A5A;
    fft_output[15:0]  = 16'hA5A5;

    $display("[%0t] TB: Reset asserted", $time);

    repeat (3) @(negedge sck);
    reset = 0;
    $display("[%0t] TB: Reset deasserted", $time);

    repeat (2) @(negedge sck);

    // ----------------------------------------------------------
    // Frame 0: Alternating bits
    // ----------------------------------------------------------
    for (i = 0; i < FRAME_BITS; i++) begin
      frame_in_0[i] = (i & 1);
    end

    send_frame(frame_in_0, frame_out_0, "FRAME0");
	
	@(negedge sck);

    if (fft_loaded)
      $display("[%0t] TB: fft_loaded is HIGH after frame0", $time);
    else
      $display("[%0t] TB WARNING: fft_loaded NOT high!", $time);
	  
	#1; 
	// After frame 0
	if (fft_input !== frame_in_0) begin
		$display("[%0t] TB ERROR: fft_input != frame_in_0", $time);
		$display("fft_input = %0h", fft_input);
		$display("frame_in_0 = %0h", frame_in_0);
		$fatal;
	end else begin
		$display("[%0t] TB: fft_input matches frame_in_0", $time);
	end


    // ----------------------------------------------------------
    // Frame 1: Random data
    // ----------------------------------------------------------
    for (i = 0; i < FRAME_BITS; i++) begin
      frame_in_1[i] = $urandom_range(0,1);
    end

    send_frame(frame_in_1, frame_out_1, "FRAME1");

    $display("[%0t] TB: Done with frame1. fft_loaded=%0b", $time, fft_loaded);

    #40;
    $display("[%0t] TB: Simulation finished", $time);
    $finish;
  end

endmodule