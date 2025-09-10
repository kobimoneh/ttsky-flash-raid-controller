// SPDX-License-Identifier: MIT
//
// Flash Mux (No MISO) Module - Routes host SPI signals to one or both flash chips
// Supports MAIN, SECONDARY, and SHARE modes
// ENHANCED: Added transaction-safe mode switching to prevent corruption
//
`timescale 1ns/1ps

module flash_mux_no_miso (
    // System clock and reset for safe switching logic
    input  wire clk,            // System clock for synchronization
    input  wire rst,            // Active high reset
    
    // Host SPI Interface (input)
    input  wire h_clk,
    input  wire h_cs_n,
    input  wire h_mosi,
    
    // Main Flash SPI Interface (output)
    output wire mf_clk,
    output wire mf_cs_n,
    output wire mf_mosi,
    
    // Secondary Flash SPI Interface (output)
    output wire sf_clk,
    output wire sf_cs_n,
    output wire sf_mosi,
    
    // Control signals (mode selection)
    input  wire sel0,           // Enable Main Flash
    input  wire sel1,           // Enable Secondary Flash
    
    // Debug/Status outputs
    output wire mode_switch_pending,  // Indicates mode change is waiting
    output wire [1:0] active_mode     // Current active mode
);

    // ============================================================================
    // Parameters and Mode Definitions
    // ============================================================================
    
    // Mode encoding (matches raider.v mode generation)
    // sel0=1, sel1=0: MAIN mode (only main flash active)
    // sel0=0, sel1=1: SECONDARY mode (only secondary flash active)
    // sel0=1, sel1=1: SHARE mode (both flashes active)
    // sel0=0, sel1=0: DISABLED (no flash active - unusual but possible)
    
    localparam MODE_DISABLED  = 2'b00;  // Neither flash active
    localparam MODE_MAIN      = 2'b10;  // sel0=1, sel1=0
    localparam MODE_SECONDARY = 2'b01;  // sel0=0, sel1=1
    localparam MODE_SHARE     = 2'b11;  // sel0=1, sel1=1
    
    // ============================================================================
    // Transaction Safety Logic
    // ============================================================================
    // Only allow mode changes when CS# is inactive to prevent corruption
    // of ongoing SPI transactions
    
    // Safe switching condition: no active transaction
    wire safe_to_switch = h_cs_n;
    
    // Registered select signals for glitch-free operation
    reg sel0_safe, sel1_safe;
    reg mode_change_pending;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sel0_safe <= 1'b1;          // Default to MAIN mode
            sel1_safe <= 1'b0;          // (sel0=1, sel1=0)
            mode_change_pending <= 1'b0;
        end else begin
            if (safe_to_switch) begin
                // Safe to switch - update mode
                sel0_safe <= sel0;
                sel1_safe <= sel1;
                mode_change_pending <= 1'b0;
            end else if ((sel0 != sel0_safe) || (sel1 != sel1_safe)) begin
                // Mode change requested but not safe - set pending flag
                mode_change_pending <= 1'b1;
            end
        end
    end
    
    // Status outputs
    assign mode_switch_pending = mode_change_pending;
    assign active_mode = {sel1_safe, sel0_safe};
    
    // ============================================================================
    // Signal Routing (using safe selection)
    // ============================================================================
    
    // Main Flash outputs
    // When sel0_safe=1, pass through the host signals; when sel0_safe=0, drive inactive
    assign mf_clk  = sel0_safe ? h_clk  : 1'b0;    // Clock idle low
    assign mf_cs_n = sel0_safe ? h_cs_n : 1'b1;    // CS inactive high
    assign mf_mosi = sel0_safe ? h_mosi : 1'b0;    // MOSI idle low
    
    // Secondary Flash outputs
    // When sel1_safe=1, pass through the host signals; when sel1_safe=0, drive inactive
    assign sf_clk  = sel1_safe ? h_clk  : 1'b0;    // Clock idle low
    assign sf_cs_n = sel1_safe ? h_cs_n : 1'b1;    // CS inactive high
    assign sf_mosi = sel1_safe ? h_mosi : 1'b0;    // MOSI idle low
    
    // ============================================================================
    // Assertions for Verification (simulation only)
    // ============================================================================
    
    // synthesis translate_off
    `ifdef SIMULATION
    
    // Check that mode switching doesn't occur during active transaction
    reg [1:0] mode_prev;
    always @(posedge clk) begin
        mode_prev <= {sel1_safe, sel0_safe};
        
        if (!rst && ({sel1_safe, sel0_safe} != mode_prev)) begin
            if (!h_cs_n) begin
                $error("Flash mode changed during active transaction!");
            end
        end
    end
    
    // Warn about unusual mode combinations
    always @(posedge clk) begin
        if (!rst) begin
            case ({sel1_safe, sel0_safe})
                MODE_DISABLED: begin
                    if (!h_cs_n) begin
                        $display("WARNING: Both flashes disabled during active transaction");
                    end
                end
                MODE_MAIN: ; // Normal
                MODE_SECONDARY: ; // Normal
                MODE_SHARE: ; // Normal
            endcase
        end
    end
    
    // Verify no glitches on flash clocks during mode transitions
    reg mf_clk_prev, sf_clk_prev;
    always @(posedge clk) begin
        if (!rst) begin
            mf_clk_prev <= mf_clk;
            sf_clk_prev <= sf_clk;
            
            // Check for runt pulses (clock changes without h_clk changing)
            if ((mf_clk != mf_clk_prev) && (h_clk == mf_clk_prev) && sel0_safe) begin
                $display("WARNING: Potential glitch on mf_clk");
            end
            if ((sf_clk != sf_clk_prev) && (h_clk == sf_clk_prev) && sel1_safe) begin
                $display("WARNING: Potential glitch on sf_clk");
            end
        end
    end
    
    `endif
    // synthesis translate_on

endmodule