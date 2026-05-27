// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_mem_src_disp32.sv
// Bounded Rung 6 Pass 6A-1 smoke: MOV memory-source direct disp32 only.
//
// Authorized memory-source forms:
//   8A /r      mod=00 r/m=101 disp32 -> MOV r8,  [disp32]
//   8B /r      mod=00 r/m=101 disp32 -> MOV r32, [disp32]
//   66 8B /r   mod=00 r/m=101 disp32 -> MOV r16, [disp32]
//
// This test intentionally does not exercise authorized SIB, base/index/scale,
// disp8, base+disp8/base+disp32, 0x67, STORE_RM, or C6/C7. Later Pass 6 tests
// cover those newly-authorized bounded MOV memory forms in separate testbenches.

`timescale 1ns/1ps

module tb_rung6_mov_mem_src_disp32;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 120000;
    localparam int MAX_OPS         = 80;

    localparam logic [7:0]  ENTRY_NULL_ID      = 8'h00;
    localparam logic [7:0]  ENTRY_MOV_ID       = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM32    = 8'h03;
    localparam logic [7:0]  SVC_EA_CALC_32     = 8'h11;
    localparam logic [7:0]  SVC_LOAD_RM8       = 8'h20;
    localparam logic [7:0]  SVC_LOAD_RM16      = 8'h21;
    localparam logic [7:0]  SVC_LOAD_RM32      = 8'h22;
    localparam logic [9:0]  CM_MOV_REG_MASK    = 10'h1C1;
    localparam logic [31:0] RESET_EIP          = 32'hFFFFFFF0;
    localparam logic [31:0] DATA_BASE8         = 32'h00003000;
    localparam logic [31:0] DATA_BASE32        = 32'h00003100;
    localparam logic [31:0] DATA_BASE16        = 32'h00003200;

    localparam int OP_IMM32 = 0;
    localparam int OP_MEM8  = 1;
    localparam int OP_MEM32 = 2;
    localparam int OP_MEM16 = 3;

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
    logic [31:0] committed_gpr [0:7];

    logic [31:0] program_pc;
    int          op_count;
    int          op_kind [0:MAX_OPS-1];
    logic [2:0]  op_dst  [0:MAX_OPS-1];
    logic [31:0] op_val  [0:MAX_OPS-1];
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int mov_route_count;
    int fetch_imm32_count;
    int ea_calc32_count;
    int load_rm8_count;
    int load_rm16_count;
    int load_rm32_count;
    int bus_wr_count;
    int load_bus_read_count;
    logic saw_cm_mov_reg;
    logic early_gpr_visible;
    logic timed_out;
    logic ls_mem_rd_req_d;

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
            bus_ready         <= 1'b0;
            bus_din           <= 32'h0;
            bus_pending       <= 1'b0;
            bus_wr_pending    <= 1'b0;
            bus_addr_pending  <= 32'h0;
            bus_byteen_pending <= 4'h0;
            bus_dout_pending  <= 32'h0;
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

    function automatic logic [31:0] seed32(input int idx);
        return 32'h31415926 ^ ({24'h0, idx[7:0]} * 32'h0103070B);
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
                             input logic [31:0] val);
        begin
            op_kind[op_count] = kind;
            op_dst[op_count]  = dst;
            op_val[op_count]  = val;
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

    task automatic append_mov8_mem(input logic [2:0] dst, input logic [31:0] addr,
                                   input logic [7:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h8A;
            mem[pa16(program_pc + 32'd1)] = {2'b00, dst, 3'b101};
            program_pc += 32'd2;
            append_disp32(addr);
            record_op(OP_MEM8, dst, {24'h0, val});
        end
    endtask

    task automatic append_mov32_mem(input logic [2:0] dst, input logic [31:0] addr,
                                    input logic [31:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h8B;
            mem[pa16(program_pc + 32'd1)] = {2'b00, dst, 3'b101};
            program_pc += 32'd2;
            append_disp32(addr);
            record_op(OP_MEM32, dst, val);
        end
    endtask

    task automatic append_mov16_mem(input logic [2:0] dst, input logic [31:0] addr,
                                    input logic [15:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'h8B;
            mem[pa16(program_pc + 32'd2)] = {2'b00, dst, 3'b101};
            program_pc += 32'd3;
            append_disp32(addr);
            record_op(OP_MEM16, dst, {16'h0, val});
        end
    endtask

    task automatic apply_expected(input int idx);
        begin
            case (op_kind[idx])
                OP_IMM32: committed_gpr[op_dst[idx]] = op_val[idx];
                OP_MEM8: begin
                    committed_gpr[{1'b0, op_dst[idx][1:0]}] =
                        merge_byte(committed_gpr[{1'b0, op_dst[idx][1:0]}],
                                   op_dst[idx], op_val[idx][7:0]);
                end
                OP_MEM32: committed_gpr[op_dst[idx]] = op_val[idx];
                OP_MEM16: committed_gpr[op_dst[idx]] =
                    merge_word(committed_gpr[op_dst[idx]], op_val[idx][15:0]);
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
        input string name
    );
        logic saw_entry_null;
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
        bus_byteen_pending = 4'h0;
        bus_dout_pending = 32'h0;

        clear_memory();
        for (int i = 0; i < 8; i++)
            committed_gpr[i] = 32'h0;

        program_pc = RESET_EIP;
        op_count = 0;

        for (int r = 0; r < 8; r++)
            append_mov32_imm(r[2:0], seed32(r));

        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            logic [7:0]  val;
            addr = DATA_BASE8 + ({29'h0, r[2:0]} * 32'd4);
            val  = 8'h80 + r[7:0];
            write_mem32(addr, {24'h0, val});
            append_mov8_mem(r[2:0], addr, val);
        end

        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            logic [31:0] val;
            addr = DATA_BASE32 + ({29'h0, r[2:0]} * 32'd4);
            val  = 32'hA0001000 ^ ({24'h0, r[7:0]} * 32'h01010101);
            write_mem32(addr, val);
            append_mov32_mem(r[2:0], addr, val);
        end

        for (int r = 0; r < 8; r++) begin
            logic [31:0] addr;
            logic [15:0] val;
            addr = DATA_BASE16 + ({29'h0, r[2:0]} * 32'd4);
            val  = 16'h7000 ^ ({8'h0, r[7:0]} * 16'h0103);
            write_mem32(addr, {16'h0, val});
            append_mov16_mem(r[2:0], addr, val);
        end

        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6A-1 MOV mem-source disp32 Smoke");

        mov_endi_count = 0;
        mov_route_count = 0;
        fetch_imm32_count = 0;
        ea_calc32_count = 0;
        load_rm8_count = 0;
        load_rm16_count = 0;
        load_rm32_count = 0;
        bus_wr_count = 0;
        load_bus_read_count = 0;
        saw_cm_mov_reg = 1'b0;
        early_gpr_visible = 1'b0;
        timed_out = 1'b1;
        ls_mem_rd_req_d = 1'b0;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (bus_wr)
                    bus_wr_count++;

                if (dut.ls_mem_rd_req && !ls_mem_rd_req_d)
                    load_bus_read_count++;
                ls_mem_rd_req_d = dut.ls_mem_rd_req;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID))
                    mov_route_count++;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_EA_CALC_32))
                    ea_calc32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM8))
                    load_rm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM16))
                    load_rm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM32))
                    load_rm32_count++;

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

        check("eight setup MOVs plus 24 memory-source MOVs completed",
              !timed_out && (mov_endi_count == op_count) && (op_count == 32));
        check("ENTRY_MOV routed for setup and authorized memory-source forms",
              mov_route_count == 32);
        check("FETCH_IMM32 preserved for setup MOVs", fetch_imm32_count == 8);
        check("EA_CALC_32 issued once per memory-source MOV", ea_calc32_count == 24);
        check("LOAD_RM8 issued for all 8A memory-source forms", load_rm8_count == 8);
        check("LOAD_RM32 issued for all 8B r32 memory-source forms", load_rm32_count == 8);
        check("LOAD_RM16 issued for all 66+8B r16 memory-source forms", load_rm16_count == 8);
        check("load_store issued memory read requests", load_bus_read_count == 24);
        check("ENDI used CM_MOV_REG", saw_cm_mov_reg);
        check("no bus writes for memory-source MOV", bus_wr_count == 0);
        check("no early GPR visibility before CM_MOV_REG", !early_gpr_visible);
        check("no fault after memory-source MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6A-1 MOV sequence", dbg_eip == program_end_eip);
        check("final GPR state matches shadow", gprs_match_shadow());
        if (!gprs_match_shadow()) begin
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== committed_gpr[i])
                    $display("    GPR[%0d] actual=%08X expected=%08X",
                             i, dut.u_commit.gpr_r[i], committed_gpr[i]);
            end
        end

        run_unsupported_form(7, 8'h66, 8'h8A, 8'h05, 8'h00, 8'h30, 8'h00, 8'h00,
                             "66+8A memory-source byte");

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6A-1 MOV mem-source disp32 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6A-1 MOV mem-source disp32 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6A-1 MOV mem-source disp32 smoke failed");
        end

        $finish;
    end

endmodule
