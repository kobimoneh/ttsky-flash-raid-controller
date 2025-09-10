module instruction_decoder (
    // System clock and reset
    input  wire clk,            // 50 MHz system clock
    input  wire rst,            // Active high reset
    
    // Host SPI interface (monitoring)
    input  wire h_cs_n,         // Chip select (active low)
    input  wire h_clk,          // SPI clock
    input  wire h_mosi,         // MOSI from host
    
    // Address range configuration (from serial_interface)
    input  wire [23:0] addr0_start,
    input  wire [23:0] addr0_end,
    input  wire        range0_enable,
    input  wire        range0_flash_select,
    
    input  wire [23:0] addr1_start,
    input  wire [23:0] addr1_end,
    input  wire        range1_enable,
    input  wire        range1_flash_select,
    
    input  wire        default_flash_select,
    
    // Flash select output
    output reg  flash_select,   // 0: Main Flash, 1: Secondary Flash
    
    // Debug outputs
    output reg [7:0]  debug_instruction,
    output reg [23:0] debug_address,
    output reg [2:0]  debug_state
);

    // States
    localparam [2:0] 
        IDLE_STATE  = 3'd0,
        CMD_STATE   = 3'd1,
        ADDR_STATE  = 3'd2,
        DUMMY_STATE = 3'd3,
        DATA_STATE  = 3'd4;
    
    // Read commands (simplified - only basic SPI)
    localparam CMD_READ_STD   = 8'h03;
    localparam CMD_FAST_READ  = 8'h0B;
    
    // State machine registers
    reg [2:0]  state, next_state;
    reg [4:0]  bit_counter;        // Use 5 bits like original
    reg [7:0]  shift_reg;
    reg [7:0]  addr_byte_count;    // Use 8 bits like original
    reg        is_read_cmd;
    
    // CDC - Fixed edge detection
    reg h_clk_r1, h_clk_r2;
    reg h_cs_n_r1, h_cs_n_r2;
    reg h_mosi_r1, h_mosi_r2;
    
    always @(posedge clk) begin
        if (rst) begin
            h_clk_r1 <= 1'b0;
            h_clk_r2 <= 1'b0;
            h_cs_n_r1 <= 1'b1;
            h_cs_n_r2 <= 1'b1;
            h_mosi_r1 <= 1'b0;
            h_mosi_r2 <= 1'b0;
        end else begin
            h_clk_r1 <= h_clk;
            h_clk_r2 <= h_clk_r1;
            h_cs_n_r1 <= h_cs_n;
            h_cs_n_r2 <= h_cs_n_r1;
            h_mosi_r1 <= h_mosi;
            h_mosi_r2 <= h_mosi_r1;
        end
    end
    
    // Fixed edge detection - detect between r1 and r2, not r2 and r3!
    wire sclk_rising_edge = h_clk_r1 & ~h_clk_r2;
    wire cs_falling_edge = ~h_cs_n_r1 & h_cs_n_r2;
    wire cs_rising_edge = h_cs_n_r1 & ~h_cs_n_r2;
    
    // State machine
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE_STATE;
            debug_state <= IDLE_STATE;
        end else begin
            state <= next_state;
            debug_state <= next_state;
        end
    end
    
    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE_STATE: begin
                if (cs_falling_edge)
                    next_state = CMD_STATE;
            end
            
            CMD_STATE: begin
                if (cs_rising_edge)
                    next_state = IDLE_STATE;
                else if (sclk_rising_edge && bit_counter == 5'd7)
                    next_state = ADDR_STATE;
            end
            
            ADDR_STATE: begin
                if (cs_rising_edge)
                    next_state = IDLE_STATE;
                else if (sclk_rising_edge && bit_counter == 5'd7 && addr_byte_count == 8'd2) begin
                    if (debug_instruction == CMD_FAST_READ)
                        next_state = DUMMY_STATE;
                    else
                        next_state = DATA_STATE;
                end
            end
            
            DUMMY_STATE: begin
                if (cs_rising_edge)
                    next_state = IDLE_STATE;
                else if (sclk_rising_edge && bit_counter == 5'd7)
                    next_state = DATA_STATE;
            end
            
            DATA_STATE: begin
                if (cs_rising_edge)
                    next_state = IDLE_STATE;
            end
            
            default: next_state = IDLE_STATE;
        endcase
    end
    
    // Main decoder logic
    always @(posedge clk) begin
        if (rst) begin
            bit_counter <= 5'd0;
            shift_reg <= 8'd0;
            addr_byte_count <= 8'd0;
            debug_instruction <= 8'd0;
            debug_address <= 24'd0;
            is_read_cmd <= 1'b0;
            flash_select <= 1'b0;  // Default to main flash
        end else begin
            // Reset on CS rising edge
            if (cs_rising_edge) begin
                bit_counter <= 5'd0;
                shift_reg <= 8'd0;
                addr_byte_count <= 8'd0;
                is_read_cmd <= 1'b0;
                // Keep flash_select stable until next transaction
            end else if (sclk_rising_edge && ~h_cs_n_r1) begin
                // Shift in data on rising edge when CS is active
                shift_reg <= {shift_reg[6:0], h_mosi_r1};
                bit_counter <= bit_counter + 1;
                
                // Process complete bytes
                if (bit_counter == 5'd7) begin
                    case (state)
                        CMD_STATE: begin
                            debug_instruction <= {shift_reg[6:0], h_mosi_r1};
                            // Check if read command
                            case ({shift_reg[6:0], h_mosi_r1})
                                CMD_READ_STD, CMD_FAST_READ: is_read_cmd <= 1'b1;
                                default: is_read_cmd <= 1'b0;
                            endcase
                            // Set default flash select for non-read commands
                            if ({shift_reg[6:0], h_mosi_r1} != CMD_READ_STD && 
                                {shift_reg[6:0], h_mosi_r1} != CMD_FAST_READ) begin
                                flash_select <= default_flash_select;
                            end
                        end
                        
                        ADDR_STATE: begin
                            case (addr_byte_count)
                                8'd0: debug_address[23:16] <= {shift_reg[6:0], h_mosi_r1};
                                8'd1: debug_address[15:8]  <= {shift_reg[6:0], h_mosi_r1};
                                8'd2: begin
                                    debug_address[7:0] <= {shift_reg[6:0], h_mosi_r1};
                                    
                                    // Address complete - do range check NOW for read commands
                                    if (is_read_cmd) begin
                                        reg [23:0] full_address;
                                        full_address = {debug_address[23:8], shift_reg[6:0], h_mosi_r1};
                                        
                                        // Range check with priority
                                        if (range0_enable && 
                                            full_address >= addr0_start && 
                                            full_address <= addr0_end) begin
                                            flash_select <= range0_flash_select;
                                        end else if (range1_enable && 
                                                     full_address >= addr1_start && 
                                                     full_address <= addr1_end) begin
                                            flash_select <= range1_flash_select;
                                        end else begin
                                            flash_select <= default_flash_select;
                                        end
                                    end
                                end
                                default: ;
                            endcase
                            addr_byte_count <= addr_byte_count + 1;
                        end
                        
                        default: ;
                    endcase
                    bit_counter <= 5'd0;
                end
            end
            
            // When idle, track default flash select for mode changes
            if (h_cs_n_r1) begin
                flash_select <= default_flash_select;
            end
        end
    end

endmodule