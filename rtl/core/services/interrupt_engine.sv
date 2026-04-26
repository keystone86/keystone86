// Keystone86 / Aegis
// rtl/core/services/interrupt_engine.sv
//
// Bounded Rung 5 Pass 2 interrupt-entry service.
//
// Owns only the INT_ENTER leaf primitive for the accepted phase-1 real-mode
// contract: use the vector already fetched into T4, read the real-mode IVT
// entry, and stage candidate EIP/CS/FLAGS/ESP/frame bytes for commit_engine.
// It does not classify opcodes, choose instruction sequencing, or make any
// architectural state visible; microcode calls the service and ENDI/CM_INT is
// still the architectural boundary.

import keystone86_pkg::*;

module interrupt_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [7:0]  svc_id,
    input  logic        svc_req,
    output logic        svc_done,
    output logic [1:0]  svc_sr,

    input  logic [31:0] vector_in,
    input  logic [31:0] m_next_eip,
    input  logic [31:0] eflags_in,
    input  logic [31:0] esp_in,
    input  logic [15:0] cs_in,

    output logic        mem_rd_req,
    output logic [31:0] mem_rd_addr,
    input  logic [31:0] mem_rd_data,
    input  logic        mem_rd_ready,

    output logic        pc_int_en,
    output logic [31:0] pc_int_eip,
    output logic [15:0] pc_int_cs,
    output logic [31:0] pc_int_eflags,
    output logic [31:0] pc_int_esp,
    output logic [31:0] pc_int_frame_addr,
    output logic [47:0] pc_int_frame_bytes
);

    typedef enum logic [1:0] {
        IE_IDLE     = 2'h0,
        IE_IVT_WAIT = 2'h1,
        IE_DONE     = 2'h2
    } ie_state_t;

    ie_state_t state_r;

    logic [7:0]  vector_r;
    logic [15:0] return_ip_r;
    logic [15:0] return_cs_r;
    logic [15:0] return_flags_r;
    logic [31:0] frame_esp_r;

    logic [31:0] staged_eip_r;
    logic [15:0] staged_cs_r;
    logic [31:0] staged_eflags_r;
    logic [31:0] staged_esp_r;
    logic [47:0] staged_frame_r;
    logic [1:0]  staged_sr_r;

    function automatic logic [47:0] pack_frame(
        input logic [15:0] ip_word,
        input logic [15:0] cs_word,
        input logic [15:0] flags_word
    );
        // Final memory layout after the downward-growing pushes:
        // [ESP+0]=IP, [ESP+2]=CS, [ESP+4]=FLAGS, all little-endian.
        return {flags_word[15:8], flags_word[7:0],
                cs_word[15:8],    cs_word[7:0],
                ip_word[15:8],    ip_word[7:0]};
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_r            <= IE_IDLE;
            vector_r           <= 8'h0;
            return_ip_r        <= 16'h0;
            return_cs_r        <= 16'h0;
            return_flags_r     <= 16'h0;
            frame_esp_r        <= 32'h0;
            staged_eip_r       <= 32'h0;
            staged_cs_r        <= 16'h0;
            staged_eflags_r    <= 32'h0;
            staged_esp_r       <= 32'h0;
            staged_frame_r     <= 48'h0;
            staged_sr_r        <= SR_WAIT;
        end else begin
            if (state_r == IE_DONE)
                state_r <= IE_IDLE;

            case (state_r)
                IE_IDLE: begin
                    staged_sr_r <= SR_WAIT;

                    if (svc_req) begin
                        if (svc_id == INT_ENTER) begin
                            // T4 carries the zero-extended vector from
                            // FETCH_IMM8. Rung 5 Pass 2 uses 16-bit real-mode
                            // frame words and flat handler fetch EIP.
                            state_r        <= IE_IVT_WAIT;
                            vector_r       <= vector_in[7:0];
                            return_ip_r    <= m_next_eip[15:0];
                            return_cs_r    <= cs_in;
                            return_flags_r <= eflags_in[15:0];
                            frame_esp_r    <= esp_in - 32'd6;
                        end else begin
                            state_r     <= IE_DONE;
                            staged_sr_r <= SR_FAULT;
                        end
                    end
                end

                IE_IVT_WAIT: begin
                    if (mem_rd_ready) begin
                        state_r         <= IE_DONE;
                        staged_sr_r     <= SR_OK;
                        staged_eip_r    <= {16'h0, mem_rd_data[15:0]};
                        staged_cs_r     <= mem_rd_data[31:16];
                        staged_eflags_r <= eflags_in & ~(32'h1 << 9);
                        staged_esp_r    <= frame_esp_r;
                        staged_frame_r  <= pack_frame(return_ip_r,
                                                       return_cs_r,
                                                       return_flags_r);
                    end
                end

                default: state_r <= IE_IDLE;
            endcase
        end
    end

    always_comb begin
        svc_done           = (state_r == IE_DONE);
        svc_sr             = (state_r == IE_DONE) ? staged_sr_r : SR_WAIT;

        // IVT entries are four little-endian bytes at vector*4.
        mem_rd_req         = (state_r == IE_IVT_WAIT);
        mem_rd_addr        = {22'h0, vector_r, 2'b00};

        pc_int_en          = (state_r == IE_DONE) && (staged_sr_r == SR_OK);
        pc_int_eip         = staged_eip_r;
        pc_int_cs          = staged_cs_r;
        pc_int_eflags      = staged_eflags_r;
        pc_int_esp         = staged_esp_r;
        pc_int_frame_addr  = staged_esp_r;
        pc_int_frame_bytes = staged_frame_r;
    end

endmodule
