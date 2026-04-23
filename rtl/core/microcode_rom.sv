// Keystone86 / Aegis
// rtl/core/microcode_rom.sv
// Rung 0: Microcode ROM and dispatch table
//
// Ownership (Appendix B):
//   This module owns: microinstruction storage and read-by-uPC,
//   dispatch table lookup (entry_id -> base uPC).
//   This module must NOT: own control flow, interpret microinstructions,
//   know instruction semantics.
//
// Rung 0 scope:
//   - 4096-word microcode ROM loaded from ucode.hex
//   - 256-entry dispatch table loaded from dispatch.hex
//   - synchronous read with 1-cycle latency
//
// Both files are generated bootstrap artifacts from the repo seed.
// Format: ucode.hex  — one 32-bit word per line (hex, no 0x prefix)
//         dispatch.hex — one 12-bit uPC per line (hex, no 0x prefix)
//
// IMPORTANT:
//   These paths are resolved by the simulator at runtime from the repo root
//   (where vvp is launched by the Makefile), not from this source file's
//   directory. Therefore the defaults are repo-root-relative.

module microcode_rom #(
    parameter string UCODE_FILE    = "build/microcode/ucode.hex",
    parameter string DISPATCH_FILE = "build/microcode/dispatch.hex"
) (
    input  logic        clk,

    // --- Microinstruction fetch ---
    input  logic [11:0] upc,                // current micro-PC
    output logic [31:0] uinst,              // microinstruction word (registered)

    // --- Dispatch table lookup ---
    input  logic [7:0]  entry_id,           // ENTRY_* to dispatch
    output logic [11:0] dispatch_upc        // base uPC for that entry (registered)
);

    // ----------------------------------------------------------------
    // Microcode ROM: 4096 x 32-bit words
    // ----------------------------------------------------------------
    logic [31:0] ucode_mem [0:4095];

    initial begin
        $readmemh(UCODE_FILE, ucode_mem);
    end

    always_ff @(posedge clk) begin
        uinst <= ucode_mem[upc];
    end

    // ----------------------------------------------------------------
    // Dispatch table: 256 x 12-bit entries
    // ----------------------------------------------------------------
    logic [11:0] dispatch_mem [0:255];

    initial begin
        $readmemh(DISPATCH_FILE, dispatch_mem);
    end

    always_ff @(posedge clk) begin
        dispatch_upc <= dispatch_mem[entry_id];
    end

endmodule