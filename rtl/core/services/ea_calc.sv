// Keystone86 / Aegis
// rtl/core/services/ea_calc.sv
//
// Bounded Rung 6 Pass 6A-1 effective-address service.
//
// This slice implements only EA_CALC_32 for the direct absolute disp32
// addressing form used by memory-source MOV:
//   ModRM.mod=00, ModRM.r/m=101
//
// It does not implement EA_CALC_16, SIB, base/index/scale, disp8, mod=01/10,
// 0x67, segment-base addition, protection checks, or memory access.

import keystone86_pkg::*;

module ea_calc (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [7:0]  meta_modrm_byte,
    input  logic [3:0]  meta_modrm_class,
    input  logic [31:0] meta_disp_value,

    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data
);

    localparam logic [3:0] MRM_MEM_DISP32 = 4'h3;

    logic        done_r;
    logic [1:0]  sr_r;
    logic        t2_wr_en_r;
    logic [31:0] t2_wr_data_r;

    function automatic logic is_direct_disp32_mem_form;
        return (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b101);
    endfunction

    assign svc_done   = done_r;
    assign svc_sr     = sr_r;
    assign t2_wr_en   = t2_wr_en_r;
    assign t2_wr_data = t2_wr_data_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            done_r       <= 1'b0;
            sr_r         <= SR_OK;
            t2_wr_en_r   <= 1'b0;
            t2_wr_data_r <= 32'h0;
        end else begin
            done_r     <= 1'b0;
            sr_r       <= SR_OK;
            t2_wr_en_r <= 1'b0;

            if (svc_req) begin
                done_r <= 1'b1;

                if ((svc_id == EA_CALC_32) && is_direct_disp32_mem_form()) begin
                    sr_r         <= SR_OK;
                    t2_wr_en_r   <= 1'b1;
                    t2_wr_data_r <= meta_disp_value;
                end else begin
                    sr_r <= SR_FAULT;
                end
            end
        end
    end

endmodule
