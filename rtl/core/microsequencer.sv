// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 2: Control-transfer serialization + stale-work squash
//
// Ownership (Appendix B):
//   This module owns: uPC management, entry dispatch, microinstruction
//   fetch and decode, RAISE, ENDI, return to FETCH_DECODE,
//   accepted-control-packet policy, squash issuance on control-transfer.
//   This module must NOT: own instruction meaning, bypass dispatch,
//   make redirect architecturally visible (that is commit_engine's job).
//
// Rung 2 additions:
//
//   Contract 2 — Real decode/control acceptance boundary:
//     decode result becomes the active instruction ONLY on dec_ack.
//     This was already implicit in Rung 1 via the three-phase handshake.
//     Rung 2 makes it explicit by gating all control-transfer behavior
//     on the dispatch cycle (when dispatch_pending fires and dec_ack is
//     issued). Before dec_ack, the decode payload is not yet accepted.
//
//   Contract 3 — Stale-work suppression (squash):
//     Once a control-transfer decode payload is accepted (dec_ack cycle),
//     microsequencer asserts squash=1 for one cycle. This kills:
//       - decoder in-formation state
//       - prefetch queue inflight work
//     The machine then holds the front end until commit_engine issues
//     flush (which happens at ENDI with CM_JMP mask). The queue will be
//     flushed and re-pointed to the JMP target by commit_engine.
//
//   Contract 4 — Commit-owned redirect visibility:
//     Microsequencer knows a redirect is coming (ctrl_transfer_pending)
//     but does NOT make it architecturally visible. It issues squash and
//     holds upstream. commit_engine makes redirect real via flush_req.
//     After ENDI fires, microsequencer returns to FETCH_DECODE and the
//     machine resumes from the new EIP.
//
//   Front-end hold during control transfer:
//     When ctrl_transfer_pending=1, decode_done is ignored even if the
//     prefetch queue presents bytes. This prevents old-path decode work
//     from entering dispatch while the redirect is in flight.
//     Once commit_engine completes ENDI (endi_done), the hold is cleared.
//
// ROM timing model (unchanged from Rung 1):
//   Two-cycle dispatch handshake: dispatch_rom_pending -> dispatch_pending.
//   One-cycle execute stall: execute_fetch_pending.
//
// Dispatch sequence (N = cycle where decode_done arrives):
//   Cycle N:   latch decode payload, set dispatch_rom_pending
//   Cycle N+1: ROM settling, set dispatch_pending
//   Cycle N+2: dispatch — dec_ack, upc=dispatch_upc_in, squash if ctrl
//   Cycle N+3: EXECUTE stall (execute_fetch_pending)
//   Cycle N+4: EXECUTE active — process microinstruction

`include "entry_ids.svh"
`include "fault_defs.svh"
`include "commit_defs.svh"
`include "field_defs.svh"

