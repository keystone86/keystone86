// Keystone86 / Aegis
// rtl/core/commit_engine.sv
//
// Current active role:
//   Commit behavior required by the delivered Rung 2 direct-JMP path.
//
// Rung 2 contract:
//   - Redirect becomes architecturally visible only at ENDI.
//   - CM_FLUSHQ must generate a committed flush pulse.
//   - For the active JMP path, flush_addr must be the committed redirect target.
//   - ENDI launch must be able to consume LIVE pending EIP/target inputs
//     in the same cycle, not only staged *_r copies.
//
// Scope note:
//   This file may contain structural surfaces that later rungs can build on,
//   but current Rung 2 verification claims only the bounded direct-JMP commit
//   and flush behavior proven by the active regression.

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

    // --- Reserved structural surfaces for later rungs ---
    input  logic        pc_ret_addr_en,
    input  logic [31:0] pc_ret_addr_val,
    input  logic        pc_ret_imm_en,
    input  logic [15:0] pc_ret_imm_val,
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

    // --- Stack write bus ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,

    // --- Stack read bus ---
    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,

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

    // Pending commit staging. Rung 2 actively uses the EIP/target path.
    // The remaining fields are retained as structural surfaces but are not
    // part of current Rung 2 acceptance claims.
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;
    logic [31:0] pc_target_val_r;
    logic        pc_ret_addr_en_r;
    logic [31:0] pc_ret_addr_val_r;
    logic        pc_ret_imm_en_r;
    logic [15:0] pc_ret_imm_val_r;

    // Reserved wait state for later-rung stack-based returns.
    logic        ret_wait_r;
    logic        ret_imm_en_saved;
    logic [15:0] ret_imm_val_saved;

    // ENDI rising-edge detection
    logic        endi_req_d;
    logic        reset_flush_done;

    // Effective live-or-staged values for ENDI launch. This lets the
    // commit boundary consume the active redirect handoff even if the
    // value is still live on the launch cycle.
    logic        eff_pc_eip_en;
    logic [31:0] eff_pc_eip_val;
    logic        eff_pc_target_en;
    logic [31:0] eff_pc_target_val;
    logic        eff_pc_ret_addr_en;
    logic [31:0] eff_pc_ret_addr_val;
    logic        eff_pc_ret_imm_en;
    logic [15:0] eff_pc_ret_imm_val;

    assign eip           = eip_r;
    assign esp           = esp_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    assign eff_pc_eip_en       = pc_eip_en | pc_eip_en_r;
    assign eff_pc_eip_val      = pc_eip_en ? pc_eip_val : pc_eip_val_r;
    assign eff_pc_target_en    = pc_target_en | pc_target_en_r;
    assign eff_pc_target_val   = pc_target_en ? pc_target_val : pc_target_val_r;
    assign eff_pc_ret_addr_en  = pc_ret_addr_en | pc_ret_addr_en_r;
    assign eff_pc_ret_addr_val = pc_ret_addr_en ? pc_ret_addr_val : pc_ret_addr_val_r;
    assign eff_pc_ret_imm_en   = pc_ret_imm_en | pc_ret_imm_en_r;
    assign eff_pc_ret_imm_val  = pc_ret_imm_en ? pc_ret_imm_val : pc_ret_imm_val_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r             <= RESET_FETCH_ADDR;
            esp_r             <= RESET_ESP;
            fault_pending_r   <= 1'b0;
            fault_class_r     <= 4'h0;
            fault_error_r     <= 32'h0;

            pc_eip_en_r       <= 1'b0;
            pc_eip_val_r      <= 32'h0;
            pc_target_en_r    <= 1'b0;
            pc_target_val_r   <= 32'h0;
            pc_ret_addr_en_r  <= 1'b0;
            pc_ret_addr_val_r <= 32'h0;
            pc_ret_imm_en_r   <= 1'b0;
            pc_ret_imm_val_r  <= 16'h0;

            ret_wait_r        <= 1'b0;
            ret_imm_en_saved  <= 1'b0;
            ret_imm_val_saved <= 16'h0;

            endi_req_d        <= 1'b0;
            reset_flush_done  <= 1'b0;

            flush_req         <= 1'b0;
            flush_addr        <= RESET_FETCH_ADDR;
            endi_done         <= 1'b0;

            stk_wr_en         <= 1'b0;
            stk_wr_addr       <= 32'h0;
            stk_wr_data       <= 32'h0;
            stk_rd_req        <= 1'b0;
            stk_rd_addr       <= 32'h0;
        end else begin
            // Default pulse clears
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;
            stk_wr_en  <= 1'b0;
            stk_rd_req <= 1'b0;

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

            // Stage pending values for later visibility / fallback use.
            // While a RET stack-pop completion is in flight, do not restage
            // fresh decoder fall-through state on top of the architectural
            // return result that is about to be restored from the stack.
            if (!ret_wait_r && pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end

            if (!ret_wait_r && pc_target_en) begin
                pc_target_en_r  <= 1'b1;
                pc_target_val_r <= pc_target_val;
            end

            if (!ret_wait_r && pc_ret_addr_en) begin
                pc_ret_addr_en_r  <= 1'b1;
                pc_ret_addr_val_r <= pc_ret_addr_val;
            end

            if (!ret_wait_r && pc_ret_imm_en) begin
                pc_ret_imm_en_r  <= 1'b1;
                pc_ret_imm_val_r <= pc_ret_imm_val;
            end

            // Reserved RET completion path for later rungs.
            if (ret_wait_r) begin
                if (stk_rd_ready) begin
                    ret_wait_r        <= 1'b0;
                    eip_r             <= stk_rd_data;
                    esp_r             <= esp_r + 32'h4 +
                                         (ret_imm_en_saved ? {16'h0, ret_imm_val_saved} : 32'h0);

                    flush_req         <= 1'b1;
                    flush_addr        <= stk_rd_data;

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;
                    ret_imm_en_saved  <= 1'b0;
                    ret_imm_val_saved <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
            end
            // ENDI launch edge only
            else if (endi_req && !endi_req_d) begin
                // Reserved CALL / RET commit path
                if (endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_ret_addr_en) begin
                        stk_wr_en   <= 1'b1;
                        stk_wr_addr <= esp_r - 32'h4;
                        stk_wr_data <= eff_pc_ret_addr_val;
                        esp_r       <= esp_r - 32'h4;

                        if (eff_pc_target_en) begin
                            eip_r      <= eff_pc_target_val;
                            flush_req  <= 1'b1;
                            flush_addr <= eff_pc_target_val;
                        end else if (indirect_call_target_valid) begin
                            eip_r      <= indirect_call_target;
                            flush_req  <= 1'b1;
                            flush_addr <= indirect_call_target;
                        end else begin
                            eip_r      <= eff_pc_eip_val;
                            flush_req  <= 1'b1;
                            flush_addr <= eff_pc_eip_val;
                        end

                        pc_eip_en_r       <= 1'b0;
                        pc_eip_val_r      <= 32'h0;
                        pc_target_en_r    <= 1'b0;
                        pc_target_val_r   <= 32'h0;
                        pc_ret_addr_en_r  <= 1'b0;
                        pc_ret_addr_val_r <= 32'h0;
                        pc_ret_imm_en_r   <= 1'b0;
                        pc_ret_imm_val_r  <= 16'h0;

                        if (endi_mask[8]) begin
                            fault_pending_r <= 1'b0;
                            fault_class_r   <= 4'h0;
                            fault_error_r   <= 32'h0;
                        end

                        endi_done <= 1'b1;
                    end else begin
                        stk_rd_req        <= 1'b1;
                        stk_rd_addr       <= esp_r;
                        ret_wait_r        <= 1'b1;
                        ret_imm_en_saved  <= eff_pc_ret_imm_en;
                        ret_imm_val_saved <= eff_pc_ret_imm_val;
                    end
                end
                // Active Rung 2 JMP / redirect commit path
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
                        // CM_FLUSHQ still means the queue must restart.
                        flush_req  <= 1'b1;
                        flush_addr <= eip_r;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Sequential EIP commit
                else if (endi_mask[1] && !endi_mask[9] && !endi_mask[4]
                         && eff_pc_eip_en && !fault_pending_r) begin
                    eip_r <= eff_pc_eip_val;

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Clear / fault-only path
                else begin
                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

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