// Keystone86 / Aegis
// rtl/core/prefetch_queue.sv
//
// Rung 2 / Rung 3 front-end queue
//
// Ownership:
//   - owns instruction byte buffering
//   - owns queue flush execution
//   - owns byte-valid/empty status
//   - owns consume-one-byte interface for decoder
//
// Must NOT:
//   - classify bytes
//   - interpret opcodes
//   - self-initiate redirects
//   - own the redirect address source
//
// Bounded Rung 3 intent:
//   - flush is the authoritative committed redirect boundary
//   - kill/squash is stale-work cleanup only
//   - kill must not discard the first post-flush target byte
//
// Active repair:
//   A committed CALL redirect is correct upstream, but the first byte at the
//   redirected target is being lost before decode, causing RET at the target
//   to be skipped. The bounded repair here is to protect the first post-flush
//   fetch window from a coincident/next-cycle kill pulse, while preserving the
//   existing Rung 2 committed redirect behavior.

module prefetch_queue #(
    parameter int DEPTH = 4    // must be power of 2
) (
    input  logic        clk,
    input  logic        reset_n,

    // --- Flush (from commit_engine only — authoritative redirect) ---
    input  logic        flush,              // synchronous flush with new address
    input  logic [31:0] flush_addr,         // new fetch address after flush

    // --- Kill (from microsequencer squash — stale-work kill, no address) ---
    input  logic        kill,               // clear stale queue work, no redirect ownership

    // --- Byte output to decoder ---
    output logic [7:0]  q_data,
    output logic        q_valid,
    input  logic        q_consume,

    // --- Current fetch EIP (for decoder position-proven capture) ---
    output logic [31:0] q_fetch_eip,

    // --- Bus fetch interface ---
    output logic        fetch_req,
    output logic [31:0] fetch_addr,
    input  logic        fetch_done,
    input  logic [7:0]  fetch_data
);

    localparam int PTR_W = $clog2(DEPTH);

    logic [7:0]  mem     [0:DEPTH-1];
    logic [31:0] eip_mem [0:DEPTH-1];
    logic [PTR_W:0] head, tail;

    logic [31:0] fetch_ptr;
    logic        fetch_inflight;
    logic        queue_ready;

    // One-cycle protection window after an authoritative redirect.
    // This prevents a trailing kill pulse from discarding the first
    // post-flush target byte/window.
    logic        post_flush_protect;

    logic [PTR_W:0] count;
    logic           queue_full;

    assign count       = tail - head;
    assign q_data      = mem[head[PTR_W-1:0]];
    assign q_valid     = (count > 0) && queue_ready;
    assign q_fetch_eip = eip_mem[head[PTR_W-1:0]];
    assign queue_full  = (count == DEPTH[PTR_W:0]);

    // Fetch only when ready, not full, no inflight, and not during a same-cycle
    // authoritative flush. kill does not own redirect state and must not block
    // the redirected fetch window after flush protection is established.
    assign fetch_req  = queue_ready && !queue_full && !fetch_inflight && !flush;
    assign fetch_addr = fetch_ptr;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head               <= '0;
            tail               <= '0;
            fetch_ptr          <= 32'h0;
            fetch_inflight     <= 1'b0;
            queue_ready        <= 1'b0;
            post_flush_protect <= 1'b0;
        end else if (flush) begin
            // Authoritative redirect from commit_engine.
            // Clears queue, retargets fetch to the committed address, and arms
            // a one-cycle protection window so the first redirected target byte
            // cannot be discarded by a trailing squash/kill.
            head               <= '0;
            tail               <= '0;
            fetch_ptr          <= flush_addr;
            fetch_inflight     <= 1'b0;
            queue_ready        <= 1'b1;
            post_flush_protect <= 1'b1;
        end else if (kill && !post_flush_protect) begin
            // Stale-work kill away from a fresh committed redirect.
            // Clear buffered stale bytes and cancel inflight work, but do not
            // retarget fetch_ptr here because commit_engine owns redirect state.
            head               <= '0;
            tail               <= '0;
            fetch_inflight     <= 1'b0;
            queue_ready        <= 1'b0;   // wait for the authoritative flush
            post_flush_protect <= 1'b0;
        end else begin
            // Protection window lasts exactly one non-flush cycle.
            if (post_flush_protect)
                post_flush_protect <= 1'b0;

            // Normal operation
            if (fetch_req && !fetch_inflight)
                fetch_inflight <= 1'b1;

            if (fetch_inflight && fetch_done) begin
                fetch_inflight                <= 1'b0;
                mem    [tail[PTR_W-1:0]]      <= fetch_data;
                eip_mem[tail[PTR_W-1:0]]      <= fetch_ptr;
                tail                          <= tail + 1'b1;
                fetch_ptr                     <= fetch_ptr + 32'h1;
            end

            if (q_consume && q_valid)
                head <= head + 1'b1;
        end
    end

endmodule