// Keystone86 / Aegis
// sim/tb/tb_rung4_jcc.sv
// Rung 4 self-checking testbench: short Jcc control-transfer path.
//
// The testbench initializes committed EFLAGS directly because flag-producing
// instructions are later-rung work. Rung 4 proves that the committed flag
// state is consumed by flow_control:CONDITION_EVAL and that microcode/commit
// resolve taken versus not-taken Jcc only at ENDI.

`timescale 1ns/1ps

module tb_rung4_jcc;

    localparam int TIMEOUT         = 2000;
    localparam int CLK_HALF_PERIOD = 5;
    localparam logic [31:0] RESET_EIP = 32'hFFFFFFF0;
    localparam logic [7:0] ENTRY_JCC_ID = 8'h0D;
    localparam logic [7:0] SVC_VALIDATE_NEAR_TRANSFER = 8'h44;

    logic        clk, reset_n;
    logic [31:0] bus_addr;
    logic        bus_rd, bus_wr;
    logic [3:0]  bus_byteen;
    logic [31:0] bus_dout, bus_din;
    logic        bus_ready;

    logic [31:0] dbg_eip, dbg_esp;
    logic [1:0]  dbg_mseq_state;
    logic [11:0] dbg_upc;
    logic [7:0]  dbg_entry_id, dbg_dec_entry_id;
    logic        dbg_endi_pulse, dbg_fault_pending;
    logic [3:0]  dbg_fault_class;
    logic        dbg_decode_done;
    logic [31:0] dbg_fetch_addr;

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
        .dbg_esp           (dbg_esp),
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

    logic [7:0] mem_code [0:255];
    logic       bus_pending;
    logic [31:0] bus_addr_pending;
    logic [3:0]  bus_byteen_pending;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready        <= 1'b0;
            bus_din          <= 32'h0;
            bus_pending      <= 1'b0;
            bus_addr_pending <= 32'h0;
            bus_byteen_pending <= 4'h0;
        end else begin
            bus_ready <= 1'b0;

            if (bus_rd && !bus_pending) begin
                bus_pending <= 1'b1;
                bus_addr_pending <= bus_addr;
                bus_byteen_pending <= bus_byteen;
            end

            if (bus_pending) begin
                if (bus_byteen_pending == 4'b0001)
                    bus_din <= {24'h0, mem_code[bus_addr_pending[7:0]]};
                else
                    bus_din <= 32'h0;
                bus_ready <= 1'b1;
                bus_pending <= 1'b0;
            end
        end
    end

    initial clk = 1'b0;
    always #CLK_HALF_PERIOD clk = ~clk;

    int pass_count;
    int fail_count;
    logic [31:0] forced_flags;

    function automatic logic [31:0] flags_for(
        input logic [3:0] cond,
        input logic       taken
    );
        logic [31:0] flags;
        begin
            flags = 32'h00000002;
            unique case (cond)
                4'h0: flags[11] = taken;       // O
                4'h1: flags[11] = !taken;      // NO
                4'h2: flags[0]  = taken;       // B
                4'h3: flags[0]  = !taken;      // NB
                4'h4: flags[6]  = taken;       // Z
                4'h5: flags[6]  = !taken;      // NZ
                4'h6: begin                    // BE
                    flags[0] = taken;
                    flags[6] = 1'b0;
                end
                4'h7: begin                    // NBE
                    flags[0] = !taken;
                    flags[6] = 1'b0;
                end
                4'h8: flags[7]  = taken;       // S
                4'h9: flags[7]  = !taken;      // NS
                4'hA: flags[2]  = taken;       // P
                4'hB: flags[2]  = !taken;      // NP
                4'hC: begin                    // L: SF != OF
                    flags[7]  = taken;
                    flags[11] = 1'b0;
                end
                4'hD: begin                    // NL: SF == OF
                    flags[7]  = !taken;
                    flags[11] = 1'b0;
                end
                4'hE: begin                    // LE
                    flags[6]  = taken;
                    flags[7]  = 1'b0;
                    flags[11] = 1'b0;
                end
                4'hF: begin                    // NLE
                    flags[6]  = !taken;
                    flags[7]  = 1'b0;
                    flags[11] = 1'b0;
                end
                default: ;
            endcase
            return flags;
        end
    endfunction

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02h dec=%02h fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_dec_entry_id,
                     dbg_fault_pending, dbg_fault_class);
            fail_count++;
        end
    endtask

    task automatic reset_cpu;
        reset_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(posedge clk);
    endtask

    task automatic load_jcc_program(input logic [3:0] cond, input logic [7:0] disp);
        for (int i = 0; i < 256; i++)
            mem_code[i] = 8'h90;
        mem_code[8'hF0] = {4'h7, cond};
        mem_code[8'hF1] = disp;
    endtask

    task automatic wait_jcc_endi(
        output logic timed_out,
        output logic saw_decode,
        output logic saw_validate,
        output logic saw_flush
    );
        int cycles;
        timed_out = 1'b0;
        saw_decode = 1'b0;
        saw_validate = 1'b0;
        saw_flush = 1'b0;
        cycles = 0;

        begin : wait_loop
            forever begin
                @(posedge clk);

                if (dbg_decode_done && (dbg_dec_entry_id == ENTRY_JCC_ID))
                    saw_decode = 1'b1;

                if (saw_decode && dut.fc_svc_req &&
                        (dut.fc_svc_id == SVC_VALIDATE_NEAR_TRANSFER))
                    saw_validate = 1'b1;

                if (saw_decode && dut.flush_req)
                    saw_flush = 1'b1;

                if (saw_decode && dbg_endi_pulse) begin
                    @(posedge clk);
                    disable wait_loop;
                end

                cycles++;
                if (cycles > TIMEOUT) begin
                    timed_out = 1'b1;
                    disable wait_loop;
                end
            end
        end
    endtask

    task automatic run_jcc_case(
        input string       name,
        input logic [3:0]  cond,
        input logic        taken,
        input logic [7:0]  disp,
        input logic [31:0] expected_eip
    );
        logic timed_out;
        logic saw_decode;
        logic saw_validate;
        logic saw_flush;
        begin
            release dut.u_commit.eflags_r;
            load_jcc_program(cond, disp);
            reset_cpu();
            forced_flags = flags_for(cond, taken);
            force dut.u_commit.eflags_r = forced_flags;

            wait_jcc_endi(timed_out, saw_decode, saw_validate, saw_flush);

            check({name, ": completed"}, !timed_out);
            check({name, ": decoded ENTRY_JCC"}, saw_decode && (dbg_entry_id == ENTRY_JCC_ID));
            check({name, ": EIP"}, dbg_eip == expected_eip);
            check({name, ": no fault"}, !dbg_fault_pending);
            if (taken) begin
                check({name, ": taken path validated"}, saw_validate);
                check({name, ": taken path flushed"}, saw_flush);
            end else begin
                check({name, ": not-taken skipped validation"}, !saw_validate);
                check({name, ": not-taken did not flush"}, !saw_flush);
            end

            release dut.u_commit.eflags_r;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;

        $display("Keystone86 / Aegis - Rung 4 Jcc Regression");

        for (int cond = 0; cond < 16; cond++) begin
            run_jcc_case($sformatf("Jcc 0x%02X taken", 8'h70 + cond[3:0]),
                         cond[3:0], 1'b1, 8'h05, RESET_EIP + 32'h7);
            run_jcc_case($sformatf("Jcc 0x%02X not taken", 8'h70 + cond[3:0]),
                         cond[3:0], 1'b0, 8'h05, RESET_EIP + 32'h2);
        end

        run_jcc_case("JZ taken max forward disp8 +127",
                     4'h4, 1'b1, 8'h7F, RESET_EIP + 32'h2 + 32'sd127);
        run_jcc_case("JZ taken max backward disp8 -128",
                     4'h4, 1'b1, 8'h80, RESET_EIP + 32'h2 - 32'sd128);

        $display("");
        $display("Rung 4 Regression Summary");
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("RESULT: ALL RUNG 4 TESTS PASSED");
            $finish;
        end

        $fatal(1, "RESULT: RUNG 4 TESTS FAILED");
    end

endmodule
