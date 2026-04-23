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
// Debug policy:
//   Debug is testbench-only and off by default.
//   It does not change ownership or architectural behavior.
//   It only exposes the exact RET-side failure path while staying within
//   bounded Rung 3 design intent.

`timescale 1ns/1ps

module tb_rung3_call_ret;

    localparam int TIMEOUT             = 8000;
    localparam int CLK_HALF_PERIOD     = 5;
    localparam logic [31:0] RESET_ESP  = 32'h000FFFF0;
    localparam logic [1:0]  MSEQ_FETCH_DECODE = 2'h0;
    localparam bit ENABLE_DEBUG        = 1'b1;

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

            if (stk_wr_en)
                stack_mem[stk_wr_addr[9:2]] <= stk_wr_data;

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

    task automatic dump_ret_debug(input string tag);
        logic [31:0] next_addr;
        integer top_idx;
        integer next_idx;
        if (ENABLE_DEBUG) begin
            next_addr = dbg_esp + 32'd4;
            top_idx   = dbg_esp[9:2];
            next_idx  = next_addr[9:2];

            $display("------------------------------------------------------------");
            $display(" RET DEBUG: %s", tag);
            $display(" time=%0t", $time);
            $display(" dbg_eip=%08X dbg_esp=%08X endi=%0d fault=%0d fc=%0h",
                     dbg_eip, dbg_esp, dbg_endi_pulse, dbg_fault_pending, dbg_fault_class);
            $display(" dec: done=%0d entry=%02h next_eip=%08X target=%08X has_target=%0d is_call=%0d is_ret=%0d has_ret_imm=%0d ret_imm=%04h",
                     dut.decode_done, dut.entry_id, dut.next_eip,
                     dut.target_eip_dec, dut.has_target_dec,
                     dut.is_call_dec, dut.is_ret_dec,
                     dut.has_ret_imm_dec, dut.ret_imm_dec);
            $display(" mseq: state=%0d upc=%03h entry=%02h next_eip_r=%08X target_eip_r=%08X ret_imm_r=%04h",
                     dut.u_mseq.state, dut.u_mseq.upc_r, dut.u_mseq.entry_id_r,
                     dut.u_mseq.next_eip_r, dut.u_mseq.target_eip_r, dut.u_mseq.ret_imm_r);
            $display(" mseq: endi_req=%0d endi_done=%0d endi_mask=%03h ctrl_transfer_pending=%0d execute_fetch_pending=%0d",
                     dut.endi_req, dut.endi_done, dut.endi_mask,
                     dut.u_mseq.ctrl_transfer_pending, dut.u_mseq.execute_fetch_pending);
            $display(" mseq stage: pc_eip_en=%0d pc_eip_val=%08X pc_target_en=%0d pc_target_val=%08X",
                     dut.pc_eip_en, dut.pc_eip_val, dut.pc_target_en, dut.pc_target_val);
            $display(" mseq stage: pc_ret_addr_en=%0d pc_ret_addr_val=%08X pc_ret_imm_en=%0d pc_ret_imm_val=%04h",
                     dut.pc_ret_addr_en, dut.pc_ret_addr_val, dut.pc_ret_imm_en, dut.pc_ret_imm_val);
            $display(" commit: eip_r=%08X esp_r=%08X flush_req=%0d flush_addr=%08X",
                     dut.u_commit.eip_r, dut.u_commit.esp_r, dut.flush_req, dut.flush_addr);
            $display(" commit stage: eff_pc_eip_en=%0d eff_pc_eip_val=%08X eff_pc_target_en=%0d eff_pc_target_val=%08X",
                     dut.u_commit.eff_pc_eip_en, dut.u_commit.eff_pc_eip_val,
                     dut.u_commit.eff_pc_target_en, dut.u_commit.eff_pc_target_val);
            $display(" commit stage: eff_pc_ret_addr_en=%0d eff_pc_ret_addr_val=%08X eff_pc_ret_imm_en=%0d eff_pc_ret_imm_val=%04h",
                     dut.u_commit.eff_pc_ret_addr_en, dut.u_commit.eff_pc_ret_addr_val,
                     dut.u_commit.eff_pc_ret_imm_en, dut.u_commit.eff_pc_ret_imm_val);
            $display(" commit regs: pc_eip_en_r=%0d pc_eip_val_r=%08X pc_target_en_r=%0d pc_target_val_r=%08X",
                     dut.u_commit.pc_eip_en_r, dut.u_commit.pc_eip_val_r,
                     dut.u_commit.pc_target_en_r, dut.u_commit.pc_target_val_r);
            $display(" commit regs: pc_ret_addr_en_r=%0d pc_ret_addr_val_r=%08X pc_ret_imm_en_r=%0d pc_ret_imm_val_r=%04h",
                     dut.u_commit.pc_ret_addr_en_r, dut.u_commit.pc_ret_addr_val_r,
                     dut.u_commit.pc_ret_imm_en_r, dut.u_commit.pc_ret_imm_val_r);
            $display(" commit ret: ret_wait_r=%0d ret_imm_en_saved=%0d ret_imm_val_saved=%04h stk_rd_req=%0d stk_rd_addr=%08X stk_rd_ready=%0d stk_rd_data=%08X",
                     dut.u_commit.ret_wait_r, dut.u_commit.ret_imm_en_saved,
                     dut.u_commit.ret_imm_val_saved, dut.stk_rd_req, dut.stk_rd_addr,
                     stk_rd_ready, stk_rd_data);
            $display(" stack mem: top_addr=%08X top_data=%08X next_addr=%08X next_data=%08X",
                     dbg_esp, stack_mem[top_idx], next_addr, stack_mem[next_idx]);
            $display("------------------------------------------------------------");
        end
    endtask

    task automatic dump_ret_trace_window(input string tag, input int cycles);
        integer k;
        if (ENABLE_DEBUG) begin
            $display("================ RET TRACE WINDOW: %s ================", tag);
            for (k = 0; k < cycles; k = k + 1) begin
                @(posedge clk);
                $display("[RETTRACE %0d] EIP=%08X ESP=%08X entry=%02h upc=%03h state=%0d endi_req=%0d endi_done=%0d mask=%03h ret_wait=%0d stk_rd_req=%0d stk_rd_addr=%08X stk_rd_ready=%0d stk_rd_data=%08X pc_eip_en=%0d pc_target_en=%0d pc_ret_addr_en=%0d pc_ret_imm_en=%0d",
                         k,
                         dbg_eip, dbg_esp,
                         dut.u_mseq.entry_id_r, dut.u_mseq.upc_r, dut.u_mseq.state,
                         dut.endi_req, dut.endi_done, dut.endi_mask,
                         dut.u_commit.ret_wait_r,
                         dut.stk_rd_req, dut.stk_rd_addr, stk_rd_ready, stk_rd_data,
                         dut.pc_eip_en, dut.pc_target_en, dut.pc_ret_addr_en, dut.pc_ret_imm_en);
            end
            $display("======================================================");
        end
    endtask

    // ----------------------------------------------------------------
    // Test A — Direct CALL + RET pair
    // ----------------------------------------------------------------
    task test_a_call_ret_pair;
        logic timed_out;
        logic [31:0] esp_after_call;
        $display("--- Test A: Direct CALL + RET pair ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hE8;
        mem_code[8'hF1] = 8'h02;
        mem_code[8'hF2] = 8'h00;
        mem_code[8'hF3] = 8'h90;
        mem_code[8'hF4] = 8'h90;
        mem_code[8'hF5] = 8'hC3;

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        wait_endi(timed_out);
        check("A.1: CALL ENDI fires",                    !timed_out);
        check("A.2: EIP = CALL target (0xFFFFFFF5)",    dbg_eip == 32'hFFFFFFF5);
        check("A.3: ESP decremented by 4",              dbg_esp == RESET_ESP - 32'h4);
        check("A.4: no fault after CALL",               !dbg_fault_pending);
        esp_after_call = dbg_esp;

        @(posedge clk);
        check("A.5: return address on stack = 0xFFFFFFF3",
              stack_mem[esp_after_call[9:2]] == 32'hFFFFFFF3);

        wait_endi(timed_out);
        check("A.6: RET ENDI fires",                    !timed_out);

        if (dbg_eip !== 32'hFFFFFFF3) begin
            dump_ret_debug("A.7 direct RET wrong EIP");
            dump_ret_trace_window("A.7 direct RET wrong EIP", 8);
        end
        check("A.7: EIP = return address (0xFFFFFFF3)", dbg_eip == 32'hFFFFFFF3);

        if (dbg_esp !== RESET_ESP) begin
            dump_ret_debug("A.8 direct RET wrong ESP");
        end
        check("A.8: ESP restored to RESET_ESP",         dbg_esp == RESET_ESP);

        check("A.9: no fault after RET",                !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test B — RET imm16 (C2)
    // ----------------------------------------------------------------
    task test_b_ret_imm16;
        logic timed_out;
        $display("--- Test B: RET imm16 (C2 08 00) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hE8;
        mem_code[8'hF1] = 8'h02;
        mem_code[8'hF2] = 8'h00;
        mem_code[8'hF3] = 8'h90;
        mem_code[8'hF4] = 8'h90;
        mem_code[8'hF5] = 8'hC2;
        mem_code[8'hF6] = 8'h08;
        mem_code[8'hF7] = 8'h00;

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        wait_endi(timed_out);
        check("B.1: CALL ENDI fires",                   !timed_out);
        check("B.2: EIP = 0xFFFFFFF5 after CALL",       dbg_eip == 32'hFFFFFFF5);

        wait_endi(timed_out);
        check("B.3: RET imm16 ENDI fires",              !timed_out);

        if (dbg_eip !== 32'hFFFFFFF3) begin
            dump_ret_debug("B.4 RET imm16 wrong EIP");
            dump_ret_trace_window("B.4 RET imm16 wrong EIP", 8);
        end
        check("B.4: EIP = return address (0xFFFFFFF3)", dbg_eip == 32'hFFFFFFF3);

        if (dbg_esp !== (RESET_ESP + 32'h8)) begin
            dump_ret_debug("B.5 RET imm16 wrong ESP");
        end
        check("B.5: ESP = RESET_ESP + 8",               dbg_esp == RESET_ESP + 32'h8);

        check("B.6: no fault after RET imm16",          !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test C — Nested CALL/RET depth 4
    // ----------------------------------------------------------------
    task test_c_nested_depth4;
        logic timed_out;
        $display("--- Test C: Nested CALL/RET depth 4 ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;

        mem_code[8'hE0] = 8'hE8; mem_code[8'hE1] = 8'h02; mem_code[8'hE2] = 8'h00;
        mem_code[8'hE3] = 8'hEB; mem_code[8'hE4] = 8'hFE;

        mem_code[8'hE5] = 8'hE8; mem_code[8'hE6] = 8'h02; mem_code[8'hE7] = 8'h00;
        mem_code[8'hE8] = 8'hC3;

        mem_code[8'hEA] = 8'hE8; mem_code[8'hEB] = 8'h02; mem_code[8'hEC] = 8'h00;
        mem_code[8'hED] = 8'hC3;

        mem_code[8'hEF] = 8'hC3;

        mem_code[8'hF0] = 8'hEB;
        mem_code[8'hF1] = 8'hEE;

        indirect_call_target       = 32'h0;
        indirect_call_target_valid = 1'b0;
        reset_cpu();

        wait_n_endi(7, timed_out);
        if (timed_out) begin
            dump_ret_debug("C.1 nested CALL/RET timeout");
            dump_ret_trace_window("C.1 nested CALL/RET timeout", 12);
        end
        check("C.1: all 7 ENDIs fire without timeout",   !timed_out);

        if (dbg_eip !== 32'hFFFFFFE3) begin
            dump_ret_debug("C.2 nested CALL/RET wrong EIP");
        end
        check("C.2: EIP = 0xFFFFFFE3 (depth-1 return)",  dbg_eip == 32'hFFFFFFE3);

        if (dbg_esp !== RESET_ESP) begin
            dump_ret_debug("C.3 nested CALL/RET wrong ESP");
        end
        check("C.3: ESP = RESET_ESP (fully unwound)",    dbg_esp == RESET_ESP);

        check("C.4: no fault during nested CALL/RET",    !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test D — Indirect CALL (FF /2) + RET
    // ----------------------------------------------------------------
    task test_d_indirect_call;
        logic timed_out;
        logic [31:0] esp_after_call;
        $display("--- Test D: Indirect CALL (FF /2, register form) ---");

        for (int i = 0; i < 256; i++) mem_code[i] = 8'h90;
        mem_code[8'hF0] = 8'hFF;
        mem_code[8'hF1] = 8'hD0;
        mem_code[8'hF2] = 8'h90;
        mem_code[8'hA0] = 8'hC3;

        indirect_call_target       = 32'hFFFFFFA0;
        indirect_call_target_valid = 1'b1;
        reset_cpu();

        wait_endi(timed_out);
        check("D.1: indirect CALL ENDI fires",               !timed_out);
        check("D.2: EIP = indirect target (0xFFFFFFA0)",     dbg_eip == 32'hFFFFFFA0);
        check("D.3: ESP decremented by 4",                   dbg_esp == RESET_ESP - 32'h4);
        check("D.4: no fault after indirect CALL",           !dbg_fault_pending);
        esp_after_call = dbg_esp;

        @(posedge clk);
        check("D.5: return address on stack = 0xFFFFFFF2",
              stack_mem[esp_after_call[9:2]] == 32'hFFFFFFF2);

        wait_endi(timed_out);
        check("D.6: RET after indirect CALL fires",          !timed_out);

        if (dbg_eip !== 32'hFFFFFFF2) begin
            dump_ret_debug("D.7 indirect CALL return wrong EIP");
            dump_ret_trace_window("D.7 indirect CALL return wrong EIP", 8);
        end
        check("D.7: EIP = 0xFFFFFFF2 (return address)",      dbg_eip == 32'hFFFFFFF2);

        if (dbg_esp !== RESET_ESP) begin
            dump_ret_debug("D.8 indirect CALL return wrong ESP");
        end
        check("D.8: ESP restored",                           dbg_esp == RESET_ESP);

        check("D.9: no fault after RET",                     !dbg_fault_pending);
    endtask

    // ----------------------------------------------------------------
    // Test E — Rung 2 regression: JMP SHORT self-loop
    // ----------------------------------------------------------------
    task test_e_rung2_regression;
        int endi_count, cyc;
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

        check("E.1: no fault in 500 cycles (JMP loop)", !saw_fault);
        check("E.2: JMP ENDIs fired in 500 cycles",      endi_count >= 5);
        check("E.3: EIP stays at reset vector",          dbg_eip == 32'hFFFFFFF0);
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
        check("F.2: no fault during NOP regression",      !dbg_fault_pending);
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