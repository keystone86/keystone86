// Keystone86 / Aegis
// rtl/core/services/flow_control.sv
//
// Current phase support:
//   COMPUTE_REL_TARGET
//   VALIDATE_NEAR_TRANSFER
//
// CONDITION_EVAL is stubbed as SR_FAULT for now because it is not part of
// the active Rung 2 path.

import keystone86_pkg::*;

module flow_control (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] t2_in,
    input  logic [31:0] t4_in,
    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data,

    input  logic [31:0] m_next_eip,
    input  logic        mode_prot,

    output logic        fault_req,
    output logic [3:0]  fault_fc
);

    always_comb begin
        svc_done   = 1'b0;
        svc_sr     = SR_WAIT;
        t2_wr_en   = 1'b0;
        t2_wr_data = 32'h0;
        fault_req  = 1'b0;
        fault_fc   = 4'h0;

        if (svc_req) begin
            unique case (svc_id)
                COMPUTE_REL_TARGET: begin
                    svc_done   = 1'b1;
                    svc_sr     = SR_OK;
                    t2_wr_en   = 1'b1;
                    t2_wr_data = m_next_eip + t4_in;
                end

                VALIDATE_NEAR_TRANSFER: begin
                    // Current phase: accept the already-computed near target.
                    // No protection checks are active in this path yet.
                    svc_done = 1'b1;
                    svc_sr   = SR_OK;
                end

                CONDITION_EVAL: begin
                    // Not part of the active Rung 2 path.
                    svc_done = 1'b1;
                    svc_sr   = SR_FAULT;
                end

                default: begin
                    svc_done = 1'b1;
                    svc_sr   = SR_FAULT;
                end
            endcase
        end
    end

endmodule