// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_imm16.sv
// Bounded Rung 6 Pass 4B smoke: 66+B8-BF MOV r16, imm16 only.
//
// This test proves the authorized operand-size override slice only: decoder
// latches one 0x66 prefix for B8-BF, FETCH_IMM16 supplies T4, and ENDI
// CM_MOV_REG merges only the low word into the destination GPR.

`timescale 1ns/1ps

module tb_rung6_mov_imm16;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 16000;

    localparam logic [7:0]  ENTRY_NULL_ID   = 8'h00;
    localparam logic [7:0]  ENTRY_MOV_ID    = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM16 = 8'h02;
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

    logic [7:0]  mem [0:65535];
    logic        bus_pending;
    logic        bus_wr_pending;
    logic [31:0] bus_addr_pending;
    logic [31:0] committed_gpr [0:7];
    logic [31:0] seed_gpr [0:7];
    logic [15:0] imm16_values [0:7];

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready        <= 1'b0;
            bus_din          <= 32'h0;
            bus_pending      <= 1'b0;
            bus_wr_pending   <= 1'b0;
            bus_addr_pending <= 32'h0;
        end else begin
            bus_ready <= 1'b0;

            if ((bus_rd || bus_wr) && !bus_pending) begin
                bus_pending      <= 1'b1;
                bus_wr_pending   <= bus_wr;
                bus_addr_pending <= bus_addr;
            end

            if (bus_pending) begin
                if (bus_wr_pending)
                    bus_din <= 32'h0;
                else
                    bus_din <= {24'h0, mem[pa16(bus_addr_pending)]};

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

    task automatic clear_memory;
        for (int i = 0; i < 65536; i++)
            mem[i] = 8'h90;
    endtask

    task automatic write_mov32(input logic [31:0] addr, input logic [2:0] reg_idx,
                               input logic [31:0] imm);
        begin
            mem[pa16(addr + 32'd0)] = 8'hB8 | {5'h0, reg_idx};
            mem[pa16(addr + 32'd1)] = imm[7:0];
            mem[pa16(addr + 32'd2)] = imm[15:8];
            mem[pa16(addr + 32'd3)] = imm[23:16];
            mem[pa16(addr + 32'd4)] = imm[31:24];
        end
    endtask

    task automatic write_mov16(input logic [31:0] addr, input logic [2:0] reg_idx,
                               input logic [15:0] imm);
        begin
            mem[pa16(addr + 32'd0)] = 8'h66;
            mem[pa16(addr + 32'd1)] = 8'hB8 | {5'h0, reg_idx};
            mem[pa16(addr + 32'd2)] = imm[7:0];
            mem[pa16(addr + 32'd3)] = imm[15:8];
        end
    endtask

    function automatic logic [31:0] merge_word(input logic [31:0] old_val,
                                               input logic [15:0] imm);
        logic [31:0] tmp;
        begin
            tmp = old_val;
            tmp[15:0] = imm;
            return tmp;
        end
    endfunction

    function automatic logic gprs_match_shadow;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== committed_gpr[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    int failures;
    int cycles;
    int mov_endi_count;
    int mov16_route_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int bus_wr_count;
    logic saw_cm_mov_reg;
    logic early_gpr_visible;
    logic timed_out;
    logic [7:0] saw_mov16_opcode;

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending, dbg_fault_class);
            failures++;
        end
    endtask

    task automatic apply_expected(input int idx);
        if (idx < 8)
            committed_gpr[idx] = seed_gpr[idx];
        else
            committed_gpr[idx - 8] = merge_word(committed_gpr[idx - 8],
                                                imm16_values[idx - 8]);
    endtask

    task automatic run_unsupported_prefix(input logic [7:0] opcode,
                                          input logic [7:0] modrm,
                                          input bit has_modrm,
                                          input string name);
        logic saw_entry_null;
        logic saw_mov_endi;
        logic saw_bus_wr;
        begin
            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = 8'h66;
            mem[pa16(RESET_EIP + 32'd1)] = opcode;
            if (has_modrm)
                mem[pa16(RESET_EIP + 32'd2)] = modrm;
            saw_entry_null = 1'b0;
            saw_mov_endi   = 1'b0;
            saw_bus_wr     = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 500; c++) begin
                    @(posedge clk);
                    #1;
                    if (bus_wr)
                        saw_bus_wr = 1'b1;
                    if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID))
                        saw_mov_endi = 1'b1;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch == ENTRY_NULL_ID)) begin
                        saw_entry_null = 1'b1;
                        disable wait_unsupported;
                    end
                end
            end

            check({name, " routes to ENTRY_NULL"}, saw_entry_null);
            check({name, " does not ENDI as MOV"}, !saw_mov_endi);
            check({name, " issues no bus write before unsupported dispatch"}, !saw_bus_wr);
        end
    endtask

    initial begin
        failures = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;
        bus_wr_pending = 1'b0;
        bus_addr_pending = 32'h0;

        clear_memory();

        for (int i = 0; i < 8; i++)
            committed_gpr[i] = 32'h0;

        seed_gpr[0] = 32'h11223344;
        seed_gpr[1] = 32'h55667788;
        seed_gpr[2] = 32'h99AABBCC;
        seed_gpr[3] = 32'hDDEEFF00;
        seed_gpr[4] = 32'h01020304;
        seed_gpr[5] = 32'hA5A55A5A;
        seed_gpr[6] = 32'hCAFEBABE;
        seed_gpr[7] = 32'h0BADF00D;

        imm16_values[0] = 16'hA001;
        imm16_values[1] = 16'hB112;
        imm16_values[2] = 16'hC223;
        imm16_values[3] = 16'hD334;
        imm16_values[4] = 16'hE445;
        imm16_values[5] = 16'hF556;
        imm16_values[6] = 16'h0667;
        imm16_values[7] = 16'h1778;

        for (int r = 0; r < 8; r++)
            write_mov32(RESET_EIP + (32'd5 * r), r[2:0], seed_gpr[r]);

        for (int r = 0; r < 8; r++)
            write_mov16(RESET_EIP + 32'd40 + (32'd4 * r), r[2:0], imm16_values[r]);

        $display("Keystone86 / Aegis - Rung 6 Pass 4B MOV r16, imm16 Smoke");

        mov_endi_count = 0;
        mov16_route_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        bus_wr_count = 0;
        saw_cm_mov_reg = 1'b0;
        early_gpr_visible = 1'b0;
        timed_out = 1'b1;
        saw_mov16_opcode = 8'h00;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (bus_wr)
                    bus_wr_count++;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID) &&
                    dut.u_dec.prefix66_active &&
                    (dut.u_dec.opcode_byte_latch[7:3] == 5'b10111)) begin
                    mov16_route_count++;
                    saw_mov16_opcode[dut.u_dec.opcode_byte_latch[2:0]] = 1'b1;
                end

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM16))
                    fetch_imm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;

                if (dut.endi_req && (dut.endi_mask == CM_MOV_REG_MASK))
                    saw_cm_mov_reg = 1'b1;

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    apply_expected(mov_endi_count);
                    mov_endi_count++;
                    if (mov_endi_count == 16) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_movs;
                    end
                end else if (!gprs_match_shadow()) begin
                    early_gpr_visible = 1'b1;
                end
            end
        end

        check("all eight 66+B8-BF opcodes routed to ENTRY_MOV",
              (mov16_route_count == 8) && (saw_mov16_opcode == 8'hFF));
        check("FETCH_IMM16 service issued for each MOV r16, imm16", fetch_imm16_count == 8);
        check("FETCH_IMM32 preserved for setup MOVs", fetch_imm32_count == 8);
        check("ENDI used CM_MOV_REG", saw_cm_mov_reg);
        check("sixteen MOV instructions completed", !timed_out && (mov_endi_count == 16));
        check("no bus writes for register-immediate MOV sequence", bus_wr_count == 0);
        check("no early GPR visibility before CM_MOV_REG", !early_gpr_visible);
        check("no fault after MOV r16, imm16 sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 4B MOV sequence",
              dbg_eip == (RESET_EIP + 32'd72));
        check("final GPR state preserves high words and merges low words", gprs_match_shadow());

        run_unsupported_prefix(8'h90, 8'h00, 1'b0, "66+90");
        run_unsupported_prefix(8'h88, 8'hC0, 1'b1, "66+88 mod=11");

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 4B MOV r16, imm16 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 4B MOV r16, imm16 smoke had %0d failure(s)", failures);
            $fatal(1, "Rung 6 Pass 4B MOV r16, imm16 smoke failed");
        end

        $finish;
    end

endmodule
