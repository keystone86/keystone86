// Keystone86 / Aegis
// rtl/core/cpu_top.sv
//
// Rung 2/3 top-level with service-based control-transfer paths.

import keystone86_pkg::*;

module cpu_top (
    input  logic        clk,
    input  logic        reset_n,

    // --- Main bus ---
    output logic [31:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,
    output logic [3:0]  bus_byteen,
    output logic [31:0] bus_dout,
    input  logic [31:0] bus_din,
    input  logic        bus_ready,

    // --- Debug ports ---
    output logic [31:0] dbg_eip,
    output logic [31:0] dbg_esp,
    output logic [1:0]  dbg_mseq_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id,
    output logic [7:0]  dbg_dec_entry_id,
    output logic        dbg_endi_pulse,
    output logic        dbg_fault_pending,
    output logic [3:0]  dbg_fault_class,
    output logic        dbg_decode_done,
    output logic [31:0] dbg_fetch_addr
);

    // ------------------------------------------------------------
    // Bus/prefetch
    // ------------------------------------------------------------
    logic        fetch_req;
    logic [31:0] fetch_addr_internal;
    logic        fetch_done;
    logic [7:0]  fetch_data;
    logic        eu_req;
    logic        eu_wr;
    logic [31:0] eu_addr;
    logic [3:0]  eu_byteen;
    logic [31:0] eu_wdata;
    logic        eu_done;
    logic [31:0] eu_rdata;
    logic        commit_stack_wr_pending;
    logic [31:0] commit_stack_wr_addr_r;
    logic [31:0] commit_stack_wr_data_r;
    logic [3:0]  commit_stack_wr_byteen_r;

    logic [7:0]  q_data;
    logic        q_valid;
    logic        q_consume_dec;
    logic        fe_q_consume;
    logic        q_consume;
    logic [31:0] q_fetch_eip;

    logic        flush_req;
    logic [31:0] flush_addr;
    logic        squash;

    assign q_consume = q_consume_dec | fe_q_consume;

    // ------------------------------------------------------------
    // Decoder -> microsequencer
    // ------------------------------------------------------------
    logic        decode_done;
    logic [7:0]  entry_id;
    logic [31:0] next_eip;
    logic [31:0] dec_target_eip;
    logic        dec_has_target;
    logic        dec_is_call;
    logic        dec_is_ret;
    logic        dec_has_ret_imm;
    logic [15:0] dec_ret_imm;
    logic [7:0]  dec_modrm_byte;
    logic [7:0]  dec_sib_byte;
    logic        dec_modrm_present;
    logic [3:0]  dec_modrm_class;
    logic        dec_disp_valid;
    logic [31:0] dec_disp_value;
    logic        dec_payload16_valid;
    logic        dec_payload16_signed;
    logic [15:0] dec_payload16;
    logic [3:0]  dec_cond_code;
    logic        dec_ack;

    // ------------------------------------------------------------
    // Microcode ROM
    // ------------------------------------------------------------
    logic [11:0] upc;
    logic [31:0] uinst;
    logic [7:0]  dispatch_entry;
    logic [11:0] dispatch_upc;

    // ------------------------------------------------------------
    // Commit engine / architectural state
    // ------------------------------------------------------------
    logic        endi_req;
    logic [9:0]  endi_mask;
    logic        endi_done;
    logic        raise_req;
    logic [3:0]  raise_fc;
    logic [31:0] raise_fe;

    logic        pc_eip_en;
    logic [31:0] pc_eip_val;
    logic        pc_target_en;
    logic [31:0] pc_target_val;
    logic        pc_stack_adj_en;
    logic [31:0] pc_stack_adj_val;
    logic [31:0] stack_push_data;

    logic        mode_prot;
    logic        cs_d_bit;
    logic [31:0] eip;
    logic [31:0] esp;
    logic [31:0] eflags;
    logic [15:0] cs;

    logic        fault_pending;
    logic [3:0]  fault_class;
    logic [31:0] fault_error;

    // ------------------------------------------------------------
    // Service dispatch
    // ------------------------------------------------------------
    logic [7:0]  svc_id_out;
    logic        svc_req_out;
    logic        svc_done_in;
    logic [1:0]  svc_sr_in;

    // fetch_engine side
    logic [7:0]  fe_svc_id;
    logic        fe_svc_req;
    logic        fe_svc_done;
    logic [1:0]  fe_svc_sr;
    logic        fe_t4_wr_en;
    logic [31:0] fe_t4_wr_data;

    // flow_control side
    logic [7:0]  fc_svc_id;
    logic        fc_svc_req;
    logic        fc_svc_done;
    logic [1:0]  fc_svc_sr;
    logic        fc_t2_wr_en;
    logic [31:0] fc_t2_wr_data;
    logic        fc_t3_wr_en;
    logic [31:0] fc_t3_wr_data;

    // operand_engine side
    logic [7:0]  op_svc_id;
    logic        op_svc_req;
    logic        op_svc_done;
    logic [1:0]  op_svc_sr;
    logic        op_t2_wr_en;
    logic [31:0] op_t2_wr_data;
    logic        op_mem_rd_req;
    logic [31:0] op_mem_rd_addr;
    logic        op_mem_rd_ready;
    logic [31:0] op_mem_rd_data;

    // stack_engine side
    logic [7:0]  se_svc_id;
    logic        se_svc_req;
    logic        se_svc_done;
    logic [1:0]  se_svc_sr;
    logic        se_t2_wr_en;
    logic [31:0] se_t2_wr_data;
    logic        se_stk_rd_req;
    logic [31:0] se_stk_rd_addr;
    logic        se_stk_rd_ready;
    logic [31:0] se_stk_rd_data;
    logic        pc_stack_en;
    logic        pc_stack_write_en;
    logic [31:0] pc_stack_addr;
    logic [31:0] pc_stack_data;
    logic [31:0] pc_stack_esp_val;
    logic        commit_stk_wr_en;
    logic [31:0] commit_stk_wr_addr;
    logic [31:0] commit_stk_wr_data;
    logic [3:0]  commit_stk_wr_byteen;

    // interrupt_engine side
    logic [7:0]  ie_svc_id;
    logic        ie_svc_req;
    logic        ie_svc_done;
    logic [1:0]  ie_svc_sr;
    logic        ie_mem_rd_req;
    logic [31:0] ie_mem_rd_addr;
    logic        ie_mem_rd_ready;
    logic [31:0] ie_mem_rd_data;
    logic        pc_int_en;
    logic [31:0] pc_int_eip;
    logic [15:0] pc_int_cs;
    logic [31:0] pc_int_eflags;
    logic [31:0] pc_int_esp;
    logic        pc_int_frame_write_en;
    logic [31:0] pc_int_frame_addr;
    logic [47:0] pc_int_frame_bytes;

    // scratch/state registers used by current rung2 path
    logic [31:0] t2_r;
    logic [31:0] t3_r;
    logic [31:0] t4_r;
    logic        mseq_t4_wr_en;
    logic [31:0] mseq_t4_wr_data;
    logic [31:0] meta_next_eip;
    logic [3:0]  meta_cond_code;
    logic        meta_modrm_present_r;
    logic [7:0]  meta_modrm_byte_r;
    logic [7:0]  meta_sib_byte_r;
    logic [3:0]  meta_modrm_class_r;
    logic [31:0] meta_disp_value_r;

    // debug wires from microsequencer
    logic [1:0]  dbg_mseq_state_w;
    logic [11:0] dbg_upc_w;
    logic [7:0]  dbg_entry_id_w;

    assign dbg_eip           = eip;
    assign dbg_esp           = esp;
    assign dbg_mseq_state    = dbg_mseq_state_w;
    assign dbg_upc           = dbg_upc_w;
    assign dbg_entry_id      = dbg_entry_id_w;
    assign dbg_dec_entry_id  = entry_id;
    assign dbg_endi_pulse    = endi_done;
    assign dbg_fault_pending = fault_pending;
    assign dbg_fault_class   = fault_class;
    assign dbg_decode_done   = decode_done;
    assign dbg_fetch_addr    = fetch_addr_internal;

    assign eu_req     = commit_stack_wr_pending || ie_mem_rd_req ||
                        se_stk_rd_req || op_mem_rd_req;
    assign eu_wr      = commit_stack_wr_pending;
    assign eu_addr    = commit_stack_wr_pending ? commit_stack_wr_addr_r :
                        (ie_mem_rd_req ? ie_mem_rd_addr :
                        (se_stk_rd_req ? se_stk_rd_addr : op_mem_rd_addr));
    assign eu_byteen  = commit_stack_wr_pending ? commit_stack_wr_byteen_r : 4'b1111;
    assign eu_wdata   = commit_stack_wr_pending ? commit_stack_wr_data_r : 32'h0;

    assign ie_mem_rd_ready = (!commit_stack_wr_pending) && ie_mem_rd_req && eu_done;
    assign ie_mem_rd_data  = eu_rdata;
    assign se_stk_rd_ready = (!commit_stack_wr_pending) && (!ie_mem_rd_req) && eu_done;
    assign se_stk_rd_data  = eu_rdata;
    assign op_mem_rd_ready = (!commit_stack_wr_pending) && (!ie_mem_rd_req) &&
                             (!se_stk_rd_req) && eu_done;
    assign op_mem_rd_data  = eu_rdata;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            commit_stack_wr_pending <= 1'b0;
            commit_stack_wr_addr_r  <= 32'h0;
            commit_stack_wr_data_r  <= 32'h0;
            commit_stack_wr_byteen_r <= 4'h0;
        end else begin
            if (commit_stack_wr_pending && eu_done) begin
                if (commit_stk_wr_en) begin
                    commit_stack_wr_pending <= 1'b1;
                    commit_stack_wr_addr_r  <= commit_stk_wr_addr;
                    commit_stack_wr_data_r  <= commit_stk_wr_data;
                    commit_stack_wr_byteen_r <= commit_stk_wr_byteen;
                end else begin
                    commit_stack_wr_pending <= 1'b0;
                end
            end else if (commit_stk_wr_en && !commit_stack_wr_pending) begin
                commit_stack_wr_pending <= 1'b1;
                commit_stack_wr_addr_r  <= commit_stk_wr_addr;
                commit_stack_wr_data_r  <= commit_stk_wr_data;
                commit_stack_wr_byteen_r <= commit_stk_wr_byteen;
            end
        end
    end

    // ------------------------------------------------------------
    // Simple T2/T4 storage for current service path
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            t2_r <= 32'h0;
            t3_r <= 32'h0;
            t4_r <= 32'h0;
            meta_modrm_present_r <= 1'b0;
            meta_modrm_byte_r    <= 8'h0;
            meta_sib_byte_r      <= 8'h0;
            meta_modrm_class_r   <= 4'hF;
            meta_disp_value_r    <= 32'h0;
        end else begin
            if (dec_ack) begin
                meta_modrm_present_r <= dec_modrm_present;
                meta_modrm_byte_r    <= dec_modrm_byte;
                meta_sib_byte_r      <= dec_sib_byte;
                meta_modrm_class_r   <= dec_modrm_class;
                meta_disp_value_r    <= dec_disp_value;
            end
            if (fe_t4_wr_en) t4_r <= fe_t4_wr_data;
            if (mseq_t4_wr_en) t4_r <= mseq_t4_wr_data;
            if (dec_ack && dec_payload16_valid) begin
                if (dec_payload16_signed)
                    t4_r <= {{16{dec_payload16[15]}}, dec_payload16};
                else
                    t4_r <= {16'h0, dec_payload16};
            end else if (dec_ack && dec_is_ret && !dec_has_ret_imm) begin
                t4_r <= 32'h0;
            end
            if (fc_t2_wr_en) t2_r <= fc_t2_wr_data;
            if (fc_t3_wr_en) t3_r <= fc_t3_wr_data;
            if (op_t2_wr_en) t2_r <= op_t2_wr_data;
            if (se_t2_wr_en) t2_r <= se_t2_wr_data;
        end
    end

    // ------------------------------------------------------------
    // Bus + prefetch
    // ------------------------------------------------------------
    bus_interface u_bus (
        .clk        (clk),
        .reset_n    (reset_n),
        .fetch_req  (fetch_req),
        .fetch_addr (fetch_addr_internal),
        .fetch_done (fetch_done),
        .fetch_data (fetch_data),
        .eu_req     (eu_req),
        .eu_wr      (eu_wr),
        .eu_addr    (eu_addr),
        .eu_byteen  (eu_byteen),
        .eu_wdata   (eu_wdata),
        .eu_done    (eu_done),
        .eu_rdata   (eu_rdata),
        .bus_addr   (bus_addr),
        .bus_rd     (bus_rd),
        .bus_wr     (bus_wr),
        .bus_byteen (bus_byteen),
        .bus_dout   (bus_dout),
        .bus_din    (bus_din),
        .bus_ready  (bus_ready)
    );

    prefetch_queue #(.DEPTH(4)) u_pq (
        .clk         (clk),
        .reset_n     (reset_n),
        .flush       (flush_req),
        .flush_addr  (flush_addr),
        // Commit flush is the authoritative prefetch redirect/cleanup path.
        // The microsequencer squash clears stale decoder state at delayed ENDI
        // completion; feeding that late pulse into the queue would discard
        // already-fetched handler bytes for the Rung 5 INT/IRET path.
        .kill        (1'b0),
        .q_data      (q_data),
        .q_valid     (q_valid),
        .q_consume   (q_consume),
        .q_fetch_eip (q_fetch_eip),
        .fetch_req   (fetch_req),
        .fetch_addr  (fetch_addr_internal),
        .fetch_done  (fetch_done),
        .fetch_data  (fetch_data)
    );

    // ------------------------------------------------------------
    // Front-end decode
    // ------------------------------------------------------------
    decoder u_dec (
        .clk          (clk),
        .reset_n      (reset_n),
        .squash       (squash),
        .mode_prot    (mode_prot),
        .cs_d_bit     (cs_d_bit),
        .q_data       (q_data),
        .q_valid      (q_valid),
        .q_consume    (q_consume_dec),
        .decode_done  (decode_done),
        .entry_id     (entry_id),
        .next_eip     (next_eip),
        .target_eip   (dec_target_eip),
        .has_target   (dec_has_target),
        .is_call      (dec_is_call),
        .is_call_indirect (),
        .is_ret       (dec_is_ret),
        .has_ret_imm  (dec_has_ret_imm),
        .ret_imm      (dec_ret_imm),
        .modrm_byte   (dec_modrm_byte),
        .sib_byte     (dec_sib_byte),
        .modrm_present(dec_modrm_present),
        .modrm_class  (dec_modrm_class),
        .disp_valid   (dec_disp_valid),
        .disp_value   (dec_disp_value),
        .payload16_valid (dec_payload16_valid),
        .payload16_signed(dec_payload16_signed),
        .payload16    (dec_payload16),
        .cond_code    (dec_cond_code),
        .dec_ack      (dec_ack),
        .q_fetch_eip  (q_fetch_eip)
    );

    // ------------------------------------------------------------
    // Microsequencer + ROM
    // ------------------------------------------------------------
    microsequencer u_mseq (
        .clk             (clk),
        .reset_n         (reset_n),
        .decode_done     (decode_done),
        .entry_id_in     (entry_id),
        .next_eip_in     (next_eip),
        .cond_code_in    (dec_cond_code),
        .dec_is_call     (dec_is_call),
        .dec_is_ret      (dec_is_ret),
        .dec_ack         (dec_ack),
        .squash          (squash),
        .upc             (upc),
        .uinst           (uinst),
        .dispatch_entry  (dispatch_entry),
        .dispatch_upc_in (dispatch_upc),

        .endi_req        (endi_req),
        .endi_mask       (endi_mask),
        .raise_req       (raise_req),
        .raise_fc        (raise_fc),
        .raise_fe        (raise_fe),
        .endi_done       (endi_done),
        .fault_class_in  (fault_class),

        .pc_eip_en       (pc_eip_en),
        .pc_eip_val      (pc_eip_val),
        .pc_target_en    (pc_target_en),
        .pc_target_val   (pc_target_val),
        .pc_stack_adj_en (pc_stack_adj_en),
        .pc_stack_adj_val(pc_stack_adj_val),
        .stack_push_data (stack_push_data),
        .mseq_t4_wr_en   (mseq_t4_wr_en),
        .mseq_t4_wr_data (mseq_t4_wr_data),

        .svc_id_out      (svc_id_out),
        .svc_req_out     (svc_req_out),
        .svc_done_in     (svc_done_in),
        .svc_sr_in       (svc_sr_in),

        .t2_data         (t2_r),
        .t4_data         (t4_r),
        .t3_data         (t3_r),
        .meta_next_eip   (meta_next_eip),
        .meta_cond_code  (meta_cond_code),

        .dbg_state       (dbg_mseq_state_w),
        .dbg_upc         (dbg_upc_w),
        .dbg_entry_id    (dbg_entry_id_w)
    );

    microcode_rom u_rom (
        .clk          (clk),
        .upc          (upc),
        .uinst        (uinst),
        .entry_id     (dispatch_entry),
        .dispatch_upc (dispatch_upc)
    );

    // ------------------------------------------------------------
    // Services
    // ------------------------------------------------------------
    service_dispatch u_sdispatch (
        .svc_id      (svc_id_out),
        .svc_req     (svc_req_out),
        .svc_done    (svc_done_in),
        .svc_sr      (svc_sr_in),

        .fe_svc_id   (fe_svc_id),
        .fe_svc_req  (fe_svc_req),
        .fe_svc_done (fe_svc_done),
        .fe_svc_sr   (fe_svc_sr),

        .fc_svc_id   (fc_svc_id),
        .fc_svc_req  (fc_svc_req),
        .fc_svc_done (fc_svc_done),
        .fc_svc_sr   (fc_svc_sr),

        .op_svc_id   (op_svc_id),
        .op_svc_req  (op_svc_req),
        .op_svc_done (op_svc_done),
        .op_svc_sr   (op_svc_sr),

        .se_svc_id   (se_svc_id),
        .se_svc_req  (se_svc_req),
        .se_svc_done (se_svc_done),
        .se_svc_sr   (se_svc_sr),

        .ie_svc_id   (ie_svc_id),
        .ie_svc_req  (ie_svc_req),
        .ie_svc_done (ie_svc_done),
        .ie_svc_sr   (ie_svc_sr)
    );

    fetch_engine u_fetch_eng (
        .clk         (clk),
        .reset_n     (reset_n),
        .svc_id      (fe_svc_id),
        .svc_req     (fe_svc_req),
        .svc_done    (fe_svc_done),
        .svc_sr      (fe_svc_sr),
        .q_data      (q_data),
        .q_valid     (q_valid),
        .q_consume   (fe_q_consume),
        .q_fetch_eip (q_fetch_eip),
        .t4_wr_en    (fe_t4_wr_en),
        .t4_wr_data  (fe_t4_wr_data),
        .squash      (squash)
    );

    flow_control u_flow (
        .clk           (clk),
        .reset_n       (reset_n),
        .svc_id        (fc_svc_id),
        .svc_req       (fc_svc_req),
        .svc_done      (fc_svc_done),
        .svc_sr        (fc_svc_sr),
        .t2_in         (t2_r),
        .t4_in         (t4_r),
        .t2_wr_en      (fc_t2_wr_en),
        .t2_wr_data    (fc_t2_wr_data),
        .t3_wr_en      (fc_t3_wr_en),
        .t3_wr_data    (fc_t3_wr_data),
        .m_next_eip    (meta_next_eip),
        .m_cond_code   (meta_cond_code),
        .eflags_in     (eflags),
        .mode_prot     (mode_prot),
        .fault_req     (),
        .fault_fc      ()
    );

    operand_engine u_operand (
        .clk           (clk),
        .reset_n       (reset_n),
        .svc_id        (op_svc_id),
        .svc_req       (op_svc_req),
        .svc_done      (op_svc_done),
        .svc_sr        (op_svc_sr),
        .esp_in        (esp),
        .modrm_present (meta_modrm_present_r),
        .modrm_byte    (meta_modrm_byte_r),
        .sib_byte      (meta_sib_byte_r),
        .modrm_class   (meta_modrm_class_r),
        .disp_value    (meta_disp_value_r),
        .mem_rd_req    (op_mem_rd_req),
        .mem_rd_addr   (op_mem_rd_addr),
        .mem_rd_data   (op_mem_rd_data),
        .mem_rd_ready  (op_mem_rd_ready),
        .t2_wr_en      (op_t2_wr_en),
        .t2_wr_data    (op_t2_wr_data)
    );

    stack_engine u_stack (
        .clk              (clk),
        .reset_n          (reset_n),
        .svc_id           (se_svc_id),
        .svc_req          (se_svc_req),
        .svc_done         (se_svc_done),
        .svc_sr           (se_svc_sr),
        .esp_in           (esp),
        .push_data        (stack_push_data),
        .stk_rd_req       (se_stk_rd_req),
        .stk_rd_addr      (se_stk_rd_addr),
        .stk_rd_data      (se_stk_rd_data),
        .stk_rd_ready     (se_stk_rd_ready),
        .t2_wr_en         (se_t2_wr_en),
        .t2_wr_data       (se_t2_wr_data),
        .pc_stack_en      (pc_stack_en),
        .pc_stack_write_en(pc_stack_write_en),
        .pc_stack_addr    (pc_stack_addr),
        .pc_stack_data    (pc_stack_data),
        .pc_stack_esp_val (pc_stack_esp_val)
    );

    interrupt_engine u_interrupt (
        .clk                (clk),
        .reset_n            (reset_n),
        .svc_id             (ie_svc_id),
        .svc_req            (ie_svc_req),
        .svc_done           (ie_svc_done),
        .svc_sr             (ie_svc_sr),
        .vector_in          (t4_r),
        .m_next_eip         (meta_next_eip),
        .eflags_in          (eflags),
        .esp_in             (esp),
        .cs_in              (cs),
        .mem_rd_req         (ie_mem_rd_req),
        .mem_rd_addr        (ie_mem_rd_addr),
        .mem_rd_data        (ie_mem_rd_data),
        .mem_rd_ready       (ie_mem_rd_ready),
        .pc_int_en          (pc_int_en),
        .pc_int_eip         (pc_int_eip),
        .pc_int_cs          (pc_int_cs),
        .pc_int_eflags      (pc_int_eflags),
        .pc_int_esp         (pc_int_esp),
        .pc_int_frame_write_en(pc_int_frame_write_en),
        .pc_int_frame_addr  (pc_int_frame_addr),
        .pc_int_frame_bytes (pc_int_frame_bytes)
    );

    // ------------------------------------------------------------
    // Commit / architectural visibility
    // ------------------------------------------------------------
    commit_engine u_commit (
        .clk                        (clk),
        .reset_n                    (reset_n),
        .endi_req                   (endi_req),
        .endi_mask                  (endi_mask),
        .endi_done                  (endi_done),
        .raise_req                  (raise_req),
        .raise_fc                   (raise_fc),
        .raise_fe                   (raise_fe),

        .pc_gpr_en                  (1'b0),
        .pc_gpr_idx                 (3'h0),
        .pc_gpr_val                 (32'h0),

        .pc_eip_en                  (pc_eip_en),
        .pc_eip_val                 (pc_eip_val),
        .pc_target_en               (pc_target_en),
        .pc_target_val              (pc_target_val),

        .pc_stack_en                (pc_stack_en),
        .pc_stack_write_en          (pc_stack_write_en),
        .pc_stack_addr              (pc_stack_addr),
        .pc_stack_data              (pc_stack_data),
        .pc_stack_esp_val           (pc_stack_esp_val),
        .pc_stack_adj_en            (pc_stack_adj_en),
        .pc_stack_adj_val           (pc_stack_adj_val),

        .pc_int_en                  (pc_int_en),
        .pc_int_eip                 (pc_int_eip),
        .pc_int_cs                  (pc_int_cs),
        .pc_int_eflags              (pc_int_eflags),
        .pc_int_esp                 (pc_int_esp),
        .pc_int_frame_write_en      (pc_int_frame_write_en),
        .pc_int_frame_addr          (pc_int_frame_addr),
        .pc_int_frame_bytes         (pc_int_frame_bytes),

        .eip                        (eip),
        .esp                        (esp),
        .eflags                     (eflags),
        .cs                         (cs),
        .mode_prot                  (mode_prot),
        .cs_d_bit                   (cs_d_bit),

        .flush_req                  (flush_req),
        .flush_addr                 (flush_addr),

        .stk_wr_en                  (commit_stk_wr_en),
        .stk_wr_addr                (commit_stk_wr_addr),
        .stk_wr_data                (commit_stk_wr_data),
        .stk_wr_byteen              (commit_stk_wr_byteen),
        .stk_wr_done                (commit_stack_wr_pending && eu_done),

        .fault_pending              (fault_pending),
        .fault_class                (fault_class),
        .fault_error                (fault_error)
    );

endmodule
