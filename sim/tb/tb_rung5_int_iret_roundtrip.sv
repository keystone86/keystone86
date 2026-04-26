// Keystone86 / Aegis
// sim/tb/tb_rung5_int_iret_roundtrip.sv
// Bounded Rung 5 Pass 5 smoke: integrated INT imm8 -> handler IRET round trip.
//
// This test proves the final integrated Rung 5 phase-1 real-mode slice without
// adding protected-mode behavior. The handler fetch model is intentionally flat:
// IVT[0x21].offset is the fetch address for the trivial IRET handler.

`timescale 1ns/1ps

module tb_rung5_int_iret_roundtrip;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 9000;

    localparam logic [31:0] RESET_ESP       = 32'h000FFFF0;
    localparam logic [31:0] FRAME_ESP       = RESET_ESP - 32'd6;
    localparam logic [31:0] RETURN_EIP      = 32'h0000FFF2;
    localparam logic [15:0] RETURN_IP       = 16'hFFF2;
    localparam logic [15:0] INITIAL_CS      = 16'h1234;
    localparam logic [15:0] HANDLER_CS      = 16'h5678;
    localparam logic [31:0] HANDLER_EIP     = 32'h00000030;
    localparam logic [31:0] INITIAL_FLAGS   = 32'h00000202;

    localparam logic [7:0]  ENTRY_INT_ID    = 8'h0E;
    localparam logic [7:0]  ENTRY_IRET_ID   = 8'h0F;
    localparam logic [7:0]  SVC_FETCH_IMM8  = 8'h01;
    localparam logic [7:0]  SVC_INT_ENTER   = 8'h62;
    localparam logic [7:0]  SVC_IRET_FLOW   = 8'h63;
    localparam logic [9:0]  CM_INT_MASK     = 10'h3DE;
    localparam logic [9:0]  CM_IRET_MASK    = 10'h3DE;

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
    logic saw_decode_int;
    logic saw_fetch_imm8;
    logic saw_vector_21;
    logic saw_int_enter;
    logic saw_cm_int;
    logic saw_int_flush;
    logic saw_decode_iret;
    logic saw_iret_flow;
    logic saw_cm_iret;
    logic saw_iret_flush;
    logic saw_frame_lo_read;
    logic saw_frame_flags_read;
    logic early_int_visible;
    logic early_iret_visible;
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

        // Reset stream: INT 21h, then a NOP continuation after IRET.
        mem[16'hFFF0] = 8'hCD;
        mem[16'hFFF1] = 8'h21;
        mem[16'hFFF2] = 8'h90;

        // IVT[0x21] = offset 0x0030, segment 0x5678. Rung 5 phase 1 keeps
        // handler fetch flat to offset 0x0030; no CS<<4 translation is tested.
        mem[16'h0084] = HANDLER_EIP[7:0];
        mem[16'h0085] = HANDLER_EIP[15:8];
        mem[16'h0086] = HANDLER_CS[7:0];
        mem[16'h0087] = HANDLER_CS[15:8];

        // Trivial interrupt handler: IRET.
        mem[16'h0030] = 8'hCF;

        $display("Keystone86 / Aegis - Rung 5 Pass 5 INT/IRET Round Trip");

        reset_cpu();

        // Initial architectural setup for the frame. This is input state for
        // INT_ENTER/IRET_FLOW, not a shortcut around either committed result.
        force dut.u_commit.cs_r = INITIAL_CS;
        force dut.u_commit.eflags_r = INITIAL_FLAGS;
        @(posedge clk);
        release dut.u_commit.cs_r;
        release dut.u_commit.eflags_r;

        saw_decode_int = 1'b0;
        saw_fetch_imm8 = 1'b0;
        saw_vector_21 = 1'b0;
        saw_int_enter = 1'b0;
        saw_cm_int = 1'b0;
        saw_int_flush = 1'b0;
        saw_decode_iret = 1'b0;
        saw_iret_flow = 1'b0;
        saw_cm_iret = 1'b0;
        saw_iret_flush = 1'b0;
        saw_frame_lo_read = 1'b0;
        saw_frame_flags_read = 1'b0;
        early_int_visible = 1'b0;
        early_iret_visible = 1'b0;
        timed_out = 1'b1;

        begin : wait_roundtrip
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);

                if (dbg_decode_done && (dbg_dec_entry_id == ENTRY_INT_ID))
                    saw_decode_int = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM8))
                    saw_fetch_imm8 = 1'b1;

                if (dut.u_fetch_eng.t4_wr_en && (dut.u_fetch_eng.t4_wr_data == 32'h21))
                    saw_vector_21 = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_INT_ENTER))
                    saw_int_enter = 1'b1;

                if (dut.endi_req && (dut.endi_mask == CM_INT_MASK) && !saw_cm_int)
                    saw_cm_int = 1'b1;

                if (!saw_cm_int &&
                    ((dbg_eip == HANDLER_EIP) ||
                     (dut.u_commit.cs_r == HANDLER_CS) ||
                     (dut.u_commit.eflags_r[9] == 1'b0) ||
                     (dbg_esp == FRAME_ESP)))
                    early_int_visible = 1'b1;

                if (dut.flush_req && (dut.flush_addr == HANDLER_EIP))
                    saw_int_flush = 1'b1;

                if (saw_cm_int && dbg_decode_done &&
                    (dbg_dec_entry_id == ENTRY_IRET_ID))
                    saw_decode_iret = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_IRET_FLOW))
                    saw_iret_flow = 1'b1;

                if (bus_rd && (bus_addr == FRAME_ESP) && (bus_byteen == 4'b1111))
                    saw_frame_lo_read = 1'b1;

                if (bus_rd && (bus_addr == (FRAME_ESP + 32'd4)) &&
                    (bus_byteen == 4'b1111))
                    saw_frame_flags_read = 1'b1;

                if (dut.endi_req && (dut.endi_mask == CM_IRET_MASK) &&
                    saw_decode_iret)
                    saw_cm_iret = 1'b1;

                if (saw_decode_iret && !saw_cm_iret &&
                    ((dbg_eip == RETURN_EIP) ||
                     (dut.u_commit.cs_r == INITIAL_CS) ||
                     (dut.u_commit.eflags_r == INITIAL_FLAGS) ||
                     (dbg_esp == RESET_ESP)))
                    early_iret_visible = 1'b1;

                if (dut.flush_req && (dut.flush_addr == RETURN_EIP))
                    saw_iret_flush = 1'b1;

                if (saw_cm_iret && dbg_endi_pulse) begin
                    timed_out = 1'b0;
                    @(posedge clk);
                    disable wait_roundtrip;
                end
            end
        end

        check("decoded CD imm8 as ENTRY_INT", saw_decode_int);
        check("FETCH_IMM8 service issued", saw_fetch_imm8);
        check("FETCH_IMM8 produced vector 0x21", saw_vector_21);
        check("INT_ENTER service issued", saw_int_enter);
        check("ENDI used CM_INT for interrupt entry", saw_cm_int);
        check("no early INT EIP/CS/FLAGS/ESP visibility before CM_INT",
              !early_int_visible);
        check("committed INT redirect flush to flat handler offset", saw_int_flush);

        check("decoded handler CF as ENTRY_IRET", saw_decode_iret);
        check("IRET_FLOW service issued", saw_iret_flow);
        check("ENDI used CM_IRET for interrupt return", saw_cm_iret);
        check("IRET read IP/CS from INT frame", saw_frame_lo_read);
        check("IRET read FLAGS from INT frame", saw_frame_flags_read);
        check("no early IRET EIP/CS/FLAGS/ESP visibility before CM_IRET",
              !early_iret_visible);
        check("committed IRET redirect flush to post-INT continuation", saw_iret_flush);
        check("INT/IRET round trip completed", !timed_out);

        check("no fault after round trip", !dbg_fault_pending);
        check("final EIP = post-INT continuation", dbg_eip == RETURN_EIP);
        check("final CS = pre-INT CS", dut.u_commit.cs_r == INITIAL_CS);
        check("final FLAGS low 16 restored", dut.u_commit.eflags_r[15:0] == INITIAL_FLAGS[15:0]);
        check("final FLAGS upper 16 preserved as zero", dut.u_commit.eflags_r[31:16] == 16'h0000);
        check("final IF restored", dut.u_commit.eflags_r[9] == INITIAL_FLAGS[9]);
        check("final ESP restored", dbg_esp == RESET_ESP);

        check("frame IP low byte", mem[pa16(FRAME_ESP + 32'd0)] == RETURN_IP[7:0]);
        check("frame IP high byte", mem[pa16(FRAME_ESP + 32'd1)] == RETURN_IP[15:8]);
        check("frame CS low byte", mem[pa16(FRAME_ESP + 32'd2)] == INITIAL_CS[7:0]);
        check("frame CS high byte", mem[pa16(FRAME_ESP + 32'd3)] == INITIAL_CS[15:8]);
        check("frame FLAGS low byte", mem[pa16(FRAME_ESP + 32'd4)] == INITIAL_FLAGS[7:0]);
        check("frame FLAGS high byte", mem[pa16(FRAME_ESP + 32'd5)] == INITIAL_FLAGS[15:8]);

        $display("");
        $display("Rung 5 Pass 5 INT/IRET Round Trip Summary");
        $display("  Failed: %0d", failures);

        if (failures == 0) begin
            $display("RESULT: RUNG 5 PASS 5 INT/IRET ROUND TRIP PASSED");
            $finish;
        end

        $fatal(1, "RESULT: RUNG 5 PASS 5 INT/IRET ROUND TRIP FAILED");
    end

endmodule
