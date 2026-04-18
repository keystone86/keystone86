// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 2: SVCW, BR, MSEQ_WAIT_SERVICE, EXT word, metadata latch
//
// Ownership (Appendix B):
//   Owns: uPC management, entry dispatch, microinstruction fetch/decode,
//         service invocation (SVC/SVCW), stall on WAIT, RAISE, ENDI,
//         return to FETCH_DECODE, squash on control-transfer.
//   Must not: own instruction meaning, modify architectural state,
//             evaluate conditions (services do that).
//
// Rung 2 additions over Rung 1:
//   - UOP_SVCW (0x9): issue service request, transition to MSEQ_WAIT_SERVICE
//   - UOP_BR   (0x4): conditional branch on COND field
//   - UOP_EXT  (0xF): read extension word for service IDs > 63
//   - MSEQ_WAIT_SERVICE: stall uPC until svc_done fires
//   - metadata latch: M_NEXT_EIP latched from decoder at dispatch time
//   - T4 register: written by fetch_engine service result
//   - T2 register: written by flow_control service result
//   - SR register: written by microsequencer after each service completes
//
// Microinstruction encoding (Appendix A Section 7):
//   bits[31:28] = UOP_CLASS
//   bits[27:22] = TARGET  (6-bit service ID for SVC/SVCW when id <= 63;
//                          branch offset for BR; uPC for CALL/JMP)
//   bits[21:18] = COND    (branch condition)
//   bits[9:0]   = IMM10   (commit mask for ENDI; immediate for LOADI)
//
// EXT word (UOP_CLASS=0xF, IMM10=0x000):
//   Next ROM word carries the full 8-bit service ID in bits[7:0].
//   Used when service_id > 63 (COMPUTE_REL_TARGET=0x46, VALIDATE=0x44, etc.)
//
// Control-transfer (Rung 2):
//   JMP target: decoder sets has_target=1. Microsequencer issues squash,
//   sets ctrl_transfer_pending, stages pc_eip_en and pc_target_en.
//   ENTRY_JMP_NEAR microcode calls FETCH_DISP*, COMPUTE_REL_TARGET,
//   VALIDATE_NEAR_TRANSFER, then ENDI CM_JMP. T2 at ENDI time is the
//   target; microsequencer stages it via pc_target_en at ENDI.

import keystone86_pkg::*;

