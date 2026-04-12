// Keystone86 / Aegis
// rtl/core/decoder.sv
// Rung 0: Decoder stub — always outputs ENTRY_NULL
//
// Ownership (Appendix B):
//   This module owns: opcode byte consumption from prefetch queue,
//   entry ID selection, decode_done assertion, M_NEXT_EIP production.
//   This module must NOT: implement instruction semantics, read
//   architectural registers, access memory, produce instruction results.
//
// Rung 0 scope:
//   The decoder is a STUB. It consumes one byte from the prefetch queue
//   and always emits ENTRY_NULL. No ModRM, no prefix parsing, no real
//   classification. That is intentional and correct for Rung 0.
//
//   Decoder handshake:
//     - Wait for q_valid from prefetch queue
//     - Assert q_consume for one cycle to consume the opcode byte
//     - Assert decode_done with entry_id = ENTRY_NULL
//     - Hold decode_done until dec_ack from microsequencer
//     - Clear decode_done and return to idle on dec_ack

`include "entry_ids.svh"

module decoder (
    input  logic        clk,
    input  logic        reset_n,

    // --- Mode context (from commit_engine) ---
    input  logic        mode_prot,          // 0=real, 1=protected
    input  logic        cs_d_bit,           // CS.D default operand size

    // --- Prefetch queue interface ---
    input  logic [7:0]  q_data,             // next available byte
    input  logic        q_valid,            // queue has a byte
    output logic        q_consume,          // consume one byte

    // --- Microsequencer handshake ---
    output logic        decode_done,        // instruction fully decoded
    output logic [7:0]  entry_id,           // ENTRY_* for this instruction
    output logic [31:0] next_eip,           // EIP of following instruction
    input  logic        dec_ack,            // microsequencer acknowledged

    // --- Fetch EIP tracking (from prefetch_queue) ---
    input  logic [31:0] q_fetch_eip         // EIP of current head byte
);

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        DEC_IDLE    = 2'b00,
        DEC_CONSUME = 2'b01,
        DEC_DONE    = 2'b10
    } dec_state_t;

    dec_state_t state, state_next;

    // Latch for opcode byte EIP
    logic [31:0] opcode_eip_latch;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= DEC_IDLE;
            opcode_eip_latch <= 32'h0;
        end else begin
            state <= state_next;
            if (state == DEC_IDLE && q_valid)
                opcode_eip_latch <= q_fetch_eip;
        end
    end

    // ----------------------------------------------------------------
    // Next-state logic
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
    // Output logic
    // ----------------------------------------------------------------
    // entry_id: always ENTRY_NULL in Rung 0 stub
    // next_eip: opcode EIP + 1 (one byte consumed)
    // decode_done: held high in DEC_DONE until dec_ack
    // q_consume: pulsed for one cycle in DEC_CONSUME

    always_comb begin
        q_consume   = 1'b0;
        decode_done = 1'b0;
        entry_id    = `ENTRY_NULL;
        next_eip    = opcode_eip_latch + 32'h1;

        case (state)
            DEC_CONSUME: begin
                q_consume = 1'b1;   // consume the opcode byte this cycle
            end
            DEC_DONE: begin
                decode_done = 1'b1;
                entry_id    = `ENTRY_NULL;
                next_eip    = opcode_eip_latch + 32'h1;
            end
            default: ;
        endcase
    end

    // ----------------------------------------------------------------
    // Observability signals (visible in simulation for debug)
    // ----------------------------------------------------------------
    // synthesis translate_off
    logic [7:0] dbg_last_opcode_byte;
    always_ff @(posedge clk) begin
        if (state == DEC_CONSUME && q_valid)
            dbg_last_opcode_byte <= q_data;
    end
    // synthesis translate_on

endmodule
