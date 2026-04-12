// Keystone86 / Aegis
// sim/tb/tb_rung1_nop_loop.sv
// Rung 1 self-checking testbench: NOP + prefix-only classification and EIP advancement
//
// All tests are self-checking — no manual waveform inspection required.
//
// Tests:
//   Test 1:  decoder classifies 0x90 as ENTRY_NOP_XCHG_AX (0x13)
//   Test 2:  dispatch reaches uPC 0x020 (ENTRY_NOP_XCHG_AX)
//   Test 3:  no fault raised during NOP execution
//   Test 4:  architectural EIP advances by 1 after one NOP
//   Test 5:  microsequencer returns to FETCH_DECODE after NOP
//   Test 6:  10 consecutive NOPs execute without fault or deadlock
//   Test 7:  100 consecutive NOPs — zero spurious faults, stable decode
//   Test 8:  prefix-only: 0x66 classifies as ENTRY_PREFIX_ONLY (0x12),
//            dispatches to uPC 0x030, no fault, EIP+1, FETCH_DECODE return
//
// Memory model (ctrl_mem):
//   Returns 0x90 (NOP) normally.
//   When inject_prefix is held high by the testbench, the NEXT fetch
//   that starts (rd && !rd_pending) returns 0x66 instead of 0x90.
//   inject_prefix is raised after Test 7 completes and held until
//   prefix_classification_seen fires — guaranteeing the prefix byte
//   is delivered and observed while Test 8 is active.

