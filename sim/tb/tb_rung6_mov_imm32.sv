// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_imm32.sv
// Bounded Rung 6 Pass 2 first-slice smoke: B8+rd id, MOV r32, imm32 only.
//
// This is not full Rung 6 acceptance. It proves the authorized first slice:
// decoder routes B8-BF to ENTRY_MOV, FETCH_IMM32 supplies the immediate, and
// ENDI CM_MOV_REG is the only architectural GPR publication boundary.

`timescale 1ns/1ps

module tb_rung6_mov_imm32;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 8000;

    localparam logic [7:0]  ENTRY_MOV_ID    = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM32 = 8'h03;
    localparam logic [9:0]  CM_MOV_REG_MASK = 10'h1C1;
    localparam logic [31:0] RESET_EIP       = 32'hFFFFFFF0;

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

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready       <= 1'b0;
            bus_din         <= 32'h0;
            bus_pending     <= 1'b0;
            bus_wr_pending  <= 1'b0;
            bus_addr_pending <= 32'h0;
        end else begin
            bus_ready <= 1'b0;

            if ((bus_rd || bus_wr) && !bus_pending) begin
                bus_pending      <= 1'b1;
                bus_wr_pending   <= bus_wr;
                bus_addr_pending <= bus_addr;
            end

            if (bus_pending) begin
                if (bus_wr_pending) begin
                    bus_din <= 32'h0;
                end else begin
                    bus_din <= {24'h0, mem[pa16(bus_addr_pending)]};
                end

                bus_ready   <= 1'b1;
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
    endtask

    task automatic write_mov32(
        input logic [31:0] addr,
        input logic [2:0]  reg_idx,
        input logic [31:0] imm
    );
        begin
            mem[pa16(addr + 32'd0)] = 8'hB8 | {5'h0, reg_idx};
            mem[pa16(addr + 32'd1)] = imm[7:0];
            mem[pa16(addr + 32'd2)] = imm[15:8];
            mem[pa16(addr + 32'd3)] = imm[23:16];
            mem[pa16(addr + 32'd4)] = imm[31:24];
        end
    endtask

    int failures;
    int cycles;
    int mov_route_count;
    int mov_endi_count;
    int fetch_imm32_count;
    int bus_wr_count;
    logic saw_cm_mov_reg;
    logic early_gpr_visible;
    logic timed_out;
    logic [7:0] saw_mov_opcode;
    logic [31:0] expected_gpr [0:7];

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending, dbg_fault_class);
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

        expected_gpr[0] = 32'h11223344;
        expected_gpr[1] = 32'h55667788;
        expected_gpr[2] = 32'h99AABBCC;
        expected_gpr[3] = 32'hDDEEFF00;
        expected_gpr[4] = 32'h01020304;
        expected_gpr[5] = 32'hA5A55A5A;
        expected_gpr[6] = 32'hCAFEBABE;
        expected_gpr[7] = 32'h0BADF00D;

        for (int r = 0; r < 8; r++)
            write_mov32(RESET_EIP + (32'd5 * r), r[2:0], expected_gpr[r]);

        $display("Keystone86 / Aegis - Rung 6 Pass 2 MOV r32, imm32 Smoke");

        mov_route_count = 0;
        mov_endi_count = 0;
        fetch_imm32_count = 0;
        bus_wr_count = 0;
        saw_cm_mov_reg = 1'b0;
        early_gpr_visible = 1'b0;
        timed_out = 1'b1;
        saw_mov_opcode = 8'h00;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (bus_wr)
                    bus_wr_count++;

                // The public decode debug pulse can be missed while the
                // microsequencer is back-pressuring decode. This samples the
                // bounded decoder-to-dispatch handoff instead: the decoder
                // still holds the B8-BF opcode while ENTRY_MOV is being queued.
                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID) &&
                    (dut.u_dec.opcode_byte_latch[7:3] == 5'b10111)) begin
                    mov_route_count++;
                    saw_mov_opcode[dut.u_dec.opcode_byte_latch[2:0]] = 1'b1;
                end

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;

                if (dut.endi_req && (dut.endi_mask == CM_MOV_REG_MASK))
                    saw_cm_mov_reg = 1'b1;

                if (!saw_cm_mov_reg && (dut.u_commit.gpr_r[0] != 32'h0))
                    early_gpr_visible = 1'b1;

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    mov_endi_count++;
                    if (mov_endi_count == 8) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_movs;
                    end
                end
            end
        end

        check("all eight B8-BF opcodes routed to ENTRY_MOV",
              (mov_route_count == 8) && (saw_mov_opcode == 8'hFF));
        check("FETCH_IMM32 service issued for each MOV", fetch_imm32_count == 8);
        check("ENDI used CM_MOV_REG", saw_cm_mov_reg);
        check("eight MOV instructions completed", !timed_out && (mov_endi_count == 8));
        check("no bus writes for register-immediate MOV", bus_wr_count == 0);
        check("no early GPR visibility before first CM_MOV_REG", !early_gpr_visible);
        check("no fault after MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after eight MOV r32, imm32 instructions",
              dbg_eip == (RESET_EIP + 32'd40));

        for (int r = 0; r < 8; r++)
            check($sformatf("GPR[%0d] receives MOV immediate", r),
                  dut.u_commit.gpr_r[r] == expected_gpr[r]);

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 2 MOV r32, imm32 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 2 MOV r32, imm32 smoke had %0d failure(s)", failures);
            $fatal(1, "Rung 6 Pass 2 MOV r32, imm32 smoke failed");
        end

        $finish;
    end

endmodule
