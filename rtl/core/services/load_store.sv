// Keystone86 / Aegis
// rtl/core/services/load_store.sv
//
// Bounded Rung 6 load/store service.
//
// Existing LOAD_REG_META/STORE_REG_META behavior remains limited to
// ModRM.mod=11 MOV register-register forms. Pass 6A-1 adds only memory-source
// LOAD_RM8/16/32 for the direct absolute disp32 form after EA_CALC_32 has
// staged the effective address in T2. STORE_RM* and memory-destination MOV
// remain unsupported.

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
    input  logic [7:0]  meta_modrm_byte,
    input  logic [3:0]  meta_modrm_class,
    input  logic [2:0]  meta_reg_dst,
    input  logic [2:0]  meta_reg_src,
    input  logic [2:0]  meta_reg_rm,

    output logic [2:0]  gpr_rd_idx,
    output logic [1:0]  gpr_rd_opsz,
    input  logic [31:0] gpr_rd_val,

    input  logic [31:0] t4_in,
    input  logic [31:0] t2_in,
    output logic        t4_wr_en,
    output logic [31:0] t4_wr_data,

    output logic        mem_rd_req,
    output logic [31:0] mem_rd_addr,
    output logic [3:0]  mem_rd_byteen,
    input  logic [31:0] mem_rd_data,
    input  logic        mem_rd_ready,

    output logic        pc_gpr_en,
    output logic [2:0]  pc_gpr_idx,
    output logic [1:0]  pc_gpr_opsz,
    output logic [31:0] pc_gpr_val
);

    localparam logic [7:0] OC_MOV_RM_R = 8'h00;
    localparam logic [7:0] OC_MOV_R_RM = 8'h01;
    localparam logic [3:0] MRM_REG     = 4'h0;
    localparam logic [3:0] MRM_MEM_DISP32 = 4'h3;

    typedef enum logic [1:0] {
        LS_IDLE     = 2'h0,
        LS_MEM_WAIT = 2'h1,
        LS_DONE     = 2'h2
    } ls_state_t;

    ls_state_t state_r;
    logic [7:0]  active_svc_id_r;
    logic [31:0] mem_addr_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t4_wr_en_r;
    logic [31:0] complete_t4_wr_data_r;

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
    assign mem_rd_req = (state_r == LS_MEM_WAIT);
    assign mem_rd_addr = mem_addr_r;
    assign mem_rd_byteen = byteen_for_service(active_svc_id_r);
    assign pc_gpr_en  = pc_gpr_en_r;
    assign pc_gpr_idx = pc_gpr_idx_r;
    assign pc_gpr_opsz = pc_gpr_opsz_r;
    assign pc_gpr_val = pc_gpr_val_r;

    function automatic logic is_direct_disp32_mem_form;
        return (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b101);
    endfunction

    function automatic logic [3:0] byteen_for_service(input logic [7:0] sid);
        case (sid)
            LOAD_RM8:  return 4'b0001;
            LOAD_RM16: return 4'b0011;
            LOAD_RM32: return 4'b1111;
            default:   return 4'b0000;
        endcase
    endfunction

    function automatic logic service_width_matches_opsz(input logic [7:0] sid);
        case (sid)
            LOAD_RM8:  return (meta_opsz == 2'h0);
            LOAD_RM16: return (meta_opsz == 2'h1);
            LOAD_RM32: return (meta_opsz == 2'h2);
            default:   return 1'b0;
        endcase
    endfunction

    function automatic logic [31:0] load_result_for_service(
        input logic [7:0]  sid,
        input logic [31:0] data
    );
        case (sid)
            LOAD_RM8:  return {24'h0, data[7:0]};
            LOAD_RM16: return {16'h0, data[15:0]};
            LOAD_RM32: return data;
            default:   return 32'h0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r      <= LS_IDLE;
            active_svc_id_r <= 8'h00;
            mem_addr_r   <= 32'h0;
            complete_sr_r <= SR_WAIT;
            complete_t4_wr_en_r <= 1'b0;
            complete_t4_wr_data_r <= 32'h0;
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

            if (state_r == LS_DONE)
                state_r <= LS_IDLE;

            case (state_r)
                LS_IDLE: begin
                    complete_sr_r <= SR_WAIT;
                    complete_t4_wr_en_r <= 1'b0;
                    complete_t4_wr_data_r <= 32'h0;

                    if (svc_req) begin
                        unique case (svc_id)
                            LOAD_REG_META: begin
                                done_r <= 1'b1;
                                if (meta_modrm_class != MRM_REG) begin
                                    sr_r <= SR_FAULT;
                                end else begin
                                    sr_r         <= SR_OK;
                                    t4_wr_en_r   <= 1'b1;
                                    t4_wr_data_r <= gpr_rd_val;
                                end
                            end

                            STORE_REG_META: begin
                                done_r <= 1'b1;
                                if (meta_modrm_class != MRM_REG) begin
                                    sr_r <= SR_FAULT;
                                end else begin
                                    sr_r          <= SR_OK;
                                    pc_gpr_en_r   <= 1'b1;
                                    pc_gpr_idx_r  <= meta_reg_dst;
                                    pc_gpr_opsz_r <= meta_opsz;
                                    pc_gpr_val_r  <= t4_in;
                                end
                            end

                            LOAD_RM8,
                            LOAD_RM16,
                            LOAD_RM32: begin
                                if ((meta_opcode_class == OC_MOV_R_RM) &&
                                    is_direct_disp32_mem_form() &&
                                    service_width_matches_opsz(svc_id)) begin
                                    state_r         <= LS_MEM_WAIT;
                                    active_svc_id_r <= svc_id;
                                    mem_addr_r      <= t2_in;
                                end else begin
                                    done_r <= 1'b1;
                                    sr_r   <= SR_FAULT;
                                end
                            end

                            default: begin
                                done_r <= 1'b1;
                                sr_r   <= SR_FAULT;
                            end
                        endcase
                    end
                end

                LS_MEM_WAIT: begin
                    if (mem_rd_ready) begin
                        state_r                 <= LS_DONE;
                        complete_sr_r           <= SR_OK;
                        complete_t4_wr_en_r     <= 1'b1;
                        complete_t4_wr_data_r   <= load_result_for_service(active_svc_id_r,
                                                                            mem_rd_data);
                    end
                end

                default: state_r <= LS_IDLE;
            endcase

            if (state_r == LS_DONE) begin
                done_r       <= 1'b1;
                sr_r         <= complete_sr_r;
                t4_wr_en_r   <= complete_t4_wr_en_r;
                t4_wr_data_r <= complete_t4_wr_data_r;
            end
        end
    end

endmodule