`timescale 1ns/1ps

module tb_rung1_nop_loop;

    localparam int TIMEOUT           = 3000;
    localparam int CLK_HALF_PERIOD   = 5;
    localparam int NOP_RUN_LENGTH    = 100;

    localparam logic [11:0] EXPECTED_NOP_UPC    = 12'h020;
    localparam logic [11:0] EXPECTED_PREFIX_UPC = 12'h030;
    localparam logic [7:0]  EXPECTED_NOP_ENTRY  = 8'h13;
    localparam logic [7:0]  EXPECTED_PFX_ENTRY  = 8'h12;
    localparam logic [1:0]  MSEQ_FETCH_DECODE   = 2'h0;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic        clk, reset_n;
    logic [31:0] bus_addr;
    logic        bus_rd, bus_wr;
    logic [3:0]  bus_byteen;
    logic [31:0] bus_dout, bus_din;
    logic        bus_ready;

    logic [31:0] dbg_eip;
    logic [1:0]  dbg_mseq_state;
    logic [11:0] dbg_upc;
    logic [7:0]  dbg_entry_id;
    logic [7:0]  dbg_dec_entry_id;
    logic        dbg_endi_pulse;
    logic        dbg_fault_pending;
    logic [3:0]  dbg_fault_class;
    logic        dbg_decode_done;
    logic [31:0] dbg_fetch_addr;

    // inject_prefix: held high by testbench from Test 7 completion until
    // the decoder classifies the prefix byte (prefix_classification_seen).
    logic inject_prefix;

    // ----------------------------------------------------------------
    // DUT + memory
    // ----------------------------------------------------------------
    cpu_top dut (
        .clk               (clk),   .reset_n          (reset_n),
        .bus_addr          (bus_addr), .bus_rd         (bus_rd),
        .bus_wr            (bus_wr),   .bus_byteen     (bus_byteen),
        .bus_dout          (bus_dout), .bus_din        (bus_din),
        .bus_ready         (bus_ready),
        .dbg_eip           (dbg_eip),
        .dbg_mseq_state    (dbg_mseq_state),
        .dbg_upc           (dbg_upc),
        .dbg_entry_id      (dbg_entry_id),
        .dbg_dec_entry_id  (dbg_dec_entry_id),
        .dbg_endi_pulse    (dbg_endi_pulse),
        .dbg_fault_pending (dbg_fault_pending),
        .dbg_fault_class   (dbg_fault_class),
        .dbg_decode_done   (dbg_decode_done),
        .dbg_fetch_addr    (dbg_fetch_addr)
    );

    ctrl_mem u_mem (
        .clk           (clk),    .reset_n       (reset_n),
        .addr          (bus_addr), .rd          (bus_rd),
        .inject_prefix (inject_prefix),
        .dout          (bus_din), .ready        (bus_ready)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ----------------------------------------------------------------
    // Counters and state
    // ----------------------------------------------------------------
    int   pass_count, fail_count, cycle_count;
    int   nop_count, nop_fault_count, prefix_fault_count;

    logic test1_done, test2_done, test3_done, test4_done;
    logic test5_done, test6_done, test7_done, test8_done;

    logic [31:0] eip_at_first_nop_decode, eip_at_prefix_decode;
    logic        eip_at_first_nop_captured, eip_at_prefix_captured;

    logic [7:0]  last_decoded_entry;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) last_decoded_entry <= 8'h0;
        else if (dbg_decode_done) last_decoded_entry <= dbg_dec_entry_id;
    end

    logic prefix_test_armed;
    logic prefix_classification_seen;
    logic prefix_upc_seen;
    logic prefix_endi_seen, prefix_endi_latch;
    logic prefix_fetch_decode_seen;
    logic test8_triggered, test8_ready;
    logic [31:0] test8_eip_snap;
    logic first_nop_endi_seen, nop_endi_latch;
    logic test4_triggered;

    // ----------------------------------------------------------------
    // Watchdog
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count++;
            if (cycle_count >= TIMEOUT) begin
                $display("FAIL: Timeout after %0d cycles", TIMEOUT);
                $display("  NOPs=%0d  test_done=%b%b%b%b%b%b%b%b",
                    nop_count,
                    test1_done,test2_done,test3_done,test4_done,
                    test5_done,test6_done,test7_done,test8_done);
                $finish;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 1: 0x90 -> ENTRY_NOP_XCHG_AX
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_decode_done && !test1_done) begin
            if (dbg_dec_entry_id === EXPECTED_NOP_ENTRY) begin
                $display("PASS Test 1: 0x90 -> ENTRY_NOP_XCHG_AX (0x%02X)", dbg_dec_entry_id);
                pass_count++;
            end else begin
                $display("FAIL Test 1: entry_id=0x%02X expected 0x%02X",
                         dbg_dec_entry_id, EXPECTED_NOP_ENTRY);
                fail_count++;
            end
            test1_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test 2: uPC 0x020
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_upc === EXPECTED_NOP_UPC && !test2_done) begin
            $display("PASS Test 2: uPC=0x%03X (ENTRY_NOP_XCHG_AX dispatch)", dbg_upc);
            pass_count++;
            test2_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test 3: no fault on first NOP ENDI
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            if (!eip_at_first_nop_captured && dbg_decode_done &&
                    dbg_dec_entry_id === EXPECTED_NOP_ENTRY) begin
                eip_at_first_nop_captured <= 1'b1;
                eip_at_first_nop_decode   <= dbg_eip;
            end
            if (dbg_endi_pulse && eip_at_first_nop_captured &&
                    last_decoded_entry === EXPECTED_NOP_ENTRY && !first_nop_endi_seen) begin
                first_nop_endi_seen = 1'b1;
                if (!dbg_fault_pending && !test3_done) begin
                    $display("PASS Test 3: no fault during NOP (fault_pending=0)");
                    pass_count++; test3_done = 1'b1;
                end else if (!test3_done) begin
                    $display("FAIL Test 3: fault_pending=1 fc=0x%X", dbg_fault_class);
                    fail_count++; test3_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 4: EIP+1 after first NOP
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && first_nop_endi_seen && !test4_triggered) begin
            test4_triggered = 1'b1;
            @(posedge clk);
            if (!test4_done) begin
                if (dbg_eip === eip_at_first_nop_decode + 32'h1) begin
                    $display("PASS Test 4: EIP+1 after NOP (0x%08X -> 0x%08X)",
                             eip_at_first_nop_decode, dbg_eip);
                    pass_count++;
                end else begin
                    $display("FAIL Test 4: EIP=0x%08X, expected 0x%08X",
                             dbg_eip, eip_at_first_nop_decode + 32'h1);
                    fail_count++;
                end
                test4_done = 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 5: FETCH_DECODE return after NOP
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_endi_pulse && eip_at_first_nop_captured)
            nop_endi_latch <= 1'b1;
        if (reset_n && nop_endi_latch &&
                dbg_mseq_state === MSEQ_FETCH_DECODE && !test5_done) begin
            $display("PASS Test 5: microsequencer returned to FETCH_DECODE after NOP");
            pass_count++; test5_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Tests 6/7: 10 and 100 consecutive NOPs
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            if (dbg_endi_pulse && last_decoded_entry === EXPECTED_NOP_ENTRY)
                nop_count++;
            if (test1_done && !test7_done && dbg_fault_pending)
                nop_fault_count++;

            if (nop_count == 10 && !test6_done) begin
                if (nop_fault_count == 0) begin
                    $display("PASS Test 6: 10 consecutive NOPs, zero faults");
                    pass_count++;
                end else begin
                    $display("FAIL Test 6: 10 NOPs, %0d faults", nop_fault_count);
                    fail_count++;
                end
                test6_done = 1'b1;
            end

            if (nop_count == NOP_RUN_LENGTH && !test7_done) begin
                if (nop_fault_count == 0) begin
                    $display("PASS Test 7: %0d NOPs, zero spurious faults, decode stable",
                             NOP_RUN_LENGTH);
                    pass_count++;
                end else begin
                    $display("FAIL Test 7: %0d NOPs, %0d spurious faults",
                             NOP_RUN_LENGTH, nop_fault_count);
                    fail_count++;
                end
                test7_done        = 1'b1;
                prefix_test_armed = 1'b1;
                // Raise inject_prefix and hold it until prefix_classification_seen.
                // ctrl_mem will insert 0x66 on the next fetch transaction it starts.
                inject_prefix     = 1'b1;
            end
        end
    end

    // Lower inject_prefix once the decoder has classified the prefix byte.
    // This is a separate always block so it fires as soon as the decoder fires.
    always @(posedge clk) begin
        if (reset_n && prefix_classification_seen && inject_prefix)
            inject_prefix = 1'b0;
    end

    // ----------------------------------------------------------------
    // Test 8: prefix-only classification (0x66 -> ENTRY_PREFIX_ONLY)
    // ----------------------------------------------------------------

    // 8a: classification seen
    always @(posedge clk) begin
        if (reset_n && prefix_test_armed && dbg_decode_done &&
                dbg_dec_entry_id === EXPECTED_PFX_ENTRY &&
                !prefix_classification_seen) begin
            eip_at_prefix_captured    <= 1'b1;
            eip_at_prefix_decode      <= dbg_eip;
            prefix_classification_seen = 1'b1;
        end
    end

    // 8b: uPC 0x030
    always @(posedge clk) begin
        if (reset_n && prefix_test_armed &&
                dbg_upc === EXPECTED_PREFIX_UPC && !prefix_upc_seen)
            prefix_upc_seen = 1'b1;
    end

    // 8c: fault count during prefix phase
    always @(posedge clk) begin
        if (reset_n && prefix_test_armed && !prefix_endi_seen && dbg_fault_pending)
            prefix_fault_count++;
    end

    // 8d/e: ENDI fires, then FETCH_DECODE returns
    always @(posedge clk) begin
        if (reset_n && prefix_test_armed) begin
            if (dbg_endi_pulse && last_decoded_entry === EXPECTED_PFX_ENTRY &&
                    !prefix_endi_seen) begin
                prefix_endi_seen  = 1'b1;
                prefix_endi_latch = 1'b1;
            end
            if (prefix_endi_latch && dbg_mseq_state === MSEQ_FETCH_DECODE &&
                    !prefix_fetch_decode_seen)
                prefix_fetch_decode_seen = 1'b1;
            if (prefix_fetch_decode_seen && eip_at_prefix_captured && !test8_triggered) begin
                test8_triggered = 1'b1;
                test8_ready     = 1'b1;
            end
        end
    end

    // Test 8 reporting block — fires one cycle after test8_ready
    always @(posedge clk) begin
        if (reset_n && test8_ready && !test8_done) begin
            test8_eip_snap = dbg_eip;

            if (!prefix_classification_seen) begin
                $display("FAIL Test 8a: 0x66 not classified as ENTRY_PREFIX_ONLY");
                fail_count++;
            end
            if (!prefix_upc_seen) begin
                $display("FAIL Test 8b: uPC 0x030 not reached");
                fail_count++;
            end
            if (prefix_fault_count > 0) begin
                $display("FAIL Test 8c: %0d fault(s) during prefix", prefix_fault_count);
                fail_count++;
            end
            if (test8_eip_snap !== eip_at_prefix_decode + 32'h1) begin
                $display("FAIL Test 8d: EIP=0x%08X after prefix, expected 0x%08X",
                         test8_eip_snap, eip_at_prefix_decode + 32'h1);
                fail_count++;
            end
            if (!prefix_fetch_decode_seen) begin
                $display("FAIL Test 8e: FETCH_DECODE not reached after prefix");
                fail_count++;
            end

            if (prefix_classification_seen && prefix_upc_seen &&
                    prefix_fault_count == 0 &&
                    test8_eip_snap === eip_at_prefix_decode + 32'h1 &&
                    prefix_fetch_decode_seen) begin
                $display("PASS Test 8: 0x66 -> ENTRY_PREFIX_ONLY (0x%02X), uPC=0x%03X,",
                         EXPECTED_PFX_ENTRY, EXPECTED_PREFIX_UPC);
                $display("            no fault, EIP 0x%08X -> 0x%08X, FETCH_DECODE returned",
                         eip_at_prefix_decode, test8_eip_snap);
                pass_count++;
            end
            test8_done  = 1'b1;
            test8_ready = 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // Summary and finish
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && test1_done && test2_done && test3_done && test4_done &&
            test5_done && test6_done && test7_done && test8_done) begin
            $display("");
            $display("=== Rung 1 Testbench Summary ===");
            $display("  Cycles elapsed : %0d", cycle_count);
            $display("  NOPs completed : %0d", nop_count);
            $display("  PASS           : %0d", pass_count);
            $display("  FAIL           : %0d", fail_count);
            if (fail_count == 0)
                $display("  RESULT: ALL RUNG 1 TESTS PASSED");
            else
                $display("  RESULT: %0d TEST(S) FAILED", fail_count);
            $display("================================");
            $finish;
        end
    end

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        reset_n = 1'b0;
        cycle_count = 0; pass_count = 0; fail_count = 0;
        nop_count = 0; nop_fault_count = 0; prefix_fault_count = 0;
        test1_done = 0; test2_done = 0; test3_done = 0; test4_done = 0;
        test5_done = 0; test6_done = 0; test7_done = 0; test8_done = 0;
        eip_at_first_nop_captured = 0; eip_at_prefix_captured = 0;
        first_nop_endi_seen = 0; nop_endi_latch = 0;
        prefix_test_armed = 0; inject_prefix = 0;
        prefix_classification_seen = 0; prefix_upc_seen = 0;
        prefix_endi_seen = 0; prefix_endi_latch = 0;
        prefix_fetch_decode_seen = 0;
        test4_triggered = 0; test8_triggered = 0;
        test8_ready = 0; test8_eip_snap = 0;
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        $display("--- Reset released, Rung 1 NOP+PREFIX loop starting ---");
    end

endmodule

// ----------------------------------------------------------------
// ctrl_mem: testbench-controlled memory
//   - Returns 0x90 normally
//   - When inject_prefix=1 at the moment a new fetch starts (rd && !rd_pending),
//     that fetch returns 0x66 instead of 0x90
//   - After that one fetch completes, resumes returning 0x90
// ----------------------------------------------------------------
module ctrl_mem #(
    parameter int READY_LATENCY = 1
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [31:0] addr,
    input  logic        rd,
    input  logic        inject_prefix,
    output logic [31:0] dout,
    output logic        ready
);
    int unsigned latency_cnt;
    logic [7:0]  pending_byte;
    logic        rd_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            latency_cnt  <= 0;
            rd_pending   <= 1'b0;
            ready        <= 1'b0;
            dout         <= 32'h0;
            pending_byte <= 8'h90;
        end else begin
            ready <= 1'b0;
            if (rd && !rd_pending) begin
                // Latch inject_prefix at the moment this fetch starts.
                // If inject_prefix is currently held high, this fetch returns 0x66.
                pending_byte <= inject_prefix ? 8'h66 : 8'h90;
                rd_pending   <= 1'b1;
                latency_cnt  <= READY_LATENCY;
            end
            if (rd_pending) begin
                if (latency_cnt > 0)
                    latency_cnt <= latency_cnt - 1;
                else begin
                    dout       <= {24'h0, pending_byte};
                    ready      <= 1'b1;
                    rd_pending <= 1'b0;
                end
            end
        end
    end
endmodule
