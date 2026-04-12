// Keystone86 / Aegis
// rtl/core/decoder.sv
// Rung 1: Real opcode classification (NOP and prefix-only placeholder)
//
// Ownership (Appendix B):
//   This module owns: opcode byte consumption from prefetch queue,
//   entry ID selection, decode_done assertion, M_NEXT_EIP production.
//   This module must NOT: implement instruction semantics, read
//   architectural registers, access memory, produce instruction results.
//
// Rung 1 changes from Rung 0:
//   - Opcode byte is now latched (was consumed but ignored in Rung 0)
//   - Classification added in DEC_DONE output logic:
//       0x90                          -> ENTRY_NOP_XCHG_AX
//       prefix-only placeholder group -> ENTRY_PREFIX_ONLY
//       all other opcodes             -> ENTRY_NULL
//   - All handshake behavior, state machine, and next_eip logic
//     are UNCHANGED from Rung 0.
//
// Decoder handshake (unchanged):
//   - Wait for q_valid from prefetch queue
//   - Latch EIP and opcode byte in DEC_IDLE
//   - Assert q_consume for one cycle in DEC_CONSUME
//   - Assert decode_done with classified entry_id in DEC_DONE
//   - Hold decode_done until dec_ack from microsequencer
//   - Clear decode_done and return to DEC_IDLE on dec_ack
//
// Prefix-only placeholder group (Rung 1 stub):
//   Bytes: F0(LOCK) F2(REPNE) F3(REP) 2E(CS) 36(SS) 3E(DS)
//          26(ES) 64(FS) 65(GS) 66(operand-size) 67(addr-size)
//   No prefix accumulation. Treated as single-byte no-ops in Rung 1.

`include "entry_ids.svh"

module decoder (
    input  logic        clk,
    input  logic        reset_n,

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
    input  logic        dec_ack,

    // --- Fetch EIP tracking ---
    input  logic [31:0] q_fetch_eip
);

    typedef enum logic [1:0] {
        DEC_IDLE    = 2'b00,
        DEC_CONSUME = 2'b01,
        DEC_DONE    = 2'b10
    } dec_state_t;

    dec_state_t state, state_next;

    logic [31:0] opcode_eip_latch;
    logic [7:0]  opcode_byte_latch;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= DEC_IDLE;
            opcode_eip_latch  <= 32'h0;
            opcode_byte_latch <= 8'h0;
        end else begin
            state <= state_next;
            if (state == DEC_IDLE && q_valid) begin
                opcode_eip_latch  <= q_fetch_eip;
                opcode_byte_latch <= q_data;
            end
        end
    end

    // ----------------------------------------------------------------
    // Next-state logic (unchanged from Rung 0)
    // ----------------------------------------------------------------
    always_comb begin
        state_next = state;
        case (state)
            DEC_IDLE:    if (q_valid)    state_next = DEC_CONSUME;
            DEC_CONSUME:                 state_next = DEC_DONE;
            DEC_DONE:    if (dec_ack)    state_next = DEC_IDLE;
            default:                     state_next = DEC_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Opcode classification — Rung 1
    // Combinational, no state, no side effects.
    // Classification-only: no instruction semantics here.
    // ----------------------------------------------------------------
    function automatic logic [7:0] classify_opcode(input logic [7:0] op);
        case (op)
            8'h90:                          return `ENTRY_NOP_XCHG_AX;
            8'hF0, 8'hF2, 8'hF3,           // LOCK, REPNE, REP
            8'h2E, 8'h36, 8'h3E, 8'h26,    // CS, SS, DS, ES
            8'h64, 8'h65,                   // FS, GS
            8'h66, 8'h67:                   // operand-size, addr-size
                                            return `ENTRY_PREFIX_ONLY;
            default:                        return `ENTRY_NULL;
        endcase
    endfunction

    // ----------------------------------------------------------------
    // Output logic
    // ----------------------------------------------------------------
    always_comb begin
        q_consume   = 1'b0;
        decode_done = 1'b0;
        entry_id    = `ENTRY_NULL;
        next_eip    = opcode_eip_latch + 32'h1;

        case (state)
            DEC_CONSUME: begin
                q_consume = 1'b1;
            end
            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = classify_opcode(opcode_byte_latch);
                next_eip    = opcode_eip_latch + 32'h1;
            end
            default: ;
        endcase
    end

    // synthesis translate_off
    logic [7:0] dbg_last_opcode_byte;
    always_ff @(posedge clk) begin
        if (state == DEC_CONSUME && q_valid)
            dbg_last_opcode_byte <= q_data;
    end
    // synthesis translate_on

endmodule
