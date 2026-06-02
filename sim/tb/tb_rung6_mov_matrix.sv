// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_matrix.sv
// Rung 6 final MOV matrix/reference harness.
//
// This is a test-only Appendix D proof harness. It uses a deterministic
// in-test oracle for the bounded Rung 6 MOV scope and intentionally excludes
// segment-base addition, default-SS linearization, protected/page behavior,
// moffs, segment/control/debug/test MOV, MOVS, MOVSX, and MOVZX.

`timescale 1ns/1ps

module tb_rung6_mov_matrix;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 3000000;
    localparam int MAX_OPS         = 5000;
    localparam int MAX_STORES      = 1200;
    localparam int ADDR_CLASSES    = 13;

    localparam logic [7:0]  ENTRY_NULL_ID   = 8'h00;
    localparam logic [7:0]  ENTRY_MOV_ID    = 8'h01;
    localparam logic [7:0]  ENTRY_PREFIX_ID = 8'h12;
    localparam logic [31:0] RESET_EIP       = 32'hFFFFFFF0;
    localparam logic [31:0] DATA_BASE       = 32'h00008000;

    localparam int OP_GPR_IMM   = 0;
    localparam int OP_REG_COPY  = 1;
    localparam int OP_MEM_LOAD  = 2;
    localparam int OP_MEM_STORE = 3;

    localparam int W8  = 0;
    localparam int W16 = 1;
    localparam int W32 = 2;

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
    logic [7:0]  ref_mem [0:65535];
    logic        bus_pending;
    logic        bus_wr_pending;
    logic        bus_wr_observed_active;
    logic [31:0] bus_addr_pending;
    logic [3:0]  bus_byteen_pending;
    logic [31:0] bus_dout_pending;

    logic [31:0] program_pc;
    logic [31:0] program_end_eip;
    int          op_count;
    int          data_seq;

    int          op_kind [0:MAX_OPS-1];
    int          op_width [0:MAX_OPS-1];
    logic [2:0]  op_dst [0:MAX_OPS-1];
    logic [2:0]  op_src [0:MAX_OPS-1];
    logic [31:0] op_value [0:MAX_OPS-1];
    logic [31:0] op_addr [0:MAX_OPS-1];
    logic [31:0] op_next_eip [0:MAX_OPS-1];

    logic [31:0] ref_gpr [0:7];

    logic [31:0] observed_store_addr [0:MAX_STORES-1];
    logic [31:0] observed_store_data [0:MAX_STORES-1];
    logic [3:0]  observed_store_be [0:MAX_STORES-1];
    logic [31:0] expected_store_addr [0:MAX_STORES-1];
    logic [31:0] expected_store_data [0:MAX_STORES-1];
    logic [3:0]  expected_store_be [0:MAX_STORES-1];
    int          observed_store_count;
    int          expected_store_count;
    logic        extra_store_seen;

    int failures;
    int cycles;
    int completed_ops;
    logic timed_out;
    logic eflags_changed;
    logic gpr_mismatch_seen;
    logic store_addr_match;
    logic store_be_match;
    logic store_data_match;

    int cov_b0_imm8;
    int cov_b8_imm32;
    int cov_66_b8_imm16;
    int cov_c6_mod11;
    int cov_c7_mod11;
    int cov_66_c7_mod11;
    int cov_88_reg;
    int cov_89_reg;
    int cov_8a_reg;
    int cov_8b_reg;
    int cov_66_89_reg;
    int cov_66_8b_reg;
    int cov_regmem8;
    int cov_regmem16;
    int cov_regmem32;
    int cov_memreg8;
    int cov_memreg16;
    int cov_memreg32;
    int cov_memimm8;
    int cov_memimm16;
    int cov_memimm32;
    int cov_regmem_class [0:ADDR_CLASSES-1];
    int cov_memreg_class [0:ADDR_CLASSES-1];
    int cov_memimm_class [0:ADDR_CLASSES-1];

    function automatic logic [15:0] pa16(input logic [31:0] addr);
        return addr[15:0];
    endfunction

    function automatic logic [31:0] read_ref_mem32(input logic [31:0] addr);
        return {ref_mem[pa16(addr + 32'd3)],
                ref_mem[pa16(addr + 32'd2)],
                ref_mem[pa16(addr + 32'd1)],
                ref_mem[pa16(addr + 32'd0)]};
    endfunction

    function automatic logic [31:0] read_mem32(input logic [31:0] addr);
        return {mem[pa16(addr + 32'd3)],
                mem[pa16(addr + 32'd2)],
                mem[pa16(addr + 32'd1)],
                mem[pa16(addr + 32'd0)]};
    endfunction

    function automatic logic [31:0] mask_store_data(
        input logic [31:0] data,
        input logic [3:0]  be
    );
        logic [31:0] masked;
        begin
            masked = 32'h0;
            if (be[0]) masked[7:0]   = data[7:0];
            if (be[1]) masked[15:8]  = data[15:8];
            if (be[2]) masked[23:16] = data[23:16];
            if (be[3]) masked[31:24] = data[31:24];
            return masked;
        end
    endfunction

    function automatic logic [3:0] byteen_for_width(input int width);
        case (width)
            W8:  return 4'b0001;
            W16: return 4'b0011;
            default: return 4'b1111;
        endcase
    endfunction

    function automatic logic [31:0] seed32(input int idx);
        return 32'h10203040 ^ ({24'h0, idx[7:0]} * 32'h01040911);
    endfunction

    function automatic logic [31:0] matrix_imm(input int idx, input int width);
        case (width)
            W8:  return {24'h0, (8'h40 ^ idx[7:0])};
            W16: return {16'h0, (16'h6000 ^ ({8'h0, idx[7:0]} * 16'h0105))};
            default: return 32'hA0001000 ^ ({24'h0, idx[7:0]} * 32'h01010111);
        endcase
    endfunction

    function automatic logic [31:0] merge_gpr(
        input logic [31:0] old_val,
        input logic [2:0]  raw_idx,
        input int          width,
        input logic [31:0] data
    );
        logic [31:0] tmp;
        begin
            tmp = old_val;
            case (width)
                W8: begin
                    if (raw_idx[2])
                        tmp[15:8] = data[7:0];
                    else
                        tmp[7:0] = data[7:0];
                    return tmp;
                end
                W16: begin
                    tmp[15:0] = data[15:0];
                    return tmp;
                end
                default: return data;
            endcase
        end
    endfunction

    function automatic logic [31:0] read_gpr_width(
        input logic [2:0] raw_idx,
        input int         width
    );
        logic [31:0] val;
        begin
            val = ref_gpr[(width == W8) ? {1'b0, raw_idx[1:0]} : raw_idx];
            case (width)
                W8: begin
                    if (raw_idx[2])
                        return {24'h0, val[15:8]};
                    return {24'h0, val[7:0]};
                end
                W16: return {16'h0, val[15:0]};
                default: return val;
            endcase
        end
    endfunction

    function automatic logic [31:0] class_target_addr(input int cls, input int seq);
        return DATA_BASE + ({20'h0, seq[11:0]} * 32'd8) + ({28'h0, cls[3:0]} * 32'd512);
    endfunction

    function automatic logic [31:0] setup_ebx(input int cls, input logic [31:0] target);
        case (cls)
            1, 4: return target;
            2: return target + 32'd7;
            6: return target - 32'd12;
            9: return {16'h0, target[15:0] - 16'h0020};
            11: return {16'h0, target[15:0] + 16'h0005};
            12: return {16'h0, target[15:0] - 16'h0140};
            default: return 32'h00002000;
        endcase
    endfunction

    function automatic logic [31:0] setup_ebp(input int cls, input logic [31:0] target);
        case (cls)
            3: return target - 32'h00000123;
            10: return {16'h0, target[15:0] - 16'h0030};
            default: return 32'h00003000;
        endcase
    endfunction

    function automatic logic [31:0] setup_esi(input int cls, input logic [31:0] target);
        case (cls)
            6: return 32'h00000003;
            9: return 32'h00000020;
            10: return 32'h00000030;
            default: return 32'h00000010;
        endcase
    endfunction

    function automatic logic [31:0] setup_edi(input int cls, input logic [31:0] target);
        case (cls)
            7: return 32'h00000005;
            12: return 32'h00000040;
            default: return 32'h00000018;
        endcase
    endfunction

    function automatic logic gprs_match_ref;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== ref_gpr[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready              <= 1'b0;
            bus_din                <= 32'h0;
            bus_pending            <= 1'b0;
            bus_wr_pending         <= 1'b0;
            bus_wr_observed_active <= 1'b0;
            bus_addr_pending       <= 32'h0;
            bus_byteen_pending     <= 4'h0;
            bus_dout_pending       <= 32'h0;
        end else begin
            bus_ready <= 1'b0;

            if (!bus_wr) begin
                bus_wr_observed_active <= 1'b0;
            end else if (!bus_wr_observed_active) begin
                bus_wr_observed_active <= 1'b1;
                if (observed_store_count < MAX_STORES) begin
                    observed_store_addr[observed_store_count] <= bus_addr;
                    observed_store_data[observed_store_count] <= bus_dout;
                    observed_store_be[observed_store_count]   <= bus_byteen;
                end else begin
                    extra_store_seen <= 1'b1;
                end
                observed_store_count++;
            end

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

    task automatic check(input string name, input logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
        end else begin
            $display("  [FAIL] %s  EIP=%08X entry=%02X fault=%0d fc=%0h",
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending,
                     dbg_fault_class);
            failures++;
        end
    endtask

    task automatic reset_cpu;
        reset_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
    endtask

    task automatic clear_memory;
        for (int i = 0; i < 65536; i++) begin
            mem[i] = 8'h90;
            ref_mem[i] = 8'h90;
        end
    endtask

    task automatic write_data32(input logic [31:0] addr, input logic [31:0] val);
        begin
            mem[pa16(addr + 32'd0)] = val[7:0];
            mem[pa16(addr + 32'd1)] = val[15:8];
            mem[pa16(addr + 32'd2)] = val[23:16];
            mem[pa16(addr + 32'd3)] = val[31:24];
            ref_mem[pa16(addr + 32'd0)] = val[7:0];
            ref_mem[pa16(addr + 32'd1)] = val[15:8];
            ref_mem[pa16(addr + 32'd2)] = val[23:16];
            ref_mem[pa16(addr + 32'd3)] = val[31:24];
        end
    endtask

    task automatic emit8(input logic [7:0] b);
        begin
            mem[pa16(program_pc)] = b;
            ref_mem[pa16(program_pc)] = b;
            program_pc += 32'd1;
        end
    endtask

    task automatic emit16(input logic [15:0] w);
        begin
            emit8(w[7:0]);
            emit8(w[15:8]);
        end
    endtask

    task automatic emit32(input logic [31:0] d);
        begin
            emit8(d[7:0]);
            emit8(d[15:8]);
            emit8(d[23:16]);
            emit8(d[31:24]);
        end
    endtask

    task automatic record_op(input int kind, input int width,
                             input logic [2:0] dst, input logic [2:0] src,
                             input logic [31:0] value, input logic [31:0] addr);
        begin
            if (op_count >= MAX_OPS) begin
                $fatal(1, "MOV matrix op table overflow");
            end
            op_kind[op_count]     = kind;
            op_width[op_count]    = width;
            op_dst[op_count]      = dst;
            op_src[op_count]      = src;
            op_value[op_count]    = value;
            op_addr[op_count]     = addr;
            op_next_eip[op_count] = program_pc;
            op_count++;
        end
    endtask

    task automatic append_mov32_imm(input logic [2:0] dst, input logic [31:0] imm,
                                    input logic count_matrix);
        begin
            emit8(8'hB8 | {5'h0, dst});
            emit32(imm);
            record_op(OP_GPR_IMM, W32, dst, 3'h0, imm, 32'h0);
            if (count_matrix)
                cov_b8_imm32++;
        end
    endtask

    task automatic append_mov8_imm(input logic [2:0] dst, input logic [7:0] imm);
        begin
            emit8(8'hB0 | {5'h0, dst});
            emit8(imm);
            record_op(OP_GPR_IMM, W8, dst, 3'h0, {24'h0, imm}, 32'h0);
            cov_b0_imm8++;
        end
    endtask

    task automatic append_mov16_imm(input logic [2:0] dst, input logic [15:0] imm);
        begin
            emit8(8'h66);
            emit8(8'hB8 | {5'h0, dst});
            emit16(imm);
            record_op(OP_GPR_IMM, W16, dst, 3'h0, {16'h0, imm}, 32'h0);
            cov_66_b8_imm16++;
        end
    endtask

    task automatic append_c6_mod11(input logic [2:0] dst, input logic [7:0] imm);
        begin
            emit8(8'hC6);
            emit8({2'b11, 3'b000, dst});
            emit8(imm);
            record_op(OP_GPR_IMM, W8, dst, 3'h0, {24'h0, imm}, 32'h0);
            cov_c6_mod11++;
        end
    endtask

    task automatic append_c7_mod11(input logic [2:0] dst, input logic [31:0] imm);
        begin
            emit8(8'hC7);
            emit8({2'b11, 3'b000, dst});
            emit32(imm);
            record_op(OP_GPR_IMM, W32, dst, 3'h0, imm, 32'h0);
            cov_c7_mod11++;
        end
    endtask

    task automatic append_66_c7_mod11(input logic [2:0] dst, input logic [15:0] imm);
        begin
            emit8(8'h66);
            emit8(8'hC7);
            emit8({2'b11, 3'b000, dst});
            emit16(imm);
            record_op(OP_GPR_IMM, W16, dst, 3'h0, {16'h0, imm}, 32'h0);
            cov_66_c7_mod11++;
        end
    endtask

    task automatic append_reg_reg(input logic [7:0] opcode, input int width,
                                  input logic [2:0] dst, input logic [2:0] src,
                                  input logic pref66);
        begin
            if (pref66)
                emit8(8'h66);
            emit8(opcode);
            case (opcode)
                8'h88,
                8'h89: emit8({2'b11, src, dst});
                default: emit8({2'b11, dst, src});
            endcase
            record_op(OP_REG_COPY, width, dst, src, 32'h0, 32'h0);
            case (opcode)
                8'h88: cov_88_reg++;
                8'h89: begin
                    if (pref66) cov_66_89_reg++;
                    else cov_89_reg++;
                end
                8'h8A: cov_8a_reg++;
                8'h8B: begin
                    if (pref66) cov_66_8b_reg++;
                    else cov_8b_reg++;
                end
                default: ;
            endcase
        end
    endtask

    task automatic append_addr_setup(input int cls, input logic [31:0] target);
        begin
            append_mov32_imm(3'h3, setup_ebx(cls, target), 1'b0);
            append_mov32_imm(3'h5, setup_ebp(cls, target), 1'b0);
            append_mov32_imm(3'h6, setup_esi(cls, target), 1'b0);
            append_mov32_imm(3'h7, setup_edi(cls, target), 1'b0);
        end
    endtask

    task automatic emit_mem_ea(input int cls, input logic [2:0] reg_field);
        logic [31:0] target;
        begin
            target = class_target_addr(cls, data_seq);
            case (cls)
                0: begin
                    emit8({2'b00, reg_field, 3'b101});
                    emit32(target);
                end
                1: emit8({2'b00, reg_field, 3'b011});
                2: begin
                    emit8({2'b01, reg_field, 3'b011});
                    emit8(8'hF9);
                end
                3: begin
                    emit8({2'b10, reg_field, 3'b101});
                    emit32(32'h00000123);
                end
                4: begin
                    emit8({2'b00, reg_field, 3'b100});
                    emit8({2'b00, 3'b100, 3'b011});
                end
                5: begin
                    emit8({2'b00, reg_field, 3'b100});
                    emit8({2'b00, 3'b100, 3'b101});
                    emit32(target);
                end
                6: begin
                    emit8({2'b00, reg_field, 3'b100});
                    emit8({2'b10, 3'b110, 3'b011});
                end
                7: begin
                    emit8({2'b00, reg_field, 3'b100});
                    emit8({2'b01, 3'b111, 3'b101});
                    emit32(target - 32'd10);
                end
                8: begin
                    emit8({2'b00, reg_field, 3'b110});
                    emit16(target[15:0]);
                end
                9: emit8({2'b00, reg_field, 3'b000});
                10: emit8({2'b00, reg_field, 3'b010});
                11: begin
                    emit8({2'b01, reg_field, 3'b111});
                    emit8(8'hFB);
                end
                default: begin
                    emit8({2'b10, reg_field, 3'b001});
                    emit16(16'h0100);
                end
            endcase
        end
    endtask

    task automatic append_reg_mem(input int cls, int width, input logic [2:0] dst);
        logic [31:0] addr;
        logic [31:0] val;
        begin
            addr = class_target_addr(cls, data_seq);
            val = matrix_imm(data_seq + dst + (width * 17), width);
            write_data32(addr, val);
            append_addr_setup(cls, addr);
            if (cls >= 8) begin
                if (width == W16)
                    emit8(8'h66);
                emit8(8'h67);
            end else if (width == W16) begin
                emit8(8'h66);
            end
            emit8((width == W8) ? 8'h8A : 8'h8B);
            emit_mem_ea(cls, dst);
            record_op(OP_MEM_LOAD, width, dst, 3'h0, 32'h0, addr);
            if (width == W8) cov_regmem8++;
            else if (width == W16) cov_regmem16++;
            else cov_regmem32++;
            cov_regmem_class[cls]++;
            data_seq++;
        end
    endtask

    task automatic append_mem_reg(input int cls, int width, input logic [2:0] src);
        logic [31:0] addr;
        begin
            addr = class_target_addr(cls, data_seq);
            write_data32(addr, 32'h55555555 ^ ({20'h0, data_seq[11:0]} * 32'h10101));
            append_addr_setup(cls, addr);
            if (cls >= 8) begin
                if (width == W16)
                    emit8(8'h66);
                emit8(8'h67);
            end else if (width == W16) begin
                emit8(8'h66);
            end
            emit8((width == W8) ? 8'h88 : 8'h89);
            emit_mem_ea(cls, src);
            record_op(OP_MEM_STORE, width, 3'h0, src, 32'h0, addr);
            if (width == W8) cov_memreg8++;
            else if (width == W16) cov_memreg16++;
            else cov_memreg32++;
            cov_memreg_class[cls]++;
            data_seq++;
        end
    endtask

    task automatic append_mem_imm(input int cls, int width);
        logic [31:0] addr;
        logic [31:0] imm;
        begin
            addr = class_target_addr(cls, data_seq);
            imm = matrix_imm(data_seq + (width * 31), width);
            write_data32(addr, 32'hAAAAAAAA ^ ({20'h0, data_seq[11:0]} * 32'h01010101));
            append_addr_setup(cls, addr);
            if (cls >= 8) begin
                if (width == W16)
                    emit8(8'h66);
                emit8(8'h67);
            end else if (width == W16) begin
                emit8(8'h66);
            end
            emit8((width == W8) ? 8'hC6 : 8'hC7);
            emit_mem_ea(cls, 3'b000);
            if (width == W8)
                emit8(imm[7:0]);
            else if (width == W16)
                emit16(imm[15:0]);
            else
                emit32(imm);
            record_op(OP_MEM_STORE, width, 3'h0, 3'h0, imm, addr);
            if (width == W8) cov_memimm8++;
            else if (width == W16) cov_memimm16++;
            else cov_memimm32++;
            cov_memimm_class[cls]++;
            data_seq++;
        end
    endtask

    task automatic apply_expected(input int idx);
        logic [31:0] val;
        logic [2:0] commit_idx;
        logic [3:0] be;
        begin
            case (op_kind[idx])
                OP_GPR_IMM: begin
                    commit_idx = (op_width[idx] == W8) ? {1'b0, op_dst[idx][1:0]} :
                                                         op_dst[idx];
                    ref_gpr[commit_idx] = merge_gpr(ref_gpr[commit_idx],
                                                    op_dst[idx], op_width[idx],
                                                    op_value[idx]);
                end
                OP_REG_COPY: begin
                    val = read_gpr_width(op_src[idx], op_width[idx]);
                    commit_idx = (op_width[idx] == W8) ? {1'b0, op_dst[idx][1:0]} :
                                                         op_dst[idx];
                    ref_gpr[commit_idx] = merge_gpr(ref_gpr[commit_idx],
                                                    op_dst[idx], op_width[idx],
                                                    val);
                end
                OP_MEM_LOAD: begin
                    val = read_ref_mem32(op_addr[idx]);
                    commit_idx = (op_width[idx] == W8) ? {1'b0, op_dst[idx][1:0]} :
                                                         op_dst[idx];
                    ref_gpr[commit_idx] = merge_gpr(ref_gpr[commit_idx],
                                                    op_dst[idx], op_width[idx],
                                                    val);
                end
                OP_MEM_STORE: begin
                    val = (op_value[idx] != 32'h0) ? op_value[idx] :
                          read_gpr_width(op_src[idx], op_width[idx]);
                    be = byteen_for_width(op_width[idx]);
                    if (expected_store_count < MAX_STORES) begin
                        expected_store_addr[expected_store_count] = op_addr[idx];
                        expected_store_data[expected_store_count] = val;
                        expected_store_be[expected_store_count] = be;
                    end else begin
                        $fatal(1, "MOV matrix expected store table overflow");
                    end
                    expected_store_count++;
                    if (be[0]) ref_mem[pa16(op_addr[idx] + 32'd0)] = val[7:0];
                    if (be[1]) ref_mem[pa16(op_addr[idx] + 32'd1)] = val[15:8];
                    if (be[2]) ref_mem[pa16(op_addr[idx] + 32'd2)] = val[23:16];
                    if (be[3]) ref_mem[pa16(op_addr[idx] + 32'd3)] = val[31:24];
                end
                default: ;
            endcase
        end
    endtask

    task automatic build_program;
        begin
            $display("  section: reg-imm");
            for (int r = 0; r < 8; r++)
                append_mov32_imm(r[2:0], seed32(r), 1'b1);
            for (int r = 0; r < 8; r++)
                append_mov8_imm(r[2:0], matrix_imm(r, W8));
            for (int r = 0; r < 8; r++)
                append_mov16_imm(r[2:0], matrix_imm(r, W16));
            for (int r = 0; r < 8; r++)
                append_c6_mod11(r[2:0], (8'h90 ^ r[7:0]));
            for (int r = 0; r < 8; r++)
                append_c7_mod11(r[2:0], 32'h70000000 ^ ({24'h0, r[7:0]} * 32'h01020304));
            for (int r = 0; r < 8; r++)
                append_66_c7_mod11(r[2:0], 16'h3300 ^ ({8'h0, r[7:0]} * 16'h0107));

            $display("  section: reg-reg");
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h88, W8, dst[2:0], src[2:0], 1'b0);
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h8A, W8, dst[2:0], src[2:0], 1'b0);
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h89, W32, dst[2:0], src[2:0], 1'b0);
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h8B, W32, dst[2:0], src[2:0], 1'b0);
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h89, W16, dst[2:0], src[2:0], 1'b1);
            for (int dst = 0; dst < 8; dst++)
                for (int src = 0; src < 8; src++)
                    append_reg_reg(8'h8B, W16, dst[2:0], src[2:0], 1'b1);

            $display("  section: reg-mem");
            for (int cls = 0; cls < ADDR_CLASSES; cls++) begin
                for (int r = 0; r < 8; r++)
                    append_reg_mem(cls, W8, r[2:0]);
                for (int r = 0; r < 8; r++)
                    append_reg_mem(cls, W32, r[2:0]);
                for (int r = 0; r < 8; r++)
                    append_reg_mem(cls, W16, r[2:0]);
            end

            $display("  section: mem-reg");
            for (int cls = 0; cls < ADDR_CLASSES; cls++) begin
                for (int r = 0; r < 8; r++)
                    append_mem_reg(cls, W8, r[2:0]);
                for (int r = 0; r < 8; r++)
                    append_mem_reg(cls, W32, r[2:0]);
                for (int r = 0; r < 8; r++)
                    append_mem_reg(cls, W16, r[2:0]);
            end

            $display("  section: mem-imm");
            for (int cls = 0; cls < ADDR_CLASSES; cls++) begin
                append_mem_imm(cls, W8);
                append_mem_imm(cls, W32);
                append_mem_imm(cls, W16);
            end

            program_end_eip = program_pc;
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
        input string name,
        input logic expect_prefix_boundary
    );
        logic saw_boundary;
        logic saw_mov_endi;
        logic saw_bus_wr;
        begin
            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = b0;
            ref_mem[pa16(RESET_EIP + 32'd0)] = b0;
            if (len > 1) begin mem[pa16(RESET_EIP + 32'd1)] = b1; ref_mem[pa16(RESET_EIP + 32'd1)] = b1; end
            if (len > 2) begin mem[pa16(RESET_EIP + 32'd2)] = b2; ref_mem[pa16(RESET_EIP + 32'd2)] = b2; end
            if (len > 3) begin mem[pa16(RESET_EIP + 32'd3)] = b3; ref_mem[pa16(RESET_EIP + 32'd3)] = b3; end
            if (len > 4) begin mem[pa16(RESET_EIP + 32'd4)] = b4; ref_mem[pa16(RESET_EIP + 32'd4)] = b4; end
            if (len > 5) begin mem[pa16(RESET_EIP + 32'd5)] = b5; ref_mem[pa16(RESET_EIP + 32'd5)] = b5; end

            saw_boundary = 1'b0;
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
                         (expect_prefix_boundary ? ENTRY_PREFIX_ID : ENTRY_NULL_ID))) begin
                        saw_boundary = 1'b1;
                        disable wait_unsupported;
                    end
                end
            end

            check({name, expect_prefix_boundary ? " stops at prefix-only boundary" :
                                               " routes to ENTRY_NULL"},
                  saw_boundary);
            check({name, " does not ENDI as MOV"}, !saw_mov_endi);
            check({name, " issues no bus write before unsupported boundary"}, !saw_bus_wr);
        end
    endtask

    task automatic check_coverage;
        begin
            check("B0-B7 MOV r8, imm8 covered for all destinations", cov_b0_imm8 == 8);
            check("B8-BF MOV r32, imm32 covered for all destinations", cov_b8_imm32 == 8);
            check("66+B8-BF MOV r16, imm16 covered for all destinations", cov_66_b8_imm16 == 8);
            check("C6 /0 ModRM.mod=11 covered for all destinations", cov_c6_mod11 == 8);
            check("C7 /0 ModRM.mod=11 covered for all destinations", cov_c7_mod11 == 8);
            check("66+C7 /0 ModRM.mod=11 covered for all destinations", cov_66_c7_mod11 == 8);
            check("88 register-register 8-bit matrix covered", cov_88_reg == 64);
            check("8A register-register 8-bit matrix covered", cov_8a_reg == 64);
            check("89 register-register 32-bit matrix covered", cov_89_reg == 64);
            check("8B register-register 32-bit matrix covered", cov_8b_reg == 64);
            check("66+89 register-register 16-bit matrix covered", cov_66_89_reg == 64);
            check("66+8B register-register 16-bit matrix covered", cov_66_8b_reg == 64);
            check("8A memory-source matrix covers all register destinations/classes", cov_regmem8 == 104);
            check("8B memory-source matrix covers all register destinations/classes", cov_regmem32 == 104);
            check("66+8B memory-source matrix covers all register destinations/classes", cov_regmem16 == 104);
            check("88 memory-destination matrix covers all register sources/classes", cov_memreg8 == 104);
            check("89 memory-destination matrix covers all register sources/classes", cov_memreg32 == 104);
            check("66+89 memory-destination matrix covers all register sources/classes", cov_memreg16 == 104);
            check("C6 memory-immediate matrix covers all addressing classes", cov_memimm8 == 13);
            check("C7 memory-immediate matrix covers all addressing classes", cov_memimm32 == 13);
            check("66+C7 memory-immediate matrix covers all addressing classes", cov_memimm16 == 13);
            for (int cls = 0; cls < ADDR_CLASSES; cls++) begin
                check("each addressing class covered by reg-mem forms",
                      cov_regmem_class[cls] == 24);
                check("each addressing class covered by mem-reg forms",
                      cov_memreg_class[cls] == 24);
                check("each addressing class covered by mem-imm forms",
                      cov_memimm_class[cls] == 3);
            end
        end
    endtask

    initial begin
        failures = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;
        bus_wr_pending = 1'b0;
        bus_wr_observed_active = 1'b0;
        bus_addr_pending = 32'h0;
        bus_byteen_pending = 4'h0;
        bus_dout_pending = 32'h0;
        observed_store_count = 0;
        expected_store_count = 0;
        extra_store_seen = 1'b0;
        completed_ops = 0;
        data_seq = 0;
        op_count = 0;
        eflags_changed = 1'b0;
        gpr_mismatch_seen = 1'b0;
        store_addr_match = 1'b1;
        store_be_match = 1'b1;
        store_data_match = 1'b1;

        cov_b0_imm8 = 0;
        cov_b8_imm32 = 0;
        cov_66_b8_imm16 = 0;
        cov_c6_mod11 = 0;
        cov_c7_mod11 = 0;
        cov_66_c7_mod11 = 0;
        cov_88_reg = 0;
        cov_89_reg = 0;
        cov_8a_reg = 0;
        cov_8b_reg = 0;
        cov_66_89_reg = 0;
        cov_66_8b_reg = 0;
        cov_regmem8 = 0;
        cov_regmem16 = 0;
        cov_regmem32 = 0;
        cov_memreg8 = 0;
        cov_memreg16 = 0;
        cov_memreg32 = 0;
        cov_memimm8 = 0;
        cov_memimm16 = 0;
        cov_memimm32 = 0;
        for (int i = 0; i < ADDR_CLASSES; i++) begin
            cov_regmem_class[i] = 0;
            cov_memreg_class[i] = 0;
            cov_memimm_class[i] = 0;
        end
        for (int i = 0; i < 8; i++)
            ref_gpr[i] = 32'h0;
        for (int i = 0; i < MAX_STORES; i++) begin
            observed_store_addr[i] = 32'h0;
            observed_store_data[i] = 32'h0;
            observed_store_be[i] = 4'h0;
            expected_store_addr[i] = 32'h0;
            expected_store_data[i] = 32'h0;
            expected_store_be[i] = 4'h0;
        end

        clear_memory();
        program_pc = RESET_EIP;

        $display("Keystone86 / Aegis - Rung 6 Appendix D MOV Matrix");
        build_program();
        check_coverage();

        timed_out = 1'b1;
        reset_cpu();

        begin : wait_matrix
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (dut.u_commit.eflags_r != 32'h00000002)
                    eflags_changed = 1'b1;

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    apply_expected(completed_ops);
                    if (dbg_eip != op_next_eip[completed_ops]) begin
                        $display("  [FAIL] EIP advance mismatch at op %0d actual=%08X expected=%08X",
                                 completed_ops, dbg_eip, op_next_eip[completed_ops]);
                        failures++;
                    end
                    if (!gprs_match_ref())
                        gpr_mismatch_seen = 1'b1;
                    completed_ops++;
                    if (completed_ops == op_count) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_matrix;
                    end
                end
            end
        end

        check("all emitted MOV operations completed", !timed_out && (completed_ops == op_count));
        check("final EIP matches table oracle", dbg_eip == program_end_eip);
        check("EFLAGS unchanged by every MOV", !eflags_changed && (dut.u_commit.eflags_r == 32'h00000002));
        check("final GPR state matches oracle", gprs_match_ref() && !gpr_mismatch_seen);
        if (!gprs_match_ref()) begin
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== ref_gpr[i])
                    $display("    GPR[%0d] actual=%08X expected=%08X",
                             i, dut.u_commit.gpr_r[i], ref_gpr[i]);
            end
        end
        check("no fault after MOV matrix", !dbg_fault_pending);
        check("no extra memory store observed", !extra_store_seen);
        check("observed store count matches oracle", observed_store_count == expected_store_count);
        for (int i = 0; i < expected_store_count; i++) begin
            if (observed_store_addr[i] != expected_store_addr[i])
                store_addr_match = 1'b0;
            if (observed_store_be[i] != expected_store_be[i])
                store_be_match = 1'b0;
            if (mask_store_data(observed_store_data[i], observed_store_be[i]) !=
                mask_store_data(expected_store_data[i], expected_store_be[i]))
                store_data_match = 1'b0;
        end
        check("all store bus addresses match oracle", store_addr_match);
        check("all store bus byte enables match oracle", store_be_match);
        check("all store bus data bytes match oracle", store_data_match);

        $display("  section: unsupported-adjacent forms");
        run_unsupported_form(3, 8'h67, 8'h8B, 8'hC0, 8'h00, 8'h00, 8'h00,
                             "0x67 + ModRM.mod=11", 1'b0);
        run_unsupported_form(6, 8'hC6, 8'h08, 8'h00, 8'h90, 8'h00, 8'h00,
                             "C6 non-/0", 1'b0);
        run_unsupported_form(6, 8'hC7, 8'h08, 8'h00, 8'h90, 8'h00, 8'h00,
                             "C7 non-/0", 1'b0);
        run_unsupported_form(6, 8'h67, 8'h66, 8'h8B, 8'h80, 8'h34, 8'h12,
                             "unsupported 67+66 prefix order", 1'b1);

        if (failures == 0) begin
            $display("PASS: Rung 6 Appendix D MOV matrix completed");
        end else begin
            $display("FAIL: Rung 6 Appendix D MOV matrix had %0d failure(s)", failures);
            $fatal(1, "Rung 6 MOV matrix failed");
        end

        $finish;
    end

endmodule
