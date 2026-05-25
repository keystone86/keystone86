// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_imm_reg_mod11.sv
// Bounded Rung 6 Pass 6D-1 smoke: C6/C7 MOV immediate-to-register,
// ModRM.mod=11 only.
//
// Authorized immediate-to-register forms:
//   C6 /0 ib      mod=11 -> MOV r8, imm8
//   C7 /0 id      mod=11 -> MOV r32, imm32
//   66 C7 /0 iw   mod=11 -> MOV r16, imm16
//
// This test intentionally does not exercise C6/C7 non-/0 extensions, memory
// addressing beyond the previously verified direct/base-only/base+disp8/base+disp32
// slices, SIB, base/index/scale, 0x67 address-size behavior, EA_CALC_16,
// 16-bit addressing, protected/page/segment behavior, flags production,
// segment/control/debug/test-register MOV, string MOVS, or Rung 7 behavior.

`timescale 1ns/1ps

module tb_rung6_mov_imm_reg_mod11;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 50000;
    localparam int MAX_OPS         = 40;

    localparam logic [7:0]  ENTRY_NULL_ID       = 8'h00;
    localparam logic [7:0]  ENTRY_PREFIX_ID     = 8'h12;
    localparam logic [7:0]  ENTRY_MOV_ID        = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM8      = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM16     = 8'h02;
    localparam logic [7:0]  SVC_FETCH_IMM32     = 8'h03;
    localparam logic [7:0]  SVC_EA_CALC_32      = 8'h11;
    localparam logic [7:0]  SVC_LOAD_RM8        = 8'h20;
    localparam logic [7:0]  SVC_LOAD_RM16       = 8'h21;
    localparam logic [7:0]  SVC_LOAD_RM32       = 8'h22;
    localparam logic [7:0]  SVC_STORE_RM8       = 8'h23;
    localparam logic [7:0]  SVC_STORE_RM16      = 8'h24;
    localparam logic [7:0]  SVC_STORE_RM32      = 8'h25;
    localparam logic [7:0]  SVC_LOAD_REG_META   = 8'h26;
    localparam logic [7:0]  SVC_STORE_REG_META  = 8'h27;
    localparam logic [9:0]  CM_MOV_REG_MASK     = 10'h1C1;
    localparam logic [9:0]  CM_NOP_EIP_MASK     = 10'h1C2;
    localparam logic [31:0] RESET_EIP           = 32'hFFFFFFF0;

    localparam int OP_IMM32 = 0;
    localparam int OP_IMM8  = 1;
    localparam int OP_IMM16 = 2;

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
    logic [31:0] op_imm  [0:MAX_OPS-1];
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int setup_route_count;
    int c6_route_count;
    int c7_route_count;
    int c7w_route_count;
    int fetch_imm8_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int stage_gpr_count;
    int ea_calc32_count;
    int load_rm_count;
    int store_rm_count;
    int load_reg_meta_count;
    int store_reg_meta_count;
    int bus_wr_count;
    int cm_mov_reg_count;
    logic saw_cm_nop_eip;
    logic early_gpr_visible;
    logic timed_out;
    logic endi_req_d;

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

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending, dbg_fault_class);
            failures++;
        end
    endtask

    function automatic logic [31:0] seed32(input int idx);
        return 32'h11223344 ^ ({24'h0, idx[7:0]} * 32'h01040911);
    endfunction

    function automatic logic [31:0] merge_byte(
        input logic [31:0] old_val,
        input logic [2:0]  raw_idx,
        input logic [7:0]  imm
    );
        logic [31:0] tmp;
        begin
            tmp = old_val;
            if (raw_idx[2])
                tmp[15:8] = imm;
            else
                tmp[7:0] = imm;
            return tmp;
        end
    endfunction

    function automatic logic [31:0] merge_word(
        input logic [31:0] old_val,
        input logic [15:0] imm
    );
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

    task automatic record_op(input int kind, input logic [2:0] dst,
                             input logic [31:0] imm);
        begin
            op_kind[op_count] = kind;
            op_dst[op_count]  = dst;
            op_imm[op_count]  = imm;
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
            record_op(OP_IMM32, dst, imm);
            program_pc += 32'd5;
        end
    endtask

    task automatic append_c6_reg_imm8(input logic [2:0] dst, input logic [7:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hC6;
            mem[pa16(program_pc + 32'd1)] = {2'b11, 3'b000, dst};
            mem[pa16(program_pc + 32'd2)] = imm;
            record_op(OP_IMM8, dst, {24'h0, imm});
            program_pc += 32'd3;
        end
    endtask

    task automatic append_c7_reg_imm32(input logic [2:0] dst, input logic [31:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hC7;
            mem[pa16(program_pc + 32'd1)] = {2'b11, 3'b000, dst};
            mem[pa16(program_pc + 32'd2)] = imm[7:0];
            mem[pa16(program_pc + 32'd3)] = imm[15:8];
            mem[pa16(program_pc + 32'd4)] = imm[23:16];
            mem[pa16(program_pc + 32'd5)] = imm[31:24];
            record_op(OP_IMM32, dst, imm);
            program_pc += 32'd6;
        end
    endtask

    task automatic append_66_c7_reg_imm16(input logic [2:0] dst, input logic [15:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'hC7;
            mem[pa16(program_pc + 32'd2)] = {2'b11, 3'b000, dst};
            mem[pa16(program_pc + 32'd3)] = imm[7:0];
            mem[pa16(program_pc + 32'd4)] = imm[15:8];
            record_op(OP_IMM16, dst, {16'h0, imm});
            program_pc += 32'd5;
        end
    endtask

    task automatic apply_expected(input int idx);
        begin
            unique case (op_kind[idx])
                OP_IMM32: committed_gpr[op_dst[idx]] = op_imm[idx];
                OP_IMM8:  committed_gpr[{1'b0, op_dst[idx][1:0]}] =
                    merge_byte(committed_gpr[{1'b0, op_dst[idx][1:0]}],
                               op_dst[idx], op_imm[idx][7:0]);
                OP_IMM16: committed_gpr[op_dst[idx]] =
                    merge_word(committed_gpr[op_dst[idx]], op_imm[idx][15:0]);
                default: ;
            endcase
        end
    endtask

    task automatic run_unsupported_form(
        input int len,
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic [7:0] b4,
        input logic [7:0] b5,
        input logic [7:0] b6,
        input logic [7:0] b7,
        input logic [7:0] b8,
        input logic [7:0] b9,
        input string name,
        input logic expect_prefix_only
    );
        logic saw_expected_dispatch;
        logic saw_mov_endi;
        logic saw_bus_wr;
        begin
            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = b0;
            if (len > 1) mem[pa16(RESET_EIP + 32'd1)] = b1;
            if (len > 2) mem[pa16(RESET_EIP + 32'd2)] = b2;
            if (len > 3) mem[pa16(RESET_EIP + 32'd3)] = b3;
            if (len > 4) mem[pa16(RESET_EIP + 32'd4)] = b4;
            if (len > 5) mem[pa16(RESET_EIP + 32'd5)] = b5;
            if (len > 6) mem[pa16(RESET_EIP + 32'd6)] = b6;
            if (len > 7) mem[pa16(RESET_EIP + 32'd7)] = b7;
            if (len > 8) mem[pa16(RESET_EIP + 32'd8)] = b8;
            if (len > 9) mem[pa16(RESET_EIP + 32'd9)] = b9;

            saw_expected_dispatch = 1'b0;
            saw_mov_endi = 1'b0;
            saw_bus_wr = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 800; c++) begin
                    @(posedge clk);
                    #1;
                    if (bus_wr)
                        saw_bus_wr = 1'b1;
                    if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID))
                        saw_mov_endi = 1'b1;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch ==
                         (expect_prefix_only ? ENTRY_PREFIX_ID : ENTRY_NULL_ID))) begin
                        saw_expected_dispatch = 1'b1;
                        disable wait_unsupported;
                    end
                end
            end

            check({name, expect_prefix_only ? " routes as prefix-only" :
                  " routes to ENTRY_NULL"}, saw_expected_dispatch);
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

        for (int r = 0; r < 8; r++)
            append_c6_reg_imm8(r[2:0], 8'h40 ^ (8'h13 * r[7:0]));

        for (int r = 0; r < 8; r++)
            append_c7_reg_imm32(r[2:0],
                                 32'hA5B60000 ^ ({24'h0, r[7:0]} * 32'h00011131));

        for (int r = 0; r < 8; r++)
            append_66_c7_reg_imm16(r[2:0], 16'h7000 ^ (16'h0127 * r[15:0]));

        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6D-1 MOV imm-to-reg ModRM.mod=11 Smoke");

        mov_endi_count = 0;
        setup_route_count = 0;
        c6_route_count = 0;
        c7_route_count = 0;
        c7w_route_count = 0;
        fetch_imm8_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        stage_gpr_count = 0;
        ea_calc32_count = 0;
        load_rm_count = 0;
        store_rm_count = 0;
        load_reg_meta_count = 0;
        store_reg_meta_count = 0;
        bus_wr_count = 0;
        cm_mov_reg_count = 0;
        saw_cm_nop_eip = 1'b0;
        early_gpr_visible = 1'b0;
        timed_out = 1'b1;
        endi_req_d = 1'b0;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (bus_wr)
                    bus_wr_count++;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID)) begin
                    if (!dut.u_dec.prefix66_active && (dut.u_dec.opcode_byte_latch[7:3] == 5'b10111))
                        setup_route_count++;
                    if (!dut.u_dec.prefix66_active && (dut.u_dec.opcode_byte_latch == 8'hC6))
                        c6_route_count++;
                    if (!dut.u_dec.prefix66_active && (dut.u_dec.opcode_byte_latch == 8'hC7))
                        c7_route_count++;
                    if (dut.u_dec.prefix66_active && (dut.u_dec.opcode_byte_latch == 8'hC7))
                        c7w_route_count++;
                end

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM8))
                    fetch_imm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM16))
                    fetch_imm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_EA_CALC_32))
                    ea_calc32_count++;
                if (dut.svc_req_out &&
                    ((dut.svc_id_out == SVC_LOAD_RM8) ||
                     (dut.svc_id_out == SVC_LOAD_RM16) ||
                     (dut.svc_id_out == SVC_LOAD_RM32)))
                    load_rm_count++;
                if (dut.svc_req_out &&
                    ((dut.svc_id_out == SVC_STORE_RM8) ||
                     (dut.svc_id_out == SVC_STORE_RM16) ||
                     (dut.svc_id_out == SVC_STORE_RM32)))
                    store_rm_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_REG_META))
                    load_reg_meta_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_REG_META))
                    store_reg_meta_count++;

                if (dut.pc_gpr_en)
                    stage_gpr_count++;
                if (dut.endi_req && !endi_req_d && (dut.endi_mask == CM_MOV_REG_MASK))
                    cm_mov_reg_count++;
                if (dut.endi_req && !endi_req_d && (dut.endi_mask == CM_NOP_EIP_MASK))
                    saw_cm_nop_eip = 1'b1;
                endi_req_d = dut.endi_req;

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

        check("eight setup MOVs plus 24 C6/C7 immediate-to-register MOVs completed",
              !timed_out && (mov_endi_count == op_count) && (op_count == 32));
        check("setup B8-BF MOVs still route to ENTRY_MOV", setup_route_count == 8);
        check("C6 /0 ib ModRM.mod=11 routes to ENTRY_MOV for all r8 destinations",
              c6_route_count == 8);
        check("C7 /0 id ModRM.mod=11 routes to ENTRY_MOV for all r32 destinations",
              c7_route_count == 8);
        check("66+C7 /0 iw ModRM.mod=11 routes to ENTRY_MOV for all r16 destinations",
              c7w_route_count == 8);
        check("FETCH_IMM8 issued for all C6 register destinations", fetch_imm8_count == 8);
        check("FETCH_IMM16 issued for all 66+C7 register destinations", fetch_imm16_count == 8);
        check("FETCH_IMM32 issued for setup and C7 register destinations",
              fetch_imm32_count == 16);
        check("STAGE_GPR issued once per register immediate MOV", stage_gpr_count == 32);
        check("ENDI CM_MOV_REG issued once per register immediate MOV", cm_mov_reg_count == 32);
        check("no ENDI CM_NOP|CM_EIP used by immediate-to-register MOV", !saw_cm_nop_eip);
        check("no EA_CALC_32 issued for register-destination C6/C7", ea_calc32_count == 0);
        check("no LOAD_RM* issued for register-destination C6/C7", load_rm_count == 0);
        check("no STORE_RM* issued for register-destination C6/C7", store_rm_count == 0);
        check("no LOAD_REG_META issued for immediate-to-register MOV", load_reg_meta_count == 0);
        check("no STORE_REG_META issued for immediate-to-register MOV", store_reg_meta_count == 0);
        check("no bus writes for register-destination immediate MOV sequence", bus_wr_count == 0);
        check("no early GPR visibility before CM_MOV_REG", !early_gpr_visible);
        check("no fault after Pass 6D-1 MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6D-1 MOV sequence", dbg_eip == program_end_eip);
        check("final GPR state matches byte/dword/word shadow", gprs_match_shadow());

        run_unsupported_form(3, 8'hC6, 8'hC8, 8'h12, 8'h00, 8'h00, 8'h00,
                             8'h00, 8'h00, 8'h00, 8'h00,
                             "C6 non-/0 ModRM.mod=11", 1'b0);
        run_unsupported_form(6, 8'hC7, 8'hC8, 8'h78, 8'h56, 8'h34, 8'h12,
                             8'h00, 8'h00, 8'h00, 8'h00,
                             "C7 non-/0 ModRM.mod=11", 1'b0);
        run_unsupported_form(8, 8'hC6, 8'h84, 8'h25, 8'h00, 8'h50, 8'h00,
                             8'h00, 8'h12, 8'h00, 8'h00,
                             "C6 SIB mod=10 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'hC7, 8'h84, 8'h25, 8'h00, 8'h51, 8'h00,
                             8'h00, 8'h78, 8'h56, 8'h34,
                             "C7 SIB mod=10 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'hC7, 8'h04, 8'h25, 8'h00, 8'h51, 8'h00,
                             8'h00, 8'h78, 8'h56, 8'h34,
                             "C7 SIB immediate-to-memory", 1'b0);
        run_unsupported_form(4, 8'h66, 8'hC6, 8'hC0, 8'h12, 8'h00, 8'h00,
                             8'h00, 8'h00, 8'h00, 8'h00,
                             "66+C6 ModRM.mod=11", 1'b0);
        run_unsupported_form(7, 8'h67, 8'hC7, 8'hC0, 8'h78, 8'h56, 8'h34,
                             8'h12, 8'h00, 8'h00, 8'h00,
                             "67-prefixed C7 ModRM.mod=11", 1'b1);

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6D-1 MOV imm-to-reg ModRM.mod=11 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6D-1 MOV imm-to-reg ModRM.mod=11 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6D-1 MOV imm-to-reg ModRM.mod=11 smoke failed");
        end

        $finish;
    end

endmodule
