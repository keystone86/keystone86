// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_sib_index_base.sv
// Bounded Rung 6 Pass 6G-1 smoke: default-32 base-present indexed SIB MOV.
//
// Authorized addressing subset:
//   ModRM.r/m=100, SIB.index!=100
//   mod=00 base!=101, no displacement
//   mod=01 any base plus signed disp8, including base=101 as EBP
//   mod=10 any base plus disp32, including base=101 as EBP
//   EA = committed base + (committed index << scale) + optional displacement
//
// No-base indexed SIB, 0x67, EA_CALC_16, 16-bit addressing,
// protected/page/segment behavior, flags production, segment/control/debug/
// test-register MOV, string MOVS, and Rung 7 behavior remain unsupported.

`timescale 1ns/1ps

module tb_rung6_mov_sib_index_base;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 260000;

    localparam logic [7:0]  ENTRY_NULL_ID      = 8'h00;
    localparam logic [7:0]  ENTRY_PREFIX_ID    = 8'h12;
    localparam logic [7:0]  ENTRY_MOV_ID       = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM8     = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM16    = 8'h02;
    localparam logic [7:0]  SVC_FETCH_IMM32    = 8'h03;
    localparam logic [7:0]  SVC_EA_CALC_32     = 8'h11;
    localparam logic [7:0]  SVC_LOAD_RM8       = 8'h20;
    localparam logic [7:0]  SVC_LOAD_RM16      = 8'h21;
    localparam logic [7:0]  SVC_LOAD_RM32      = 8'h22;
    localparam logic [7:0]  SVC_STORE_RM8      = 8'h23;
    localparam logic [7:0]  SVC_STORE_RM16     = 8'h24;
    localparam logic [7:0]  SVC_STORE_RM32     = 8'h25;
    localparam logic [9:0]  CM_MOV_REG_MASK    = 10'h1C1;
    localparam logic [9:0]  CM_NOP_EIP_MASK    = 10'h1C2;
    localparam logic [31:0] RESET_EIP          = 32'hFFFFFFF0;

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
    logic [3:0]  bus_byteen_pending;
    logic [31:0] bus_dout_pending;
    logic [31:0] expected_gpr [0:7];
    logic        base_seen [0:7];
    logic        index_seen [0:7];

    logic [31:0] program_pc;
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int ea_calc32_count;
    int indexed_ea_count;
    int indexed_t2_exact_count;
    int no_index_ea_count;
    int no_index_t2_exact_count;
    int esp_index_seen_count;
    int scale0_count;
    int scale1_count;
    int scale2_count;
    int scale3_count;
    int load_rm8_count;
    int load_rm16_count;
    int load_rm32_count;
    int store_rm8_count;
    int store_rm16_count;
    int store_rm32_count;
    int fetch_imm8_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int byteen_0001_count;
    int byteen_0011_count;
    int byteen_1111_count;
    int cm_mov_reg_count;
    int cm_nop_eip_count;
    logic timed_out;

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    function automatic logic [31:0] read_mem32(input logic [31:0] addr);
        return {mem[pa16(addr + 32'd3)],
                mem[pa16(addr + 32'd2)],
                mem[pa16(addr + 32'd1)],
                mem[pa16(addr + 32'd0)]};
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

    function automatic logic [31:0] merge_word(
        input logic [31:0] old_val,
        input logic [15:0] data
    );
        logic [31:0] tmp;
        begin
            tmp = old_val;
            tmp[15:0] = data;
            return tmp;
        end
    endfunction

    function automatic logic [31:0] scale_value(
        input logic [31:0] val,
        input logic [1:0]  scale
    );
        case (scale)
            2'b00: return val;
            2'b01: return val << 1;
            2'b10: return val << 2;
            default: return val << 3;
        endcase
    endfunction

    function automatic logic [31:0] indexed_ea(
        input logic [2:0] base,
        input logic [2:0] index,
        input logic [1:0] scale,
        input logic signed [31:0] disp
    );
        return expected_gpr[base] + scale_value(expected_gpr[index], scale) + disp;
    endfunction

    function automatic logic [31:0] dut_indexed_ea;
        logic [2:0] base;
        logic [2:0] index;
        logic [1:0] scale;
        logic [31:0] disp;
        begin
            base = dut.meta_sib_byte_r[2:0];
            index = dut.meta_sib_byte_r[5:3];
            scale = dut.meta_sib_byte_r[7:6];
            disp = ((dut.meta_modrm_class_r == 4'h6) ||
                    (dut.meta_modrm_class_r == 4'h7)) ? dut.meta_disp_value_r : 32'h0;
            return dut.u_commit.gpr_r[base] + scale_value(dut.u_commit.gpr_r[index], scale) + disp;
        end
    endfunction

    function automatic logic gprs_match_expected;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== expected_gpr[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    function automatic logic is_indexed_sib_form;
        return ((dut.meta_modrm_class_r == 4'h5) ||
                (dut.meta_modrm_class_r == 4'h6) ||
                (dut.meta_modrm_class_r == 4'h7)) &&
               (dut.meta_modrm_byte_r[2:0] == 3'b100) &&
               (dut.meta_sib_byte_r[5:3] != 3'b100) &&
               !((dut.meta_modrm_class_r == 4'h5) &&
                 (dut.meta_sib_byte_r[2:0] == 3'b101));
    endfunction

    function automatic logic is_no_index_sib_form;
        return ((dut.meta_modrm_class_r == 4'h5) ||
                (dut.meta_modrm_class_r == 4'h6) ||
                (dut.meta_modrm_class_r == 4'h7)) &&
               (dut.meta_modrm_byte_r[2:0] == 3'b100) &&
               (dut.meta_sib_byte_r[5:3] == 3'b100) &&
               !((dut.meta_modrm_class_r == 4'h5) &&
                 (dut.meta_sib_byte_r[2:0] == 3'b101));
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready          <= 1'b0;
            bus_din            <= 32'h0;
            bus_pending        <= 1'b0;
            bus_wr_pending     <= 1'b0;
            bus_addr_pending   <= 32'h0;
            bus_byteen_pending <= 4'h0;
            bus_dout_pending   <= 32'h0;
        end else begin
            bus_ready <= 1'b0;

            if ((bus_rd || bus_wr) && !bus_pending) begin
                bus_pending        <= 1'b1;
                bus_wr_pending     <= bus_wr;
                bus_addr_pending   <= bus_addr;
                bus_byteen_pending <= bus_byteen;
                bus_dout_pending   <= bus_dout;
            end

            if (bus_pending) begin
                if (bus_wr_pending) begin
                    if (bus_byteen_pending[0])
                        mem[pa16(bus_addr_pending + 32'd0)] <= bus_dout_pending[7:0];
                    if (bus_byteen_pending[1])
                        mem[pa16(bus_addr_pending + 32'd1)] <= bus_dout_pending[15:8];
                    if (bus_byteen_pending[2])
                        mem[pa16(bus_addr_pending + 32'd2)] <= bus_dout_pending[23:16];
                    if (bus_byteen_pending[3])
                        mem[pa16(bus_addr_pending + 32'd3)] <= bus_dout_pending[31:24];
                    bus_din <= 32'h0;
                end else begin
                    bus_din <= read_mem32(bus_addr_pending);
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

    task automatic write_mem32(input logic [31:0] addr, input logic [31:0] val);
        begin
            mem[pa16(addr + 32'd0)] = val[7:0];
            mem[pa16(addr + 32'd1)] = val[15:8];
            mem[pa16(addr + 32'd2)] = val[23:16];
            mem[pa16(addr + 32'd3)] = val[31:24];
        end
    endtask

    task automatic append_disp8(input logic signed [7:0] disp);
        begin
            mem[pa16(program_pc)] = disp[7:0];
            program_pc += 32'd1;
        end
    endtask

    task automatic append_disp32(input logic signed [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = disp[7:0];
            mem[pa16(program_pc + 32'd1)] = disp[15:8];
            mem[pa16(program_pc + 32'd2)] = disp[23:16];
            mem[pa16(program_pc + 32'd3)] = disp[31:24];
            program_pc += 32'd4;
        end
    endtask

    task automatic append_mov32_imm(input logic [2:0] dst, input logic [31:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hB8 | {5'h0, dst};
            mem[pa16(program_pc + 32'd1)] = imm[7:0];
            mem[pa16(program_pc + 32'd2)] = imm[15:8];
            mem[pa16(program_pc + 32'd3)] = imm[23:16];
            mem[pa16(program_pc + 32'd4)] = imm[31:24];
            expected_gpr[dst] = imm;
            program_pc += 32'd5;
        end
    endtask

    task automatic append_sib(input logic [1:0] mod_bits,
                              input logic [2:0] reg_bits,
                              input logic [1:0] scale_bits,
                              input logic [2:0] index_bits,
                              input logic [2:0] base_bits);
        begin
            mem[pa16(program_pc + 32'd0)] = {mod_bits, reg_bits, 3'b100};
            mem[pa16(program_pc + 32'd1)] = {scale_bits, index_bits, base_bits};
            program_pc += 32'd2;
        end
    endtask

    task automatic append_mov32_sib_index(input logic [2:0] dst,
                                          input logic [1:0] mod_bits,
                                          input logic [2:0] base,
                                          input logic [2:0] index,
                                          input logic [1:0] scale,
                                          input logic signed [31:0] disp,
                                          input logic [31:0] val);
        begin
            mem[pa16(program_pc++)] = 8'h8B;
            append_sib(mod_bits, dst, scale, index, base);
            if (mod_bits == 2'b01)
                append_disp8(disp[7:0]);
            else if (mod_bits == 2'b10)
                append_disp32(disp);
            expected_gpr[dst] = val;
        end
    endtask

    task automatic append_mov8_sib_index(input logic [2:0] dst,
                                         input logic [1:0] mod_bits,
                                         input logic [2:0] base,
                                         input logic [2:0] index,
                                         input logic [1:0] scale,
                                         input logic signed [31:0] disp,
                                         input logic [7:0] val);
        begin
            mem[pa16(program_pc++)] = 8'h8A;
            append_sib(mod_bits, dst, scale, index, base);
            if (mod_bits == 2'b01)
                append_disp8(disp[7:0]);
            else if (mod_bits == 2'b10)
                append_disp32(disp);
            expected_gpr[{1'b0, dst[1:0]}] =
                merge_byte(expected_gpr[{1'b0, dst[1:0]}], dst, val);
        end
    endtask

    task automatic append_mov16_sib_index(input logic [2:0] dst,
                                          input logic [1:0] mod_bits,
                                          input logic [2:0] base,
                                          input logic [2:0] index,
                                          input logic [1:0] scale,
                                          input logic signed [31:0] disp,
                                          input logic [15:0] val);
        begin
            mem[pa16(program_pc++)] = 8'h66;
            mem[pa16(program_pc++)] = 8'h8B;
            append_sib(mod_bits, dst, scale, index, base);
            if (mod_bits == 2'b01)
                append_disp8(disp[7:0]);
            else if (mod_bits == 2'b10)
                append_disp32(disp);
            expected_gpr[dst] = merge_word(expected_gpr[dst], val);
        end
    endtask

    task automatic append_store_sib_index(input logic [7:0] opcode,
                                          input logic [2:0] src,
                                          input logic [1:0] mod_bits,
                                          input logic [2:0] base,
                                          input logic [2:0] index,
                                          input logic [1:0] scale,
                                          input logic signed [31:0] disp,
                                          input logic pref66);
        begin
            if (pref66)
                mem[pa16(program_pc++)] = 8'h66;
            mem[pa16(program_pc++)] = opcode;
            append_sib(mod_bits, src, scale, index, base);
            if (mod_bits == 2'b01)
                append_disp8(disp[7:0]);
            else if (mod_bits == 2'b10)
                append_disp32(disp);
        end
    endtask

    task automatic append_imm_sib_index(input logic [7:0] opcode,
                                        input logic [1:0] mod_bits,
                                        input logic [2:0] base,
                                        input logic [2:0] index,
                                        input logic [1:0] scale,
                                        input logic signed [31:0] disp,
                                        input logic [31:0] imm,
                                        input logic pref66);
        begin
            if (pref66)
                mem[pa16(program_pc++)] = 8'h66;
            mem[pa16(program_pc++)] = opcode;
            append_sib(mod_bits, 3'b000, scale, index, base);
            if (mod_bits == 2'b01)
                append_disp8(disp[7:0]);
            else if (mod_bits == 2'b10)
                append_disp32(disp);
            mem[pa16(program_pc + 32'd0)] = imm[7:0];
            if (opcode == 8'hC6) begin
                program_pc += 32'd1;
            end else if (pref66) begin
                mem[pa16(program_pc + 32'd1)] = imm[15:8];
                program_pc += 32'd2;
            end else begin
                mem[pa16(program_pc + 32'd1)] = imm[15:8];
                mem[pa16(program_pc + 32'd2)] = imm[23:16];
                mem[pa16(program_pc + 32'd3)] = imm[31:24];
                program_pc += 32'd4;
            end
        end
    endtask

    task automatic append_mov32_sib_no_index(input logic [2:0] dst,
                                             input logic [2:0] base,
                                             input logic [31:0] val);
        begin
            mem[pa16(program_pc++)] = 8'h8B;
            append_sib(2'b00, dst, 2'b11, 3'b100, base);
            expected_gpr[dst] = val;
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

            saw_expected_dispatch = 1'b0;
            saw_mov_endi = 1'b0;
            saw_bus_wr = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 1000; c++) begin
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
            check({name, " does not ENDI as MOV before unsupported dispatch"}, !saw_mov_endi);
            check({name, " issues no bus write before unsupported dispatch"}, !saw_bus_wr);
        end
    endtask

    initial begin
        logic [31:0] ea_a;
        logic [31:0] ea_b;
        logic [31:0] ea_c;
        logic [31:0] ea_d;
        logic [31:0] ea_e;
        logic [31:0] ea_f;
        logic [31:0] ea_g;
        logic [31:0] ea_h;
        logic [31:0] ea_i;
        logic [31:0] ea_j;
        logic [31:0] ea_k;
        logic [31:0] ea_l;
        logic [31:0] ea_m;
        logic [31:0] ea_n;

        failures = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;
        bus_wr_pending = 1'b0;
        bus_addr_pending = 32'h0;
        bus_byteen_pending = 4'h0;
        bus_dout_pending = 32'h0;

        clear_memory();

        run_unsupported_form(7, 8'h8B, 8'h04, 8'h0D, 8'h00, 8'h20, 8'h00, 8'h00,
                             "no-base indexed SIB", 1'b0);
        run_unsupported_form(1, 8'h67, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                             "0x67 prefix byte", 1'b1);
        run_unsupported_form(4, 8'hC7, 8'h4C, 8'h4D, 8'h00, 8'h00, 8'h00, 8'h00,
                             "C7 indexed SIB non-/0", 1'b0);

        clear_memory();
        for (int i = 0; i < 8; i++) begin
            expected_gpr[i] = 32'h0;
            base_seen[i] = 1'b0;
            index_seen[i] = 1'b0;
        end

        mov_endi_count = 0;
        ea_calc32_count = 0;
        indexed_ea_count = 0;
        indexed_t2_exact_count = 0;
        no_index_ea_count = 0;
        no_index_t2_exact_count = 0;
        esp_index_seen_count = 0;
        scale0_count = 0;
        scale1_count = 0;
        scale2_count = 0;
        scale3_count = 0;
        load_rm8_count = 0;
        load_rm16_count = 0;
        load_rm32_count = 0;
        store_rm8_count = 0;
        store_rm16_count = 0;
        store_rm32_count = 0;
        fetch_imm8_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        byteen_0001_count = 0;
        byteen_0011_count = 0;
        byteen_1111_count = 0;
        cm_mov_reg_count = 0;
        cm_nop_eip_count = 0;
        timed_out = 1'b0;

        program_pc = RESET_EIP;

        append_mov32_imm(3'h0, 32'h00001000); // EAX base for mod=00
        append_mov32_imm(3'h1, 32'h00000004); // ECX index
        append_mov32_imm(3'h2, 32'h00000003); // EDX index
        append_mov32_imm(3'h3, 32'h00001300); // EBX base
        append_mov32_imm(3'h4, 32'h00001400); // ESP base
        append_mov32_imm(3'h5, 32'h00000005); // EBP index
        append_mov32_imm(3'h6, 32'h00000002); // ESI index
        append_mov32_imm(3'h7, 32'h00000006); // EDI index

        ea_a = indexed_ea(3'h0, 3'h5, 2'b00, 32'sd0);
        write_mem32(ea_a, 32'hA1A2A3A4);
        append_mov32_sib_index(3'h2, 2'b00, 3'h0, 3'h5, 2'b00, 32'sd0, 32'hA1A2A3A4);

        ea_b = indexed_ea(3'h4, 3'h1, 2'b01, -32'sd4);
        write_mem32(ea_b, 32'hB1B2B35A);
        append_mov8_sib_index(3'h3, 2'b01, 3'h4, 3'h1, 2'b01, -32'sd4, 8'h5A);

        append_mov32_imm(3'h5, 32'h00001500); // EBP base for mod=10
        append_mov32_imm(3'h6, 32'h00000002); // ESI index restored
        ea_c = indexed_ea(3'h5, 3'h6, 2'b10, 32'sd32);
        write_mem32(ea_c, 32'hC1C2BEEF);
        append_mov16_sib_index(3'h7, 2'b10, 3'h5, 3'h6, 2'b10, 32'sd32, 16'hBEEF);

        ea_d = indexed_ea(3'h3, 3'h7, 2'b11, 32'sd0);
        write_mem32(ea_d, 32'hD1D2D3D4);
        append_mov32_sib_index(3'h0, 2'b00, 3'h3, 3'h7, 2'b11, 32'sd0, 32'hD1D2D3D4);

        append_mov32_imm(3'h0, 32'h00000001); // EAX index
        append_mov32_imm(3'h1, 32'h0000005A); // CL store source
        append_mov32_imm(3'h2, 32'h00001200); // EDX base
        ea_e = indexed_ea(3'h2, 3'h0, 2'b00, 32'sd0);
        write_mem32(ea_e, 32'h11111111);
        append_store_sib_index(8'h88, 3'h1, 2'b00, 3'h2, 3'h0, 2'b00, 32'sd0, 1'b0);

        append_mov32_imm(3'h2, 32'h00000003); // EDX index
        append_mov32_imm(3'h3, 32'h55667788); // EBX store source
        append_mov32_imm(3'h6, 32'h00001600); // ESI base
        ea_f = indexed_ea(3'h6, 3'h2, 2'b01, 32'sd8);
        write_mem32(ea_f, 32'h22222222);
        append_store_sib_index(8'h89, 3'h3, 2'b01, 3'h6, 3'h2, 2'b01, 32'sd8, 1'b0);

        append_mov32_imm(3'h3, 32'h00000004); // EBX index
        append_mov32_imm(3'h6, 32'h0000CAFE); // SI store source
        append_mov32_imm(3'h7, 32'h00001700); // EDI base
        ea_g = indexed_ea(3'h7, 3'h3, 2'b10, 32'sd16);
        write_mem32(ea_g, 32'h33333333);
        append_store_sib_index(8'h89, 3'h6, 2'b10, 3'h7, 3'h3, 2'b10, 32'sd16, 1'b1);

        append_mov32_imm(3'h0, 32'h00000001); // EAX index
        append_mov32_imm(3'h1, 32'h00001100); // ECX base
        ea_h = indexed_ea(3'h1, 3'h0, 2'b11, -32'sd8);
        write_mem32(ea_h, 32'h44444444);
        append_imm_sib_index(8'hC6, 2'b01, 3'h1, 3'h0, 2'b11, -32'sd8,
                             32'h0000005A, 1'b0);

        append_mov32_imm(3'h5, 32'h00001500); // EBP base for mod=01
        append_mov32_imm(3'h7, 32'h00000002); // EDI index
        ea_i = indexed_ea(3'h5, 3'h7, 2'b01, 32'sd4);
        write_mem32(ea_i, 32'h55555555);
        append_imm_sib_index(8'hC7, 2'b01, 3'h5, 3'h7, 2'b01, 32'sd4,
                             32'h11223344, 1'b0);

        append_mov32_imm(3'h4, 32'h00001400); // ESP base
        append_mov32_imm(3'h6, 32'h00000003); // ESI index
        ea_j = indexed_ea(3'h4, 3'h6, 2'b10, 32'sd32);
        write_mem32(ea_j, 32'h66666666);
        append_imm_sib_index(8'hC7, 2'b10, 3'h4, 3'h6, 2'b10, 32'sd32,
                             32'h0000BEEF, 1'b1);

        append_mov32_imm(3'h0, 32'h00001800);
        append_mov32_imm(3'h1, 32'h00000002);
        ea_l = indexed_ea(3'h0, 3'h1, 2'b00, 32'sd0);
        write_mem32(ea_l, 32'hAAAAAA7C);
        append_mov8_sib_index(3'h3, 2'b00, 3'h0, 3'h1, 2'b00, 32'sd0, 8'h7C);

        append_mov32_imm(3'h5, 32'h00001900);
        append_mov32_imm(3'h6, 32'h00000003);
        ea_m = indexed_ea(3'h5, 3'h6, 2'b01, 32'sd4);
        write_mem32(ea_m, 32'hBBBBCAFE);
        append_mov16_sib_index(3'h7, 2'b01, 3'h5, 3'h6, 2'b01, 32'sd4, 16'hCAFE);

        append_mov32_imm(3'h0, 32'h00001A00);
        append_mov32_imm(3'h1, 32'h00000001);
        ea_n = indexed_ea(3'h0, 3'h1, 2'b10, 32'sd16);
        write_mem32(ea_n, 32'hCAFEBABE);
        append_mov32_sib_index(3'h1, 2'b10, 3'h0, 3'h1, 2'b10, 32'sd16, 32'hCAFEBABE);

        append_mov32_imm(3'h0, 32'h00001B00); // base
        append_mov32_imm(3'h4, 32'h00000020); // proves SIB.index=100 is no-index
        ea_k = expected_gpr[3'h0];
        write_mem32(ea_k, 32'hABCDEF01);
        write_mem32(ea_k + (expected_gpr[3'h4] << 3), 32'hBAD0BAD0);
        append_mov32_sib_no_index(3'h2, 3'h0, 32'hABCDEF01);

        mem[pa16(program_pc)] = 8'h90;
        program_end_eip = program_pc + 32'd1;

        reset_cpu();

        for (cycles = 0; cycles < TIMEOUT; cycles++) begin
            @(posedge clk);
            #1;

            if (dut.svc_req_out) begin
                unique case (dut.svc_id_out)
                    SVC_FETCH_IMM8:  fetch_imm8_count++;
                    SVC_FETCH_IMM16: fetch_imm16_count++;
                    SVC_FETCH_IMM32: fetch_imm32_count++;
                    SVC_EA_CALC_32: begin
                        ea_calc32_count++;
                        if (is_indexed_sib_form()) begin
                            indexed_ea_count++;
                            base_seen[dut.meta_sib_byte_r[2:0]] = 1'b1;
                            index_seen[dut.meta_sib_byte_r[5:3]] = 1'b1;
                            if (dut.meta_sib_byte_r[5:3] == 3'b100)
                                esp_index_seen_count++;
                            unique case (dut.meta_sib_byte_r[7:6])
                                2'b00: scale0_count++;
                                2'b01: scale1_count++;
                                2'b10: scale2_count++;
                                2'b11: scale3_count++;
                                default: ;
                            endcase
                        end else if (is_no_index_sib_form()) begin
                            no_index_ea_count++;
                        end
                    end
                    SVC_LOAD_RM8:    load_rm8_count++;
                    SVC_LOAD_RM16:   load_rm16_count++;
                    SVC_LOAD_RM32:   load_rm32_count++;
                    SVC_STORE_RM8:   store_rm8_count++;
                    SVC_STORE_RM16:  store_rm16_count++;
                    SVC_STORE_RM32:  store_rm32_count++;
                    default: ;
                endcase
            end

            if (dut.ea_t2_wr_en && is_indexed_sib_form() &&
                (dut.ea_t2_wr_data == dut_indexed_ea()))
                indexed_t2_exact_count++;

            if (dut.ea_t2_wr_en && is_no_index_sib_form() &&
                (dut.ea_t2_wr_data == dut.u_commit.gpr_r[dut.meta_sib_byte_r[2:0]]))
                no_index_t2_exact_count++;

            if (bus_wr && !bus_pending) begin
                unique case (bus_byteen)
                    4'b0001: byteen_0001_count++;
                    4'b0011: byteen_0011_count++;
                    4'b1111: byteen_1111_count++;
                    default: ;
                endcase
            end

            if (dut.endi_req && !dut.u_commit.endi_req_d) begin
                if (dut.endi_mask == CM_MOV_REG_MASK)
                    cm_mov_reg_count++;
                if (dut.endi_mask == CM_NOP_EIP_MASK)
                    cm_nop_eip_count++;
            end

            if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID))
                mov_endi_count++;

            if (dbg_endi_pulse && (dbg_eip == program_end_eip))
                break;
        end

        if (cycles >= TIMEOUT)
            timed_out = 1'b1;

        $display("Rung 6 Pass 6G-1 MOV base-present indexed SIB checks");

        check("simulation completed before timeout", !timed_out);
        check("final EIP reached NOP fall-through", dbg_eip == program_end_eip);
        check("no fault pending", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("EA_CALC_32 issued for indexed and no-index SIB MOV", ea_calc32_count == 14);
        check("EA_CALC_32 issued for each indexed SIB MOV", indexed_ea_count == 13);
        check("EA_CALC_32 computed base + scaled index + displacement", indexed_t2_exact_count == 13);
        check("scale=00 covered", scale0_count >= 2);
        check("scale=01 covered", scale1_count >= 3);
        check("scale=10 covered", scale2_count >= 3);
        check("scale=11 covered", scale3_count >= 2);
        check("EAX covered as index", index_seen[3'h0]);
        check("ECX covered as index", index_seen[3'h1]);
        check("EDX covered as index", index_seen[3'h2]);
        check("EBX covered as index", index_seen[3'h3]);
        check("ESP not observed as index", !index_seen[3'h4] && (esp_index_seen_count == 0));
        check("EBP covered as index", index_seen[3'h5]);
        check("ESI covered as index", index_seen[3'h6]);
        check("EDI covered as index", index_seen[3'h7]);
        check("EAX covered as base", base_seen[3'h0]);
        check("ECX covered as base", base_seen[3'h1]);
        check("EDX covered as base", base_seen[3'h2]);
        check("EBX covered as base", base_seen[3'h3]);
        check("ESP covered as base", base_seen[3'h4]);
        check("EBP covered as base", base_seen[3'h5]);
        check("ESI covered as base", base_seen[3'h6]);
        check("EDI covered as base", base_seen[3'h7]);
        check("SIB.index=100 remains no-index", no_index_ea_count == 1);
        check("no-index SIB ignored ESP as index", no_index_t2_exact_count == 1);
        check("LOAD_RM8 issued for indexed memory-source", load_rm8_count == 2);
        check("LOAD_RM16 issued for indexed memory-source", load_rm16_count == 2);
        check("LOAD_RM32 issued for indexed/no-index memory-source", load_rm32_count == 4);
        check("STORE_RM8 issued for indexed stores", store_rm8_count == 2);
        check("STORE_RM16 issued for indexed stores", store_rm16_count == 2);
        check("STORE_RM32 issued for indexed stores", store_rm32_count == 2);
        check("FETCH_IMM8 issued for C6 indexed SIB form", fetch_imm8_count >= 1);
        check("FETCH_IMM16 issued for 66+C7 indexed SIB form", fetch_imm16_count >= 1);
        check("FETCH_IMM32 issued for C7 indexed SIB form and setup", fetch_imm32_count >= 1);
        check("CM_MOV_REG used for register destinations", cm_mov_reg_count >= 12);
        check("CM_NOP|CM_EIP used for memory destinations", cm_nop_eip_count >= 6);
        check("STORE_RM8 byte enable observed", byteen_0001_count >= 2);
        check("STORE_RM16 byte enable observed", byteen_0011_count >= 2);
        check("STORE_RM32 byte enable observed", byteen_1111_count >= 2);

        check("final GPR state matches expected", gprs_match_expected());
        check("8A r8,[EAX+ECX] loaded final byte", dut.u_commit.gpr_r[3'h3][7:0] == 8'h7C);
        check("66 8B r16,[EBP+ESI*2+4] loaded final word", dut.u_commit.gpr_r[3'h7][15:0] == 16'hCAFE);
        check("8B r32,[EAX+ECX*4+16] loaded final dword", dut.u_commit.gpr_r[3'h1] == 32'hCAFEBABE);
        check("88 [EDX+EAX], CL wrote byte", read_mem32(ea_e) == 32'h1111115A);
        check("89 [ESI+EDX*2+8], EBX wrote dword", read_mem32(ea_f) == 32'h55667788);
        check("66 89 [EDI+EBX*4+16], SI wrote word", read_mem32(ea_g) == 32'h3333CAFE);
        check("C6 [ECX+EAX*8-8], imm8 wrote byte", read_mem32(ea_h) == 32'h4444445A);
        check("C7 [EBP+EDI*2+4], imm32 wrote dword", read_mem32(ea_i) == 32'h11223344);
        check("66 C7 [ESP+ESI*4+32], imm16 wrote word", read_mem32(ea_j) == 32'h6666BEEF);
        check("index=100 no-index form loaded base-only address", dut.u_commit.gpr_r[3'h2] == 32'hABCDEF01);

        if (failures == 0) begin
            $display("RESULT: ALL TESTS PASSED");
        end else begin
            $display("RESULT: %0d TEST(S) FAILED", failures);
        end
        $finish;
    end

endmodule
