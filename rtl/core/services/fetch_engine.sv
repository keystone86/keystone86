// Keystone86 / Aegis
// rtl/core/services/fetch_engine.sv
//
// Current phase support:
//   FETCH_DISP8
//   FETCH_DISP16
//   FETCH_DISP32
//
// Result is written to T4 as a sign-extended displacement for DISP8/DISP16,
// or raw 32-bit value for DISP32.

import keystone86_pkg::*;

module fetch_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [7:0]  q_data,
    input  logic        q_valid,
    output logic        q_consume,
    input  logic [31:0] q_fetch_eip,

    output logic        t4_wr_en,
    output logic [31:0] t4_wr_data,

    input  logic        squash
);

    logic        active_r;
    logic [7:0]  svc_id_r;
    logic [31:0] accum_r;
    logic [2:0]  idx_r;
    logic [2:0]  total_bytes_r;

    function automatic logic [2:0] bytes_for_service(input logic [7:0] sid);
        case (sid)
            FETCH_DISP8:  return 3'd1;
            FETCH_DISP16: return 3'd2;
            FETCH_DISP32: return 3'd4;
            default:      return 3'd0;
        endcase
    endfunction

    function automatic logic [31:0] pack_next_accum(
        input logic [31:0] cur,
        input logic [2:0]  idx,
        input logic [7:0]  byte_in
    );
        logic [31:0] tmp;
        begin
            tmp = cur;
            case (idx)
                3'd0: tmp[7:0]   = byte_in;
                3'd1: tmp[15:8]  = byte_in;
                3'd2: tmp[23:16] = byte_in;
                3'd3: tmp[31:24] = byte_in;
                default: ;
            endcase
            return tmp;
        end
    endfunction

    function automatic logic [31:0] finalize_disp(
        input logic [7:0] sid,
        input logic [31:0] accum_next
    );
        case (sid)
            FETCH_DISP8:  return {{24{accum_next[7]}},  accum_next[7:0]};
            FETCH_DISP16: return {{16{accum_next[15]}}, accum_next[15:0]};
            default:      return accum_next;
        endcase
    endfunction

    logic [31:0] accum_next_byte;
    logic        last_byte;

    assign accum_next_byte = pack_next_accum(accum_r, idx_r, q_data);
    assign last_byte       = (idx_r + 3'd1 == total_bytes_r);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_r      <= 1'b0;
            svc_id_r      <= 8'h00;
            accum_r       <= 32'h0;
            idx_r         <= 3'd0;
            total_bytes_r <= 3'd0;
        end else if (squash) begin
            active_r      <= 1'b0;
            svc_id_r      <= 8'h00;
            accum_r       <= 32'h0;
            idx_r         <= 3'd0;
            total_bytes_r <= 3'd0;
        end else begin
            if (!active_r && svc_req) begin
                if (bytes_for_service(svc_id) != 3'd0) begin
                    active_r      <= 1'b1;
                    svc_id_r      <= svc_id;
                    accum_r       <= 32'h0;
                    idx_r         <= 3'd0;
                    total_bytes_r <= bytes_for_service(svc_id);
                end
            end else if (active_r && q_valid) begin
                if (last_byte) begin
                    active_r      <= 1'b0;
                    svc_id_r      <= 8'h00;
                    accum_r       <= 32'h0;
                    idx_r         <= 3'd0;
                    total_bytes_r <= 3'd0;
                end else begin
                    accum_r <= accum_next_byte;
                    idx_r   <= idx_r + 3'd1;
                end
            end
        end
    end

    always_comb begin
        svc_done  = 1'b0;
        svc_sr    = SR_WAIT;
        q_consume = 1'b0;
        t4_wr_en  = 1'b0;
        t4_wr_data = 32'h0;

        if (active_r) begin
            if (q_valid) begin
                q_consume = 1'b1;
                if (last_byte) begin
                    svc_done   = 1'b1;
                    svc_sr     = SR_OK;
                    t4_wr_en   = 1'b1;
                    t4_wr_data = finalize_disp(svc_id_r, accum_next_byte);
                end
            end else begin
                svc_done = 1'b1;
                svc_sr   = SR_WAIT;
            end
        end
    end

endmodule