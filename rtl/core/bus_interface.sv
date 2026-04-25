// Keystone86 / Aegis
// rtl/core/bus_interface.sv
// Rung 0/3: Minimal shared bus interface
//
// Ownership (Appendix B):
//   This module owns: external bus signal generation, aligned fetch
//   transactions, EU memory transactions, ready handshake, and arbitration.
//   This module must NOT: know instruction meaning, contain policy logic,
//   know anything about the CPU instruction stream beyond addresses.
//
// Current bounded scope:
//   - instruction byte fetches for the prefetch queue
//   - aligned 32-bit EU stack reads/writes for the Rung 3 CALL/RET path
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

    // --- EU memory request (from services / commit staging) ---
    input  logic        eu_req,
    input  logic        eu_wr,
    input  logic [31:0] eu_addr,
    input  logic [3:0]  eu_byteen,
    input  logic [31:0] eu_wdata,
    output logic        eu_done,
    output logic [31:0] eu_rdata,

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
        S_BUS    = 2'b01,
        S_DONE   = 2'b10
    } bus_state_t;

    bus_state_t state, state_next;

    // Latch incoming request
    logic [31:0] addr_latch;
    logic [31:0] data_latch;
    logic [3:0]  byteen_latch;
    logic [31:0] wdata_latch;
    logic        wr_latch;
    logic        eu_latch;

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= S_IDLE;
            addr_latch <= 32'h0;
            data_latch <= 32'h0;
            byteen_latch <= 4'h0;
            wdata_latch  <= 32'h0;
            wr_latch     <= 1'b0;
            eu_latch     <= 1'b0;
        end else begin
            state <= state_next;
            if (state == S_IDLE && eu_req) begin
                addr_latch   <= eu_addr;
                byteen_latch <= eu_byteen;
                wdata_latch  <= eu_wdata;
                wr_latch     <= eu_wr;
                eu_latch     <= 1'b1;
            end else if (state == S_IDLE && fetch_req) begin
                addr_latch   <= fetch_addr;
                byteen_latch <= 4'b0001;
                wdata_latch  <= 32'h0;
                wr_latch     <= 1'b0;
                eu_latch     <= 1'b0;
            end
            if (state == S_BUS && bus_ready)
                data_latch <= bus_din;
        end
    end

    // ----------------------------------------------------------------
    // Next-state logic
    // ----------------------------------------------------------------
    always_comb begin
        state_next = state;
        case (state)
            S_IDLE:  if (eu_req || fetch_req)      state_next = S_BUS;
            S_BUS:   if (bus_ready)                state_next = S_DONE;
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
        bus_wr      = 1'b0;
        bus_byteen  = 4'b0001;
        bus_dout    = 32'h0;
        fetch_done  = 1'b0;
        fetch_data  = 8'h0;
        eu_done     = 1'b0;
        eu_rdata    = 32'h0;

        case (state)
            S_BUS: begin
                bus_addr   = addr_latch;
                bus_rd     = !wr_latch;
                bus_wr     = wr_latch;
                bus_byteen = byteen_latch;
                bus_dout   = wdata_latch;
            end
            S_DONE: begin
                if (eu_latch) begin
                    eu_done  = 1'b1;
                    eu_rdata = data_latch;
                end else begin
                    fetch_done = 1'b1;
                    fetch_data = data_latch_byte;
                end
            end
            default: ;
        endcase
    end

endmodule
