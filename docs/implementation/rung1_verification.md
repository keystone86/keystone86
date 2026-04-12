# Keystone86 / Aegis — Rung 1 Verification

## How to Run

    make rung1-sim      # compile and run Rung 1 testbench only
    make rung1-regress  # run Rung 1 + Rung 0 baseline together

Prerequisites: `iverilog` installed, repo root as working directory.
Run `make ucode` first if `microcode/build/` is empty.

## Tests

### Test 1 — NOP Classification
**Proves:** decoder classifies `0x90` as `ENTRY_NOP_XCHG_AX` (`0x13`).
**Pass:** `decode_done` fires with `dbg_dec_entry_id === 8'h13`.

### Test 2 — Dispatch to uPC `0x020`
**Proves:** dispatch table routes `ENTRY_NOP_XCHG_AX` to bootstrap `uPC 0x020`.
**Pass:** `dbg_upc` reaches `12'h020`.

### Test 3 — No Fault During NOP
**Proves:** NOP execution does not stage a fault.
**Pass:** `dbg_fault_pending=0` at first NOP `ENDI`.

### Test 4 — EIP Advances by 1
**Proves:** architectural `EIP = initial_EIP + 1` after one NOP.
**Pass:** `dbg_eip === eip_before_nop + 1` one cycle after first `ENDI`.

### Test 5 — Return to `FETCH_DECODE`
**Proves:** microsequencer returns to `FETCH_DECODE` after NOP `ENDI`.
**Pass:** `dbg_mseq_state === 2'h0` after NOP `ENDI`.

### Test 6 — 10 Consecutive NOPs
**Proves:** 10 NOPs execute without fault or deadlock.
**Pass:** `nop_count` reaches 10, `fault_count=0`.

### Test 7 — 100 Consecutive NOPs
**Proves:** 100 NOPs complete cleanly with zero spurious faults and stable decode.
**Pass:** `nop_count` reaches 100, `fault_count=0`.

### Test 8 — Prefix-Only Classification and EIP Advancement
**Proves:** prefix-only byte `0x66` (operand-size override) is correctly classified
and executed. This is a real proof of the prefix-only path, not a NOP-stream check.

Specifically proves:
- decoder emits `ENTRY_PREFIX_ONLY` (`0x12`) for `0x66`
- dispatch reaches `uPC 0x030`
- no fault raised during prefix execution
- EIP advances by 1
- microsequencer returns to `FETCH_DECODE`

**Memory model:** `seq_mem` in the testbench serves `0x90` for the first 100
fetches, then `0x66` on the 101st fetch, then `0x90` thereafter.

## Expected Output

    --- Reset released, Rung 1 NOP+PREFIX loop starting ---
    PASS Test 1: 0x90 -> ENTRY_NOP_XCHG_AX (0x13)
    PASS Test 2: uPC=0x020 (ENTRY_NOP_XCHG_AX dispatch)
    PASS Test 3: no fault during NOP (fault_pending=0)
    PASS Test 4: EIP+1 after NOP (0xFFFFFFF0 -> 0xFFFFFFF1)
    PASS Test 5: microsequencer returned to FETCH_DECODE after NOP
    PASS Test 6: 10 consecutive NOPs, zero faults
    PASS Test 7: 100 NOPs, zero spurious faults, decode stable
    PASS Test 8: 0x66 -> ENTRY_PREFIX_ONLY (0x12), uPC=0x030,
                no fault, EIP 0x...64 -> 0x...65, FETCH_DECODE returned

    === Rung 1 Testbench Summary ===
      PASS: 8 / FAIL: 0
      RESULT: ALL RUNG 1 TESTS PASSED

## Dispatch Timing Note

`microcode_rom` provides registered outputs (1-cycle latency). The microsequencer
uses a two-cycle dispatch handshake to ensure dispatch_upc_in is valid when read:

- Cycle N   (`decode_done`): latch entry_id, present to ROM (`dispatch_rom_pending`)
- Cycle N+1 (ROM settling):  ROM has sampled new entry; set `dispatch_pending`
- Cycle N+2 (dispatch):      `dispatch_upc_in` is valid; load uPC, enter EXECUTE

## What Is Not Yet Covered

- Real prefix semantics (operand/address size override)
- Multi-byte instruction decode
- Any instruction family beyond NOP and PREFIX_ONLY
- EIP advancement for ENTRY_NULL (fault path — EIP intentionally not committed)