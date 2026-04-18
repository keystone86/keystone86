// Keystone86 / Aegis
// rtl/core/decoder.sv
// Rung 3: CALL (E8, FF /2) and RET (C3, C2) decode added
// (includes all Rung 2 JMP behavior)
//
// Ownership (Appendix B):
//   This module owns: opcode byte consumption from prefetch queue,
//   entry ID selection, decode_done assertion, M_NEXT_EIP production,
//   instruction-local target_eip computation for direct calls.
//   This module must NOT: implement instruction semantics, read
//   architectural registers, access memory, produce instruction results,
//   own control-transfer policy, own redirect policy.
//
// Rung 3 additions over Rung 2:
//
//   E8 — CALL near relative (direct):
//     Opcode (1) + disp16 (2) = 3 bytes total.
//     target_eip = opcode_eip + 3 + sign_extend(disp16)
//     next_eip   = opcode_eip + 3  (this IS the return address CALL pushes)
//     has_target = 1,  is_call = 1
//
//   FF /2 — CALL near indirect:
//     Opcode (1) + ModRM (1) = 2 bytes (phase-1: register-form ModRM only).
//     target_eip NOT computed here (comes from register file at commit).
//     has_target = 0,  is_call = 1
//     next_eip   = opcode_eip + 2  (return address)
//     modrm_byte carries the ModRM byte for commit staging.
//
//   C3 — RET near (no immediate):
//     Single byte. is_ret=1, has_ret_imm=0
//
//   C2 — RET near + imm16 stack adjust:
//     Opcode (1) + imm16 (2) = 3 bytes. is_ret=1, has_ret_imm=1, ret_imm=imm16
//
// State machine additions (over Rung 2):
//   DEC_MODRM : consume opcode, then position-proven capture of ModRM byte
//   DEC_DISP32 is reused for E8 disp16 and C2 imm16 (both are 2-byte gathers)
//
// Position-proven byte capture rule (unchanged from Rung 2):
//   Decoder may only latch a non-opcode byte when:
//     (1) q_valid == 1
//     (2) q_fetch_eip == expected_byte_eip
//     (3) squash == 0
//
// Shared constants: ENTRY_* from keystone86_pkg (authoritative source).

import keystone86_pkg::*;

