// Keystone86 / Aegis
// rtl/core/microsequencer.sv
//
// Rung 3 service-capable microsequencer.
//
// Rung 3 additions over Rung 2:
//   - Latches CALL/RET decode-owned metadata (is_call, call_target,
//     has_call_target, is_ret, has_ret_imm, ret_imm) at decode handoff.
//   - Stages pc_ret_addr_en/val at dispatch for CALL (return address to push).
//   - Stages pc_target_en/val at dispatch for direct CALL (decoder-computed target).
//   - Stages pc_ret_imm_en/val at dispatch for RET imm16.
//   - Sets ctrl_transfer_pending for CALL and RET (same as JMP) so squash
//     fires when the committed redirect retires at ENDI.
//
// Control-transfer cleanup rule:
//   - Do NOT squash on JMP/CALL/RET dispatch. fetch_engine still needs
//     fall-through displacement bytes for the JMP path.
//   - Do assert squash when the committed redirect retires so stale decoder
//     state and abandoned-stream work do not survive past ENDI.
//
// Service handoff rule:
//   - svc_req_out is a one-cycle start pulse.
//   - svc_id_r remains stable while WAIT_SERVICE is active.
//   - SR_WAIT is a true hold condition. The sequencer does not advance until
//     the selected service reports a terminal result.

import keystone86_pkg::*;

