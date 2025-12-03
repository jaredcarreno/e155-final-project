module fft (
    input  logic sck, 
    input  logic sdi, 
    input  logic reset, 
    input  logic full_reset,
    input  logic clk,     // <-- ADD FOR TESTBENCHING
    output logic sdo, 
    output logic done
);

    logic [1:0] clk_counter = 0;
    logic ram_clk, slow_clk;
    // logic clk;

    // HSOSC #(.CLKHF_DIV ("0b10")) hf_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk)); // 12 MHz

    always_ff @(posedge clk) clk_counter <= clk_counter + 1'b1;
    assign ram_clk = clk_counter[0];
    assign slow_clk = clk_counter[1];

    // Signals
    logic [31:0] spi_to_fft_data, fft_to_spi_data;
    logic [8:0]  spi_read_addr, spi_write_addr;
    logic        spi_write_en, spi_buffer_full;
    logic        fft_load, fft_start, fft_processing, fft_done;
    logic [8:0]  fft_load_addr;
    logic [31:0] fft_data_out;
    logic [8:0]  fft_out_addr_probe; // NEW: Robust Address Signal

    typedef enum logic [1:0] {IDLE, LOAD, PROCESS, DONE} state_t;
    state_t state;
    logic [8:0] load_ptr;

    // RAM-Based SPI Buffer
    spi_fft_buffer spi_inst (
        .sck(sck), .sdi(sdi), .reset(reset), .sdo(sdo), .clk(clk),
        .data_to_fft(spi_to_fft_data), .data_from_fft(fft_to_spi_data),
        .fft_read_addr(spi_read_addr), .fft_write_addr(spi_write_addr),
        .fft_write_en(spi_write_en), .start_fft(spi_buffer_full)
    );

    // FFT Controller (Connected to Probe)
    fft_controller fft_unit (
        .clk(clk), .ram_clk(ram_clk), .slow_clk(slow_clk), .reset(reset),
        .start(fft_start), .load(fft_load), .load_address(fft_load_addr),
        .data_in(spi_to_fft_data), .done(fft_done), .processing(fft_processing),
        .data_out(fft_data_out),
        .out_addr_probe(fft_out_addr_probe) 
    );

    // State Machine
    always_ff @(posedge slow_clk) begin
        if (~reset) begin
            state <= IDLE;
            load_ptr <= 0;
        end else begin
            case (state)
                IDLE: if (spi_buffer_full) state <= LOAD;
                LOAD: begin
                    if (load_ptr == 511) begin
                        state <= PROCESS;
                        load_ptr <= 0;
                    end else load_ptr <= load_ptr + 1;
                end
                PROCESS: if (fft_done) state <= DONE;
                DONE: state <= DONE;
            endcase
        end
    end

    // Signal Routing
    always_comb begin
        fft_load      = (state == LOAD);
        fft_start     = (state == PROCESS); 
        spi_read_addr = load_ptr;
        fft_load_addr = load_ptr;
        fft_to_spi_data = fft_data_out;
    end
    
    // --- ROBUST OUTPUT LOGIC ---
    // Delay address and enable by 1 cycle to match RAM read latency
    logic [8:0] addr_delayed;
    logic       en_delayed;

    always_ff @(posedge slow_clk) begin
        if (~reset) begin
            addr_delayed <= 0;
            en_delayed <= 0;
        end else begin
            addr_delayed <= fft_out_addr_probe;
            en_delayed <= fft_done;
        end
    end

    assign spi_write_addr = addr_delayed;
    assign spi_write_en   = en_delayed;
    assign done = (state == DONE);

endmodule