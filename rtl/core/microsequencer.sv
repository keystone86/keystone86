// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 0: Microsequencer — the control center
//
// Ownership (Appendix B):
//   This module owns: uPC management, entry dispatch, microinstruction
//   fetch and decode (Rung 0 subset), RAISE, ENDI, return to FETCH_DECODE.
//   This module must NOT: own instruction meaning, bypass the dispatch
//   table, let instruction policy leak into non-microcode logic.
//
// Rung 0 microinstruction subset supported:
//   RAISE  (UOP_CLASS = 0xC) — stage fault class
//   ENDI   (UOP_CLASS = 0xE) — end instruction, apply commit mask
//   NOP    (UOP_CLASS = 0x0) — no operation, advance uPC
//
// All other UOP_CLASS values are treated as NOP in Rung 0.
// This is safe because the bootstrap ROM only contains RAISE and ENDI.
//
// Microsequencer states (all four defined per spec):
//   FETCH_DECODE  — waiting for decoder decode_done
//   EXECUTE       — running microcode, one uinst per clock
//   WAIT_SERVICE  — stalled on SVCW (not used in Rung 0 bootstrap)
//   FAULT_HOLD    — fault staged (used briefly in RAISE path)

`include "entry_ids.svh"
`include "fault_defs.svh"
`include "commit_defs.svh"
`include "field_defs.svh"

