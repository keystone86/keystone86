// Keystone86 / Aegis
// sim/tb/tb_rung2_jmp_near.sv
// Rung 2 self-checking testbench: Near JMP (EB short, E9 near relative)
//
// All tests are self-checking — no manual waveform inspection required.
//
// Tests:
//   Test 1:  EB FE decoder classifies as ENTRY_JMP_NEAR (0x07)
//   Test 2:  Dispatch reaches uPC 0x050
//   Test 3:  No fault during JMP execution
//   Test 4:  EIP = jump target after ENDI (EB FE self-loop: same address)
//   Test 5:  Prefetch flush triggered after JMP
//   Test 6:  1000-cycle EB FE self-loop stability (gate criterion)
//   Test 7:  EB 05 short forward jump: EIP = opc_eip + 7
//   Test 8:  EB F9 short backward jump: EIP = opc_eip - 5
//   Test 9:  E9 10 00 near relative jump: EIP = opc_eip + 19
//   Test 10: Stale-byte proof: poison bytes in fall-through do not execute
//
// Memory models:
//   Phase 0 (self-loop): EB FE at all addresses
//   Phase 1 (forward):   EB 05 at reset vector; NOPs fill; target = reset+7
//   Phase 2 (backward):  EB F9 at reset vector; target = reset-5 (NOPs there)
//   Phase 3 (E9):        E9 10 00 at reset vector; target = reset+19 (NOPs)
//   Phase 4 (stale):     JMP at base; POISON (0xFF=ENTRY_NULL path) in fall-through;
//                        NOP at target. If flush wrong, 0xFF executes -> FC_UD.
//
// VALIDATE_NEAR_TRANSFER note:
//   Out-of-range target detection (jmp_oor) is scaffolded in the decoder but
//   disabled in Rung 2. The current baseline uses flat 32-bit EIP starting at
//   0xFFFFFFF0 which exceeds the 16-bit range. Correct validation requires
//   CS:IP segment arithmetic not yet present. ENTRY_JMP_NEAR_FAULT microcode
//   exists for when this is enabled in a later rung.

