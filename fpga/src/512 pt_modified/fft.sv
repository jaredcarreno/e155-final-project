module fft (
    input  logic sck, 
    input  logic sdi, 
    input  logic reset, 
    input  logic full_reset,
    input  logic clk,     // 12MHz System Clock
    output logic sdo, 
    output logic done
);
    logic [1:0] clk_counter = 0;
    logic ram_clk, slow_clk;

    // Clock Dividers
    always_ff @(posedge clk) clk_counter <= clk_counter + 1'b1;
    assign ram_clk = clk_counter[0];   // 6 MHz
    assign slow_clk = clk_counter[1];  // 3 MHz

    // Signals
    logic [31:0] spi_to_fft_data, fft_to_spi_data;
    logic [8:0]  spi_read_addr, spi_write_addr;
    logic        spi_write_en, spi_buffer_full;
    logic        fft_load, fft_start, fft_processing, fft_done;
    logic [8:0]  fft_load_addr;
    logic [31:0] fft_data_out;
    logic [8:0]  fft_out_addr_probe; 

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

    // FFT Controller
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
    
    // --- ROBUST OUTPUT LOGIC (Fixing Bus Contention) ---
    // Delay address and enable by 1 cycle to match RAM read latency
    // AND automatically release the bus after writing 512 words.
    logic [8:0] addr_delayed;
    logic       en_delayed;
    logic [9:0] output_write_count; // Counter to stop writing

    always_ff @(posedge slow_clk) begin
        if (~reset) begin
            addr_delayed <= 0;
            en_delayed <= 0;
            output_write_count <= 0;
        end else begin
            addr_delayed <= fft_out_addr_probe;
            
            // LOGIC CHANGE: Only write if we haven't finished the full readout
            if (fft_done && output_write_count < 512) begin
                en_delayed <= 1;
                output_write_count <= output_write_count + 1;
            end else begin
                en_delayed <= 0; // RELEASE THE BUS so SPI can read!
            end
        end
    end

    assign spi_write_addr = addr_delayed;
    assign spi_write_en   = en_delayed;
    assign done = (state == DONE);

endmodule