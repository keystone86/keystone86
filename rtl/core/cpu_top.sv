// Keystone86 / Aegis
// rtl/core/cpu_top.sv
//
// Rung 3 top-level: wires CALL/RET metadata from decoder to microsequencer,
// adds stack_engine instantiation, routes stack bus signals through stack_engine
// (not commit_engine), and connects pc_stack staging from stack_engine to
// commit_engine. The stack bus (stk_wr_en etc.) is exported as compatibility
// ports for the testbench stack memory model.

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

    // --- Compatibility ports expected by earlier rung testbenches ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,
    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,
    input  logic [31:0] indirect_call_target,
    input  logic        indirect_call_target_valid,

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

    logic        mode_prot;
    logic        cs_d_bit;
    logic [31:0] eip;
    logic [31:0] esp;

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

    // scratch/state registers used by current rung2 path
    logic [31:0] t2_r;
    logic [31:0] t4_r;
    logic [31:0] meta_next_eip;

    // Rung 3: decoder CALL/RET metadata wires (decoder → microsequencer)
    logic [31:0] dec_target_eip;
    logic        dec_has_target;
    logic        dec_is_call;
    logic        dec_is_ret;
    logic        dec_has_ret_imm;
    logic [15:0] dec_ret_imm;

    // Rung 3: RET imm16 adjustment (microsequencer → commit_engine)
    logic        pc_ret_imm_en;
    logic [15:0] pc_ret_imm_val;

    // Rung 3: staged new ESP from stack_engine (stack_engine → commit_engine)
    logic        pc_stack_en;
    logic [31:0] pc_stack_val;

    // Rung 3: stack_engine service routing
    logic [7:0]  sk_svc_id;
    logic        sk_svc_req;
    logic        sk_svc_done;
    logic [1:0]  sk_svc_sr;

    // Rung 3: T2 mux — stack_engine and flow_control both write T2
    // (popped return address and computed JMP target, respectively)
    logic        sk_t2_wr_en;
    logic [31:0] sk_t2_wr_data;

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

    // ------------------------------------------------------------
    // Simple T2/T4 storage for current service path
    //
    // T2 write priority: stack_engine (POP32 popped value) and flow_control
    // (COMPUTE_REL_TARGET result) are mutually exclusive by microcode sequencing —
    // they are never called in the same instruction's service sequence.
    // stack_engine wins if both somehow assert simultaneously (defensive).
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            t2_r <= 32'h0;
            t4_r <= 32'h0;
        end else begin
            if (fe_t4_wr_en) t4_r <= fe_t4_wr_data;
            if (sk_t2_wr_en) t2_r <= sk_t2_wr_data;
            else if (fc_t2_wr_en) t2_r <= fc_t2_wr_data;
        end
    end

    // ------------------------------------------------------------
    // Bus + prefetch
    // ------------------------------------------------------------
    bus_interface u_bus (
        .clk        (clk),
        .reset_n    (reset_n),
        .flush      (flush_req),
        .fetch_req  (fetch_req),
        .fetch_addr (fetch_addr_internal),
        .fetch_done (fetch_done),
        .fetch_data (fetch_data),
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
        .kill        (squash),
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
        // Rung 3: CALL/RET decode-owned metadata
        .target_eip   (dec_target_eip),
        .has_target   (dec_has_target),
        .is_call      (dec_is_call),
        .is_ret       (dec_is_ret),
        .has_ret_imm  (dec_has_ret_imm),
        .ret_imm      (dec_ret_imm),
        .modrm_byte   (),              // routed through decoder for classification only
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
        .dec_ack         (dec_ack),
        // Rung 3: CALL/RET metadata from decoder
        .is_call_in         (dec_is_call),
        .call_target_in     (dec_target_eip),
        .has_call_target_in (dec_has_target),
        .is_ret_in          (dec_is_ret),
        .has_ret_imm_in     (dec_has_ret_imm),
        .ret_imm_in         (dec_ret_imm),
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

        .pc_eip_en       (pc_eip_en),
        .pc_eip_val      (pc_eip_val),
        .pc_target_en    (pc_target_en),
        .pc_target_val   (pc_target_val),
        // Rung 3: RET imm16 adjustment to commit_engine
        .pc_ret_imm_en   (pc_ret_imm_en),
        .pc_ret_imm_val  (pc_ret_imm_val),

        .svc_id_out      (svc_id_out),
        .svc_req_out     (svc_req_out),
        .svc_done_in     (svc_done_in),
        .svc_sr_in       (svc_sr_in),

        .t2_data         (t2_r),
        .meta_next_eip   (meta_next_eip),

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

        // Rung 3: stack_engine routing
        .sk_svc_id   (sk_svc_id),
        .sk_svc_req  (sk_svc_req),
        .sk_svc_done (sk_svc_done),
        .sk_svc_sr   (sk_svc_sr)
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

    // Rung 3: stack_engine — PUSH32/POP32/PUSH16/POP16 service leaf.
    // push_val is wired to meta_next_eip (return address for CALL).
    // Popped value (RET return address) is written to T2 via sk_t2_wr_*.
    // New ESP is staged via pc_stack_en/val for commit_engine to apply at ENDI.
    // Stack bus (stk_wr_en etc.) is exported through cpu_top compatibility ports.
    stack_engine u_stack (
        .clk          (clk),
        .reset_n      (reset_n),
        .svc_id       (sk_svc_id),
        .svc_req      (sk_svc_req),
        .svc_done     (sk_svc_done),
        .svc_sr       (sk_svc_sr),
        .esp_in       (esp),
        .push_val     (meta_next_eip),
        .t2_wr_en     (sk_t2_wr_en),
        .t2_wr_data   (sk_t2_wr_data),
        .pc_stack_en  (pc_stack_en),
        .pc_stack_val (pc_stack_val),
        .stk_wr_en    (stk_wr_en),
        .stk_wr_addr  (stk_wr_addr),
        .stk_wr_data  (stk_wr_data),
        .stk_rd_req   (stk_rd_req),
        .stk_rd_addr  (stk_rd_addr),
        .stk_rd_data  (stk_rd_data),
        .stk_rd_ready (stk_rd_ready),
        .squash       (squash)
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
        .m_next_eip    (meta_next_eip),
        .mode_prot     (mode_prot),
        .fault_req     (),
        .fault_fc      ()
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

        // Rung 3: RET imm16 adjustment from microsequencer
        .pc_ret_imm_en              (pc_ret_imm_en),
        .pc_ret_imm_val             (pc_ret_imm_val),

        // Rung 3: new ESP staged by stack_engine after PUSH32/POP32
        .pc_stack_en                (pc_stack_en),
        .pc_stack_val               (pc_stack_val),

        .indirect_call_target       (indirect_call_target),
        .indirect_call_target_valid (indirect_call_target_valid),

        .eip                        (eip),
        .esp                        (esp),
        .mode_prot                  (mode_prot),
        .cs_d_bit                   (cs_d_bit),

        .flush_req                  (flush_req),
        .flush_addr                 (flush_addr),

        .fault_pending              (fault_pending),
        .fault_class                (fault_class),
        .fault_error                (fault_error)
    );

endmodule