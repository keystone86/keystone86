// Keystone86 / Aegis
// rtl/core/commit_engine.sv
//
// Rung 3 additions over Rung 2:
//   - CM_STACK (endi_mask[4]) path: applies staged ESP from stack_engine
//     and staged EIP (call target or popped return address) at ENDI.
//   - pc_stack_en/val input: receives new ESP staged by stack_engine after
//     PUSH32 or POP32 service completes.
//   - pc_ret_imm_en/val input: receives RET imm16 adjustment staged at dispatch;
//     added to pc_stack_val at ENDI for C2 forms.
//   - Stack memory access removed: stack_engine owns stk_wr/stk_rd bus.
//     commit_engine no longer issues stk_wr_en or stk_rd_req.
//
// Ownership (per Appendix B):
//   - Sole owner of architectural register visibility (EIP, ESP, etc.)
//   - Applies all staged values atomically at ENDI only — never before.
//   - Does not know what instruction means; applies the mask microcode provides.
//   - Does not access stack memory directly (stack_engine owns that).

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

    // --- Pending GPR commit (unused in active Rung 2 path) ---
    input  logic        pc_gpr_en,
    input  logic [2:0]  pc_gpr_idx,
    input  logic [31:0] pc_gpr_val,

    // --- Pending fall-through EIP commit ---
    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    // --- Pending target EIP commit (JMP/CALL-direct target) ---
    input  logic        pc_target_en,
    input  logic [31:0] pc_target_val,

    // --- Staged RET imm16 adjustment (from microsequencer, staged at dispatch) ---
    // Applied on top of pc_stack_val at ENDI for RET imm16 (C2).
    input  logic        pc_ret_imm_en,
    input  logic [15:0] pc_ret_imm_val,

    // --- Staged new ESP from stack_engine (Rung 3) ---
    // stack_engine stages the post-push or post-pop ESP value.
    // commit_engine applies it architecturally at ENDI with CM_STACK.
    input  logic        pc_stack_en,
    input  logic [31:0] pc_stack_val,

    // --- Indirect CALL target (external; no register file in phase-1) ---
    input  logic [31:0] indirect_call_target,
    input  logic        indirect_call_target_valid,

    // --- Architectural state outputs ---
    output logic [31:0] eip,
    output logic [31:0] esp,
    output logic        mode_prot,
    output logic        cs_d_bit,

    // --- Prefetch queue flush ---
    output logic        flush_req,
    output logic [31:0] flush_addr,

    // --- Fault state export ---
    output logic        fault_pending,
    output logic [3:0]  fault_class,
    output logic [31:0] fault_error
);

    localparam logic [31:0] RESET_FETCH_ADDR = 32'hFFFFFFF0;
    localparam logic [31:0] RESET_ESP        = 32'h000FFFF0;

    // Architectural registers
    logic [31:0] eip_r;
    logic [31:0] esp_r;
    logic        fault_pending_r;
    logic [3:0]  fault_class_r;
    logic [31:0] fault_error_r;

    // Pending commit staging registers.
    // Values staged here are applied atomically at ENDI, never before.
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;
    logic [31:0] pc_target_val_r;
    logic        pc_ret_imm_en_r;
    logic [15:0] pc_ret_imm_val_r;
    logic        pc_stack_en_r;
    logic [31:0] pc_stack_val_r;

    // ENDI rising-edge detection
    logic        endi_req_d;
    logic        reset_flush_done;

    // Effective live-or-staged values for ENDI launch.
    // Allows consuming a handoff that arrives on the same cycle as endi_req.
    logic        eff_pc_eip_en;
    logic [31:0] eff_pc_eip_val;
    logic        eff_pc_target_en;
    logic [31:0] eff_pc_target_val;
    logic        eff_pc_ret_imm_en;
    logic [15:0] eff_pc_ret_imm_val;
    logic        eff_pc_stack_en;
    logic [31:0] eff_pc_stack_val;

    assign eip           = eip_r;
    assign esp           = esp_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    assign eff_pc_eip_en     = pc_eip_en | pc_eip_en_r;
    assign eff_pc_eip_val    = pc_eip_en ? pc_eip_val : pc_eip_val_r;
    assign eff_pc_target_en  = pc_target_en | pc_target_en_r;
    assign eff_pc_target_val = pc_target_en ? pc_target_val : pc_target_val_r;
    assign eff_pc_ret_imm_en  = pc_ret_imm_en | pc_ret_imm_en_r;
    assign eff_pc_ret_imm_val = pc_ret_imm_en ? pc_ret_imm_val : pc_ret_imm_val_r;
    assign eff_pc_stack_en   = pc_stack_en | pc_stack_en_r;
    assign eff_pc_stack_val  = pc_stack_en ? pc_stack_val : pc_stack_val_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r            <= RESET_FETCH_ADDR;
            esp_r            <= RESET_ESP;
            fault_pending_r  <= 1'b0;
            fault_class_r    <= 4'h0;
            fault_error_r    <= 32'h0;

            pc_eip_en_r      <= 1'b0;
            pc_eip_val_r     <= 32'h0;
            pc_target_en_r   <= 1'b0;
            pc_target_val_r  <= 32'h0;
            pc_ret_imm_en_r  <= 1'b0;
            pc_ret_imm_val_r <= 16'h0;
            pc_stack_en_r    <= 1'b0;
            pc_stack_val_r   <= 32'h0;

            endi_req_d       <= 1'b0;
            reset_flush_done <= 1'b0;

            flush_req        <= 1'b0;
            flush_addr       <= RESET_FETCH_ADDR;
            endi_done        <= 1'b0;
        end else begin
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;

            endi_req_d <= endi_req;

            // Initial authoritative reset flush
            if (!reset_flush_done) begin
                flush_req        <= 1'b1;
                flush_addr       <= RESET_FETCH_ADDR;
                reset_flush_done <= 1'b1;
            end

            if (raise_req) begin
                fault_pending_r <= 1'b1;
                fault_class_r   <= raise_fc;
                fault_error_r   <= raise_fe;
            end

            // Latch incoming staged values for fallback visibility at ENDI.
            if (pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end
            if (pc_target_en) begin
                pc_target_en_r  <= 1'b1;
                pc_target_val_r <= pc_target_val;
            end
            if (pc_ret_imm_en) begin
                pc_ret_imm_en_r  <= 1'b1;
                pc_ret_imm_val_r <= pc_ret_imm_val;
            end
            // pc_stack_en staged by stack_engine after PUSH32/POP32 service completes
            if (pc_stack_en) begin
                pc_stack_en_r  <= 1'b1;
                pc_stack_val_r <= pc_stack_val;
            end

            // ENDI launch edge only
            if (endi_req && !endi_req_d) begin
                // CM_STACK (bit 4): CALL or RET.
                // stack_engine already did the memory work via service call.
                // Commit applies: staged ESP (from stack_engine) + optional ret_imm,
                // and staged EIP (call target for CALL; T2 popped value for RET).
                if (endi_mask[4] && !fault_pending_r) begin
                    // Apply new ESP from stack_engine staging + optional RET imm16 adjust
                    esp_r <= eff_pc_stack_val +
                             (eff_pc_ret_imm_en ? {16'h0, eff_pc_ret_imm_val} : 32'h0);

                    // Apply new EIP: pc_target_val holds call target (direct/indirect)
                    // or popped return address (RET, staged by microsequencer at ENDI).
                    if (eff_pc_target_en) begin
                        eip_r      <= eff_pc_target_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_target_val;
                    end else if (indirect_call_target_valid) begin
                        // Indirect CALL: target provided externally (no register file yet)
                        eip_r      <= indirect_call_target;
                        flush_req  <= 1'b1;
                        flush_addr <= indirect_call_target;
                    end else begin
                        eip_r      <= eff_pc_eip_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_eip_val;
                    end

                    pc_eip_en_r      <= 1'b0;
                    pc_eip_val_r     <= 32'h0;
                    pc_target_en_r   <= 1'b0;
                    pc_target_val_r  <= 32'h0;
                    pc_ret_imm_en_r  <= 1'b0;
                    pc_ret_imm_val_r <= 16'h0;
                    pc_stack_en_r    <= 1'b0;
                    pc_stack_val_r   <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // CM_FLUSHQ (bit 9) without CM_STACK: JMP redirect commit path
                else if (endi_mask[9] && !endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_target_en) begin
                        eip_r      <= eff_pc_target_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_target_val;
                    end else if (eff_pc_eip_en) begin
                        eip_r      <= eff_pc_eip_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_eip_val;
                    end else begin
                        flush_req  <= 1'b1;
                        flush_addr <= eip_r;
                    end

                    pc_eip_en_r      <= 1'b0;
                    pc_eip_val_r     <= 32'h0;
                    pc_target_en_r   <= 1'b0;
                    pc_target_val_r  <= 32'h0;
                    pc_ret_imm_en_r  <= 1'b0;
                    pc_ret_imm_val_r <= 16'h0;
                    pc_stack_en_r    <= 1'b0;
                    pc_stack_val_r   <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Sequential EIP commit (CM_EIP only)
                else if (endi_mask[1] && !endi_mask[9] && !endi_mask[4]
                         && eff_pc_eip_en && !fault_pending_r) begin
                    eip_r <= eff_pc_eip_val;

                    pc_eip_en_r      <= 1'b0;
                    pc_eip_val_r     <= 32'h0;
                    pc_target_en_r   <= 1'b0;
                    pc_target_val_r  <= 32'h0;
                    pc_ret_imm_en_r  <= 1'b0;
                    pc_ret_imm_val_r <= 16'h0;
                    pc_stack_en_r    <= 1'b0;
                    pc_stack_val_r   <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Clear / fault-only path
                else begin
                    pc_eip_en_r      <= 1'b0;
                    pc_eip_val_r     <= 32'h0;
                    pc_target_en_r   <= 1'b0;
                    pc_target_val_r  <= 32'h0;
                    pc_ret_imm_en_r  <= 1'b0;
                    pc_ret_imm_val_r <= 16'h0;
                    pc_stack_en_r    <= 1'b0;
                    pc_stack_val_r   <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
            end
        end
    end

endmodule