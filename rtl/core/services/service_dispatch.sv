// Keystone86 / Aegis
// rtl/core/services/service_dispatch.sv
//
// Pure routing for the current service subset.
// No policy lives here.

import keystone86_pkg::*;

module service_dispatch (
    input  logic [7:0] svc_id,
    input  logic       svc_req,
    output logic       svc_done,
    output logic [1:0] svc_sr,

    output logic [7:0] fe_svc_id,
    output logic       fe_svc_req,
    input  logic       fe_svc_done,
    input  logic [1:0] fe_svc_sr,

    output logic [7:0] fc_svc_id,
    output logic       fc_svc_req,
    input  logic       fc_svc_done,
    input  logic [1:0] fc_svc_sr
);

    logic to_fetch;
    logic to_flow;

    always_comb begin
        fe_svc_id  = svc_id;
        fe_svc_req = 1'b0;
        fc_svc_id  = svc_id;
        fc_svc_req = 1'b0;

        svc_done   = 1'b0;
        svc_sr     = SR_WAIT;

        unique case (svc_id)
            FETCH_DISP8,
            FETCH_DISP16,
            FETCH_DISP32: begin
                to_fetch = 1'b1;
                to_flow  = 1'b0;
            end

            COMPUTE_REL_TARGET,
            VALIDATE_NEAR_TRANSFER,
            CONDITION_EVAL: begin
                to_fetch = 1'b0;
                to_flow  = 1'b1;
            end

            default: begin
                to_fetch = 1'b0;
                to_flow  = 1'b0;
            end
        endcase

        if (svc_req) begin
            if (to_fetch) begin
                fe_svc_req = 1'b1;
                svc_done   = fe_svc_done;
                svc_sr     = fe_svc_sr;
            end else if (to_flow) begin
                fc_svc_req = 1'b1;
                svc_done   = fc_svc_done;
                svc_sr     = fc_svc_sr;
            end else begin
                // Unknown / unsupported service in this phase
                svc_done = 1'b1;
                svc_sr   = SR_FAULT;
            end
        end
    end

endmodule