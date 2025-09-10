// SPDX-License-Identifier: MIT
//
// Host Mux Module - Selects between Main and Secondary Host SPI interfaces
// Part of the Raider ASIC architecture for dual-host support
// ENHANCED: Added transaction-safe switching to prevent mid-transaction corruption
//
`timescale 1ns/1ps

module host_mux (
    // System clock and reset for safe switching logic
    input  wire clk,            // System clock for synchronization
    input  wire rst,            // Active high reset
    
    // Main Host SPI Interface (input)
    input  wire mh_clk,
    input  wire mh_cs_n,
    input  wire mh_mosi,
    output wire mh_miso,
    
    // Secondary Host SPI Interface (input)
    input  wire sh_clk,
    input  wire sh_cs_n,
    input  wire sh_mosi,
    output wire sh_miso,
    
    // Selected Host Interface (output)
    output wire h_clk,
    output wire h_cs_n,
    output wire h_mosi,
    input  wire h_miso,
    
    // Control signal
    input  wire host_select,    // 0: Main Host, 1: Secondary Host
    
    // Debug/Status outputs
    output wire switching_blocked,  // Indicates switch request is pending
    output wire active_transaction  // Indicates a SPI transaction is active
);

    // ============================================================================
    // Transaction Safety Logic
    // ============================================================================
    // Only allow host switching when both CS# signals are inactive
    // This prevents corruption of ongoing SPI transactions
    
    // Detect if any transaction is active
    assign active_transaction = ~mh_cs_n | ~sh_cs_n;
    
    // Safe switching condition: no active transactions
    wire safe_to_switch = mh_cs_n & sh_cs_n;
    
    // Registered host selection for glitch-free operation
    reg host_select_safe;
    reg host_select_pending;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            host_select_safe <= 1'b0;     // Default to main host after reset
            host_select_pending <= 1'b0;
        end else begin
            if (safe_to_switch) begin
                // Safe to switch - update selection
                host_select_safe <= host_select;
                host_select_pending <= 1'b0;
            end else if (host_select != host_select_safe) begin
                // Switch requested but not safe - set pending flag
                host_select_pending <= 1'b1;
            end
        end
    end
    
    // Status output: indicates when a switch is blocked
    assign switching_blocked = host_select_pending;
    
    // ============================================================================
    // Signal Multiplexing (using safe selection)
    // ============================================================================
    
    // Forward path: Select host signals based on safe selection
    // Note: For production ASIC, consider using glitch-free mux cells for clock
    assign h_clk  = host_select_safe ? sh_clk  : mh_clk;
    assign h_cs_n = host_select_safe ? sh_cs_n : mh_cs_n;
    assign h_mosi = host_select_safe ? sh_mosi : mh_mosi;
    
    // Return path: Route MISO back to the selected host
    // Non-selected host sees logic high (not floating)
    assign mh_miso = host_select_safe ? 1'b1 : h_miso;  // Drive high when not selected
    assign sh_miso = host_select_safe ? h_miso : 1'b1;  // Drive high when not selected
    
    // ============================================================================
    // Assertions for Verification (simulation only)
    // ============================================================================
    
    // synthesis translate_off
    `ifdef SIMULATION
    
    // Check that switching doesn't occur during active transaction
    reg host_select_prev;
    always @(posedge clk) begin
        host_select_prev <= host_select_safe;
        
        if (!rst && (host_select_safe != host_select_prev)) begin
            if (active_transaction) begin
                $error("Host selection changed during active transaction!");
            end
        end
    end
    
    // Verify that both hosts don't drive simultaneously (shouldn't happen with mux)
    always @(*) begin
        if (!rst && !mh_cs_n && !sh_cs_n) begin
            $display("WARNING: Both hosts attempting to access simultaneously");
        end
    end
    
    `endif
    // synthesis translate_on

endmodule