// Keystone86 / Aegis
// sim/tb/tb_rung3_call_ret.sv
// Rung 3 self-checking testbench: near CALL and near RET
//
// All tests are self-checking — pass/fail by assertion.
//
// Memory model:
//   Two separate address spaces handled by bus_ready/bus_din logic:
//     Code space: mem_code[addr[7:0]]  — instruction bytes at 0xFFFFFFxx
//     Stack space: a flat 256-word DWORD array at 0x000FFFxx
//       (matches RESET_ESP = 0x000FFFF0; stack grows downward)
//   Stack bus (stk_wr_en / stk_rd_req) is served by the same logic but
//   via dedicated stk_* ports on cpu_top (no bus arbitration needed).
//
// Tests:
//
//   Test A — Direct CALL + RET pair
//     Code at 0xFFFFFFF0: E8 05 00  CALL +5  (target = 0xFFFFFFF8)
//     Code at 0xFFFFFFF8: C3        RET
//     After CALL: EIP=0xFFFFFFF8, ESP=RESET_ESP-4, [ESP]=0xFFFFFFF3
//     After RET:  EIP=0xFFFFFFF3, ESP=RESET_ESP
//     Then infinite-loop NOP at 0xFFFFFFF3
//
//   Test B — RET imm16 (C2) stack adjustment
//     Code at 0xFFFFFFF0: E8 04 00  CALL +4  (target = 0xFFFFFFF7)
//     Code at 0xFFFFFFF7: C2 08 00  RET 8
//     After RET: EIP=0xFFFFFFF3, ESP=RESET_ESP-4+4+8 = RESET_ESP+8
//     Verify ESP = RESET_ESP + 8 (net positive because imm16=8 was added)
//
//   Test C — Nested CALL/RET depth 4
//     Layout (all at 0xFFFFFFxx):
//       0xF0: E8 0A 00  CALL +10  -> target 0xFD  (level 1)
//       0xF3: 90        NOP (level 1 return landing)
//       0xF4: 90        NOP
//       0xF5: EB FE     JMP self  (stable end)
//       0xFD: E8 06 00  CALL +6   -> target 0x106 (wraps; use 0x06 here mapped low byte)
//     NOTE: For nested depth 4, use a simpler layout where all targets
//     are reachable in the 0xFFFFFFxx window.
//     Simplified depth-4 proof:
//       Frame 1: CALL to frame2, RET back
//       Frame 2: CALL to frame3, RET back
//       Frame 3: CALL to frame4, RET back
//       Frame 4: RET
//     Layout uses only indices 0xF0-0xFF:
//       0xF0: E8 02 00 -> CALL +2  target=0xF5  (frame1 call)
//       0xF3: EB 06    -> JMP +6 = 0xFB         (frame1 return lands here -> jump to end)
//       0xF5: E8 02 00 -> CALL +2  target=0xFA  (frame2 call)
//       0xF8: C3       -> RET                   (frame2 return)
//       0xFA: C3       -> RET                   (frame3 = RET immediately)
//       0xFB: 90       -> NOP
//       0xFC: EB FE    -> JMP self (stable end)
//     Verify: after all RETs unwind, EIP=0xFB, ESP=RESET_ESP
//
//   Test D — Indirect CALL (FF /2, register form)
//     indirect_call_target wired to a fixed value (0x000000A0).
//     Code at 0xFFFFFFF0: FF D0  (FF /2, mod=11, reg=2, rm=0 => ModRM=0xD0)
//     After CALL: EIP=0x000000A0, ESP=RESET_ESP-4, [ESP]=0xFFFFFFF2
//     Code at 0x000000A0: C3  RET
//     After RET:  EIP=0xFFFFFFF2, ESP=RESET_ESP
//
//   Test E — Rung 2 regression (JMP SHORT self-loop, 200 cycles)
//
//   Test F — Rung 1 regression (10 NOPs, EIP advances correctly)

