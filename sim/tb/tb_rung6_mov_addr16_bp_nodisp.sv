// Keystone86 / Aegis
// sim/tb/tb_rung6_mov_addr16_bp_nodisp.sv
// Bounded Rung 6 Pass 6H-3 smoke: 0x67 no-displacement BP-based MOV forms.
//
// Authorized address-size-16 subset:
//   ModRM.mod=00, no displacement, r/m=010 [BP+SI] and r/m=011 [BP+DI].
//
// This test intentionally does not exercise accepted signed-disp8 forms, direct
// disp16 changes, segment-base/default-SS linearization, protected/page behavior,
// broad 0x67 behavior, or Rung 7 behavior.

`timescale 1ns/1ps

module tb_rung6_mov_addr16_bp_nodisp;

    localparam int CLK_HALF_PERIOD = 5;
    localparam int TIMEOUT         = 140000;

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
    logic [31:0] expected_store_addr [0:5];
    logic [31:0] expected_store_data [0:5];
    logic [3:0]  expected_store_be [0:5];
    logic [31:0] observed_store_addr [0:5];
    logic [31:0] observed_store_data [0:5];
    logic [3:0]  observed_store_be [0:5];
    logic        extra_store_seen;

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
    int store_bus_count;
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

                if (store_bus_count < 6) begin
                    observed_store_addr[store_bus_count] <= bus_addr;
                    observed_store_be[store_bus_count]   <= bus_byteen;
                    observed_store_data[store_bus_count] <= bus_dout;
                end else begin
                    extra_store_seen <= 1'b1;
                end
                store_bus_count++;
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

    task automatic append_addr16_modrm(input logic [7:0] op,
                                       input logic [2:0] reg_field,
                                       input logic [2:0] rm_field);
        begin
            emit8(8'h67);
            emit8(op);
            emit8({2'b00, reg_field, rm_field});
        end
    endtask

    task automatic append_addr16_modrm_66(input logic [7:0] op,
                                          input logic [2:0] reg_field,
                                          input logic [2:0] rm_field);
        begin
            emit8(8'h66);
            emit8(8'h67);
            emit8(op);
            emit8({2'b00, reg_field, rm_field});
        end
    endtask

    task automatic append_c6_addr16(input logic [2:0] rm_field, input logic [7:0] imm);
        begin
            emit8(8'h67);
            emit8(8'hC6);
            emit8({2'b00, 3'b000, rm_field});
            emit8(imm);
        end
    endtask

    task automatic append_c7_addr16(input logic [2:0] rm_field, input logic [31:0] imm);
        begin
            emit8(8'h67);
            emit8(8'hC7);
            emit8({2'b00, 3'b000, rm_field});
            emit32(imm);
        end
    endtask

    task automatic append_66_c7_addr16(input logic [2:0] rm_field, input logic [15:0] imm);
        begin
            emit8(8'h66);
            emit8(8'h67);
            emit8(8'hC7);
            emit8({2'b00, 3'b000, rm_field});
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
        extra_store_seen = 1'b0;
        for (int i = 0; i < 6; i++) begin
            observed_store_addr[i] = 32'h0;
            observed_store_data[i] = 32'h0;
            observed_store_be[i] = 4'h0;
        end

        clear_memory();
        write_mem32(32'h00001020, 32'h1111115A);
        write_mem32(32'h000020F0, 32'hA1A2A3A4);
        write_mem32(32'h00008030, 32'h22222222);
        write_mem32(32'h00009100, 32'h33333333);

        expected_t2[0] = 32'h00001020; // [BP+SI], 8FF0+8030 wraps
        expected_t2[1] = 32'h000020F0; // [BP+DI], 8FF0+9100 wraps
        expected_t2[2] = 32'h00001020; // [BP+SI]
        expected_t2[3] = 32'h000020F0; // [BP+DI]
        expected_t2[4] = 32'h00001020; // [BP+SI]
        expected_t2[5] = 32'h000020F0; // [BP+DI]
        expected_t2[6] = 32'h00001020; // [BP+SI]
        expected_t2[7] = 32'h000020F0; // [BP+DI]
        expected_t2[8] = 32'h00001020; // [BP+SI]

        expected_store_addr[0] = 32'h000020F0;
        expected_store_be[0]   = 4'b0001;
        expected_store_data[0] = 32'h000000BB;
        expected_store_addr[1] = 32'h00001020;
        expected_store_be[1]   = 4'b1111;
        expected_store_data[1] = 32'h1122AABB;
        expected_store_addr[2] = 32'h000020F0;
        expected_store_be[2]   = 4'b0011;
        expected_store_data[2] = 32'h0000AABB;
        expected_store_addr[3] = 32'h00001020;
        expected_store_be[3]   = 4'b0001;
        expected_store_data[3] = 32'h0000006B;
        expected_store_addr[4] = 32'h000020F0;
        expected_store_be[4]   = 4'b1111;
        expected_store_data[4] = 32'h55667788;
        expected_store_addr[5] = 32'h00001020;
        expected_store_be[5]   = 4'b0011;
        expected_store_data[5] = 32'h0000BEEF;

        program_pc = RESET_EIP;
        append_mov32_imm(3'h0, 32'h1122AABB); // EAX source for stores
        append_mov32_imm(3'h5, 32'h00008FF0); // EBP/BP address term
        append_mov32_imm(3'h6, 32'h00008030); // ESI/SI address term
        append_mov32_imm(3'h7, 32'h00009100); // EDI/DI address term
        append_addr16_modrm(8'h8A, 3'h1, 3'b010);      // CL <- [BP+SI]
        append_addr16_modrm(8'h8B, 3'h2, 3'b011);      // EDX <- [BP+DI]
        append_addr16_modrm_66(8'h8B, 3'h3, 3'b010);   // BX <- [BP+SI]
        append_addr16_modrm(8'h88, 3'h0, 3'b011);      // [BP+DI] <- AL
        append_addr16_modrm(8'h89, 3'h0, 3'b010);      // [BP+SI] <- EAX
        append_addr16_modrm_66(8'h89, 3'h0, 3'b011);   // [BP+DI] <- AX
        append_c6_addr16(3'b010, 8'h6B);               // [BP+SI] <- imm8
        append_c7_addr16(3'b011, 32'h55667788);        // [BP+DI] <- imm32
        append_66_c7_addr16(3'b010, 16'hBEEF);         // [BP+SI] <- imm16
        program_end_eip = program_pc;

        $display("Keystone86 / Aegis - Rung 6 Pass 6H-3 MOV addr16 no-disp BP Smoke");

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
        store_bus_count = 0;
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
                    if (mov_endi_count == 13) begin
                        timed_out = 1'b0;
                        @(posedge clk);
                        #1;
                        disable wait_movs;
                    end
                end
            end
        end

        check("four setup MOVs plus nine addr16 BP no-disp MOVs completed",
              !timed_out && (mov_endi_count == 13));
        check("ENTRY_MOV routed for all setup and addr16 BP no-disp forms",
              mov_route_count == 13);
        check("EA_CALC_16 issued for each addr16 memory MOV", ea_calc16_count == 9);
        check("EA_CALC_32 not issued for addr16 BP no-disp MOVs", ea_calc32_count == 0);
        check("T2 checked for every addr16 BP no-disp MOV", t2_check_count == 9);
        check("BP-based two-register addr16 forms wrapped before zero-extension",
              (expected_t2[0] == 32'h00001020) &&
              (expected_t2[1] == 32'h000020F0));
        check("LOAD_RM8 issued for 67+8A", load_rm8_count == 1);
        check("LOAD_RM32 issued for 67+8B", load_rm32_count == 1);
        check("LOAD_RM16 issued for 66+67+8B", load_rm16_count == 1);
        check("STORE_RM8 issued for 67+88 and 67+C6", store_rm8_count == 2);
        check("STORE_RM32 issued for 67+89 and 67+C7", store_rm32_count == 2);
        check("STORE_RM16 issued for 66+67+89 and 66+67+C7", store_rm16_count == 2);
        check("FETCH_IMM8 issued for 67+C6", fetch_imm8_count == 1);
        check("FETCH_IMM16 issued for 66+67+C7", fetch_imm16_count == 1);
        check("FETCH_IMM32 issued for setup MOVs and 67+C7", fetch_imm32_count == 5);
        check("all STORE_RM bus writes observed", store_bus_count == 6);
        check("no extra STORE_RM bus write observed", !extra_store_seen);
        for (int i = 0; i < 6; i++) begin
            check("STORE_RM bus write address matches expected sequence",
                  observed_store_addr[i] == expected_store_addr[i]);
            check("STORE_RM bus byte-enable matches expected sequence",
                  observed_store_be[i] == expected_store_be[i]);
            check("STORE_RM bus data matches expected sequence",
                  mask_store_data(observed_store_data[i], observed_store_be[i]) ==
                  mask_store_data(expected_store_data[i], expected_store_be[i]));
        end
        check("STORE_RM8 byte enable observed", byteen_0001_count == 2);
        check("STORE_RM16 byte enable observed", byteen_0011_count == 2);
        check("STORE_RM32 byte enable observed", byteen_1111_count == 2);

        check("67+8A loaded byte through [BP+SI] into CL",
              dut.u_commit.gpr_r[3'h1] == 32'h0000005A);
        check("67+8B loaded dword through [BP+DI] into EDX",
              dut.u_commit.gpr_r[3'h2] == 32'hA1A2A3A4);
        check("66+67+8B loaded word through [BP+SI] into BX",
              dut.u_commit.gpr_r[3'h3] == 32'h0000115A);
        check("67+89/C6/66+C7 final stores through [BP+SI]",
              read_mem32(32'h00001020) == 32'h1122BEEF);
        check("88/66+89/C7 final stores through [BP+DI]",
              read_mem32(32'h000020F0) == 32'h55667788);
        check("EFLAGS unchanged", dut.u_commit.eflags_r == 32'h00000002);
        check("fall-through EIP after Pass 6H-3 MOV sequence", dbg_eip == program_end_eip);
        check("no fault after addr16 BP no-disp MOV sequence", !dbg_fault_pending);

        run_unsupported_form(3, 8'h67, 8'h8B, 8'hC0, 8'h00, 8'h00, 8'h00,
                             "0x67 ModRM.mod=11 register form");
        run_unsupported_form(4, 8'h67, 8'hC7, 8'h08, 8'h34, 8'h12, 8'h00,
                             "0x67 C7 non-/0 no-disp form");
        run_unsupported_prefix_order(4, 8'h67, 8'h66, 8'h8B, 8'h00, 8'h00, 8'h00,
                                     "unsupported 67+66 prefix order");

        if (failures == 0) begin
            $display("PASS: Rung 6 Pass 6H-3 MOV addr16 no-disp BP smoke completed");
        end else begin
            $display("FAIL: Rung 6 Pass 6H-3 MOV addr16 no-disp BP smoke had %0d failure(s)",
                     failures);
            $fatal(1, "Rung 6 Pass 6H-3 MOV addr16 no-disp BP smoke failed");
        end

        $finish;
    end

endmodule
