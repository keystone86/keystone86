// Keystone86 / Aegis
// rtl/core/services/ea_calc.sv
//
// Bounded Rung 6 Pass 6G-1 effective-address service.
//
// This slice implements only EA_CALC_32 for:
//   ModRM.mod=00, ModRM.r/m=101
//   ModRM.mod=00, ModRM.r/m!=100/101 base-only no-displacement
//   ModRM.mod=01, ModRM.r/m!=100 base plus signed disp8
//   ModRM.mod=10, ModRM.r/m!=100 base plus signed disp32
//   ModRM.r/m=100 SIB forms with SIB.index=100:
//     mod=00 base!=101 base-only, mod=01 any base + disp8,
//     mod=10 any base + disp32, and Pass 6F-2 ModRM.mod=00,
//     ModRM.r/m=100, SIB.index=100, SIB.base=101 no-base disp32 with EA=disp32
//   Pass 6G-1 base-present indexed SIB forms with SIB.index!=100:
//     mod=00 base!=101, mod=01 any base + disp8, mod=10 any base + disp32
//
// It does not implement EA_CALC_16, no-base indexed SIB, 0x67,
// segment-base addition, protection checks, memory access, or Rung 7 behavior.

import keystone86_pkg::*;

module ea_calc (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [7:0]  meta_modrm_byte,
    input  logic [7:0]  meta_sib_byte,
    input  logic [3:0]  meta_modrm_class,
    input  logic [31:0] meta_disp_value,

    output logic [2:0]  base_gpr_rd_idx,
    input  logic [31:0] base_gpr_rd_val,

    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data
);

    localparam logic [3:0] MRM_MEM_NO_DISP = 4'h1;
    localparam logic [3:0] MRM_MEM_DISP8 = 4'h2;
    localparam logic [3:0] MRM_MEM_DISP32 = 4'h3;
    localparam logic [3:0] MRM_SIB = 4'h5;
    localparam logic [3:0] MRM_SIB_DISP8 = 4'h6;
    localparam logic [3:0] MRM_SIB_DISP32 = 4'h7;

    typedef enum logic [1:0] {
        EA_IDLE          = 2'h0,
        EA_INDEX_READ    = 2'h1,
        EA_INDEX_DONE    = 2'h2
    } ea_state_t;

    ea_state_t   state_r;
    logic        done_r;
    logic [1:0]  sr_r;
    logic        t2_wr_en_r;
    logic [31:0] t2_wr_data_r;
    logic [31:0] indexed_base_val_r;
    logic [31:0] indexed_disp_val_r;
    logic        sib_index_none_w;
    logic        sib_index_present_w;
    logic        sib_nodisp_mem_form_w;
    logic        sib_disp8_mem_form_w;
    logic        sib_disp32_mem_form_w;
    logic        sib_index_nodisp_mem_form_w;
    logic        sib_index_disp8_mem_form_w;
    logic        sib_index_disp32_mem_form_w;
    logic        authorized_sib_mem_form_w;

    function automatic logic is_direct_disp32_mem_form;
        return (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b101);
    endfunction

    function automatic logic is_base_nodisp_mem_form;
        return (meta_modrm_class == MRM_MEM_NO_DISP) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] != 3'b100) &&
               (meta_modrm_byte[2:0] != 3'b101);
    endfunction

    function automatic logic is_base_disp8_mem_form;
        return (meta_modrm_class == MRM_MEM_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01) &&
               (meta_modrm_byte[2:0] != 3'b100);
    endfunction

    function automatic logic is_base_disp32_mem_form;
        return (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b10) &&
               (meta_modrm_byte[2:0] != 3'b100);
    endfunction

    function automatic logic sib_index_none;
        return (meta_sib_byte[5:3] == 3'b100);
    endfunction

    function automatic logic sib_index_present;
        return (meta_sib_byte[5:3] != 3'b100);
    endfunction

    function automatic logic is_sib_nodisp_mem_form;
        return (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_none() &&
               (meta_sib_byte[2:0] != 3'b101);
    endfunction

    function automatic logic is_sib_nobase_disp32_mem_form;
        return (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_none() &&
               (meta_sib_byte[2:0] == 3'b101);
    endfunction

    function automatic logic is_sib_disp8_mem_form;
        return (meta_modrm_class == MRM_SIB_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_none();
    endfunction

    function automatic logic is_sib_disp32_mem_form;
        return (meta_modrm_class == MRM_SIB_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b10) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_none();
    endfunction

    function automatic logic is_sib_index_nodisp_mem_form;
        return (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_present() &&
               (meta_sib_byte[2:0] != 3'b101);
    endfunction

    function automatic logic is_sib_index_disp8_mem_form;
        return (meta_modrm_class == MRM_SIB_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_present();
    endfunction

    function automatic logic is_sib_index_disp32_mem_form;
        return (meta_modrm_class == MRM_SIB_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b10) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_present();
    endfunction

    function automatic logic is_authorized_sib_mem_form;
        return is_sib_nodisp_mem_form() ||
               is_sib_index_nodisp_mem_form() ||
               is_sib_disp8_mem_form() ||
               is_sib_index_disp8_mem_form() ||
               is_sib_disp32_mem_form() ||
               is_sib_index_disp32_mem_form();
    endfunction

    function automatic logic is_indexed_sib_mem_form;
        return is_sib_index_nodisp_mem_form() ||
               is_sib_index_disp8_mem_form() ||
               is_sib_index_disp32_mem_form();
    endfunction

    function automatic logic [31:0] indexed_disp_value;
        if (is_sib_index_disp8_mem_form() || is_sib_index_disp32_mem_form())
            return meta_disp_value;
        return 32'h0;
    endfunction

    function automatic logic [31:0] scale_index(
        input logic [31:0] idx_val,
        input logic [1:0]  scale
    );
        case (scale)
            2'b00: return idx_val;
            2'b01: return idx_val << 1;
            2'b10: return idx_val << 2;
            default: return idx_val << 3;
        endcase
    endfunction

    assign sib_index_none_w = (meta_sib_byte[5:3] == 3'b100);
    assign sib_index_present_w = (meta_sib_byte[5:3] != 3'b100);
    assign sib_nodisp_mem_form_w =
        (meta_modrm_class == MRM_SIB) &&
        (meta_modrm_byte[7:6] == 2'b00) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_none_w &&
        (meta_sib_byte[2:0] != 3'b101);
    assign sib_disp8_mem_form_w =
        (meta_modrm_class == MRM_SIB_DISP8) &&
        (meta_modrm_byte[7:6] == 2'b01) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_none_w;
    assign sib_disp32_mem_form_w =
        (meta_modrm_class == MRM_SIB_DISP32) &&
        (meta_modrm_byte[7:6] == 2'b10) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_none_w;
    assign sib_index_nodisp_mem_form_w =
        (meta_modrm_class == MRM_SIB) &&
        (meta_modrm_byte[7:6] == 2'b00) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_present_w &&
        (meta_sib_byte[2:0] != 3'b101);
    assign sib_index_disp8_mem_form_w =
        (meta_modrm_class == MRM_SIB_DISP8) &&
        (meta_modrm_byte[7:6] == 2'b01) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_present_w;
    assign sib_index_disp32_mem_form_w =
        (meta_modrm_class == MRM_SIB_DISP32) &&
        (meta_modrm_byte[7:6] == 2'b10) &&
        (meta_modrm_byte[2:0] == 3'b100) &&
        sib_index_present_w;
    assign authorized_sib_mem_form_w = sib_nodisp_mem_form_w ||
                                       sib_index_nodisp_mem_form_w ||
                                       sib_disp8_mem_form_w ||
                                       sib_index_disp8_mem_form_w ||
                                       sib_disp32_mem_form_w ||
                                       sib_index_disp32_mem_form_w;

    assign svc_done   = done_r;
    assign svc_sr     = sr_r;
    assign base_gpr_rd_idx = ((state_r == EA_INDEX_READ) || (state_r == EA_INDEX_DONE)) ?
                                                        meta_sib_byte[5:3] :
                             authorized_sib_mem_form_w ? meta_sib_byte[2:0] :
                                                         meta_modrm_byte[2:0];
    assign t2_wr_en   = t2_wr_en_r;
    assign t2_wr_data = t2_wr_data_r;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r       <= EA_IDLE;
            done_r       <= 1'b0;
            sr_r         <= SR_OK;
            t2_wr_en_r   <= 1'b0;
            t2_wr_data_r <= 32'h0;
            indexed_base_val_r <= 32'h0;
            indexed_disp_val_r <= 32'h0;
        end else begin
            done_r     <= 1'b0;
            sr_r       <= SR_OK;
            t2_wr_en_r <= 1'b0;

            case (state_r)
                EA_IDLE: begin
                    if (svc_req) begin
                        if ((svc_id == EA_CALC_32) && is_indexed_sib_mem_form()) begin
                            // Pass 6G-1 keeps the single committed-GPR read
                            // path: latch base now, then hold the index
                            // selection for a full wait cycle before consuming
                            // the read data.
                            indexed_base_val_r <= base_gpr_rd_val;
                            indexed_disp_val_r <= indexed_disp_value();
                            sr_r               <= SR_WAIT;
                            state_r            <= EA_INDEX_READ;
                        end else begin
                            done_r <= 1'b1;

                            if ((svc_id == EA_CALC_32) && is_direct_disp32_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= meta_disp_value;
                            end else if ((svc_id == EA_CALC_32) && is_base_nodisp_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val;
                            end else if ((svc_id == EA_CALC_32) && is_base_disp8_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val + meta_disp_value;
                            end else if ((svc_id == EA_CALC_32) && is_base_disp32_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val + meta_disp_value;
                            end else if ((svc_id == EA_CALC_32) && is_sib_nodisp_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val;
                            end else if ((svc_id == EA_CALC_32) && is_sib_nobase_disp32_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= meta_disp_value;
                            end else if ((svc_id == EA_CALC_32) && is_sib_disp8_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val + meta_disp_value;
                            end else if ((svc_id == EA_CALC_32) && is_sib_disp32_mem_form()) begin
                                sr_r         <= SR_OK;
                                t2_wr_en_r   <= 1'b1;
                                t2_wr_data_r <= base_gpr_rd_val + meta_disp_value;
                            end else begin
                                sr_r <= SR_FAULT;
                            end
                        end
                    end
                end

                EA_INDEX_READ: begin
                    sr_r    <= SR_WAIT;
                    state_r <= EA_INDEX_DONE;
                end

                EA_INDEX_DONE: begin
                    done_r       <= 1'b1;
                    sr_r         <= SR_OK;
                    t2_wr_en_r   <= 1'b1;
                    t2_wr_data_r <= indexed_base_val_r +
                                    scale_index(base_gpr_rd_val, meta_sib_byte[7:6]) +
                                    indexed_disp_val_r;
                    state_r      <= EA_IDLE;
                end

                default: state_r <= EA_IDLE;
            endcase
        end
    end

endmodule
