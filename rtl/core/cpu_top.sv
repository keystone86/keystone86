// Keystone86 / Aegis
// rtl/core/cpu_top.sv
// Rung 0: Top-level CPU integration
//
// This module wires the Rung 0 RTL path together.
// A reviewer must be able to follow this path clearly:
//
//   reset → commit_engine holds EIP=FFFFFFF0
//         → prefetch_queue fetches from 0xFFFFFFF0 via bus_interface
//         → decoder consumes byte, emits ENTRY_NULL, asserts decode_done
//         → microsequencer latches entry_id, dispatches via ROM
//         → microsequencer executes RAISE FC_UD, then ENDI
//         → commit_engine processes ENDI (with fault suppression)
//         → microsequencer returns to FETCH_DECODE
//         → prefetch_queue continues fetching
//
// No instruction semantics live here. This is pure wiring and reset.

import keystone86_pkg::*;

module cpu_top (
    input  logic        clk,
    input  logic        reset_n,

    // --- External memory bus ---
    output logic [31:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,
    output logic [3:0]  bus_byteen,
    output logic [31:0] bus_dout,
    input  logic [31:0] bus_din,
    input  logic        bus_ready,

    // --- Debug/observability outputs ---
    output logic [31:0] dbg_eip,
    output logic [1:0]  dbg_mseq_state,
    output logic [11:0] dbg_upc,
    output logic [7:0]  dbg_entry_id,
    output logic        dbg_endi_pulse,
    output logic        dbg_fault_pending,
    output logic [3:0]  dbg_fault_class,
    output logic        dbg_decode_done,
    output logic [31:0] dbg_fetch_addr
);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------

    // bus_interface <-> prefetch_queue
    logic        fetch_req;
    logic [31:0] fetch_addr_internal;
    logic        fetch_done;
    logic [7:0]  fetch_data;

    // prefetch_queue <-> decoder
    logic [7:0]  q_data;
    logic        q_valid;
    logic        q_consume;
    logic [31:0] q_fetch_eip;

    // commit_engine -> prefetch_queue (flush)
    logic        flush_req;
    logic [31:0] flush_addr;

    // decoder <-> microsequencer
    logic        decode_done;
    logic [7:0]  entry_id;
    logic [31:0] next_eip;
    logic        dec_ack;

    // microsequencer <-> microcode_rom
    logic [11:0] upc;
    logic [31:0] uinst;
    logic [7:0]  dispatch_entry;
    logic [11:0] dispatch_upc;

    // microsequencer <-> commit_engine
    logic        endi_req;
    logic [9:0]  endi_mask;
    logic        endi_done;
    logic        raise_req;
    logic [3:0]  raise_fc;
    logic [31:0] raise_fe;

    // commit_engine -> decoder (mode context)
    logic        mode_prot;
    logic        cs_d_bit;

    // commit_engine -> observability
    logic [31:0] eip;
    logic        fault_pending;
    logic [3:0]  fault_class;
    logic [31:0] fault_error;

    // ----------------------------------------------------------------
    // Observability assignments
    // ----------------------------------------------------------------
    assign dbg_eip           = eip;
    assign dbg_mseq_state    = dbg_mseq_state_w;
    assign dbg_upc           = dbg_upc_w;
    assign dbg_entry_id      = dbg_entry_id_w;
    assign dbg_endi_pulse     = endi_req && endi_done;
    assign dbg_fault_pending = fault_pending;
    assign dbg_fault_class   = fault_class;
    assign dbg_decode_done   = decode_done;
    assign dbg_fetch_addr    = fetch_addr_internal;

    logic [1:0]  dbg_mseq_state_w;
    logic [11:0] dbg_upc_w;
    logic [7:0]  dbg_entry_id_w;

    // ----------------------------------------------------------------
    // Module instantiations
    // ----------------------------------------------------------------

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
        .mode_prot   (mode_prot),
        .cs_d_bit    (cs_d_bit),
        .q_data      (q_data),
        .q_valid     (q_valid),
        .q_consume   (q_consume),
        .decode_done (decode_done),
        .entry_id    (entry_id),
        .next_eip    (next_eip),
        .dec_ack     (dec_ack),
        .q_fetch_eip (q_fetch_eip)
    );

    microsequencer u_mseq (
        .clk              (clk),
        .reset_n          (reset_n),
        .decode_done      (decode_done),
        .entry_id_in      (entry_id),
        .next_eip_in      (next_eip),
        .dec_ack          (dec_ack),
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
        .clk           (clk),
        .reset_n       (reset_n),
        .endi_req      (endi_req),
        .endi_mask     (endi_mask),
        .endi_done     (endi_done),
        .raise_req     (raise_req),
        .raise_fc      (raise_fc),
        .raise_fe      (raise_fe),
        .pc_gpr_en     (1'b0),
        .pc_gpr_idx    (3'h0),
        .pc_gpr_val    (32'h0),
        .pc_eip_en     (1'b0),
        .pc_eip_val    (32'h0),
        .eip           (eip),
        .mode_prot     (mode_prot),
        .cs_d_bit      (cs_d_bit),
        .flush_req     (flush_req),
        .flush_addr    (flush_addr),
        .fault_pending (fault_pending),
        .fault_class   (fault_class),
        .fault_error   (fault_error)
    );

endmodule
