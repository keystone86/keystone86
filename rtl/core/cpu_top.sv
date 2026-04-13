// Keystone86 / Aegis
// rtl/core/cpu_top.sv
// Rung 2: Wire squash, target_eip, has_target, pc_target_en/val
//
// Rung 2 changes from Rung 1:
//   - squash: microsequencer -> decoder + prefetch_queue
//   - target_eip / has_target: decoder -> microsequencer
//   - pc_target_en / pc_target_val: microsequencer -> commit_engine
//   - prefetch_queue now receives squash for inflight kill
//
// Control path (Rung 2):
//   reset -> commit_engine drives flush -> prefetch_queue fetches 0xFFFFFFF0
//         -> decoder forms JMP instruction (opcode + displacement)
//         -> microsequencer accepts payload, asserts squash, stages target_eip
//         -> ENDI CM_JMP commits target_eip to EIP and drives flush
//         -> prefetch_queue flushes and refills from JMP target
//         -> microsequencer returns to FETCH_DECODE
//         -> loop from JMP target

import keystone86_pkg::*;

module cpu_top (
    input  logic        clk,
    input  logic        reset_n,

    output logic [31:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,
    output logic [3:0]  bus_byteen,
    output logic [31:0] bus_dout,
    input  logic [31:0] bus_din,
    input  logic        bus_ready,

    output logic [31:0] dbg_eip,
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

    // Rung 2: squash signal (microsequencer -> decoder + prefetch_queue)
    logic        squash;

    logic        decode_done;
    logic [7:0]  entry_id;
    logic [31:0] next_eip;
    logic [31:0] target_eip;    // Rung 2
    logic        has_target;    // Rung 2
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
    logic        pc_target_en;   // Rung 2
    logic [31:0] pc_target_val;  // Rung 2

    logic        mode_prot;
    logic        cs_d_bit;

    logic [31:0] eip;
    logic        fault_pending;
    logic [3:0]  fault_class;
    logic [31:0] fault_error;

    logic [1:0]  dbg_mseq_state_w;
    logic [11:0] dbg_upc_w;
    logic [7:0]  dbg_entry_id_w;

    assign dbg_eip           = eip;
    assign dbg_mseq_state    = dbg_mseq_state_w;
    assign dbg_upc           = dbg_upc_w;
    assign dbg_entry_id      = dbg_entry_id_w;
    assign dbg_dec_entry_id  = entry_id;
    assign dbg_endi_pulse    = endi_req && endi_done;
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
        .flush       (flush_req),            // authoritative redirect from commit_engine
        .flush_addr  (flush_addr),
        .kill        (squash),               // Rung 2: stale-work kill from microsequencer
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
        .clk         (clk),
        .reset_n     (reset_n),
        .squash      (squash),               // Rung 2: stale-work kill
        .mode_prot   (mode_prot),
        .cs_d_bit    (cs_d_bit),
        .q_data      (q_data),
        .q_valid     (q_valid),
        .q_consume   (q_consume),
        .decode_done (decode_done),
        .entry_id    (entry_id),
        .next_eip    (next_eip),
        .target_eip  (target_eip),           // Rung 2
        .has_target  (has_target),           // Rung 2
        .dec_ack     (dec_ack),
        .q_fetch_eip (q_fetch_eip)
    );

    microsequencer u_mseq (
        .clk              (clk),
        .reset_n          (reset_n),
        .decode_done      (decode_done),
        .entry_id_in      (entry_id),
        .next_eip_in      (next_eip),
        .target_eip_in    (target_eip),      // Rung 2
        .has_target_in    (has_target),      // Rung 2
        .dec_ack          (dec_ack),
        .squash           (squash),          // Rung 2: output to decoder+queue
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
        .pc_target_en     (pc_target_en),    // Rung 2
        .pc_target_val    (pc_target_val),   // Rung 2
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
        .clk            (clk),
        .reset_n        (reset_n),
        .endi_req       (endi_req),
        .endi_mask      (endi_mask),
        .endi_done      (endi_done),
        .raise_req      (raise_req),
        .raise_fc       (raise_fc),
        .raise_fe       (raise_fe),
        .pc_gpr_en      (1'b0),
        .pc_gpr_idx     (3'h0),
        .pc_gpr_val     (32'h0),
        .pc_eip_en      (pc_eip_en),
        .pc_eip_val     (pc_eip_val),
        .pc_target_en   (pc_target_en),      // Rung 2
        .pc_target_val  (pc_target_val),     // Rung 2
        .eip            (eip),
        .mode_prot      (mode_prot),
        .cs_d_bit       (cs_d_bit),
        .flush_req      (flush_req),
        .flush_addr     (flush_addr),
        .fault_pending  (fault_pending),
        .fault_class    (fault_class),
        .fault_error    (fault_error)
    );

endmodule
