// SPDX-License-Identifier: MIT
//
// Simple Flash MISO Multiplexer
// Selects between main and secondary flash MISO signals
//
`timescale 1ns/1ps

module flash_mux_miso (
    // Flash MISO inputs
    input  wire mf_miso,         // Main Flash MISO
    input  wire sf_miso,         // Secondary Flash MISO
    
    // Control signal
    input  wire flash_select,    // 0: Main Flash, 1: Secondary Flash
    
    // Host MISO output
    output wire h_miso           // MISO to host
);

    // Simple combinational mux
    // The instruction decoder already handles all the logic for:
    // - Read command detection
    // - Address range comparison
    // - Determining which flash to select
    // So we just need a simple mux here
    assign h_miso = flash_select ? sf_miso : mf_miso;

endmodule