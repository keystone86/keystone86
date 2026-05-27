// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_addr16_direct.sv
// Bounded Rung 6 Pass 6H-1 smoke: 0x67 direct disp16 MOV forms only.
//
// Authorized address-size-16 subset:
//   ModRM.mod=00, ModRM.r/m=110, disp16 present, EA = zero-extended disp16.
//
// This test intentionally does not exercise BX/BP/SI/DI register-based
// addressing, 16-bit mod=01/mod=10 forms, BP segment semantics, segment-base
// addition, protected/page behavior, broad 0x67 behavior, or Rung 7 behavior.

`timescale 1ns/1ps

module tb_rung6_mov_addr16_direct;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 120000;

    localparam logic [7:0]  ENTRY_NULL_ID      = 8'h00;
    localparam logic [7:0]  ENTRY_MOV_ID       = 8'h01;
    localparam logic [7:0]  ENTRY_PREFIX_ID    = 8'h12;
    localparam logic [7:0]  SVC_FETCH_IMM8     = 8'h01;
    localparam logic [7:0]  SVC_FETCH_IMM16    = 8'h02;
    localparam logic [7:0]  SVC_FETCH_IMM32    = 8'h03;
    localparam logic [7:0]  SVC_EA_CALC_16     = 8'h10;
    localparam logic [7:0]  SVC_EA_CALC_32     = 8'h11;
    localparam logic [7:0]  SVC_LOAD_RM8       = 8'h20;
    localparam logic [7:0]  SVC_LOAD_RM16      = 8'h21;
    localparam logic [7:0]  SVC_LOAD_RM32      = 8'h22;
    localparam logic [7:0]  SVC_STORE_RM8      = 8'h23;
    localparam logic [7:0]  SVC_STORE_RM16     = 8'h24;
    localparam logic [7:0]  SVC_STORE_RM32     = 8'h25;
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
    logic        bus_wr_observed_active;
    logic [31:0] bus_addr_pending;
    logic [3:0]  bus_byteen_pending;
    logic [31:0] bus_dout_pending;

    logic [31:0] program_pc;
    logic [31:0] program_end_eip;
    logic [31:0] expected_t2 [0:8];

    int failures;
    int cycles;
    int mov_endi_count;
    int mov_route_count;
    int fetch_imm8_count;
    int fetch_imm16_count;
    int fetch_imm32_count;
    int ea_calc16_count;
    int ea_calc32_count;
    int load_rm8_count;
    int load_rm16_count;
    int load_rm32_count;
    int store_rm8_count;
    int store_rm16_count;
    int store_rm32_count;
    int byteen_0001_count;
    int byteen_0011_count;
    int byteen_1111_count;
    int t2_check_count;
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

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_ready          <= 1'b0;
            bus_din            <= 32'h0;
            bus_pending        <= 1'b0;
            bus_wr_pending     <= 1'b0;
            bus_wr_observed_active <= 1'b0;
            bus_addr_pending   <= 32'h0;
            bus_byteen_pending <= 4'h0;
            bus_dout_pending   <= 32'h0;
        end else begin
            bus_ready <= 1'b0;

            if (!bus_wr) begin
                bus_wr_observed_active <= 1'b0;
            end else if (!bus_wr_observed_active) begin
                bus_wr_observed_active <= 1'b1;
                if (bus_byteen == 4'b0001)
                    byteen_0001_count++;
                if (bus_byteen == 4'b0011)
                    byteen_0011_count++;
                if (bus_byteen == 4'b1111)
                    byteen_1111_count++;
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
                     name, dbg_eip, dbg_entry_id, dbg_fault_pending,
                     dbg_fault_class);
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

    task automatic emit8(input logic [7:0] b);
        begin
            mem[pa16(program_pc)] = b;
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

    task automatic append_mov32_imm(input logic [2:0] dst, input logic [31:0] imm);
        begin
            emit8(8'hB8 | {5'h0, dst});
            emit32(imm);
        end
    endtask

    task automatic append_addr16_modrm_disp(input logic [7:0] op,
                                            input logic [2:0] reg_field,
                                            input logic [15:0] disp);
        begin
            emit8(8'h67);
            emit8(op);
            emit8({2'b00, reg_field, 3'b110});
            emit16(disp);
        end
    endtask

    task automatic append_addr16_modrm_disp_66(input logic [7:0] op,
                                               input logic [2:0] reg_field,
                                               input logic [15:0] disp);
        begin
            emit8(8'h66);
            emit8(8'h67);
            emit8(op);
            emit8({2'b00, reg_field, 3'b110});
            emit16(disp);
        end
    endtask

    task automatic append_c6_addr16(input logic [15:0] disp, input logic [7:0] imm);
        begin
            emit8(8'h67);
            emit8(8'hC6);
            emit8(8'h06);
            emit16(disp);
            emit8(imm);
        end
    endtask

    task automatic append_c7_addr16(input logic [15:0] disp, input logic [31:0] imm);
        begin
            emit8(8'h67);
            emit8(8'hC7);
            emit8(8'h06);
            emit16(disp);
            emit32(imm);
        end
    endtask

    task automatic append_66_c7_addr16(input logic [15:0] disp, input logic [15:0] imm);
        begin
            emit8(8'h66);
            emit8(8'h67);
            emit8(8'hC7);
            emit8(8'h06);
            emit16(disp);
            emit16(imm);
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

            saw_entry_null = 1'b0;
            saw_mov_endi   = 1'b0;
            saw_bus_wr     = 1'b0;

            reset_cpu();

            begin : wait_unsupported
                for (int c = 0; c < 700; c++) begin
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
            check({name, " issues no bus write before unsupported dispatch"},
                  !saw_bus_wr);
        end
    endtask

    task automatic run_unsupported_prefix_order(
        input int len,
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic [7:0] b4,
        input logic [7:0] b5,
        input string name
    );
        logic saw_prefix_boundary;
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

            saw_prefix_boundary = 1'b0;
            saw_mov_endi        = 1'b0;
            saw_bus_wr          = 1'b0;

            reset_cpu();

            begin : wait_prefix_order
                for (int c = 0; c < 700; c++) begin
                    @(posedge clk);
                    #1;
                    if (bus_wr)
                        saw_bus_wr = 1'b1;
                    if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID))
                        saw_mov_endi = 1'b1;
                    if (dut.u_mseq.dispatch_rom_pending &&
                        (dut.u_mseq.dispatch_entry_latch == ENTRY_PREFIX_ID)) begin
                        saw_prefix_boundary = 1'b1;
                        disable wait_prefix_order;
                    end
                end
            end

            check({name, " stops at prefix-only boundary"}, saw_prefix_boundary);
            check({name, " does not ENDI as MOV"}, !saw_mov_endi);
            check({name, " issues no bus write before unsupported boundary"},
                  !saw_bus_wr);
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

        clear_memory();
        write_mem32(32'h00002100, 32'h0000005A);
        write_mem32(32'h00002200, 32'hA1A2A3A4);
        write_mem32(32'h00002300, 32'h0000BEEF);
        write_mem32(32'h00002400, 32'h11111111);
        write_mem32(32'h00002500, 32'h22222222);
        write_mem32(32'h00002600, 32'h33333333);
        write_mem32(32'h00002700, 32'h44444444);
        write_mem32(32'h00002800, 32'h55555555);
        write_mem32(32'h00002900, 32'h66666666);

        expected_t2[0] = 32'h00002100;
        expected_t2[1] = 32'h00002200;
        expected_t2[2] = 32'h00002300;
        expected_t2[3] = 32'h00002400;
        expected_t2[4] = 32'h00002500;
        expected_t2[5] = 32'h00002600;
        expected_t2[6] = 32'h00002700;
        expected_t2[7] = 32'h00002800;
        expected_t2[8] = 32'h00002900;

        program_pc = RESET_EIP;
        append_mov32_imm(3'h0, 32'h1122AABB);       // EAX source for 88/89
        append_mov32_imm(3'h6, 32'h0000CAFE);       // ESI source for 66+89
        append_addr16_modrm_disp(8'h8A, 3'h1, 16'h2100);
        append_addr16_modrm_disp(8'h8B, 3'h2, 16'h2200);
        append_addr16_modrm_disp_66(8'h8B, 3'h3, 16'h2300);
        append_addr16_modrm_disp(8'h88, 3'h0, 16'h2400);
        append_addr16_modrm_disp(8'h89, 3'h0, 16'h2500);
        append_addr16_modrm_disp_66(8'h89, 3'h6, 16'h2600);
        append_c6_addr16(16'h2700, 8'h6B);
        append_c7_addr16(16'h2800, 32'h55667788);
        append_66_c7_addr16(16'h2900, 16'hBEEF);
        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6H-1 MOV addr16 direct disp16 Smoke");

        mov_endi_count = 0;
        mov_route_count = 0;
        fetch_imm8_count = 0;
        fetch_imm16_count = 0;
        fetch_imm32_count = 0;
        ea_calc16_count = 0;
        ea_calc32_count = 0;
        load_rm8_count = 0;
        load_rm16_count = 0;
        load_rm32_count = 0;
        store_rm8_count = 0;
        store_rm16_count = 0;
        store_rm32_count = 0;
        byteen_0001_count = 0;
        byteen_0011_count = 0;
        byteen_1111_count = 0;
        t2_check_count = 0;
        timed_out = 1'b1;

        reset_cpu();

        begin : wait_movs
            for (cycles = 0; cycles < TIMEOUT; cycles++) begin
                @(posedge clk);
                #1;

                if (dut.u_mseq.dispatch_rom_pending &&
                    (dut.u_mseq.dispatch_entry_latch == ENTRY_MOV_ID))
                    mov_route_count++;

                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM8))
                    fetch_imm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM16))
                    fetch_imm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_FETCH_IMM32))
                    fetch_imm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_EA_CALC_16))
                    ea_calc16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_EA_CALC_32))
                    ea_calc32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM8))
                    load_rm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM16))
                    load_rm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_LOAD_RM32))
                    load_rm32_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM8))
                    store_rm8_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM16))
                    store_rm16_count++;
                if (dut.svc_req_out && (dut.svc_id_out == SVC_STORE_RM32))
                    store_rm32_count++;

                if (dut.ea_t2_wr_en) begin
                    if (t2_check_count < 9) begin
                        check("EA_CALC_16 wrote expected zero-extended T2",
                              dut.ea_t2_wr_data == expected_t2[t2_check_count]);
                        check("EA_CALC_16 T2 high half is zero",
                              dut.ea_t2_wr_data[31:16] == 16'h0000);
                    end else begin
                        check("no extra EA_CALC_16 T2 write", 1'b0);
                    end
                    t2_check_count++;
                end

                if (dbg_endi_pulse && (dbg_entry_id == ENTRY_MOV_ID)) begin
                    mov_endi_count++;
                    if (mov_endi_count == 11) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_movs;
                    end
                end
            end
        end

        check("two setup MOVs plus nine addr16 direct MOVs completed",
              !timed_out && (mov_endi_count == 11));
        check("ENTRY_MOV routed for all setup and addr16 direct forms",
              mov_route_count == 11);
        check("EA_CALC_16 issued for each addr16 memory MOV", ea_calc16_count == 9);
        check("EA_CALC_32 not issued for addr16 direct MOVs", ea_calc32_count == 0);
        check("T2 checked for every addr16 direct MOV", t2_check_count == 9);
        check("LOAD_RM8 issued for 67+8A", load_rm8_count == 1);
        check("LOAD_RM32 issued for 67+8B", load_rm32_count == 1);
        check("LOAD_RM16 issued for 66+67+8B", load_rm16_count == 1);
        check("STORE_RM8 issued for 67+88 and 67+C6", store_rm8_count == 2);
        check("STORE_RM32 issued for 67+89 and 67+C7", store_rm32_count == 2);
        check("STORE_RM16 issued for 66+67+89 and 66+67+C7", store_rm16_count == 2);
        check("FETCH_IMM8 issued for 67+C6", fetch_imm8_count == 1);
        check("FETCH_IMM16 issued for 66+67+C7", fetch_imm16_count == 1);
        check("FETCH_IMM32 issued for setup MOVs and 67+C7", fetch_imm32_count == 3);
        $display("  [INFO] accepted write byte-enables: 0001=%0d 0011=%0d 1111=%0d",
                 byteen_0001_count, byteen_0011_count, byteen_1111_count);
        check("STORE_RM8 byte enable observed", byteen_0001_count == 2);
        check("STORE_RM16 byte enable observed", byteen_0011_count == 2);
        check("STORE_RM32 byte enable observed", byteen_1111_count == 2);

        check("67+8A loaded byte into CL", dut.u_commit.gpr_r[3'h1] == 32'h0000005A);
        check("67+8B loaded dword into EDX", dut.u_commit.gpr_r[3'h2] == 32'hA1A2A3A4);
        check("66+67+8B loaded word into BX", dut.u_commit.gpr_r[3'h3] == 32'h0000BEEF);
        check("67+88 stored AL byte", read_mem32(32'h00002400) == 32'h111111BB);
        check("67+89 stored EAX dword", read_mem32(32'h00002500) == 32'h1122AABB);
        check("66+67+89 stored SI word", read_mem32(32'h00002600) == 32'h3333CAFE);
        check("67+C6 stored imm8", read_mem32(32'h00002700) == 32'h4444446B);
        check("67+C7 stored imm32", read_mem32(32'h00002800) == 32'h55667788);
        check("66+67+C7 stored imm16", read_mem32(32'h00002900) == 32'h6666BEEF);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6H-1 MOV sequence", dbg_eip == program_end_eip);
        check("no fault after addr16 direct MOV sequence", !dbg_fault_pending);

        run_unsupported_form(3, 8'h67, 8'h8B, 8'h00, 8'h00, 8'h00, 8'h00,
                             "0x67 mod=00 r/m=000 [BX+SI]");
        run_unsupported_form(4, 8'h67, 8'h8B, 8'h46, 8'h04, 8'h00, 8'h00,
                             "0x67 mod=01 signed disp8");
        run_unsupported_form(5, 8'h67, 8'h8B, 8'h86, 8'h34, 8'h12, 8'h00,
                             "0x67 mod=10 disp16");
        run_unsupported_form(5, 8'h67, 8'hC7, 8'h0E, 8'h00, 8'h21, 8'h00,
                             "0x67 C7 non-/0 direct disp16");
        run_unsupported_prefix_order(6, 8'h67, 8'h66, 8'h8B, 8'h06, 8'h00, 8'h21,
                                     "unsupported 67+66 prefix order");

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6H-1 MOV addr16 direct disp16 smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6H-1 MOV addr16 direct disp16 smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6H-1 MOV addr16 direct disp16 smoke failed");
        end

        $finish;
    end

endmodule
