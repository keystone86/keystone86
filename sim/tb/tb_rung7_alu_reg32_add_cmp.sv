// Keystone86 / Aegis
// sim/tb/tb_rung7_alu_reg32_add_cmp.sv
// Focused Rung 7 smoke: 01/03 /r ADD, 29/2B /r SUB, and 39/3B /r CMP
// register-register only.
//
// Each case seeds committed architectural state before the tested instruction.
// The checks then prove operands are loaded before the bounded ALU service,
// architectural GPR/EFLAGS visibility waits until ENDI, and unsupported
// adjacent forms do not dispatch through either bounded ALU entry.

`timescale 1ns/1ps

module tb_rung7_alu_reg32_add_cmp;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int CASE_TIMEOUT    = 2500;

    localparam logic [31:0] RESET_EIP         = 32'hFFFFFFF0;
    localparam logic [7:0]  ENTRY_NULL_ID     = 8'h00;
    localparam logic [7:0]  ENTRY_ALU_RM_R_ID = 8'h02;
    localparam logic [7:0]  ENTRY_ALU_R_RM_ID = 8'h03;
    localparam logic [7:0]  SVC_LOAD_REG_META = 8'h26;
    localparam logic [7:0]  SVC_ALU_ADD32     = 8'h32;
    localparam logic [7:0]  SVC_ALU_SUB32     = 8'h35;
    localparam logic [7:0]  SVC_ALU_CMP32     = 8'h3B;
    localparam logic [9:0]  CM_ALU_REG_MASK   = 10'h1C5;
    localparam logic [9:0]  CM_FLAGS_MASK     = 10'h1C4;
    localparam logic [31:0] ALU_EFLAGS_MASK   = 32'h000008D5;

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
    int          failures;
    int          case_count;
    int          add_case_count;
    int          sub_case_count;
    int          cmp_case_count;
    int          unsupported_count;
    logic [31:0] before_gpr_snapshot [0:7];
    logic [31:0] expected_gpr_snapshot [0:7];

    initial clk = 1'b0;
    always #CLK_HALF_PERIOD clk = ~clk;

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

    task automatic clear_memory;
        for (int i = 0; i < 65536; i++)
            mem[i] = 8'h90;
    endtask

    task automatic reset_cpu;
        reset_n = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    function automatic logic [31:0] seeded_eflags;
        return 32'h00000702;
    endfunction

    task automatic seed_arch_state(input logic [2:0] dst,
                                   input logic [31:0] dst_val,
                                   input logic [2:0] src,
                                   input logic [31:0] src_val);
        begin
            for (int i = 0; i < 8; i++)
                dut.u_commit.gpr_r[i] = 32'hA5A50000 ^ {29'h0, i[2:0]};
            dut.u_commit.gpr_r[dst] = dst_val;
            dut.u_commit.gpr_r[src] = src_val;
            dut.u_commit.eflags_r   = seeded_eflags();
        end
    endtask

    function automatic logic even_parity8(input logic [7:0] value);
        return ~^value;
    endfunction

    function automatic logic [31:0] flags_add32(input logic [31:0] a,
                                                input logic [31:0] b);
        logic [32:0] wide;
        logic [31:0] result;
        logic [31:0] flags;
        begin
            wide = {1'b0, a} + {1'b0, b};
            result = wide[31:0];
            flags = 32'h0;
            flags[0]  = wide[32];
            flags[2]  = even_parity8(result[7:0]);
            flags[4]  = (a[4] ^ b[4] ^ result[4]);
            flags[6]  = (result == 32'h0);
            flags[7]  = result[31];
            flags[11] = ((a[31] == b[31]) && (result[31] != a[31]));
            return flags;
        end
    endfunction

    function automatic logic [31:0] flags_sub32(input logic [31:0] a,
                                                input logic [31:0] b);
        logic [31:0] result;
        logic [31:0] flags;
        begin
            result = a - b;
            flags = 32'h0;
            flags[0]  = (a < b);
            flags[2]  = even_parity8(result[7:0]);
            flags[4]  = (a[4] ^ b[4] ^ result[4]);
            flags[6]  = (result == 32'h0);
            flags[7]  = result[31];
            flags[11] = ((a[31] != b[31]) && (result[31] != a[31]));
            return flags;
        end
    endfunction

    function automatic logic [31:0] merge_flags(input logic [31:0] old_flags,
                                                input logic [31:0] candidate);
        return (old_flags & ~ALU_EFLAGS_MASK) | (candidate & ALU_EFLAGS_MASK);
    endfunction

    function automatic logic gprs_match_before_snapshot;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== before_gpr_snapshot[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    function automatic logic gprs_match_expected_snapshot;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== expected_gpr_snapshot[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    function automatic logic [7:0] modrm_rr(input logic [2:0] rm,
                                            input logic [2:0] reg_id);
        return {2'b11, reg_id, rm};
    endfunction

    task automatic run_alu_case(input string name,
                                input logic [7:0] opcode,
                                input bit is_sub,
                                input bit is_cmp,
                                input bit dest_is_reg_field,
                                input logic [2:0] dst,
                                input logic [2:0] src,
                                input logic [31:0] dst_val,
                                input logic [31:0] src_val);
        logic [7:0] expected_entry;
        logic [7:0] wrong_entry;
        logic [31:0] before_flags;
        logic [31:0] expected_flags;
        logic [31:0] result;
        logic [31:0] candidate_flags;
        int cycles;
        int load_count;
        int alu_count;
        int wrong_alu_count;
        int alu_route_count;
        int wrong_route_count;
        int alu_endi_count;
        int wrong_endi_count;
        int bus_wr_count;
        bit timed_out;
        bit early_gpr_visible;
        bit early_eflags_visible;
        begin
            case_count++;
            if (is_cmp)
                cmp_case_count++;
            else if (is_sub)
                sub_case_count++;
            else
                add_case_count++;

            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = opcode;
            mem[pa16(RESET_EIP + 32'd1)] = dest_is_reg_field ?
                                           modrm_rr(src, dst) :
                                           modrm_rr(dst, src);

            reset_cpu();
            seed_arch_state(dst, dst_val, src, src_val);

            for (int i = 0; i < 8; i++) begin
                before_gpr_snapshot[i] = dut.u_commit.gpr_r[i];
                expected_gpr_snapshot[i] = dut.u_commit.gpr_r[i];
            end
            before_flags = dut.u_commit.eflags_r;

            if (is_cmp || is_sub) begin
                result = dst_val - src_val;
                candidate_flags = flags_sub32(dst_val, src_val);
                if (is_sub)
                    expected_gpr_snapshot[dst] = result;
            end else begin
                result = dst_val + src_val;
                candidate_flags = flags_add32(dst_val, src_val);
                expected_gpr_snapshot[dst] = result;
            end
            expected_flags = merge_flags(before_flags, candidate_flags);

            load_count = 0;
            alu_count = 0;
            wrong_alu_count = 0;
            alu_route_count = 0;
            wrong_route_count = 0;
            alu_endi_count = 0;
            wrong_endi_count = 0;
            bus_wr_count = 0;
            timed_out = 1'b1;
            early_gpr_visible = 1'b0;
            early_eflags_visible = 1'b0;
            expected_entry = dest_is_reg_field ? ENTRY_ALU_R_RM_ID :
                                                 ENTRY_ALU_RM_R_ID;
            wrong_entry = dest_is_reg_field ? ENTRY_ALU_RM_R_ID :
                                             ENTRY_ALU_R_RM_ID;

            begin : wait_case
                for (cycles = 0; cycles < CASE_TIMEOUT; cycles++) begin
                    @(posedge clk);
                    #1;

                    if (bus_wr)
                        bus_wr_count++;

                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch == expected_entry))
                        alu_route_count++;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch == wrong_entry))
                        wrong_route_count++;

                    if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_REG_META))
                        load_count++;

                    if (dut.svc_req_out &&
                        (dut.svc_id_out == (is_cmp ? SVC_ALU_CMP32 :
                                            (is_sub ? SVC_ALU_SUB32 :
                                                      SVC_ALU_ADD32))))
                        alu_count++;
                    if (dut.svc_req_out &&
                        (((!is_cmp) && (dut.svc_id_out == SVC_ALU_CMP32)) ||
                         ((!is_sub) && (dut.svc_id_out == SVC_ALU_SUB32)) ||
                         ((is_sub || is_cmp) && (dut.svc_id_out == SVC_ALU_ADD32))))
                        wrong_alu_count++;

                    if (dut.endi_req &&
                        (dut.endi_mask == (is_cmp ? CM_FLAGS_MASK :
                                                   CM_ALU_REG_MASK)))
                        alu_endi_count++;
                    if (dut.endi_req &&
                        (((!is_cmp) && (dut.endi_mask == CM_FLAGS_MASK)) ||
                         (is_cmp && (dut.endi_mask == CM_ALU_REG_MASK))))
                        wrong_endi_count++;

                    if (dbg_endi_pulse && (dbg_entry_id == expected_entry)) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_case;
                    end else begin
                        if (!gprs_match_before_snapshot())
                            early_gpr_visible = 1'b1;
                        if (dut.u_commit.eflags_r !== before_flags)
                            early_eflags_visible = 1'b1;
                    end
                end
            end

            check({name, " completed"}, !timed_out);
            check({name, dest_is_reg_field ? " routed to ENTRY_ALU_R_RM once" :
                                             " routed to ENTRY_ALU_RM_R once"},
                  alu_route_count == 1);
            check({name, " did not route to opposite ALU entry"},
                  wrong_route_count == 0);
            check({name, " loaded two explicit register operands"}, load_count == 2);
            check({name, " invoked one expected bounded ALU service"}, alu_count == 1);
            check({name, " did not invoke another ALU service"}, wrong_alu_count == 0);
            check({name, is_cmp ? " used CM_FLAGS" : " used CM_ALU_REG"},
                  alu_endi_count > 0);
            check({name, is_cmp ? " did not use CM_ALU_REG" : " did not use CM_FLAGS"},
                  wrong_endi_count == 0);
            check({name, " issued no memory write bus request"}, bus_wr_count == 0);
            check({name, " no early GPR visibility"}, !early_gpr_visible);
            check({name, " no early EFLAGS visibility"}, !early_eflags_visible);
            check({name, " final EIP is EIP+2"}, dbg_eip == (RESET_EIP + 32'd2));
            check({name, " final GPR state"}, gprs_match_expected_snapshot());
            check({name, " destination write policy"},
                  is_cmp ? (dut.u_commit.gpr_r[dst] == dst_val) :
                           (dut.u_commit.gpr_r[dst] == result));
            check({name, " final masked flags"},
                  ((dut.u_commit.eflags_r & ALU_EFLAGS_MASK) ==
                   (expected_flags & ALU_EFLAGS_MASK)));
            check({name, " unrelated EFLAGS bits preserved"},
                  ((dut.u_commit.eflags_r & ~ALU_EFLAGS_MASK) ==
                   (before_flags & ~ALU_EFLAGS_MASK)));
            check({name, " no fault"}, !dbg_fault_pending);

            if ((dut.u_commit.eflags_r & ALU_EFLAGS_MASK) !=
                (expected_flags & ALU_EFLAGS_MASK)) begin
                $display("    flags actual=%08X expected=%08X candidate=%08X",
                         dut.u_commit.eflags_r, expected_flags, candidate_flags);
            end
        end
    endtask

    task automatic run_unsupported(input string name,
                                   input logic [7:0] b0,
                                   input logic [7:0] b1,
                                   input logic [7:0] b2,
                                   input logic [7:0] b3,
                                   input logic [7:0] b4,
                                   input logic [7:0] b5);
        logic [31:0] before_flags;
        bit saw_entry_null;
        bit saw_alu_entry;
        bit saw_alu_service;
        bit saw_alu_endi;
        bit saw_bus_wr;
        begin
            unsupported_count++;
            clear_memory();
            mem[pa16(RESET_EIP + 32'd0)] = b0;
            mem[pa16(RESET_EIP + 32'd1)] = b1;
            mem[pa16(RESET_EIP + 32'd2)] = b2;
            mem[pa16(RESET_EIP + 32'd3)] = b3;
            mem[pa16(RESET_EIP + 32'd4)] = b4;
            mem[pa16(RESET_EIP + 32'd5)] = b5;

            reset_cpu();
            seed_arch_state(3'd0, 32'h11223344, 3'd3, 32'h55667788);
            for (int i = 0; i < 8; i++)
                before_gpr_snapshot[i] = dut.u_commit.gpr_r[i];
            before_flags = dut.u_commit.eflags_r;

            saw_entry_null = 1'b0;
            saw_alu_entry = 1'b0;
            saw_alu_service = 1'b0;
            saw_alu_endi = 1'b0;
            saw_bus_wr = 1'b0;

            begin : wait_unsupported
                for (int c = 0; c < CASE_TIMEOUT; c++) begin
                    @(posedge clk);
                    #1;

                    if (bus_wr)
                        saw_bus_wr = 1'b1;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        ((dut.u_mseq.dispatch_entry_latch == ENTRY_ALU_RM_R_ID) ||
                         (dut.u_mseq.dispatch_entry_latch == ENTRY_ALU_R_RM_ID)))
                        saw_alu_entry = 1'b1;
                    if (dut.svc_req_out &&
                        ((dut.svc_id_out == SVC_ALU_ADD32) ||
                         (dut.svc_id_out == SVC_ALU_SUB32) ||
                         (dut.svc_id_out == SVC_ALU_CMP32)))
                        saw_alu_service = 1'b1;
                    if (dut.endi_req &&
                        ((dut.endi_mask == CM_ALU_REG_MASK) ||
                         (dut.endi_mask == CM_FLAGS_MASK)))
                        saw_alu_endi = 1'b1;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch == ENTRY_NULL_ID)) begin
                        saw_entry_null = 1'b1;
                        disable wait_unsupported;
                    end
                end
            end

            check({name, " routes to ENTRY_NULL"}, saw_entry_null);
            check({name, " does not route to bounded ALU entries"}, !saw_alu_entry);
            check({name, " does not invoke ALU service"}, !saw_alu_service);
            check({name, " does not use ALU ENDI masks"}, !saw_alu_endi);
            check({name, " issues no bus write before unsupported dispatch"}, !saw_bus_wr);
            check({name, " leaves GPRs unchanged before unsupported dispatch"},
                  gprs_match_before_snapshot());
            check({name, " leaves EFLAGS unchanged before unsupported dispatch"},
                  dut.u_commit.eflags_r == before_flags);
        end
    endtask

    initial begin
        failures = 0;
        case_count = 0;
        add_case_count = 0;
        cmp_case_count = 0;
        sub_case_count = 0;
        unsupported_count = 0;
        reset_n = 1'b0;
        bus_ready = 1'b0;
        bus_din = 32'h0;
        bus_pending = 1'b0;
        bus_wr_pending = 1'b0;
        bus_addr_pending = 32'h0;
        clear_memory();

        $display("Keystone86 / Aegis - Rung 7 focused ADD/SUB/CMP reg32 Smoke");

        run_alu_case("ADD 01 /r 7fffffff+1 OF/SF/AF/PF", 8'h01, 1'b0, 1'b0, 1'b0,
                     3'd0, 3'd3, 32'h7FFFFFFF, 32'h00000001);
        run_alu_case("ADD 01 /r ffffffff+1 CF/ZF/AF/PF", 8'h01, 1'b0, 1'b0, 1'b0,
                     3'd1, 3'd2, 32'hFFFFFFFF, 32'h00000001);
        run_alu_case("ADD 01 /r 0000000f+1 AF/PF clear", 8'h01, 1'b0, 1'b0, 1'b0,
                     3'd6, 3'd7, 32'h0000000F, 32'h00000001);
        run_alu_case("ADD 03 /r 7fffffff+1 OF/SF/AF/PF", 8'h03, 1'b0, 1'b0, 1'b1,
                     3'd0, 3'd3, 32'h7FFFFFFF, 32'h00000001);
        run_alu_case("ADD 03 /r ffffffff+1 CF/ZF/AF/PF", 8'h03, 1'b0, 1'b0, 1'b1,
                     3'd1, 3'd2, 32'hFFFFFFFF, 32'h00000001);
        run_alu_case("ADD 03 /r 0000000f+1 AF/PF clear", 8'h03, 1'b0, 1'b0, 1'b1,
                     3'd6, 3'd7, 32'h0000000F, 32'h00000001);
        run_alu_case("SUB 29 /r 5-3 normal", 8'h29, 1'b1, 1'b0, 1'b0,
                     3'd4, 3'd5, 32'h00000005, 32'h00000003);
        run_alu_case("SUB 29 /r 0-1 CF/SF/AF/PF", 8'h29, 1'b1, 1'b0, 1'b0,
                     3'd0, 3'd3, 32'h00000000, 32'h00000001);
        run_alu_case("SUB 29 /r 80000000-1 OF/AF/PF", 8'h29, 1'b1, 1'b0, 1'b0,
                     3'd1, 3'd2, 32'h80000000, 32'h00000001);
        run_alu_case("SUB 29 /r equal ZF/PF", 8'h29, 1'b1, 1'b0, 1'b0,
                     3'd6, 3'd7, 32'h12345678, 32'h12345678);
        run_alu_case("SUB 2B /r 5-3 normal", 8'h2B, 1'b1, 1'b0, 1'b1,
                     3'd4, 3'd5, 32'h00000005, 32'h00000003);
        run_alu_case("SUB 2B /r 0-1 CF/SF/AF/PF", 8'h2B, 1'b1, 1'b0, 1'b1,
                     3'd0, 3'd3, 32'h00000000, 32'h00000001);
        run_alu_case("SUB 2B /r 80000000-1 OF/AF/PF", 8'h2B, 1'b1, 1'b0, 1'b1,
                     3'd1, 3'd2, 32'h80000000, 32'h00000001);
        run_alu_case("SUB 2B /r equal ZF/PF", 8'h2B, 1'b1, 1'b0, 1'b1,
                     3'd6, 3'd7, 32'h12345678, 32'h12345678);
        run_alu_case("CMP 39 /r 0-1 CF/SF/AF/PF", 8'h39, 1'b0, 1'b1, 1'b0,
                     3'd0, 3'd3, 32'h00000000, 32'h00000001);
        run_alu_case("CMP 39 /r 80000000-1 OF/AF/PF", 8'h39, 1'b0, 1'b1, 1'b0,
                     3'd1, 3'd2, 32'h80000000, 32'h00000001);
        run_alu_case("CMP 39 /r equal ZF/PF", 8'h39, 1'b0, 1'b1, 1'b0,
                     3'd6, 3'd7, 32'h12345678, 32'h12345678);
        run_alu_case("CMP 3B /r 0-1 CF/SF/AF/PF", 8'h3B, 1'b0, 1'b1, 1'b1,
                     3'd0, 3'd3, 32'h00000000, 32'h00000001);
        run_alu_case("CMP 3B /r 80000000-1 OF/AF/PF", 8'h3B, 1'b0, 1'b1, 1'b1,
                     3'd1, 3'd2, 32'h80000000, 32'h00000001);
        run_alu_case("CMP 3B /r equal ZF/PF", 8'h3B, 1'b0, 1'b1, 1'b1,
                     3'd6, 3'd7, 32'h12345678, 32'h12345678);

        run_unsupported("00 /r byte ADD", 8'h00, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("02 /r byte opposite ADD direction", 8'h02, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("38 /r byte CMP", 8'h38, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("3A /r byte opposite CMP direction", 8'h3A, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("28 /r byte SUB", 8'h28, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("2A /r byte opposite SUB direction", 8'h2A, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 01 /r operand override ADD", 8'h66, 8'h01, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 03 /r operand override ADD", 8'h66, 8'h03, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 29 /r operand override SUB", 8'h66, 8'h29, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 2B /r operand override SUB", 8'h66, 8'h2B, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 39 /r operand override CMP", 8'h66, 8'h39, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("66 3B /r operand override CMP", 8'h66, 8'h3B, 8'hD8, 8'h90, 8'h90, 8'h90);
        run_unsupported("81 /0 id immediate ADD", 8'h81, 8'hC0, 8'h78, 8'h56, 8'h34, 8'h12);
        run_unsupported("83 /7 ib immediate CMP", 8'h83, 8'hF8, 8'h7F, 8'h90, 8'h90, 8'h90);
        run_unsupported("05 id accumulator ADD", 8'h05, 8'h78, 8'h56, 8'h34, 8'h12, 8'h90);
        run_unsupported("3D id accumulator CMP", 8'h3D, 8'h78, 8'h56, 8'h34, 8'h12, 8'h90);
        run_unsupported("29 /r memory ModRM", 8'h29, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("2B /r memory ModRM", 8'h2B, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("2D id accumulator SUB", 8'h2D, 8'h78, 8'h56, 8'h34, 8'h12, 8'h90);
        run_unsupported("83 /5 ib immediate SUB", 8'h83, 8'hE8, 8'h7F, 8'h90, 8'h90, 8'h90);
        run_unsupported("09 /r adjacent OR", 8'h09, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("21 /r adjacent AND", 8'h21, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("31 /r adjacent XOR", 8'h31, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("11 /r adjacent ADC", 8'h11, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("19 /r adjacent SBB", 8'h19, 8'hD8, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("01 /r memory ModRM", 8'h01, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("03 /r memory ModRM", 8'h03, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("39 /r memory ModRM", 8'h39, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);
        run_unsupported("3B /r memory ModRM", 8'h3B, 8'h00, 8'h90, 8'h90, 8'h90, 8'h90);

        check("six ADD cases ran", add_case_count == 6);
        check("eight SUB cases ran", sub_case_count == 8);
        check("six CMP cases ran", cmp_case_count == 6);
        check("twenty-nine unsupported adjacent forms checked", unsupported_count == 29);

        if (failures == 0) begin
            $display("PASS: Rung 7 focused ADD/SUB/CMP reg32 smoke completed");
        end else begin
            $display("FAIL: Rung 7 focused ADD/SUB/CMP reg32 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 7 focused ADD/SUB/CMP reg32 smoke failed");
        end

        $finish;
    end

endmodule
