// Keystone86 / Aegis
// rtl/core/services/flow_control.sv
//
// Current phase support:
//   COMPUTE_REL_TARGET
//   VALIDATE_NEAR_TRANSFER
//   CONDITION_EVAL
//
// Root-cause fix:
//   Align flow_control with the pulse-start / report-later service protocol
//   already used by fetch_engine and the microsequencer WAIT_SERVICE path.
//
// Rung 4 ownership:
//   CONDITION_EVAL is the bounded Jcc condition service. It reads the current
//   architectural EFLAGS and decode-owned condition code, then returns T3=1 for
//   taken or T3=0 for not taken. It does not stage EIP or decide commit policy.
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
    output logic        t3_wr_en,
    output logic [31:0] t3_wr_data,

    input  logic [31:0] m_next_eip,
    input  logic [3:0]  m_cond_code,
    input  logic [31:0] eflags_in,
    input  logic        mode_prot,

    output logic        fault_req,
    output logic [3:0]  fault_fc
);

    logic        complete_pending_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t2_wr_en_r;
    logic [31:0] complete_t2_wr_data_r;
    logic        complete_t3_wr_en_r;
    logic [31:0] complete_t3_wr_data_r;
    logic        complete_fault_req_r;
    logic [3:0]  complete_fault_fc_r;

    logic [31:0] computed_target;
    logic        cond_taken;

    assign computed_target = m_next_eip + t4_in;

    always_comb begin
        unique case (m_cond_code)
            4'h0: cond_taken = eflags_in[11];                         // O
            4'h1: cond_taken = !eflags_in[11];                        // NO
            4'h2: cond_taken = eflags_in[0];                          // B/CF
            4'h3: cond_taken = !eflags_in[0];                         // NB/NC
            4'h4: cond_taken = eflags_in[6];                          // Z
            4'h5: cond_taken = !eflags_in[6];                         // NZ
            4'h6: cond_taken = eflags_in[0] || eflags_in[6];          // BE
            4'h7: cond_taken = !(eflags_in[0] || eflags_in[6]);       // NBE
            4'h8: cond_taken = eflags_in[7];                          // S
            4'h9: cond_taken = !eflags_in[7];                         // NS
            4'hA: cond_taken = eflags_in[2];                          // P
            4'hB: cond_taken = !eflags_in[2];                         // NP
            4'hC: cond_taken = eflags_in[7] != eflags_in[11];         // L
            4'hD: cond_taken = eflags_in[7] == eflags_in[11];         // NL
            4'hE: cond_taken = eflags_in[6] ||
                               (eflags_in[7] != eflags_in[11]);       // LE
            4'hF: cond_taken = !eflags_in[6] &&
                               (eflags_in[7] == eflags_in[11]);       // NLE
            default: cond_taken = 1'b0;
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;
            complete_t3_wr_en_r   <= 1'b0;
            complete_t3_wr_data_r <= 32'h0;
            complete_fault_req_r  <= 1'b0;
            complete_fault_fc_r   <= 4'h0;
        end else begin
            // completion pulse is one cycle unless re-armed below
            complete_pending_r    <= 1'b0;
            complete_sr_r         <= SR_WAIT;
            complete_t2_wr_en_r   <= 1'b0;
            complete_t2_wr_data_r <= 32'h0;
            complete_t3_wr_en_r   <= 1'b0;
            complete_t3_wr_data_r <= 32'h0;
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
                        complete_pending_r   <= 1'b1;
                        complete_sr_r        <= SR_OK;
                        complete_t3_wr_en_r  <= 1'b1;
                        complete_t3_wr_data_r <= {31'h0, cond_taken};
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
        t3_wr_en   = complete_pending_r ? complete_t3_wr_en_r : 1'b0;
        t3_wr_data = complete_t3_wr_data_r;

        fault_req  = complete_pending_r ? complete_fault_req_r : 1'b0;
        fault_fc   = complete_fault_fc_r;
    end

endmodule
