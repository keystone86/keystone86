// Keystone86 / Aegis
// rtl/core/services/fetch_engine.sv
//
// Current phase support:
//   FETCH_IMM8
//   FETCH_DISP8
//   FETCH_DISP16
//   FETCH_DISP32
//
// Root-cause fix:
//   Consume the first displacement byte immediately on the service-start cycle
//   when q_valid is already present. The previous version waited until a later
//   cycle and ended up consuming the next opcode byte instead.
//
// Result is written to T4. FETCH_IMM8 is zero-extended for the Rung 5
// interrupt vector path; DISP8/DISP16 remain sign-extended displacements.

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

    logic        complete_pending_r;
    logic [31:0] complete_data_r;

    function automatic logic [2:0] bytes_for_service(input logic [7:0] sid);
        case (sid)
            FETCH_IMM8:  return 3'd1;
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
            FETCH_IMM8:   return {24'h0, accum_next[7:0]};
            default:      return accum_next;
        endcase
    endfunction

    logic [2:0]  start_bytes;
    logic        start_valid;
    logic        start_with_byte;
    logic [31:0] start_accum;
    logic        start_last_byte;

    logic [31:0] active_accum_next;
    logic        active_last_byte;

    assign start_bytes     = bytes_for_service(svc_id);
    assign start_valid     = (!active_r) && svc_req && (start_bytes != 3'd0);
    assign start_with_byte = start_valid && q_valid;
    assign start_accum     = pack_next_accum(32'h0, 3'd0, q_data);
    assign start_last_byte = start_with_byte && (start_bytes == 3'd1);

    assign active_accum_next = pack_next_accum(accum_r, idx_r, q_data);
    assign active_last_byte  = active_r && q_valid && ((idx_r + 3'd1) == total_bytes_r);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_r           <= 1'b0;
            svc_id_r           <= 8'h00;
            accum_r            <= 32'h0;
            idx_r              <= 3'd0;
            total_bytes_r      <= 3'd0;
            complete_pending_r <= 1'b0;
            complete_data_r    <= 32'h0;
        end else if (squash) begin
            active_r           <= 1'b0;
            svc_id_r           <= 8'h00;
            accum_r            <= 32'h0;
            idx_r              <= 3'd0;
            total_bytes_r      <= 3'd0;
            complete_pending_r <= 1'b0;
            complete_data_r    <= 32'h0;
        end else begin
            // completion pulse lasts one cycle unless re-armed below
            complete_pending_r <= 1'b0;

            // Start a new service
            if (start_valid) begin
                if (start_with_byte) begin
                    if (start_last_byte) begin
                        // 1-byte fetch completed immediately on start cycle.
                        // FETCH_IMM8 is only a vector byte handoff here; INT
                        // entry policy remains in microcode/interrupt service.
                        active_r           <= 1'b0;
                        svc_id_r           <= 8'h00;
                        accum_r            <= 32'h0;
                        idx_r              <= 3'd0;
                        total_bytes_r      <= 3'd0;
                        complete_pending_r <= 1'b1;
                        complete_data_r    <= finalize_disp(svc_id, start_accum);
                    end else begin
                        // consumed first byte immediately; keep running
                        active_r      <= 1'b1;
                        svc_id_r      <= svc_id;
                        accum_r       <= start_accum;
                        idx_r         <= 3'd1;
                        total_bytes_r <= start_bytes;
                    end
                end else begin
                    // service started, waiting for first byte
                    active_r      <= 1'b1;
                    svc_id_r      <= svc_id;
                    accum_r       <= 32'h0;
                    idx_r         <= 3'd0;
                    total_bytes_r <= start_bytes;
                end
            end
            // Continue an active service
            else if (active_r && q_valid) begin
                if (active_last_byte) begin
                    active_r           <= 1'b0;
                    svc_id_r           <= 8'h00;
                    accum_r            <= 32'h0;
                    idx_r              <= 3'd0;
                    total_bytes_r      <= 3'd0;
                    complete_pending_r <= 1'b1;
                    complete_data_r    <= finalize_disp(svc_id_r, active_accum_next);
                end else begin
                    accum_r <= active_accum_next;
                    idx_r   <= idx_r + 3'd1;
                end
            end
        end
    end

    always_comb begin
        svc_done   = complete_pending_r;
        svc_sr     = complete_pending_r ? SR_OK : SR_WAIT;
        q_consume  = 1'b0;
        t4_wr_en   = complete_pending_r;
        t4_wr_data = complete_data_r;

        // Consume first byte immediately on start if available
        if (start_with_byte) begin
            q_consume = 1'b1;
        end
        // Otherwise consume bytes while active
        else if (active_r && q_valid) begin
            q_consume = 1'b1;
        end
    end

endmodule
