// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_reg_reg.sv
// Bounded Rung 6 Pass 5A smoke: 88/89/8A/8B MOV register-register only.
//
// This test intentionally exercises only ModRM.mod=11 forms. Non-register
// ModRM forms are checked for ENTRY_NULL routing so memory MOV remains
// unimplemented in this pass.

`timescale 1ns/1ps

module tb_rung6_mov_reg_reg;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 80000;
    localparam int MAX_OPS         = 300;

    localparam logic [7:0]  ENTRY_NULL_ID       = 8'h00;
    localparam logic [7:0]  ENTRY_MOV_ID        = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM32     = 8'h03;
    localparam logic [7:0]  SVC_LOAD_REG_META   = 8'h26;
    localparam logic [7:0]  SVC_STORE_REG_META  = 8'h27;
    localparam logic [9:0]  CM_MOV_REG_MASK     = 10'h1C1;
    localparam logic [31:0] RESET_EIP           = 32'hFFFFFFF0;

    localparam int OP_IMM32 = 0;
    localparam int OP_REG32 = 1;
    localparam int OP_REG8  = 2;

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

    logic [31:0] program_pc;
    int          op_count;
    int          op_kind [0:MAX_OPS-1];
    logic [2:0]  op_dst  [0:MAX_OPS-1];
    logic [2:0]  op_src  [0:MAX_OPS-1];
    logic [31:0] op_imm  [0:MAX_OPS-1];
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int mov_route_count;
    int fetch_imm32_count;
    int load_reg_meta_count;
    int store_reg_meta_count;
    int bus_wr_count;
    int opcode88_count, opcode89_count, opcode8a_count, opcode8b_count;
    logic saw_cm_mov_reg;
    logic early_gpr_visible;
    logic timed_out;

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

    function automatic logic [31:0] seed32(input int idx);
        return 32'h10203040 ^ ({24'h0, idx[7:0]} * 32'h01040911);
    endfunction

    function automatic logic [31:0] merge_byte(
        input logic [31:0] old_val,
        input logic [2:0]  raw_idx,
        input logic [7:0]  data
    );
        logic [31:0] tmp;
        begin
            tmp = old_val;
            if (raw_idx[2])
                tmp[15:8] = data;
            else
                tmp[7:0] = data;
            return tmp;
        end
    endfunction

    function automatic logic [7:0] read_byte(input logic [2:0] raw_idx);
        if (raw_idx[2])
            return committed_gpr[{1'b0, raw_idx[1:0]}][15:8];
        return committed_gpr[{1'b0, raw_idx[1:0]}][7:0];
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

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending, dbg_fault_class);
            failures++;
        end
    endtask

    task automatic clear_memory;
        for (int i = 0; i < 65536; i++)
            mem[i] = 8'h90;
    endtask

    task automatic record_imm32(input logic [2:0] dst, input logic [31:0] imm);
        begin
            op_kind[op_count] = OP_IMM32;
            op_dst[op_count]  = dst;
            op_src[op_count]  = 3'h0;
            op_imm[op_count]  = imm;
            op_count++;
        end
    endtask

    task automatic record_reg(input int kind, input logic [2:0] dst, input logic [2:0] src);
        begin
            op_kind[op_count] = kind;
            op_dst[op_count]  = dst;
            op_src[op_count]  = src;
            op_imm[op_count]  = 32'h0;
            op_count++;
        end
    endtask

    task automatic append_mov32_imm(input logic [2:0] dst, input logic [31:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hB8 | {5'h0, dst};
            mem[pa16(program_pc + 32'd1)] = imm[7:0];
            mem[pa16(program_pc + 32'd2)] = imm[15:8];
            mem[pa16(program_pc + 32'd3)] = imm[23:16];
            mem[pa16(program_pc + 32'd4)] = imm[31:24];
            record_imm32(dst, imm);
            program_pc += 32'd5;
        end
    endtask

    task automatic append_mov_reg(input logic [7:0] opcode, input logic [2:0] dst,
                                  input logic [2:0] src);
        begin
            mem[pa16(program_pc + 32'd0)] = opcode;
            case (opcode)
                8'h88,
                8'h89: mem[pa16(program_pc + 32'd1)] = {2'b11, src, dst};
                default: mem[pa16(program_pc + 32'd1)] = {2'b11, dst, src};
            endcase

            if (opcode[0])
                record_reg(OP_REG32, dst, src);
            else
                record_reg(OP_REG8, dst, src);

            program_pc += 32'd2;
        end
    endtask

    task automatic apply_expected(input int idx);
        logic [7:0] byte_val;
        begin
            case (op_kind[idx])
                OP_IMM32: committed_gpr[op_dst[idx]] = op_imm[idx];
                OP_REG32: committed_gpr[op_dst[idx]] = committed_gpr[op_src[idx]];
                OP_REG8: begin
                    byte_val = read_byte(op_src[idx]);
                    committed_gpr[{1'b0, op_dst[idx][1:0]}] =
                        merge_byte(committed_gpr[{1'b0, op_dst[idx][1:0]}],
                                   op_dst[idx], byte_val);
                end
                default: ;
            endcase
        end
    endtask

    task automatic run_unsupported_form(input logic [7:0] opcode,
                                        input logic [7:0] modrm,
                                        input string name);
        logic saw_entry_null;
        logic saw_mov_endi;
        logic saw_bus_wr;
        begin
            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = opcode;
            mem[pa16(RESET_EIP + 32'd1)] = modrm;
            saw_entry_null = 1'b0;
            saw_mov_endi   = 1'b0;
            saw_bus_wr     = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 300; c++) begin
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

        program_pc = RESET_EIP;
        op_count = 0;

        for (int r = 0; r < 8; r++)
            append_mov32_imm(r[2:0], seed32(r));

        for (int dst = 0; dst < 8; dst++) begin
            for (int src = 0; src < 8; src++)
                append_mov_reg(8'h89, dst[2:0], src[2:0]);
        end

        for (int dst = 0; dst < 8; dst++) begin
            for (int src = 0; src < 8; src++)
                append_mov_reg(8'h8B, dst[2:0], src[2:0]);
        end

        for (int dst = 0; dst < 8; dst++) begin
            for (int src = 0; src < 8; src++)
                append_mov_reg(8'h88, dst[2:0], src[2:0]);
        end

        for (int dst = 0; dst < 8; dst++) begin
            for (int src = 0; src < 8; src++)
                append_mov_reg(8'h8A, dst[2:0], src[2:0]);
        end

        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 5A MOV register-register Smoke");

        mov_endi_count = 0;
        mov_route_count = 0;
        fetch_imm32_count = 0;
        load_reg_meta_count = 0;
        store_reg_meta_count = 0;
        bus_wr_count = 0;
        opcode88_count = 0;
        opcode89_count = 0;
        opcode8a_count = 0;
        opcode8b_count = 0;
        saw_cm_mov_reg = 1'b0;
        early_gpr_visible = 1'b0;
        timed_out = 1'b1;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (bus_wr)
                    bus_wr_count++;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID)) begin
                    mov_route_count++;
                    case (dut.u_dec.opcode_byte_latch)
                        8'h88: opcode88_count++;
                        8'h89: opcode89_count++;
                        8'h8A: opcode8a_count++;
                        8'h8B: opcode8b_count++;
                        default: ;
                    endcase
                end

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_REG_META)) begin
                    load_reg_meta_count++;
                end
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_REG_META))
                    store_reg_meta_count++;

                if (dut.endi_req && (dut.endi_mask == CM_MOV_REG_MASK))
                    saw_cm_mov_reg = 1'b1;

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    apply_expected(mov_endi_count);
                    mov_endi_count++;
                    if (mov_endi_count == op_count) begin
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

        check("eight B8-BF setup MOVs plus 256 register-register MOVs completed",
              !timed_out && (mov_endi_count == op_count) && (op_count == 264));
        check("all 88 register-register forms routed", opcode88_count == 64);
        check("all 89 register-register forms routed", opcode89_count == 64);
        check("all 8A register-register forms routed", opcode8a_count == 64);
        check("all 8B register-register forms routed", opcode8b_count == 64);
        check("FETCH_IMM32 preserved for setup MOVs", fetch_imm32_count == 8);
        check("LOAD_REG_META issued once per register-register MOV", load_reg_meta_count == 256);
        check("STORE_REG_META issued once per register-register MOV", store_reg_meta_count == 256);
        check("ENDI used CM_MOV_REG", saw_cm_mov_reg);
        check("no bus writes for register-only MOV sequence", bus_wr_count == 0);
        check("no early GPR visibility before CM_MOV_REG", !early_gpr_visible);
        check("no fault after register-only MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 5A MOV sequence", dbg_eip == program_end_eip);
        check("final GPR state matches shadow", gprs_match_shadow());
        if (!gprs_match_shadow()) begin
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== committed_gpr[i])
                    $display("    GPR[%0d] actual=%08X expected=%08X",
                             i, dut.u_commit.gpr_r[i], committed_gpr[i]);
            end
        end

        run_unsupported_form(8'h88, 8'h00, "88 mod=00");
        run_unsupported_form(8'h89, 8'h45, "89 mod=01");
        run_unsupported_form(8'h8A, 8'h85, "8A mod=10");
        run_unsupported_form(8'h8B, 8'h04, "8B SIB memory");

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 5A MOV register-register smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 5A MOV register-register smoke had %0d failure(s)", failures);
            $fatal(1, "Rung 6 Pass 5A MOV register-register smoke failed");
        end

        $finish;
    end

endmodule
