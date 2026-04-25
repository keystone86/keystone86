// Keystone86 / Aegis
// rtl/core/services/stack_engine.sv
//
// Rung 3: Stack push/pop service leaf.
//
// Owns (per Appendix B):
//   - Stack push: ESP decrement + stack write
//   - Stack pop:  stack read + ESP increment
//   - PC_STACK_* staging: new ESP for commit_engine to apply at ENDI
//   - Stack memory bus (stk_wr_en / stk_rd_req)
//
// Must not:
//   - Know which instruction is executing (instruction-agnostic leaf)
//   - Apply ESP or EIP architecturally (commit_engine owns that, at ENDI only)
//   - Call other services (leaf function; only microcode calls services)
//
// Protocol (same as fetch_engine / flow_control):
//   - svc_req is a one-cycle start pulse
//   - Result is latched; svc_done/svc_sr presented one cycle after completion
//
// PUSH32/PUSH16:
//   push_val input holds the value to push.
//   For Rung 3 CALL, cpu_top wires push_val = meta_next_eip (return address).
//   Stack write is issued on the start cycle; completion reported next cycle.
//
// POP32/POP16:
//   Stack read is issued on start; svc_done is held until stk_rd_ready.
//   Popped value is written to T2 via t2_wr_en / t2_wr_data (service ABI).
//   New ESP is staged in pc_stack_val for commit_engine.
//
// RET imm16 ESP adjustment is NOT applied here.
// commit_engine adds pc_ret_imm_val to pc_stack_val at ENDI.
// This keeps ret imm16 semantics at the commit boundary, not in this leaf.

import keystone86_pkg::*;

module stack_engine (
    input  logic        clk,
    input  logic        reset_n,

    // --- Service interface ---
    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    // --- Current ESP from commit_engine (read-only) ---
    input  logic [31:0] esp_in,

    // --- Push value: caller wires appropriate source ---
    // Rung 3: wired to meta_next_eip (CALL return address).
    input  logic [31:0] push_val,

    // --- Popped value to T2 (service ABI; same pattern as flow_control) ---
    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data,

    // --- Staged new ESP for commit_engine ---
    output logic        pc_stack_en,
    output logic [31:0] pc_stack_val,

    // --- Stack memory bus ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,
    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,

    // --- Squash ---
    input  logic        squash
);

    logic        active_r;
    logic [7:0]  svc_id_r;
    logic [31:0] esp_snap_r;

    logic        complete_pending_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t2_wr_en_r;
    logic [31:0] complete_t2_wr_data_r;
    logic        complete_pc_stack_en_r;
    logic [31:0] complete_pc_stack_val_r;

    // Push write issued on start cycle; completion latch fires next cycle.
    logic        push_pending_r;
    logic [31:0] push_new_esp_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n || squash) begin
            active_r                <= 1'b0;
            svc_id_r                <= 8'h00;
            esp_snap_r              <= 32'h0;
            complete_pending_r      <= 1'b0;
            complete_sr_r           <= SR_WAIT;
            complete_t2_wr_en_r     <= 1'b0;
            complete_t2_wr_data_r   <= 32'h0;
            complete_pc_stack_en_r  <= 1'b0;
            complete_pc_stack_val_r <= 32'h0;
            push_pending_r          <= 1'b0;
            push_new_esp_r          <= 32'h0;
        end else begin
            complete_pending_r      <= 1'b0;
            complete_sr_r           <= SR_WAIT;
            complete_t2_wr_en_r     <= 1'b0;
            complete_t2_wr_data_r   <= 32'h0;
            complete_pc_stack_en_r  <= 1'b0;
            complete_pc_stack_val_r <= 32'h0;
            push_pending_r          <= 1'b0;

            // PUSH completion: one cycle after write was issued
            if (push_pending_r) begin
                complete_pending_r      <= 1'b1;
                complete_sr_r           <= SR_OK;
                complete_pc_stack_en_r  <= 1'b1;
                complete_pc_stack_val_r <= push_new_esp_r;
                active_r                <= 1'b0;
                svc_id_r                <= 8'h00;
            end

            // POP completion: when stk_rd_ready arrives
            else if (active_r && (svc_id_r == POP32 || svc_id_r == POP16)) begin
                if (stk_rd_ready) begin
                    complete_pending_r      <= 1'b1;
                    complete_sr_r           <= SR_OK;
                    complete_t2_wr_en_r     <= 1'b1;
                    complete_t2_wr_data_r   <= stk_rd_data;
                    complete_pc_stack_en_r  <= 1'b1;
                    // New ESP: increment by width (standard pop; ret_imm adjustment is commit_engine's job)
                    complete_pc_stack_val_r <= esp_snap_r +
                                              (svc_id_r == POP32 ? 32'h4 : 32'h2);
                    active_r                <= 1'b0;
                    svc_id_r                <= 8'h00;
                end
            end

            // New service start
            else if (!active_r && svc_req) begin
                case (svc_id)
                    PUSH32: begin
                        push_new_esp_r <= esp_in - 32'h4;
                        push_pending_r <= 1'b1;
                        active_r       <= 1'b1;
                        svc_id_r       <= svc_id;
                        esp_snap_r     <= esp_in;
                    end
                    PUSH16: begin
                        push_new_esp_r <= esp_in - 32'h2;
                        push_pending_r <= 1'b1;
                        active_r       <= 1'b1;
                        svc_id_r       <= svc_id;
                        esp_snap_r     <= esp_in;
                    end
                    POP32,
                    POP16: begin
                        active_r   <= 1'b1;
                        svc_id_r   <= svc_id;
                        esp_snap_r <= esp_in;
                    end
                    default: begin
                        complete_pending_r <= 1'b1;
                        complete_sr_r      <= SR_FAULT;
                    end
                endcase
            end
        end
    end

    // ----------------------------------------------------------------
    // Combinational outputs
    // ----------------------------------------------------------------
    always_comb begin
        svc_done   = complete_pending_r;
        svc_sr     = complete_pending_r ? complete_sr_r : SR_WAIT;

        t2_wr_en   = complete_pending_r & complete_t2_wr_en_r;
        t2_wr_data = complete_t2_wr_data_r;

        pc_stack_en  = complete_pending_r & complete_pc_stack_en_r;
        pc_stack_val = complete_pc_stack_val_r;

        stk_wr_en   = 1'b0;
        stk_wr_addr = 32'h0;
        stk_wr_data = 32'h0;
        stk_rd_req  = 1'b0;
        stk_rd_addr = 32'h0;

        // Stack bus: issued on start cycle (not registered, so write/read appear immediately)
        if (!active_r && svc_req) begin
            case (svc_id)
                PUSH32: begin
                    stk_wr_en   = 1'b1;
                    stk_wr_addr = esp_in - 32'h4;
                    stk_wr_data = push_val;
                end
                PUSH16: begin
                    stk_wr_en   = 1'b1;
                    stk_wr_addr = esp_in - 32'h2;
                    stk_wr_data = {16'h0, push_val[15:0]};
                end
                POP32: begin
                    stk_rd_req  = 1'b1;
                    stk_rd_addr = esp_in;
                end
                POP16: begin
                    stk_rd_req  = 1'b1;
                    stk_rd_addr = esp_in;
                end
                default: ;
            endcase
        end else if (active_r && (svc_id_r == POP32 || svc_id_r == POP16)
                     && !stk_rd_ready) begin
            // Hold rd_addr stable while waiting for ready
            stk_rd_addr = esp_snap_r;
        end
    end

endmodule
