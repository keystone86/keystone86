// Keystone86 / Aegis
// sim/tb/tb_rung5_ud_fault_delivery.sv
// Bounded Rung 5 Pass 4 smoke: unknown opcode -> #UD -> SUB_FAULT_HANDLER.
//
// This is not a full Rung 5 acceptance test. It proves only the accepted
// Pass 4 contract: ENTRY_NULL raises FC_UD, SUB_FAULT_HANDLER maps it to
// vector 0x06, INT_ENTER stages the real-mode frame/target, and
// CM_FAULT_END is the architectural visibility boundary for #UD delivery.

`timescale 1ns/1ps

module tb_rung5_ud_fault_delivery;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 5000;

    localparam logic [31:0] RESET_ESP       = 32'h000FFFF0;
    localparam logic [31:0] FAULT_OPCODE_IP = 32'h0000FFF0;
    localparam logic [31:0] HANDLER_EIP     = 32'h00000040;
    localparam logic [15:0] INITIAL_CS      = 16'h2222;
    localparam logic [15:0] HANDLER_CS      = 16'h3456;
    localparam logic [31:0] INITIAL_FLAGS   = 32'h00000202;

    localparam logic [7:0]  ENTRY_NULL_ID   = 8'h00;
    localparam logic [7:0]  SVC_INT_ENTER   = 8'h62;
    localparam logic [3:0]  FC_UD_CLASS     = 4'h6;
    localparam logic [9:0]  CM_FAULT_MASK   = 10'h040;

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
    logic saw_decode_null;
    logic saw_entry_null_upc;
    logic saw_fc_ud;
    logic saw_sub_fault_handler;
    logic saw_int_enter;
    logic saw_cm_fault_end;
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

        // Program at reset vector: D6 is outside the bounded decode set and
        // must enter ENTRY_NULL. The following byte must not become the #UD
        // return IP; the frame pushes the faulting opcode IP 0xFFF0.
        mem[16'hFFF0] = 8'hD6;
        mem[16'hFFF1] = 8'h90;

        // IVT[0x06] = offset 0x0040, segment 0x3456.
        mem[16'h0018] = HANDLER_EIP[7:0];
        mem[16'h0019] = HANDLER_EIP[15:8];
        mem[16'h001A] = HANDLER_CS[7:0];
        mem[16'h001B] = HANDLER_CS[15:8];
        mem[16'h0040] = 8'h90;

        $display("Keystone86 / Aegis - Rung 5 Pass 4 #UD Delivery Smoke");

        reset_cpu();

        // Initialize in-scope architectural inputs for the #UD frame. This is
        // setup state, not a shortcut around SUB_FAULT_HANDLER or INT_ENTER.
        force dut.u_commit.cs_r = INITIAL_CS;
        force dut.u_commit.eflags_r = INITIAL_FLAGS;
        @(posedge clk);
        release dut.u_commit.cs_r;
        release dut.u_commit.eflags_r;

        saw_decode_null = 1'b0;
        saw_entry_null_upc = 1'b0;
        saw_fc_ud = 1'b0;
        saw_sub_fault_handler = 1'b0;
        saw_int_enter = 1'b0;
        saw_cm_fault_end = 1'b0;
        saw_flush = 1'b0;
        early_visible = 1'b0;
        timed_out = 1'b1;

        begin : wait_ud_delivery
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);

                if (dbg_decode_done && (dbg_dec_entry_id == ENTRY_NULL_ID))
                    saw_decode_null = 1'b1;

                if (dbg_upc == 12'h010)
                    saw_entry_null_upc = 1'b1;

                if (dbg_fault_pending && (dbg_fault_class == FC_UD_CLASS))
                    saw_fc_ud = 1'b1;

                if (dbg_upc == 12'h000)
                    saw_sub_fault_handler = 1'b1;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_INT_ENTER))
                    saw_int_enter = 1'b1;

                if (dut.endi_req && (dut.endi_mask == CM_FAULT_MASK))
                    saw_cm_fault_end = 1'b1;

                if (!saw_cm_fault_end &&
                    ((dbg_eip == HANDLER_EIP) || (dut.u_commit.cs_r == HANDLER_CS)))
                    early_visible = 1'b1;

                if (dut.flush_req && (dut.flush_addr == HANDLER_EIP))
                    saw_flush = 1'b1;

                if (saw_cm_fault_end && dbg_endi_pulse) begin
                    timed_out = 1'b0;
                    @(posedge clk);
                    disable wait_ud_delivery;
                end
            end
        end

        check("decoded unknown opcode as ENTRY_NULL", saw_decode_null);
        check("dispatched ENTRY_NULL", saw_entry_null_upc);
        check("ENTRY_NULL raised FC_UD", saw_fc_ud);
        check("reached SUB_FAULT_HANDLER", saw_sub_fault_handler);
        check("SUB_FAULT_HANDLER issued INT_ENTER", saw_int_enter);
        check("fault delivery ENDI used CM_FAULT_END", saw_cm_fault_end);
        check("no early EIP/CS visibility before CM_FAULT_END", !early_visible);
        check("#UD delivery ENDI completed", !timed_out);
        check("fault state cleared after delivery", !dbg_fault_pending);
        check("committed EIP = IVT[6] offset", dbg_eip == HANDLER_EIP);
        check("committed CS = IVT[6] segment", dut.u_commit.cs_r == HANDLER_CS);
        check("IF cleared in committed FLAGS", dut.u_commit.eflags_r[9] == 1'b0);
        check("ESP decremented by 6", dbg_esp == RESET_ESP - 32'd6);
        check("committed redirect flush to #UD handler", saw_flush);

        check("frame IP low byte is faulting opcode IP",
              mem[16'hFFEA] == FAULT_OPCODE_IP[7:0]);
        check("frame IP high byte is faulting opcode IP",
              mem[16'hFFEB] == FAULT_OPCODE_IP[15:8]);
        check("frame CS low byte", mem[16'hFFEC] == INITIAL_CS[7:0]);
        check("frame CS high byte", mem[16'hFFED] == INITIAL_CS[15:8]);
        check("frame FLAGS low byte", mem[16'hFFEE] == INITIAL_FLAGS[7:0]);
        check("frame FLAGS high byte", mem[16'hFFEF] == INITIAL_FLAGS[15:8]);

        $display("");
        $display("Rung 5 Pass 4 #UD Delivery Summary");
        $display("  Failed: %0d", failures);

        if (failures == 0) begin
            $display("RESULT: RUNG 5 PASS 4 #UD DELIVERY SMOKE PASSED");
            $finish;
        end

        $fatal(1, "RESULT: RUNG 5 PASS 4 #UD DELIVERY SMOKE FAILED");
    end

endmodule
