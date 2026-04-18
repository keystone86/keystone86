// Keystone86 / Aegis
// rtl/core/commit_engine.sv
// Rung 3: CALL/RET stack commit + ESP architectural register
// (includes all Rung 2 JMP behavior)
//
// Ownership (Appendix B):
//   This module owns: architectural register file (EIP, ESP for Rung 3),
//   reset-visible state, ENDI processing, fault-aware end-of-instruction
//   handling, prefetch queue flush initiation, stack bus initiation.
//   This module must NOT: own instruction policy, decide what to commit
//   beyond what ENDI/control inputs explicitly request.
//
// ENDI handshake:
//   endi_req is a level signal held by the microsequencer until endi_done.
//   commit_engine launches exactly ONE ENDI transaction per instruction by
//   detecting the rising edge of endi_req (endi_req && !endi_req_d).
//   For RET, the transaction completes asynchronously when stk_rd_ready fires,
//   at which point endi_done is asserted and the microsequencer releases endi_req.
//
// CM_STACK (bit 4) processing:
//   CALL: write return address to [ESP-4], ESP -= 4, commit EIP, flush.
//         endi_done asserted in the same cycle as the write.
//   RET:  issue stk_rd_req, enter ret_wait_r.
//         When stk_rd_ready: EIP <- stk_rd_data, ESP += 4 (+ imm16 if C2),
//         flush, endi_done.

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

    // --- Pending fall-through EIP commit ---
    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    // --- Pending target EIP commit (JMP/CALL-direct target) ---
    input  logic        pc_target_en,
    input  logic [31:0] pc_target_val,

    // --- Rung 3: CALL return address to push ---
    input  logic        pc_ret_addr_en,
    input  logic [31:0] pc_ret_addr_val,

    // --- Rung 3: RET imm16 stack adjustment ---
    input  logic        pc_ret_imm_en,
    input  logic [15:0] pc_ret_imm_val,

    // --- Rung 3: indirect CALL target (from register file / testbench) ---
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

    // --- Stack write bus (CALL: push return address) ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,

    // --- Stack read bus (RET: pop return address) ---
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

    // Pending commit staging
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;
    logic [31:0] pc_target_val_r;
    logic        pc_ret_addr_en_r;
    logic [31:0] pc_ret_addr_val_r;
    logic        pc_ret_imm_en_r;
    logic [15:0] pc_ret_imm_val_r;

    // RET read-wait state
    logic        ret_wait_r;
    logic        ret_imm_en_saved;
    logic [15:0] ret_imm_val_saved;

    // ENDI rising-edge detection: launch one transaction per instruction
    logic        endi_req_d;

    logic        reset_flush_done;

    // Outputs
    assign eip           = eip_r;
    assign esp           = esp_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    // Commit mask bit positions (matches CM_* in keystone86_pkg)
    // bit 1  = CM_EIP
    // bit 4  = CM_STACK
    // bit 8  = CM_CLRF
    // bit 9  = CM_FLUSHQ

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
            flush_req         <= 1'b0;
            flush_addr        <= RESET_FETCH_ADDR;
            endi_done         <= 1'b0;
            stk_wr_en         <= 1'b0;
            stk_wr_addr       <= 32'h0;
            stk_wr_data       <= 32'h0;
            stk_rd_req        <= 1'b0;
            stk_rd_addr       <= 32'h0;
            reset_flush_done  <= 1'b0;
        end else begin
            // Top-of-cycle pulse clears
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;
            stk_wr_en  <= 1'b0;
            stk_rd_req <= 1'b0;

            // Track endi_req for rising-edge detection
            endi_req_d <= endi_req;

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
            // Stage fall-through EIP
            // --------------------------------------------------------
            if (pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end

            // --------------------------------------------------------
            // Stage target EIP (JMP/CALL-direct)
            // --------------------------------------------------------
            if (pc_target_en) begin
                pc_target_en_r  <= 1'b1;
                pc_target_val_r <= pc_target_val;
            end

            // --------------------------------------------------------
            // Stage CALL return address
            // --------------------------------------------------------
            if (pc_ret_addr_en) begin
                pc_ret_addr_en_r  <= 1'b1;
                pc_ret_addr_val_r <= pc_ret_addr_val;
            end

            // --------------------------------------------------------
            // Stage RET imm16
            // --------------------------------------------------------
            if (pc_ret_imm_en) begin
                pc_ret_imm_en_r  <= 1'b1;
                pc_ret_imm_val_r <= pc_ret_imm_val;
            end

            // --------------------------------------------------------
            // RET read-wait: hold until stk_rd_ready
            // --------------------------------------------------------
            if (ret_wait_r) begin
                if (stk_rd_ready) begin
                    ret_wait_r        <= 1'b0;
                    // Commit: EIP <- popped return address
                    eip_r      <= stk_rd_data;
                    // ESP += 4, plus optional imm16 adjustment (C2 form)
                    esp_r      <= esp_r + 32'h4 +
                                  (ret_imm_en_saved ? {16'h0, ret_imm_val_saved} : 32'h0);
                    // Flush to return address
                    flush_req  <= 1'b1;
                    flush_addr <= stk_rd_data;
                    // Clear all staging
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

            // --------------------------------------------------------
            // ENDI processing — launched on rising edge of endi_req only
            // --------------------------------------------------------
            else if (endi_req && !endi_req_d) begin

                // ---- CM_STACK (bit 4): CALL or RET ----
                if (endi_mask[4] && !fault_pending_r) begin

                    if (pc_ret_addr_en_r) begin
                        // CALL: push return address, update ESP, commit target

                        stk_wr_en   <= 1'b1;
                        stk_wr_addr <= esp_r - 32'h4;
                        stk_wr_data <= pc_ret_addr_val_r;
                        esp_r       <= esp_r - 32'h4;

                        if (pc_target_en_r) begin
                            eip_r      <= pc_target_val_r;
                            flush_req  <= 1'b1;
                            flush_addr <= pc_target_val_r;
                        end else if (indirect_call_target_valid) begin
                            eip_r      <= indirect_call_target;
                            flush_req  <= 1'b1;
                            flush_addr <= indirect_call_target;
                        end else begin
                            eip_r      <= pc_eip_val_r;
                            flush_req  <= 1'b1;
                            flush_addr <= pc_eip_val_r;
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
                        // RET: issue stack read, enter wait state
                        stk_rd_req        <= 1'b1;
                        stk_rd_addr       <= esp_r;
                        ret_wait_r        <= 1'b1;
                        ret_imm_en_saved  <= pc_ret_imm_en_r;
                        ret_imm_val_saved <= pc_ret_imm_val_r;
                        // endi_done fires when stk_rd_ready
                    end

                end

                // ---- CM_FLUSHQ (bit 9) without CM_STACK: JMP ----
                else if (endi_mask[9] && !endi_mask[4] && !fault_pending_r) begin
                    if (pc_target_en_r) begin
                        eip_r      <= pc_target_val_r;
                        flush_req  <= 1'b1;
                        flush_addr <= pc_target_val_r;
                    end else begin
                        flush_req  <= 1'b1;
                        flush_addr <= pc_eip_en_r ? pc_eip_val_r : eip_r;
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

                // ---- CM_EIP without CM_FLUSHQ/CM_STACK: sequential (NOP, prefix) ----
                else if (endi_mask[1] && !endi_mask[9] && !endi_mask[4]
                         && pc_eip_en_r && !fault_pending_r) begin
                    eip_r <= pc_eip_val_r;
                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
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

                // ---- Fault/clear-only path ----
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
