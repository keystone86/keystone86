// Keystone86 / Aegis
// rtl/core/prefetch_queue.sv
// Rung 0: Minimal instruction byte prefetch queue
//
// Ownership (Appendix B):
//   This module owns: instruction byte buffering, queue flush execution,
//   byte-valid/empty status, consume-one-byte interface for decoder.
//   This module must NOT: classify bytes, interpret opcodes,
//   self-initiate flushes (only commit_engine initiates flush),
//   own or hardcode the reset fetch address.
//
// Reset fetch address ownership:
//   The reset fetch address is owned exclusively by commit_engine.
//   On the first cycle after reset, commit_engine asserts flush=1 with
//   flush_addr=32'hFFFFFFF0. This module receives that flush and begins
//   fetching from that address. There is NO hardcoded reset vector here.
//   This preserves the Appendix B rule that commit_engine is the single
//   owner of architectural reset state.
//
// Rung 0 scope: 4-byte circular buffer, single byte consume,
// flush on commit_engine request, bus fetch interface.

module prefetch_queue #(
    parameter int DEPTH = 4    // must be power of 2
) (
    input  logic        clk,
    input  logic        reset_n,

    // --- Flush (from commit_engine only) ---
    input  logic        flush,              // synchronous flush
    input  logic [31:0] flush_addr,         // new fetch address after flush

    // --- Byte output to decoder ---
    output logic [7:0]  q_data,             // next byte available
    output logic        q_valid,            // queue has at least one byte
    input  logic        q_consume,          // decoder consumed one byte

    // --- Current fetch EIP (for decoder M_NEXT_EIP) ---
    output logic [31:0] q_fetch_eip,        // EIP of byte at q_data head

    // --- Bus fetch interface ---
    output logic        fetch_req,          // request one byte from bus
    output logic [31:0] fetch_addr,         // address to fetch
    input  logic        fetch_done,         // bus returns data
    input  logic [7:0]  fetch_data          // fetched byte
);

    // ----------------------------------------------------------------
    // Queue storage
    // ----------------------------------------------------------------
    localparam int PTR_W = $clog2(DEPTH);

    logic [7:0]  mem    [0:DEPTH-1];
    logic [31:0] eip_mem[0:DEPTH-1];   // EIP of each buffered byte
    logic [PTR_W:0] head, tail;         // one extra bit for full/empty

    // ----------------------------------------------------------------
    // Fetch pointer (next address to request from bus)
    // ----------------------------------------------------------------
    logic [31:0] fetch_ptr;
    logic        fetch_inflight;        // bus fetch in progress
    logic        queue_ready;           // flush received, ready to fetch

    // ----------------------------------------------------------------
    // Derived signals
    // ----------------------------------------------------------------
    logic [PTR_W:0] count;
    assign count      = tail - head;
    assign q_data     = mem[head[PTR_W-1:0]];
    assign q_valid    = (count > 0) && queue_ready;
    assign q_fetch_eip = eip_mem[head[PTR_W-1:0]];

    logic queue_full;
    assign queue_full = (count == DEPTH[PTR_W:0]);

    // Only issue fetch when ready (flush received), queue not full, no inflight
    assign fetch_req  = queue_ready && !queue_full && !fetch_inflight && !flush;
    assign fetch_addr = fetch_ptr;

    // ----------------------------------------------------------------
    // Sequential logic
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head          <= '0;
            tail          <= '0;
            fetch_ptr     <= 32'h0;     // NO hardcoded reset address here
            fetch_inflight <= 1'b0;
            queue_ready   <= 1'b0;      // wait for flush from commit_engine
        end else if (flush) begin
            // Flush with new address from commit_engine
            head           <= '0;
            tail           <= '0;
            fetch_ptr      <= flush_addr;  // address from commit_engine
            fetch_inflight <= 1'b0;
            queue_ready    <= 1'b1;        // now ready to fetch
        end else begin
            // Track in-flight fetch
            if (fetch_req && !fetch_inflight)
                fetch_inflight <= 1'b1;

            if (fetch_inflight && fetch_done) begin
                fetch_inflight <= 1'b0;
                mem    [tail[PTR_W-1:0]] <= fetch_data;
                eip_mem[tail[PTR_W-1:0]] <= fetch_ptr;
                tail       <= tail + 1'b1;
                fetch_ptr  <= fetch_ptr + 32'h1;
            end

            // Consume on decoder request
            if (q_consume && q_valid)
                head <= head + 1'b1;
        end
    end

endmodule
