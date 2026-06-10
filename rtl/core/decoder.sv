// Keystone86 / Aegis
// rtl/core/decoder.sv
//
// Decoder role through bounded Rung 6 Pass 6H-5 plus the bounded Rung 7
// ADD/SUB/CMP reg32 register-form slices:
//   - Classify in-scope control-transfer forms and produce decode-owned
//     metadata only.
//   - Consume every byte that belongs to the instruction before decode_done,
//     including E8 disp16 and C2 imm16, so M_NEXT_EIP is stable at handoff.
//   - For short Jcc, emit only ENTRY_JCC and M_COND_CODE. Condition
//     evaluation and taken-target computation remain service/microcode owned.
//   - For CD imm8, consume only the opcode and report M_NEXT_EIP as opcode+2;
//     FETCH_IMM8 remains the microcode-called service that consumes the vector.
//   - For B0-B7 MOV r8, imm8, B8-BF MOV r32, imm32, and the bounded
//     66+B8-BF MOV r16, imm16 slice, consume only opcode/prefix bytes and
//     report M_NEXT_EIP after the immediate; FETCH_IMM* remains the
//     microcode-called service that consumes the immediate payload.
//   - For 88/89/8A/8B MOV register-register, consume opcode+ModRM only when
//     the instruction is handed to ENTRY_MOV. The 0x66 latch is intentionally
//     limited to 89/8B ModRM.mod=11 for r16 register-register MOV, plus
//     66+8B memory-source and 66+89 memory-destination only for the authorized
//     Rung 6 memory forms documented below. Other prefixed forms remain
//     unsupported.
//   - For the bounded Pass 6A-1 memory-source slice, accept only 8A/8B and
//     66+8B with ModRM.mod=00 and r/m=101, consume the disp32 absolute address,
//     and report M_NEXT_EIP after that displacement. Pass 6E-1 additionally
//     accepts default-32 ModRM.mod=00 base-only forms with r/m!=100/101 and no
//     displacement. Pass 6E-2 additionally accepts default-32 ModRM.mod=01
//     non-SIB forms with one signed disp8. Pass 6E-3 additionally accepts
//     default-32 ModRM.mod=10 non-SIB forms with four signed disp32 bytes.
//     Pass 6F-1 additionally accepts base-only SIB with SIB.index=100.
//     Pass 6F-2 additionally accepts only the ModRM.mod=00, ModRM.r/m=100,
//     SIB.index=100, SIB.base=101 no-base disp32 special case, where
//     EA=disp32. Pass 6G-1 additionally accepts base-present indexed SIB
//     forms. Pass 6G-2 additionally accepts no-base indexed SIB disp32.
//     Pass 6H-1 additionally accepts 0x67 address-size override only for
//     16-bit direct disp16 MOV forms with ModRM.mod=00 and ModRM.r/m=110.
//     Pass 6H-2 additionally accepts only 0x67 16-bit no-displacement
//     non-BP register-based forms with ModRM.mod=00 and
//     r/m=000/001/100/101/111. Pass 6H-3 additionally accepts only
//     r/m=010 [BP+SI] and r/m=011 [BP+DI]. Pass 6H-4 additionally accepts
//     only 0x67 ModRM.mod=01 signed disp8 16-bit addressing forms. Pass
//     6H-5 additionally accepts only 0x67 ModRM.mod=10 disp16 16-bit
//     addressing forms. Segment-base addition, default-SS linearization,
//     protected/page behavior, and Rung 7 behavior outside the bounded
//     ADD/SUB/CMP reg32 ModRM.mod=11 01/03/29/39/3B slices remain
//     unsupported.
//   - For the bounded Pass 6B-1 memory-destination slice, accept only 88/89
//     and 66+89 with ModRM.mod=00 and r/m=101, consume the disp32 absolute
//     address, and report M_NEXT_EIP after that displacement. Pass 6E-1
//     additionally accepts default-32 ModRM.mod=00 base-only forms with
//     r/m!=100/101 and no displacement. Pass 6E-2 additionally accepts
//     default-32 ModRM.mod=01 non-SIB forms with one signed disp8. Pass 6E-3
//     additionally accepts default-32 ModRM.mod=10 non-SIB forms with four
//     signed disp32 bytes. Pass 6F-1 additionally accepts the same bounded
//     base-only SIB subset. Pass 6F-2 additionally accepts only the mod=00
//     SIB.index=100 SIB.base=101 no-base disp32 special case. Pass 6G-1
//     additionally accepts base-present indexed SIB. Pass 6G-2 additionally
//     accepts no-base indexed SIB disp32. Pass 6H-1 adds only 0x67 direct
//     disp16 memory-destination forms. Pass 6H-2 adds only the authorized
//     0x67 no-displacement non-BP memory-destination forms. Pass 6H-3 adds
//     only the authorized BP-based no-displacement memory-destination forms.
//     Pass 6H-4 adds only 0x67 ModRM.mod=01 signed disp8 forms. Pass 6H-5
//     adds only 0x67 ModRM.mod=10 disp16 forms.
//   - For the bounded Pass 6C-1 immediate-to-memory slice, accept only C6/C7
//     /0 with ModRM.mod=00 and r/m=101, consume the disp32 absolute address,
//     and report M_NEXT_EIP after the immediate. Pass 6E-1 additionally
//     accepts /0 default-32 ModRM.mod=00 base-only forms with r/m!=100/101 and
//     no displacement. Pass 6E-2 additionally accepts /0 default-32
//     ModRM.mod=01 non-SIB forms with one signed disp8, or Pass 6E-3
//     default-32 ModRM.mod=10 non-SIB forms with four signed disp32 bytes.
//     Pass 6F-1 additionally accepts the same bounded base-only SIB subset.
//     Pass 6F-2 additionally accepts only the mod=00 SIB.index=100
//     SIB.base=101 no-base disp32 special case. Pass 6G-1 additionally
//     accepts base-present indexed SIB. Pass 6G-2 additionally accepts
//     no-base indexed SIB disp32. Pass 6H-1 adds only 0x67 direct disp16
//     immediate-to-memory forms. Pass 6H-2 adds only the authorized 0x67
//     no-displacement non-BP immediate-to-memory forms. Pass 6H-3 adds only
//     the authorized BP-based no-displacement immediate-to-memory forms.
//     Pass 6H-4 adds only 0x67 ModRM.mod=01 signed disp8 forms. Pass 6H-5
//     adds only 0x67 ModRM.mod=10 disp16 forms.
//     For Pass 6D-1, also accept C6/C7 /0 with ModRM.mod=11 as
//     register-destination MOV and report M_NEXT_EIP after the immediate.
//     FETCH_IMM* remains the microcode-called service that consumes the
//     immediate payload.
//   - Leave target computation, condition evaluation, interrupt policy, and
//     stack effects to services/microcode.
//   - Hold decode results stable until dec_ack or committed-boundary squash.

