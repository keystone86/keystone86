// Keystone86 / Aegis
// rtl/core/services/service_dispatch.sv
//
// Request model:
//   - svc_req is a one-cycle start pulse.
//   - svc_id remains stable while the microsequencer waits.
//   - Done/status are routed from the selected service based on svc_id,
//     independent of whether svc_req is still high.

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

    logic use_fetch;
    logic use_flow;

    always_comb begin
        fe_svc_id  = svc_id;
        fe_svc_req = 1'b0;
        fc_svc_id  = svc_id;
        fc_svc_req = 1'b0;

        use_fetch = 1'b0;
        use_flow  = 1'b0;

        unique case (svc_id)
            FETCH_DISP8,
            FETCH_DISP16,
            FETCH_DISP32: begin
                use_fetch = 1'b1;
            end

            COMPUTE_REL_TARGET,
            VALIDATE_NEAR_TRANSFER,
            CONDITION_EVAL: begin
                use_flow = 1'b1;
            end

            default: begin
                use_fetch = 1'b0;
                use_flow  = 1'b0;
            end
        endcase

        if (svc_req) begin
            if (use_fetch)
                fe_svc_req = 1'b1;
            else if (use_flow)
                fc_svc_req = 1'b1;
        end

        if (use_fetch) begin
            svc_done = fe_svc_done;
            svc_sr   = fe_svc_sr;
        end else if (use_flow) begin
            svc_done = fc_svc_done;
            svc_sr   = fc_svc_sr;
        end else begin
            svc_done = 1'b1;
            svc_sr   = SR_FAULT;
        end
    end

endmodule