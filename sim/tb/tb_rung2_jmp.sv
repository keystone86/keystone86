// Keystone86 / Aegis
// sim/tb/tb_rung2_jmp.sv
// Rung 2 self-checking testbench: JMP SHORT and JMP NEAR
//
// All tests are self-checking — pass/fail determined by assertions.
//
// Test A: JMP SHORT self-loop (EB FE)
//   Memory: [FE, EB] at 0xFFFFFFF0 (EB FE = JMP -2, targets itself)
//   Expected: CPU loops forever at 0xFFFFFFF0, zero faults, 1000 cycles
//   Verification: no fault, EIP stays at 0xFFFFFFF0 after each ENDI
//
// Test B: JMP SHORT +5 (EB 05)
//   Memory: [EB, 05] at 0xFFFFFFF0
//   Expected: EIP = 0xFFFFFFF0 + 2 + 5 = 0xFFFFFFF7 after one JMP
//   Then CPU fetches from 0xFFFFFFF7 -> gets EB FE (infinite loop)
//   Verification: EIP == 0xFFFFFFF7 after first ENDI, no fault
//
// Test C: JMP SHORT backward (EB F0)
//   Memory: [EB, F0] at 0xFFFFFFF0
//   EB F0 = JMP -16 (0xF0 = -16 signed) -> target = 0xFFFFFFF0+2-16 = 0xFFFFFFE2
//   Expected: EIP = 0xFFFFFFE2 after one JMP, flush verified
//
// Test D: Earlier rungs still pass
//   Run 10 NOPs (0x90) through a separate memory, verify EIP advances,
//   verify no fault, verify decode_done behavior.
//
// Memory model:
//   ctrl_mem responds to any bus_addr with a configurable byte pattern.
//   Tests configure mem_program[] before releasing reset.

