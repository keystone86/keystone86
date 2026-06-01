// Keystone86 / Aegis
// rtl/core/services/load_store.sv
//
// Bounded Rung 6 load/store service.
//
// Existing STORE_REG_META behavior remains limited to ModRM.mod=11 MOV
// register-register forms. Pass 6A-1 adds memory-source LOAD_RM8/16/32 for
// the direct absolute disp32 form after EA_CALC_32 has staged the effective
// address in T2. Pass 6B-1 adds memory-destination STORE_RM* for the same
// direct absolute disp32 form; LOAD_REG_META may read the source register for
// that bounded store path, and the memory write is completed before ENDI.
// Pass 6C-1 reuses STORE_RM* for OC_MOV_RM_IMM after FETCH_IMM* leaves the
// immediate in T4. Pass 6E-1 extends the same LOAD_RM*/STORE_RM* paths only to
// default-32 base-only no-displacement ModRM.mod=00 r/m!=100/101 forms.
// Pass 6E-2 additionally allows default-32 ModRM.mod=01 r/m!=100 base plus
// signed disp8 forms after EA_CALC_32 has staged the effective address in T2.
// Pass 6E-3 additionally allows default-32 ModRM.mod=10 r/m!=100 base plus
// signed disp32 forms through the same EA_CALC_32/T2 path. Pass 6F-1
// additionally allows base-only SIB forms with SIB.index=100. Pass 6F-2
// additionally allows only the mod=00 SIB.index=100
// SIB.base=101 no-base disp32 special case. Pass 6G-1 additionally allows
// base-present indexed SIB forms. Pass 6G-2 additionally allows no-base
// indexed SIB disp32 forms. Pass 6H-1 additionally allows only 0x67
// address-size direct disp16 forms after EA_CALC_16 has staged the
// zero-extended offset in T2. Pass 6H-2 additionally allows only 0x67
// address-size no-displacement non-BP forms after EA_CALC_16 has staged T2.
// Pass 6H-3 additionally allows only 0x67 address-size no-displacement
// BP-based [BP+SI]/[BP+DI] forms after EA_CALC_16 has staged T2.
// Pass 6H-4 additionally allows only 0x67 address-size ModRM.mod=01 signed
// disp8 forms after EA_CALC_16 has staged T2. Pass 6H-5 additionally allows
// only 0x67 address-size ModRM.mod=10 disp16 forms after EA_CALC_16 has
// staged T2.

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
    input  logic        meta_addrsz,
    input  logic [7:0]  meta_modrm_byte,
    input  logic [7:0]  meta_sib_byte,
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

    output logic        mem_wr_req,
    output logic [31:0] mem_wr_addr,
    output logic [3:0]  mem_wr_byteen,
    output logic [31:0] mem_wr_data,
    input  logic        mem_wr_ready,

    output logic        pc_gpr_en,
    output logic [2:0]  pc_gpr_idx,
    output logic [1:0]  pc_gpr_opsz,
    output logic [31:0] pc_gpr_val
);

    localparam logic [7:0] OC_MOV_RM_R = 8'h00;
    localparam logic [7:0] OC_MOV_R_RM = 8'h01;
    localparam logic [7:0] OC_MOV_RM_IMM = 8'h03;
    localparam logic [3:0] MRM_REG     = 4'h0;
    localparam logic [3:0] MRM_MEM_NO_DISP = 4'h1;
    localparam logic [3:0] MRM_MEM_DISP8 = 4'h2;
    localparam logic [3:0] MRM_MEM_DISP32 = 4'h3;
    localparam logic [3:0] MRM_MEM_DISP16 = 4'h4;
    localparam logic [3:0] MRM_DIRECT16 = 4'h8;
    localparam logic [3:0] MRM_SIB = 4'h5;
    localparam logic [3:0] MRM_SIB_DISP8 = 4'h6;
    localparam logic [3:0] MRM_SIB_DISP32 = 4'h7;

    typedef enum logic [1:0] {
        LS_IDLE     = 2'h0,
        LS_MEM_WAIT = 2'h1,
        LS_DONE     = 2'h2
    } ls_state_t;

    ls_state_t state_r;
    logic [7:0]  active_svc_id_r;
    logic [31:0] mem_addr_r;
    logic [31:0] mem_wdata_r;
    logic        active_is_store_r;
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
    assign mem_rd_req = (state_r == LS_MEM_WAIT) && !active_is_store_r;
    assign mem_rd_addr = mem_addr_r;
    assign mem_rd_byteen = byteen_for_service(active_svc_id_r);
    assign mem_wr_req = (state_r == LS_MEM_WAIT) && active_is_store_r;
    assign mem_wr_addr = mem_addr_r;
    assign mem_wr_byteen = byteen_for_service(active_svc_id_r);
    assign mem_wr_data = mem_wdata_r;
    assign pc_gpr_en  = pc_gpr_en_r;
    assign pc_gpr_idx = pc_gpr_idx_r;
    assign pc_gpr_opsz = pc_gpr_opsz_r;
    assign pc_gpr_val = pc_gpr_val_r;

    function automatic logic is_direct_disp32_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b101);
    endfunction

    function automatic logic is_direct_disp16_mem_form;
        return !meta_addrsz &&
               (meta_modrm_class == MRM_DIRECT16) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b110);
    endfunction

    function automatic logic is_addr16_nodisp_mem_form;
        if (meta_addrsz ||
            (meta_modrm_class != MRM_MEM_NO_DISP) ||
            (meta_modrm_byte[7:6] != 2'b00))
            return 1'b0;
        case (meta_modrm_byte[2:0])
            3'b000, // [BX+SI]
            3'b001, // [BX+DI]
            3'b010, // [BP+SI]
            3'b011, // [BP+DI]
            3'b100, // [SI]
            3'b101, // [DI]
            3'b111: return 1'b1; // [BX]
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic is_addr16_disp8_mem_form;
        return !meta_addrsz &&
               (meta_modrm_class == MRM_MEM_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01);
    endfunction

    function automatic logic is_addr16_disp16_mem_form;
        return !meta_addrsz &&
               (meta_modrm_class == MRM_MEM_DISP16) &&
               (meta_modrm_byte[7:6] == 2'b10);
    endfunction

    function automatic logic is_base_nodisp_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_MEM_NO_DISP) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] != 3'b100) &&
               (meta_modrm_byte[2:0] != 3'b101);
    endfunction

    function automatic logic is_base_disp8_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_MEM_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01) &&
               (meta_modrm_byte[2:0] != 3'b100);
    endfunction

    function automatic logic is_base_disp32_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_MEM_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b10) &&
               (meta_modrm_byte[2:0] != 3'b100);
    endfunction

    function automatic logic sib_index_none;
        return (meta_sib_byte[5:3] == 3'b100);
    endfunction

    function automatic logic is_sib_nodisp_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               (meta_sib_byte[2:0] != 3'b101);
    endfunction

    function automatic logic is_sib_nobase_disp32_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               sib_index_none() &&
               (meta_sib_byte[2:0] == 3'b101);
    endfunction

    function automatic logic is_sib_index_nobase_disp32_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_SIB) &&
               (meta_modrm_byte[7:6] == 2'b00) &&
               (meta_modrm_byte[2:0] == 3'b100) &&
               !sib_index_none() &&
               (meta_sib_byte[2:0] == 3'b101);
    endfunction

    function automatic logic is_sib_disp8_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_SIB_DISP8) &&
               (meta_modrm_byte[7:6] == 2'b01) &&
               (meta_modrm_byte[2:0] == 3'b100);
    endfunction

    function automatic logic is_sib_disp32_mem_form;
        return meta_addrsz &&
               (meta_modrm_class == MRM_SIB_DISP32) &&
               (meta_modrm_byte[7:6] == 2'b10) &&
               (meta_modrm_byte[2:0] == 3'b100);
    endfunction

    function automatic logic is_authorized_mem_form;
        return is_direct_disp32_mem_form() ||
               is_direct_disp16_mem_form() ||
               is_addr16_nodisp_mem_form() ||
               is_addr16_disp8_mem_form() ||
               is_addr16_disp16_mem_form() ||
               is_base_nodisp_mem_form() ||
               is_base_disp8_mem_form() ||
               is_base_disp32_mem_form() ||
               is_sib_nodisp_mem_form() ||
               is_sib_nobase_disp32_mem_form() ||
               is_sib_index_nobase_disp32_mem_form() ||
               is_sib_disp8_mem_form() ||
               is_sib_disp32_mem_form();
    endfunction

    function automatic logic [3:0] byteen_for_service(input logic [7:0] sid);
        case (sid)
            LOAD_RM8:  return 4'b0001;
            LOAD_RM16: return 4'b0011;
            LOAD_RM32: return 4'b1111;
            STORE_RM8:  return 4'b0001;
            STORE_RM16: return 4'b0011;
            STORE_RM32: return 4'b1111;
            default:   return 4'b0000;
        endcase
    endfunction

    function automatic logic service_width_matches_opsz(input logic [7:0] sid);
        case (sid)
            LOAD_RM8:  return (meta_opsz == 2'h0);
            LOAD_RM16: return (meta_opsz == 2'h1);
            LOAD_RM32: return (meta_opsz == 2'h2);
            STORE_RM8:  return (meta_opsz == 2'h0);
            STORE_RM16: return (meta_opsz == 2'h1);
            STORE_RM32: return (meta_opsz == 2'h2);
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

    function automatic logic [31:0] store_data_for_service(
        input logic [7:0]  sid,
        input logic [31:0] data
    );
        case (sid)
            STORE_RM8:  return {24'h0, data[7:0]};
            STORE_RM16: return {16'h0, data[15:0]};
            STORE_RM32: return data;
            default:    return 32'h0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r      <= LS_IDLE;
            active_svc_id_r <= 8'h00;
            mem_addr_r   <= 32'h0;
            mem_wdata_r  <= 32'h0;
            active_is_store_r <= 1'b0;
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
                                if (!((meta_modrm_class == MRM_REG) ||
                                      ((meta_opcode_class == OC_MOV_RM_R) &&
                                       is_authorized_mem_form()))) begin
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
                                    is_authorized_mem_form() &&
                                    service_width_matches_opsz(svc_id)) begin
                                    state_r         <= LS_MEM_WAIT;
                                    active_svc_id_r <= svc_id;
                                    mem_addr_r      <= t2_in;
                                    active_is_store_r <= 1'b0;
                                end else begin
                                    done_r <= 1'b1;
                                    sr_r   <= SR_FAULT;
                                end
                            end

                            STORE_RM8,
                            STORE_RM16,
                            STORE_RM32: begin
                                if (((meta_opcode_class == OC_MOV_RM_R) ||
                                     (meta_opcode_class == OC_MOV_RM_IMM)) &&
                                    is_authorized_mem_form() &&
                                    service_width_matches_opsz(svc_id)) begin
                                    state_r           <= LS_MEM_WAIT;
                                    active_svc_id_r   <= svc_id;
                                    mem_addr_r        <= t2_in;
                                    mem_wdata_r       <= store_data_for_service(svc_id, t4_in);
                                    active_is_store_r <= 1'b1;
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
                    if (active_is_store_r && mem_wr_ready) begin
                        state_r                 <= LS_DONE;
                        complete_sr_r           <= SR_OK;
                        complete_t4_wr_en_r     <= 1'b0;
                        complete_t4_wr_data_r   <= 32'h0;
                    end else if (!active_is_store_r && mem_rd_ready) begin
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