module microsequencer (
    input  logic        clk,
    input  logic        reset_n,

    // --- Decoder interface ---
    input  logic        decode_done,
    input  logic [7:0]  entry_id_in,
    input  logic [31:0] next_eip_in,
    input  logic [31:0] target_eip_in,     // Rung 2: JMP target
    input  logic        has_target_in,     // Rung 2: target is valid
    output logic        dec_ack,

    // --- Squash output (to decoder + prefetch_queue) ---
    output logic        squash,            // Rung 2: stale-work kill

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

    // --- EIP staging (Rung 1+) ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,

    // --- Target EIP staging (Rung 2: JMP target) ---
    output logic        pc_target_en,
    output logic [31:0] pc_target_val,

    // --- Observability ---
    output logic [1:0]  dbg_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id
);

    localparam logic [1:0] MSEQ_FETCH_DECODE = 2'h0;
    localparam logic [1:0] MSEQ_EXECUTE      = 2'h1;
    localparam logic [1:0] MSEQ_WAIT_SERVICE = 2'h2;
    localparam logic [1:0] MSEQ_FAULT_HOLD   = 2'h3;

    localparam logic [3:0] UOP_NOP   = 4'h0;
    localparam logic [3:0] UOP_RAISE = 4'hC;
    localparam logic [3:0] UOP_ENDI  = 4'hE;

    logic [1:0]  state,      state_next;
    logic [11:0] upc_r,      upc_next;
    logic [7:0]  entry_id_r;
    logic [31:0] next_eip_r;
    logic [31:0] target_eip_r;
    logic        has_target_r;

    // Dispatch handshake
    logic        dispatch_rom_pending;
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;
    logic        execute_fetch_pending;

    // Rung 2: control-transfer serialization
    // Set when a control-transfer (JMP) decode payload is accepted.
    // Cleared when ENDI completes (commit makes redirect real).
    logic        ctrl_transfer_pending;

    // Rung 2: squash pulse — one cycle on control-transfer acceptance
    logic        squash_r;

    logic        fault_pending;
    logic [3:0]  fault_class;

    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;
    assign dbg_state      = state;
    assign dbg_upc        = upc_r;
    assign dbg_entry_id   = entry_id_r;
    assign squash         = squash_r;

    logic [3:0]  uop_class;
    logic [9:0]  uop_imm10;
    logic [3:0]  uop_target_fc;

    assign uop_class     = uinst[31:28];
    assign uop_imm10     = uinst[9:0];
    assign uop_target_fc = uinst[25:22];

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state                 <= MSEQ_FETCH_DECODE;
            upc_r                 <= 12'h000;
            entry_id_r            <= `ENTRY_RESET;
            next_eip_r            <= 32'h0;
            target_eip_r          <= 32'h0;
            has_target_r          <= 1'b0;
            dispatch_rom_pending  <= 1'b0;
            dispatch_pending      <= 1'b0;
            dispatch_entry_latch  <= 8'h00;
            execute_fetch_pending <= 1'b0;
            fault_pending         <= 1'b0;
            fault_class           <= 4'h0;
            ctrl_transfer_pending <= 1'b0;
            squash_r              <= 1'b0;
        end else begin
            state <= state_next;
            upc_r <= upc_next;

            // Squash is a one-cycle pulse — clear it every cycle
            squash_r <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                // FETCH_DECODE: three-phase dispatch handshake
                // ----------------------------------------------------------
                MSEQ_FETCH_DECODE: begin
                    // Phase 1: latch decode payload, start ROM read
                    // Gate on ctrl_transfer_pending: do NOT accept new decode
                    // while a control transfer is in flight (Contract 3).
                    if (decode_done && !dispatch_rom_pending && !dispatch_pending
                        && !ctrl_transfer_pending) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        target_eip_r         <= target_eip_in;
                        has_target_r         <= has_target_in;
                        dispatch_entry_latch <= entry_id_in;
                        dispatch_rom_pending <= 1'b1;
                        fault_pending        <= 1'b0;
                        fault_class          <= 4'h0;
                    end

                    // Phase 2: ROM settling
                    if (dispatch_rom_pending) begin
                        dispatch_rom_pending <= 1'b0;
                        dispatch_pending     <= 1'b1;
                    end

                    // Phase 3: dispatch (handled in comb block for dec_ack/upc)
                    if (dispatch_pending) begin
                        dispatch_pending      <= 1'b0;
                        execute_fetch_pending <= 1'b1;

                        // Rung 2: if this is a control-transfer instruction,
                        // assert squash for one cycle and set ctrl_transfer_pending.
                        // has_target_r is set by decoder for JMP instructions.
                        if (has_target_r) begin
                            squash_r              <= 1'b1;   // kill decoder + queue
                            ctrl_transfer_pending <= 1'b1;   // hold front end
                        end
                    end

                    // Clear ctrl_transfer_pending after ENDI completes
                    // (endi_done fires from commit_engine on ENDI processing)
                    if (ctrl_transfer_pending && endi_done) begin
                        ctrl_transfer_pending <= 1'b0;
                    end
                end

                // ----------------------------------------------------------
                // EXECUTE
                // ----------------------------------------------------------
                MSEQ_EXECUTE: begin
                    if (execute_fetch_pending)
                        execute_fetch_pending <= 1'b0;

                    if (!execute_fetch_pending) begin
                        case (uop_class)
                            UOP_RAISE: begin
                                fault_pending <= 1'b1;
                                fault_class   <= uop_target_fc;
                            end
                            default: ;
                        endcase
                    end

                    // Clear ctrl_transfer_pending when ENDI completes
                    if (ctrl_transfer_pending && endi_done) begin
                        ctrl_transfer_pending <= 1'b0;
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
    // Combinational: next-state, uPC, and output logic
    // ----------------------------------------------------------------
    always_comb begin
        state_next     = state;
        upc_next       = upc_r;
        dec_ack        = 1'b0;
        endi_req       = 1'b0;
        endi_mask      = 10'h0;
        raise_req      = 1'b0;
        raise_fc       = 4'h0;
        raise_fe       = 32'h0;
        pc_eip_en      = 1'b0;
        pc_eip_val     = 32'h0;
        pc_target_en   = 1'b0;
        pc_target_val  = 32'h0;

        case (state)
            // ----------------------------------------------------------
            // FETCH_DECODE
            // ----------------------------------------------------------
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;

                    // Stage EIP for commit_engine
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;

                    // Rung 2: if control transfer, also stage target EIP
                    if (has_target_r) begin
                        pc_target_en  = 1'b1;
                        pc_target_val = target_eip_r;
                    end
                end
            end

            // ----------------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------------
            MSEQ_EXECUTE: begin
                if (execute_fetch_pending) begin
                    // Fetch stall: uinst is stale; do nothing
                end else begin
                    case (uop_class)
                        UOP_NOP: begin
                            upc_next = upc_r + 12'h1;
                        end

                        UOP_RAISE: begin
                            raise_req  = 1'b1;
                            raise_fc   = uop_target_fc;
                            raise_fe   = 32'h0;
                            upc_next   = upc_r + 12'h1;
                            state_next = MSEQ_FAULT_HOLD;
                        end

                        UOP_ENDI: begin
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

            // ----------------------------------------------------------
            // FAULT_HOLD
            // ----------------------------------------------------------
            MSEQ_FAULT_HOLD: begin
                state_next = MSEQ_EXECUTE;
                upc_next   = upc_r;
            end

            // ----------------------------------------------------------
            // WAIT_SERVICE: reserved
            // ----------------------------------------------------------
            MSEQ_WAIT_SERVICE: begin
                state_next = MSEQ_FETCH_DECODE;
            end

            default: state_next = MSEQ_FETCH_DECODE;
        endcase
    end

endmodule