module decoder (
    input  logic        clk,
    input  logic        reset_n,

    // --- Squash (from microsequencer on control-transfer acceptance) ---
    input  logic        squash,

    // --- Mode context (from commit_engine) ---
    input  logic        mode_prot,
    input  logic        cs_d_bit,

    // --- Prefetch queue interface ---
    input  logic [7:0]  q_data,
    input  logic        q_valid,
    output logic        q_consume,

    // --- Microsequencer handshake ---
    output logic        decode_done,
    output logic [7:0]  entry_id,
    output logic [31:0] next_eip,
    output logic [31:0] target_eip,     // JMP/CALL-direct target EIP
    output logic        has_target,     // target_eip is valid (direct only)
    output logic        is_call,        // Rung 3: CALL instruction
    output logic        is_ret,         // Rung 3: RET instruction
    output logic        has_ret_imm,    // Rung 3: RET imm16 form
    output logic [15:0] ret_imm,        // Rung 3: RET immediate value
    output logic [7:0]  modrm_byte,     // Rung 3: ModRM for FF/2 indirect CALL
    input  logic        dec_ack,

    // --- Fetch EIP tracking ---
    input  logic [31:0] q_fetch_eip
);

    typedef enum logic [3:0] {
        DEC_IDLE    = 4'h0,
        DEC_CONSUME = 4'h1,
        DEC_DISP8   = 4'h2,
        DEC_DISP32  = 4'h3,   // 2-byte gather: E9 disp16 / E8 disp16 / C2 imm16
        DEC_MODRM   = 4'h4,   // Rung 3: FF /2 ModRM byte
        DEC_DONE    = 4'h5
    } dec_state_t;

    dec_state_t state, state_next;

    logic [31:0] opcode_eip_latch;
    logic [7:0]  opcode_byte_latch;

    // Byte accumulation
    logic [7:0]  disp_lo;
    logic [7:0]  disp_hi;
    logic        disp_lo_valid;
    logic        disp_hi_valid;

    // Instruction type flags (latched at DEC_IDLE)
    logic        is_jmp_short;
    logic        is_jmp_near;
    logic        is_call_direct;    // E8
    logic        is_call_indirect;  // FF /2
    logic        is_ret_near;       // C3
    logic        is_ret_imm16;      // C2

    logic        opcode_consumed;
    logic [7:0]  modrm_latch;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= DEC_IDLE;
            opcode_eip_latch  <= 32'h0;
            opcode_byte_latch <= 8'h0;
            disp_lo           <= 8'h0;
            disp_hi           <= 8'h0;
            disp_lo_valid     <= 1'b0;
            disp_hi_valid     <= 1'b0;
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_indirect  <= 1'b0;
            is_ret_near       <= 1'b0;
            is_ret_imm16      <= 1'b0;
            opcode_consumed   <= 1'b0;
            modrm_latch       <= 8'h0;
        end else if (squash) begin
            // Contract 3: stale-work kill on squash from microsequencer
            state             <= DEC_IDLE;
            opcode_eip_latch  <= 32'h0;
            opcode_byte_latch <= 8'h0;
            disp_lo           <= 8'h0;
            disp_hi           <= 8'h0;
            disp_lo_valid     <= 1'b0;
            disp_hi_valid     <= 1'b0;
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_indirect  <= 1'b0;
            is_ret_near       <= 1'b0;
            is_ret_imm16      <= 1'b0;
            opcode_consumed   <= 1'b0;
            modrm_latch       <= 8'h0;
        end else begin
            state <= state_next;

            case (state)
                DEC_IDLE: begin
                    if (q_valid) begin
                        opcode_eip_latch  <= q_fetch_eip;
                        opcode_byte_latch <= q_data;
                        is_jmp_short      <= (q_data == 8'hEB);
                        is_jmp_near       <= (q_data == 8'hE9);
                        is_call_direct    <= (q_data == 8'hE8);
                        is_call_indirect  <= (q_data == 8'hFF);
                        is_ret_near       <= (q_data == 8'hC3);
                        is_ret_imm16      <= (q_data == 8'hC2);
                        disp_lo_valid     <= 1'b0;
                        disp_hi_valid     <= 1'b0;
                        opcode_consumed   <= 1'b0;
                        modrm_latch       <= 8'h0;
                    end
                end

                DEC_CONSUME: begin
                    opcode_consumed <= 1'b1;
                end

                // JMP SHORT: consume opcode then disp8 at opcode_eip+1
                DEC_DISP8: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            disp_lo       <= q_data;
                            disp_lo_valid <= 1'b1;
                        end
                    end
                end

                // 2-byte gather: byte1 at +1, byte2 at +2
                // Used for: E9 disp16, E8 disp16, C2 imm16
                DEC_DISP32: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else if (!disp_lo_valid) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            disp_lo       <= q_data;
                            disp_lo_valid <= 1'b1;
                        end
                    end else if (!disp_hi_valid) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h2)) begin
                            disp_hi       <= q_data;
                            disp_hi_valid <= 1'b1;
                        end
                    end
                end

                // FF /2 — ModRM byte at opcode_eip+1
                DEC_MODRM: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            modrm_latch   <= q_data;
                            disp_lo_valid <= 1'b1;  // reuse as "second byte captured"
                        end
                    end
                end

                DEC_DONE: begin
                    // Hold stable until dec_ack
                end

                default: ;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Next-state logic
    // ----------------------------------------------------------------
    always_comb begin
        state_next = state;
        case (state)
            DEC_IDLE: begin
                if (q_valid) begin
                    if (q_data == 8'hEB)
                        state_next = DEC_DISP8;
                    else if (q_data == 8'hE9 || q_data == 8'hE8 || q_data == 8'hC2)
                        state_next = DEC_DISP32;
                    else if (q_data == 8'hFF)
                        state_next = DEC_MODRM;
                    else
                        state_next = DEC_CONSUME;
                end
            end

            DEC_CONSUME:
                state_next = DEC_DONE;

            DEC_DISP8: begin
                if (opcode_consumed && q_valid &&
                    (q_fetch_eip == opcode_eip_latch + 32'h1) && !disp_lo_valid)
                    state_next = DEC_DONE;
                else if (disp_lo_valid)
                    state_next = DEC_DONE;
            end

            DEC_DISP32: begin
                if (opcode_consumed && disp_lo_valid && !disp_hi_valid &&
                    q_valid && (q_fetch_eip == opcode_eip_latch + 32'h2))
                    state_next = DEC_DONE;
                else if (disp_hi_valid)
                    state_next = DEC_DONE;
            end

            DEC_MODRM: begin
                if (opcode_consumed && q_valid &&
                    (q_fetch_eip == opcode_eip_latch + 32'h1) && !disp_lo_valid)
                    state_next = DEC_DONE;
                else if (disp_lo_valid)
                    state_next = DEC_DONE;
            end

            DEC_DONE:
                if (dec_ack) state_next = DEC_IDLE;

            default:
                state_next = DEC_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // FF /2 check: ModRM reg field bits [5:3] == 3'b010
    // Only valid when is_call_indirect and DEC_DONE state.
    // ----------------------------------------------------------------
    logic ff_is_call_near;
    assign ff_is_call_near = (modrm_latch[5:3] == 3'b010);

    // ----------------------------------------------------------------
    // Opcode classification
    // Uses ENTRY_* constants from keystone86_pkg (authoritative source).
    // FF classification depends on ModRM: only /2 is ENTRY_CALL_NEAR.
    // ----------------------------------------------------------------
    function automatic logic [7:0] classify_opcode(
        input logic [7:0] op,
        input logic       ff2
    );
        case (op)
            8'h90:                          return ENTRY_NOP_XCHG_AX;
            8'hEB, 8'hE9:                   return ENTRY_JMP_NEAR;
            8'hE8:                          return ENTRY_CALL_NEAR;
            8'hFF:                          return ff2 ? ENTRY_CALL_NEAR : ENTRY_NULL;
            8'hC3, 8'hC2:                   return ENTRY_RET_NEAR;
            8'hF0, 8'hF2, 8'hF3,
            8'h2E, 8'h36, 8'h3E, 8'h26,
            8'h64, 8'h65,
            8'h66, 8'h67:                   return ENTRY_PREFIX_ONLY;
            default:                        return ENTRY_NULL;
        endcase
    endfunction

    // ----------------------------------------------------------------
    // Target EIP computation (combinational, instruction-local only)
    //
    // JMP SHORT:    target = opcode_eip + 2 + sign_extend(disp8)
    // JMP NEAR:     target = opcode_eip + 3 + sign_extend(disp16)
    // CALL direct:  target = opcode_eip + 3 + sign_extend(disp16)
    // CALL indirect: NOT computed here (register provides target)
    // RET:          NOT computed here (stack pop provides target)
    //
    // Sign-extend wires declared outside always_comb to avoid iverilog
    // "constant selects in always_* not supported" on replication operators.
    // ----------------------------------------------------------------
    logic [31:0] disp8_sext;
    logic [31:0] disp16_sext;
    logic [31:0] computed_target_eip;
    logic        computed_has_target;

    assign disp8_sext  = {{24{disp_lo[7]}}, disp_lo};
    assign disp16_sext = {{16{disp_hi[7]}}, disp_hi, disp_lo};

    always_comb begin
        computed_target_eip = 32'h0;
        computed_has_target = 1'b0;
        if (is_jmp_short && disp_lo_valid) begin
            computed_target_eip = opcode_eip_latch + 32'h2 + disp8_sext;
            computed_has_target = 1'b1;
        end else if ((is_jmp_near || is_call_direct) && disp_lo_valid && disp_hi_valid) begin
            computed_target_eip = opcode_eip_latch + 32'h3 + disp16_sext;
            computed_has_target = 1'b1;
        end
        // is_call_indirect: has_target=0; commit_engine reads register file
        // is_ret_near/is_ret_imm16: target comes from stack pop
    end

    // ----------------------------------------------------------------
    // Output logic
    // ----------------------------------------------------------------
    always_comb begin
        q_consume    = 1'b0;
        decode_done  = 1'b0;
        entry_id     = ENTRY_NULL;
        next_eip     = opcode_eip_latch + 32'h1;
        target_eip   = computed_target_eip;
        has_target   = 1'b0;
        is_call      = 1'b0;
        is_ret       = 1'b0;
        has_ret_imm  = 1'b0;
        ret_imm      = 16'h0;
        modrm_byte   = modrm_latch;

        case (state)
            DEC_CONSUME: begin
                q_consume = 1'b1;
            end

            DEC_DISP8: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (!disp_lo_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    q_consume = 1'b1;
                end
            end

            DEC_DISP32: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (disp_lo_valid && !disp_hi_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h2)) begin
                    q_consume = 1'b1;
                end else if (!disp_lo_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    q_consume = 1'b1;
                end
            end

            DEC_MODRM: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (!disp_lo_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    q_consume = 1'b1;
                end
            end

            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = classify_opcode(opcode_byte_latch, ff_is_call_near);

                if (is_jmp_short)
                    next_eip = opcode_eip_latch + 32'h2;
                else if (is_jmp_near || is_call_direct || is_ret_imm16)
                    next_eip = opcode_eip_latch + 32'h3;
                else if (is_call_indirect)
                    next_eip = opcode_eip_latch + 32'h2;
                else
                    next_eip = opcode_eip_latch + 32'h1;

                target_eip  = computed_target_eip;
                has_target  = computed_has_target;
                // FF indirect CALL: only valid if ModRM reg == /2
                is_call     = is_call_direct || (is_call_indirect && ff_is_call_near);
                is_ret      = is_ret_near || is_ret_imm16;
                has_ret_imm = is_ret_imm16;
                ret_imm     = {disp_hi, disp_lo};
                modrm_byte  = modrm_latch;
            end

            default: ;
        endcase
    end

endmodule
