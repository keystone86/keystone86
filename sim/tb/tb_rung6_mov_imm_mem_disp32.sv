// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_imm_mem_disp32.sv
// Bounded Rung 6 Pass 6C-1 smoke: MOV immediate-to-memory direct disp32 only.
//
// Authorized immediate-to-memory forms:
//   C6 /0 ib      mod=00 r/m=101 disp32 -> MOV byte [disp32], imm8
//   C7 /0 id      mod=00 r/m=101 disp32 -> MOV dword [disp32], imm32
//   66 C7 /0 iw   mod=00 r/m=101 disp32 -> MOV word [disp32], imm16
//
// This test intentionally does not exercise register-destination C6/C7
// behavior, which is covered by Pass 6D-1. It also does not exercise non-/0
// extensions, SIB, base/index/scale, disp8, base+disp8/base+disp32, 0x67
// address-size behavior, EA_CALC_16, 16-bit addressing, protected/page/segment behavior,
// segment/control/debug/test-register MOV, string MOVS, or flags production.

`timescale 1ns/1ps

module tb_rung6_mov_imm_mem_disp32;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 140000;
    localparam int MAX_OPS         = 40;

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
    localparam logic [9:0]  CM_MOV_REG_MASK    = 10'h1C1;
    localparam logic [9:0]  CM_NOP_EIP_MASK    = 10'h1C2;
    localparam logic [31:0] RESET_EIP          = 32'hFFFFFFF0;
    localparam logic [31:0] DATA_BASE8         = 32'h00005000;
    localparam logic [31:0] DATA_BASE32        = 32'h00005100;
    localparam logic [31:0] DATA_BASE16        = 32'h00005200;

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
    logic [31:0] expected_mem32 [0:23];
    logic [31:0] initial_gpr [0:7];

    logic [31:0] program_pc;
    int          op_count;
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int mov_route_count;
    int fetch_imm8_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int ea_calc32_count;
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
            bus_ready           <= 1'b0;
            bus_din             <= 32'h0;
            bus_pending         <= 1'b0;
            bus_wr_pending      <= 1'b0;
            bus_addr_pending    <= 32'h0;
            bus_byteen_pending  <= 4'h0;
            bus_dout_pending    <= 32'h0;
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

    function automatic logic gprs_match_initial;
        logic ok;
        begin
            ok = 1'b1;
            for (int i = 0; i < 8; i++) begin
                if (dut.u_commit.gpr_r[i] !== initial_gpr[i])
                    ok = 1'b0;
            end
            return ok;
        end
    endfunction

    task automatic append_disp32(input logic [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = disp[7:0];
            mem[pa16(program_pc + 32'd1)] = disp[15:8];
            mem[pa16(program_pc + 32'd2)] = disp[23:16];
            mem[pa16(program_pc + 32'd3)] = disp[31:24];
            program_pc += 32'd4;
        end
    endtask

    task automatic append_mov_mem_imm8(input logic [31:0] addr,
                                       input logic [7:0] imm,
                                       input int slot);
        begin
            write_mem32(addr, 32'hA6A60000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = (32'hA6A60000 | {24'h0, slot[7:0]});
            expected_mem32[slot][7:0] = imm;
            mem[pa16(program_pc + 32'd0)] = 8'hC6;
            mem[pa16(program_pc + 32'd1)] = 8'h05;
            program_pc += 32'd2;
            append_disp32(addr);
            mem[pa16(program_pc)] = imm;
            program_pc += 32'd1;
            op_count++;
        end
    endtask

    task automatic append_mov_mem_imm32(input logic [31:0] addr,
                                        input logic [31:0] imm,
                                        input int slot);
        begin
            write_mem32(addr, 32'h5B5B0000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = imm;
            mem[pa16(program_pc + 32'd0)] = 8'hC7;
            mem[pa16(program_pc + 32'd1)] = 8'h05;
            program_pc += 32'd2;
            append_disp32(addr);
            mem[pa16(program_pc + 32'd0)] = imm[7:0];
            mem[pa16(program_pc + 32'd1)] = imm[15:8];
            mem[pa16(program_pc + 32'd2)] = imm[23:16];
            mem[pa16(program_pc + 32'd3)] = imm[31:24];
            program_pc += 32'd4;
            op_count++;
        end
    endtask

    task automatic append_mov_mem_imm16(input logic [31:0] addr,
                                        input logic [15:0] imm,
                                        input int slot);
        begin
            write_mem32(addr, 32'hC7C70000 | {24'h0, slot[7:0]});
            expected_mem32[slot] = (32'hC7C70000 | {24'h0, slot[7:0]});
            expected_mem32[slot][15:0] = imm;
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'hC7;
            mem[pa16(program_pc + 32'd2)] = 8'h05;
            program_pc += 32'd3;
            append_disp32(addr);
            mem[pa16(program_pc + 32'd0)] = imm[7:0];
            mem[pa16(program_pc + 32'd1)] = imm[15:8];
            program_pc += 32'd2;
            op_count++;
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
        bus_byteen_pending = 4'h0;
        bus_dout_pending = 32'h0;
        bus_write_completed = 1'b0;

        clear_memory();
        for (int i = 0; i < 8; i++)
            initial_gpr[i] = 32'h0;
        for (int i = 0; i < 24; i++)
            expected_mem32[i] = 32'h0;

        program_pc = RESET_EIP;
        op_count = 0;

        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            logic [7:0]  imm;
            addr = DATA_BASE8 + ({29'h0, i[2:0]} * 32'd4);
            imm = 8'h01 ^ (8'h31 + i[7:0] * 8'h17);
            append_mov_mem_imm8(addr, imm, i);
        end

        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            logic [31:0] imm;
            addr = DATA_BASE32 + ({29'h0, i[2:0]} * 32'd4);
            imm = 32'h10203040 ^ ({24'h0, i[7:0]} * 32'h01040A11);
            append_mov_mem_imm32(addr, imm, 8 + i);
        end

        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            logic [15:0] imm;
            addr = DATA_BASE16 + ({29'h0, i[2:0]} * 32'd4);
            imm = 16'h6C00 ^ ({8'h0, i[7:0]} * 16'h0125);
            append_mov_mem_imm16(addr, imm, 16 + i);
        end

        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6C-1 MOV imm-to-mem disp32 Smoke");

        mov_endi_count = 0;
        mov_route_count = 0;
        fetch_imm8_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        ea_calc32_count = 0;
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

        check("24 immediate-to-memory MOVs completed",
              !timed_out && (mov_endi_count == op_count) && (op_count == 24));
        check("ENTRY_MOV routed for authorized C6/C7 immediate-to-memory forms",
              mov_route_count == 24);
        check("FETCH_IMM8 issued for all C6 byte immediate stores", fetch_imm8_count == 8);
        check("FETCH_IMM16 issued for all 66+C7 word immediate stores", fetch_imm16_count == 8);
        check("FETCH_IMM32 issued for all C7 dword immediate stores", fetch_imm32_count == 8);
        check("EA_CALC_32 issued once per immediate-to-memory MOV", ea_calc32_count == 24);
        check("STORE_RM8 issued for all C6 byte stores", store_rm8_count == 8);
        check("STORE_RM32 issued for all C7 dword stores", store_rm32_count == 8);
        check("STORE_RM16 issued for all 66+C7 word stores", store_rm16_count == 8);
        check("one bus write per immediate-to-memory MOV", bus_wr_count == 24);
        check("STORE_RM8 bus byte enables are 0001", byteen_0001_count == 8);
        check("STORE_RM16 bus byte enables are 0011", byteen_0011_count == 8);
        check("STORE_RM32 bus byte enables are 1111", byteen_1111_count == 8);
        check("STORE_RM services complete before ENDI",
              (store_complete_before_endi_count == 24) && !store_endi_before_completion);
        check("immediate-to-memory MOVs do not use CM_MOV_REG", !saw_cm_mov_reg);
        check("immediate-to-memory MOVs use ENDI CM_NOP|CM_EIP", saw_cm_nop_eip &&
              (store_endi_count == 24));
        check("no fault after immediate-to-memory MOV sequence", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6C-1 MOV sequence", dbg_eip == program_end_eip);
        check("no unintended GPR changes from immediate-to-memory stores", gprs_match_initial());

        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            addr = DATA_BASE8 + ({29'h0, i[2:0]} * 32'd4);
            check($sformatf("C6 /0 byte store %0d final memory byte", i),
                  read_mem32(addr) == expected_mem32[i]);
        end
        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            addr = DATA_BASE32 + ({29'h0, i[2:0]} * 32'd4);
            check($sformatf("C7 /0 dword store %0d final memory dword", i),
                  read_mem32(addr) == expected_mem32[8 + i]);
        end
        for (int i = 0; i < 8; i++) begin
            logic [31:0] addr;
            addr = DATA_BASE16 + ({29'h0, i[2:0]} * 32'd4);
            check($sformatf("66+C7 /0 word store %0d final memory word", i),
                  read_mem32(addr) == expected_mem32[16 + i]);
        end

        run_unsupported_form(7, 8'hC6, 8'h0D, 8'h00, 8'h50, 8'h00, 8'h00,
                             8'h12, 8'h00, 8'h00, 8'h00,
                             "C6 non-/0 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'hC7, 8'h0D, 8'h00, 8'h51, 8'h00, 8'h00,
                             8'h78, 8'h56, 8'h34, 8'h12,
                             "C7 non-/0 immediate-to-memory", 1'b0);
        run_unsupported_form(8, 8'hC6, 8'h84, 8'h25, 8'h00, 8'h50, 8'h00,
                             8'h00, 8'h12, 8'h00, 8'h00,
                             "C6 SIB mod=10 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'hC7, 8'h84, 8'h25, 8'h00, 8'h51, 8'h00,
                             8'h00, 8'h78, 8'h56, 8'h34,
                             "C7 SIB mod=10 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'hC7, 8'h04, 8'h25, 8'h00, 8'h51, 8'h00,
                             8'h00, 8'h78, 8'h56, 8'h34,
                             "C7 SIB immediate-to-memory", 1'b0);
        run_unsupported_form(8, 8'h66, 8'hC6, 8'h05, 8'h00, 8'h50, 8'h00,
                             8'h00, 8'h12, 8'h00, 8'h00,
                             "66+C6 immediate-to-memory", 1'b0);
        run_unsupported_form(10, 8'h67, 8'hC7, 8'h05, 8'h00, 8'h51, 8'h00,
                             8'h00, 8'h78, 8'h56, 8'h34,
                             "67-prefixed C7 immediate-to-memory", 1'b1);

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6C-1 MOV imm-to-mem disp32 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6C-1 MOV imm-to-mem disp32 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6C-1 MOV imm-to-mem disp32 smoke failed");
        end

        $finish;
    end

endmodule
