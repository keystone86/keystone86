// Keystone86 / Aegis
// rtl/core/decoder.sv
// Rung 2: JMP SHORT (EB) and JMP NEAR (E9) multi-byte decode
//
// Ownership (Appendix B):
//   This module owns: opcode byte consumption from prefetch queue,
//   entry ID selection, decode_done assertion, M_NEXT_EIP production,
//   instruction-local target_eip computation.
//   This module must NOT: implement instruction semantics, read
//   architectural registers, access memory, produce instruction results,
//   own control-transfer policy, own redirect policy.
//
// Rung 2 changes from Rung 1:
//   - Two new states: DEC_DISP8 and DEC_DISP32
//   - Opcode EB (JMP SHORT): gather one disp8 byte with POSITION-PROVEN
//     capture (byte EIP must equal opcode_eip_latch + 1). Compute:
//       target_eip = opcode_eip + 2 + sign_extend(disp8)
//   - Opcode E9 (JMP NEAR rel16/rel32): gather 2 displacement bytes
//     with position-proven capture. Real-mode 16-bit default:
//       target_eip = opcode_eip + 3 + sign_extend(disp16)
//   - squash input: when asserted, decoder resets to DEC_IDLE and
//     clears all in-formation state (stale-work kill, Contract 3).
//   - New decode payload fields: target_eip[31:0], has_target
//
// Position-proven byte capture rule (Contract 1):
//   Decoder may only latch a non-opcode byte when:
//     (1) q_valid == 1
//     (2) q_fetch_eip == expected_byte_eip
//     (3) squash == 0
//   This eliminates the timing-assumption bug where "one cycle later"
//   was incorrectly assumed to mean "correct next byte."
//
// State machine:
//   DEC_IDLE    : wait for q_valid; latch opcode byte + EIP
//   DEC_CONSUME : consume opcode byte (single-byte instructions)
//   DEC_DISP8   : consume opcode, then position-proven capture of disp8
//   DEC_DISP32  : consume opcode, then position-proven capture of disp16
//   DEC_DONE    : hold stable payload until dec_ack
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
    output logic [31:0] target_eip,     // Rung 2: JMP target EIP
    output logic        has_target,     // Rung 2: target_eip is valid
    input  logic        dec_ack,

    // --- Fetch EIP tracking ---
    input  logic [31:0] q_fetch_eip
);

    typedef enum logic [2:0] {
        DEC_IDLE    = 3'b000,
        DEC_CONSUME = 3'b001,
        DEC_DISP8   = 3'b010,
        DEC_DISP32  = 3'b011,
        DEC_DONE    = 3'b100
    } dec_state_t;

    dec_state_t state, state_next;

    logic [31:0] opcode_eip_latch;
    logic [7:0]  opcode_byte_latch;

    // Displacement accumulation
    logic [7:0]  disp_lo;
    logic [7:0]  disp_hi;
    logic        disp_lo_valid;
    logic        disp_hi_valid;
    logic        is_jmp_short;      // EB path: need 1 disp byte
    logic        is_jmp_near;       // E9 path: need 2 disp bytes (real-mode)
    logic        opcode_consumed;   // opcode q_consume has been issued

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= DEC_IDLE;
            opcode_eip_latch <= 32'h0;
            opcode_byte_latch<= 8'h0;
            disp_lo          <= 8'h0;
            disp_hi          <= 8'h0;
            disp_lo_valid    <= 1'b0;
            disp_hi_valid    <= 1'b0;
            is_jmp_short     <= 1'b0;
            is_jmp_near      <= 1'b0;
            opcode_consumed  <= 1'b0;
        end else if (squash) begin
            // Contract 3: stale-work kill on squash from microsequencer
            state            <= DEC_IDLE;
            opcode_eip_latch <= 32'h0;
            opcode_byte_latch<= 8'h0;
            disp_lo          <= 8'h0;
            disp_hi          <= 8'h0;
            disp_lo_valid    <= 1'b0;
            disp_hi_valid    <= 1'b0;
            is_jmp_short     <= 1'b0;
            is_jmp_near      <= 1'b0;
            opcode_consumed  <= 1'b0;
        end else begin
            state <= state_next;

            case (state)
                DEC_IDLE: begin
                    if (q_valid) begin
                        opcode_eip_latch  <= q_fetch_eip;
                        opcode_byte_latch <= q_data;
                        is_jmp_short      <= (q_data == 8'hEB);
                        is_jmp_near       <= (q_data == 8'hE9);
                        disp_lo_valid     <= 1'b0;
                        disp_hi_valid     <= 1'b0;
                        opcode_consumed   <= 1'b0;
                    end
                end

                DEC_CONSUME: begin
                    // Single-byte path: opcode consumed combinationally
                    opcode_consumed <= 1'b1;
                end

                // JMP SHORT: consume opcode first cycle, then wait for
                // position-proven disp byte at opcode_eip+1
                DEC_DISP8: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else begin
                        // Position-proven capture: only latch when EIP matches
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            disp_lo       <= q_data;
                            disp_lo_valid <= 1'b1;
                        end
                    end
                end

                // JMP NEAR (real-mode disp16): consume opcode first cycle,
                // then wait for byte at +1 (disp_lo), then byte at +2 (disp_hi)
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
                    else if (q_data == 8'hE9)
                        state_next = DEC_DISP32;
                    else
                        state_next = DEC_CONSUME;
                end
            end

            DEC_CONSUME:
                state_next = DEC_DONE;

            DEC_DISP8: begin
                // Advance to DEC_DONE once opcode consumed and disp_lo captured
                if (opcode_consumed && q_valid &&
                    (q_fetch_eip == opcode_eip_latch + 32'h1) && !disp_lo_valid)
                    state_next = DEC_DONE;
                else if (disp_lo_valid)
                    state_next = DEC_DONE;
            end

            DEC_DISP32: begin
                // Advance to DEC_DONE once opcode, disp_lo, disp_hi all captured
                if (opcode_consumed && disp_lo_valid && !disp_hi_valid &&
                    q_valid && (q_fetch_eip == opcode_eip_latch + 32'h2))
                    state_next = DEC_DONE;
                else if (disp_hi_valid)
                    state_next = DEC_DONE;
            end

            DEC_DONE:
                if (dec_ack) state_next = DEC_IDLE;

            default:
                state_next = DEC_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Opcode classification
    // Uses ENTRY_* constants from keystone86_pkg (authoritative source).
    // ----------------------------------------------------------------
    function automatic logic [7:0] classify_opcode(input logic [7:0] op);
        case (op)
            8'h90:                          return ENTRY_NOP_XCHG_AX;
            8'hEB, 8'hE9:                   return ENTRY_JMP_NEAR;
            8'hF0, 8'hF2, 8'hF3,
            8'h2E, 8'h36, 8'h3E, 8'h26,
            8'h64, 8'h65,
            8'h66, 8'h67:                   return ENTRY_PREFIX_ONLY;
            default:                        return ENTRY_NULL;
        endcase
    endfunction

    // ----------------------------------------------------------------
    // Target EIP computation (combinational, instruction-local only)
    // JMP SHORT: target = opcode_eip + 2 + sign_extend(disp8)
    // JMP NEAR:  target = opcode_eip + 3 + sign_extend(disp16)
    //
    // Sign-extend wires declared outside always_comb to avoid iverilog
    // "constant selects in always_* not supported" on replication operators.
    // ----------------------------------------------------------------
    logic [31:0] disp8_sext;   // sign-extended disp8
    logic [31:0] disp16_sext;  // sign-extended disp16
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
        end else if (is_jmp_near && disp_lo_valid && disp_hi_valid) begin
            computed_target_eip = opcode_eip_latch + 32'h3 + disp16_sext;
            computed_has_target = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Output logic
    // ----------------------------------------------------------------
    always_comb begin
        q_consume   = 1'b0;
        decode_done = 1'b0;
        entry_id    = ENTRY_NULL;
        next_eip    = opcode_eip_latch + 32'h1;
        target_eip  = computed_target_eip;
        has_target  = 1'b0;

        case (state)
            DEC_CONSUME: begin
                q_consume = 1'b1;
            end

            DEC_DISP8: begin
                if (!opcode_consumed) begin
                    // First cycle: consume opcode byte
                    q_consume = 1'b1;
                end else if (!disp_lo_valid &&
                             q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    // Displacement byte is at the right position: consume it
                    q_consume = 1'b1;
                end
            end

            DEC_DISP32: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (disp_lo_valid && !disp_hi_valid &&
                             q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h2)) begin
                    // Second displacement byte at right position: consume
                    q_consume = 1'b1;
                end else if (!disp_lo_valid &&
                             q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    // First displacement byte at right position: consume
                    q_consume = 1'b1;
                end
            end

            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = classify_opcode(opcode_byte_latch);
                if (is_jmp_short)
                    next_eip = opcode_eip_latch + 32'h2;
                else if (is_jmp_near)
                    next_eip = opcode_eip_latch + 32'h3;
                else
                    next_eip = opcode_eip_latch + 32'h1;
                target_eip  = computed_target_eip;
                has_target  = computed_has_target;
            end

            default: ;
        endcase
    end

    // synthesis translate_off
    logic [7:0] dbg_last_opcode_byte;
    always_ff @(posedge clk) begin
        if (state == DEC_CONSUME)
            dbg_last_opcode_byte <= opcode_byte_latch;
    end
    // synthesis translate_on

endmodule
