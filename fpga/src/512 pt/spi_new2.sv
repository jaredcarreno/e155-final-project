// Authors: Jared Carreno, Shreya Jampana, Emma Angel
// Purpose: Handles SPI communication with the MCU. Buffers and formats incoming 
// data (8-bit to 32-bit complex) and serializes FFT results back to the MCU.

module spi_fft_buffer (
    input  logic        sck,  // From MCU
    input  logic        sdi,  // From MCU
    input  logic        reset,
    output logic        sdo,  // To MCU
    
    // System Clock
    input  logic        clk, 

    // Interface to FFT Controller
    output logic [31:0] data_to_fft,    // 32-bit complex out to FFT
    input  logic [31:0] data_from_fft,  // 32-bit complex in from FFT
    input  logic [8:0]  fft_read_addr,  // Address FFT wants to read
    input  logic [8:0]  fft_write_addr, // Address FFT wants to write
    input  logic        fft_write_en,   // FFT Write enable
    output logic        start_fft       // Trigger signal
);


    logic [1:0] sck_sync;
    logic [1:0] sdi_sync;
    logic sck_rise, sck_fall;
    logic sdi_clean;

    always_ff @(posedge clk) begin
        if (~reset) begin
            sck_sync <= 2'b00;
            sdi_sync <= 2'b00;
        end else begin
            sck_sync <= {sck_sync[0], sck};
            sdi_sync <= {sdi_sync[0], sdi};
        end
    end

    assign sck_rise  = (sck_sync == 2'b01);
    assign sck_fall  = (sck_sync == 2'b10);
    assign sdi_clean = sdi_sync[1]; 

    logic [7:0] input_ram [0:511];
    logic [8:0] spi_in_addr;
    logic [2:0] spi_in_bit_cnt;
    logic [7:0] spi_in_shift;
    logic       spi_in_we;
    logic [2:0] start_pulse_cnt;

    // SPI Input State Machine
    always_ff @(posedge clk) begin
        if (~reset) begin
            spi_in_addr <= 0;
            spi_in_bit_cnt <= 0;
            spi_in_we <= 0;
            start_fft <= 0;
            start_pulse_cnt <= 0;
        end else begin
            // 1. Shift Logic
            if (sck_rise) begin
                spi_in_shift <= {spi_in_shift[6:0], sdi_clean};
                spi_in_bit_cnt <= spi_in_bit_cnt + 1;
                if (spi_in_bit_cnt == 3'b111) spi_in_we <= 1; 
            end else begin
                spi_in_we <= 0;
            end

            // 2. Address & Start Logic
            if (spi_in_we) begin 
                if (spi_in_addr == 511) begin
                    spi_in_addr <= 0;
                    start_pulse_cnt <= 3'b111; 
                end else begin
                    spi_in_addr <= spi_in_addr + 1;
                end
            end
            
            // 3. Pulse Stretching
            if (start_pulse_cnt > 0) begin
                start_fft <= 1;
                start_pulse_cnt <= start_pulse_cnt - 1;
            end else begin
                start_fft <= 0;
            end
        end
    end

    // RAM Access Arbitration (MUX)
    logic [8:0] ram_in_addr_mux;
    assign ram_in_addr_mux = (start_pulse_cnt > 0) ? 9'b0 : (spi_in_we ? spi_in_addr : fft_read_addr);
    
    // Infer Single Port RAM
    logic [7:0] ram_rdata_raw;
    always_ff @(posedge clk) begin
        if (spi_in_we) input_ram[ram_in_addr_mux] <= {spi_in_shift[6:0], sdi_clean};
        ram_rdata_raw <= input_ram[ram_in_addr_mux];
    end

    assign data_to_fft = { {8{ram_rdata_raw[7]}}, ram_rdata_raw, 16'b0 };


    logic [31:0] output_ram [0:511] = '{default:32'b0};
    
    logic [8:0]  spi_out_addr;
    logic [4:0]  spi_out_bit_cnt;
    logic [31:0] spi_out_shift;
    logic [31:0] ram_out_data;
    logic        load_new_word;
    logic        fetch_wait;

    logic [8:0] ram_out_addr_mux;
    assign ram_out_addr_mux = fft_write_en ? fft_write_addr : spi_out_addr;

    always_ff @(posedge clk) begin
        if (fft_write_en)
            output_ram[ram_out_addr_mux] <= data_from_fft;
        
        ram_out_data <= output_ram[ram_out_addr_mux];
    end

    logic fft_write_en_d;
    logic bus_released;
    always_ff @(posedge clk) fft_write_en_d <= fft_write_en;
    assign bus_released = (fft_write_en_d == 1 && fft_write_en == 0);

    // SPI Output Logic
    always_ff @(posedge clk) begin
        if (~reset) begin
            spi_out_addr <= 0;
            spi_out_bit_cnt <= 0;
            load_new_word <= 0;
            fetch_wait <= 1; // Start by fetching address 0
            spi_out_shift <= 32'b0; 
        end else begin 
            // 1. RE-SYNC: When FFT finishes, reset to address 0
            if (bus_released) begin
                spi_out_addr <= 0;
                spi_out_bit_cnt <= 0;
                load_new_word <= 0;
                fetch_wait <= 1; // Trigger the wait cycle
            end
            
            // 2. WAIT STATE: Give RAM 1 cycle to update 'ram_out_data'
            else if (fetch_wait) begin
                fetch_wait <= 0;
                load_new_word <= 1; // NOW we are ready to load
            end

            // 3. LOAD STATE: Capture the valid data
            else if (load_new_word) begin
                spi_out_shift <= ram_out_data;
                load_new_word <= 0;
            end 
            
            // 4. SHIFT STATE: Shift bits out on SCK falling edge
            else if (sck_fall) begin
                if (spi_out_bit_cnt == 31) begin
                    spi_out_addr <= spi_out_addr + 1;
                    spi_out_bit_cnt <= 0;
                    fetch_wait <= 1; // Trigger wait for NEXT word
                end else begin
                    spi_out_shift <= {spi_out_shift[30:0], 1'b0};
                    spi_out_bit_cnt <= spi_out_bit_cnt + 1;
                end
            end
        end
    end

    assign sdo = spi_out_shift[31];

endmodule