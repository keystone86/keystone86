// Keystone86 / Aegis
// rtl/core/cpu_top.sv
// Rung 3: Wire CALL/RET signals through all modules
// (includes all Rung 2 wiring)
//
// Rung 3 additions:
//   - is_call, is_ret, has_ret_imm, ret_imm, modrm_byte: decoder -> microsequencer
//   - pc_ret_addr_en/val, pc_ret_imm_en/val: microsequencer -> commit_engine
//   - indirect_call_target/valid: cpu_top ports (testbench drives register)
//   - stk_wr_*/stk_rd_*: commit_engine -> top-level stack bus ports
//   - esp: commit_engine -> dbg_esp output

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

    // --- Stack bus (Rung 3) ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,
    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,

    // --- Indirect CALL target (Rung 3: from register file / testbench) ---
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

    logic        fetch_req;
    logic [31:0] fetch_addr_internal;
    logic        fetch_done;
    logic [7:0]  fetch_data;

    logic [7:0]  q_data;
    logic        q_valid;
    logic        q_consume;
    logic [31:0] q_fetch_eip;

    logic        flush_req;
    logic [31:0] flush_addr;

    logic        squash;

    logic        decode_done;
    logic [7:0]  entry_id;
    logic [31:0] next_eip;
    logic [31:0] target_eip;
    logic        has_target;
    logic        is_call;        // Rung 3
    logic        is_ret;         // Rung 3
    logic        has_ret_imm;    // Rung 3
    logic [15:0] ret_imm;        // Rung 3
    logic [7:0]  modrm_byte;     // Rung 3
    logic        dec_ack;

    logic [11:0] upc;
    logic [31:0] uinst;
    logic [7:0]  dispatch_entry;
    logic [11:0] dispatch_upc;

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
    logic        pc_ret_addr_en;   // Rung 3
    logic [31:0] pc_ret_addr_val;  // Rung 3
    logic        pc_ret_imm_en;    // Rung 3
    logic [15:0] pc_ret_imm_val;   // Rung 3

    logic        mode_prot;
    logic        cs_d_bit;

    logic [31:0] eip;
    logic [31:0] esp;
    logic        fault_pending;
    logic [3:0]  fault_class;
    logic [31:0] fault_error;

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

    bus_interface u_bus (
        .clk        (clk),
        .reset_n    (reset_n),
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

    decoder u_dec (
        .clk          (clk),
        .reset_n      (reset_n),
        .squash       (squash),
        .mode_prot    (mode_prot),
        .cs_d_bit     (cs_d_bit),
        .q_data       (q_data),
        .q_valid      (q_valid),
        .q_consume    (q_consume),
        .decode_done  (decode_done),
        .entry_id     (entry_id),
        .next_eip     (next_eip),
        .target_eip   (target_eip),
        .has_target   (has_target),
        .is_call      (is_call),        // Rung 3
        .is_ret       (is_ret),         // Rung 3
        .has_ret_imm  (has_ret_imm),    // Rung 3
        .ret_imm      (ret_imm),        // Rung 3
        .modrm_byte   (modrm_byte),     // Rung 3
        .dec_ack      (dec_ack),
        .q_fetch_eip  (q_fetch_eip)
    );

    microsequencer u_mseq (
        .clk              (clk),
        .reset_n          (reset_n),
        .decode_done      (decode_done),
        .entry_id_in      (entry_id),
        .next_eip_in      (next_eip),
        .target_eip_in    (target_eip),
        .has_target_in    (has_target),
        .is_call_in       (is_call),         // Rung 3
        .is_ret_in        (is_ret),          // Rung 3
        .has_ret_imm_in   (has_ret_imm),     // Rung 3
        .ret_imm_in       (ret_imm),         // Rung 3
        .modrm_in         (modrm_byte),      // Rung 3
        .dec_ack          (dec_ack),
        .squash           (squash),
        .upc              (upc),
        .uinst            (uinst),
        .dispatch_entry   (dispatch_entry),
        .dispatch_upc_in  (dispatch_upc),
        .endi_req         (endi_req),
        .endi_mask        (endi_mask),
        .raise_req        (raise_req),
        .raise_fc         (raise_fc),
        .raise_fe         (raise_fe),
        .endi_done        (endi_done),
        .pc_eip_en        (pc_eip_en),
        .pc_eip_val       (pc_eip_val),
        .pc_target_en     (pc_target_en),
        .pc_target_val    (pc_target_val),
        .pc_ret_addr_en   (pc_ret_addr_en),  // Rung 3
        .pc_ret_addr_val  (pc_ret_addr_val), // Rung 3
        .pc_ret_imm_en    (pc_ret_imm_en),   // Rung 3
        .pc_ret_imm_val   (pc_ret_imm_val),  // Rung 3
        .dbg_state        (dbg_mseq_state_w),
        .dbg_upc          (dbg_upc_w),
        .dbg_entry_id     (dbg_entry_id_w)
    );

    microcode_rom u_rom (
        .clk          (clk),
        .upc          (upc),
        .uinst        (uinst),
        .entry_id     (dispatch_entry),
        .dispatch_upc (dispatch_upc)
    );

    commit_engine u_commit (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .endi_req                  (endi_req),
        .endi_mask                 (endi_mask),
        .endi_done                 (endi_done),
        .raise_req                 (raise_req),
        .raise_fc                  (raise_fc),
        .raise_fe                  (raise_fe),
        .pc_gpr_en                 (1'b0),
        .pc_gpr_idx                (3'h0),
        .pc_gpr_val                (32'h0),
        .pc_eip_en                 (pc_eip_en),
        .pc_eip_val                (pc_eip_val),
        .pc_target_en              (pc_target_en),
        .pc_target_val             (pc_target_val),
        .pc_ret_addr_en            (pc_ret_addr_en),           // Rung 3
        .pc_ret_addr_val           (pc_ret_addr_val),          // Rung 3
        .pc_ret_imm_en             (pc_ret_imm_en),            // Rung 3
        .pc_ret_imm_val            (pc_ret_imm_val),           // Rung 3
        .indirect_call_target      (indirect_call_target),     // Rung 3
        .indirect_call_target_valid(indirect_call_target_valid),// Rung 3
        .eip                       (eip),
        .esp                       (esp),
        .mode_prot                 (mode_prot),
        .cs_d_bit                  (cs_d_bit),
        .flush_req                 (flush_req),
        .flush_addr                (flush_addr),
        .stk_wr_en                 (stk_wr_en),                // Rung 3
        .stk_wr_addr               (stk_wr_addr),              // Rung 3
        .stk_wr_data               (stk_wr_data),              // Rung 3
        .stk_rd_req                (stk_rd_req),               // Rung 3
        .stk_rd_addr               (stk_rd_addr),              // Rung 3
        .stk_rd_data               (stk_rd_data),              // Rung 3
        .stk_rd_ready              (stk_rd_ready),             // Rung 3
        .fault_pending             (fault_pending),
        .fault_class               (fault_class),
        .fault_error               (fault_error)
    );

endmodule
