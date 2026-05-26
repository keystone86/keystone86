// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_mem_dst_disp32.sv
// Bounded Rung 6 Pass 6B-1 smoke: MOV memory-destination direct disp32 only.
//
// Authorized memory-destination forms:
//   88 /r      mod=00 r/m=101 disp32 -> MOV [disp32], r8
//   89 /r      mod=00 r/m=101 disp32 -> MOV [disp32], r32
//   66 89 /r   mod=00 r/m=101 disp32 -> MOV [disp32], r16
//
// This test intentionally does not exercise C6/C7, authorized SIB,
// base/index/scale, disp8, base+disp8/base+disp32, 0x67 address-size behavior,
// EA_CALC_16, 16-bit addressing, protected/page/segment behavior, or flags
// production.

`timescale 1ns/1ps

module tb_rung6_mov_mem_dst_disp32;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 160000;
    localparam int MAX_OPS         = 80;

    localparam logic [7:0]  ENTRY_NULL_ID      = 8'h00;
    localparam logic [7:0]  ENTRY_PREFIX_ID    = 8'h12;
    localparam logic [7:0]  ENTRY_MOV_ID       = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM8     = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM16    = 8'h02;
    localparam logic [7:0]  SVC_FETCH_IMM32    = 8'h03;
    localparam logic [7:0]  SVC_EA_CALC_32     = 8'h11;
    localparam logic [7:0]  SVC_STORE_RM8      = 8'h23;
    localparam logic [7:0]  SVC_STORE_RM16     = 8'h24;
    localparam logic [7:0]  SVC_STORE_RM32     = 8'h25;
    localparam logic [7:0]  SVC_LOAD_REG_META  = 8'h26;
    localparam logic [9:0]  CM_MOV_REG_MASK    = 10'h1C1;
    localparam logic [9:0]  CM_NOP_EIP_MASK    = 10'h1C2;
    localparam logic [31:0] RESET_EIP          = 32'hFFFFFFF0;
    localparam logic [31:0] DATA_BASE8         = 32'h00004000;
    localparam logic [31:0] DATA_BASE32        = 32'h00004100;
    localparam logic [31:0] DATA_BASE16        = 32'h00004200;

    localparam int OP_SETUP = 0;
    localparam int OP_STORE = 1;

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
    logic        bus_write_completed;
    logic [31:0] expected_gpr [0:7];
    logic [31:0] expected_mem32 [0:23];

    logic [31:0] program_pc;
    int          op_count;
    int          op_kind [0:MAX_OPS-1];
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int mov_route_count;
    int fetch_imm8_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int ea_calc32_count;
    int load_reg_meta_count;
    int store_rm8_count;
    int store_rm16_count;
    int store_rm32_count;
    int store_endi_count;
    int bus_wr_count;
    int byteen_0001_count;
    int byteen_0011_count;
    int byteen_1111_count;
    int store_complete_before_endi_count;
    logic saw_cm_mov_reg;
    logic saw_cm_nop_eip;
    logic timed_out;
    logic store_service_active;
    logic store_completed_since_service;
    logic store_endi_before_completion;
    logic eu_wr_req_d;
    logic endi_req_d;

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    function automatic logic [31:0] read_mem32(input logic [31:0] addr);
        return {mem[pa16(addr + 32'd3)],
                mem[pa16(addr + 32'd2)],
                mem[pa16(addr + 32'd1)],
                mem[pa16(addr + 32'd0)]};
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
            bus_write_completed <= 1'b0;
        end else begin
            bus_ready <= 1'b0;
            bus_write_completed <= 1'b0;

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
                    bus_write_completed <= 1'b1;
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

    function automatic logic [31:0] seed32(input int idx);
        return 32'h13579BDF ^ ({24'h0, idx[7:0]} * 32'h0105090D);
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

    task automatic record_op(input int kind);
        begin
            op_kind[op_count] = kind;
            op_count++;
        end
    endtask

    task automatic append_disp32(input logic [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = disp[7:0];
            mem[pa16(program_pc + 32'd1)] = disp[15:8];
            mem[pa16(program_pc + 32'd2)] = disp[23:16];
            mem[pa16(program_pc + 32'd3)] = disp[31:24];
            program_pc += 32'd4;
        end
    endtask

    task automatic append_mov8_imm(input logic [2:0] dst, input logic [7:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hB0 | {5'h0, dst};
            mem[pa16(program_pc + 32'd1)] = imm;
            expected_gpr[{1'b0, dst[1:0]}] =
                merge_byte(expected_gpr[{1'b0, dst[1:0]}], dst, imm);
            record_op(OP_SETUP);
            program_pc += 32'd2;
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
            record_op(OP_SETUP);
            program_pc += 32'd5;
        end
    endtask

    task automatic append_mov16_imm(input logic [2:0] dst, input logic [15:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'hB8 | {5'h0, dst};
            mem[pa16(program_pc + 32'd2)] = imm[7:0];
            mem[pa16(program_pc + 32'd3)] = imm[15:8];
            expected_gpr[dst] = merge_word(expected_gpr[dst], imm);
            record_op(OP_SETUP);
            program_pc += 32'd4;
        end
    endtask

    task automatic append_mov_mem8(input logic [2:0] src, input logic [31:0] addr,
                                   input logic [7:0] val, input int slot);
        begin
            write_mem32(addr, 32'hA5A50000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = (32'hA5A50000 | {24'h0, slot[7:0]});
            expected_mem32[slot][7:0] = val;
            mem[pa16(program_pc + 32'd0)] = 8'h88;
            mem[pa16(program_pc + 32'd1)] = {2'b00, src, 3'b101};
            program_pc += 32'd2;
            append_disp32(addr);
            record_op(OP_STORE);
        end
    endtask

    task automatic append_mov_mem32(input logic [2:0] src, input logic [31:0] addr,
                                    input logic [31:0] val, input int slot);
        begin
            write_mem32(addr, 32'h5A5A0000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = val;
            mem[pa16(program_pc + 32'd0)] = 8'h89;
            mem[pa16(program_pc + 32'd1)] = {2'b00, src, 3'b101};
            program_pc += 32'd2;
            append_disp32(addr);
            record_op(OP_STORE);
        end
    endtask

    task automatic append_mov_mem16(input logic [2:0] src, input logic [31:0] addr,
                                    input logic [15:0] val, input int slot);
        begin
            write_mem32(addr, 32'hC3C30000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = (32'hC3C30000 | {24'h0, slot[7:0]});
            expected_mem32[slot][15:0] = val;
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'h89;
            mem[pa16(program_pc + 32'd2)] = {2'b00, src, 3'b101};
            program_pc += 32'd3;
            append_disp32(addr);
            record_op(OP_STORE);
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
                for (int c = 0; c < 600; c++) begin
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
        bus_byteen_pending = 4'h0;
        bus_dout_pending = 32'h0;
        bus_write_completed = 1'b0;

        clear_memory();
        for (int i = 0; i < 8; i++)
            expected_gpr[i] = 32'h0;
        for (int i = 0; i < 24; i++)
            expected_mem32[i] = 32'h0;

        program_pc = RESET_EIP;
        op_count = 0;

        for (int r = 0; r < 8; r++)
            append_mov8_imm(r[2:0], 8'h50 + r[7:0]);
        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            logic [7:0]  val;
            addr = DATA_BASE8 + ({29'h0, r[2:0]} * 32'd4);
            if (r[2])
                val = expected_gpr[{1'b0, r[1:0]}][15:8];
            else
                val = expected_gpr[{1'b0, r[1:0]}][7:0];
            append_mov_mem8(r[2:0], addr, val, r);
        end

        for (int r = 0; r < 8; r++)
            append_mov32_imm(r[2:0], seed32(r));
        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            addr = DATA_BASE32 + ({29'h0, r[2:0]} * 32'd4);
            append_mov_mem32(r[2:0], addr, expected_gpr[r], 8 + r);
        end

        for (int r = 0; r < 8; r++)
            append_mov16_imm(r[2:0], 16'h7000 ^ ({8'h0, r[7:0]} * 16'h0103));
        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            addr = DATA_BASE16 + ({29'h0, r[2:0]} * 32'd4);
            append_mov_mem16(r[2:0], addr, expected_gpr[r][15:0], 16 + r);
        end

        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6B-1 MOV mem-destination disp32 Smoke");

        mov_endi_count = 0;
        mov_route_count = 0;
        fetch_imm8_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        ea_calc32_count = 0;
        load_reg_meta_count = 0;
        store_rm8_count = 0;
        store_rm16_count = 0;
        store_rm32_count = 0;
        store_endi_count = 0;
        bus_wr_count = 0;
        byteen_0001_count = 0;
        byteen_0011_count = 0;
        byteen_1111_count = 0;
        store_complete_before_endi_count = 0;
        saw_cm_mov_reg = 1'b0;
        saw_cm_nop_eip = 1'b0;
        timed_out = 1'b1;
        store_service_active = 1'b0;
        store_completed_since_service = 1'b0;
        store_endi_before_completion = 1'b0;
        eu_wr_req_d = 1'b0;
        endi_req_d = 1'b0;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if ((dut.eu_req && dut.eu_wr) && !eu_wr_req_d) begin
                    bus_wr_count++;
                    case (dut.eu_byteen)
                        4'b0001: byteen_0001_count++;
                        4'b0011: byteen_0011_count++;
                        4'b1111: byteen_1111_count++;
                        default: ;
                    endcase
                end
                eu_wr_req_d = dut.eu_req && dut.eu_wr;

                if (bus_write_completed && store_service_active)
                    store_completed_since_service = 1'b1;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID))
                    mov_route_count++;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM8))
                    fetch_imm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM16))
                    fetch_imm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_EA_CALC_32))
                    ea_calc32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_REG_META))
                    load_reg_meta_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM8)) begin
                    store_rm8_count++;
                    store_service_active = 1'b1;
                    store_completed_since_service = 1'b0;
                end
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM16)) begin
                    store_rm16_count++;
                    store_service_active = 1'b1;
                    store_completed_since_service = 1'b0;
                end
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM32)) begin
                    store_rm32_count++;
                    store_service_active = 1'b1;
                    store_completed_since_service = 1'b0;
                end

                if (dut.endi_req && !endi_req_d && (dut.endi_mask == CM_MOV_REG_MASK))
                    saw_cm_mov_reg = 1'b1;
                if (dut.endi_req && !endi_req_d && (dut.endi_mask == CM_NOP_EIP_MASK)) begin
                    saw_cm_nop_eip = 1'b1;
                    store_endi_count++;
                    if (store_completed_since_service)
                        store_complete_before_endi_count++;
                    else
                        store_endi_before_completion = 1'b1;
                    store_service_active = 1'b0;
                end
                endi_req_d = dut.endi_req;

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    mov_endi_count++;
                    if (mov_endi_count == op_count) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_movs;
                    end
                end
            end
        end

        check("24 setup MOVs plus 24 memory-destination MOVs completed",
              !timed_out && (mov_endi_count == op_count) && (op_count == 48));
        check("ENTRY_MOV routed for setup and authorized memory-destination forms",
              mov_route_count == 48);
        check("FETCH_IMM8 preserved for byte setup MOVs", fetch_imm8_count == 8);
        check("FETCH_IMM16 preserved for word setup MOVs", fetch_imm16_count == 8);
        check("FETCH_IMM32 preserved for dword setup MOVs", fetch_imm32_count == 8);
        check("EA_CALC_32 issued once per memory-destination MOV", ea_calc32_count == 24);
        check("LOAD_REG_META issued for every memory-destination source register",
              load_reg_meta_count == 24);
        check("STORE_RM8 issued for all 88 memory-destination forms", store_rm8_count == 8);
        check("STORE_RM32 issued for all 89 r32 memory-destination forms", store_rm32_count == 8);
        check("STORE_RM16 issued for all 66+89 r16 memory-destination forms", store_rm16_count == 8);
        check("one bus write per memory-destination MOV", bus_wr_count == 24);
        check("STORE_RM8 bus byte enables are 0001", byteen_0001_count == 8);
        check("STORE_RM16 bus byte enables are 0011", byteen_0011_count == 8);
        check("STORE_RM32 bus byte enables are 1111", byteen_1111_count == 8);
        check("STORE_RM services complete before ENDI",
              (store_complete_before_endi_count == 24) && !store_endi_before_completion);
        check("setup MOVs still use CM_MOV_REG", saw_cm_mov_reg);
        check("memory-destination MOVs use ENDI CM_NOP|CM_EIP", saw_cm_nop_eip);
        check("no fault after memory-destination MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6B-1 MOV sequence", dbg_eip == program_end_eip);
        check("no unintended GPR changes from memory-destination stores", gprs_match_expected());
        if (!gprs_match_expected()) begin
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== expected_gpr[i])
                    $display("    GPR[%0d] actual=%08X expected=%08X",
                             i, dut.u_commit.gpr_r[i], expected_gpr[i]);
            end
        end

        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            addr = DATA_BASE8 + ({29'h0, r[2:0]} * 32'd4);
            check($sformatf("88 r8 source %0d final memory byte", r),
                  read_mem32(addr) == expected_mem32[r]);
        end
        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            addr = DATA_BASE32 + ({29'h0, r[2:0]} * 32'd4);
            check($sformatf("89 r32 source %0d final memory dword", r),
                  read_mem32(addr) == expected_mem32[8 + r]);
        end
        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            addr = DATA_BASE16 + ({29'h0, r[2:0]} * 32'd4);
            check($sformatf("66+89 r16 source %0d final memory word", r),
                  read_mem32(addr) == expected_mem32[16 + r]);
        end

        run_unsupported_form(7, 8'h88, 8'h84, 8'h0D, 8'h00, 8'h40, 8'h00, 8'h00,
                             "88 SIB mod=10 index!=100 memory destination", 1'b0);
        run_unsupported_form(7, 8'h89, 8'h84, 8'h0D, 8'h00, 8'h40, 8'h00, 8'h00,
                             "89 SIB mod=10 index!=100 memory destination", 1'b0);
        run_unsupported_form(7, 8'h89, 8'h04, 8'h25, 8'h00, 8'h40, 8'h00, 8'h00,
                             "89 SIB memory destination", 1'b0);
        run_unsupported_form(7, 8'h66, 8'h88, 8'h05, 8'h00, 8'h40, 8'h00, 8'h00,
                             "66+88 memory destination", 1'b0);
        run_unsupported_form(7, 8'h67, 8'h89, 8'h05, 8'h00, 8'h40, 8'h00, 8'h00,
                             "67-prefixed memory destination", 1'b1);

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6B-1 MOV mem-destination disp32 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6B-1 MOV mem-destination disp32 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6B-1 MOV mem-destination disp32 smoke failed");
        end

        $finish;
    end

endmodule
