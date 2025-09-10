// SPDX-License-Identifier: MIT
//
// Raider Top-Level Module - MITM ASIC for dual SPI flash with programmable routing
// Integrates all sub-modules to create complete system
//
`timescale 1ns/1ps

module raider (
    // System signals
    input  wire clk,           // System clock (50 MHz)
    input  wire rst_n,         // Active-low reset
    
    // Main Host Interface
    input  wire mh_clk,
    input  wire mh_cs_n,
    input  wire mh_mosi,
    output wire mh_miso,
    
    // Secondary Host Interface  
    input  wire sh_clk,
    input  wire sh_cs_n,
    input  wire sh_mosi,
    output wire sh_miso,
    
    // Management SPI
    input  wire mgmt_clk,
    input  wire mgmt_cs_n,
    input  wire mgmt_mosi,
    output wire mgmt_miso,
    
    // Main Flash Interface
    output wire mf_clk,
    output wire mf_cs_n,
    output wire mf_mosi,
    input  wire mf_miso,
    
    // Secondary Flash Interface
    output wire sf_clk,
    output wire sf_cs_n,
    output wire sf_mosi,
    input  wire sf_miso
);

    // ============================================================================
    // Clock Domain Crossing Note
    // ============================================================================
    // This design has multiple asynchronous clock domains:
    // 1. System clock (clk) - 50 MHz
    // 2. Host SPI clocks (mh_clk, sh_clk) - variable frequency
    // 3. Management SPI clock (mgmt_clk) - variable frequency
    //
    // CDC handling:
    // - serial_interface: Handles mgmt_clk to clk domain crossing internally
    // - instruction_decoder: Samples h_clk/h_cs_n/h_mosi with synchronizers
    // - host_mux & flash_mux: Pure combinational, no CDC issues
    //
    // TODO: Verify all CDC paths have proper synchronization
    
    // ============================================================================
    // Parameters and Constants
    // ============================================================================
    
    // Flash mode definitions
    localparam MODE_MAIN      = 2'b00;  // Only Main Flash active
    localparam MODE_SECONDARY = 2'b01;  // Only Secondary Flash active
    localparam MODE_SHARE     = 2'b10;  // Both flashes receive commands
    localparam MODE_RESERVED  = 2'b11;  // Reserved for future use
    
    // ============================================================================
    // Internal Signals
    // ============================================================================
    
    // Internal reset (active high for internal modules)
    wire rst = ~rst_n;
    
    // Selected host signals (from host_mux output)
    wire h_clk, h_cs_n, h_mosi, h_miso;
    
    // Configuration registers from serial_interface
    wire [7:0] control_reg;
    wire [7:0] status_reg;
    
    // Flash mux control signals
    wire sel0, sel1;
    wire flash_select;
    wire default_flash_select;
    
    // Address range configuration signals from serial_interface
    wire [23:0] addr0_start, addr0_end;
    wire [23:0] addr1_start, addr1_end;
    wire range0_enable, range0_flash_select;
    wire range1_enable, range1_flash_select;
    
    // Debug signals from instruction decoder (currently unused)
    wire [7:0] debug_instruction;
    wire [23:0] debug_address;
    wire [2:0] debug_state;
    // TODO: Consider exposing debug signals as module outputs for verification
    
    // ============================================================================
    // Control Register Bit Extraction
    // ============================================================================
    // Control Register Bit Mapping (matches serial_interface.v documentation):
    // Bits [1:0]: Flash Mode (00=MAIN, 01=SECONDARY, 10=SHARE, 11=Reserved)
    // Bit  [2]:   Range 0 Enable
    // Bit  [3]:   Range 1 Enable  
    // Bit  [4]:   Range 0 Flash Select (0=Main Flash, 1=Secondary Flash)
    // Bit  [5]:   Range 1 Flash Select (0=Main Flash, 1=Secondary Flash)
    // Bit  [6]:   Host Select (0=Main Host, 1=Secondary Host)
    // Bit  [7]:   Reserved
    
    wire [1:0] flash_mode = control_reg[1:0];
    wire host_select = control_reg[6];  // Fixed: moved from bit 2 to bit 6
    // Note: range enables and flash selects are provided directly by serial_interface
    
    // ============================================================================
    // Mode Logic
    // ============================================================================
    
    // Default flash selection for non-read commands and unmatched addresses
    // In SECONDARY mode, default to secondary flash; otherwise use main flash
    assign default_flash_select = (flash_mode == MODE_SECONDARY) ? 1'b1 : 1'b0;
    
    // Generate SEL0/SEL1 control signals for flash_mux_no_miso
    // SEL0: Enable Main Flash in MAIN and SHARE modes
    // SEL1: Enable Secondary Flash in SECONDARY and SHARE modes
    assign sel0 = (flash_mode == MODE_MAIN) || (flash_mode == MODE_SHARE);
    assign sel1 = (flash_mode == MODE_SECONDARY) || (flash_mode == MODE_SHARE);
    
    // Host Mux - Select between main and secondary host
    // Enhanced with transaction-safe switching
    wire switching_blocked;    // Status signal (currently unused)
    wire active_transaction;   // Status signal (currently unused)
    
    host_mux u_host_mux (
        .clk(clk),              // System clock for safe switching
        .rst(rst),              // Active high reset
        .mh_clk(mh_clk),
        .mh_cs_n(mh_cs_n),
        .mh_mosi(mh_mosi),
        .mh_miso(mh_miso),
        .sh_clk(sh_clk),
        .sh_cs_n(sh_cs_n),
        .sh_mosi(sh_mosi),
        .sh_miso(sh_miso),
        .h_clk(h_clk),
        .h_cs_n(h_cs_n),
        .h_mosi(h_mosi),
        .h_miso(h_miso),
        .host_select(host_select),
        .switching_blocked(switching_blocked),
        .active_transaction(active_transaction)
    );
    
    // Flash Mux (No MISO) - Route host signals to flash chips
    // Enhanced with transaction-safe mode switching
    wire mode_switch_pending;  // Status signal (currently unused)
    wire [1:0] active_mode;     // Status signal (currently unused)
    
    flash_mux_no_miso u_flash_mux_no_miso (
        .clk(clk),              // System clock for safe switching
        .rst(rst),              // Active high reset
        .h_clk(h_clk),
        .h_cs_n(h_cs_n),
        .h_mosi(h_mosi),
        .mf_clk(mf_clk),
        .mf_cs_n(mf_cs_n),
        .mf_mosi(mf_mosi),
        .sf_clk(sf_clk),
        .sf_cs_n(sf_cs_n),
        .sf_mosi(sf_mosi),
        .sel0(sel0),
        .sel1(sel1),
        .mode_switch_pending(mode_switch_pending),
        .active_mode(active_mode)
    );
    
    // Instruction Decoder - Decode SPI commands and generate flash select
    instruction_decoder u_instruction_decoder (
        .clk(clk),
        .rst(rst),
        .h_cs_n(h_cs_n),
        .h_clk(h_clk),
        .h_mosi(h_mosi),
        .addr0_start(addr0_start),
        .addr0_end(addr0_end),
        .range0_enable(range0_enable),
        .range0_flash_select(range0_flash_select),
        .addr1_start(addr1_start),
        .addr1_end(addr1_end),
        .range1_enable(range1_enable),
        .range1_flash_select(range1_flash_select),
        .default_flash_select(default_flash_select),
        .flash_select(flash_select),
        .debug_instruction(debug_instruction),
        .debug_address(debug_address),
        .debug_state(debug_state)
    );
    
    // Flash MISO Mux - Simple combinational mux
    flash_mux_miso u_flash_mux_miso (
        .mf_miso(mf_miso),
        .sf_miso(sf_miso),
        .flash_select(flash_select),
        .h_miso(h_miso)
    );
    
    // Serial Interface - SPI slave for configuration
    serial_interface u_serial_interface (
        .clk(clk),
        .rst(rst),
        .mgmt_clk(mgmt_clk),
        .mgmt_cs_n(mgmt_cs_n),
        .mgmt_mosi(mgmt_mosi),
        .mgmt_miso(mgmt_miso),
        .addr0_start(addr0_start),
        .addr0_end(addr0_end),
        .range0_enable(range0_enable),
        .range0_flash_select(range0_flash_select),
        .addr1_start(addr1_start),
        .addr1_end(addr1_end),
        .range1_enable(range1_enable),
        .range1_flash_select(range1_flash_select),
        .control_reg(control_reg),
        .status_reg(status_reg)
    );

endmodule