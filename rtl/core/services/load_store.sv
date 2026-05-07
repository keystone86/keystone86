// Keystone86 / Aegis
// rtl/core/services/load_store.sv
//
// Bounded Rung 6 Pass 5A metadata-only register service.
// This slice implements LOAD_REG_META/STORE_REG_META only for ModRM.mod=11
// MOV register-register forms. It has no effective-address calculation,
// no memory interface, and cannot issue bus reads or writes.

import keystone86_pkg::*;

module load_store (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [7:0]  meta_opcode_class,
    input  logic [1:0]  meta_opsz,
    input  logic [3:0]  meta_modrm_class,
    input  logic [2:0]  meta_reg_dst,
    input  logic [2:0]  meta_reg_src,
    input  logic [2:0]  meta_reg_rm,

    output logic [2:0]  gpr_rd_idx,
    output logic [1:0]  gpr_rd_opsz,
    input  logic [31:0] gpr_rd_val,

    input  logic [31:0] t4_in,
    output logic        t4_wr_en,
    output logic [31:0] t4_wr_data,

    output logic        pc_gpr_en,
    output logic [2:0]  pc_gpr_idx,
    output logic [1:0]  pc_gpr_opsz,
    output logic [31:0] pc_gpr_val
);

    localparam logic [7:0] OC_MOV_RM_R = 8'h00;
    localparam logic [7:0] OC_MOV_R_RM = 8'h01;
    localparam logic [3:0] MRM_REG     = 4'h0;

    logic        done_r;
    logic [1:0]  sr_r;
    logic        t4_wr_en_r;
    logic [31:0] t4_wr_data_r;
    logic        pc_gpr_en_r;
    logic [2:0]  pc_gpr_idx_r;
    logic [1:0]  pc_gpr_opsz_r;
    logic [31:0] pc_gpr_val_r;

    assign gpr_rd_idx = (meta_opcode_class == OC_MOV_RM_R) ? meta_reg_src :
                        (meta_opcode_class == OC_MOV_R_RM) ? meta_reg_rm  :
                                                             3'h0;
    assign gpr_rd_opsz = meta_opsz;

    assign svc_done   = done_r;
    assign svc_sr     = sr_r;
    assign t4_wr_en   = t4_wr_en_r;
    assign t4_wr_data = t4_wr_data_r;
    assign pc_gpr_en  = pc_gpr_en_r;
    assign pc_gpr_idx = pc_gpr_idx_r;
    assign pc_gpr_opsz = pc_gpr_opsz_r;
    assign pc_gpr_val = pc_gpr_val_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            done_r       <= 1'b0;
            sr_r         <= SR_OK;
            t4_wr_en_r   <= 1'b0;
            t4_wr_data_r <= 32'h0;
            pc_gpr_en_r  <= 1'b0;
            pc_gpr_idx_r <= 3'h0;
            pc_gpr_opsz_r <= 2'h0;
            pc_gpr_val_r <= 32'h0;
        end else begin
            done_r       <= 1'b0;
            sr_r         <= SR_OK;
            t4_wr_en_r   <= 1'b0;
            pc_gpr_en_r  <= 1'b0;

            if (svc_req) begin
                done_r <= 1'b1;

                if (meta_modrm_class != MRM_REG) begin
                    sr_r <= SR_FAULT;
                end else begin
                    unique case (svc_id)
                        LOAD_REG_META: begin
                            sr_r         <= SR_OK;
                            t4_wr_en_r   <= 1'b1;
                            t4_wr_data_r <= gpr_rd_val;
                        end

                        STORE_REG_META: begin
                            sr_r          <= SR_OK;
                            pc_gpr_en_r   <= 1'b1;
                            pc_gpr_idx_r  <= meta_reg_dst;
                            pc_gpr_opsz_r <= meta_opsz;
                            pc_gpr_val_r  <= t4_in;
                        end

                        default: begin
                            sr_r <= SR_FAULT;
                        end
                    endcase
                end
            end
        end
    end

endmodule
