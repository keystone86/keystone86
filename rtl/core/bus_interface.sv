// Keystone86 / Aegis
// rtl/core/bus_interface.sv
// Rung 0: Minimal instruction fetch bus interface
//
// Ownership (Appendix B):
//   This module owns: external bus signal generation, aligned fetch
//   transactions, ready handshake.
//   This module must NOT: know instruction meaning, contain policy logic,
//   know anything about the CPU instruction stream beyond addresses.
//
// Rung 0 scope: instruction fetch read path only.
// Write path is stubbed for interface completeness.
//
// Shared constants: none used in this module.
// This module operates on plain logic signals only and requires no
// shared namespace imports.

module bus_interface (
    input  logic        clk,
    input  logic        reset_n,

    // --- EU fetch request (from prefetch_queue) ---
    input  logic        fetch_req,          // request a fetch
    input  logic [31:0] fetch_addr,         // fetch physical address
    output logic        fetch_done,         // data ready
    output logic [7:0]  fetch_data,         // fetched byte

    // --- External bus ---
    output logic [31:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,             // stub for Rung 0
    output logic [3:0]  bus_byteen,
    output logic [31:0] bus_dout,           // stub for Rung 0
    input  logic [31:0] bus_din,
    input  logic        bus_ready
);

    // ----------------------------------------------------------------
    // State machine
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE   = 2'b00,
        S_FETCH  = 2'b01,
        S_DONE   = 2'b10
    } bus_state_t;

    bus_state_t state, state_next;

    // Latch incoming request
    logic [31:0] addr_latch;
    logic [31:0] data_latch;

    // ----------------------------------------------------------------
    // Stub outputs (write path not used in Rung 0)
    // ----------------------------------------------------------------
    assign bus_wr   = 1'b0;
    assign bus_dout = 32'h0;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= S_IDLE;
            addr_latch <= 32'h0;
            data_latch <= 32'h0;
        end else begin
            state <= state_next;
            if (state == S_IDLE && fetch_req)
                addr_latch <= fetch_addr;
            if (state == S_FETCH && bus_ready)
                data_latch <= bus_din;
        end
    end

    // ----------------------------------------------------------------
    // Next-state logic
    // ----------------------------------------------------------------
    always_comb begin
        state_next = state;
        case (state)
            S_IDLE:  if (fetch_req)               state_next = S_FETCH;
            S_FETCH: if (bus_ready)                state_next = S_DONE;
            S_DONE:                                state_next = S_IDLE;
            default:                               state_next = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Output logic
    // data_latch_byte hoisted outside always_comb to avoid iverilog
    // "constant selects in always_* not supported" limitation.
    // ----------------------------------------------------------------
    logic [7:0] data_latch_byte;
    assign data_latch_byte = data_latch[7:0];

    always_comb begin
        bus_addr    = 32'h0;
        bus_rd      = 1'b0;
        bus_byteen  = 4'b0001;   // byte fetch for instruction stream
        fetch_done  = 1'b0;
        fetch_data  = 8'h0;

        case (state)
            S_FETCH: begin
                bus_addr   = addr_latch;
                bus_rd     = 1'b1;
                bus_byteen = 4'b0001;
            end
            S_DONE: begin
                fetch_done = 1'b1;
                fetch_data = data_latch_byte;
            end
            default: ;
        endcase
    end

endmodule
