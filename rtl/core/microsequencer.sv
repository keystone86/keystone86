// Keystone86 / Aegis
// rtl/core/microsequencer.sv
// Rung 1: EIP staging added for NOP advancement
//
// Ownership (Appendix B):
//   This module owns: uPC management, entry dispatch, microinstruction
//   fetch and decode (Rung 0/1 subset), RAISE, ENDI, return to FETCH_DECODE.
//   This module must NOT: own instruction meaning, bypass dispatch,
//   let instruction policy leak into non-microcode logic.
//
// Rung 1 change from Rung 0:
//   - Added pc_eip_en and pc_eip_val output ports
//   - When transitioning from FETCH_DECODE->EXECUTE (dec_ack cycle),
//     microsequencer stages next_eip_r into commit_engine via these ports.
//   - This allows ENDI CM_NOP|CM_EIP to commit visible EIP for NOP.
//   - No change to state machine, uPC logic, or microinstruction decode.
//
// Rung 0/1 microinstruction subset:
//   RAISE  (0xC) — stage fault class
//   ENDI   (0xE) — end instruction, apply commit mask
//   NOP    (0x0) — no operation, advance uPC

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
    output logic        pc_eip_en,          // stage EIP into commit_engine
    output logic [31:0] pc_eip_val,         // EIP value to stage

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

    logic        dispatch_pending;
    logic [7:0]  dispatch_entry_latch;

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
            state                <= MSEQ_FETCH_DECODE;
            upc_r                <= 12'h000;
            entry_id_r           <= `ENTRY_RESET;
            next_eip_r           <= 32'h0;
            dispatch_pending     <= 1'b0;
            dispatch_entry_latch <= 8'h00;
            fault_pending        <= 1'b0;
            fault_class          <= 4'h0;
        end else begin
            state <= state_next;
            upc_r <= upc_next;

            case (state)
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

                MSEQ_EXECUTE: begin
                    dispatch_pending <= 1'b0;
                    case (uop_class)
                        UOP_RAISE: begin
                            fault_pending <= 1'b1;
                            fault_class   <= uop_target_fc;
                        end
                        default: ;
                    endcase
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
        pc_eip_en   = 1'b0;        // Rung 1: default no staging
        pc_eip_val  = 32'h0;

        case (state)
            // ----------------------------------------------------------
            // FETCH_DECODE
            // ----------------------------------------------------------
            MSEQ_FETCH_DECODE: begin
                if (dispatch_pending) begin
                    dec_ack    = 1'b1;
                    upc_next   = dispatch_upc_in;
                    state_next = MSEQ_EXECUTE;
                    // Rung 1: stage EIP on the cycle we dispatch.
                    // next_eip_r was latched when decode_done arrived.
                    // This puts the value into commit_engine's staging
                    // register so ENDI CM_NOP|CM_EIP can commit it.
                    pc_eip_en  = 1'b1;
                    pc_eip_val = next_eip_r;
                end
            end

            // ----------------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------------
            MSEQ_EXECUTE: begin
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

            // ----------------------------------------------------------
            // FAULT_HOLD
            // ----------------------------------------------------------
            MSEQ_FAULT_HOLD: begin
                state_next = MSEQ_EXECUTE;
                upc_next   = upc_r;
            end

            // ----------------------------------------------------------
            // WAIT_SERVICE: reserved, not used in Rung 0/1
            // ----------------------------------------------------------
            MSEQ_WAIT_SERVICE: begin
                state_next = MSEQ_FETCH_DECODE;
            end

            default: state_next = MSEQ_FETCH_DECODE;
        endcase
    end

endmodule
