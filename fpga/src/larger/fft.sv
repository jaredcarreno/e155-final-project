// fft.sv - Top Level

module fft (input logic sck, sdi, reset, output logic sdo);

    // Clock Generation (Brian's style 3-clock logic)
    logic clk, ram_clk, slow_clk;
    logic [1:0] clk_counter;
    
    HSOSC #("0b00") hf_osc (1'b1, 1'b1, clk); // 48 MHz

    always_ff @(posedge clk) begin
        clk_counter <= clk_counter + 1;
    end
    assign ram_clk = clk_counter[0];  // 24 MHz
    assign slow_clk = clk_counter[1]; // 12 MHz


    // Interconnects
    logic dataReady, buf_ready, core_done, core_processing, core_load, core_start;
    logic [8:0]  core_rd_adr;
    logic [31:0] core_rd_data, core_wd_data;
    
    logic [4095:0]  spi_in_packet;
    logic [16383:0] spi_out_packet;

    // SPI
    fft_spi spi(sck, reset, sdi, sdo, spi_in_packet, dataReady, spi_out_packet);

    // Buffers
    fft_in_flop in_buf(slow_clk, reset, spi_in_packet, core_processing, 
                       dataReady, core_done, core_rd_data, core_load, core_start, core_rd_adr);
                       
    fft_out_flop out_buf(slow_clk, reset, core_wd_data, core_start, core_done, 
                         spi_out_packet, buf_ready);

    // FFT Controller
    fft_controller controller(
        .clk(clk), .ram_clk(ram_clk), .slow_clk(slow_clk), .reset(reset),
        .start(core_start), .load(core_load),
        .load_address(core_rd_adr), .data_in(core_rd_data),
        .done(core_done), .processing(core_processing), .data_out(core_wd_data)
    );

endmodule