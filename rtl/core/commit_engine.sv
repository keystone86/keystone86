// Keystone86 / Aegis
// rtl/core/commit_engine.sv
// Rung 0: Minimal architectural commit boundary
//
// Ownership (Appendix B):
//   This module owns: architectural register file (EIP for Rung 0),
//   reset-visible state including the reset fetch address,
//   ENDI processing, fault-aware end-of-instruction handling,
//   prefetch queue flush initiation.
//   This module must NOT: own instruction policy, decide what to commit
//   beyond what ENDI/control inputs explicitly request.
//
// Reset fetch address:
//   This module is the SINGLE owner of the reset fetch address.
//   On the first cycle after reset_n deasserts, commit_engine drives
//   flush_req=1 and flush_addr=32'hFFFFFFF0 so that prefetch_queue
//   begins fetching from the correct reset vector. No other module
//   hardcodes the reset vector.
//
// Rung 0 scope:
//   - EIP (initialized to reset vector)
//   - Reset architectural state + initial queue flush
//   - ENDI processing with fault suppression
//   - Mode/CS.D exports (real mode, 16-bit)
//   Interface shaped for Rung 1+ growth without redesign.

`include "commit_defs.svh"
`include "fault_defs.svh"

module commit_engine (
    input  logic        clk,
    input  logic        reset_n,

    // --- ENDI interface (from microsequencer) ---
    input  logic        endi_req,
    input  logic [9:0]  endi_mask,
    output logic        endi_done,

    // --- Fault interface (from microsequencer) ---
    input  logic        raise_req,
    input  logic [3:0]  raise_fc,
    input  logic [31:0] raise_fe,

    // --- Pending GPR commit (shaped for Rung 1+, unused in Rung 0) ---
    input  logic        pc_gpr_en,
    input  logic [2:0]  pc_gpr_idx,
    input  logic [31:0] pc_gpr_val,

    // --- Pending EIP commit (shaped for Rung 1+, unused in Rung 0) ---
    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    // --- Architectural state outputs ---
    output logic [31:0] eip,
    output logic        mode_prot,          // always 0 in Rung 0
    output logic        cs_d_bit,           // always 0 in Rung 0

    // --- Prefetch queue flush (commit_engine is the sole flush authority) ---
    output logic        flush_req,
    output logic [31:0] flush_addr,

    // --- Fault state export ---
    output logic        fault_pending,
    output logic [3:0]  fault_class,
    output logic [31:0] fault_error
);

    // ----------------------------------------------------------------
    // 486 reset vector (single definition, owned by this module)
    // ----------------------------------------------------------------
    localparam logic [31:0] RESET_FETCH_ADDR = 32'hFFFFFFF0;

    // ----------------------------------------------------------------
    // Architectural registers (Rung 0 minimal set)
    // ----------------------------------------------------------------
    logic [31:0] eip_r;
    logic        fault_pending_r;
    logic [3:0]  fault_class_r;
    logic [31:0] fault_error_r;

    // Pending commit record
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;

    // Reset flush tracking
    logic        reset_flush_done;         // have we sent the initial flush?

    // ----------------------------------------------------------------
    // Outputs
    // ----------------------------------------------------------------
    assign eip           = eip_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    // ----------------------------------------------------------------
    // Sequential logic
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r            <= RESET_FETCH_ADDR;
            fault_pending_r  <= 1'b0;
            fault_class_r    <= 4'h0;
            fault_error_r    <= 32'h0;
            pc_eip_en_r      <= 1'b0;
            pc_eip_val_r     <= 32'h0;
            flush_req        <= 1'b0;
            flush_addr       <= RESET_FETCH_ADDR;
            endi_done        <= 1'b0;
            reset_flush_done <= 1'b0;
        end else begin
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;

            // --------------------------------------------------------
            // Initial reset flush: on first clock after reset, drive
            // flush_req so prefetch_queue begins at the reset vector.
            // This is the single authoritative reset-fetch-address event.
            // --------------------------------------------------------
            if (!reset_flush_done) begin
                flush_req        <= 1'b1;
                flush_addr       <= RESET_FETCH_ADDR;
                reset_flush_done <= 1'b1;
            end

            // --------------------------------------------------------
            // Stage RAISE (fault staging)
            // --------------------------------------------------------
            if (raise_req) begin
                fault_pending_r <= 1'b1;
                fault_class_r   <= raise_fc;
                fault_error_r   <= raise_fe;
            end

            // --------------------------------------------------------
            // Stage EIP (unused in Rung 0 bootstrap, interface ready)
            // --------------------------------------------------------
            if (pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end

            // --------------------------------------------------------
            // ENDI processing
            // --------------------------------------------------------
            if (endi_req) begin
                // EIP commit (bit 1 = CM_EIP) — suppressed if fault pending
                if (endi_mask[1] && pc_eip_en_r && !fault_pending_r) begin
                    eip_r <= pc_eip_val_r;
                end

                // Queue flush (bit 9 = CM_FLUSHQ or implied by EIP commit)
                if (endi_mask[9] ||
                    (endi_mask[1] && pc_eip_en_r && !fault_pending_r)) begin
                    flush_req  <= 1'b1;
                    flush_addr <= pc_eip_en_r ? pc_eip_val_r : eip_r;
                end

                // Clear fault state (bit 8 = CM_CLRF)
                if (endi_mask[8]) begin
                    fault_pending_r <= 1'b0;
                    fault_class_r   <= 4'h0;
                    fault_error_r   <= 32'h0;
                end

                // Clear staged pending commit
                pc_eip_en_r  <= 1'b0;
                pc_eip_val_r <= 32'h0;

                endi_done <= 1'b1;
            end
        end
    end

endmodule