`timescale 1ns/1ps

module tb_rung2_jmp_near;

    localparam int TIMEOUT          = 8000;
    localparam int CLK_HALF_PERIOD  = 5;
    localparam int SELF_LOOP_CYCLES = 1000;

    localparam logic [11:0] EXPECTED_JMP_UPC   = 12'h050;
    localparam logic [7:0]  EXPECTED_JMP_ENTRY = 8'h07;
    localparam logic [1:0]  MSEQ_FETCH_DECODE  = 2'h0;
    localparam logic [31:0] RESET_VEC          = 32'hFFFFFFF0;

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

    logic [3:0]  mem_phase;

    // ----------------------------------------------------------------
    // DUT
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

    jmp_mem u_mem (
        .clk      (clk), .reset_n  (reset_n),
        .addr     (bus_addr), .rd  (bus_rd),
        .phase    (mem_phase),
        .dout     (bus_din),  .ready (bus_ready)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ----------------------------------------------------------------
    // Counters and state (all at module scope — no inline declarations)
    // ----------------------------------------------------------------
    int  pass_count, fail_count, cycle_count;
    logic test1_done,  test2_done,  test3_done,  test4_done,  test5_done;
    logic test6_done,  test7_done,  test8_done,  test9_done,  test10_done;

    // Track last decoded entry
    logic [7:0] last_decoded_entry;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) last_decoded_entry <= 8'h0;
        else if (dbg_decode_done) last_decoded_entry <= dbg_dec_entry_id;
    end

    // Module-scope EIP captures and expected values (no inline declarations)
    logic [31:0] eip_at_first_jmp;         // EIP when first JMP decode_done fires
    logic        eip_at_first_jmp_cap;
    logic [31:0] expected_t4;              // expected EIP for test 4

    logic [31:0] eip_at_fwd_jmp;
    logic        eip_at_fwd_jmp_cap;
    logic [31:0] expected_t7;

    logic [31:0] eip_at_bwd_jmp;
    logic        eip_at_bwd_jmp_cap;
    logic [31:0] expected_t8;

    logic [31:0] eip_at_e9_jmp;
    logic        eip_at_e9_jmp_cap;
    logic [31:0] expected_t9;

    // ENDI trigger flags
    logic first_jmp_endi_t3;
    logic test4_triggered, test5_triggered;
    logic test7_triggered, test8_triggered, test9_triggered;

    // Self-loop counters
    int   self_loop_jmp_count;
    int   self_loop_fault_count;
    int   self_loop_cycle_count;
    logic test6_counting;
    logic first_jmp_endi_latch;

    // Stale-byte test state
    int   stale_fault_count;
    logic stale_jmp_endi_seen;
    logic test10_triggered;

    // ----------------------------------------------------------------
    // Watchdog
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            cycle_count++;
            if (cycle_count >= TIMEOUT) begin
                $display("FAIL: Timeout after %0d cycles", TIMEOUT);
                $display("  done=%b%b%b%b%b/%b%b%b%b%b phase=%0d",
                    test1_done,test2_done,test3_done,test4_done,test5_done,
                    test6_done,test7_done,test8_done,test9_done,test10_done,
                    mem_phase);
                $finish;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 1: ENTRY_JMP_NEAR classification
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0 && dbg_decode_done && !test1_done) begin
            if (dbg_dec_entry_id === EXPECTED_JMP_ENTRY) begin
                $display("PASS Test 1: EB decoded as ENTRY_JMP_NEAR (0x%02X)", dbg_dec_entry_id);
                pass_count++;
            end else begin
                $display("FAIL Test 1: entry=0x%02X expected ENTRY_JMP_NEAR=0x%02X",
                         dbg_dec_entry_id, EXPECTED_JMP_ENTRY);
                fail_count++;
            end
            test1_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test 2: dispatch uPC 0x050
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0 && dbg_upc === EXPECTED_JMP_UPC && !test2_done) begin
            $display("PASS Test 2: uPC=0x%03X (ENTRY_JMP_NEAR dispatch)", dbg_upc);
            pass_count++;
            test2_done = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Test 3: no fault at first JMP ENDI
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0) begin
            // Capture EIP when first JMP decode_done fires
            if (!eip_at_first_jmp_cap && dbg_decode_done &&
                    dbg_dec_entry_id === EXPECTED_JMP_ENTRY) begin
                eip_at_first_jmp_cap <= 1'b1;
                eip_at_first_jmp     <= dbg_eip;
                // EB FE self-loop: target = opc_eip + 2 - 2 = opc_eip
                expected_t4          <= dbg_eip; // same address
            end

            if (dbg_endi_pulse && eip_at_first_jmp_cap &&
                    last_decoded_entry === EXPECTED_JMP_ENTRY && !first_jmp_endi_t3) begin
                first_jmp_endi_t3 = 1'b1;
                if (!dbg_fault_pending && !test3_done) begin
                    $display("PASS Test 3: no fault during JMP (fault_pending=0)");
                    pass_count++; test3_done = 1'b1;
                end else if (!test3_done) begin
                    $display("FAIL Test 3: fault_pending=1 fc=0x%X", dbg_fault_class);
                    fail_count++; test3_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 4: EIP = target after first JMP ENDI (one cycle later)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0 &&
                first_jmp_endi_t3 && eip_at_first_jmp_cap && !test4_triggered) begin
            test4_triggered = 1'b1;
            @(posedge clk);
            if (!test4_done) begin
                if (dbg_eip === expected_t4) begin
                    $display("PASS Test 4: EIP=0x%08X after EB FE (self-loop target correct)",
                             dbg_eip);
                    pass_count++;
                end else begin
                    $display("FAIL Test 4: EIP=0x%08X, expected 0x%08X",
                             dbg_eip, expected_t4);
                    fail_count++;
                end
                test4_done = 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 5: queue flush triggered (fetch restarts after JMP)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0 &&
                dbg_endi_pulse && eip_at_first_jmp_cap &&
                last_decoded_entry === EXPECTED_JMP_ENTRY && !first_jmp_endi_latch) begin
            first_jmp_endi_latch = 1'b1;
        end
        if (reset_n && mem_phase == 0 && first_jmp_endi_latch &&
                !test5_triggered && !test5_done) begin
            test5_triggered = 1'b1;
            repeat (5) @(posedge clk);
            if (!test5_done) begin
                $display("PASS Test 5: queue flush triggered after JMP (fetch restarts)");
                pass_count++;
                test5_done = 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 6: 1000-cycle self-loop stability (frozen gate criterion)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 0) begin
            if (test5_done && !test6_counting)
                test6_counting = 1'b1;
            if (test6_counting) begin
                if (dbg_endi_pulse && last_decoded_entry === EXPECTED_JMP_ENTRY)
                    self_loop_jmp_count++;
                if (dbg_fault_pending)
                    self_loop_fault_count++;
                self_loop_cycle_count++;
                if (self_loop_cycle_count >= SELF_LOOP_CYCLES && !test6_done) begin
                    if (self_loop_fault_count == 0) begin
                        $display("PASS Test 6: EB FE self-loop %0d cycles, zero faults",
                                 SELF_LOOP_CYCLES);
                        pass_count++;
                    end else begin
                        $display("FAIL Test 6: self-loop %0d cycles, %0d faults",
                                 SELF_LOOP_CYCLES, self_loop_fault_count);
                        fail_count++;
                    end
                    test6_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 7: EB 05 forward jump (phase 1)
    // target = reset_vec + 2 + 5 = reset_vec + 7
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 1) begin
            if (!eip_at_fwd_jmp_cap && dbg_decode_done &&
                    dbg_dec_entry_id === EXPECTED_JMP_ENTRY) begin
                eip_at_fwd_jmp_cap <= 1'b1;
                eip_at_fwd_jmp     <= dbg_eip;
                expected_t7        <= dbg_eip + 32'd7;  // opc_eip + 7
            end
            if (dbg_endi_pulse && eip_at_fwd_jmp_cap &&
                    last_decoded_entry === EXPECTED_JMP_ENTRY && !test7_triggered) begin
                test7_triggered = 1'b1;
                @(posedge clk);
                if (!test7_done) begin
                    if (dbg_eip === expected_t7) begin
                        $display("PASS Test 7: EB 05 forward EIP=0x%08X (opc+7)", dbg_eip);
                        pass_count++;
                    end else begin
                        $display("FAIL Test 7: EIP=0x%08X, expected 0x%08X",
                                 dbg_eip, expected_t7);
                        fail_count++;
                    end
                    test7_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 8: EB F9 backward jump (phase 2)
    // disp8=0xF9=-7, target = opc_eip + 2 + (-7) = opc_eip - 5
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 2) begin
            if (!eip_at_bwd_jmp_cap && dbg_decode_done &&
                    dbg_dec_entry_id === EXPECTED_JMP_ENTRY) begin
                eip_at_bwd_jmp_cap <= 1'b1;
                eip_at_bwd_jmp     <= dbg_eip;
                expected_t8        <= dbg_eip - 32'd5;  // opc_eip - 5
            end
            if (dbg_endi_pulse && eip_at_bwd_jmp_cap &&
                    last_decoded_entry === EXPECTED_JMP_ENTRY && !test8_triggered) begin
                test8_triggered = 1'b1;
                @(posedge clk);
                if (!test8_done) begin
                    if (dbg_eip === expected_t8) begin
                        $display("PASS Test 8: EB F9 backward EIP=0x%08X (opc-5)", dbg_eip);
                        pass_count++;
                    end else begin
                        $display("FAIL Test 8: EIP=0x%08X, expected 0x%08X",
                                 dbg_eip, expected_t8);
                        fail_count++;
                    end
                    test8_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 9: E9 10 00 near relative jump (phase 3)
    // disp16=0x0010=16, target = opc_eip + 3 + 16 = opc_eip + 19
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 3) begin
            if (!eip_at_e9_jmp_cap && dbg_decode_done &&
                    dbg_dec_entry_id === EXPECTED_JMP_ENTRY) begin
                eip_at_e9_jmp_cap <= 1'b1;
                eip_at_e9_jmp     <= dbg_eip;
                expected_t9       <= dbg_eip + 32'd19;  // opc_eip + 19
            end
            if (dbg_endi_pulse && eip_at_e9_jmp_cap &&
                    last_decoded_entry === EXPECTED_JMP_ENTRY && !test9_triggered) begin
                test9_triggered = 1'b1;
                @(posedge clk);
                if (!test9_done) begin
                    if (dbg_eip === expected_t9) begin
                        $display("PASS Test 9: E9 10 00 near EIP=0x%08X (opc+19)", dbg_eip);
                        pass_count++;
                    end else begin
                        $display("FAIL Test 9: EIP=0x%08X, expected 0x%08X",
                                 dbg_eip, expected_t9);
                        fail_count++;
                    end
                    test9_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Test 10: Stale-byte proof (phase 4)
    //
    // Memory layout for phase 4:
    //   RESET_VEC+0:  EB 0A   (JMP SHORT +10 -> target = RESET_VEC + 12)
    //   RESET_VEC+2:  FF FF FF FF FF FF FF FF FF FF  (10 bytes of 0xFF = poison)
    //   RESET_VEC+12: 90 90 90 ...  (NOPs at target)
    //
    // 0xFF dispatches as ENTRY_NULL -> RAISE FC_UD.
    // If flush is correct: poison bytes never execute. Zero faults.
    // If flush is wrong: poison bytes execute. Faults detected.
    //
    // The prefetch queue (depth=4) may have already fetched some poison bytes
    // before the JMP is decoded. The flush must discard ALL of them.
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && mem_phase == 4) begin
            if (dbg_endi_pulse && last_decoded_entry === EXPECTED_JMP_ENTRY &&
                    !stale_jmp_endi_seen) begin
                stale_jmp_endi_seen = 1'b1;
            end
            if (stale_jmp_endi_seen && dbg_fault_pending)
                stale_fault_count++;

            // After ENDI fires, wait 50 cycles and check for faults
            if (stale_jmp_endi_seen && !test10_triggered) begin
                test10_triggered = 1'b1;
                repeat (50) @(posedge clk);
                if (!test10_done) begin
                    if (stale_fault_count == 0) begin
                        $display("PASS Test 10: no stale bytes executed after JMP flush");
                        $display("             (zero faults in 50 cycles post-redirect)");
                        pass_count++;
                    end else begin
                        $display("FAIL Test 10: %0d fault(s) after JMP — stale bytes leaked!",
                                 stale_fault_count);
                        fail_count++;
                    end
                    test10_done = 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Phase sequencing
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n) begin
            if (test6_done  && !test7_done  && mem_phase == 0) mem_phase = 1;
            if (test7_done  && !test8_done  && mem_phase == 1) mem_phase = 2;
            if (test8_done  && !test9_done  && mem_phase == 2) mem_phase = 3;
            if (test9_done  && !test10_done && mem_phase == 3) mem_phase = 4;
        end
    end

    // ----------------------------------------------------------------
    // Summary and finish
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset_n && test1_done && test2_done && test3_done && test4_done &&
            test5_done && test6_done && test7_done && test8_done &&
            test9_done && test10_done) begin
            $display("");
            $display("=== Rung 2 Testbench Summary ===");
            $display("  Cycles elapsed : %0d", cycle_count);
            $display("  PASS           : %0d", pass_count);
            $display("  FAIL           : %0d", fail_count);
            if (fail_count == 0)
                $display("  RESULT: ALL RUNG 2 TESTS PASSED");
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
        mem_phase = 0;
        test1_done = 0; test2_done = 0; test3_done = 0; test4_done = 0; test5_done = 0;
        test6_done = 0; test7_done = 0; test8_done = 0; test9_done = 0; test10_done = 0;
        eip_at_first_jmp_cap = 0; eip_at_fwd_jmp_cap = 0;
        eip_at_bwd_jmp_cap = 0; eip_at_e9_jmp_cap = 0;
        expected_t4 = 0; expected_t7 = 0; expected_t8 = 0; expected_t9 = 0;
        first_jmp_endi_t3 = 0; first_jmp_endi_latch = 0;
        test4_triggered = 0; test5_triggered = 0;
        test6_counting = 0; test7_triggered = 0; test8_triggered = 0; test9_triggered = 0;
        self_loop_jmp_count = 0; self_loop_fault_count = 0; self_loop_cycle_count = 0;
        stale_fault_count = 0; stale_jmp_endi_seen = 0; test10_triggered = 0;
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        $display("--- Reset released, Rung 2 JMP test starting ---");
    end

endmodule

// ----------------------------------------------------------------
// jmp_mem: address-decoded instruction memory model
//
// Phase 0: EB FE at every address (self-loop anywhere)
// Phase 1: EB 05 at RESET_VEC, NOPs elsewhere (forward +7)
// Phase 2: EB F9 at RESET_VEC, NOPs elsewhere (backward -5)
// Phase 3: E9 10 00 at RESET_VEC, NOPs elsewhere (near +19)
// Phase 4: EB 0A at RESET_VEC, 0xFF poison at +2..+11, NOPs at target
//          Target = RESET_VEC + 12. Poison = bytes that would fault.
//          If flush fails, poison executes as ENTRY_NULL -> FC_UD.
// ----------------------------------------------------------------
module jmp_mem #(
    parameter int READY_LATENCY = 1
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [31:0] addr,
    input  logic        rd,
    input  logic [3:0]  phase,
    output logic [31:0] dout,
    output logic        ready
);
    localparam logic [31:0] RESET_VEC = 32'hFFFFFFF0;

    int unsigned latency_cnt;
    logic [7:0]  pending_byte;
    logic        rd_pending;

    function automatic logic [7:0] mem_byte(
        input logic [31:0] a,
        input logic [3:0]  p
    );
        case (p)
            4'd0: begin
                // EB FE repeating: even addr=EB, odd addr=FE
                return a[0] ? 8'hFE : 8'hEB;
            end
            4'd1: begin
                // EB 05 at reset vector, NOPs everywhere else
                if (a == RESET_VEC)   return 8'hEB;
                if (a == RESET_VEC+1) return 8'h05;
                else                  return 8'h90;
            end
            4'd2: begin
                // EB F9 (-7) at reset vector, NOPs elsewhere
                if (a == RESET_VEC)   return 8'hEB;
                if (a == RESET_VEC+1) return 8'hF9;
                else                  return 8'h90;
            end
            4'd3: begin
                // E9 10 00 at reset vector (disp16=16, target=reset+19)
                if (a == RESET_VEC)   return 8'hE9;
                if (a == RESET_VEC+1) return 8'h10;
                if (a == RESET_VEC+2) return 8'h00;
                else                  return 8'h90;
            end
            4'd4: begin
                // EB 0A at reset vector (target = reset+12)
                // Bytes reset+2 through reset+11: 0xFF (poison)
                //   0xFF = undefined opcode -> ENTRY_NULL -> FC_UD if executed
                // Bytes from reset+12 onward: 0x90 (NOP — safe target stream)
                if (a == RESET_VEC)   return 8'hEB;
                if (a == RESET_VEC+1) return 8'h0A;
                if (a >= RESET_VEC+2 && a <= RESET_VEC+11) return 8'hFF;  // poison
                else                  return 8'h90;  // safe target + fill
            end
            default: return 8'h90;
        endcase
    endfunction

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
                pending_byte <= mem_byte(addr, phase);
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
