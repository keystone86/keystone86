// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_base_disp32.sv
// Bounded Rung 6 Pass 6E-3 smoke: default-32 base + signed disp32 MOV forms.
//
// Authorized addressing subset:
//   ModRM.mod=10, r/m!=100, no SIB, signed disp32
//
// Authorized forms covered here:
//   8A/8B/66+8B memory-source
//   88/89/66+89 memory-destination
//   C6/C7/66+C7 /0 immediate-to-memory
//
// This test intentionally does not exercise SIB, index, scale, 0x67
// address-size behavior, EA_CALC_16, 16-bit addressing, protected/page/segment
// behavior, flags production, segment/control/debug/test-register MOV, string
// MOVS, or Rung 7 behavior.

`timescale 1ns/1ps

module tb_rung6_mov_base_disp32;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 280000;

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

    logic [31:0] program_pc;
    logic [31:0] program_end_eip;

    int failures;
    int cycles;
    int mov_endi_count;
    int ea_calc32_count;
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

    task automatic append_mov8_disp32(input logic [2:0] dst, input logic [2:0] base,
                                      input logic signed [31:0] disp,
                                      input logic [7:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h8A;
            mem[pa16(program_pc + 32'd1)] = {2'b10, dst, base};
            program_pc += 32'd2;
            append_disp32(disp);
            expected_gpr[{1'b0, dst[1:0]}] =
                merge_byte(expected_gpr[{1'b0, dst[1:0]}], dst, val);
        end
    endtask

    task automatic append_mov32_disp32(input logic [2:0] dst, input logic [2:0] base,
                                       input logic signed [31:0] disp,
                                       input logic [31:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h8B;
            mem[pa16(program_pc + 32'd1)] = {2'b10, dst, base};
            program_pc += 32'd2;
            append_disp32(disp);
            expected_gpr[dst] = val;
        end
    endtask

    task automatic append_mov16_disp32(input logic [2:0] dst, input logic [2:0] base,
                                       input logic signed [31:0] disp,
                                       input logic [15:0] val);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'h8B;
            mem[pa16(program_pc + 32'd2)] = {2'b10, dst, base};
            program_pc += 32'd3;
            append_disp32(disp);
            expected_gpr[dst] = merge_word(expected_gpr[dst], val);
        end
    endtask

    task automatic append_store8_disp32(input logic [2:0] src, input logic [2:0] base,
                                        input logic signed [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h88;
            mem[pa16(program_pc + 32'd1)] = {2'b10, src, base};
            program_pc += 32'd2;
            append_disp32(disp);
        end
    endtask

    task automatic append_store32_disp32(input logic [2:0] src, input logic [2:0] base,
                                         input logic signed [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h89;
            mem[pa16(program_pc + 32'd1)] = {2'b10, src, base};
            program_pc += 32'd2;
            append_disp32(disp);
        end
    endtask

    task automatic append_store16_disp32(input logic [2:0] src, input logic [2:0] base,
                                         input logic signed [31:0] disp);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'h89;
            mem[pa16(program_pc + 32'd2)] = {2'b10, src, base};
            program_pc += 32'd3;
            append_disp32(disp);
        end
    endtask

    task automatic append_imm8_disp32(input logic [2:0] base,
                                      input logic signed [31:0] disp,
                                      input logic [7:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hC6;
            mem[pa16(program_pc + 32'd1)] = {2'b10, 3'b000, base};
            program_pc += 32'd2;
            append_disp32(disp);
            mem[pa16(program_pc + 32'd0)] = imm;
            program_pc += 32'd1;
        end
    endtask

    task automatic append_imm32_disp32(input logic [2:0] base,
                                       input logic signed [31:0] disp,
                                       input logic [31:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'hC7;
            mem[pa16(program_pc + 32'd1)] = {2'b10, 3'b000, base};
            program_pc += 32'd2;
            append_disp32(disp);
            mem[pa16(program_pc + 32'd0)] = imm[7:0];
            mem[pa16(program_pc + 32'd1)] = imm[15:8];
            mem[pa16(program_pc + 32'd2)] = imm[23:16];
            mem[pa16(program_pc + 32'd3)] = imm[31:24];
            program_pc += 32'd4;
        end
    endtask

    task automatic append_imm16_disp32(input logic [2:0] base,
                                       input logic signed [31:0] disp,
                                       input logic [15:0] imm);
        begin
            mem[pa16(program_pc + 32'd0)] = 8'h66;
            mem[pa16(program_pc + 32'd1)] = 8'hC7;
            mem[pa16(program_pc + 32'd2)] = {2'b10, 3'b000, base};
            program_pc += 32'd3;
            append_disp32(disp);
            mem[pa16(program_pc + 32'd0)] = imm[7:0];
            mem[pa16(program_pc + 32'd1)] = imm[15:8];
            program_pc += 32'd2;
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

            saw_expected_dispatch = 1'b0;
            saw_mov_endi = 1'b0;
            saw_bus_wr = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 900; c++) begin
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
            check({name, expect_prefix_only ? " does not ENDI as MOV before prefix dispatch" :
                  " does not ENDI as MOV before unsupported dispatch"}, !saw_mov_endi);
            check({name, expect_prefix_only ? " issues no bus write before prefix dispatch" :
                  " issues no bus write before unsupported dispatch"}, !saw_bus_wr);
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

        run_unsupported_form(7, 8'h8B, 8'h84, 8'h0C, 8'h00, 8'h00, 8'h00,
                             "SIB index!=100 with disp32", 1'b0);
        run_unsupported_form(1, 8'h67, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                             "0x67 prefix byte", 1'b1);
        run_unsupported_form(7, 8'hC7, 8'h8D, 8'h08, 8'h00, 8'h00, 8'h00,
                             "C7 mod=10 non-/0", 1'b0);

        clear_memory();
        for (int i = 0; i < 8; i++)
            expected_gpr[i] = 32'h0;

        mov_endi_count = 0;
        ea_calc32_count = 0;
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

        write_mem32(32'h00003004, 32'hA1A2A3A4);
        write_mem32(32'h00003018, 32'hB1B25A5A);
        write_mem32(32'h00003030, 32'hC1C2C3C4);
        write_mem32(32'h00003047, 32'hD1D2BEEF);
        write_mem32(32'h00003053, 32'hE1E2C3E4);
        write_mem32(32'h0000306C, 32'hF1F2F3F4);
        write_mem32(32'h0000308C, 32'h0102CAFE);

        append_mov32_imm(3'h0, 32'h00002FF0); // EAX, +0x14
        append_mov32_imm(3'h1, 32'h00003040); // ECX, -0x28
        append_mov32_imm(3'h3, 32'h00003080); // EBX, -0x50
        append_mov32_imm(3'h2, 32'h00003000); // EDX, +0x47
        append_mov32_imm(3'h5, 32'h00003090); // EBP, -0x3D
        append_mov32_imm(3'h7, 32'h00003000); // EDI, +0x6C
        append_mov32_imm(3'h6, 32'h000030C0); // ESI, -0x34
        append_mov32_disp32(3'h4, 3'h0, 32'sd20, 32'hA1A2A3A4);
        append_mov8_disp32(3'h0, 3'h1, -32'sd40, 8'h5A);
        append_mov32_disp32(3'h4, 3'h3, -32'sd80, 32'hC1C2C3C4);
        append_mov16_disp32(3'h3, 3'h2, 32'sd71, 16'hBEEF);
        append_mov8_disp32(3'h2, 3'h5, -32'sd61, 8'hC3);
        append_mov32_disp32(3'h5, 3'h7, 32'sd108, 32'hF1F2F3F4);
        append_mov16_disp32(3'h7, 3'h6, -32'sd52, 16'hCAFE);

        write_mem32(32'h00004005, 32'h11111111);
        append_mov32_imm(3'h0, 32'h00003FF0);
        append_mov32_imm(3'h1, 32'h000000AA);
        append_store8_disp32(3'h1, 3'h0, 32'sd21);

        write_mem32(32'h0000401C, 32'h22222222);
        append_mov32_imm(3'h1, 32'h00004040);
        append_mov32_imm(3'h5, 32'h55667788);
        append_store32_disp32(3'h5, 3'h1, -32'sd36);

        write_mem32(32'h00004039, 32'h33333333);
        append_mov32_imm(3'h2, 32'h00004000);
        append_mov32_imm(3'h5, 32'hAABBCCDD);
        append_store16_disp32(3'h5, 3'h2, 32'sd57);

        write_mem32(32'h00004049, 32'h44444444);
        append_mov32_imm(3'h3, 32'h00004090);
        append_mov32_imm(3'h2, 32'h00000012);
        append_store8_disp32(3'h2, 3'h3, -32'sd71);

        write_mem32(32'h00004062, 32'h55555555);
        append_mov32_imm(3'h5, 32'h00004020);
        append_mov32_imm(3'h4, 32'hDEADBEEF);
        append_store32_disp32(3'h4, 3'h5, 32'sd66);

        write_mem32(32'h0000407D, 32'h66666666);
        append_mov32_imm(3'h6, 32'h000040C0);
        append_mov32_imm(3'h5, 32'hFACECAFE);
        append_store16_disp32(3'h5, 3'h6, -32'sd67);

        write_mem32(32'h00004096, 32'h77777777);
        append_mov32_imm(3'h7, 32'h00004000);
        append_mov32_imm(3'h3, 32'h12345678);
        append_store32_disp32(3'h3, 3'h7, 32'sd150);

        write_mem32(32'h00005001, 32'h88888888);
        append_mov32_imm(3'h0, 32'h00004FF0);
        append_imm8_disp32(3'h0, 32'sd17, 8'h5A);

        write_mem32(32'h00005018, 32'h99999999);
        append_mov32_imm(3'h1, 32'h00005080);
        append_imm32_disp32(3'h1, -32'sd104, 32'h11223344);

        write_mem32(32'h00005047, 32'hAAAAAAAA);
        append_mov32_imm(3'h2, 32'h00005000);
        append_imm16_disp32(3'h2, 32'sd71, 16'hBEEF);

        write_mem32(32'h0000505C, 32'hBBBBBBBB);
        append_mov32_imm(3'h3, 32'h000050A0);
        append_imm8_disp32(3'h3, -32'sd68, 8'hA5);

        write_mem32(32'h00005072, 32'hCCCCCCCC);
        append_mov32_imm(3'h5, 32'h00005040);
        append_imm32_disp32(3'h5, 32'sd50, 32'h89ABCDEF);

        write_mem32(32'h0000507E, 32'hDDDDDDDD);
        append_mov32_imm(3'h6, 32'h000050C0);
        append_imm16_disp32(3'h6, -32'sd66, 16'hCAFE);

        write_mem32(32'h00005096, 32'hEEEEEEEE);
        append_mov32_imm(3'h7, 32'h00005000);
        append_imm8_disp32(3'h7, 32'sd150, 8'h3C);

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
                    SVC_EA_CALC_32:  ea_calc32_count++;
                    SVC_LOAD_RM8:    load_rm8_count++;
                    SVC_LOAD_RM16:   load_rm16_count++;
                    SVC_LOAD_RM32:   load_rm32_count++;
                    SVC_STORE_RM8:   store_rm8_count++;
                    SVC_STORE_RM16:  store_rm16_count++;
                    SVC_STORE_RM32:  store_rm32_count++;
                    default: ;
                endcase
            end

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

        $display("Rung 6 Pass 6E-3 MOV base+signed-disp32 checks");

        check("simulation completed before timeout", !timed_out);
        check("final EIP reached NOP fall-through", dbg_eip == program_end_eip);
        check("no fault pending", !dbg_fault_pending);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("EA_CALC_32 issued for each disp32 base memory MOV", ea_calc32_count == 21);
        check("LOAD_RM8 issued for disp32 memory-source", load_rm8_count == 2);
        check("LOAD_RM16 issued for disp32 memory-source", load_rm16_count == 2);
        check("LOAD_RM32 issued for disp32 memory-source", load_rm32_count == 3);
        check("STORE_RM8 issued for disp32 stores", store_rm8_count == 5);
        check("STORE_RM16 issued for disp32 stores", store_rm16_count == 4);
        check("STORE_RM32 issued for disp32 stores", store_rm32_count == 5);
        check("FETCH_IMM8 issued for C6 disp32 forms", fetch_imm8_count == 3);
        check("FETCH_IMM16 issued for 66+C7 disp32 forms", fetch_imm16_count == 2);
        check("FETCH_IMM32 issued for C7 disp32 and setup", fetch_imm32_count == 30);
        check("CM_MOV_REG used for register destinations", cm_mov_reg_count == 35);
        check("CM_NOP|CM_EIP used for memory destinations", cm_nop_eip_count >= 14);
        check("STORE_RM8 byte enable observed", byteen_0001_count >= 5);
        check("STORE_RM16 byte enable observed", byteen_0011_count >= 4);
        check("STORE_RM32 byte enable observed", byteen_1111_count >= 5);

        check("final GPR state matches expected", gprs_match_expected());
        check("88 [EAX+21], CL wrote byte", read_mem32(32'h00004005) == 32'h111111AA);
        check("89 [ECX-36], EBP wrote dword", read_mem32(32'h0000401C) == 32'h55667788);
        check("66 89 [EDX+57], BP wrote word", read_mem32(32'h00004039) == 32'h3333CCDD);
        check("88 [EBX-71], DL wrote byte", read_mem32(32'h00004049) == 32'h44444412);
        check("89 [EBP+66], ESP wrote dword", read_mem32(32'h00004062) == 32'hDEADBEEF);
        check("66 89 [ESI-67], BP wrote word", read_mem32(32'h0000407D) == 32'h6666CAFE);
        check("89 [EDI+150], EBX wrote dword", read_mem32(32'h00004096) == 32'h12345678);
        check("C6 [EAX+17], imm8 wrote byte", read_mem32(32'h00005001) == 32'h8888885A);
        check("C7 [ECX-104], imm32 wrote dword", read_mem32(32'h00005018) == 32'h11223344);
        check("66 C7 [EDX+71], imm16 wrote word", read_mem32(32'h00005047) == 32'hAAAABEEF);
        check("C6 [EBX-68], imm8 wrote byte", read_mem32(32'h0000505C) == 32'hBBBBBBA5);
        check("C7 [EBP+50], imm32 wrote dword", read_mem32(32'h00005072) == 32'h89ABCDEF);
        check("66 C7 [ESI-66], imm16 wrote word", read_mem32(32'h0000507E) == 32'hDDDDCAFE);
        check("C6 [EDI+150], imm8 wrote byte", read_mem32(32'h00005096) == 32'hEEEEEE3C);

        if (failures == 0) begin
            $display("RESULT: ALL TESTS PASSED");
        end else begin
            $display("RESULT: %0d TEST(S) FAILED", failures);
        end
        $finish;
    end

endmodule
