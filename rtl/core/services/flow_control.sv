// Keystone86 / Aegis
// rtl/core/services/flow_control.sv
//
// Current phase support:
//   COMPUTE_REL_TARGET
//   VALIDATE_NEAR_TRANSFER
//
// Root-cause fix:
//   Align flow_control with the pulse-start / report-later service protocol
//   already used by fetch_engine and the microsequencer WAIT_SERVICE path.
//
// Protocol here:
//   - svc_req is a one-cycle start pulse.
//   - Result is latched internally.
//   - svc_done/svc_sr and any writeback pulse are presented on the following
//     cycle via complete_pending_r so WAIT_SERVICE can observe them.

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

    logic        complete_pending_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t2_wr_en_r;
    logic [31:0] complete_t2_wr_data_r;
    logic        complete_fault_req_r;
    logic [3:0]  complete_fault_fc_r;

    logic [31:0] computed_target;

    assign computed_target = m_next_eip + t4_in;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;
            complete_fault_req_r  <= 1'b0;
            complete_fault_fc_r   <= 4'h0;
        end else begin
            // completion pulse is one cycle unless re-armed below
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;
            complete_fault_req_r  <= 1'b0;
            complete_fault_fc_r   <= 4'h0;

            if (svc_req) begin
                unique case (svc_id)
                    COMPUTE_REL_TARGET: begin
                        complete_pending_r    <= 1'b1;
                        complete_sr_r         <= SR_OK;
                        complete_t2_wr_en_r   <= 1'b1;
                        complete_t2_wr_data_r <= computed_target;
                    end

                    VALIDATE_NEAR_TRANSFER: begin
                        complete_pending_r <= 1'b1;
                        if (mode_prot && (t2_in > 32'h0000FFFF)) begin
                            complete_sr_r        <= SR_FAULT;
                            complete_fault_req_r <= 1'b1;
                            complete_fault_fc_r  <= FC_GP;
                        end else begin
                            complete_sr_r <= SR_OK;
                        end
                    end

                    CONDITION_EVAL: begin
                        // Not part of active Rung 2 path yet.
                        complete_pending_r   <= 1'b1;
                        complete_sr_r        <= SR_FAULT;
                    end

                    default: begin
                        complete_pending_r   <= 1'b1;
                        complete_sr_r        <= SR_FAULT;
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

        fault_req  = complete_pending_r ? complete_fault_req_r : 1'b0;
        fault_fc   = complete_fault_fc_r;
    end

endmodule
