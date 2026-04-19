// Keystone86 / Aegis
// rtl/core/prefetch_queue.sv
// Rung 2: Separate kill (squash) vs flush (redirect) inputs
//
// Ownership (Appendix B):
//   This module owns: instruction byte buffering, queue flush execution,
//   byte-valid/empty status, consume-one-byte interface for decoder.
//   This module must NOT: classify bytes, interpret opcodes,
//   self-initiate flushes (only commit_engine initiates flush),
//   own or hardcode the reset fetch address.
//
// Rung 2 additions:
//   kill input (from microsequencer squash):
//     - clears queue contents and cancels any inflight bus request
//     - does NOT change fetch_ptr
//     - may pause fetching until a later flush arrives if kill is used on its own
//   flush input (from commit_engine):
//     - is the authoritative redirect boundary
//     - clears queue contents and retargets fetch_ptr to the committed address
//
// In the active direct-JMP path, squash is intended to coincide with the
// committed redirect boundary so stale front-end work is cleared without
// introducing speculative dispatch-time cleanup.
//
// Reset fetch address ownership: unchanged — commit_engine is sole owner.

module prefetch_queue #(
    parameter int DEPTH = 4    // must be power of 2
) (
    input  logic        clk,
    input  logic        reset_n,

    // --- Flush (from commit_engine only — authoritative redirect) ---
    input  logic        flush,              // synchronous flush with new address
    input  logic [31:0] flush_addr,         // new fetch address after flush

    // --- Kill (from microsequencer squash — stale-work kill, no address) ---
    input  logic        kill,               // clear queue, pause until flush

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

    logic [7:0]  mem    [0:DEPTH-1];
    logic [31:0] eip_mem[0:DEPTH-1];
    logic [PTR_W:0] head, tail;

    logic [31:0] fetch_ptr;
    logic        fetch_inflight;
    logic        queue_ready;

    logic [PTR_W:0] count;
    assign count       = tail - head;
    assign q_data      = mem[head[PTR_W-1:0]];
    assign q_valid     = (count > 0) && queue_ready;
    assign q_fetch_eip = eip_mem[head[PTR_W-1:0]];

    logic queue_full;
    assign queue_full = (count == DEPTH[PTR_W:0]);

    // Fetch only when ready, not full, no inflight, not flushing/killing
    assign fetch_req  = queue_ready && !queue_full && !fetch_inflight
                        && !flush && !kill;
    assign fetch_addr = fetch_ptr;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head           <= '0;
            tail           <= '0;
            fetch_ptr      <= 32'h0;
            fetch_inflight <= 1'b0;
            queue_ready    <= 1'b0;
        end else if (flush) begin
            // Authoritative redirect from commit_engine.
            // Clears queue, retargets fetch to JMP target (or reset vector).
            head           <= '0;
            tail           <= '0;
            fetch_ptr      <= flush_addr;
            fetch_inflight <= 1'b0;
            queue_ready    <= 1'b1;
        end else if (kill) begin
            // Squash from microsequencer on control-transfer acceptance.
            // Clears queue contents and inflight; pauses until flush arrives.
            // fetch_ptr is NOT updated — commit_engine owns that via flush.
            head           <= '0;
            tail           <= '0;
            fetch_inflight <= 1'b0;
            queue_ready    <= 1'b0;   // pause: wait for commit_engine flush
        end else begin
            // Normal operation
            if (fetch_req && !fetch_inflight)
                fetch_inflight <= 1'b1;

            if (fetch_inflight && fetch_done) begin
                fetch_inflight <= 1'b0;
                mem    [tail[PTR_W-1:0]] <= fetch_data;
                eip_mem[tail[PTR_W-1:0]] <= fetch_ptr;
                tail       <= tail + 1'b1;
                fetch_ptr  <= fetch_ptr + 32'h1;
            end

            if (q_consume && q_valid)
                head <= head + 1'b1;
        end
    end

endmodule
