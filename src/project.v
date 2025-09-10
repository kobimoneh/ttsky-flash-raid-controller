/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_flash_raid_controller (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ============================================================================
    // Pin Mapping Documentation
    // ============================================================================
    // Total pins used: 22 out of 24 available (2 spare for debug/future use)
    //
    // ui_in[7:0] - Dedicated inputs (8 pins):
    //   [0] mh_clk     - Main Host SPI Clock
    //   [1] mh_cs_n    - Main Host Chip Select (active low)
    //   [2] mh_mosi    - Main Host Master Out Slave In
    //   [3] sh_clk     - Secondary Host SPI Clock
    //   [4] sh_cs_n    - Secondary Host Chip Select (active low)
    //   [5] sh_mosi    - Secondary Host Master Out Slave In
    //   [6] mgmt_clk   - Management SPI Clock
    //   [7] mgmt_cs_n  - Management Chip Select (active low)
    //
    // uo_out[7:0] - Dedicated outputs (8 pins):
    //   [0] mh_miso    - Main Host Master In Slave Out
    //   [1] sh_miso    - Secondary Host Master In Slave Out
    //   [2] mgmt_miso  - Management Master In Slave Out
    //   [3] mf_clk     - Main Flash SPI Clock
    //   [4] mf_cs_n    - Main Flash Chip Select (active low)
    //   [5] mf_mosi    - Main Flash Master Out Slave In
    //   [6] sf_clk     - Secondary Flash SPI Clock
    //   [7] sf_cs_n    - Secondary Flash Chip Select (active low)
    //
    // uio[7:0] - Bidirectional pins (3 inputs, 1 output, 4 spare):
    //   [0] mgmt_mosi  - Management Master Out Slave In (input)
    //   [1] mf_miso    - Main Flash Master In Slave Out (input)
    //   [2] sf_miso    - Secondary Flash Master In Slave Out (input)
    //   [3] sf_mosi    - Secondary Flash Master Out Slave In (output)
    //   [4] spare      - Available for debug (configured as input)
    //   [5] spare      - Available for debug (configured as input)
    //   [6] spare      - Available for debug (configured as input)
    //   [7] spare      - Available for debug (configured as input)
    
    // ============================================================================
    // Bidirectional Pin Configuration
    // ============================================================================
    // Configure uio[3] as output for sf_mosi, all others as inputs
    assign uio_oe = 8'b00001000;
    
    // ============================================================================
    // Internal Signal Declarations
    // ============================================================================
    
    // Internal wires for Raider outputs
    wire mh_miso_internal;
    wire sh_miso_internal;
    wire mgmt_miso_internal;
    wire mf_clk_internal;
    wire mf_cs_n_internal;
    wire mf_mosi_internal;
    wire sf_clk_internal;
    wire sf_cs_n_internal;
    wire sf_mosi_internal;
    
    // ============================================================================
    // Raider Instance
    // ============================================================================
    raider u_raider (
        // System signals
        .clk        (clk),           // System clock (50 MHz max)
        .rst_n      (rst_n),         // Active-low reset
        
        // Main Host Interface (from dedicated inputs/outputs)
        .mh_clk     (ui_in[0]),      // Main Host SPI Clock
        .mh_cs_n    (ui_in[1]),      // Main Host Chip Select
        .mh_mosi    (ui_in[2]),      // Main Host MOSI
        .mh_miso    (mh_miso_internal),  // Main Host MISO (to internal wire)
        
        // Secondary Host Interface (from dedicated inputs/outputs)
        .sh_clk     (ui_in[3]),      // Secondary Host SPI Clock
        .sh_cs_n    (ui_in[4]),      // Secondary Host Chip Select
        .sh_mosi    (ui_in[5]),      // Secondary Host MOSI
        .sh_miso    (sh_miso_internal),  // Secondary Host MISO (to internal wire)
        
        // Management Interface (mixed dedicated and bidirectional)
        .mgmt_clk   (ui_in[6]),      // Management SPI Clock
        .mgmt_cs_n  (ui_in[7]),      // Management Chip Select
        .mgmt_mosi  (uio_in[0]),     // Management MOSI (from bidirectional)
        .mgmt_miso  (mgmt_miso_internal), // Management MISO (to internal wire)
        
        // Main Flash Interface (outputs and bidirectional input)
        .mf_clk     (mf_clk_internal),    // Main Flash SPI Clock (to internal wire)
        .mf_cs_n    (mf_cs_n_internal),   // Main Flash Chip Select (to internal wire)
        .mf_mosi    (mf_mosi_internal),   // Main Flash MOSI (to internal wire)
        .mf_miso    (uio_in[1]),          // Main Flash MISO (from bidirectional)
        
        // Secondary Flash Interface (outputs and bidirectional)
        .sf_clk     (sf_clk_internal),    // Secondary Flash SPI Clock (to internal wire)
        .sf_cs_n    (sf_cs_n_internal),   // Secondary Flash Chip Select (to internal wire)
        .sf_mosi    (sf_mosi_internal),   // Secondary Flash MOSI (to internal wire)
        .sf_miso    (uio_in[2])           // Secondary Flash MISO (from bidirectional)
    );
    
    // ============================================================================
    // Output Pin Assignments
    // ============================================================================
    // Drive uo_out with the internal signals
    assign uo_out[0] = mh_miso_internal;
    assign uo_out[1] = sh_miso_internal;
    assign uo_out[2] = mgmt_miso_internal;  // This is critical for MISO reads!
    assign uo_out[3] = mf_clk_internal;
    assign uo_out[4] = mf_cs_n_internal;
    assign uo_out[5] = mf_mosi_internal;
    assign uo_out[6] = sf_clk_internal;
    assign uo_out[7] = sf_cs_n_internal;
    
    // Drive bidirectional outputs
    // Only bit 3 (sf_mosi) is an output, all others should be 0
    assign uio_out[7:4] = 4'b0000;  // Spare pins (unused)
    assign uio_out[3] = sf_mosi_internal;  // Secondary Flash MOSI (output)
    assign uio_out[2:0] = 3'b000;   // Input pins (driven low)
    
    // ============================================================================
    // Unused Signal Declaration (to prevent warnings)
    // ============================================================================
    // Note: ena is documented as always 1 when powered, so we can safely ignore it
    // The spare uio pins are available for future debug use
    wire _unused = &{ena, uio_in[7:4], 1'b0};

endmodule

`default_nettype wire