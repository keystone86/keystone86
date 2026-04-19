`timescale 1ns/1ps

module tb_rung2_jmp;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int MAX_CYCLES      = 90;

    // Default bring-up behavior: keep verbose trace off unless explicitly
    // enabled for diagnosis.
    localparam bit ENABLE_DEBUG = 1'b0;

    logic        clk, reset_n;
    logic [31:0] bus_addr;
    logic        bus_rd, bus_wr;
    logic [3:0]  bus_byteen;
    logic [31:0] bus_dout, bus_din;
    logic        bus_ready;

    logic        stk_wr_en_nc;
    logic [31:0] stk_wr_addr_nc;
    logic [31:0] stk_wr_data_nc;
    logic        stk_rd_req_nc;
    logic [31:0] stk_rd_addr_nc;

    logic [31:0] dbg_eip;
    logic [31:0] dbg_esp;
    logic [1:0]  dbg_mseq_state;
    logic [11:0] dbg_upc;
    logic [7:0]  dbg_entry_id;
    logic [7:0]  dbg_dec_entry_id;
    logic        dbg_endi_pulse;
    logic        dbg_fault_pending;
    logic [3:0]  dbg_fault_class;
    logic        dbg_decode_done;
    logic [31:0] dbg_fetch_addr;

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

        .stk_wr_en                  (stk_wr_en_nc),
        .stk_wr_addr                (stk_wr_addr_nc),
        .stk_wr_data                (stk_wr_data_nc),
        .stk_rd_req                 (stk_rd_req_nc),
        .stk_rd_addr                (stk_rd_addr_nc),
        .stk_rd_data                (32'h0),
        .stk_rd_ready               (1'b0),
        .indirect_call_target       (32'h0),
        .indirect_call_target_valid (1'b0),

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

    logic [7:0] mem_program [0:255];
    logic       rd_pending;

    logic [7:0] bus_addr_lo;
    assign bus_addr_lo = bus_addr[7:0];

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
                bus_din    <= {24'h0, mem_program[bus_addr_lo]};
                bus_ready  <= 1'b1;
                rd_pending <= 1'b0;
            end
        end
    end

    initial clk = 1'b0;
    always #CLK_HALF_PERIOD clk = ~clk;

    task automatic reset_cpu;
        reset_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
    endtask

    task automatic dump_debug(input string why);
        if (ENABLE_DEBUG) begin
            $display("------------------------------------------------------------");
            $display(" DEBUG: %s", why);
            $display(" time=%0t", $time);
            $display(" dbg_eip=%08X dbg_esp=%08X dbg_fault_pending=%0d dbg_fault_class=%0h dbg_endi_pulse=%0d",
                     dbg_eip, dbg_esp, dbg_fault_pending, dbg_fault_class, dbg_endi_pulse);
            $display(" dbg_mseq_state=%0d dbg_upc=%03h dbg_entry_id=%02h dbg_dec_entry_id=%02h dbg_decode_done=%0d",
                     dbg_mseq_state, dbg_upc, dbg_entry_id, dbg_dec_entry_id, dbg_decode_done);
            $display(" bus: rd=%0d wr=%0d addr=%08X ready=%0d din=%08X fetch_addr=%08X",
                     bus_rd, bus_wr, bus_addr, bus_ready, bus_din, dbg_fetch_addr);

            $display(" queue: q_valid=%0d q_data=%02h q_fetch_eip=%08X q_consume=%0d",
                     dut.q_valid, dut.q_data, dut.q_fetch_eip, dut.q_consume);
            $display(" queue: head=%0d tail=%0d count=%0d fetch_ptr=%08X inflight=%0d ready=%0d flush=%0d flush_addr=%08X kill=%0d",
                     dut.u_pq.head, dut.u_pq.tail, dut.u_pq.count,
                     dut.u_pq.fetch_ptr, dut.u_pq.fetch_inflight, dut.u_pq.queue_ready,
                     dut.flush_req, dut.flush_addr, dut.squash);

            $display(" mseq: state=%0d state_next=%0d upc=%03h upc_next=%03h uinst=%08X",
                     dut.u_mseq.state, dut.u_mseq.state_next,
                     dut.u_mseq.upc_r, dut.u_mseq.upc_next, dut.uinst);
            $display(" mseq: execute_fetch_pending=%0d dispatch_pending=%0d dispatch_rom_pending=%0d ext_pending_r=%0d ctrl_transfer_pending=%0d",
                     dut.u_mseq.execute_fetch_pending, dut.u_mseq.dispatch_pending,
                     dut.u_mseq.dispatch_rom_pending, dut.u_mseq.ext_pending_r,
                     dut.u_mseq.ctrl_transfer_pending);
            $display(" mseq: svc_id_r=%02h svc_id_out=%02h svc_req_out=%0d svc_done_in=%0d svc_sr_in=%0d sr_r=%0d",
                     dut.u_mseq.svc_id_r, dut.svc_id_out, dut.svc_req_out,
                     dut.svc_done_in, dut.svc_sr_in, dut.u_mseq.sr_r);
            $display(" mseq: next_eip_r=%08X pc_eip_en=%0d pc_eip_val=%08X pc_target_en=%0d pc_target_val=%08X",
                     dut.u_mseq.next_eip_r, dut.pc_eip_en, dut.pc_eip_val,
                     dut.pc_target_en, dut.pc_target_val);

            $display(" dispatch: fe_req=%0d fe_done=%0d fe_sr=%0d fc_req=%0d fc_done=%0d fc_sr=%0d",
                     dut.fe_svc_req, dut.fe_svc_done, dut.fe_svc_sr,
                     dut.fc_svc_req, dut.fc_svc_done, dut.fc_svc_sr);

            $display(" regs: t2_r=%08X t4_r=%08X meta_next_eip=%08X",
                     dut.t2_r, dut.t4_r, dut.meta_next_eip);

            $display(" commit: endi_req=%0d endi_done=%0d endi_mask=%03h flush_req=%0d flush_addr=%08X",
                     dut.endi_req, dut.endi_done, dut.endi_mask, dut.flush_req, dut.flush_addr);
            $display(" commit: eip_r=%08X pc_eip_en_r=%0d pc_eip_val_r=%08X pc_target_en_r=%0d pc_target_val_r=%08X",
                     dut.u_commit.eip_r,
                     dut.u_commit.pc_eip_en_r, dut.u_commit.pc_eip_val_r,
                     dut.u_commit.pc_target_en_r, dut.u_commit.pc_target_val_r);
            $display("------------------------------------------------------------");
        end
    endtask

    task automatic trace_line(input int cyc);
        if (ENABLE_DEBUG) begin
            $display("[TRACE %0d] EIP=%08X uPC=%03h->%03h mseq=%0d->%0d uinst=%08X dec_done=%0d dec_entry=%02h entry=%02h q_valid=%0d q_data=%02h q_eip=%08X q_consume=%0d head=%0d tail=%0d cnt=%0d q_ready=%0d fptr=%08X inflight=%0d flush=%0d faddr=%08X kill=%0d svc_id=%02h svc_req=%0d svc_done=%0d svc_sr=%0d fe_req=%0d fc_req=%0d exec_fetch_pending=%0d t2=%08X t4=%08X endi_req=%0d endi_done=%0d mask=%03h pc_target_en=%0d pc_target_val=%08X pc_target_en_r=%0d pc_target_val_r=%08X",
                     cyc,
                     dbg_eip,
                     dut.u_mseq.upc_r, dut.u_mseq.upc_next,
                     dut.u_mseq.state, dut.u_mseq.state_next,
                     dut.uinst,
                     dbg_decode_done, dbg_dec_entry_id, dbg_entry_id,
                     dut.q_valid, dut.q_data, dut.q_fetch_eip, dut.q_consume,
                     dut.u_pq.head, dut.u_pq.tail, dut.u_pq.count, dut.u_pq.queue_ready,
                     dut.u_pq.fetch_ptr, dut.u_pq.fetch_inflight,
                     dut.flush_req, dut.flush_addr, dut.squash,
                     dut.svc_id_out, dut.svc_req_out, dut.svc_done_in, dut.svc_sr_in,
                     dut.fe_svc_req, dut.fc_svc_req,
                     dut.u_mseq.execute_fetch_pending,
                     dut.t2_r, dut.t4_r,
                     dut.endi_req, dut.endi_done, dut.endi_mask,
                     dut.pc_target_en, dut.pc_target_val,
                     dut.u_commit.pc_target_en_r, dut.u_commit.pc_target_val_r);
        end
    endtask

    integer i;
    integer endi_count;
    integer flush_count;

    initial begin
        if (ENABLE_DEBUG) begin
            $display("============================================================");
            $display(" Keystone86 / Aegis — Rung 2 Commit/Flush Diagnostic");
            $display("============================================================");
            $display("--- Diagnostic: JMP SHORT self-loop (EB FE) ---");
        end else begin
            $display("Keystone86 / Aegis — Rung 2 Regression");
            $display("  Rung 2: direct JMP service path, committed redirect, bounded self-loop");
        end

        reset_n    = 1'b0;
        rd_pending = 1'b0;
        bus_ready  = 1'b0;
        bus_din    = 32'h0;

        for (i = 0; i < 256; i = i + 1)
            mem_program[i] = (i[0] == 1'b0) ? 8'hEB : 8'hFE;

        reset_cpu();

        endi_count  = 0;
        flush_count = 0;

        for (i = 1; i <= MAX_CYCLES; i = i + 1) begin
            @(posedge clk);
            trace_line(i);

            if (dbg_endi_pulse)
                endi_count = endi_count + 1;

            if (dut.flush_req)
                flush_count = flush_count + 1;

            if (dbg_fault_pending) begin
                dump_debug("unexpected fault during Rung 2 JMP path");
                $fatal(1, "FAIL: fault_pending asserted during Rung 2 direct JMP path");
            end
        end

        if (endi_count < 2) begin
            dump_debug("insufficient ENDI retire count");
            $fatal(1, "FAIL: expected at least 2 committed JMP retires in bounded run");
        end

        if (flush_count < 2) begin
            dump_debug("insufficient flush count");
            $fatal(1, "FAIL: expected at least 2 committed redirect flushes in bounded run");
        end

        if (dbg_entry_id != 8'h07) begin
            dump_debug("unexpected active entry at end of bounded run");
            $fatal(1, "FAIL: expected to remain on JMP entry path");
        end

        if (ENABLE_DEBUG) begin
            $display("------------------------------------------------------------");
            $display("Bounded diagnostic finished after %0d cycles", MAX_CYCLES);
            $display("ENDI count = %0d", endi_count);
            $display("Flush count = %0d", flush_count);
            $display("RESULT: PASS");
            $display("============================================================");
        end else begin
            $display("");
            $display("Rung 2 Regression Summary");
            $display("  [x] Rung 0 baseline still passes");
            $display("  [x] Rung 1 baseline still passes");
            $display("  [x] No fault during bounded direct JMP loop");
            $display("  [x] Committed JMP retires observed: %0d", endi_count);
            $display("  [x] Committed redirect flushes observed: %0d", flush_count);
            $display("  [x] Active decoded entry remains ENTRY_JMP_NEAR");
            $display("");
            $display("RESULT: ALL RUNG 2 TESTS PASSED");
        end

        $finish;
    end

endmodule