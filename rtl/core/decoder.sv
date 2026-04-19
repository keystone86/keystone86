// Keystone86 / Aegis
// rtl/core/decoder.sv
//
// Rung 2 reset-aligned decoder:
//   - Decoder classifies JMP and produces M_NEXT_EIP.
//   - Decoder consumes only the opcode byte for JMP forms.
//   - Displacement bytes for JMP are consumed by fetch_engine services.
//   - Retained later-rung outputs stay present for compatibility, but the
//     active Rung 2 JMP path must not eat displacement bytes in decode.

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
    output logic [31:0] target_eip,     // direct-call target only
    output logic        has_target,
    output logic        is_call,
    output logic        is_ret,
    output logic        has_ret_imm,
    output logic [15:0] ret_imm,
    output logic [7:0]  modrm_byte,
    input  logic        dec_ack,

    // --- Fetch EIP tracking ---
    input  logic [31:0] q_fetch_eip
);

    typedef enum logic [3:0] {
        DEC_IDLE    = 4'h0,
        DEC_CONSUME = 4'h1,
        DEC_DISP16  = 4'h2,   // used for E8 disp16 and C2 imm16
        DEC_MODRM   = 4'h3,   // used for FF forms
        DEC_DONE    = 4'h4
    } dec_state_t;

    dec_state_t state, state_next;

    logic [31:0] opcode_eip_latch;
    logic [7:0]  opcode_byte_latch;

    logic [7:0]  aux_lo;
    logic [7:0]  aux_hi;
    logic        aux_lo_valid;
    logic        aux_hi_valid;

    logic        is_jmp_short;
    logic        is_jmp_near;
    logic        is_call_direct;
    logic        is_call_ff;
    logic        is_ret_near;
    logic        is_ret_imm16;

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
            aux_lo            <= 8'h0;
            aux_hi            <= 8'h0;
            aux_lo_valid      <= 1'b0;
            aux_hi_valid      <= 1'b0;
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_ff        <= 1'b0;
            is_ret_near       <= 1'b0;
            is_ret_imm16      <= 1'b0;
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
            is_jmp_short      <= 1'b0;
            is_jmp_near       <= 1'b0;
            is_call_direct    <= 1'b0;
            is_call_ff        <= 1'b0;
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
                        is_call_ff        <= (q_data == 8'hFF);
                        is_ret_near       <= (q_data == 8'hC3);
                        is_ret_imm16      <= (q_data == 8'hC2);
                        aux_lo_valid      <= 1'b0;
                        aux_hi_valid      <= 1'b0;
                        opcode_consumed   <= 1'b0;
                        modrm_latch       <= 8'h0;
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
                        if (q_valid && (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                            modrm_latch  <= q_data;
                            aux_lo_valid <= 1'b1;
                        end
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
                    // Rung 2: JMP forms consume opcode only.
                    if (q_data == 8'hEB || q_data == 8'hE9)
                        state_next = DEC_CONSUME;
                    else if (q_data == 8'hE8 || q_data == 8'hC2)
                        state_next = DEC_DISP16;
                    else if (q_data == 8'hFF)
                        state_next = DEC_MODRM;
                    else
                        state_next = DEC_CONSUME;
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
                if (opcode_consumed && aux_lo_valid)
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
    logic ff_is_call_near;
    assign ff_is_call_near = (modrm_latch[5:3] == 3'b010);

    function automatic logic [7:0] classify_opcode(
        input logic [7:0] op,
        input logic       ff2
    );
        case (op)
            8'h90:            return ENTRY_NOP_XCHG_AX;
            8'hEB, 8'hE9:     return ENTRY_JMP_NEAR;
            8'hE8:            return ENTRY_CALL_NEAR;
            8'hFF:            return ff2 ? ENTRY_CALL_NEAR : ENTRY_NULL;
            8'hC3, 8'hC2:     return ENTRY_RET_NEAR;
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
        if (is_jmp_short)
            next_eip = opcode_eip_latch + 32'h2;
        else if (is_jmp_near || is_call_direct || is_ret_imm16)
            next_eip = opcode_eip_latch + 32'h3;
        else if (is_call_ff)
            next_eip = opcode_eip_latch + 32'h2;
        else
            next_eip = opcode_eip_latch + 32'h1;

        // Only direct CALL target is still formed here.
        target_eip   = 32'h0;
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
                             (q_fetch_eip == opcode_eip_latch + 32'h1)) begin
                    q_consume = 1'b1;
                end
            end

            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = classify_opcode(opcode_byte_latch, ff_is_call_near);

                if (is_call_direct && aux_lo_valid && aux_hi_valid) begin
                    target_eip = opcode_eip_latch + 32'h3 + disp16_sext;
                    has_target = 1'b1;
                    is_call    = 1'b1;
                end else if (is_call_ff) begin
                    is_call    = ff_is_call_near;
                    has_target = 1'b0;
                end else if (is_ret_near) begin
                    is_ret      = 1'b1;
                    has_ret_imm = 1'b0;
                end else if (is_ret_imm16) begin
                    is_ret      = 1'b1;
                    has_ret_imm = 1'b1;
                    ret_imm     = {aux_hi, aux_lo};
                end
            end

            default: ;
        endcase
    end

endmodule