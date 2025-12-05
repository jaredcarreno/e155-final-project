// Testbench modified for a 512-point FFT
module fft_testbench();
   
   logic clk, ram_clk, slow_clk;
   logic start, load, done, reset;
   logic signed [15:0] expected_re, expected_im, wd_re, wd_im;
   logic [31:0]        rd, wd;
   logic [31:0]        idx, out_idx, expected;
   
   // CHANGE 1: Address width updated to [8:0] for 512 points
   logic [8:0]            rd_adr;
   assign rd_adr = idx[8:0];

   // CHANGE 2: Array depth increased to 512
   logic [31:0]          input_data [0:511];
   logic [31:0]        expected_out [0:511];
   
   integer             f; // file pointer

   fft_controller dut (
    .clk(clk), 
    .ram_clk(ram_clk),      
    .slow_clk(slow_clk),    
    .reset(reset), 
    .start(start), 
    .load(load), 
    .load_address(rd_adr),  
    .data_in(rd),           
    .done(done), 
    .processing(),        
    // Output unused in TB, leave unconnected
    .data_out(wd)           
   );

   // Clock Generation
   always begin
       clk = 1; #5; clk=0; #5;
   end

   always begin
       ram_clk = 1; #10; ram_clk=0; #10;
   end

   always begin
       slow_clk = 1; #20; slow_clk=0; #20;
   end
   
   // start of test: load `input_data`, `expected_out`, open output file, reset fft module.
   initial begin
    // Note: You must generate new 512-line .memh files for this to work!
    $readmemh("test_in_512.memh", input_data);
    $readmemh("ideal_test_out_512.memh", expected_out);
    f = $fopen("test_out_512.memh", "w"); // write computed values.
    
    idx=0; reset=1; #40;
    reset=0;
   end    

   // increment testbench counter and derive load/start signals
   always @(posedge slow_clk)
     if (~reset) idx <= idx + 1;
     else idx <= idx;

   // CHANGE 3: Update Loop Limits for 512 points
   assign load =  idx < 512;
   assign start = idx === 512;

   // increment output address if done, reset if restarting FFT
   always @(posedge slow_clk)
     if (load) out_idx <= 0;
     else if (done) out_idx <= out_idx + 1;
   
   // load/start logic
   // CHANGE 4: Update array indexing to [8:0]
   assign rd = load ? input_data[idx[8:0]] : 0;  
   assign expected = expected_out[out_idx[8:0]];

   // Slice components
   assign expected_re = expected[31:16]; 
   assign expected_im = expected[15:0]; 
   assign wd_re = wd[31:16]; 
   assign wd_im = wd[15:0]; 

   // if FFT is done, compare gt to computed output, and write computed output to file.
   always @(posedge slow_clk)
     if (done) begin
        // CHANGE 5: Update verification loop limit to 511
        if (out_idx <= 511) begin
           $fwrite(f, "%h\n", wd);
           if (wd !== expected) begin
              $display("Error @ out_idx %d: expected %b (got %b)    expected: %d+j%d, got %d+j%d", 
                       out_idx, expected, wd, expected_re, expected_im, wd_re, wd_im);
           end
        end else begin
           $display("FFT test complete.");
           $fclose(f);
           $stop;
        end
     end
endmodule // fft_testbench