module microsequencer (
    input  logic        clk,
    input  logic        reset_n,

    // --- Decoder interface ---
    input  logic        decode_done,        // decoder has an instruction ready
    input  logic [7:0]  entry_id_in,        // ENTRY_* from decoder
    input  logic [31:0] next_eip_in,        // next EIP from decoder
    output logic        dec_ack,            // acknowledge to decoder

    // --- Microcode ROM interface ---
    output logic [11:0] upc,                // current micro-PC to ROM
    input  logic [31:0] uinst,              // microinstruction from ROM (1 cycle latency)
    output logic [7:0]  dispatch_entry,     // entry_id to dispatch table
    input  logic [11:0] dispatch_upc_in,    // dispatch result from ROM (1 cycle latency)

    // --- Commit engine interface ---
    output logic        endi_req,           // end-of-instruction request
    output logic [9:0]  endi_mask,          // commit mask for this ENDI
    output logic        raise_req,          // fault is being raised
    output logic [3:0]  raise_fc,           // fault class for RAISE
    output logic [31:0] raise_fe,           // fault error code (zero for bootstrap)
    input  logic        endi_done,          // commit engine finished ENDI

    // --- Observability ---
    output logic [1:0]  dbg_state,          // current sequencer state
    output logic [11:0] dbg_upc,            // current uPC
    output logic [7:0]  dbg_entry_id        // current entry being executed
);

    // ----------------------------------------------------------------
    // State encoding (all four spec states, per keystone86_pkg.sv)
    // ----------------------------------------------------------------
    localparam logic [1:0] MSEQ_FETCH_DECODE = 2'h0;
    localparam logic [1:0] MSEQ_EXECUTE      = 2'h1;
    localparam logic [1:0] MSEQ_WAIT_SERVICE = 2'h2;  // reserved Rung 0
    localparam logic [1:0] MSEQ_FAULT_HOLD   = 2'h3;  // used briefly by RAISE

    // ----------------------------------------------------------------
    // UOP_CLASS encoding (from Appendix A Section 7.2)
    // ----------------------------------------------------------------
    localparam logic [3:0] UOP_NOP   = 4'h0;
    localparam logic [3:0] UOP_RAISE = 4'hC;
    localparam logic [3:0] UOP_ENDI  = 4'hE;

    // ----------------------------------------------------------------
    // Registers
    // ----------------------------------------------------------------
    logic [1:0]  state,      state_next;
    logic [11:0] upc_r,      upc_next;
    logic [7:0]  entry_id_r;
    logic [31:0] next_eip_r;

    // Dispatch handshake: we need 1 extra cycle for ROM lookup
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;

    // RAISE staging
    logic        fault_pending;
    logic [3:0]  fault_class;

    // ----------------------------------------------------------------
    // uPC and dispatch_entry drive ROM
    // ----------------------------------------------------------------
    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;

    // ----------------------------------------------------------------
    // Observability
    // ----------------------------------------------------------------
    assign dbg_state    = state;
    assign dbg_upc      = upc_r;
    assign dbg_entry_id = entry_id_r;

    // ----------------------------------------------------------------
    // Microinstruction field decode (from 32-bit uinst)
    // Appendix A Section 7.1:
    //   bits[31:28] = UOP_CLASS
    //   bits[27:22] = TARGET (6 bits)
    //   bits[21:18] = COND   (4 bits)
    //   bits[17:14] = DST    (4 bits)
    //   bits[13:10] = SRC    (4 bits)
    //   bits[9:0]   = IMM10/SUBOP
    // ----------------------------------------------------------------
    logic [3:0]  uop_class;
    logic [9:0]  uop_imm10;
    logic [3:0]  uop_target_fc; // lower 4 bits of TARGET = fault class for RAISE

    assign uop_class     = uinst[31:28];
    assign uop_imm10     = uinst[9:0];
    assign uop_target_fc = uinst[25:22];  // bits[25:22] of TARGET field

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= MSEQ_FETCH_DECODE;
            upc_r             <= 12'h000;
            entry_id_r        <= `ENTRY_RESET;
            next_eip_r        <= 32'h0;
            dispatch_pending  <= 1'b0;
            dispatch_entry_latch <= 8'h00;
            fault_pending     <= 1'b0;
            fault_class       <= 4'h0;
        end else begin
            state  <= state_next;
            upc_r  <= upc_next;

            case (state)
                // ------------------------------------------------------
                // FETCH_DECODE: latch decode result, start dispatch
                // ------------------------------------------------------
                MSEQ_FETCH_DECODE: begin
                    if (decode_done) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        dispatch_entry_latch <= entry_id_in;
                        dispatch_pending     <= 1'b1;
                        fault_pending        <= 1'b0;
                        fault_class          <= 4'h0;
                    end
                end

                // ------------------------------------------------------
                // EXECUTE: process microinstruction
                // Sequential block only handles state that must be latched.
                // Control flow (state_next, upc_next) is in the comb block.
                // ------------------------------------------------------
                MSEQ_EXECUTE: begin
                    dispatch_pending <= 1'b0;

                    case (uop_class)
                        UOP_RAISE: begin
                            // Stage fault — combinational block handles
                            // RAISE output and state transition to FAULT_HOLD
                            fault_pending <= 1'b1;
                            fault_class   <= uop_target_fc;
                        end
                        // UOP_ENDI: no sequential action needed.
                        // Combinational block drives endi_req and waits
                        // for endi_done before transitioning.
                        // UOP_NOP and all others: advance uPC in comb block.
                        default: ;
                    endcase
                end

                // ------------------------------------------------------
                // FAULT_HOLD: fault staged.
                // Return to EXECUTE on next cycle to process ENDI.
                // fault_pending is cleared by commit_engine at ENDI with CLRF.
                // ------------------------------------------------------
                MSEQ_FAULT_HOLD: begin
                    // No sequential action — comb block returns to EXECUTE
                end

                default: ;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Next-state and uPC logic
    // ----------------------------------------------------------------
    always_comb begin
        state_next = state;
        upc_next   = upc_r;
        dec_ack    = 1'b0;
        endi_req   = 1'b0;
        endi_mask  = 10'h0;
        raise_req  = 1'b0;
        raise_fc   = 4'h0;
        raise_fe   = 32'h0;

        case (state)
            // ----------------------------------------------------------
            // FETCH_DECODE: wait for decoder, then dispatch
            // ----------------------------------------------------------
            MSEQ_FETCH_DECODE: begin
                if (decode_done && !dispatch_pending) begin
                    // First cycle: latch entry, start dispatch ROM read
                    // (dispatch_pending set in sequential block above)
                end
                if (dispatch_pending) begin
                    // Second cycle: dispatch_upc_in is valid from ROM
                    // Transition to EXECUTE, set uPC to dispatch result
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;
                end
            end

            // ----------------------------------------------------------
            // EXECUTE: run one microinstruction per clock
            // ----------------------------------------------------------
            MSEQ_EXECUTE: begin
                case (uop_class)
                    UOP_NOP: begin
                        upc_next = upc_r + 12'h1;
                    end

                    UOP_RAISE: begin
                        // Stage the fault class; advance uPC
                        raise_req  = 1'b1;
                        raise_fc   = uop_target_fc;
                        raise_fe   = 32'h0;
                        upc_next   = upc_r + 12'h1;
                        state_next = MSEQ_FAULT_HOLD;
                    end

                    UOP_ENDI: begin
                        // Issue ENDI with commit mask from IMM10
                        endi_req   = 1'b1;
                        endi_mask  = uop_imm10;
                        // Wait for endi_done before returning to FETCH_DECODE
                        if (endi_done) begin
                            upc_next   = 12'h000;
                            state_next = MSEQ_FETCH_DECODE;
                        end
                    end

                    default: begin
                        // All other uop_class values: treat as NOP in Rung 0
                        upc_next = upc_r + 12'h1;
                    end
                endcase
            end

            // ----------------------------------------------------------
            // FAULT_HOLD: fault staged, expecting ENDI next
            // ----------------------------------------------------------
            MSEQ_FAULT_HOLD: begin
                // In bootstrap ROM: RAISE is always followed immediately by ENDI
                // so we stay in FAULT_HOLD for one cycle then resume EXECUTE
                // to process the ENDI microinstruction
                state_next = MSEQ_EXECUTE;
                upc_next   = upc_r;  // uPC was already advanced by RAISE
            end

            // ----------------------------------------------------------
            // WAIT_SERVICE: not used in Rung 0 bootstrap
            // ----------------------------------------------------------
            MSEQ_WAIT_SERVICE: begin
                // Never entered in Rung 0. Reserved for Rung 5+.
                state_next = MSEQ_FETCH_DECODE;
            end

            default: state_next = MSEQ_FETCH_DECODE;
        endcase
    end

endmodule
