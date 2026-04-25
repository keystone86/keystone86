// Keystone86 / Aegis
// sim/tb/tb_rung3_call_ret.sv
// Rung 3 self-checking testbench: near CALL and near RET
//
// All tests are self-checking — pass/fail by assertion.
//
// Memory model:
//   Two address spaces handled through the shared bus:
//     Code space: mem_code[addr[7:0]]  — instruction bytes at 0xFFFFFFxx
//     Stack space: a flat 256-word DWORD array at 0x000FFFxx
//       (matches RESET_ESP = 0x000FFFF0; stack grows downward)
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
//     Code at 0xFFFFFFF0: FF D0  (FF /2, mod=11, reg=2, rm=0 => ModRM=0xD0)
//     Bootstrap EAX reads as zero, so the register-form target is 0x00000000.
//     Code at 0x00000000: C3  RET
//     After RET: EIP=0xFFFFFFF2, ESP=RESET_ESP
//
//   Test E — Indirect CALL (FF /2, memory direct disp32 form)
//     Code at 0xFFFFFFF0: FF 15 80 00 00 00  CALL dword [0x80]
//     Data at 0x00000080: 0xFFFFFFA0
//     Code at 0xFFFFFFA0: C3  RET
//     After RET: EIP=0xFFFFFFF6, ESP=RESET_ESP
//
//   Test F — Unsupported FF /2 memory form fails safely
//     Code at 0xFFFFFFF0: FF 10  CALL dword [EAX]
//     Rung 3 consumes bytes for M_NEXT_EIP but does not execute this memory form.
//     Verify no CALL stack effect or redirect is committed.
//
//   Test G — Rung 2 regression (JMP SHORT self-loop, 200 cycles)
//
//   Test H — Rung 1 regression (10 NOPs, EIP advances correctly)

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
    // Shared bus memory model
    //   Code reads: mem_code[N] = byte at address where addr[7:0]==N
    //   Stack R/W:  stack_mem[addr[9:2]] at 0x000FFFxx
    // ----------------------------------------------------------------
    logic [7:0]  mem_code [0:255];
    logic [31:0] stack_mem [0:255];
    logic        bus_pending;
    logic        bus_wr_pending;
    logic [31:0] bus_addr_pending;
    logic [31:0] bus_dout_pending;
    logic [3:0]  bus_byteen_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready        <= 1'b0;
            bus_din          <= 32'h0;
            bus_pending      <= 1'b0;
            bus_wr_pending   <= 1'b0;
            bus_addr_pending <= 32'h0;
            bus_dout_pending <= 32'h0;
        end else begin
            bus_ready <= 1'b0;
            if ((bus_rd || bus_wr) && !bus_pending) begin
                bus_pending      <= 1'b1;
                bus_wr_pending   <= bus_wr;
                bus_addr_pending <= bus_addr;
                bus_dout_pending <= bus_dout;
                bus_byteen_pending <= bus_byteen;
            end
            if (bus_pending) begin
                if (bus_wr_pending) begin
                    stack_mem[bus_addr_pending[9:2]] <= bus_dout_pending;
                    bus_din <= 32'h0;
                end else if (bus_byteen_pending == 4'b0001) begin
                    bus_din <= {24'h0, mem_code[bus_addr_pending[7:0]]};
                end else begin
                    bus_din <= stack_mem[bus_addr_pending[9:2]];
                end
                bus_ready   <= 1'b1;
                bus_pending <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Stack backing storage is initialized here and accessed above by bus.
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (int i = 0; i < 256; i++) stack_mem[i] = 32'h0;
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
            while (dbg_endi_pulse) @(posedge clk);
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
        int limit;
        int seen;
        logic prev_endi;
        timed_out = 0;
        limit = 0;
        seen = 0;
        prev_endi = dbg_endi_pulse;
        begin : wait_n_loop
            forever begin
                @(posedge clk);
                if (dbg_endi_pulse && !prev_endi)
                    seen++;
                prev_endi = dbg_endi_pulse;
                if (seen >= n)
                    disable wait_n_loop;
                limit++;
                if (limit > TIMEOUT) begin
                    timed_out = 1;
                    disable wait_n_loop;
                end
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
        logic [31:0] esp_after_call;
        $display("--- Test A: Direct CALL + RET pair ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;  // NOPs
        mem_code[8'hF0] = 8'hE8;  // CALL opcode
        mem_code[8'hF1] = 8'h02;  // disp16 lo = 2
        mem_code[8'hF2] = 8'h00;  // disp16 hi = 0  => target = F0+3+2 = F5
        mem_code[8'hF3] = 8'h90;  // return landing NOP
        mem_code[8'hF4] = 8'h90;
        mem_code[8'hF5] = 8'hC3;  // RET
        // After RET lands at F3: NOPs run indefinitely (safe)

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
    //   C0: E8 02 00  CALL +2 -> C5  (calls frame2; return addr = C3)
    //   C3: EB FE     JMP self (after all returns land here — stable)
    //   C5: E8 02 00  CALL +2 -> CA  (calls frame3; return addr = C8)
    //   C8: C3        RET            (returns to C3 after unwind)
    //   CA: E8 02 00  CALL +2 -> CF  (calls frame4; return addr = CD)
    //   CD: C3        RET            (returns to C8)
    //   CF: E8 02 00  CALL +2 -> D4  (calls frame5; return addr = D2)
    //   D2: C3        RET            (returns to CD)
    //   D4: C3        RET            (returns to D2)
    //
    // Execution:
    //   1. C0 CALL -> C5  (ESP=R-4,  [R-4]=C3)
    //   2. C5 CALL -> CA  (ESP=R-8,  [R-8]=C8)
    //   3. CA CALL -> CF  (ESP=R-12, [R-12]=CD)
    //   4. CF CALL -> D4  (ESP=R-16, [R-16]=D2)
    //   5. D4 RET  -> D2  (ESP=R-12)
    //   6. D2 RET  -> CD  (ESP=R-8)
    //   7. CD RET  -> C8  (ESP=R-4)
    //   8. C8 RET  -> C3  (ESP=R)
    //   Final: EIP=C3, ESP=RESET_ESP, no fault
    // ----------------------------------------------------------------
    task test_c_nested_depth4;
        logic timed_out;
        $display("--- Test C: Nested CALL/RET depth 4 ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        // Frame 1 call: C0
        mem_code[8'hC0] = 8'hE8; mem_code[8'hC1] = 8'h02; mem_code[8'hC2] = 8'h00;
        // Frame 1 return landing: C3
        mem_code[8'hC3] = 8'hEB; mem_code[8'hC4] = 8'hFE;  // JMP self

        // Frame 2 call: C5
        mem_code[8'hC5] = 8'hE8; mem_code[8'hC6] = 8'h02; mem_code[8'hC7] = 8'h00;
        // Frame 2 return: C8
        mem_code[8'hC8] = 8'hC3;

        // Frame 3 call: CA
        mem_code[8'hCA] = 8'hE8; mem_code[8'hCB] = 8'h02; mem_code[8'hCC] = 8'h00;
        // Frame 3 return: CD
        mem_code[8'hCD] = 8'hC3;

        // Frame 4 call: CF
        mem_code[8'hCF] = 8'hE8; mem_code[8'hD0] = 8'h02; mem_code[8'hD1] = 8'h00;
        // Frame 4 return: D2
        mem_code[8'hD2] = 8'hC3;
        // Frame 5 body reached by the fourth nested CALL.
        mem_code[8'hD4] = 8'hC3;

        // Reset vector starts at C0 — patch fetch start after frame bytes.
        // The CPU always resets to 0xFFFFFFF0, so set F0 to JMP to C0.
        // JMP SHORT to 0xFFFFFFC0: disp = C0 - (F0+2) = -50 = 0xCE
        mem_code[8'hF0] = 8'hEB;
        mem_code[8'hF1] = 8'hCE;  // JMP -50 -> lands at 0xFFFFFFC0

        reset_cpu();

        // JMP to E0, four nested CALLs, then four RETs.
        wait_n_endi(9, timed_out);
        check("C.1: all 9 ENDIs fire without timeout",   !timed_out);
        check("C.2: EIP = 0xFFFFFFC3 (depth-1 return)",  dbg_eip == 32'hFFFFFFC3);
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
    // EAX bootstrap value is 0, so code at 0x00000000 is RET.
    // After CALL: EIP=0x00000000, ESP=RESET_ESP-4, [RESET_ESP-4]=0xFFFFFFF2
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
        mem_code[8'h00] = 8'hC3;  // RET at register target

        reset_cpu();

        // CALL ENDI
        wait_endi(timed_out);
        check("D.1: indirect CALL ENDI fires",               !timed_out);
        check("D.2: EIP = indirect register target (0)",     dbg_eip == 32'h00000000);
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
    // Test E — Indirect CALL (FF /2) memory direct disp32 + RET
    // ----------------------------------------------------------------
    task test_e_indirect_call_memory;
        logic timed_out;
        logic [31:0] esp_after_call;
        $display("--- Test E: Indirect CALL (FF /2, memory direct disp32) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hFF;  // FF /2 opcode
        mem_code[8'hF1] = 8'h15;  // ModRM = 00 010 101: disp32 memory operand
        mem_code[8'hF2] = 8'h80;
        mem_code[8'hF3] = 8'h00;
        mem_code[8'hF4] = 8'h00;
        mem_code[8'hF5] = 8'h00;  // disp32 = 0x00000080
        mem_code[8'hF6] = 8'h90;  // return landing
        mem_code[8'hA0] = 8'hC3;  // RET at loaded target

        reset_cpu();
        stack_mem[8'h20] = 32'hFFFFFFA0;

        wait_endi(timed_out);
        check("E.1: memory indirect CALL ENDI fires",        !timed_out);
        check("E.2: EIP = loaded memory target",             dbg_eip == 32'hFFFFFFA0);
        check("E.3: ESP decremented by 4",                   dbg_esp == RESET_ESP - 32'h4);
        check("E.4: no fault after memory indirect CALL",    !dbg_fault_pending);
        esp_after_call = dbg_esp;

        @(posedge clk);
        check("E.5: return address on stack = 0xFFFFFFF6",
              stack_mem[esp_after_call[9:2]] == 32'hFFFFFFF6);

        wait_endi(timed_out);
        check("E.6: RET after memory indirect CALL fires",   !timed_out);
        check("E.7: EIP = 0xFFFFFFF6 (return address)",      dbg_eip == 32'hFFFFFFF6);
        check("E.8: ESP restored",                           dbg_esp == RESET_ESP);
        check("E.9: no fault after memory indirect RET",      !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test F — Unsupported FF /2 memory forms do not execute successfully
    // ----------------------------------------------------------------
    task test_f_unsupported_memory_form;
        logic timed_out;
        logic [31:0] would_be_return_slot;
        $display("--- Test F: Unsupported FF /2 memory form fails safely ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hFF;  // FF /2 opcode
        mem_code[8'hF1] = 8'h10;  // ModRM = 00 010 000: [EAX], not direct disp32
        mem_code[8'h00] = 8'hC3;  // Old broad behavior would have used target 0.

        reset_cpu();

        wait_endi(timed_out);
        would_be_return_slot = RESET_ESP - 32'h4;
        check("F.1: unsupported memory form reaches fault-end ENDI", !timed_out);
        check("F.2: EIP is not redirected to placeholder target",
              dbg_eip == 32'hFFFFFFF0);
        check("F.3: ESP unchanged; CALL stack effect not committed",
              dbg_esp == RESET_ESP);
        check("F.4: return address was not pushed",
              stack_mem[would_be_return_slot[9:2]] == 32'h0);
    endtask

    // ----------------------------------------------------------------
    // Test G — Rung 2 regression: JMP SHORT self-loop
    // ----------------------------------------------------------------
    task test_g_rung2_regression;
        logic timed_out;
        int   endi_count, cyc;
        logic saw_fault;
        $display("--- Test G: Rung 2 regression (JMP SHORT self-loop) ---");

        for (int i = 0; i < 256; i++)
            mem_code[i] = (i % 2 == 0) ? 8'hEB : 8'hFE;

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

        check("G.1: no fault in 500 cycles (JMP loop)",  !saw_fault);
        check("G.2: JMP ENDIs fired in 500 cycles",       endi_count >= 5);
        check("G.3: EIP stays at reset vector",           dbg_eip == 32'hFFFFFFF0);
    endtask

    // ----------------------------------------------------------------
    // Test H — Rung 1 regression: 10 consecutive NOPs
    // ----------------------------------------------------------------
    task test_h_rung1_regression;
        logic timed_out;
        $display("--- Test H: Rung 1 regression (10 consecutive NOPs) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        reset_cpu();

        begin : nop_loop
            for (int n = 0; n < 10; n++) begin
                wait_endi(timed_out);
                if (timed_out) begin
                    check("H: NOP timeout", 0);
                    disable nop_loop;
                end
            end
        end

        check("H.1: EIP advanced by 10 after 10 NOPs",
              dbg_eip == 32'hFFFFFFF0 + 32'hA);
        check("H.2: no fault during NOP regression",       !dbg_fault_pending);
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
        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        test_a_call_ret_pair();
        test_b_ret_imm16();
        test_c_nested_depth4();
        test_d_indirect_call();
        test_e_indirect_call_memory();
        test_f_unsupported_memory_form();
        test_g_rung2_regression();
        test_h_rung1_regression();

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
