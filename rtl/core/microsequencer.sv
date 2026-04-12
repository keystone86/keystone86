// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 1: Correct ROM timing for dispatch and microinstruction fetch
//
// Ownership (Appendix B):
//   This module owns: uPC management, entry dispatch, microinstruction
//   fetch and decode (Rung 0/1 subset), RAISE, ENDI, return to FETCH_DECODE.
//   This module must NOT: own instruction meaning, bypass dispatch,
//   let instruction policy leak into non-microcode logic.
//
// ROM timing model:
//   microcode_rom has registered outputs for BOTH dispatch_upc and uinst.
//   Both have 1-cycle latency: the ROM samples its address input at the rising
//   edge and produces the output on the next rising edge.
//
// Two timing hazards, both fixed here:
//
//   Hazard 1 — dispatch address (fixed in prior pass):
//     Setting dispatch_entry_latch and dispatch_pending in the same cycle as
//     decode_done meant the ROM sampled the OLD dispatch_entry (from the
//     previous instruction). Fix: two-cycle dispatch handshake via
//     dispatch_rom_pending -> dispatch_pending.
//
//   Hazard 2 — microinstruction fetch (fixed in this pass):
//     On the dispatch cycle, upc_next = dispatch_upc_in and state_next = EXECUTE
//     are set. upc_r gets the new value at end of that cycle. But the ROM clocks
//     uinst from the OLD upc_r (the one it saw BEFORE the update). So the first
//     EXECUTE cycle has a stale uinst from the previous upc (typically 0x000 =
//     ENDI CM_FAULT_END). This stale ENDI processes without CM_EIP, clearing
//     pc_eip_en_r before the real ENDI CM_NOP|CM_EIP can use it.
//     Fix: execute_fetch_pending flag. When entering EXECUTE, stall for one
//     cycle before consuming uinst, allowing the ROM to register the correct word.
//
// Correct dispatch + execute sequence (N = cycle where decode_done arrives):
//   Cycle N:   decode_done: latch entry_id, dispatch_entry_latch, set dispatch_rom_pending
//   Cycle N+1: ROM settling: set dispatch_pending
//   Cycle N+2: dispatch: dec_ack, upc_next=dispatch_upc_in, set execute_fetch_pending
//   Cycle N+3: EXECUTE stall: uinst is stale from old upc, do not process
//   Cycle N+4: EXECUTE active: uinst = correct microinstruction, process it
//
// Rung 1 addition:
//   pc_eip_en/pc_eip_val staged at the dispatch cycle (N+2) so commit_engine
//   has pc_eip_en_r=1 before ENDI CM_NOP|CM_EIP fires at cycle N+4.

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
    output logic        dec_ack,

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

    // --- EIP staging (Rung 1) ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,

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

    // Dispatch handshake (two-cycle to handle ROM registered output):
    logic        dispatch_rom_pending;  // cycle N+1: ROM settling
    logic        dispatch_pending;      // cycle N+2: dispatch_upc_in valid
    logic [7:0]  dispatch_entry_latch;

    // Microinstruction fetch stall (one cycle after EXECUTE entry):
    logic        execute_fetch_pending; // =1: uinst stale, wait one cycle

    logic        fault_pending;
    logic [3:0]  fault_class;

    assign upc            = upc_r;
    assign dispatch_entry = dispatch_entry_latch;
    assign dbg_state      = state;
    assign dbg_upc        = upc_r;
    assign dbg_entry_id   = entry_id_r;

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
            dispatch_rom_pending  <= 1'b0;
            dispatch_pending      <= 1'b0;
            dispatch_entry_latch  <= 8'h00;
            execute_fetch_pending <= 1'b0;
            fault_pending         <= 1'b0;
            fault_class           <= 4'h0;
        end else begin
            state <= state_next;
            upc_r <= upc_next;

            case (state)
                // ----------------------------------------------------------
                // FETCH_DECODE: three-phase dispatch handshake
                // ----------------------------------------------------------
                MSEQ_FETCH_DECODE: begin
                    // Phase 1 (cycle N): latch decode, start ROM read
                    if (decode_done && !dispatch_rom_pending && !dispatch_pending) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        dispatch_entry_latch <= entry_id_in;
                        dispatch_rom_pending <= 1'b1;
                        fault_pending        <= 1'b0;
                        fault_class          <= 4'h0;
                    end
                    // Phase 2 (cycle N+1): ROM settling
                    if (dispatch_rom_pending) begin
                        dispatch_rom_pending <= 1'b0;
                        dispatch_pending     <= 1'b1;
                    end
                    // Phase 3 (cycle N+2): dispatch — comb block handles transition
                    if (dispatch_pending) begin
                        dispatch_pending      <= 1'b0;
                        execute_fetch_pending <= 1'b1;  // EXECUTE will stall one cycle
                    end
                end

                // ----------------------------------------------------------
                // EXECUTE: clear fetch stall, then process microinstructions
                // ----------------------------------------------------------
                MSEQ_EXECUTE: begin
                    // Clear fetch stall flag on entry
                    if (execute_fetch_pending)
                        execute_fetch_pending <= 1'b0;

                    // Only latch fault state when actually executing (not stalling)
                    if (!execute_fetch_pending) begin
                        case (uop_class)
                            UOP_RAISE: begin
                                fault_pending <= 1'b1;
                                fault_class   <= uop_target_fc;
                            end
                            default: ;
                        endcase
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
        state_next  = state;
        upc_next    = upc_r;
        dec_ack     = 1'b0;
        endi_req    = 1'b0;
        endi_mask   = 10'h0;
        raise_req   = 1'b0;
        raise_fc    = 4'h0;
        raise_fe    = 32'h0;
        pc_eip_en   = 1'b0;
        pc_eip_val  = 32'h0;

        case (state)
            // ----------------------------------------------------------
            // FETCH_DECODE
            // ----------------------------------------------------------
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    // Dispatch cycle: dispatch_upc_in is valid.
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;
                    // Stage EIP for commit_engine so ENDI CM_NOP|CM_EIP can use it.
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;
                end
            end

            // ----------------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------------
            MSEQ_EXECUTE: begin
                if (execute_fetch_pending) begin
                    // Fetch stall cycle: uinst is stale from previous upc.
                    // Do nothing — ROM is loading the correct uinst this cycle.
                    // upc_next = upc_r (hold) — no advancement.
                end else begin
                    // uinst is valid. Process the microinstruction.
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
                // uinst for the NEXT upc was already valid (RAISE advanced upc by 1
                // in the prior cycle, and the ROM had that cycle to register it).
                // No fetch stall needed here.
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