module microsequencer (
    input  logic        clk,
    input  logic        reset_n,

    // --- Decoder interface ---
    input  logic        decode_done,
    input  logic [7:0]  entry_id_in,
    input  logic [31:0] next_eip_in,
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

    // --- EIP staging ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,
    output logic        pc_target_en,
    output logic [31:0] pc_target_val,

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
    logic [31:0] next_eip_r;        // M_NEXT_EIP latched at dispatch
    logic        is_jmp_r;          // instruction is a JMP (has_target from decoder)

    logic        dispatch_rom_pending;
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;
    logic        execute_fetch_pending;

    logic        ctrl_transfer_pending;
    logic        squash_r;

    // EXT word handling
    logic        ext_pending_r;     // next ROM word is the service ID extension
    logic [7:0]  svc_id_r;         // latched service ID for SVCW

    // SR register (2-bit service result)
    logic [1:0]  sr_r;

    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;
    assign dbg_state      = state;
    assign dbg_upc        = upc_r;
    assign dbg_entry_id   = entry_id_r;
    assign squash         = squash_r;
    assign meta_next_eip  = next_eip_r;

    // Microinstruction field decode
    logic [3:0]  uop_class;
    logic [5:0]  uop_target;
    logic [3:0]  uop_cond;
    logic [9:0]  uop_imm10;

    assign uop_class  = uinst[31:28];
    assign uop_target = uinst[27:22];
    assign uop_cond   = uinst[21:18];
    assign uop_imm10  = uinst[9:0];

    // Branch condition evaluation against SR
    logic br_taken;
    always_comb begin
        case (uop_cond)
            C_ALWAYS: br_taken = 1'b1;
            C_OK:     br_taken = (sr_r == SR_OK);
            C_FAULT:  br_taken = (sr_r == SR_FAULT);
            default:  br_taken = 1'b0;
        endcase
    end

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
            squash_r              <= 1'b0;
            ext_pending_r         <= 1'b0;
            svc_id_r              <= 8'h0;
            sr_r                  <= SR_OK;
        end else begin
            state <= state_next;
            upc_r <= upc_next;
            squash_r <= 1'b0;

            case (state)
                MSEQ_FETCH_DECODE: begin
                    if (decode_done && !dispatch_rom_pending && !dispatch_pending
                        && !ctrl_transfer_pending) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        is_jmp_r             <= (entry_id_in == ENTRY_JMP_NEAR);
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
                        // Do NOT squash here. For JMP, displacement bytes are
                        // consumed by fetch_engine service calls in microcode.
                        // The queue must remain live until those service calls
                        // complete. The flush happens at commit via CM_FLUSHQ.
                        if (is_jmp_r) begin
                            ctrl_transfer_pending <= 1'b1;
                        end
                    end

                    if (ctrl_transfer_pending && endi_done)
                        ctrl_transfer_pending <= 1'b0;
                end

                MSEQ_EXECUTE: begin
                    if (execute_fetch_pending)
                        execute_fetch_pending <= 1'b0;
                    else begin
                        case (uop_class)
                            UOP_EXT: begin
                                // Next ROM word carries the service ID
                                ext_pending_r <= 1'b1;
                            end
                            UOP_SVCW: begin
                                if (ext_pending_r) begin
                                    // Service ID is in the current word's low 8 bits
                                    svc_id_r      <= uinst[7:0];
                                    ext_pending_r <= 1'b0;
                                end else begin
                                    svc_id_r <= {2'b00, uop_target};
                                end
                            end
                            default: ;
                        endcase
                    end

                    if (ctrl_transfer_pending && endi_done)
                        ctrl_transfer_pending <= 1'b0;
                end

                MSEQ_WAIT_SERVICE: begin
                    if (svc_done_in && (svc_sr_in != SR_WAIT)) begin
                        // Service completed with OK or FAULT — latch result
                        sr_r <= svc_sr_in;
                    end
                    // SR_WAIT: service is not done yet — stay in WAIT_SERVICE,
                    // do not latch sr_r, do not advance uPC.
                    if (ctrl_transfer_pending && endi_done)
                        ctrl_transfer_pending <= 1'b0;
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
        svc_id_out      = 8'h0;
        svc_req_out     = 1'b0;

        case (state)
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;
                end
            end

            MSEQ_EXECUTE: begin
                if (execute_fetch_pending) begin
                    // ROM fetch stall — do nothing
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
                            // Advance to extension word; sequential block latches ext_pending
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_SVCW: begin
                            // Issue service request; transition to WAIT_SERVICE
                            if (ext_pending_r)
                                svc_id_out = uinst[7:0];
                            else
                                svc_id_out = {2'b00, uop_target};
                            svc_req_out = 1'b1;
                            state_next  = MSEQ_WAIT_SERVICE;
                            // upc stays — advance after done
                        end

                        UOP_RAISE: begin
                            raise_req  = 1'b1;
                            raise_fc   = uop_target[3:0];
                            raise_fe   = 32'h0;
                            upc_next   = upc_r + 12'h1;
                            state_next = MSEQ_FAULT_HOLD;
                        end

                        UOP_ENDI: begin
                            // At ENDI for JMP: stage T2 as target
                            if (is_jmp_r) begin
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
                    // Service truly complete (OK or FAULT) — advance
                    upc_next   = upc_r + 12'h1;
                    state_next = MSEQ_EXECUTE;
                end
                // SR_WAIT: service still pending — hold uPC and state
            end

            MSEQ_FAULT_HOLD: begin
                state_next = MSEQ_EXECUTE;
                upc_next   = upc_r;
            end

            default: state_next = MSEQ_FETCH_DECODE;
        endcase
    end

endmodule