import keystone86_pkg::*;

module decoder (
    input  logic        clk,
    input  logic        reset_n,

    // --- Squash (from microsequencer at committed redirect cleanup) ---
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
    output logic [31:0] target_eip,     // retained compatibility output; not used for Rung 3 target policy
    output logic        has_target,
    output logic        is_call,
    output logic        is_call_indirect,
    output logic        is_ret,
    output logic        has_ret_imm,
    output logic [15:0] ret_imm,
    output logic [7:0]  modrm_byte,
    output logic [7:0]  sib_byte,
    output logic        modrm_present,
    output logic [3:0]  modrm_class,
    output logic        disp_valid,
    output logic [31:0] disp_value,
    output logic        payload16_valid,
    output logic        payload16_signed,
    output logic [15:0] payload16,
    output logic [7:0]  opcode_class,
    output logic [1:0]  opsz,
    output logic        addrsz,
    output logic [2:0]  imm_class,
    output logic [2:0]  reg_dst,
    output logic [2:0]  reg_src,
    output logic [2:0]  reg_rm,
    output logic [3:0]  alu_op,
    output logic        is_cmp,
    output logic [3:0]  cond_code,
    input  logic        dec_ack,

    // --- Fetch EIP tracking ---
    input  logic [31:0] q_fetch_eip
);

    typedef enum logic [3:0] {
        DEC_IDLE    = 4'h0,
        DEC_CONSUME = 4'h1,
        DEC_DISP16  = 4'h2,   // E8 disp16 and C2 imm16 payload acquisition
        DEC_MODRM   = 4'h3,   // used for FF forms
        DEC_SIB     = 4'h4,
        DEC_DISP    = 4'h5,
        DEC_DONE    = 4'h6,
        DEC_PREFIX66= 4'h7
    } dec_state_t;

    dec_state_t state, state_next;

    logic [31:0] opcode_eip_latch;
    logic [7:0]  opcode_byte_latch;

    logic [7:0]  aux_lo;
    logic [7:0]  aux_hi;
    logic        aux_lo_valid;
    logic        aux_hi_valid;
    logic [7:0]  sib_latch;
    logic [31:0] disp_latch;
    logic [2:0]  disp_idx;
    logic [2:0]  disp_total;

    logic        is_jmp_short;
    logic        is_jmp_near;
    logic        is_call_direct;
    logic        is_call_ff;
    logic        is_ret_near;
    logic        is_ret_imm16;
    logic        is_jcc_short;
    logic        is_int_imm8;
    logic        is_mov_r_imm8;
    logic        is_mov_r_imm32;
    logic        is_mov_modrm;
    logic        is_mov_rm_imm;
    logic        is_alu_rm_r;
    logic        is_alu_r_rm;
    logic        prefix66_active;
    logic        prefix67_active;
    logic [1:0]  prefix_count;

    logic        opcode_consumed;
    logic [7:0]  modrm_latch;
    logic        ff_is_call_near;

    assign ff_is_call_near = (modrm_latch[5:3] == 3'b010);

    localparam logic [7:0] OC_MOV_RM_R  = 8'h00; // Appendix A M_OPCODE_CLASS
    localparam logic [7:0] OC_MOV_R_RM  = 8'h01;
    localparam logic [7:0] OC_MOV_R_IMM = 8'h02;
    localparam logic [7:0] OC_MOV_RM_IMM = 8'h03;
    localparam logic [1:0] OPSZ_8       = 2'h0;
    localparam logic [1:0] OPSZ_16      = 2'h1;
    localparam logic [1:0] OPSZ_32      = 2'h2;
    localparam logic [2:0] IMM_NONE     = 3'h0;
    localparam logic [2:0] IMM_8        = 3'h1;
    localparam logic [2:0] IMM_16       = 3'h3;
    localparam logic [2:0] IMM_32       = 3'h4;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= DEC_IDLE;
            opcode_eip_latch  <= 32'h0;
            opcode_byte_latch <= 8'h0;
            aux_lo            <= 8'h0;
            aux_hi            <= 8'h0;
            aux_lo_valid      <= 1'b0;
            aux_hi_valid      <= 1'b0;
            sib_latch         <= 8'h0;
            disp_latch        <= 32'h0;
            disp_idx          <= 3'h0;
            disp_total        <= 3'h0;
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_ff        <= 1'b0;
            is_ret_near       <= 1'b0;
            is_ret_imm16      <= 1'b0;
            is_jcc_short      <= 1'b0;
            is_int_imm8       <= 1'b0;
            is_mov_r_imm8     <= 1'b0;
            is_mov_r_imm32    <= 1'b0;
            is_mov_modrm      <= 1'b0;
            is_mov_rm_imm     <= 1'b0;
            is_alu_rm_r        <= 1'b0;
            is_alu_r_rm        <= 1'b0;
            prefix66_active   <= 1'b0;
            prefix67_active   <= 1'b0;
            prefix_count      <= 2'h0;
            opcode_consumed   <= 1'b0;
            modrm_latch       <= 8'h0;
        end else if (squash) begin
            state             <= DEC_IDLE;
            opcode_eip_latch  <= 32'h0;
            opcode_byte_latch <= 8'h0;
            aux_lo            <= 8'h0;
            aux_hi            <= 8'h0;
            aux_lo_valid      <= 1'b0;
            aux_hi_valid      <= 1'b0;
            sib_latch         <= 8'h0;
            disp_latch        <= 32'h0;
            disp_idx          <= 3'h0;
            disp_total        <= 3'h0;
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_ff        <= 1'b0;
            is_ret_near       <= 1'b0;
            is_ret_imm16      <= 1'b0;
            is_jcc_short      <= 1'b0;
            is_int_imm8       <= 1'b0;
            is_mov_r_imm8     <= 1'b0;
            is_mov_r_imm32    <= 1'b0;
            is_mov_modrm      <= 1'b0;
            is_mov_rm_imm     <= 1'b0;
            is_alu_rm_r        <= 1'b0;
            is_alu_r_rm        <= 1'b0;
            prefix66_active   <= 1'b0;
            prefix67_active   <= 1'b0;
            prefix_count      <= 2'h0;
            opcode_consumed   <= 1'b0;
            modrm_latch       <= 8'h0;
        end else begin
            state <= state_next;

            case (state)
                DEC_IDLE: begin
                    if (q_valid) begin
                        opcode_eip_latch  <= q_fetch_eip;
                        opcode_byte_latch <= is_prefix_byte(q_data) ? 8'h00 : q_data;
                        is_jmp_short      <= !is_prefix_byte(q_data) && (q_data == 8'hEB);
                        is_jmp_near       <= !is_prefix_byte(q_data) && (q_data == 8'hE9);
                        is_call_direct    <= !is_prefix_byte(q_data) && (q_data == 8'hE8);
                        is_call_ff        <= !is_prefix_byte(q_data) && (q_data == 8'hFF);
                        is_ret_near       <= !is_prefix_byte(q_data) && (q_data == 8'hC3);
                        is_ret_imm16      <= !is_prefix_byte(q_data) && (q_data == 8'hC2);
                        is_jcc_short      <= !is_prefix_byte(q_data) && (q_data[7:4] == 4'h7);
                        is_int_imm8       <= !is_prefix_byte(q_data) && (q_data == 8'hCD);
                        is_mov_r_imm8     <= !is_prefix_byte(q_data) && (q_data[7:3] == 5'b10110);
                        is_mov_r_imm32    <= !is_prefix_byte(q_data) && (q_data[7:3] == 5'b10111);
                        is_mov_modrm      <= !is_prefix_byte(q_data) &&
                                             ((q_data == 8'h88) || (q_data == 8'h89) ||
                                              (q_data == 8'h8A) || (q_data == 8'h8B));
                        is_mov_rm_imm     <= !is_prefix_byte(q_data) &&
                                             ((q_data == 8'hC6) || (q_data == 8'hC7));
                        is_alu_rm_r        <= !is_prefix_byte(q_data) &&
                                             ((q_data == 8'h01) ||
                                              (q_data == 8'h29) ||
                                              (q_data == 8'h39));
                        is_alu_r_rm        <= !is_prefix_byte(q_data) &&
                                             ((q_data == 8'h03) || (q_data == 8'h3B));
                        prefix66_active   <= (q_data == 8'h66);
                        prefix67_active   <= (q_data == 8'h67);
                        prefix_count      <= is_prefix_byte(q_data) ? 2'd1 : 2'd0;
                        aux_lo_valid      <= 1'b0;
                        aux_hi_valid      <= 1'b0;
                        sib_latch         <= 8'h0;
                        disp_latch        <= 32'h0;
                        disp_idx          <= 3'h0;
                        disp_total        <= 3'h0;
                        opcode_consumed   <= 1'b0;
                        modrm_latch       <= 8'h0;
                    end
                end

                DEC_PREFIX66: begin
                    if (!opcode_consumed) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch))
                            opcode_consumed <= 1'b1;
                    end else if (q_valid &&
                                 (q_fetch_eip == opcode_eip_latch +
                                                 {30'h0, prefix_count})) begin
                        if (accept_second_prefix(q_data)) begin
                            prefix67_active <= 1'b1;
                            prefix_count    <= 2'd2;
                        end else if (prefix_opcode_candidate(q_data)) begin
                            // Prefix support remains bounded. Pass 6H-1 adds
                            // 0x67/66+67 direct disp16 MOV forms; Pass 6H-2
                            // also allows no-displacement non-BP addr16 forms,
                            // Pass 6H-3 adds [BP+SI]/[BP+DI], Pass 6H-4
                            // adds mod=01 signed disp8, and Pass 6H-5 adds
                            // only mod=10 disp16 addr16 forms.
                            // Unsupported prefix ordering remains a prefix-only
                            // boundary.
                            opcode_byte_latch <= q_data;
                            is_jmp_short      <= 1'b0;
                            is_jmp_near       <= 1'b0;
                            is_call_direct    <= 1'b0;
                            is_call_ff        <= 1'b0;
                            is_ret_near       <= 1'b0;
                            is_ret_imm16      <= 1'b0;
                            is_jcc_short      <= 1'b0;
                            is_int_imm8       <= 1'b0;
                            is_mov_r_imm8     <= !prefix67_active &&
                                                 (q_data[7:3] == 5'b10110);
                            is_mov_r_imm32    <= !prefix67_active &&
                                                 (q_data[7:3] == 5'b10111);
                            is_mov_modrm      <= (q_data == 8'h88) ||
                                                 (q_data == 8'h89) ||
                                                 (q_data == 8'h8A) ||
                                                 (q_data == 8'h8B);
                            is_mov_rm_imm     <= ((!prefix66_active &&
                                                   (q_data == 8'hC6)) ||
                                                  (q_data == 8'hC7));
                            is_alu_rm_r        <= 1'b0;
                            is_alu_r_rm        <= 1'b0;
                        end
                    end
                end

                DEC_CONSUME: begin
                    opcode_consumed <= 1'b1;
                end

                DEC_DISP16: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else if (!aux_lo_valid) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            aux_lo       <= q_data;
                            aux_lo_valid <= 1'b1;
                        end
                    end else if (!aux_hi_valid) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h2)) begin
                            aux_hi       <= q_data;
                            aux_hi_valid <= 1'b1;
                        end
                    end
                end

                DEC_MODRM: begin
                    if (!opcode_consumed) begin
                        opcode_consumed <= 1'b1;
                    end else if (!aux_lo_valid) begin
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + modrm_offset())) begin
                            modrm_latch  <= q_data;
                            aux_lo_valid <= 1'b1;
                            disp_total   <= disp_bytes_for_modrm(q_data, 8'h0, 1'b0);
                        end
                    end
                end

                DEC_SIB: begin
                    if (q_valid && (q_fetch_eip == opcode_eip_latch + sib_offset())) begin
                        sib_latch  <= q_data;
                        disp_total <= disp_bytes_for_modrm(modrm_latch, q_data, 1'b1);
                    end
                end

                DEC_DISP: begin
                    if ((disp_idx < disp_total) &&
                        q_valid && (q_fetch_eip == opcode_eip_latch + disp_start_offset())) begin
                        case (disp_idx)
                            3'd0: disp_latch[7:0]   <= q_data;
                            3'd1: disp_latch[15:8]  <= q_data;
                            3'd2: disp_latch[23:16] <= q_data;
                            3'd3: disp_latch[31:24] <= q_data;
                            default: ;
                        endcase
                        disp_idx <= disp_idx + 3'd1;
                    end
                end

                DEC_DONE: begin
                    // hold outputs stable until dec_ack
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
                    if (is_prefix_byte(q_data))
                        state_next = DEC_PREFIX66;
                    else if (q_data == 8'hE8 || q_data == 8'hC2)
                        state_next = DEC_DISP16;
                    else if (q_data == 8'hFF || q_data == 8'h01 ||
                             q_data == 8'h29 ||
                             q_data == 8'h03 || q_data == 8'h39 ||
                             q_data == 8'h3B || q_data == 8'h88 ||
                             q_data == 8'h89 || q_data == 8'h8A ||
                             q_data == 8'h8B || q_data == 8'hC6 ||
                             q_data == 8'hC7)
                        state_next = DEC_MODRM;
                    else
                        state_next = DEC_CONSUME;
                end
            end

            DEC_PREFIX66: begin
                if (opcode_consumed && q_valid &&
                    (q_fetch_eip == opcode_eip_latch + {30'h0, prefix_count})) begin
                    if (accept_second_prefix(q_data)) begin
                        state_next = DEC_PREFIX66;
                    end else if (prefix_opcode_candidate(q_data) &&
                                 (((q_data == 8'h88) || (q_data == 8'h89) ||
                                   (q_data == 8'h8A) || (q_data == 8'h8B) ||
                                   (q_data == 8'hC6) || (q_data == 8'hC7))))
                        state_next = DEC_MODRM;
                    else if (prefix_opcode_candidate(q_data))
                        state_next = DEC_DONE;
                    else
                        state_next = DEC_DONE;
                end
            end

            DEC_CONSUME: begin
                state_next = DEC_DONE;
            end

            DEC_DISP16: begin
                if (opcode_consumed && aux_lo_valid && aux_hi_valid)
                    state_next = DEC_DONE;
            end

            DEC_MODRM: begin
                if (opcode_consumed && aux_lo_valid) begin
                    if (is_call_ff && ff_is_call_near && modrm_needs_sib(modrm_latch))
                        state_next = DEC_SIB;
                    else if (is_call_ff && ff_is_call_near && (disp_total != 3'd0))
                        state_next = DEC_DISP;
                    else if ((is_mov_modrm || is_mov_rm_imm) &&
                             modrm_needs_sib_addr(modrm_latch))
                        state_next = DEC_SIB;
                    else if (is_mov_modrm &&
                             (mov_mem_src_form(opcode_byte_latch,
                                                modrm_latch,
                                                sib_latch,
                                                prefix66_active,
                                                prefix67_active) ||
                              mov_mem_dst_form(opcode_byte_latch,
                                                modrm_latch,
                                                sib_latch,
                                                prefix66_active,
                                                prefix67_active)) &&
                             (disp_total != 3'd0))
                        state_next = DEC_DISP;
                    else if (is_mov_rm_imm &&
                             mov_rm_imm_mem_form(opcode_byte_latch,
                                                 modrm_latch,
                                                 sib_latch,
                                                 prefix66_active,
                                                 prefix67_active) &&
                             (disp_total != 3'd0))
                        state_next = DEC_DISP;
                    else
                        state_next = DEC_DONE;
                end
            end

            DEC_SIB: begin
                if (q_valid && (q_fetch_eip == opcode_eip_latch + sib_offset())) begin
                    if (disp_bytes_for_modrm(modrm_latch, q_data, 1'b1) != 3'd0)
                        state_next = DEC_DISP;
                    else
                        state_next = DEC_DONE;
                end
            end

            DEC_DISP: begin
                if (disp_idx == disp_total)
                    state_next = DEC_DONE;
            end

            DEC_DONE: begin
                if (dec_ack)
                    state_next = DEC_IDLE;
            end

            default: state_next = DEC_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Helper decode
    // ----------------------------------------------------------------
    function automatic logic is_prefix_byte(input logic [7:0] b);
        return (b == 8'h66) || (b == 8'h67);
    endfunction

    function automatic logic accept_second_prefix(input logic [7:0] b);
        // Pass 6H supports 66+67 only. The reverse order remains outside
        // this bounded slice and is left as a prefix-only boundary.
        return prefix66_active && !prefix67_active &&
               (prefix_count == 2'd1) && (b == 8'h67);
    endfunction

    function automatic logic prefix_opcode_candidate(input logic [7:0] b);
        if (prefix67_active) begin
            if (prefix66_active)
                return (b == 8'h8B) || (b == 8'h89) || (b == 8'hC7);
            return (b == 8'h88) || (b == 8'h89) || (b == 8'h8A) ||
                   (b == 8'h8B) || (b == 8'hC6) || (b == 8'hC7);
        end

        if (prefix66_active)
            return (b == 8'h89) || (b == 8'h8B) || (b == 8'hC7) ||
                   (b[7:3] == 5'b10111);

        return 1'b0;
    endfunction

    function automatic logic modrm_needs_sib(input logic [7:0] m);
        return (m[7:6] != 2'b11) && (m[2:0] == 3'b100);
    endfunction

    function automatic logic modrm_needs_sib_addr(input logic [7:0] m);
        return !prefix67_active && modrm_needs_sib(m);
    endfunction

    function automatic logic [2:0] disp_bytes_for_modrm(
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       have_sib
    );
        logic [1:0] mod_bits;
        logic [2:0] rm_bits;
        logic [2:0] base_bits;
        begin
            mod_bits = m[7:6];
            rm_bits  = m[2:0];
            base_bits = have_sib ? s[2:0] : rm_bits;

            if (mod_bits == 2'b11)
                return 3'd0;
            if (prefix67_active) begin
                if ((mod_bits == 2'b00) && (rm_bits == 3'b110))
                    return 3'd2;
                if (mod_bits == 2'b01)
                    return 3'd1;
                if (mod_bits == 2'b10)
                    return 3'd2;
                return 3'd0;
            end
            if (mod_bits == 2'b01)
                return 3'd1;
            if (mod_bits == 2'b10)
                return 3'd4;
            if (base_bits == 3'b101)
                return 3'd4;
            return 3'd0;
        end
    endfunction

    function automatic logic [31:0] disp_start_offset();
        return modrm_offset() + 32'd1 +
               (modrm_needs_sib_addr(modrm_latch) ? 32'd1 : 32'd0) +
               {29'h0, disp_idx};
    endfunction

    function automatic logic [31:0] modrm_offset();
        return 32'd1 + {30'h0, prefix_count};
    endfunction

    function automatic logic [31:0] sib_offset();
        return modrm_offset() + 32'd1;
    endfunction

    function automatic logic [3:0] classify_modrm(input logic [7:0] m);
        if (m[7:6] == 2'b11)
            return 4'h0; // MRM_REG
        if (prefix67_active && (m[7:6] == 2'b00) && (m[2:0] == 3'b110))
            return 4'h8; // MRM_DIRECT16
        if (prefix67_active && addr16_nodisp_form(m))
            return 4'h1; // MRM_MEM_NO_DISP for the bounded 16-bit no-disp subset
        if (prefix67_active && addr16_disp8_form(m))
            return 4'h2; // MRM_MEM_DISP8 for the bounded 16-bit disp8 subset
        if (prefix67_active && addr16_disp16_form(m))
            return 4'h4; // MRM_MEM_DISP16 for the bounded 16-bit disp16 subset
        if (prefix67_active)
            return 4'hF; // Unsupported 16-bit addressing forms stay unrouted.
        if (modrm_needs_sib(m)) begin
            if (m[7:6] == 2'b01)
                return 4'h6; // MRM_SIB_DISP8
            if (m[7:6] == 2'b10)
                return 4'h7; // MRM_SIB_DISP32
            return 4'h5;     // MRM_SIB
        end
        if (m[7:6] == 2'b00 && m[2:0] == 3'b101)
            return 4'h3;     // MRM_MEM_DISP32 / direct32 in this 32-bit slice
        if (m[7:6] == 2'b01)
            return 4'h2;     // MRM_MEM_DISP8
        if (m[7:6] == 2'b10)
            return 4'h3;     // MRM_MEM_DISP32
        return 4'h1;         // MRM_MEM_NO_DISP
    endfunction

    function automatic logic base_nodisp32_form(input logic [7:0] m);
        return (m[7:6] == 2'b00) &&
               (m[2:0] != 3'b100) &&
               (m[2:0] != 3'b101);
    endfunction

    function automatic logic base_disp8_32_form(input logic [7:0] m);
        return (m[7:6] == 2'b01) &&
               (m[2:0] != 3'b100);
    endfunction

    function automatic logic base_disp32_32_form(input logic [7:0] m);
        return (m[7:6] == 2'b10) &&
               (m[2:0] != 3'b100);
    endfunction

    function automatic logic sib_index_none(input logic [7:0] s);
        return (s[5:3] == 3'b100);
    endfunction

    function automatic logic sib_nodisp32_form(
        input logic [7:0] m,
        input logic [7:0] s
    );
        return (m[7:6] == 2'b00) &&
               (m[2:0] == 3'b100) &&
               (s[2:0] != 3'b101);
    endfunction

    function automatic logic sib_nobase_disp32_form(
        input logic [7:0] m,
        input logic [7:0] s
    );
        return (m[7:6] == 2'b00) &&
               (m[2:0] == 3'b100) &&
               sib_index_none(s) &&
               (s[2:0] == 3'b101);
    endfunction

    function automatic logic sib_index_nobase_disp32_form(
        input logic [7:0] m,
        input logic [7:0] s
    );
        return (m[7:6] == 2'b00) &&
               (m[2:0] == 3'b100) &&
               !sib_index_none(s) &&
               (s[2:0] == 3'b101);
    endfunction

    function automatic logic sib_disp8_32_form(
        input logic [7:0] m,
        input logic [7:0] s
    );
        return (m[7:6] == 2'b01) &&
               (m[2:0] == 3'b100);
    endfunction

    function automatic logic sib_disp32_32_form(
        input logic [7:0] m,
        input logic [7:0] s
    );
        return (m[7:6] == 2'b10) &&
               (m[2:0] == 3'b100);
    endfunction

    function automatic logic mov_mem_src_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        logic direct_disp32;
        begin
            direct_disp32 = (m[7:6] == 2'b00) && (m[2:0] == 3'b101);
            if (!direct_disp32)
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_base_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_nodisp32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_sib_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_nodisp32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_sib_nobase_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!(sib_nobase_disp32_form(m, s) ||
                  sib_index_nobase_disp32_form(m, s)))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_base_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp8_32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_sib_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp8_32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_base_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp32_32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_src_sib_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp32_32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h8B);

            return (op == 8'h8A) || (op == 8'h8B);
        end
    endfunction

    function automatic logic mov_mem_dst_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        logic direct_disp32;
        begin
            direct_disp32 = (m[7:6] == 2'b00) && (m[2:0] == 3'b101);
            if (!direct_disp32)
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_base_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_nodisp32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_sib_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_nodisp32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_sib_nobase_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!(sib_nobase_disp32_form(m, s) ||
                  sib_index_nobase_disp32_form(m, s)))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_base_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp8_32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_sib_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp8_32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_base_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp32_32_form(m))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_mem_dst_sib_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp32_32_form(m, s))
                return 1'b0;

            if (pref66)
                return (op == 8'h89);

            return (op == 8'h88) || (op == 8'h89);
        end
    endfunction

    function automatic logic mov_rm_imm_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        logic direct_disp32_group0;
        begin
            direct_disp32_group0 = (m[7:6] == 2'b00) &&
                                   (m[5:3] == 3'b000) &&
                                   (m[2:0] == 3'b101);
            if (!direct_disp32_group0)
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_base_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_nodisp32_form(m) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_sib_nodisp_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_nodisp32_form(m, s) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_sib_nobase_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!(sib_nobase_disp32_form(m, s) ||
                  sib_index_nobase_disp32_form(m, s)) ||
                (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_base_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp8_32_form(m) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_sib_disp8_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp8_32_form(m, s) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_base_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        begin
            if (!base_disp32_32_form(m) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic mov_rm_imm_sib_disp32_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66
    );
        begin
            if (!sib_disp32_32_form(m, s) || (m[5:3] != 3'b000))
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic direct16_addr_form(input logic [7:0] m);
        return (m[7:6] == 2'b00) && (m[2:0] == 3'b110);
    endfunction

    function automatic logic addr16_nodisp_form(input logic [7:0] m);
        if (m[7:6] != 2'b00)
            return 1'b0;
        case (m[2:0])
            3'b000, // [BX+SI]
            3'b001, // [BX+DI]
            3'b010, // [BP+SI]
            3'b011, // [BP+DI]
            3'b100, // [SI]
            3'b101, // [DI]
            3'b111: return 1'b1; // [BX]
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic addr16_disp8_form(input logic [7:0] m);
        return (m[7:6] == 2'b01);
    endfunction

    function automatic logic addr16_disp16_form(input logic [7:0] m);
        return (m[7:6] == 2'b10);
    endfunction

    function automatic logic mov_mem_src_addr16_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66,
        input logic       addr16
    );
        if (!addr16 ||
            !(direct16_addr_form(m) || addr16_nodisp_form(m) ||
              addr16_disp8_form(m) || addr16_disp16_form(m)))
            return 1'b0;
        if (pref66)
            return (op == 8'h8B);
        return (op == 8'h8A) || (op == 8'h8B);
    endfunction

    function automatic logic mov_mem_dst_addr16_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66,
        input logic       addr16
    );
        if (!addr16 ||
            !(direct16_addr_form(m) || addr16_nodisp_form(m) ||
              addr16_disp8_form(m) || addr16_disp16_form(m)))
            return 1'b0;
        if (pref66)
            return (op == 8'h89);
        return (op == 8'h88) || (op == 8'h89);
    endfunction

    function automatic logic mov_rm_imm_addr16_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66,
        input logic       addr16
    );
        if (!addr16 ||
            !(direct16_addr_form(m) || addr16_nodisp_form(m) ||
              addr16_disp8_form(m) || addr16_disp16_form(m)) ||
            (m[5:3] != 3'b000))
            return 1'b0;
        if (pref66)
            return (op == 8'hC7);
        return (op == 8'hC6) || (op == 8'hC7);
    endfunction

    function automatic logic mov_mem_src_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66,
        input logic       addr16
    );
        if (addr16)
            return mov_mem_src_addr16_form(op, m, pref66, addr16);

        return mov_mem_src_disp32_form(op, m, pref66) ||
               mov_mem_src_base_nodisp_form(op, m, pref66) ||
               mov_mem_src_base_disp8_form(op, m, pref66) ||
               mov_mem_src_base_disp32_form(op, m, pref66) ||
               mov_mem_src_sib_nodisp_form(op, m, s, pref66) ||
               mov_mem_src_sib_nobase_disp32_form(op, m, s, pref66) ||
               mov_mem_src_sib_disp8_form(op, m, s, pref66) ||
               mov_mem_src_sib_disp32_form(op, m, s, pref66);
    endfunction

    function automatic logic mov_mem_dst_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66,
        input logic       addr16
    );
        if (addr16)
            return mov_mem_dst_addr16_form(op, m, pref66, addr16);

        return mov_mem_dst_disp32_form(op, m, pref66) ||
               mov_mem_dst_base_nodisp_form(op, m, pref66) ||
               mov_mem_dst_base_disp8_form(op, m, pref66) ||
               mov_mem_dst_base_disp32_form(op, m, pref66) ||
               mov_mem_dst_sib_nodisp_form(op, m, s, pref66) ||
               mov_mem_dst_sib_nobase_disp32_form(op, m, s, pref66) ||
               mov_mem_dst_sib_disp8_form(op, m, s, pref66) ||
               mov_mem_dst_sib_disp32_form(op, m, s, pref66);
    endfunction

    function automatic logic mov_rm_imm_mem_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66,
        input logic       addr16
    );
        if (addr16)
            return mov_rm_imm_addr16_form(op, m, pref66, addr16);

        return mov_rm_imm_disp32_form(op, m, pref66) ||
               mov_rm_imm_base_nodisp_form(op, m, pref66) ||
               mov_rm_imm_base_disp8_form(op, m, pref66) ||
               mov_rm_imm_base_disp32_form(op, m, pref66) ||
               mov_rm_imm_sib_nodisp_form(op, m, s, pref66) ||
               mov_rm_imm_sib_nobase_disp32_form(op, m, s, pref66) ||
               mov_rm_imm_sib_disp8_form(op, m, s, pref66) ||
               mov_rm_imm_sib_disp32_form(op, m, s, pref66);
    endfunction

    function automatic logic mov_rm_imm_reg_form(
        input logic [7:0] op,
        input logic [7:0] m,
        input logic       pref66
    );
        logic reg_group0;
        begin
            reg_group0 = (m[7:6] == 2'b11) && (m[5:3] == 3'b000);
            if (!reg_group0)
                return 1'b0;

            if (pref66)
                return (op == 8'hC7);

            return (op == 8'hC6) || (op == 8'hC7);
        end
    endfunction

    function automatic logic [31:0] mov_modrm_length();
        return modrm_offset() + 32'd1 +
               (modrm_needs_sib_addr(modrm_latch) ? 32'd1 : 32'd0) +
               {29'h0, disp_total};
    endfunction

    function automatic logic [31:0] mov_rm_imm_length();
        logic [31:0] imm_len;
        begin
            if (opcode_byte_latch == 8'hC6)
                imm_len = 32'd1;
            else if (prefix66_active)
                imm_len = 32'd2;
            else
                imm_len = 32'd4;

            return mov_modrm_length() + imm_len;
        end
    endfunction

    function automatic logic [7:0] classify_opcode(
        input logic [7:0] op,
        input logic       ff2,
        input logic [7:0] m,
        input logic [7:0] s,
        input logic       pref66,
        input logic       addr16
    );
        if (addr16 && (op == 8'h00))
            return ENTRY_PREFIX_ONLY;

        if (pref66) begin
            case (op)
                8'h89: return ((!addr16 && (m[7:6] == 2'b11)) ||
                                mov_mem_dst_form(op, m, s, pref66, addr16)) ?
                               ENTRY_MOV : ENTRY_NULL;
                8'h8B: return ((!addr16 && (m[7:6] == 2'b11)) ||
                                mov_mem_src_form(op, m, s, pref66, addr16)) ?
                               ENTRY_MOV : ENTRY_NULL;
                8'hC7: return (mov_rm_imm_mem_form(op, m, s, pref66, addr16) ||
                                (!addr16 && mov_rm_imm_reg_form(op, m, pref66)))
                               ? ENTRY_MOV : ENTRY_NULL;
                8'hB8, 8'hB9, 8'hBA, 8'hBB,
                8'hBC, 8'hBD, 8'hBE, 8'hBF:
                       return ENTRY_MOV;
                default: return ENTRY_NULL;
            endcase
        end

        case (op)
            8'h01,
            8'h29,
            8'h39:            return ((!addr16 && (m[7:6] == 2'b11)) ?
                                      ENTRY_ALU_RM_R : ENTRY_NULL);
            8'h03,
            8'h3B:            return ((!addr16 && (m[7:6] == 2'b11)) ?
                                      ENTRY_ALU_R_RM : ENTRY_NULL);
            8'h90:            return ENTRY_NOP_XCHG_AX;
            8'hEB, 8'hE9:     return ENTRY_JMP_NEAR;
            8'h70, 8'h71, 8'h72, 8'h73,
            8'h74, 8'h75, 8'h76, 8'h77,
            8'h78, 8'h79, 8'h7A, 8'h7B,
            8'h7C, 8'h7D, 8'h7E, 8'h7F:
                              return ENTRY_JCC;
            8'hE8:            return ENTRY_CALL_NEAR;
            8'hFF:            return ff2 ? ENTRY_CALL_NEAR : ENTRY_NULL;
            8'h88, 8'h89:
                              return ((!addr16 && (m[7:6] == 2'b11)) ||
                                      mov_mem_dst_form(op, m, s, pref66, addr16))
                                      ? ENTRY_MOV : ENTRY_NULL;
            8'h8A, 8'h8B:     return ((!addr16 && (m[7:6] == 2'b11)) ||
                                      mov_mem_src_form(op, m, s, pref66, addr16))
                                      ? ENTRY_MOV : ENTRY_NULL;
            8'hC6, 8'hC7:     return (mov_rm_imm_mem_form(op, m, s, pref66, addr16) ||
                                      (!addr16 && mov_rm_imm_reg_form(op, m, pref66)))
                                      ? ENTRY_MOV : ENTRY_NULL;
            8'hC3, 8'hC2:     return ENTRY_RET_NEAR;
            8'hCD:            return ENTRY_INT;
            8'hCF:            return ENTRY_IRET;
            8'hB0, 8'hB1, 8'hB2, 8'hB3,
            8'hB4, 8'hB5, 8'hB6, 8'hB7,
            8'hB8, 8'hB9, 8'hBA, 8'hBB,
            8'hBC, 8'hBD, 8'hBE, 8'hBF:
                              return ENTRY_MOV;
            8'hF0, 8'hF2, 8'hF3,
            8'h2E, 8'h36, 8'h3E, 8'h26,
            8'h64, 8'h65,
            8'h66, 8'h67:     return ENTRY_PREFIX_ONLY;
            default:          return ENTRY_NULL;
        endcase
    endfunction

    logic [31:0] disp16_sext;
    assign disp16_sext = {{16{aux_hi[7]}}, aux_hi, aux_lo};

    // ----------------------------------------------------------------
    // Output logic
    // ----------------------------------------------------------------
    always_comb begin
        q_consume    = 1'b0;
        decode_done  = 1'b0;
        entry_id     = ENTRY_NULL;

        // Architectural M_NEXT_EIP
        if (prefix66_active && is_mov_r_imm32)
            next_eip = opcode_eip_latch + 32'h4;
        else if (prefix66_active && is_mov_modrm)
            next_eip = opcode_eip_latch + mov_modrm_length();
        else if (prefix66_active && is_mov_rm_imm) begin
            if (mov_rm_imm_mem_form(opcode_byte_latch, modrm_latch,
                                    sib_latch, 1'b1, prefix67_active) ||
                mov_rm_imm_reg_form(opcode_byte_latch, modrm_latch, 1'b1))
                next_eip = opcode_eip_latch + mov_rm_imm_length();
            else
                next_eip = opcode_eip_latch + mov_modrm_length();
        end
        else if (prefix66_active)
            next_eip = opcode_eip_latch + 32'h2;
        else if (is_jmp_short || is_jcc_short || is_int_imm8)
            next_eip = opcode_eip_latch + 32'h2;
        else if (is_jmp_near || is_call_direct || is_ret_imm16)
            next_eip = opcode_eip_latch + 32'h3;
        else if (is_mov_r_imm8)
            next_eip = opcode_eip_latch + 32'h2;
        else if (is_mov_r_imm32)
            next_eip = opcode_eip_latch + 32'h5;
        else if (is_mov_modrm)
            next_eip = opcode_eip_latch + mov_modrm_length();
        else if (is_alu_rm_r || is_alu_r_rm)
            next_eip = opcode_eip_latch + 32'h2;
        else if (is_mov_rm_imm) begin
            if (mov_rm_imm_mem_form(opcode_byte_latch, modrm_latch,
                                    sib_latch, 1'b0, prefix67_active) ||
                mov_rm_imm_reg_form(opcode_byte_latch, modrm_latch, 1'b0))
                next_eip = opcode_eip_latch + mov_rm_imm_length();
            else
                next_eip = opcode_eip_latch + mov_modrm_length();
        end
        else if (is_call_ff)
            next_eip = opcode_eip_latch + 32'h2 +
                       (modrm_needs_sib_addr(modrm_latch) ? 32'h1 : 32'h0) +
                       {29'h0, disp_total};
        else
            next_eip = opcode_eip_latch + 32'h1;

        // Rung 3 target computation remains service-owned. Compatibility
        // target outputs stay inactive so decode cannot become a hidden
        // execution path.
        target_eip   = 32'h0;
        has_target   = 1'b0;
        is_call      = 1'b0;
        is_call_indirect = 1'b0;
        is_ret       = 1'b0;
        has_ret_imm  = 1'b0;
        ret_imm      = 16'h0;
        modrm_byte   = modrm_latch;
        sib_byte     = sib_latch;
        modrm_present= is_call_ff || is_mov_modrm || is_mov_rm_imm ||
                       is_alu_rm_r || is_alu_r_rm;
        // Immediate-to-register MOV has no ModRM byte but shares ENTRY_MOV's
        // immediate dispatch with C6/C7. Report the non-memory class here so
        // microcode can use M_MODRM_CLASS as the explicit memory-vs-register
        // discriminator without consulting M_REG_RM.
        modrm_class  = (is_mov_r_imm8 || is_mov_r_imm32) ? 4'h0 :
                                                            classify_modrm(modrm_latch);
        disp_valid   = (disp_total != 3'd0);
        case (disp_total)
            3'd1: disp_value = {{24{disp_latch[7]}}, disp_latch[7:0]};
            3'd2: disp_value = {16'h0, disp_latch[15:0]};
            3'd4: disp_value = disp_latch;
            default: disp_value = 32'h0;
        endcase
        payload16_valid  = 1'b0;
        payload16_signed = 1'b0;
        payload16        = {aux_hi, aux_lo};
        if (is_mov_r_imm8 || is_mov_r_imm32)
            opcode_class = OC_MOV_R_IMM;
        else if (is_mov_rm_imm)
            opcode_class = OC_MOV_RM_IMM;
        else if (is_mov_modrm)
            opcode_class = opcode_byte_latch[1] ? OC_MOV_R_RM : OC_MOV_RM_R;
        else
            opcode_class = 8'h00;
        opsz             = is_mov_r_imm8  ? OPSZ_8  :
                           (prefix66_active && (is_mov_r_imm32 || is_mov_modrm)) ? OPSZ_16 :
                           is_mov_r_imm32 ? OPSZ_32 :
                           is_mov_rm_imm  ? ((opcode_byte_latch == 8'hC6) ? OPSZ_8 :
                                              (prefix66_active ? OPSZ_16 : OPSZ_32)) :
                           (is_alu_rm_r || is_alu_r_rm) ? OPSZ_32 :
                           is_mov_modrm   ? (opcode_byte_latch[0] ? OPSZ_32 : OPSZ_8) :
                                            2'h0;
        addrsz           = prefix67_active ? 1'b0 : 1'b1;
        imm_class        = is_mov_r_imm8  ? IMM_8   :
                           (prefix66_active && is_mov_r_imm32) ? IMM_16 :
                           is_mov_r_imm32 ? IMM_32  :
                           is_mov_rm_imm  ? ((opcode_byte_latch == 8'hC6) ? IMM_8 :
                                              (prefix66_active ? IMM_16 : IMM_32)) :
                                            IMM_NONE;
        if (is_mov_r_imm8 || is_mov_r_imm32)
            reg_dst = opcode_byte_latch[2:0];
        else if (is_mov_rm_imm)
            reg_dst = modrm_latch[2:0];
        else if (is_mov_modrm)
            reg_dst = opcode_byte_latch[1] ? modrm_latch[5:3] : modrm_latch[2:0];
        else if (is_alu_rm_r)
            reg_dst = modrm_latch[2:0];
        else if (is_alu_r_rm)
            reg_dst = modrm_latch[5:3];
        else
            reg_dst = 3'h0;
        reg_src          = (is_mov_modrm || is_mov_rm_imm ||
                            is_alu_rm_r || is_alu_r_rm) ?
                           modrm_latch[5:3] : 3'h0;
        reg_rm           = (is_mov_modrm || is_mov_rm_imm ||
                            is_alu_rm_r || is_alu_r_rm) ?
                           modrm_latch[2:0] : 3'h0;
        alu_op           = ((is_alu_rm_r && (opcode_byte_latch == 8'h39)) ||
                            (is_alu_r_rm && (opcode_byte_latch == 8'h3B))) ?
                           ALU_CMP :
                           ((is_alu_rm_r && (opcode_byte_latch == 8'h29)) ?
                            ALU_SUB : ALU_ADD);
        is_cmp           = (is_alu_rm_r && (opcode_byte_latch == 8'h39)) ||
                           (is_alu_r_rm && (opcode_byte_latch == 8'h3B));
        cond_code        = opcode_byte_latch[3:0];

        case (state)
            DEC_PREFIX66: begin
                if (!opcode_consumed && q_valid &&
                    (q_fetch_eip == opcode_eip_latch)) begin
                    q_consume = 1'b1;
                end else if (opcode_consumed && q_valid &&
                             (q_fetch_eip == opcode_eip_latch +
                                             {30'h0, prefix_count}) &&
                             (accept_second_prefix(q_data) ||
                              prefix_opcode_candidate(q_data))) begin
                    q_consume = 1'b1;
                end
            end

            DEC_CONSUME: begin
                q_consume = 1'b1;
            end

            DEC_DISP16: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (!aux_lo_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    q_consume = 1'b1;
                end else if (!aux_hi_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + 32'h2)) begin
                    q_consume = 1'b1;
                end
            end

            DEC_MODRM: begin
                if (!opcode_consumed) begin
                    q_consume = 1'b1;
                end else if (!aux_lo_valid && q_valid &&
                             (q_fetch_eip == opcode_eip_latch + modrm_offset())) begin
                    q_consume = 1'b1;
                end
            end

            DEC_SIB: begin
                if (q_valid && (q_fetch_eip == opcode_eip_latch + sib_offset()))
                    q_consume = 1'b1;
            end

            DEC_DISP: begin
                if ((disp_idx < disp_total) &&
                    q_valid && (q_fetch_eip == opcode_eip_latch + disp_start_offset()))
                    q_consume = 1'b1;
            end

            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = classify_opcode(opcode_byte_latch, ff_is_call_near,
                                              modrm_latch,
                                              sib_latch,
                                              prefix66_active,
                                              prefix67_active);

                if (is_call_direct) begin
                    is_call          = 1'b1;
                    payload16_valid  = 1'b1;
                    payload16_signed = 1'b1;
                end else if (is_call_ff) begin
                    is_call          = ff_is_call_near;
                    is_call_indirect = ff_is_call_near;
                end else if (is_ret_near) begin
                    is_ret      = 1'b1;
                    has_ret_imm = 1'b0;
                end else if (is_ret_imm16) begin
                    is_ret           = 1'b1;
                    has_ret_imm      = 1'b1;
                    ret_imm          = {aux_hi, aux_lo};
                    payload16_valid  = 1'b1;
                    payload16_signed = 1'b0;
                end
            end

            default: ;
        endcase
    end

endmodule