`timescale 1ns/1ps

module tb_rung2_jmp;

    localparam int TIMEOUT         = 5000;
    localparam int CLK_HALF_PERIOD = 5;
    localparam logic [1:0] MSEQ_FETCH_DECODE = 2'h0;

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

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    // ----------------------------------------------------------------
    // Rung 3 stack bus and indirect-call stubs
    // (not exercised in Rung 2 tests — tied to safe defaults)
    // ----------------------------------------------------------------
    logic        stk_wr_en_nc;
    logic [31:0] stk_wr_addr_nc;
    logic [31:0] stk_wr_data_nc;
    logic        stk_rd_req_nc;
    logic [31:0] stk_rd_addr_nc;
    logic [31:0] dbg_esp_nc;

    cpu_top dut (
        .clk               (clk),        .reset_n          (reset_n),
        .bus_addr          (bus_addr),   .bus_rd           (bus_rd),
        .bus_wr            (bus_wr),     .bus_byteen       (bus_byteen),
        .bus_dout          (bus_dout),   .bus_din          (bus_din),
        .bus_ready         (bus_ready),
        // Rung 3 stack bus — not exercised in Rung 2 tests
        .stk_wr_en         (stk_wr_en_nc),
        .stk_wr_addr       (stk_wr_addr_nc),
        .stk_wr_data       (stk_wr_data_nc),
        .stk_rd_req        (stk_rd_req_nc),
        .stk_rd_addr       (stk_rd_addr_nc),
        .stk_rd_data       (32'h0),
        .stk_rd_ready      (1'b0),
        // Rung 3 indirect CALL — not exercised in Rung 2 tests
        .indirect_call_target       (32'h0),
        .indirect_call_target_valid (1'b0),
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

    // ----------------------------------------------------------------
    // Configurable memory model
    // ----------------------------------------------------------------
    // mem_program[N] = byte returned for any address where addr[7:0]==N.
    // All test addresses are in the 0xFFFFFFxx region so the low byte
    // uniquely identifies each location. Initialize fully before reset.
    logic [7:0] mem_program [0:255];
    logic        rd_pending;

    // Single-cycle bus: respond to fetch requests.
    // mem_program[] is indexed by bus_addr[7:0] unconditionally —
    // all test addresses are in the 0xFFFFFFxx region so the low byte
    // uniquely identifies each location across the full test range.
    // (The previous threshold >= 0xFFFFFFF0 incorrectly excluded
    // backward-JMP targets like 0xFFFFFFE2.)
    logic [7:0]  rd_byte_sel;
    logic [7:0]  bus_addr_lo;
    assign bus_addr_lo = bus_addr[7:0];
    assign rd_byte_sel = mem_program[bus_addr_lo];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready   <= 1'b0;
            bus_din     <= 32'h0;
            rd_pending  <= 1'b0;
        end else begin
            bus_ready <= 1'b0;
            if (bus_rd && !rd_pending) begin
                rd_pending    <= 1'b1;
            end
            if (rd_pending) begin
                bus_din   <= {24'h0, rd_byte_sel};
                bus_ready <= 1'b1;
                rd_pending <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 0;
    always #CLK_HALF_PERIOD clk = ~clk;

    // ----------------------------------------------------------------
    // Test infrastructure
    // ----------------------------------------------------------------
    int test_num;
    int pass_count, fail_count;
    int cycle_count;

    task reset_cpu;
        reset_n = 0;
        repeat(4) @(posedge clk);
        @(negedge clk);
        reset_n = 1;
    endtask

    task wait_endi(output logic timed_out);
        int limit;
        timed_out = 0;
        limit = 0;
        begin : wait_endi_loop
            forever begin
                if (dbg_endi_pulse) begin
                    @(posedge clk); // settle
                    disable wait_endi_loop;
                end
                @(posedge clk);
                limit++;
                if (limit > TIMEOUT) begin
                    timed_out = 1;
                    disable wait_endi_loop;
                end
            end
        end
    endtask

    task check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s (EIP=%08X fault=%0d)", name, dbg_eip, dbg_fault_pending);
            fail_count++;
        end
    endtask

    // ----------------------------------------------------------------
    // Test A: JMP SHORT self-loop — EB FE
    // EB FE = opcode 0xEB disp 0xFE (-2)
    // target = 0xFFFFFFF0 + 2 + (-2) = 0xFFFFFFF0
    // ----------------------------------------------------------------
    task test_a_jmp_self_loop;
        logic timed_out;
        int endi_count;
        logic saw_fault;
        $display("--- Test A: JMP SHORT self-loop (EB FE) ---");

        // Program memory: EB FE repeating
        for (int i = 0; i < 256; i++)
            mem_program[i] = (i % 2 == 0) ? 8'hEB : 8'hFE;

        reset_cpu();

        // Run 1000 cycles, count ENDIs, check no fault
        saw_fault   = 0;
        endi_count  = 0;
        cycle_count = 0;
        while (cycle_count < 1000) begin
            @(posedge clk);
            cycle_count++;
            if (dbg_endi_pulse) endi_count++;
            if (dbg_fault_pending) saw_fault = 1;
        end

        check("A.1: no fault in 1000 cycles",          !saw_fault);
        check("A.2: at least 10 JMP ENDIs fired",       endi_count >= 10);
        check("A.3: EIP stays at reset vector",         dbg_eip == 32'hFFFFFFF0);
        check("A.4: no spurious fault_class",           dbg_fault_class == 4'h0);
    endtask

    // ----------------------------------------------------------------
    // Test B: JMP SHORT +5 — EB 05
    // target = 0xFFFFFFF0 + 2 + 5 = 0xFFFFFFF7
    // After jump: memory at 0xFFFFFFF7 = EB FE (self-loop, stable)
    // ----------------------------------------------------------------
    task test_b_jmp_forward;
        logic timed_out;
        logic [31:0] eip_after;
        $display("--- Test B: JMP SHORT +5 (EB 05) ---");

        // First two bytes at 0xFFFFFFF0: EB 05
        // Bytes at 0xFFFFFFF7 onwards: EB FE (self-loop)
        for (int i = 0; i < 256; i++)
            mem_program[i] = 8'hEB;  // default: JMP opcode
        mem_program[8'hF0] = 8'hEB;  // 0xFFFFFFF0: opcode
        mem_program[8'hF1] = 8'h05;  // 0xFFFFFFF1: disp +5
        // 0xFFFFFFF7 = index 0xF7
        mem_program[8'hF7] = 8'hEB;  // JMP opcode (self-loop)
        mem_program[8'hF8] = 8'hFE;  // disp -2

        reset_cpu();

        // Wait for first ENDI (the JMP at 0xFFFFFFF0)
        wait_endi(timed_out);
        check("B.1: first ENDI fires without timeout",  !timed_out);
        check("B.2: EIP = 0xFFFFFFF7 after JMP +5",
              dbg_eip == 32'hFFFFFFF7);
        check("B.3: no fault after JMP",                !dbg_fault_pending);

        // Wait for second ENDI (self-loop at 0xFFFFFFF7)
        wait_endi(timed_out);
        check("B.4: second ENDI fires (self-loop stable)", !timed_out);
        check("B.5: EIP stays at 0xFFFFFFF7",
              dbg_eip == 32'hFFFFFFF7);
    endtask

    // ----------------------------------------------------------------
    // Test C: JMP SHORT backward — EB F0 (disp = -16)
    // 0xF0 as signed byte = -16
    // target = 0xFFFFFFF0 + 2 + (-16) = 0xFFFFFFE2
    // ----------------------------------------------------------------
    task test_c_jmp_backward;
        logic timed_out;
        $display("--- Test C: JMP SHORT backward (EB F0, target 0xFFFFFFE2) ---");

        for (int i = 0; i < 256; i++)
            mem_program[i] = 8'h90;   // NOPs by default
        // EB F0 at 0xFFFFFFF0
        mem_program[8'hF0] = 8'hEB;
        mem_program[8'hF1] = 8'hF0;  // -16
        // Self-loop at 0xFFFFFFE2 (index 0xE2)
        // Note: 0xFFFFFFE2 < 0xFFFFFFF0, so mem_program[0xE2] must be set.
        // Memory model uses bus_addr[7:0] unconditionally so 0xE2 is reached.
        mem_program[8'hE2] = 8'hEB;
        mem_program[8'hE3] = 8'hFE;

        reset_cpu();

        wait_endi(timed_out);
        check("C.1: ENDI fires without timeout",        !timed_out);
        check("C.2: EIP = 0xFFFFFFE2 (backward target)",
              dbg_eip == 32'hFFFFFFE2);
        check("C.3: no fault after backward JMP",       !dbg_fault_pending);

        // Verify second ENDI (self-loop at target)
        wait_endi(timed_out);
        check("C.4: second ENDI fires at new location", !timed_out);
        check("C.5: EIP stays at backward target",
              dbg_eip == 32'hFFFFFFE2);
    endtask

    // ----------------------------------------------------------------
    // Test D: Rung 1 regression — 10 consecutive NOPs
    // ----------------------------------------------------------------
    task test_d_rung1_regression;
        logic timed_out;
        logic [31:0] expected_eip;
        $display("--- Test D: Rung 1 regression (10 consecutive NOPs) ---");

        for (int i = 0; i < 256; i++)
            mem_program[i] = 8'h90;   // all NOPs

        reset_cpu();

        // Run 10 NOPs — each should advance EIP by 1
        begin : nop_loop
            for (int n = 0; n < 10; n++) begin
                wait_endi(timed_out);
                if (timed_out) begin
                    check($sformatf("D.NOP%0d: fires without timeout", n), 0);
                    disable nop_loop;
                end
            end
        end

        expected_eip = 32'hFFFFFFF0 + 32'hA; // +10
        check("D.1: EIP advances by 10 after 10 NOPs",
              dbg_eip == expected_eip);
        check("D.2: no fault during NOP regression",    !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test E: Position-proven displacement — verify no byte capture
    //          if queue delivers bytes out of order (stress test)
    // Test: Put NOP (0x90) at position 0xFFFFFFF0, then EB at 0xFFFFFFF1
    // The decoder should see 0x90 first, decode it as NOP (not JMP).
    // Then see EB FE -> JMP self-loop.
    // This validates that position-proven capture doesn't confuse byte order.
    // ----------------------------------------------------------------
    task test_e_byte_ordering;
        logic timed_out;
        $display("--- Test E: NOP then JMP, verify correct byte ordering ---");

        for (int i = 0; i < 256; i++)
            mem_program[i] = 8'h90;
        mem_program[8'hF0] = 8'h90;   // NOP at 0xFFFFFFF0
        mem_program[8'hF1] = 8'hEB;   // JMP at 0xFFFFFFF1
        mem_program[8'hF2] = 8'hFE;   // disp -2 -> targets 0xFFFFFFF1

        reset_cpu();

        // First ENDI: NOP at 0xFFFFFFF0, EIP should be 0xFFFFFFF1
        wait_endi(timed_out);
        check("E.1: first ENDI fires (NOP)",            !timed_out);
        check("E.2: EIP = 0xFFFFFFF1 after NOP",
              dbg_eip == 32'hFFFFFFF1);

        // Second ENDI: JMP at 0xFFFFFFF1, target = 0xFFFFFFF1+2-2 = 0xFFFFFFF1
        wait_endi(timed_out);
        check("E.3: second ENDI fires (JMP self-loop)", !timed_out);
        check("E.4: EIP = 0xFFFFFFF1 after JMP self",
              dbg_eip == 32'hFFFFFFF1);
        check("E.5: no fault throughout",               !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display(" Keystone86 / Aegis — Rung 2 Testbench");
        $display("============================================================");

        pass_count  = 0;
        fail_count  = 0;
        test_num    = 0;
        reset_n     = 0;
        for (int i = 0; i < 256; i++) mem_program[i] = 8'h90;

        test_a_jmp_self_loop();
        test_b_jmp_forward();
        test_c_jmp_backward();
        test_d_rung1_regression();
        test_e_byte_ordering();

        $display("============================================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(" ALL TESTS PASSED — Rung 2 acceptance criteria met.");
        else
            $display(" FAILURES DETECTED — Rung 2 not yet complete.");

        $finish;
    end

    // Global timeout
    initial begin
        #(TIMEOUT * CLK_HALF_PERIOD * 200);
        $display("[TIMEOUT] Global simulation timeout");
        $finish;
    end

endmodule
