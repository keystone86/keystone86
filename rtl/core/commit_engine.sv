// Keystone86 / Aegis
// rtl/core/commit_engine.sv
// Rung 2: JMP target EIP commit + prefetch flush
//
// Ownership (Appendix B):
//   This module owns: architectural register file (EIP for Rung 0/1/2),
//   reset-visible state including the reset fetch address,
//   ENDI processing, fault-aware end-of-instruction handling,
//   prefetch queue flush initiation.
//   This module must NOT: own instruction policy, decide what to commit
//   beyond what ENDI/control inputs explicitly request.
//
// Rung 2 additions:
//
//   Contract 4 — Commit-owned redirect visibility:
//     redirect becomes architecturally real ONLY here at ENDI time.
//     Microsequencer stages pc_target_en/pc_target_val (the JMP target).
//     When ENDI fires with CM_JMP mask (CM_EIP | CM_FLUSHQ | ...):
//       - eip_r <- pc_target_val_r  (architectural EIP update)
//       - flush_req <- 1, flush_addr <- pc_target_val_r  (queue retarget)
//     This is the single authoritative redirect event.
//     Nothing upstream makes redirect architecturally visible before this.
//
//   pc_target_en / pc_target_val:
//     New inputs from microsequencer carrying the JMP target EIP.
//     Staged into pc_target_en_r / pc_target_val_r.
//     On ENDI with CM_FLUSHQ (bit 9), these take priority over pc_eip_val_r
//     for the flush address and EIP commit.
//
// Existing Rung 0/1 behavior is fully preserved:
//   - Reset flush at 0xFFFFFFF0
//   - pc_eip_en / pc_eip_val for fall-through EIP (NOP, etc.)
//   - RAISE/fault staging
//   - endi_done pulse

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

    // --- Pending GPR commit ---
    input  logic        pc_gpr_en,
    input  logic [2:0]  pc_gpr_idx,
    input  logic [31:0] pc_gpr_val,

    // --- Pending fall-through EIP commit (NOP, sequential) ---
    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    // --- Pending target EIP commit (Rung 2: JMP target) ---
    input  logic        pc_target_en,
    input  logic [31:0] pc_target_val,

    // --- Architectural state outputs ---
    output logic [31:0] eip,
    output logic        mode_prot,
    output logic        cs_d_bit,

    // --- Prefetch queue flush (commit_engine is the sole flush authority) ---
    output logic        flush_req,
    output logic [31:0] flush_addr,

    // --- Fault state export ---
    output logic        fault_pending,
    output logic [3:0]  fault_class,
    output logic [31:0] fault_error
);

    localparam logic [31:0] RESET_FETCH_ADDR = 32'hFFFFFFF0;

    // Architectural registers
    logic [31:0] eip_r;
    logic        fault_pending_r;
    logic [3:0]  fault_class_r;
    logic [31:0] fault_error_r;

    // Pending commit records
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;   // Rung 2: JMP target
    logic [31:0] pc_target_val_r;

    logic        reset_flush_done;

    // Outputs
    assign eip           = eip_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r            <= RESET_FETCH_ADDR;
            fault_pending_r  <= 1'b0;
            fault_class_r    <= 4'h0;
            fault_error_r    <= 32'h0;
            pc_eip_en_r      <= 1'b0;
            pc_eip_val_r     <= 32'h0;
            pc_target_en_r   <= 1'b0;
            pc_target_val_r  <= 32'h0;
            flush_req        <= 1'b0;
            flush_addr       <= RESET_FETCH_ADDR;
            endi_done        <= 1'b0;
            reset_flush_done <= 1'b0;
        end else begin
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;

            // --------------------------------------------------------
            // Initial reset flush
            // --------------------------------------------------------
            if (!reset_flush_done) begin
                flush_req        <= 1'b1;
                flush_addr       <= RESET_FETCH_ADDR;
                reset_flush_done <= 1'b1;
            end

            // --------------------------------------------------------
            // Fault staging
            // --------------------------------------------------------
            if (raise_req) begin
                fault_pending_r <= 1'b1;
                fault_class_r   <= raise_fc;
                fault_error_r   <= raise_fe;
            end

            // --------------------------------------------------------
            // Stage fall-through EIP (NOP/sequential)
            // --------------------------------------------------------
            if (pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end

            // --------------------------------------------------------
            // Stage target EIP (Rung 2: JMP target)
            // --------------------------------------------------------
            if (pc_target_en) begin
                pc_target_en_r  <= 1'b1;
                pc_target_val_r <= pc_target_val;
            end

            // --------------------------------------------------------
            // ENDI processing
            // --------------------------------------------------------
            if (endi_req) begin
                // ---- EIP commit ----
                // CM_FLUSHQ (bit 9): this is a redirect (JMP/CALL/RET-class).
                //   Commit target EIP, not fall-through EIP.
                //   Contract 4: this is the single architectural redirect event.
                if (endi_mask[9] && pc_target_en_r && !fault_pending_r) begin
                    eip_r <= pc_target_val_r;
                    // Flush to JMP target
                    flush_req  <= 1'b1;
                    flush_addr <= pc_target_val_r;
                end
                // CM_EIP (bit 1) without CM_FLUSHQ: sequential EIP advance (NOP)
                else if (endi_mask[1] && pc_eip_en_r && !fault_pending_r) begin
                    eip_r <= pc_eip_val_r;
                    // CM_FLUSHQ not set here, so no flush for sequential advance
                end

                // ---- Explicit flush without redirect (CM_FLUSHQ alone) ----
                // If CM_FLUSHQ set but no target pending, flush to current eip_r
                // (shouldn't happen in Rung 2, but safe fallback)
                if (endi_mask[9] && !pc_target_en_r && !fault_pending_r) begin
                    flush_req  <= 1'b1;
                    flush_addr <= pc_eip_en_r ? pc_eip_val_r : eip_r;
                end

                // ---- Clear fault state (CM_CLRF bit 8) ----
                if (endi_mask[8]) begin
                    fault_pending_r <= 1'b0;
                    fault_class_r   <= 4'h0;
                    fault_error_r   <= 32'h0;
                end

                // Clear all staged pending commits
                pc_eip_en_r     <= 1'b0;
                pc_eip_val_r    <= 32'h0;
                pc_target_en_r  <= 1'b0;
                pc_target_val_r <= 32'h0;

                endi_done <= 1'b1;
            end
        end
    end

endmodule
