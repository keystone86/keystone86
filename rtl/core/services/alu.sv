// Keystone86 / Aegis
// rtl/core/services/alu.sv
//
// Bounded Rung 7 first-slice ALU service.
//
// This service is a leaf helper for 32-bit ADD/SUB/CMP only. It receives staged
// operands from T0/T1 and an explicit ALU op selected by microcode. It returns
// a result candidate in T0 plus EFLAGS-shaped candidate value/mask in T3/T4.
// It does not read architectural registers, stage commits, decide CMP
// writeback, or know opcode bytes.

import keystone86_pkg::*;

module alu (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [3:0]  alu_op,
    input  logic [1:0]  meta_opsz,

    output logic        t0_wr_en,
    output logic [31:0] t0_wr_data,
    output logic        t3_wr_en,
    output logic [31:0] t3_wr_data,
    output logic        t4_wr_en,
    output logic [31:0] t4_wr_data
);

    localparam logic [31:0] ALU_EFLAGS_MASK =
        (32'h1 << 0)  | // CF
        (32'h1 << 2)  | // PF
        (32'h1 << 4)  | // AF
        (32'h1 << 6)  | // ZF
        (32'h1 << 7)  | // SF
        (32'h1 << 11);  // OF

    logic [32:0] add_ext;
    logic [32:0] sub_ext;
    logic [31:0] result_w;
    logic        valid_op_w;
    logic        is_sub_w;
    logic        cf_w;
    logic        of_w;
    logic        zf_w;
    logic        sf_w;
    logic        pf_w;
    logic        af_w;

    assign add_ext = {1'b0, operand_a} + {1'b0, operand_b};
    assign sub_ext = {1'b0, operand_a} - {1'b0, operand_b};
    assign is_sub_w = (alu_op == ALU_SUB) || (alu_op == ALU_CMP);
    assign valid_op_w = (meta_opsz == 2'h2) &&
                        (((svc_id == ALU_ADD32) && (alu_op == ALU_ADD)) ||
                         ((svc_id == ALU_SUB32) && (alu_op == ALU_SUB)) ||
                         ((svc_id == ALU_CMP32) && (alu_op == ALU_CMP)));
    assign result_w = is_sub_w ? sub_ext[31:0] : add_ext[31:0];
    assign cf_w = is_sub_w ? (operand_a < operand_b) : add_ext[32];
    assign of_w = is_sub_w ? ((operand_a[31] ^ operand_b[31]) &&
                              (operand_a[31] ^ result_w[31])) :
                             ((operand_a[31] == operand_b[31]) &&
                              (operand_a[31] != result_w[31]));
    assign zf_w = (result_w == 32'h0);
    assign sf_w = result_w[31];
    assign pf_w = ~^result_w[7:0];
    assign af_w = operand_a[4] ^ operand_b[4] ^ result_w[4];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            svc_done   <= 1'b0;
            svc_sr     <= SR_OK;
            t0_wr_en   <= 1'b0;
            t0_wr_data <= 32'h0;
            t3_wr_en   <= 1'b0;
            t3_wr_data <= 32'h0;
            t4_wr_en   <= 1'b0;
            t4_wr_data <= 32'h0;
        end else begin
            svc_done <= 1'b0;
            svc_sr   <= SR_OK;
            t0_wr_en <= 1'b0;
            t3_wr_en <= 1'b0;
            t4_wr_en <= 1'b0;

            if (svc_req) begin
                svc_done <= 1'b1;
                if (!valid_op_w) begin
                    svc_sr <= SR_FAULT;
                end else begin
                    svc_sr     <= SR_OK;
                    t0_wr_en   <= 1'b1;
                    t0_wr_data <= result_w;
                    t3_wr_en   <= 1'b1;
                    t3_wr_data <= (cf_w ? 32'h00000001 : 32'h0) |
                                  (pf_w ? 32'h00000004 : 32'h0) |
                                  (af_w ? 32'h00000010 : 32'h0) |
                                  (zf_w ? 32'h00000040 : 32'h0) |
                                  (sf_w ? 32'h00000080 : 32'h0) |
                                  (of_w ? 32'h00000800 : 32'h0);
                    t4_wr_en   <= 1'b1;
                    t4_wr_data <= ALU_EFLAGS_MASK;
                end
            end
        end
    end

endmodule