module microsequencer (
    input  logic        clk,
    input  logic        reset_n,

    // --- Decoder interface ---
    input  logic        decode_done,
    input  logic [7:0]  entry_id_in,
    input  logic [31:0] next_eip_in,
    output logic        dec_ack,

    // --- Decoder CALL/RET metadata (Rung 3) ---
    // Staged at decode handoff; used to drive commit_engine staging at dispatch.
    // Decoder owns classification; microsequencer must not recompute these.
    input  logic        is_call_in,
    input  logic [31:0] call_target_in,
    input  logic        has_call_target_in,
    input  logic        is_ret_in,
    input  logic        has_ret_imm_in,
    input  logic [15:0] ret_imm_in,

    // --- Squash output ---
    output logic        squash,

    // --- Microcode ROM interface ---
    output logic [11:0] upc,
    input  logic [31:0] uinst,
    output logic [7:0]  dispatch_entry,
    input  logic [11:0] dispatch_upc_in,

    // --- Commit engine interface ---
    output logic        endi_req,
    output logic [9:0]  endi_mask,
    output logic        raise_req,
    output logic [3:0]  raise_fc,
    output logic [31:0] raise_fe,
    input  logic        endi_done,

    // --- EIP staging ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,
    output logic        pc_target_en,
    output logic [31:0] pc_target_val,

    // --- CALL/RET staging (Rung 3) ---
    // pc_ret_imm: post-pop ESP adjustment for RET imm16.
    // Staged at dispatch; applied by commit_engine at ENDI on top of pc_stack_val.
    // pc_ret_addr was removed: stack_engine now owns the push via SVCW PUSH32.
    output logic        pc_ret_imm_en,
    output logic [15:0] pc_ret_imm_val,

    // --- Service dispatch interface ---
    output logic [7:0]  svc_id_out,
    output logic        svc_req_out,
    input  logic        svc_done_in,
    input  logic [1:0]  svc_sr_in,

    // --- T2 read (computed target from flow_control) ---
    input  logic [31:0] t2_data,

    // --- Metadata latch outputs (to services) ---
    output logic [31:0] meta_next_eip,

    // --- Observability ---
    output logic [1:0]  dbg_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id
);

    localparam logic [3:0] UOP_NOP   = 4'h0;
    localparam logic [3:0] UOP_BR    = 4'h4;
    localparam logic [3:0] UOP_SVCW  = 4'h9;
    localparam logic [3:0] UOP_RAISE = 4'hC;
    localparam logic [3:0] UOP_ENDI  = 4'hE;
    localparam logic [3:0] UOP_EXT   = 4'hF;

    logic [1:0]  state, state_next;
    logic [11:0] upc_r, upc_next;
    logic [7:0]  entry_id_r;
    logic [31:0] next_eip_r;
    logic        is_jmp_r;

    logic        dispatch_rom_pending;
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;
    logic        execute_fetch_pending;

    logic        ctrl_transfer_pending;

    logic        ext_pending_r;
    logic [7:0]  svc_id_r;
    logic [1:0]  sr_r;

    // Rung 3: latched CALL/RET decode-owned metadata.
    // Captured at decode handoff; held stable through dispatch and ENDI.
    logic        is_call_r;
    logic [31:0] call_target_r;
    logic        has_call_target_r;
    logic        is_ret_r;
    logic        has_ret_imm_r;
    logic [15:0] ret_imm_r;

    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;
    assign dbg_state      = state;
    assign dbg_upc        = upc_r;
    assign dbg_entry_id   = entry_id_r;
    assign meta_next_eip  = next_eip_r;

    logic [3:0] uop_class;
    logic [5:0] uop_target;
    logic [3:0] uop_cond;
    logic [9:0] uop_imm10;

    assign uop_class  = uinst[31:28];
    assign uop_target = uinst[27:22];
    assign uop_cond   = uinst[21:18];
    assign uop_imm10  = uinst[9:0];

    logic br_taken;

    logic retire_ctrl_xfer_pulse;
    always_comb begin
        case (uop_cond)
            C_ALWAYS: br_taken = 1'b1;
            C_OK:     br_taken = (sr_r == SR_OK);
            C_FAULT:  br_taken = (sr_r == SR_FAULT);
            C_WAIT:   br_taken = (sr_r == SR_WAIT);
            default:  br_taken = 1'b0;
        endcase
    end

    // Committed redirect cleanup pulse.
    // This is asserted only when ENDI for an in-flight control transfer
    // retires. It is intentionally not asserted at dispatch time.
    assign retire_ctrl_xfer_pulse = ctrl_transfer_pending &&
                                    (state == MSEQ_EXECUTE) &&
                                    !execute_fetch_pending &&
                                    (uop_class == UOP_ENDI) &&
                                    endi_done;

    assign squash = retire_ctrl_xfer_pulse;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state                 <= MSEQ_FETCH_DECODE;
            upc_r                 <= 12'h000;
            entry_id_r            <= ENTRY_RESET;
            next_eip_r            <= 32'h0;
            is_jmp_r              <= 1'b0;
            dispatch_rom_pending  <= 1'b0;
            dispatch_pending      <= 1'b0;
            dispatch_entry_latch  <= 8'h00;
            execute_fetch_pending <= 1'b0;
            ctrl_transfer_pending <= 1'b0;
            ext_pending_r         <= 1'b0;
            svc_id_r              <= 8'h00;
            sr_r                  <= SR_OK;
            is_call_r             <= 1'b0;
            call_target_r         <= 32'h0;
            has_call_target_r     <= 1'b0;
            is_ret_r              <= 1'b0;
            has_ret_imm_r         <= 1'b0;
            ret_imm_r             <= 16'h0;
        end else begin
            state <= state_next;
            upc_r <= upc_next;

            // Clear the control-transfer pending flag exactly when the
            // committed redirect retires.
            if (retire_ctrl_xfer_pulse)
                ctrl_transfer_pending <= 1'b0;

            case (state)
                MSEQ_FETCH_DECODE: begin
                    if (decode_done && !dispatch_rom_pending && !dispatch_pending
                        && !ctrl_transfer_pending) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        is_jmp_r             <= (entry_id_in == ENTRY_JMP_NEAR);
                        dispatch_entry_latch <= entry_id_in;
                        dispatch_rom_pending <= 1'b1;
                        // Rung 3: latch CALL/RET decode-owned metadata.
                        // Decoder owns these values; we only preserve them.
                        is_call_r         <= is_call_in;
                        call_target_r     <= call_target_in;
                        has_call_target_r <= has_call_target_in;
                        is_ret_r          <= is_ret_in;
                        has_ret_imm_r     <= has_ret_imm_in;
                        ret_imm_r         <= ret_imm_in;
                    end

                    if (dispatch_rom_pending) begin
                        dispatch_rom_pending <= 1'b0;
                        dispatch_pending     <= 1'b1;
                    end

                    if (dispatch_pending) begin
                        dispatch_pending      <= 1'b0;
                        execute_fetch_pending <= 1'b1;

                        // JMP: keep queue alive through displacement fetches.
                        // CALL/RET: also set pending — both redirect EIP and
                        // require squash + prefetch flush when ENDI retires.
                        if (entry_id_r == ENTRY_JMP_NEAR  ||
                            entry_id_r == ENTRY_CALL_NEAR ||
                            entry_id_r == ENTRY_RET_NEAR)
                            ctrl_transfer_pending <= 1'b1;
                    end
                end

                MSEQ_EXECUTE: begin
                    if (execute_fetch_pending) begin
                        // Consume one settle cycle after any uPC change.
                        execute_fetch_pending <= 1'b0;
                    end else begin
                        case (uop_class)
                            UOP_EXT: begin
                                ext_pending_r         <= 1'b1;
                                execute_fetch_pending <= 1'b1;
                            end

                            UOP_SVCW: begin
                                if (ext_pending_r) begin
                                    svc_id_r      <= uinst[7:0];
                                    ext_pending_r <= 1'b0;
                                end else begin
                                    svc_id_r <= {2'b00, uop_target};
                                end
                            end

                            UOP_NOP: begin
                                execute_fetch_pending <= 1'b1;
                            end

                            UOP_BR: begin
                                execute_fetch_pending <= 1'b1;
                            end

                            UOP_RAISE: begin
                                execute_fetch_pending <= 1'b1;
                            end

                            default: ;
                        endcase
                    end
                end

                MSEQ_WAIT_SERVICE: begin
                    if (svc_done_in && (svc_sr_in != SR_WAIT)) begin
                        sr_r                  <= svc_sr_in;
                        execute_fetch_pending <= 1'b1;
                    end
                end

                MSEQ_FAULT_HOLD: begin
                    // no sequential action
                end

                default: ;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Combinational: next-state, uPC, outputs
    // ----------------------------------------------------------------
    always_comb begin
        state_next      = state;
        upc_next        = upc_r;
        dec_ack         = 1'b0;
        endi_req        = 1'b0;
        endi_mask       = 10'h0;
        raise_req       = 1'b0;
        raise_fc        = 4'h0;
        raise_fe        = 32'h0;
        pc_eip_en       = 1'b0;
        pc_eip_val      = 32'h0;
        pc_target_en    = 1'b0;
        pc_target_val   = 32'h0;
        // Rung 3 staging defaults — asserted only at dispatch.
        // pc_ret_addr removed: stack_engine owns push via SVCW PUSH32.
        pc_ret_imm_en  = 1'b0;
        pc_ret_imm_val = 16'h0;

        // Keep selected service visible while waiting.
        svc_id_out      = svc_id_r;
        svc_req_out     = 1'b0;

        case (state)
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;

                    // Stage fall-through / return EIP (all instructions).
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;

                    // Rung 3 CALL: stage direct call target if decoder provided one.
                    // Return address push is handled by stack_engine via SVCW PUSH32 —
                    // microsequencer does NOT stage pc_ret_addr here.
                    if (is_call_r) begin
                        if (has_call_target_r) begin
                            // Direct CALL: stage decoder-computed target for commit_engine.
                            pc_target_en  = 1'b1;
                            pc_target_val = call_target_r;
                        end
                        // Indirect CALL: no pc_target_en here; commit_engine uses
                        // indirect_call_target_valid input at ENDI.
                    end

                    // Rung 3 RET imm16: stage ESP adjustment for commit_engine.
                    // Applied on top of pc_stack_val (from stack_engine POP32) at ENDI.
                    if (is_ret_r && has_ret_imm_r) begin
                        pc_ret_imm_en  = 1'b1;
                        pc_ret_imm_val = ret_imm_r;
                    end
                end
            end

            MSEQ_EXECUTE: begin
                if (execute_fetch_pending) begin
                    // one-cycle ROM settle after any uPC change
                end else begin
                    case (uop_class)
                        UOP_NOP: begin
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_BR: begin
                            if (br_taken)
                                upc_next = upc_r + 12'h1 +
                                           {{2{uop_imm10[9]}}, uop_imm10};
                            else
                                upc_next = upc_r + 12'h1;
                        end

                        UOP_EXT: begin
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_SVCW: begin
                            svc_id_out  = ext_pending_r ? uinst[7:0] : {2'b00, uop_target};
                            svc_req_out = 1'b1;
                            state_next  = MSEQ_WAIT_SERVICE;
                        end

                        UOP_RAISE: begin
                            raise_req  = 1'b1;
                            raise_fc   = uop_target[3:0];
                            raise_fe   = 32'h0;
                            upc_next   = upc_r + 12'h1;
                            state_next = MSEQ_FAULT_HOLD;
                        end

                        UOP_ENDI: begin
                            // JMP and RET both deliver their EIP target via T2.
                            //   JMP: T2 = COMPUTE_REL_TARGET result (flow_control)
                            //   RET: T2 = popped return address (stack_engine POP32)
                            // CALL target was staged at dispatch; no T2 action needed.
                            // Do not re-present after endi_done or commit_engine
                            // will double-stage the target.
                            if ((is_jmp_r || is_ret_r) && !endi_done) begin
                                pc_target_en  = 1'b1;
                                pc_target_val = t2_data;
                            end

                            endi_req  = 1'b1;
                            endi_mask = uop_imm10;

                            if (endi_done) begin
                                upc_next   = 12'h000;
                                state_next = MSEQ_FETCH_DECODE;
                            end
                        end

                        default: begin
                            upc_next = upc_r + 12'h1;
                        end
                    endcase
                end
            end

            MSEQ_WAIT_SERVICE: begin
                if (svc_done_in && (svc_sr_in != SR_WAIT)) begin
                    upc_next   = upc_r + 12'h1;
                    state_next = MSEQ_EXECUTE;
                end
            end

            MSEQ_FAULT_HOLD: begin
                state_next = MSEQ_EXECUTE;
                upc_next   = upc_r;
            end

            default: begin
                state_next = MSEQ_FETCH_DECODE;
                upc_next   = 12'h000;
            end
        endcase
    end

endmodule