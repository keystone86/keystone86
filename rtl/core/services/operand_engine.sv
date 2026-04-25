// Keystone86 / Aegis
// rtl/core/services/operand_engine.sv
//
// Bounded Rung 3 operand service.
//
// Owns only the active indirect CALL register-form target load needed for
// FF /2 verification. It does not classify ModRM or decide instruction
// meaning; decoder/microcode decide when LOAD_RM* is the right service.

import keystone86_pkg::*;

module operand_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] indirect_call_target,
    input  logic        indirect_call_target_valid,

    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data
);

    logic        complete_pending_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t2_wr_en_r;
    logic [31:0] complete_t2_wr_data_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;
        end else begin
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;

            if (svc_req) begin
                unique case (svc_id)
                    LOAD_RM16,
                    LOAD_RM32: begin
                        complete_pending_r <= 1'b1;
                        if (indirect_call_target_valid) begin
                            complete_sr_r         <= SR_OK;
                            complete_t2_wr_en_r   <= 1'b1;
                            complete_t2_wr_data_r <= indirect_call_target;
                        end else begin
                            complete_sr_r <= SR_FAULT;
                        end
                    end

                    default: begin
                        complete_pending_r <= 1'b1;
                        complete_sr_r      <= SR_FAULT;
                    end
                endcase
            end
        end
    end

    always_comb begin
        svc_done   = complete_pending_r;
        svc_sr     = complete_pending_r ? complete_sr_r : SR_WAIT;
        t2_wr_en   = complete_pending_r ? complete_t2_wr_en_r : 1'b0;
        t2_wr_data = complete_t2_wr_data_r;
    end

endmodule
