// Keystone86 / Aegis
// sim/tb/tb_rung5_int_enter.sv
// Bounded Rung 5 Pass 2 smoke: INT imm8 -> INT_ENTER only.
//
// This is not a full Rung 5 acceptance test. It proves the accepted Pass 2
// contract: INT_ENTER reads a real-mode IVT entry, stages a 16-bit
// FLAGS/CS/IP frame, clears IF in committed FLAGS, commits flat handler EIP
// plus visible CS only through CM_INT, and flushes through commit.

`timescale 1ns/1ps

module tb_rung5_int_enter;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 4000;

    localparam logic [31:0] RESET_ESP = 32'h000FFFF0;
    localparam logic [7:0]  ENTRY_INT_ID = 8'h0E;
    localparam logic [7:0]  SVC_FETCH_IMM8 = 8'h01;
    localparam logic [7:0]  SVC_INT_ENTER  = 8'h62;
    localparam logic [9:0]  CM_INT_MASK    = 10'h3DE;

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

    logic [7:0] mem [0:65535];
    logic       bus_pending;
    logic       bus_wr_pending;
    logic [31:0] bus_addr_pending;
    logic [31:0] bus_dout_pending;
    logic [3:0]  bus_byteen_pending;

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready <= 1'b0;
            bus_din <= 32'h0;
            bus_pending <= 1'b0;
            bus_wr_pending <= 1'b0;
            bus_addr_pending <= 32'h0;
            bus_dout_pending <= 32'h0;
            bus_byteen_pending <= 4'h0;
        end else begin
            bus_ready <= 1'b0;

            if ((bus_rd || bus_wr) && !bus_pending) begin
                bus_pending <= 1'b1;
                bus_wr_pending <= bus_wr;
                bus_addr_pending <= bus_addr;
                bus_dout_pending <= bus_dout;
                bus_byteen_pending <= bus_byteen;
            end

            if (bus_pending) begin
                if (bus_wr_pending) begin
                    if (bus_byteen_pending[0])
                        mem[pa16(bus_addr_pending)] <= bus_dout_pending[7:0];
                    if (bus_byteen_pending[1])
                        mem[pa16(bus_addr_pending + 32'd1)] <= bus_dout_pending[15:8];
                    if (bus_byteen_pending[2])
                        mem[pa16(bus_addr_pending + 32'd2)] <= bus_dout_pending[23:16];
                    if (bus_byteen_pending[3])
                        mem[pa16(bus_addr_pending + 32'd3)] <= bus_dout_pending[31:24];
                    bus_din <= 32'h0;
                end else if (bus_byteen_pending == 4'b0001) begin
                    bus_din <= {24'h0, mem[pa16(bus_addr_pending)]};
                end else begin
                    bus_din <= {
                        mem[pa16(bus_addr_pending + 32'd3)],
                        mem[pa16(bus_addr_pending + 32'd2)],
                        mem[pa16(bus_addr_pending + 32'd1)],
                        mem[pa16(bus_addr_pending)]
                    };
                end

                bus_ready <= 1'b1;
                bus_pending <= 1'b0;
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
        @(posedge clk);
    endtask

    int failures;
    int cycles;
    logic saw_decode;
    logic saw_fetch_imm8;
    logic saw_int_enter;
    logic saw_cm_int;
    logic saw_flush;
    logic early_visible;
    logic timed_out;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X ESP=%08X CS=%04X EFLAGS=%08X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_esp, dut.u_commit.cs_r,
                     dut.u_commit.eflags_r, dbg_fault_pending, dbg_fault_class);
            failures++;
        end
    endtask

    initial begin
        failures = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;

        for (int i = 0; i < 65536; i++)
            mem[i] = 8'h90;

        // Program at reset vector: INT 21h, followed by NOP filler.
        mem[16'hFFF0] = 8'hCD;
        mem[16'hFFF1] = 8'h21;
        mem[16'hFFF2] = 8'h90;

        // IVT[0x21] = offset 0x0030, segment 0x5678.
        mem[16'h0084] = 8'h30;
        mem[16'h0085] = 8'h00;
        mem[16'h0086] = 8'h78;
        mem[16'h0087] = 8'h56;
        mem[16'h0030] = 8'h90;

        $display("Keystone86 / Aegis - Rung 5 Pass 2 INT_ENTER Smoke");

        reset_cpu();

        // Initialize in-scope architectural inputs for the interrupt frame.
        // This is setup state, not a post-INT shortcut.
        force dut.u_commit.cs_r = 16'h1234;
        force dut.u_commit.eflags_r = 32'h00000202;
        @(posedge clk);
        release dut.u_commit.cs_r;
        release dut.u_commit.eflags_r;

        saw_decode = 1'b0;
        saw_fetch_imm8 = 1'b0;
        saw_int_enter = 1'b0;
        saw_cm_int = 1'b0;
        saw_flush = 1'b0;
        early_visible = 1'b0;
        timed_out = 1'b1;

        begin : wait_int_enter
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);

                if (dbg_decode_done && (dbg_dec_entry_id == ENTRY_INT_ID))
                    saw_decode = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM8))
                    saw_fetch_imm8 = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_INT_ENTER))
                    saw_int_enter = 1'b1;

                if (dut.endi_req && (dut.endi_mask == CM_INT_MASK))
                    saw_cm_int = 1'b1;

                if (!saw_cm_int &&
                    ((dbg_eip == 32'h00000030) || (dut.u_commit.cs_r == 16'h5678)))
                    early_visible = 1'b1;

                if (dut.flush_req && (dut.flush_addr == 32'h00000030))
                    saw_flush = 1'b1;

                if (dbg_endi_pulse) begin
                    timed_out = 1'b0;
                    @(posedge clk);
                    disable wait_int_enter;
                end
            end
        end

        check("decoded ENTRY_INT", saw_decode);
        check("FETCH_IMM8 service issued", saw_fetch_imm8);
        check("INT_ENTER service issued", saw_int_enter);
        check("ENDI used CM_INT", saw_cm_int);
        check("no early EIP/CS visibility before CM_INT", !early_visible);
        check("INT ENDI completed", !timed_out);
        check("no fault after INT_ENTER", !dbg_fault_pending);
        check("committed EIP = IVT offset 0x0030", dbg_eip == 32'h00000030);
        check("committed CS = IVT segment 0x5678", dut.u_commit.cs_r == 16'h5678);
        check("IF cleared in committed FLAGS", dut.u_commit.eflags_r[9] == 1'b0);
        check("FLAGS reserved bit 1 preserved", dut.u_commit.eflags_r[1] == 1'b1);
        check("ESP decremented by 6", dbg_esp == RESET_ESP - 32'd6);
        check("committed redirect flush to handler offset", saw_flush);

        check("frame IP low byte", mem[16'hFFEA] == 8'hF2);
        check("frame IP high byte", mem[16'hFFEB] == 8'hFF);
        check("frame CS low byte", mem[16'hFFEC] == 8'h34);
        check("frame CS high byte", mem[16'hFFED] == 8'h12);
        check("frame FLAGS low byte", mem[16'hFFEE] == 8'h02);
        check("frame FLAGS high byte", mem[16'hFFEF] == 8'h02);

        $display("");
        $display("Rung 5 Pass 2 INT_ENTER Summary");
        $display("  Failed: %0d", failures);

        if (failures == 0) begin
            $display("RESULT: RUNG 5 PASS 2 INT_ENTER SMOKE PASSED");
            $finish;
        end

        $fatal(1, "RESULT: RUNG 5 PASS 2 INT_ENTER SMOKE FAILED");
    end

endmodule
