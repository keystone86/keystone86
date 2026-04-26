// Keystone86 / Aegis
// sim/tb/tb_rung0_reset_loop.sv
// Rung 0 self-checking testbench
//
// Tests (all self-checking — no manual waveform inspection required):
//   Test A: first bus read after reset is at physical 0xFFFFFFF0
//   Test B: decoder asserts decode_done and emits ENTRY_NULL
//   Test C: dispatch table sends ENTRY_NULL to bootstrap uPC 0x010
//   Test D: RAISE FC_UD occurs
//   Test E: ENDI occurs
//   Test F: microsequencer returns to FETCH_DECODE (state 0)
//   Test G: machine does not deadlock for 200 cycles
//
// Pass criterion: all checks must pass without timeout.
// Timeout: simulation terminates with FAIL if not completed in TIMEOUT cycles.

`timescale 1ns/1ps

module tb_rung0_reset_loop;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam int TIMEOUT          = 200;
    localparam int CLK_HALF_PERIOD  = 5;   // 10ns period = 100MHz

    // Expected bootstrap values (from corrected dispatch.hex)
    localparam logic [11:0] EXPECTED_ENTRY_NULL_UPC = 12'h010;
    localparam logic [7:0]  EXPECTED_ENTRY_NULL_ID  = 8'h00;
    localparam logic [31:0] EXPECTED_RESET_FETCH    = 32'hFFFFFFF0;
    localparam logic [3:0]  EXPECTED_FC_UD          = 4'h6;  // FC_UD from Appendix A
    localparam logic [1:0]  MSEQ_FETCH_DECODE       = 2'h0;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic        clk;
    logic        reset_n;

    logic [31:0] bus_addr;
    logic        bus_rd;
    logic        bus_wr;
    logic [3:0]  bus_byteen;
    logic [31:0] bus_dout;
    logic [31:0] bus_din;
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

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    logic [31:0] dbg_esp_nc;

    cpu_top dut (
        .clk               (clk),
        .reset_n           (reset_n),
        .bus_addr          (bus_addr),
        .bus_rd            (bus_rd),
        .bus_wr            (bus_wr),
        .bus_byteen        (bus_byteen),
        .bus_dout          (bus_dout),
        .bus_din           (bus_din),
        .bus_ready         (bus_ready),
        .dbg_eip           (dbg_eip),
        .dbg_esp           (dbg_esp_nc),
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

    bootstrap_mem #(.READY_LATENCY(1)) u_mem (
        .clk      (clk),
        .reset_n  (reset_n),
        .addr     (bus_addr),
        .rd       (bus_rd),
        .wr       (bus_wr),
        .dout     (bus_din),
        .ready    (bus_ready)
    );

    // ----------------------------------------------------------------
    // Clock generation
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ----------------------------------------------------------------
    // Test state tracking
    // ----------------------------------------------------------------
    int pass_count;
    int fail_count;
    int cycle_count;

    logic test_a_done, test_b_done, test_c_done;
    logic test_d_done, test_e_done, test_f_done;

    logic first_fetch_seen;
    logic [31:0] first_fetch_addr;

    // ----------------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count++;
            if (cycle_count >= TIMEOUT) begin
                $display("FAIL: Timeout after %0d cycles — machine may be deadlocked", TIMEOUT);
                $display("  dbg_mseq_state = %0d", dbg_mseq_state);
                $display("  dbg_upc        = 0x%03X", dbg_upc);
                $display("  dbg_entry_id   = 0x%02X", dbg_entry_id);
                $display("  dbg_dec_entry_id = 0x%02X", dbg_dec_entry_id);
                $display("  dbg_decode_done= %b", dbg_decode_done);
                $finish;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test A: first bus read at 0xFFFFFFF0
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && bus_rd && !first_fetch_seen) begin
            first_fetch_seen = 1'b1;
            first_fetch_addr = bus_addr;
            if (bus_addr === EXPECTED_RESET_FETCH) begin
                $display("PASS Test A: first fetch at 0x%08X (correct reset vector)", bus_addr);
                pass_count++;
                test_a_done = 1'b1;
            end else begin
                $display("FAIL Test A: first fetch at 0x%08X, expected 0x%08X",
                         bus_addr, EXPECTED_RESET_FETCH);
                fail_count++;
                test_a_done = 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test B: decoder asserts decode_done with ENTRY_NULL
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_decode_done && !test_b_done) begin
            if (dbg_dec_entry_id === EXPECTED_ENTRY_NULL_ID) begin
                $display("PASS Test B: decode_done asserted, decoder entry_id=ENTRY_NULL (0x%02X)",
                         dbg_dec_entry_id);
                pass_count++;
            end else begin
                $display("FAIL Test B: decode_done asserted but decoder entry_id=0x%02X, expected 0x%02X",
                         dbg_dec_entry_id, EXPECTED_ENTRY_NULL_ID);
                fail_count++;
            end
            test_b_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test C: microsequencer uPC reaches 0x010 (ENTRY_NULL dispatch)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && (dbg_upc === EXPECTED_ENTRY_NULL_UPC) && !test_c_done) begin
            $display("PASS Test C: uPC reached 0x%03X (ENTRY_NULL dispatch address)",
                     dbg_upc);
            pass_count++;
            test_c_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test D: RAISE FC_UD occurs (fault_class = FC_UD = 0x6)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_fault_pending && !test_d_done) begin
            if (dbg_fault_class === EXPECTED_FC_UD) begin
                $display("PASS Test D: RAISE FC_UD staged (fault_class=0x%X = FC_UD)",
                         dbg_fault_class);
                pass_count++;
            end else begin
                $display("FAIL Test D: fault_pending=1 but fault_class=0x%X, expected FC_UD=0x%X",
                         dbg_fault_class, EXPECTED_FC_UD);
                fail_count++;
            end
            test_d_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test E: ENDI pulse occurs
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && dbg_endi_pulse && !test_e_done) begin
            $display("PASS Test E: ENDI occurred");
            pass_count++;
            test_e_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test F: microsequencer returns to FETCH_DECODE after ENDI
    // ----------------------------------------------------------------
    logic endi_was_seen;
    always @(posedge clk) begin
        if (reset_n && dbg_endi_pulse)
            endi_was_seen <= 1'b1;
        if (reset_n && endi_was_seen &&
            (dbg_mseq_state === MSEQ_FETCH_DECODE) && !test_f_done) begin
            $display("PASS Test F: microsequencer returned to FETCH_DECODE after ENDI");
            pass_count++;
            test_f_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test G: no deadlock (implicit — if all other tests pass within
    // TIMEOUT we have the stability proof)
    // ----------------------------------------------------------------

    // ----------------------------------------------------------------
    // Final check and summary
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && test_a_done && test_b_done && test_c_done &&
            test_d_done && test_e_done && test_f_done) begin
            // Let machine run for 10 more cycles to prove stability
            repeat (10) @(posedge clk);

            $display("");
            $display("=== Rung 0 Testbench Summary ===");
            $display("  Cycles elapsed: %0d", cycle_count);
            $display("  PASS: %0d", pass_count);
            $display("  FAIL: %0d", fail_count);
            if (fail_count == 0) begin
                $display("  RESULT: ALL TESTS PASSED");
                $display("PASS Test G: no deadlock — all tests completed in %0d cycles",
                         cycle_count);
            end else begin
                $display("  RESULT: %0d TESTS FAILED", fail_count);
            end
            $display("================================");
            $finish;
        end
    end

    // ----------------------------------------------------------------
    // Stimulus: reset then run
    // ----------------------------------------------------------------
    initial begin
        // Initialize
        reset_n        = 1'b0;
        cycle_count    = 0;
        pass_count     = 0;
        fail_count     = 0;
        first_fetch_seen = 1'b0;
        test_a_done    = 1'b0;
        test_b_done    = 1'b0;
        test_c_done    = 1'b0;
        test_d_done    = 1'b0;
        test_e_done    = 1'b0;
        test_f_done    = 1'b0;
        endi_was_seen  = 1'b0;

        // Hold reset for 4 cycles
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        $display("--- Reset released, Rung 0 loop starting ---");

        // Testbench self-manages completion via always blocks above
    end

endmodule
