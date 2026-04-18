// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 3: CALL/RET control-transfer serialization
// (includes all Rung 2 JMP behavior)
//
// Ownership (Appendix B):
//   This module owns: uPC management, entry dispatch, microinstruction
//   fetch and decode, RAISE, ENDI, return to FETCH_DECODE,
//   accepted-control-packet policy, squash issuance on control-transfer.
//   This module must NOT: own instruction meaning, bypass dispatch,
//   make redirect architecturally visible (that is commit_engine's job).
//
// Rung 3 additions:
//
//   CALL direct (E8): has_target_r=1, is_call_r=1
//     - squash issued (same as JMP)
//     - ctrl_transfer_pending set
//     - pc_target_en/val staged (call target)
//     - pc_ret_addr_en/val staged (next_eip_r = return address to push)
//
//   CALL indirect (FF /2): has_target_r=0, is_call_r=1
//     - squash issued
//     - ctrl_transfer_pending set
//     - pc_ret_addr_en/val staged (next_eip_r = return address to push)
//     - pc_target_en NOT staged — commit_engine reads register via modrm_r
//     - modrm_r forwarded so commit can resolve register source
//
//   RET (C3/C2): is_ret_r=1
//     - squash issued
//     - ctrl_transfer_pending set
//     - pc_ret_imm_en / pc_ret_imm_val staged (for C2 stack adjustment)
//     - target EIP comes from stack pop in commit_engine; committed at ENDI
//
// All Rung 2 contracts preserved:
//   Contract 2 — decode result accepted only on dec_ack
//   Contract 3 — squash on control-transfer acceptance
//   Contract 4 — commit_engine is sole redirect visibility authority
//
// Dispatch sequence (unchanged timing from Rung 2).
//
// Shared constants: MSEQ_* state codes and ENTRY_RESET from keystone86_pkg.

import keystone86_pkg::*;

module microsequencer (
    input  logic        clk,
    input  logic        reset_n,

    // --- Decoder interface ---
    input  logic        decode_done,
    input  logic [7:0]  entry_id_in,
    input  logic [31:0] next_eip_in,
    input  logic [31:0] target_eip_in,
    input  logic        has_target_in,
    input  logic        is_call_in,        // Rung 3
    input  logic        is_ret_in,         // Rung 3
    input  logic        has_ret_imm_in,    // Rung 3
    input  logic [15:0] ret_imm_in,        // Rung 3
    input  logic [7:0]  modrm_in,          // Rung 3
    output logic        dec_ack,

    // --- Squash output (to decoder + prefetch_queue) ---
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

    // --- EIP staging (fall-through) ---
    output logic        pc_eip_en,
    output logic [31:0] pc_eip_val,

    // --- Target EIP staging (JMP/CALL-direct target) ---
    output logic        pc_target_en,
    output logic [31:0] pc_target_val,

    // --- Return address staging (Rung 3: pushed by CALL) ---
    output logic        pc_ret_addr_en,
    output logic [31:0] pc_ret_addr_val,

    // --- RET imm16 staging (Rung 3: C2 stack adjustment) ---
    output logic        pc_ret_imm_en,
    output logic [15:0] pc_ret_imm_val,

    // --- Observability ---
    output logic [1:0]  dbg_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id
);

    localparam logic [3:0] UOP_NOP   = 4'h0;
    localparam logic [3:0] UOP_RAISE = 4'hC;
    localparam logic [3:0] UOP_ENDI  = 4'hE;

    logic [1:0]  state,      state_next;
    logic [11:0] upc_r,      upc_next;
    logic [7:0]  entry_id_r;
    logic [31:0] next_eip_r;
    logic [31:0] target_eip_r;
    logic        has_target_r;
    logic        is_call_r;
    logic        is_ret_r;
    logic        has_ret_imm_r;
    logic [15:0] ret_imm_r;
    logic [7:0]  modrm_r;

    // Dispatch handshake
    logic        dispatch_rom_pending;
    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;
    logic        execute_fetch_pending;

    // Control-transfer serialization
    logic        ctrl_transfer_pending;
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
            entry_id_r            <= ENTRY_RESET;
            next_eip_r            <= 32'h0;
            target_eip_r          <= 32'h0;
            has_target_r          <= 1'b0;
            is_call_r             <= 1'b0;
            is_ret_r              <= 1'b0;
            has_ret_imm_r         <= 1'b0;
            ret_imm_r             <= 16'h0;
            modrm_r               <= 8'h0;
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

            squash_r <= 1'b0;   // one-cycle pulse: clear every cycle

            case (state)
                // ----------------------------------------------------------
                // FETCH_DECODE: three-phase dispatch handshake
                // ----------------------------------------------------------
                MSEQ_FETCH_DECODE: begin
                    // Phase 1: latch decode payload, start ROM read
                    if (decode_done && !dispatch_rom_pending && !dispatch_pending
                        && !ctrl_transfer_pending) begin
                        entry_id_r           <= entry_id_in;
                        next_eip_r           <= next_eip_in;
                        target_eip_r         <= target_eip_in;
                        has_target_r         <= has_target_in;
                        is_call_r            <= is_call_in;
                        is_ret_r             <= is_ret_in;
                        has_ret_imm_r        <= has_ret_imm_in;
                        ret_imm_r            <= ret_imm_in;
                        modrm_r              <= modrm_in;
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

                    // Phase 3: dispatch
                    if (dispatch_pending) begin
                        dispatch_pending      <= 1'b0;
                        execute_fetch_pending <= 1'b1;

                        // CALL or RET: squash + hold front end
                        // has_target_r for direct CALL/JMP; is_call_r/is_ret_r for all
                        if (has_target_r || is_call_r || is_ret_r) begin
                            squash_r              <= 1'b1;
                            ctrl_transfer_pending <= 1'b1;
                        end
                    end

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
        state_next       = state;
        upc_next         = upc_r;
        dec_ack          = 1'b0;
        endi_req         = 1'b0;
        endi_mask        = 10'h0;
        raise_req        = 1'b0;
        raise_fc         = 4'h0;
        raise_fe         = 32'h0;
        pc_eip_en        = 1'b0;
        pc_eip_val       = 32'h0;
        pc_target_en     = 1'b0;
        pc_target_val    = 32'h0;
        pc_ret_addr_en   = 1'b0;
        pc_ret_addr_val  = 32'h0;
        pc_ret_imm_en    = 1'b0;
        pc_ret_imm_val   = 16'h0;

        case (state)
            // ----------------------------------------------------------
            // FETCH_DECODE
            // ----------------------------------------------------------
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;

                    // Stage fall-through EIP (always valid)
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;

                    // Stage call/jmp target (direct only)
                    if (has_target_r) begin
                        pc_target_en  = 1'b1;
                        pc_target_val = target_eip_r;
                    end

                    // Rung 3: CALL — stage return address (= next_eip_r)
                    if (is_call_r) begin
                        pc_ret_addr_en  = 1'b1;
                        pc_ret_addr_val = next_eip_r;
                    end

                    // Rung 3: RET imm16 — stage stack adjustment
                    if (is_ret_r && has_ret_imm_r) begin
                        pc_ret_imm_en  = 1'b1;
                        pc_ret_imm_val = ret_imm_r;
                    end
                end
            end

            // ----------------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------------
            MSEQ_EXECUTE: begin
                if (execute_fetch_pending) begin
                    // fetch stall
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
