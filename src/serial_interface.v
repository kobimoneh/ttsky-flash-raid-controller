// SPDX-License-Identifier: MIT
//
// Serial Interface Module - SPI slave for configuration management
// SYNTHESIS-FRIENDLY VERSION - Compatible with Tiny Tapeout JSON backend
// 
// SOLUTION: Uses mgmt_clk OR mgmt_cs_n as combined clock signal
// This preserves original SPI timing behavior while being synthesis-friendly
//
`timescale 1ns/1ps

module serial_interface (
    // System clock and reset
    input  wire clk,            // System clock for CDC synchronization
    input  wire rst,            // Active high reset
    
    // Management SPI interface (slave)
    input  wire mgmt_clk,       // SPI clock from management interface
    input  wire mgmt_cs_n,      // Chip select (active low)
    input  wire mgmt_mosi,      // Master Out Slave In
    output reg  mgmt_miso,      // Master In Slave Out
    
    // Configuration outputs (synchronized to system clock domain)
    output wire [23:0] addr0_start,
    output wire [23:0] addr0_end,
    output wire        range0_enable,
    output wire        range0_flash_select,
    
    output wire [23:0] addr1_start,
    output wire [23:0] addr1_end,
    output wire        range1_enable,
    output wire        range1_flash_select,
    
    output wire [7:0]  control_reg,
    output wire [7:0]  status_reg
);

    // ============================================================================
    // Parameters and Constants
    // ============================================================================
    
    // Register configuration
    localparam NUM_REGISTERS = 14;  // Total number of registers
    localparam ADDR_WIDTH = 8;      // Address bus width
    
    // Register map (addresses)
    localparam [7:0]
        ADDR0_START_H = 8'h00,
        ADDR0_START_M = 8'h01,
        ADDR0_START_L = 8'h02,
        ADDR0_END_H   = 8'h03,
        ADDR0_END_M   = 8'h04,
        ADDR0_END_L   = 8'h05,
        ADDR1_START_H = 8'h06,
        ADDR1_START_M = 8'h07,
        ADDR1_START_L = 8'h08,
        ADDR1_END_H   = 8'h09,
        ADDR1_END_M   = 8'h0A,
        ADDR1_END_L   = 8'h0B,
        CONTROL_REG   = 8'h0C,
        STATUS_REG    = 8'h0D;
    
    // Configuration registers
    reg [7:0] addr0_start_h, addr0_start_m, addr0_start_l;
    reg [7:0] addr0_end_h, addr0_end_m, addr0_end_l;
    reg [7:0] addr1_start_h, addr1_start_m, addr1_start_l;
    reg [7:0] addr1_end_h, addr1_end_m, addr1_end_l;
    reg [7:0] control_reg_int;
    reg [7:0] status_reg_int;
    
    // SPI state machine
    localparam [1:0]
        IDLE = 2'd0,
        CMD  = 2'd1,
        ADDR = 2'd2,
        DATA = 2'd3;
    
    reg [1:0] state;
    reg [2:0] bit_count;
    reg [7:0] mosi_shift_reg;
    reg [7:0] cmd_reg;
    reg [7:0] addr_reg;
    reg is_write_cmd;
    reg is_read_cmd;
    
    // MISO shift register
    reg [7:0] miso_shift_reg;
    
    // Synthesis-friendly clock combining: mgmt_clk OR mgmt_cs_n
    // This allows us to respond to both mgmt_clk edges and mgmt_cs_n rising edge
    wire mgmt_clk_or_mgmt_cs_n = mgmt_clk | mgmt_cs_n;
    
    // SPI logic - synthesis-friendly always block with combined clock
    // Uses mgmt_clk OR mgmt_cs_n to preserve original timing behavior
    always @(posedge mgmt_clk_or_mgmt_cs_n or posedge rst) begin
        if (rst) begin
            // Reset everything
            state <= IDLE;
            bit_count <= 3'd0;
            mosi_shift_reg <= 8'd0;
            cmd_reg <= 8'd0;
            addr_reg <= 8'd0;
            is_write_cmd <= 1'b0;
            is_read_cmd <= 1'b0;
            
            // Initialize configuration registers
            // RANGES default to 0xFFFFFF to 0xFFFFFF
            addr0_start_h <= 8'hFF;
            addr0_start_m <= 8'hFF;
            addr0_start_l <= 8'hFF;
            addr0_end_h <= 8'hFF;
            addr0_end_m <= 8'hFF;
            addr0_end_l <= 8'hFF;
            addr1_start_h <= 8'hFF;
            addr1_start_m <= 8'hFF;
            addr1_start_l <= 8'hFF;
            addr1_end_h <= 8'hFF;
            addr1_end_m <= 8'hFF;
            addr1_end_l <= 8'hFF;
            control_reg_int <= 8'h00;
            status_reg_int <= 8'h00;
            
        end else if (mgmt_cs_n) begin
            // CS released - triggered by mgmt_cs_n rising edge
            // Reset state machine but keep configuration registers
            state <= IDLE;
            bit_count <= 3'd0;
            mosi_shift_reg <= 8'd0;
            cmd_reg <= 8'd0;
            addr_reg <= 8'd0;
            is_write_cmd <= 1'b0;
            is_read_cmd <= 1'b0;
            status_reg_int[0] <= 1'b0; // Clear SPI active
            status_reg_int[1] <= 1'b0; // Clear read command flag
            status_reg_int[2] <= 1'b0; // Clear write command flag
        end else begin
            // mgmt_clk rising edge while CS active - normal SPI processing
            // (mgmt_cs_n is low, so this was triggered by mgmt_clk edge)
            
            // CS active - SPI transaction in progress
            status_reg_int[0] <= 1'b1; // Set SPI active
            
            // Shift in data
            mosi_shift_reg <= {mosi_shift_reg[6:0], mgmt_mosi};
            bit_count <= bit_count + 1;
            
            // Process byte completion
            if (bit_count == 3'd7) begin
                bit_count <= 3'd0;
                
                case (state)
                    IDLE: begin
                        // First byte is command
                        cmd_reg <= {mosi_shift_reg[6:0], mgmt_mosi};
                        is_write_cmd <= ({mosi_shift_reg[6:0], mgmt_mosi} == 8'h02);
                        is_read_cmd <= ({mosi_shift_reg[6:0], mgmt_mosi} == 8'h03);
                        status_reg_int[1] <= ({mosi_shift_reg[6:0], mgmt_mosi} == 8'h03); // Read cmd
                        status_reg_int[2] <= ({mosi_shift_reg[6:0], mgmt_mosi} == 8'h02); // Write cmd
                        state <= CMD;
                    end
                    
                    CMD: begin
                        // Second byte is address
                        addr_reg <= {mosi_shift_reg[6:0], mgmt_mosi};
                        
                        // For read: prepare data and go to DATA state
                        // For write: go to ADDR state to receive data byte
                        if (is_read_cmd) begin
                            // Load MISO shift register based on address
                            case ({mosi_shift_reg[6:0], mgmt_mosi})
                                ADDR0_START_H: miso_shift_reg <= addr0_start_h;
                                ADDR0_START_M: miso_shift_reg <= addr0_start_m;
                                ADDR0_START_L: miso_shift_reg <= addr0_start_l;
                                ADDR0_END_H:   miso_shift_reg <= addr0_end_h;
                                ADDR0_END_M:   miso_shift_reg <= addr0_end_m;
                                ADDR0_END_L:   miso_shift_reg <= addr0_end_l;
                                ADDR1_START_H: miso_shift_reg <= addr1_start_h;
                                ADDR1_START_M: miso_shift_reg <= addr1_start_m;
                                ADDR1_START_L: miso_shift_reg <= addr1_start_l;
                                ADDR1_END_H:   miso_shift_reg <= addr1_end_h;
                                ADDR1_END_M:   miso_shift_reg <= addr1_end_m;
                                ADDR1_END_L:   miso_shift_reg <= addr1_end_l;
                                CONTROL_REG:   miso_shift_reg <= control_reg_int;
                                STATUS_REG:    miso_shift_reg <= status_reg_int;
                                default:       miso_shift_reg <= 8'hFF;
                            endcase
                            state <= DATA;  // Skip ADDR state for reads
                        end else begin
                            state <= ADDR;  // Go to ADDR for writes
                        end
                    end
                    
                    ADDR: begin
                        // Third byte is data (only for writes)
                        if (is_write_cmd) begin
                            // Write data to register
                            case (addr_reg)
                                ADDR0_START_H: addr0_start_h <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR0_START_M: addr0_start_m <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR0_START_L: addr0_start_l <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR0_END_H:   addr0_end_h <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR0_END_M:   addr0_end_m <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR0_END_L:   addr0_end_l <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_START_H: addr1_start_h <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_START_M: addr1_start_m <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_START_L: addr1_start_l <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_END_H:   addr1_end_h <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_END_M:   addr1_end_m <= {mosi_shift_reg[6:0], mgmt_mosi};
                                ADDR1_END_L:   addr1_end_l <= {mosi_shift_reg[6:0], mgmt_mosi};
                                CONTROL_REG:   control_reg_int <= {mosi_shift_reg[6:0], mgmt_mosi};
                                default: ; // Ignore writes to read-only registers
                            endcase
                        end
                        state <= DATA;
                    end
                    
                    DATA: begin
                        // Stay in DATA state for additional bytes if needed
                    end
                endcase
            end else if (is_read_cmd && state == DATA) begin
                // Shift MISO data during DATA state (except first bit)
                // The first bit is already in position from CMD state
                miso_shift_reg <= {miso_shift_reg[6:0], 1'b0};
            end
        end
    end
    
    // MISO output - update on falling edge for proper SPI timing
    always @(negedge mgmt_clk or posedge rst) begin
        if (rst) begin
            mgmt_miso <= 1'b0;
        end else if (mgmt_cs_n) begin
            mgmt_miso <= 1'b0;
        end else if (is_read_cmd && state == DATA) begin
            // Output MSB during DATA state
            mgmt_miso <= miso_shift_reg[7];
        end else begin
            mgmt_miso <= 1'b0;
        end
    end
    
    // ============================================================================
    // Clock Domain Crossing (CDC) Synchronization
    // ============================================================================
    // Registers are written in mgmt_clk domain but read in system clk domain
    // Use 2-stage synchronizers for safe crossing
    
    // Control register synchronizer
    reg [7:0] control_reg_sync1, control_reg_sync2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            control_reg_sync1 <= 8'h00;
            control_reg_sync2 <= 8'h00;
        end else begin
            control_reg_sync1 <= control_reg_int;
            control_reg_sync2 <= control_reg_sync1;
        end
    end
    
    // Status register synchronizer
    reg [7:0] status_reg_sync1, status_reg_sync2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            status_reg_sync1 <= 8'h00;
            status_reg_sync2 <= 8'h00;
        end else begin
            status_reg_sync1 <= status_reg_int;
            status_reg_sync2 <= status_reg_sync1;
        end
    end
    
    // Address register synchronizers
    reg [23:0] addr0_start_sync1, addr0_start_sync2;
    reg [23:0] addr0_end_sync1, addr0_end_sync2;
    reg [23:0] addr1_start_sync1, addr1_start_sync2;
    reg [23:0] addr1_end_sync1, addr1_end_sync2;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            addr0_start_sync1 <= 24'hFFFFFF;
            addr0_start_sync2 <= 24'hFFFFFF;
            addr0_end_sync1 <= 24'hFFFFFF;
            addr0_end_sync2 <= 24'hFFFFFF;
            addr1_start_sync1 <= 24'hFFFFFF;
            addr1_start_sync2 <= 24'hFFFFFF;
            addr1_end_sync1 <= 24'hFFFFFF;
            addr1_end_sync2 <= 24'hFFFFFF;
        end else begin
            // First stage
            addr0_start_sync1 <= {addr0_start_h, addr0_start_m, addr0_start_l};
            addr0_end_sync1 <= {addr0_end_h, addr0_end_m, addr0_end_l};
            addr1_start_sync1 <= {addr1_start_h, addr1_start_m, addr1_start_l};
            addr1_end_sync1 <= {addr1_end_h, addr1_end_m, addr1_end_l};
            // Second stage
            addr0_start_sync2 <= addr0_start_sync1;
            addr0_end_sync2 <= addr0_end_sync1;
            addr1_start_sync2 <= addr1_start_sync1;
            addr1_end_sync2 <= addr1_end_sync1;
        end
    end
    
    // ============================================================================
    // Output Assignments (Using Synchronized Values)
    // ============================================================================
    
    // Address outputs (synchronized to system clock)
    assign addr0_start = addr0_start_sync2;
    assign addr0_end = addr0_end_sync2;
    assign addr1_start = addr1_start_sync2;
    assign addr1_end = addr1_end_sync2;
    
    // Control and status registers (synchronized to system clock)
    assign control_reg = control_reg_sync2;
    assign status_reg = status_reg_sync2;
    
    // Control register bit mapping per specification
    // control_reg[1:0] = Mode (00=Main, 01=Secondary, 10=Share)  
    // control_reg[2] = Range0_Enable
    // control_reg[3] = Range1_Enable
    // control_reg[4] = Range0_Flash_Select (0=main, 1=secondary)
    // control_reg[5] = Range1_Flash_Select (0=main, 1=secondary)
    // control_reg[6] = Host_Select (0=main host, 1=secondary host)
    // control_reg[7] = Reserved
    
    // Extract control bits (synchronized values)
    assign range0_enable = control_reg_sync2[2];
    assign range0_flash_select = control_reg_sync2[4];
    assign range1_enable = control_reg_sync2[3];
    assign range1_flash_select = control_reg_sync2[5];

endmodule
