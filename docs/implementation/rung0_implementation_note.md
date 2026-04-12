# Keystone86 / Aegis — Rung 0 Implementation Note
# docs/implementation/rung0_implementation_note.md

## What Was Implemented

Rung 0 implements the minimal reset/fetch/decode/dispatch/ENDI loop
as specified in Appendix D, frozen bring-up ladder.

### Modules Added or Updated

**rtl/core/bus_interface.sv**
Minimal instruction fetch bus FSM. Issues byte-granular read transactions
at requested addresses, asserts ready handshake, returns fetched byte.
Write path is stubbed with zero output and deasserted wr. No instruction
meaning. No policy.

**rtl/core/prefetch_queue.sv**
4-byte circular byte queue. Buffers instruction bytes fetched via bus_interface.
Provides byte-valid/empty status and consume-one-byte interface for decoder.
Supports synchronous flush from commit_engine with new fetch address.
Does not classify bytes. Does not self-initiate flushes.

**rtl/core/decoder.sv**
Rung 0 decoder stub. Consumes one byte from prefetch queue. Always emits
ENTRY_NULL regardless of opcode byte value. Computes next_eip as
opcode_eip + 1. Asserts decode_done and holds it until dec_ack from
microsequencer. This is intentionally a stub — it does not perform
real decode. The module boundary, interface, and handshake are correctly
shaped for future growth.

**rtl/core/microcode_rom.sv**
Synchronous ROM loading ucode.hex and dispatch.hex via $readmemh.
Provides microinstruction read by uPC with 1-cycle latency.
Provides dispatch lookup (entry_id → base uPC) with 1-cycle latency.

**rtl/core/microsequencer.sv**
The control center. Manages all four spec states: FETCH_DECODE, EXECUTE,
WAIT_SERVICE (reserved), FAULT_HOLD. Dispatches entry_id through dispatch
table. Executes Rung 0 microinstruction subset: NOP, RAISE, ENDI.
Issues RAISE to commit_engine to stage fault class. Issues ENDI with
commit mask. Returns to FETCH_DECODE after ENDI. WAIT_SERVICE is defined
but not entered in Rung 0 bootstrap.

**rtl/core/commit_engine.sv**
Minimal architectural commit boundary. Holds EIP initialized to reset
vector (0xFFFFFFF0). Accepts RAISE to stage fault class. Accepts ENDI
and applies commit mask: EIP commit (suppressed if fault pending),
queue flush initiation, fault state clear. Exports mode_prot=0 and
cs_d_bit=0 for real-mode bootstrap. Interface shaped for Rung 1+ growth
without redesign (GPR file etc. not yet present but input ports are
correctly defined).

**rtl/core/cpu_top.sv**
Top-level integration. No longer an empty shell. Wires all Rung 0 modules.
Exposes debug observability outputs so the control path is traceable
in simulation without additional probing.

### Simulation Infrastructure Added

**sim/models/bootstrap_mem.sv**
Tiny deterministic memory model. Returns 0x00 at all addresses.
Configurable ready latency (default 1 cycle). No policy logic.

**sim/tb/tb_rung0_reset_loop.sv**
Self-checking testbench. Proves all Rung 0 acceptance criteria without
manual waveform inspection. See rung0_verification.md.

**scripts/rung0_regress.py**
Regression runner using Icarus Verilog. Runs testbench, checks output
for pass/fail markers, returns nonzero on failure.

---

## Architectural Constraints Followed

**Decoder remains a stub.** The decoder does not implement instruction
semantics. It always returns ENTRY_NULL. The opcode byte is consumed
but not classified. This is correct and intentional for Rung 0.

**Microsequencer is the control owner.** The microsequencer owns uPC,
owns dispatch, owns the control loop. No other module sequences control.

**Architectural visibility only through ENDI.** Commit engine state is
only updated when endi_req is received. No module modifies architectural
state outside that path.

**No hidden shortcut paths.** The path through cpu_top is:
bus_interface → prefetch_queue → decoder → microsequencer → commit_engine.
No module bypasses another.

**Service dispatch not present.** Rung 0 does not use the service
dispatch framework. Services are not invoked in bootstrap microcode.
The interface is shaped for future growth but not yet wired.

---

## Known Limitations (Rung 0 Only)

These are correct Rung 0 limitations, not bugs:

- Decoder always emits ENTRY_NULL. No real instruction classification.
- Only bootstrap microinstruction subset (NOP, RAISE, ENDI) is supported.
- WAIT_SERVICE state is defined but never entered.
- Commit engine only tracks EIP. No GPR file, EFLAGS, or segments.
- Fault delivery is staged (FC_UD becomes fault_pending=1) but not
  delivered via IVT. Full exception delivery requires Rung 5 (INT_ENTER).
- No instruction semantics are implemented.

---

## Interfaces Shaped for Growth

The following interfaces are present in Rung 0 but unused, to avoid
redesign later:

- commit_engine.pc_gpr_en, pc_gpr_idx, pc_gpr_val (Rung 1+)
- commit_engine.pc_eip_en, pc_eip_val (Rung 2+, via staging)
- microsequencer.WAIT_SERVICE state (Rung 5+)
- cpu_top exposes all debug signals for future trace infrastructure

---

## Startup Path Clarification (ENTRY_RESET vs ENTRY_NULL)

The Rung 0 live control path is:

    reset → commit_engine drives flush → prefetch_queue fetches 0xFFFFFFF0
          → decoder consumes byte 0x00 → emits ENTRY_NULL
          → microsequencer dispatches ENTRY_NULL
          → bootstrap ROM executes RAISE FC_UD → ENDI
          → return to FETCH_DECODE

ENTRY_RESET (0xFF → dispatch 0x040) is present in the ROM and dispatch
table as bootstrap scaffolding, matching the frozen spec's requirement that
it exist. However, in Rung 0 the microsequencer does NOT jump to ENTRY_RESET
on startup. Instead, it waits in FETCH_DECODE for the decoder to deliver
an instruction.

The master design statement says: "The microsequencer begins at a fixed
ENTRY_RESET micro-PC." This is the intended behavior for a complete
implementation. Rung 0 defers this to Rung 1 because:

1. ENTRY_RESET requires the decoder to signal reset completion, and the
   decoder stub does not yet distinguish between "reset startup" and
   "normal decode."
2. The Rung 0 proof goal (verifying the fetch/decode/dispatch/ENDI loop)
   is fully achieved without ENTRY_RESET being in the live path.
3. The ROM and dispatch table are already wired for ENTRY_RESET — adding
   it to the live path requires only a microsequencer change in Rung 1.

This is a known deliberate deferral, not an omission.

---

## Reset Fetch Address Ownership (Appendix B Compliance)

The reset fetch address (32'hFFFFFFF0) is owned exclusively by
commit_engine, defined as a localparam RESET_FETCH_ADDR. On the first
cycle after reset deassertion, commit_engine asserts flush_req=1 with
flush_addr=RESET_FETCH_ADDR. prefetch_queue receives this flush and
begins fetching from that address.

prefetch_queue has no hardcoded reset address. It starts with
queue_ready=0 and waits for the flush from commit_engine.

This preserves the Appendix B ownership rule: commit_engine is the
single owner of architectural reset state.
