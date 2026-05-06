// Keystone86 / Aegis
// rtl/core/microsequencer.sv
//
// Rung 6 Pass 2 service-capable microsequencer.
//
// Active intent:
//   - Decoder hands off only decode-owned metadata.
//   - Services fetch displacement/immediate payloads and compute/validate
//     control-transfer targets.
//   - CALL return-address and RET immediate handoffs are staged explicitly
//     into commit_engine and become architectural only at ENDI.
//   - Jcc condition metadata is latched as decode-owned metadata and carried
//     to flow_control; the sequencer branches only on the registered T3 result.
//   - The bounded MOV immediate-to-register slices use generic BR/EXTRACT/
//     STAGE_GPR behavior: decode supplies width/register metadata, FETCH_IMM*
//     supplies T4, and ENDI is the only architectural register visibility point.
//
// Control-transfer cleanup rule for this rung:
//   - Do NOT squash on JMP dispatch. fetch_engine still needs fall-through
//     displacement bytes.
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
    input  logic [3:0]  cond_code_in,
    input  logic        dec_is_call,
    input  logic        dec_is_ret,
    output logic        dec_ack,

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
    input  logic [3:0]  fault_class_in,

    // --- Commit staging ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,
    output logic        pc_target_en,
    output logic [31:0] pc_target_val,
    output logic        pc_gpr_en,
    output logic [2:0]  pc_gpr_idx,
    output logic [1:0]  pc_gpr_opsz,
    output logic [31:0] pc_gpr_val,
    output logic        pc_stack_adj_en,
    output logic [31:0] pc_stack_adj_val,

    // --- Service metadata inputs ---
    output logic [31:0] stack_push_data,
    output logic        mseq_t2_wr_en,
    output logic [31:0] mseq_t2_wr_data,
    output logic        mseq_t3_wr_en,
    output logic [31:0] mseq_t3_wr_data,
    output logic        mseq_t4_wr_en,
    output logic [31:0] mseq_t4_wr_data,

    // --- Service dispatch interface ---
    output logic [7:0]  svc_id_out,
    output logic        svc_req_out,
    input  logic        svc_done_in,
    input  logic [1:0]  svc_sr_in,

    // --- T2 read (computed target from flow_control) ---
    input  logic [31:0] t2_data,
    input  logic [31:0] t4_data,
    input  logic [31:0] t3_data,

    // --- Metadata latch outputs (to services) ---
    input  logic [7:0]  meta_opcode_class_in,
    input  logic [1:0]  meta_opsz_in,
    input  logic [2:0]  meta_imm_class_in,
    input  logic [2:0]  meta_reg_dst_in,
    output logic [31:0] meta_next_eip,
    output logic [3:0]  meta_cond_code,

    // --- Observability ---
    output logic [1:0]  dbg_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id
);

    localparam logic [3:0] UOP_NOP   = 4'h0;
    localparam logic [3:0] UOP_BR    = 4'h4;
    localparam logic [3:0] UOP_EXTRACT = 4'h7;
    localparam logic [3:0] UOP_SVCW  = 4'h9;
    localparam logic [3:0] UOP_STAGE = 4'hA;
    localparam logic [3:0] UOP_RAISE = 4'hC;
    localparam logic [3:0] UOP_ENDI  = 4'hE;
    localparam logic [3:0] UOP_EXT   = 4'hF;

    localparam logic [9:0] MF_OPSZ         = 10'h001;
    localparam logic [9:0] MF_IMM_CLASS    = 10'h004;
    localparam logic [9:0] MF_OPCODE_CLASS = 10'h006;
    localparam logic [9:0] MF_REG_DST      = 10'h009;
    localparam logic [9:0] MF_NEXT_EIP     = 10'h012;
    localparam logic [9:0] MF_FC_TO_VECTOR = 10'h013;

    logic [1:0]  state, state_next;
    logic [11:0] upc_r, upc_next;
    logic [7:0]  entry_id_r;
    logic [31:0] next_eip_r;
    logic        is_jmp_r;
    logic        is_jcc_r;
    logic        is_call_r;
    logic        is_ret_r;
    logic        is_int_r;
    logic        is_iret_r;

    logic        dispatch_rom_pending;
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;
    logic        execute_fetch_pending;

    logic        ctrl_transfer_pending;

    logic        ext_pending_r;
    logic [7:0]  svc_id_r;
    logic [1:0]  sr_r;
    logic [3:0]  cond_code_r;
    logic [7:0]  meta_opcode_class_r;
    logic [1:0]  meta_opsz_r;
    logic [2:0]  meta_imm_class_r;
    logic [2:0]  meta_reg_dst_r;

    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;
    assign dbg_state      = state;
    assign dbg_upc        = upc_r;
    assign dbg_entry_id   = entry_id_r;
    // Normal instructions use M_NEXT_EIP as their return/fall-through
    // boundary. The bounded Pass 4 #UD path pushes the faulting opcode IP:
    // ENTRY_NULL consumes exactly one unknown opcode byte, so that IP is
    // M_NEXT_EIP-1 without adding a new broad metadata field.
    assign meta_next_eip  = (entry_id_r == ENTRY_NULL) ? (next_eip_r - 32'd1)
                                                       : next_eip_r;
    assign meta_cond_code = cond_code_r;

    logic [3:0] uop_class;
    logic [5:0] uop_target;
    logic [3:0] uop_cond;
    logic [9:0] uop_imm10;
    logic [3:0] uop_dst_reg;
    logic [3:0] uop_src_reg;

    assign uop_class  = uinst[31:28];
    assign uop_target = uinst[27:22];
    assign uop_cond   = uinst[21:18];
    assign uop_imm10  = uinst[9:0];
    assign uop_dst_reg = uinst[17:14];
    assign uop_src_reg = uinst[13:10];

    function automatic logic [31:0] temp_value(input logic [3:0] reg_id);
        case (reg_id)
            REG_T2:  return t2_data;
            REG_T3:  return t3_data;
            REG_T4:  return t4_data;
            default: return 32'h0;
        endcase
    endfunction

    function automatic logic [31:0] extract_value(input logic [9:0] field_id);
        case (field_id)
            MF_OPSZ:         return {30'h0, meta_opsz_r};
            MF_IMM_CLASS:    return {29'h0, meta_imm_class_r};
            MF_OPCODE_CLASS: return {24'h0, meta_opcode_class_r};
            MF_REG_DST:      return {29'h0, meta_reg_dst_r};
            MF_NEXT_EIP:     return next_eip_r;
            MF_FC_TO_VECTOR: return (fault_class_in == FC_UD) ? 32'h00000006 :
                                                                 32'h00000000;
            default:         return 32'h0;
        endcase
    endfunction

    logic br_taken;
    logic [7:0] current_svc_id;
    logic retire_ctrl_xfer_pulse;
    always_comb begin
        case (uop_cond)
            C_ALWAYS: br_taken = 1'b1;
            C_OK:     br_taken = (sr_r == SR_OK);
            C_FAULT:  br_taken = (sr_r == SR_FAULT);
            C_WAIT:   br_taken = (sr_r == SR_WAIT);
            C_W8:     br_taken = (meta_opsz_r == 2'h0);
            C_T3Z:    br_taken = (t3_data == 32'h0);
            C_T3NZ:   br_taken = (t3_data != 32'h0);
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
    assign current_svc_id = ext_pending_r ? uinst[7:0] : {2'b00, uop_target};
    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state                 <= MSEQ_FETCH_DECODE;
            upc_r                 <= 12'h000;
            entry_id_r            <= ENTRY_RESET;
            next_eip_r            <= 32'h0;
            cond_code_r           <= 4'h0;
            is_jmp_r              <= 1'b0;
            is_jcc_r              <= 1'b0;
            is_call_r             <= 1'b0;
            is_ret_r              <= 1'b0;
            is_int_r              <= 1'b0;
            is_iret_r             <= 1'b0;
            dispatch_rom_pending  <= 1'b0;
            dispatch_pending      <= 1'b0;
            dispatch_entry_latch  <= 8'h00;
            execute_fetch_pending <= 1'b0;
            ctrl_transfer_pending <= 1'b0;
            ext_pending_r         <= 1'b0;
            svc_id_r              <= 8'h00;
            sr_r                  <= SR_OK;
            meta_opcode_class_r   <= 8'h00;
            meta_opsz_r           <= 2'h0;
            meta_imm_class_r      <= 3'h0;
            meta_reg_dst_r        <= 3'h0;
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
                        cond_code_r          <= cond_code_in;
                        meta_opcode_class_r  <= meta_opcode_class_in;
                        meta_opsz_r          <= meta_opsz_in;
                        meta_imm_class_r     <= meta_imm_class_in;
                        meta_reg_dst_r       <= meta_reg_dst_in;
                        is_jmp_r             <= (entry_id_in == ENTRY_JMP_NEAR);
                        is_jcc_r             <= (entry_id_in == ENTRY_JCC);
                        is_call_r            <= dec_is_call;
                        is_ret_r             <= dec_is_ret;
                        is_int_r             <= (entry_id_in == ENTRY_INT);
                        is_iret_r            <= (entry_id_in == ENTRY_IRET);
                        dispatch_entry_latch <= entry_id_in;
                        dispatch_rom_pending <= 1'b1;
                    end

                    if (dispatch_rom_pending) begin
                        dispatch_rom_pending <= 1'b0;
                        dispatch_pending     <= 1'b1;
                    end

                    if (dispatch_pending) begin
                        dispatch_pending      <= 1'b0;
                        execute_fetch_pending <= 1'b1;

                        // Keep the queue alive through displacement/immediate
                        // fetches and through the bounded #UD delivery redirect.
                        if ((entry_id_r == ENTRY_JMP_NEAR) || (entry_id_r == ENTRY_JCC)
                            || is_call_r || is_ret_r || is_int_r || is_iret_r
                            || (entry_id_r == ENTRY_NULL))
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

                            UOP_EXTRACT: begin
                                execute_fetch_pending <= 1'b1;
                            end

                            UOP_RAISE: begin
                                execute_fetch_pending <= 1'b1;
                            end

                            UOP_STAGE: begin
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
        pc_gpr_en       = 1'b0;
        pc_gpr_idx      = 3'h0;
        pc_gpr_opsz     = 2'h0;
        pc_gpr_val      = 32'h0;
        pc_stack_adj_en = 1'b0;
        pc_stack_adj_val= 32'h0;
        stack_push_data = next_eip_r;
        mseq_t2_wr_en   = 1'b0;
        mseq_t2_wr_data = 32'h0;
        mseq_t3_wr_en   = 1'b0;
        mseq_t3_wr_data = 32'h0;
        mseq_t4_wr_en   = 1'b0;
        mseq_t4_wr_data = 32'h0;

        // Keep selected service visible while waiting.
        svc_id_out      = svc_id_r;
        svc_req_out     = 1'b0;

        case (state)
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;

                    // Stage architectural fall-through EIP.
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;
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

                        UOP_EXTRACT: begin
                            // First-slice MOV uses the same generic EXTRACT
                            // mechanism as the existing fault-vector extract:
                            // metadata is selected by Appendix A field id, and
                            // only implemented temp destinations are written.
                            if (uop_dst_reg == REG_T2) begin
                                mseq_t2_wr_en   = 1'b1;
                                mseq_t2_wr_data = extract_value(uop_imm10);
                            end else if (uop_dst_reg == REG_T3) begin
                                mseq_t3_wr_en   = 1'b1;
                                mseq_t3_wr_data = extract_value(uop_imm10);
                            end else if (uop_dst_reg == REG_T4) begin
                                mseq_t4_wr_en   = 1'b1;
                                mseq_t4_wr_data = extract_value(uop_imm10);
                            end
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_SVCW: begin
                            svc_id_out = current_svc_id;
                            svc_req_out = 1'b1;
                            state_next  = MSEQ_WAIT_SERVICE;
                        end

                        UOP_STAGE: begin
                            if (uop_imm10[5:0] == STAGE_STACK_ADJ) begin
                                pc_stack_adj_en  = 1'b1;
                                pc_stack_adj_val = temp_value(uop_src_reg);
                            end else if (uop_imm10[5:0] == STAGE_GPR) begin
                                pc_gpr_en  = 1'b1;
                                pc_gpr_idx = meta_reg_dst_r;
                                pc_gpr_opsz = meta_opsz_r;
                                pc_gpr_val = temp_value(uop_src_reg);
                            end
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_RAISE: begin
                            raise_req  = 1'b1;
                            raise_fc   = uop_target[3:0];
                            raise_fe   = 32'h0;
                            upc_next   = upc_r + 12'h1;
                            state_next = MSEQ_FAULT_HOLD;
                        end

                        UOP_ENDI: begin
                            // Present the JMP target only while ENDI is still
                            // in flight. Once commit reports endi_done, do not
                            // re-present the same target on the retire-complete
                            // cycle or commit_engine will stage it again.
                            if (((is_jmp_r || is_call_r || is_ret_r ||
                                  (is_jcc_r && (t3_data != 32'h0))) && !endi_done)) begin
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
