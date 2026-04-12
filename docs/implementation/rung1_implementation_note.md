# Keystone86 / Aegis — Rung 1 Implementation Note

## What Changed from Rung 0

Rung 1 adds NOP and prefix-only opcode classification to the decoder,
wires EIP staging through the microsequencer to the commit_engine, and
updates the bootstrap microcode so ENDI commits the visible EIP.

Three modules changed. All other modules are unchanged from Rung 0.

---

## Changes

### rtl/core/decoder.sv

**Change:** Added opcode byte latching and classification.

In Rung 0, the decoder consumed one byte but always emitted ENTRY_NULL.
In Rung 1, the opcode byte is latched in DEC_IDLE alongside opcode_eip,
and a classify_opcode() function maps it to the correct ENTRY_*:

    0x90                          -> ENTRY_NOP_XCHG_AX
    0xF0, 0xF2, 0xF3 (LOCK, REP) -> ENTRY_PREFIX_ONLY
    0x2E, 0x36, 0x3E, 0x26       -> ENTRY_PREFIX_ONLY  (segment overrides)
    0x64, 0x65, 0x66, 0x67       -> ENTRY_PREFIX_ONLY  (FS, GS, size overrides)
    all other opcodes             -> ENTRY_NULL

The state machine (DEC_IDLE/DEC_CONSUME/DEC_DONE), the handshake
behavior, and next_eip = opcode_eip + 1 are all unchanged.

The classify_opcode() function is purely combinational with no side
effects. The decoder remains classification-only — it does not implement
NOP semantics.

### rtl/core/microsequencer.sv

**Change:** Added pc_eip_en and pc_eip_val output ports. These are
asserted for one cycle when transitioning from FETCH_DECODE to EXECUTE
(the dec_ack cycle), staging next_eip_r into the commit_engine's pending
commit record.

This is architecture-consistent: the microsequencer stages a value into
the commit_engine via the existing pc_eip_en/pc_eip_val interface that
was already present but unused in Rung 0. No policy decision is being
made — the microsequencer is staging the decoder's next_eip value so
ENDI can commit it.

### rtl/core/cpu_top.sv

**Change:** pc_eip_en and pc_eip_val are now driven by the microsequencer
instead of hardwired to 1'b0 / 32'h0.

### scripts/ucode_build.py

**Change:** ENTRY_NOP_XCHG_AX and ENTRY_PREFIX_ONLY now use
ENDI CM_NOP|CM_EIP (word E00001C2) instead of ENDI CM_NOP (E00001C0).

CM_EIP (bit 1) enables EIP commit in the commit_engine at ENDI. Since
pc_eip_en_r is now set by the microsequencer before ENDI fires, the
commit_engine applies EIP = next_eip when ENDI arrives.

ENTRY_RESET retains ENDI CM_NOP (no EIP commit at reset startup).

### scripts/ucode_bootstrap_check.py

**Change:** EXPECTED_ROM updated to reflect the Rung 1 NOP encoding
(E00001C2) and the correct Appendix A format for all entries.

---

## How EIP Advancement Works for NOP

The path for a single NOP (0x90) instruction:

1. Decoder latches 0x90 in opcode_byte_latch, fires decode_done,
   entry_id = ENTRY_NOP_XCHG_AX, next_eip = fetch_EIP + 1.

2. Microsequencer latches decode result (entry_id_r, next_eip_r).
   On the dispatch cycle (dec_ack), it asserts pc_eip_en=1 and
   pc_eip_val=next_eip_r for one cycle.

3. Commit_engine registers pc_eip_en_r=1, pc_eip_val_r=next_eip_r.

4. Microsequencer enters EXECUTE at uPC 0x020.
   uinst = E00001C2 = ENDI CM_NOP|CM_EIP.
   endi_req=1, endi_mask=0x1C2.

5. Commit_engine processes ENDI:
   - CM_EIP (bit 1) = 1, pc_eip_en_r = 1, fault_pending = 0
   - eip_r <= pc_eip_val_r  (EIP commits visibly)
   - CM_CLR03/CLR47/CLRF clear temps and fault state
   - endi_done=1

6. Microsequencer returns to FETCH_DECODE.
   Architectural EIP is now fetch_EIP + 1.

---

## What Was Intentionally Deferred

- Prefix accumulation: prefix bytes are classified as ENTRY_PREFIX_ONLY
  and execute as single-byte no-ops. No prefix state is accumulated.
  Real prefix semantics (operand size override, segment overrides etc.)
  are deferred to later rungs.
- XCHG AX, AX (0x90 is also XCHG AX,AX): treated as NOP only. The
  register swap behavior is deferred to the XCHG instruction family rung.
- Multi-byte instructions: decoder still consumes exactly one byte per
  instruction. No ModRM, no displacement, no immediate.
- All other instruction families: still dispatch to ENTRY_NULL.
