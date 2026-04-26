// Keystone86 / Aegis
// sim/tb/tb_rung5_iret_flow.sv
// Bounded Rung 5 Pass 3 smoke: direct IRET -> IRET_FLOW only.
//
// This is not a full Rung 5 acceptance test. It proves the accepted Pass 3
// contract: IRET_FLOW reads the 16-bit real-mode frame at ESP, stages popped
// EIP/CS/FLAGS/ESP only, restores IF through the low FLAGS word, preserves the
// current upper EFLAGS bits, and makes the result visible only through CM_IRET.

`timescale 1ns/1ps

module tb_rung5_iret_flow;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 4000;

    localparam logic [31:0] FRAME_ESP      = 32'h0000FFE0;
    localparam logic [31:0] RETURN_EIP     = 32'h00000040;
    localparam logic [15:0] RETURN_CS      = 16'h2468;
    localparam logic [15:0] RETURN_FLAGS   = 16'h0202;
    localparam logic [31:0] INITIAL_FLAGS  = 32'hCAFE0002;
    localparam logic [31:0] EXPECT_FLAGS   = 32'hCAFE0202;

    localparam logic [7:0]  ENTRY_IRET_ID  = 8'h0F;
    localparam logic [7:0]  SVC_IRET_FLOW  = 8'h63;
    localparam logic [9:0]  CM_IRET_MASK   = 10'h3DE;

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
    logic saw_iret_flow;
    logic saw_cm_iret;
    logic saw_flush;
    logic saw_frame_lo_read;
    logic saw_frame_flags_read;
    logic saw_unexpected_write;
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

        // Program at reset vector: IRET, followed by NOP filler.
        mem[16'hFFF0] = 8'hCF;
        mem[16'hFFF1] = 8'h90;

        // Direct-IRET setup frame. This is input state for the service path,
        // not a shortcut around IRET_FLOW.
        mem[pa16(FRAME_ESP + 32'd0)] = RETURN_EIP[7:0];
        mem[pa16(FRAME_ESP + 32'd1)] = RETURN_EIP[15:8];
        mem[pa16(FRAME_ESP + 32'd2)] = RETURN_CS[7:0];
        mem[pa16(FRAME_ESP + 32'd3)] = RETURN_CS[15:8];
        mem[pa16(FRAME_ESP + 32'd4)] = RETURN_FLAGS[7:0];
        mem[pa16(FRAME_ESP + 32'd5)] = RETURN_FLAGS[15:8];

        $display("Keystone86 / Aegis - Rung 5 Pass 3 IRET_FLOW Smoke");

        reset_cpu();

        // Initialize in-scope architectural inputs for the IRET pop. This is
        // setup state, not a post-IRET shortcut.
        force dut.u_commit.esp_r = FRAME_ESP;
        force dut.u_commit.cs_r = 16'h1357;
        force dut.u_commit.eflags_r = INITIAL_FLAGS;
        @(posedge clk);
        release dut.u_commit.esp_r;
        release dut.u_commit.cs_r;
        release dut.u_commit.eflags_r;

        saw_decode = 1'b0;
        saw_iret_flow = 1'b0;
        saw_cm_iret = 1'b0;
        saw_flush = 1'b0;
        saw_frame_lo_read = 1'b0;
        saw_frame_flags_read = 1'b0;
        saw_unexpected_write = 1'b0;
        early_visible = 1'b0;
        timed_out = 1'b1;

        begin : wait_iret_flow
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);

                if (dbg_decode_done && (dbg_dec_entry_id == ENTRY_IRET_ID))
                    saw_decode = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_IRET_FLOW))
                    saw_iret_flow = 1'b1;

                if (dut.endi_req && (dut.endi_mask == CM_IRET_MASK))
                    saw_cm_iret = 1'b1;

                if (bus_rd && (bus_addr == FRAME_ESP) && (bus_byteen == 4'b1111))
                    saw_frame_lo_read = 1'b1;

                if (bus_rd && (bus_addr == (FRAME_ESP + 32'd4)) &&
                    (bus_byteen == 4'b1111))
                    saw_frame_flags_read = 1'b1;

                if (bus_wr)
                    saw_unexpected_write = 1'b1;

                if (!saw_cm_iret &&
                    ((dbg_eip == RETURN_EIP) ||
                     (dut.u_commit.cs_r == RETURN_CS) ||
                     (dut.u_commit.eflags_r == EXPECT_FLAGS) ||
                     (dbg_esp == (FRAME_ESP + 32'd6))))
                    early_visible = 1'b1;

                if (dut.flush_req && (dut.flush_addr == RETURN_EIP))
                    saw_flush = 1'b1;

                if (saw_cm_iret && dbg_endi_pulse) begin
                    timed_out = 1'b0;
                    @(posedge clk);
                    disable wait_iret_flow;
                end
            end
        end

        check("decoded ENTRY_IRET", saw_decode);
        check("IRET_FLOW service issued", saw_iret_flow);
        check("ENDI used CM_IRET", saw_cm_iret);
        check("frame IP/CS read from [ESP+0]", saw_frame_lo_read);
        check("frame FLAGS read from [ESP+4]", saw_frame_flags_read);
        check("IRET did not write stack memory", !saw_unexpected_write);
        check("no early EIP/CS/FLAGS/ESP visibility before CM_IRET", !early_visible);
        check("IRET ENDI completed", !timed_out);
        check("no fault after IRET_FLOW", !dbg_fault_pending);
        check("committed EIP = zero-extended popped IP", dbg_eip == RETURN_EIP);
        check("committed CS = popped CS", dut.u_commit.cs_r == RETURN_CS);
        check("committed FLAGS low 16 restored", dut.u_commit.eflags_r[15:0] == RETURN_FLAGS);
        check("committed FLAGS upper 16 preserved", dut.u_commit.eflags_r[31:16] == INITIAL_FLAGS[31:16]);
        check("IF restored from popped FLAGS", dut.u_commit.eflags_r[9] == RETURN_FLAGS[9]);
        check("ESP incremented by 6", dbg_esp == FRAME_ESP + 32'd6);
        check("committed redirect flush to popped IP", saw_flush);

        $display("");
        $display("Rung 5 Pass 3 IRET_FLOW Summary");
        $display("  Failed: %0d", failures);

        if (failures == 0) begin
            $display("RESULT: RUNG 5 PASS 3 IRET_FLOW SMOKE PASSED");
            $finish;
        end

        $fatal(1, "RESULT: RUNG 5 PASS 3 IRET_FLOW SMOKE FAILED");
    end

endmodule
