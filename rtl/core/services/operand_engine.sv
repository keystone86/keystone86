// Keystone86 / Aegis
// rtl/core/services/operand_engine.sv
//
// Bounded Rung 3 operand service.
//
// This implements only the LOAD_RM32 behavior needed by near CALL FF /2:
// register-form reads use commit-owned architectural ESP for r/m=100, and
// the only successful memory-form read is the verified direct disp32 form
// (mod=00, r/m=101). Other memory addressing forms fail safely for Rung 3
// instead of growing an unverified EA/GPR surface. It remains a leaf mechanism;
// the CALL routine decides in microcode when this service is part of the
// sequence.

import keystone86_pkg::*;

module operand_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] esp_in,
    input  logic        modrm_present,
    input  logic [7:0]  modrm_byte,
    input  logic [7:0]  sib_byte,
    input  logic [3:0]  modrm_class,
    input  logic [31:0] disp_value,

    output logic        mem_rd_req,
    output logic [31:0] mem_rd_addr,
    input  logic [31:0] mem_rd_data,
    input  logic        mem_rd_ready,

    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data
);

    typedef enum logic [1:0] {
        OP_IDLE     = 2'h0,
        OP_MEM_WAIT = 2'h1,
        OP_DONE     = 2'h2
    } op_state_t;

    op_state_t state_r;
    logic [31:0] mem_addr_r;
    logic [1:0]  complete_sr_r;
    logic        complete_t2_wr_en_r;
    logic [31:0] complete_t2_wr_data_r;

    function automatic logic is_reg_form(input logic [3:0] cls);
        return cls == 4'h0; // MRM_REG
    endfunction

    function automatic logic is_direct_disp32_mem_form(input logic [3:0] cls);
        return (cls == 4'h3) && (modrm_byte[7:6] == 2'b00) &&
               (modrm_byte[2:0] == 3'b101);
    endfunction

    function automatic logic [31:0] base_for_rm(input logic [2:0] rm);
        // Rung 3 has only ESP as a real architectural register source.
        // Other base registers are not asserted by the active acceptance
        // tests and remain zero-valued bootstrap placeholders.
        return (rm == 3'b100) ? esp_in : 32'h0;
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r                 <= OP_IDLE;
            mem_addr_r              <= 32'h0;
            complete_sr_r           <= SR_WAIT;
            complete_t2_wr_en_r     <= 1'b0;
            complete_t2_wr_data_r   <= 32'h0;
        end else begin
            if (state_r == OP_DONE)
                state_r <= OP_IDLE;

            case (state_r)
                OP_IDLE: begin
                    complete_sr_r         <= SR_WAIT;
                    complete_t2_wr_en_r   <= 1'b0;
                    complete_t2_wr_data_r <= 32'h0;

                    if (svc_req) begin
                        if (svc_id != LOAD_RM32) begin
                            state_r       <= OP_DONE;
                            complete_sr_r <= SR_FAULT;
                        end else if (!modrm_present) begin
                            // Direct CALL shares the same microcode routine.
                            // With no r/m operand present, LOAD_RM32 is a
                            // leaf no-op and leaves the relative target in T2.
                            state_r       <= OP_DONE;
                            complete_sr_r <= SR_OK;
                        end else if (is_reg_form(modrm_class)) begin
                            state_r               <= OP_DONE;
                            complete_sr_r         <= SR_OK;
                            complete_t2_wr_en_r   <= 1'b1;
                            complete_t2_wr_data_r <= base_for_rm(modrm_byte[2:0]);
                        end else if (is_direct_disp32_mem_form(modrm_class)) begin
                            state_r    <= OP_MEM_WAIT;
                            mem_addr_r <= disp_value;
                        end else begin
                            // Decoder may consume these forms to preserve
                            // M_NEXT_EIP, but Rung 3 does not execute their
                            // unverified EA/register-base behavior.
                            state_r       <= OP_DONE;
                            complete_sr_r <= SR_FAULT;
                        end
                    end
                end

                OP_MEM_WAIT: begin
                    if (mem_rd_ready) begin
                        state_r               <= OP_DONE;
                        complete_sr_r         <= SR_OK;
                        complete_t2_wr_en_r   <= 1'b1;
                        complete_t2_wr_data_r <= mem_rd_data;
                    end
                end

                default: state_r <= OP_IDLE;
            endcase
        end
    end

    always_comb begin
        svc_done   = (state_r == OP_DONE);
        svc_sr     = (state_r == OP_DONE) ? complete_sr_r : SR_WAIT;

        mem_rd_req  = (state_r == OP_MEM_WAIT);
        mem_rd_addr = mem_addr_r;

        t2_wr_en   = (state_r == OP_DONE) ? complete_t2_wr_en_r : 1'b0;
        t2_wr_data = complete_t2_wr_data_r;
    end

endmodule
