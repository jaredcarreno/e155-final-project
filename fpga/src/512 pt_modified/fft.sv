// Top-level module connecting SPI Buffer <-> FFT Controller
module fft (
    input  logic sck, 
    input  logic sdi, 
    input  logic reset, 
    input  logic full_reset,
    input  logic clk,      // System Clock (e.g. 48MHz from HFOSC)
    output logic sdo, 
    output logic done      // Debug/Status LED
);

    // =========================================================================
    // 1. Clock Generation
    // =========================================================================
    logic [1:0] clk_counter = 0;
    logic ram_clk;
    logic slow_clk;

    // HSOSC #(.CLKHF_DIV ("0b10")) hf_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk));
    always_ff @(posedge clk) begin
        clk_counter <= clk_counter + 1'b1;
    end
    
    assign ram_clk = clk_counter[0]; // Half speed
    assign slow_clk = clk_counter[1]; // Quarter speed

    // =========================================================================
    // 2. Wires & Interfaces
    // =========================================================================
    
    // Signals between SPI Buffer and FFT Controller
    logic [31:0] spi_to_fft_data;
    logic [31:0] fft_to_spi_data;
    
    logic [8:0]  spi_read_addr;  // Address we read FROM SPI buffer
    logic [8:0]  spi_write_addr; // Address we write TO SPI buffer (results)
    logic        spi_write_en;
    logic        spi_buffer_full; // Signal from SPI that 512 samples are ready

    // FFT Controller Signals
    logic        fft_load;
    logic        fft_start;
    logic        fft_processing;
    logic        fft_done;
    logic [8:0]  fft_load_addr;
    logic [31:0] fft_data_out;
    
    // State Machine for Data Movement
    typedef enum logic [1:0] {IDLE, LOAD, PROCESS, DONE} state_t;
    state_t state;
    
    logic [8:0] load_ptr;

    // =========================================================================
    // 3. Module Instantiations
    // =========================================================================

    // NEW: RAM-Based SPI Buffer
    spi_fft_buffer spi_inst (
        .sck(sck), 
        .sdi(sdi), 
        .reset(reset), 
        .sdo(sdo),
        .clk(clk),
        
        // Interface to this top-level module
        .data_to_fft(spi_to_fft_data),
        .data_from_fft(fft_to_spi_data),
        .fft_read_addr(spi_read_addr),   // We control this during LOAD state
        .fft_write_addr(spi_write_addr), // We control this during DONE state
        .fft_write_en(spi_write_en),
        .start_fft(spi_buffer_full)      // Triggers our state machine
    );

    // FFT Controller
    fft_controller fft_unit (
        .clk(clk), 
        .ram_clk(ram_clk), 
        .slow_clk(slow_clk), 
        .reset(reset), 
        .start(fft_start), 
        .load(fft_load), 
        .load_address(fft_load_addr),
        .data_in(spi_to_fft_data), // Feed data directly from SPI RAM
        .done(fft_done), 
        .processing(fft_processing), 
        .data_out(fft_data_out)
    );

    // =========================================================================
    // 4. Control Logic (The "Traffic Cop")
    // =========================================================================

    // State Transition
    always_ff @(posedge slow_clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            load_ptr <= 0;
        end else begin
            case (state)
                IDLE: begin
                    load_ptr <= 0;
                    if (spi_buffer_full) state <= LOAD;
                end

                LOAD: begin
                    // Copy 512 words from SPI Buffer -> FFT Internal RAMs
                    if (load_ptr == 511) begin
                        state <= PROCESS;
                        load_ptr <= 0;
                    end else begin
                        load_ptr <= load_ptr + 1;
                    end
                end

                PROCESS: begin
                    // Wait for FFT to finish
                    if (fft_done) state <= DONE;
                end

                DONE: begin
                    // Wait here until reset
                    state <= DONE; 
                end
            endcase
        end
    end

    // Output Signals & Muxing
    always_comb begin
        fft_load      = (state == LOAD);
        fft_start     = (state == PROCESS); 
        
        // Connections
        spi_read_addr = load_ptr;
        fft_load_addr = load_ptr;
        
        // Capture FFT Output Data
        fft_to_spi_data = fft_data_out;
    end
    
    // =========================================================================
    // 5. Output Capture Logic (FIXED LATENCY)
    // =========================================================================
    
    // We need to wait 1 cycle after 'done' goes high before enabling write,
    // because the RAM read inside the FFT controller takes 1 cycle.
    
    logic done_delayed;
    always_ff @(posedge slow_clk or posedge reset) begin
        if (reset) done_delayed <= 0;
        else done_delayed <= fft_done;
    end

    // Only enable writing when the DELAYED signal is high.
    // This skips the first cycle where data is invalid/old.
    assign spi_write_en = done_delayed; 

    // Generate Write Address (Shadow Counter)
    // We increment this only when we are ACTUALLY writing (done_delayed is high)
    logic [8:0] result_ptr;
    always_ff @(posedge slow_clk or posedge reset) begin
        if (reset) begin
            result_ptr <= 0;
        end else if (done_delayed) begin
            result_ptr <= result_ptr + 1;
        end
        // Optional: Reset pointer when done goes low (new frame)
        else if (!fft_done) begin
            result_ptr <= 0;
        end
    end
    
    assign spi_write_addr = result_ptr;

    assign done = (state == DONE);

endmodule