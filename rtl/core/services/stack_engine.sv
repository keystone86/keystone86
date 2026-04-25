// Keystone86 / Aegis
// rtl/core/services/stack_engine.sv
//
// Bounded Rung 3 stack service.
//
// Owns PUSH16/PUSH32 and POP16/POP32 stack effects as staged commit records.
// It may read the stack for POP, but architectural ESP and stack writes become
// visible only when commit_engine applies the staged record at ENDI.

import keystone86_pkg::*;

module stack_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] esp_in,
    input  logic [31:0] push_data,

    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,

    output logic        t2_wr_en,
    output logic [31:0] t2_wr_data,

    output logic        pc_stack_en,
    output logic        pc_stack_write_en,
    output logic [31:0] pc_stack_addr,
    output logic [31:0] pc_stack_data,
    output logic [31:0] pc_stack_esp_val
);

    typedef enum logic [1:0] {
        ST_IDLE     = 2'h0,
        ST_POP_WAIT = 2'h1,
        ST_DONE     = 2'h2
    } st_state_t;

    st_state_t state_r;
    logic [7:0]  svc_id_r;
    logic [31:0] pop_addr_r;
    logic [31:0] next_esp_r;
    logic [31:0] pop_data_r;
    logic        complete_stack_write_r;
    logic [31:0] complete_stack_addr_r;
    logic [31:0] complete_stack_data_r;
    logic [31:0] complete_stack_esp_r;
    logic        complete_t2_wr_r;
    logic [31:0] complete_t2_data_r;
    logic [1:0]  complete_sr_r;

    function automatic logic is_push(input logic [7:0] sid);
        return (sid == PUSH16) || (sid == PUSH32);
    endfunction

    function automatic logic is_pop(input logic [7:0] sid);
        return (sid == POP16) || (sid == POP32);
    endfunction

    function automatic logic [31:0] width_bytes(input logic [7:0] sid);
        return ((sid == PUSH16) || (sid == POP16)) ? 32'd2 : 32'd4;
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r                <= ST_IDLE;
            svc_id_r               <= SVC_NULL;
            pop_addr_r             <= 32'h0;
            next_esp_r             <= 32'h0;
            pop_data_r             <= 32'h0;
            complete_stack_write_r <= 1'b0;
            complete_stack_addr_r  <= 32'h0;
            complete_stack_data_r  <= 32'h0;
            complete_stack_esp_r   <= 32'h0;
            complete_t2_wr_r       <= 1'b0;
            complete_t2_data_r     <= 32'h0;
            complete_sr_r          <= SR_WAIT;
        end else begin
            if (state_r == ST_DONE)
                state_r <= ST_IDLE;

            case (state_r)
                ST_IDLE: begin
                    complete_stack_write_r <= 1'b0;
                    complete_t2_wr_r       <= 1'b0;
                    complete_sr_r          <= SR_WAIT;

                    if (svc_req) begin
                        svc_id_r <= svc_id;
                        if (is_push(svc_id)) begin
                            state_r                <= ST_DONE;
                            complete_sr_r          <= SR_OK;
                            complete_stack_write_r <= 1'b1;
                            complete_stack_addr_r  <= esp_in - width_bytes(svc_id);
                            complete_stack_data_r  <= push_data;
                            complete_stack_esp_r   <= esp_in - width_bytes(svc_id);
                            complete_t2_wr_r       <= 1'b0;
                        end else if (is_pop(svc_id)) begin
                            state_r    <= ST_POP_WAIT;
                            pop_addr_r <= esp_in;
                            next_esp_r <= esp_in + width_bytes(svc_id);
                        end else begin
                            state_r       <= ST_DONE;
                            complete_sr_r <= SR_FAULT;
                        end
                    end
                end

                ST_POP_WAIT: begin
                    if (stk_rd_ready) begin
                        state_r                <= ST_DONE;
                        complete_sr_r          <= SR_OK;
                        pop_data_r             <= stk_rd_data;
                        complete_stack_write_r <= 1'b0;
                        complete_stack_addr_r  <= pop_addr_r;
                        complete_stack_data_r  <= 32'h0;
                        complete_stack_esp_r   <= next_esp_r;
                        complete_t2_wr_r       <= 1'b1;
                        complete_t2_data_r     <= stk_rd_data;
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

    always_comb begin
        svc_done         = (state_r == ST_DONE);
        svc_sr           = (state_r == ST_DONE) ? complete_sr_r : SR_WAIT;

        stk_rd_req       = (state_r == ST_POP_WAIT);
        stk_rd_addr      = pop_addr_r;

        t2_wr_en         = (state_r == ST_DONE) ? complete_t2_wr_r : 1'b0;
        t2_wr_data       = complete_t2_data_r;

        pc_stack_en      = (state_r == ST_DONE) && (complete_sr_r == SR_OK);
        pc_stack_write_en= complete_stack_write_r;
        pc_stack_addr    = complete_stack_addr_r;
        pc_stack_data    = complete_stack_data_r;
        pc_stack_esp_val = complete_stack_esp_r;
    end

endmodule
