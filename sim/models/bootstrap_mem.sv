// Keystone86 / Aegis
// sim/models/bootstrap_mem.sv
// Rung 0: Deterministic bootstrap memory model
//
// Provides:
//   - Deterministic byte at reset vector 0xFFFFFFF0
//   - Byte at 0xFFFFFFF1 and beyond returns 0x00 (NOP-filler)
//   - Configurable ready latency (default 1 cycle, parameterized)
//   - NEVER produces unaligned accesses — byte-granular read only
//
// This is a simulation-only model. It has no RTL synthesis target.
// It is intentionally tiny and explicit.

module bootstrap_mem #(
    parameter int READY_LATENCY = 1    // cycles before ready asserted
) (
    input  logic        clk,
    input  logic        reset_n,

    // Bus interface (matches bus_interface expectations)
    input  logic [31:0] addr,
    input  logic        rd,
    output logic [31:0] dout,
    output logic        ready
);

    // ----------------------------------------------------------------
    // Memory contents
    // ----------------------------------------------------------------
    // Physical 0xFFFFFFF0: bootstrap content
    // We return 0x00 for all addresses — a known opcode byte (ADD [BX+SI], AL)
    // which will be routed to ENTRY_NULL, which is exactly what Rung 0 proves.
    //
    // Any nonzero value here would also work since the decoder stub
    // always returns ENTRY_NULL regardless of opcode. We use 0x00 for
    // determinism and easy waveform tracing.

    function automatic [7:0] mem_read(input [31:0] a);
        if (a == 32'hFFFFFFF0)
            return 8'h00;  // reset vector first byte
        else
            return 8'h00;  // filler for all other addresses
    endfunction

    // ----------------------------------------------------------------
    // Ready latency counter
    // ----------------------------------------------------------------
    int unsigned latency_cnt;
    logic [31:0] addr_latch;
    logic [7:0]  data_latch;
    logic        rd_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            latency_cnt <= 0;
            addr_latch  <= 32'h0;
            data_latch  <= 8'h0;
            rd_pending  <= 1'b0;
            ready       <= 1'b0;
            dout        <= 32'h0;
        end else begin
            ready <= 1'b0;

            if (rd && !rd_pending) begin
                addr_latch   <= addr;
                data_latch   <= mem_read(addr);
                rd_pending   <= 1'b1;
                latency_cnt  <= READY_LATENCY;
            end

            if (rd_pending) begin
                if (latency_cnt > 0) begin
                    latency_cnt <= latency_cnt - 1;
                end else begin
                    dout      <= {24'h0, data_latch};
                    ready     <= 1'b1;
                    rd_pending <= 1'b0;
                end
            end
        end
    end

endmodule