`timescale 1ns/1ps

module tb_rung3_call_ret;

    localparam int TIMEOUT         = 8000;
    localparam int CLK_HALF_PERIOD = 5;
    localparam logic [31:0] RESET_ESP = 32'h000FFFF0;
    localparam logic [1:0]  MSEQ_FETCH_DECODE = 2'h0;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic        clk, reset_n;
    logic [31:0] bus_addr;
    logic        bus_rd, bus_wr;
    logic [3:0]  bus_byteen;
    logic [31:0] bus_dout, bus_din;
    logic        bus_ready;

    // Stack bus
    logic        stk_wr_en;
    logic [31:0] stk_wr_addr, stk_wr_data;
    logic        stk_rd_req;
    logic [31:0] stk_rd_addr;
    logic [31:0] stk_rd_data;
    logic        stk_rd_ready;

    // Indirect CALL target
    logic [31:0] indirect_call_target;
    logic        indirect_call_target_valid;

    // Debug
    logic [31:0] dbg_eip, dbg_esp;
    logic [1:0]  dbg_mseq_state;
    logic [11:0] dbg_upc;
    logic [7:0]  dbg_entry_id, dbg_dec_entry_id;
    logic        dbg_endi_pulse, dbg_fault_pending;
    logic [3:0]  dbg_fault_class;
    logic        dbg_decode_done;
    logic [31:0] dbg_fetch_addr;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    cpu_top dut (
        .clk                        (clk),
        .reset_n                    (reset_n),
        .bus_addr                   (bus_addr),
        .bus_rd                     (bus_rd),
        .bus_wr                     (bus_wr),
        .bus_byteen                 (bus_byteen),
        .bus_dout                   (bus_dout),
        .bus_din                    (bus_din),
        .bus_ready                  (bus_ready),
        .stk_wr_en                  (stk_wr_en),
        .stk_wr_addr                (stk_wr_addr),
        .stk_wr_data                (stk_wr_data),
        .stk_rd_req                 (stk_rd_req),
        .stk_rd_addr                (stk_rd_addr),
        .stk_rd_data                (stk_rd_data),
        .stk_rd_ready               (stk_rd_ready),
        .indirect_call_target       (indirect_call_target),
        .indirect_call_target_valid (indirect_call_target_valid),
        .dbg_eip                    (dbg_eip),
        .dbg_esp                    (dbg_esp),
        .dbg_mseq_state             (dbg_mseq_state),
        .dbg_upc                    (dbg_upc),
        .dbg_entry_id               (dbg_entry_id),
        .dbg_dec_entry_id           (dbg_dec_entry_id),
        .dbg_endi_pulse             (dbg_endi_pulse),
        .dbg_fault_pending          (dbg_fault_pending),
        .dbg_fault_class            (dbg_fault_class),
        .dbg_decode_done            (dbg_decode_done),
        .dbg_fetch_addr             (dbg_fetch_addr)
    );

    // ----------------------------------------------------------------
    // Code memory model  (bus_rd interface — 0xFFFFFFxx range)
    // mem_code[N] = byte at address where addr[7:0]==N
    // ----------------------------------------------------------------
    logic [7:0]  mem_code [0:255];
    logic        rd_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready  <= 1'b0;
            bus_din    <= 32'h0;
            rd_pending <= 1'b0;
        end else begin
            bus_ready <= 1'b0;
            if (bus_rd && !rd_pending)
                rd_pending <= 1'b1;
            if (rd_pending) begin
                bus_din    <= {24'h0, mem_code[bus_addr[7:0]]};
                bus_ready  <= 1'b1;
                rd_pending <= 1'b0;
                $display("  [MEM] bus fetch: addr=%08X data=%02X @%0t", bus_addr, mem_code[bus_addr[7:0]], $time);
            end
        end
    end

    // ----------------------------------------------------------------
    // Stack memory model  (stk_wr / stk_rd interface)
    // 256 DWORDs at 0x000FFFxx (word-addressed by addr[9:2])
    // ----------------------------------------------------------------
    logic [31:0] stack_mem [0:255];
    logic        stk_rd_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            stk_rd_ready   <= 1'b0;
            stk_rd_data    <= 32'h0;
            stk_rd_pending <= 1'b0;
            for (int i = 0; i < 256; i++) stack_mem[i] = 32'h0;
        end else begin
            stk_rd_ready <= 1'b0;

            // Write port (synchronous, one cycle)
            if (stk_wr_en) begin
                stack_mem[stk_wr_addr[9:2]] <= stk_wr_data;
                $display("  [STK] push: addr=%08X data=%08X @%0t", stk_wr_addr, stk_wr_data, $time);
            end

            // Read port (one-cycle latency)
            if (stk_rd_req && !stk_rd_pending)
                stk_rd_pending <= 1'b1;
            if (stk_rd_pending) begin
                stk_rd_data    <= stack_mem[stk_rd_addr[9:2]];
                stk_rd_ready   <= 1'b1;
                stk_rd_pending <= 1'b0;
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
    int pass_count, fail_count;

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
        begin : wloop
            forever begin
                if (dbg_endi_pulse) begin
                    @(posedge clk);
                    disable wloop;
                end
                @(posedge clk);
                limit++;
                if (limit > TIMEOUT) begin
                    timed_out = 1;
                    disable wloop;
                end
            end
        end
    endtask

    task wait_n_endi(input int n, output logic timed_out);
        timed_out = 0;
        begin : wait_n_loop
            for (int i = 0; i < n; i++) begin
                wait_endi(timed_out);
                if (timed_out) disable wait_n_loop;
            end
        end
    endtask

    task check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s  (EIP=%08X ESP=%08X fault=%0d fc=%0d)",
                     name, dbg_eip, dbg_esp, dbg_fault_pending, dbg_fault_class);
            fail_count++;
        end
    endtask

    // ----------------------------------------------------------------
    // Test A — Direct CALL + RET pair
    //
    // Layout at 0xFFFFFFF0:
    //   F0: E8 02 00   CALL +2   => target = F0+3+2 = 0xFFFFFFF5
    //   F3: 90         NOP       (return landing)
    //   F4: 90         NOP
    //   F5: C3         RET
    //   F6: 90         NOP  (fill)
    //   ...
    // After CALL:  EIP=0xFFFFFFF5, ESP=RESET_ESP-4, stack[RESET_ESP-4]=0xFFFFFFF3
    // After RET:   EIP=0xFFFFFFF3, ESP=RESET_ESP
    // ----------------------------------------------------------------
    task test_a_call_ret_pair;
        logic timed_out;
        logic [31:0] esp_after_call, eip_after_call;
        logic [31:0] esp_after_ret, eip_after_ret;
        $display("--- Test A: Direct CALL + RET pair ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;  // NOPs
        mem_code[8'hF0] = 8'hE8;  // CALL opcode
        mem_code[8'hF1] = 8'h02;  // disp16 lo = 2
        mem_code[8'hF2] = 8'h00;  // disp16 hi = 0  => target = F0+3+2 = F5
        mem_code[8'hF3] = 8'h90;  // return landing NOP
        mem_code[8'hF4] = 8'h90;
        mem_code[8'hF5] = 8'hC3;  // RET
        // After RET lands at F3: NOPs run indefinitely (safe)

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        // First ENDI = CALL
        wait_endi(timed_out);
        check("A.1: CALL ENDI fires",                    !timed_out);
        check("A.2: EIP = CALL target (0xFFFFFFF5)",     dbg_eip == 32'hFFFFFFF5);
        check("A.3: ESP decremented by 4",               dbg_esp == RESET_ESP - 32'h4);
        check("A.4: no fault after CALL",                !dbg_fault_pending);
        esp_after_call = dbg_esp;

        // Verify return address on stack
        @(posedge clk);
        check("A.5: return address on stack = 0xFFFFFFF3",
              stack_mem[esp_after_call[9:2]] == 32'hFFFFFFF3);

        // Second ENDI = RET
        wait_endi(timed_out);
        check("A.6: RET ENDI fires",                     !timed_out);
        check("A.7: EIP = return address (0xFFFFFFF3)",  dbg_eip == 32'hFFFFFFF3);
        check("A.8: ESP restored to RESET_ESP",          dbg_esp == RESET_ESP);
        check("A.9: no fault after RET",                 !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test B — RET imm16 (C2) stack adjustment
    //
    // Layout:
    //   F0: E8 02 00   CALL +2  => target = 0xFFFFFFF5
    //   F3: 90         NOP (return landing)
    //   F4: 90
    //   F5: C2 08 00   RET 8   (pop + add 8 to ESP)
    //   F8: 90         NOP
    //
    // After CALL:  ESP = RESET_ESP - 4
    // After RET 8: EIP = 0xFFFFFFF3, ESP = RESET_ESP - 4 + 4 + 8 = RESET_ESP + 8
    // ----------------------------------------------------------------
    task test_b_ret_imm16;
        logic timed_out;
        $display("--- Test B: RET imm16 (C2 08 00) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hE8;
        mem_code[8'hF1] = 8'h02;
        mem_code[8'hF2] = 8'h00;   // CALL -> F5
        mem_code[8'hF3] = 8'h90;   // return landing
        mem_code[8'hF4] = 8'h90;
        mem_code[8'hF5] = 8'hC2;   // RET imm16
        mem_code[8'hF6] = 8'h08;   // imm16 lo = 8
        mem_code[8'hF7] = 8'h00;   // imm16 hi = 0

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        // CALL
        wait_endi(timed_out);
        check("B.1: CALL ENDI fires",                    !timed_out);
        check("B.2: EIP = 0xFFFFFFF5 after CALL",        dbg_eip == 32'hFFFFFFF5);

        // RET 8
        wait_endi(timed_out);
        check("B.3: RET imm16 ENDI fires",               !timed_out);
        check("B.4: EIP = return address (0xFFFFFFF3)",  dbg_eip == 32'hFFFFFFF3);
        check("B.5: ESP = RESET_ESP + 8",                dbg_esp == RESET_ESP + 32'h8);
        check("B.6: no fault after RET imm16",           !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test C — Nested CALL/RET depth 4
    //
    // Depth-4 layout using only 0xFFFFFFxx window:
    //   E0: E8 02 00  CALL +2 -> E5  (depth 1 call)
    //   E3: EB 08     JMP +8  -> ED  (depth 1 return landing -> skip to end)
    //   E5: E8 02 00  CALL +2 -> EA  (depth 2 call)
    //   E8: C3        RET          (depth 2 return)
    //   EA: E8 02 00  CALL +2 -> EF (depth 3 call)
    //   ED: EB FE     JMP self (stable end landing)
    //   EF: C3        RET          (depth 3+4 return — returns to E8 -> then to E3)
    //
    // Wait, we need 4 frames. Let's be precise:
    //   Frame sequence: E0 calls E5, E5 calls EA, EA calls EF, EF rets to ED,
    //     ED rets to E8, E8 rets to E3... that's only 3 unique frames.
    //   For 4 frames:
    //   E0: E8 04 00  CALL +4 -> E7  (frame 1 → frame 2)
    //   E3: EB 08     JMP +8  -> ED  (frame 1 return landing)
    //   E5: 90 90     NOPs
    //   E7: E8 04 00  CALL +4 -> EE  (frame 2 → frame 3)
    //   EA: C3        RET            (frame 2 return)
    //   EB: 90 90 90  NOPs
    //   EE: E8 02 00  CALL +2 -> F3  (frame 3 → frame 4)
    //   F1: C3        RET            (frame 3 return)
    //   F3: C3        RET            (frame 4 return, rets to F1 → wait that loops)
    //
    // Cleaner: use a simple 4-deep chain where each frame RETs immediately.
    //   E0: E8 02 00  CALL +2 -> E5  (calls frame2; return addr = E3)
    //   E3: EB FE     JMP self (after all returns land here — stable)
    //   E5: E8 02 00  CALL +2 -> EA  (calls frame3; return addr = E8)
    //   E8: C3        RET            (returns to E3 after frame2+3+4 unwind)
    //   EA: E8 02 00  CALL +2 -> EF  (calls frame4; return addr = ED)
    //   ED: C3        RET            (returns to E8)
    //   EF: C3        RET            (returns to ED)
    //
    // Execution:
    //   1. E0 CALL -> E5  (ESP=R-4,  [R-4]=E3)
    //   2. E5 CALL -> EA  (ESP=R-8,  [R-8]=E8)
    //   3. EA CALL -> EF  (ESP=R-12, [R-12]=ED)
    //   4. EF RET  -> ED  (ESP=R-8)
    //   5. ED RET  -> E8  (ESP=R-4)
    //   6. E8 RET  -> E3  (ESP=R)
    //   Final: EIP=E3, ESP=RESET_ESP, no fault
    // ----------------------------------------------------------------
    task test_c_nested_depth4;
        logic timed_out;
        $display("--- Test C: Nested CALL/RET depth 4 ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        // Frame 1 call: E0
        mem_code[8'hE0] = 8'hE8; mem_code[8'hE1] = 8'h02; mem_code[8'hE2] = 8'h00;
        // Frame 1 return landing: E3
        mem_code[8'hE3] = 8'hEB; mem_code[8'hE4] = 8'hFE;  // JMP self

        // Frame 2 call: E5
        mem_code[8'hE5] = 8'hE8; mem_code[8'hE6] = 8'h02; mem_code[8'hE7] = 8'h00;
        // Frame 2 return: E8
        mem_code[8'hE8] = 8'hC3;

        // Frame 3 call: EA
        mem_code[8'hEA] = 8'hE8; mem_code[8'hEB] = 8'h02; mem_code[8'hEC] = 8'h00;
        // Frame 3 return: ED
        mem_code[8'hED] = 8'hC3;

        // Frame 4 body: EF
        mem_code[8'hEF] = 8'hC3;  // RET immediately

        // Reset vector starts at E0 — patch fetch start.
        // The CPU always resets to 0xFFFFFFF0, so set F0 to JMP to E0.
        // JMP SHORT to 0xFFFFFFE0: disp = E0 - (F0+2) = -18 = 0xEE
        mem_code[8'hF0] = 8'hEB;
        mem_code[8'hF1] = 8'hEE;  // JMP -18 -> lands at 0xFFFFFFE0

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        // Wait 6 ENDIs: JMP + CALL + CALL + CALL + RET + RET + RET = 7
        // (actually JMP to E0 first, then 3 CALLs and 3 RETs = 7 ENDIs total)
        timed_out = 0;
        for (int _i = 0; _i < 7; _i++) begin
            wait_endi(timed_out);
            $display("  [TRACE] ENDI %0d: EIP=%08X ESP=%08X fault=%0d", _i+1, dbg_eip, dbg_esp, dbg_fault_pending);
            if (timed_out) break;
        end
        check("C.1: all 7 ENDIs fire without timeout",   !timed_out);
        check("C.2: EIP = 0xFFFFFFE3 (depth-1 return)",  dbg_eip == 32'hFFFFFFE3);
        check("C.3: ESP = RESET_ESP (fully unwound)",    dbg_esp == RESET_ESP);
        check("C.4: no fault during nested CALL/RET",    !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test D — Indirect CALL (FF /2) + RET
    //
    // Layout at 0xFFFFFFF0:
    //   F0: FF D0   FF /2, ModRM=0xD0 (mod=11, reg=2, rm=0)
    //   F2: 90      NOP (return landing)
    //   ...
    // indirect_call_target = 0x000000A0
    // Code at 0x000000A0: C3 (RET)
    //   -> mem_code[0xA0] = 0xC3
    //
    // After CALL: EIP=0x000000A0, ESP=RESET_ESP-4, [RESET_ESP-4]=0xFFFFFFF2
    // After RET:  EIP=0xFFFFFFF2, ESP=RESET_ESP
    // ----------------------------------------------------------------
    task test_d_indirect_call;
        logic timed_out;
        logic [31:0] esp_after_call;
        $display("--- Test D: Indirect CALL (FF /2, register form) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hFF;  // FF /2 opcode
        mem_code[8'hF1] = 8'hD0;  // ModRM = 0xD0 (mod=11, reg=2, rm=0)
        mem_code[8'hF2] = 8'h90;  // return landing NOP
        mem_code[8'hA0] = 8'hC3;  // RET at call target

        indirect_call_target       = 32'hFFFFFFA0;  // target in 0xFF window
        indirect_call_target_valid = 1'b1;
        reset_cpu();

        // CALL ENDI
        wait_endi(timed_out);
        check("D.1: indirect CALL ENDI fires",               !timed_out);
        check("D.2: EIP = indirect target (0xFFFFFFA0)",     dbg_eip == 32'hFFFFFFA0);
        check("D.3: ESP decremented by 4",                   dbg_esp == RESET_ESP - 32'h4);
        check("D.4: no fault after indirect CALL",           !dbg_fault_pending);
        esp_after_call = dbg_esp;

        @(posedge clk);
        check("D.5: return address on stack = 0xFFFFFFF2",
              stack_mem[esp_after_call[9:2]] == 32'hFFFFFFF2);

        // RET ENDI
        wait_endi(timed_out);
        check("D.6: RET after indirect CALL fires",          !timed_out);
        check("D.7: EIP = 0xFFFFFFF2 (return address)",      dbg_eip == 32'hFFFFFFF2);
        check("D.8: ESP restored",                           dbg_esp == RESET_ESP);
        check("D.9: no fault after RET",                     !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test E — Rung 2 regression: JMP SHORT self-loop
    // ----------------------------------------------------------------
    task test_e_rung2_regression;
        logic timed_out;
        int   endi_count, cyc;
        logic saw_fault;
        $display("--- Test E: Rung 2 regression (JMP SHORT self-loop) ---");

        for (int i = 0; i < 256; i++)
            mem_code[i] = (i % 2 == 0) ? 8'hEB : 8'hFE;

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        saw_fault  = 0;
        endi_count = 0;
        cyc        = 0;
        while (cyc < 500) begin
            @(posedge clk);
            cyc++;
            if (dbg_endi_pulse) endi_count++;
            if (dbg_fault_pending) saw_fault = 1;
        end

        check("E.1: no fault in 500 cycles (JMP loop)",  !saw_fault);
        check("E.2: JMP ENDIs fired in 500 cycles",       endi_count >= 5);
        check("E.3: EIP stays at reset vector",           dbg_eip == 32'hFFFFFFF0);
    endtask

    // ----------------------------------------------------------------
    // Test F — Rung 1 regression: 10 consecutive NOPs
    // ----------------------------------------------------------------
    task test_f_rung1_regression;
        logic timed_out;
        $display("--- Test F: Rung 1 regression (10 consecutive NOPs) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        begin : nop_loop
            for (int n = 0; n < 10; n++) begin
                wait_endi(timed_out);
                if (timed_out) begin
                    check("F: NOP timeout", 0);
                    disable nop_loop;
                end
            end
        end

        check("F.1: EIP advanced by 10 after 10 NOPs",
              dbg_eip == 32'hFFFFFFF0 + 32'hA);
        check("F.2: no fault during NOP regression",       !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display(" Keystone86 / Aegis — Rung 3 Testbench (CALL/RET)");
        $display("============================================================");

        pass_count = 0;
        fail_count = 0;
        reset_n    = 0;
        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        test_a_call_ret_pair();
        test_b_ret_imm16();
        test_c_nested_depth4();
        test_d_indirect_call();
        test_e_rung2_regression();
        test_f_rung1_regression();

        $display("============================================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        $display("============================================================");

        if (fail_count == 0)
            $display(" ALL TESTS PASSED — Rung 3 acceptance criteria met.");
        else
            $display(" FAILURES DETECTED — Rung 3 not yet complete.");

        $finish;
    end

    // Global timeout watchdog
    initial begin
        #(TIMEOUT * CLK_HALF_PERIOD * 500);
        $display("[TIMEOUT] Global simulation timeout");
        $display("  EIP=%08X ESP=%08X mseq_state=%0d fault=%0d",
                 dbg_eip, dbg_esp, dbg_mseq_state, dbg_fault_pending);
        $finish;
    end

endmodule
