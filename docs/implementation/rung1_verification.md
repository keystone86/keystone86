# Keystone86 / Aegis — Rung 1 Verification

## How to Run

    make rung1-sim      # compile and run Rung 1 testbench only
    make rung1-regress  # run Rung 1 + Rung 0 baseline together

Prerequisites: `iverilog` installed, repo root as working directory.
Run `make ucode` first if `build/microcode/` is empty.

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

**Memory model:** the testbench uses `ctrl_mem`, not a fixed fetch-count injector.
After Test 7 completes, the testbench raises `inject_prefix`, and `ctrl_mem`
serves a single `0x66` on the next available fetch transaction. `inject_prefix`
is held until the decoder confirms prefix classification, guaranteeing the
prefix byte is observed while Test 8 is active.

## Expected Output

    --- Reset released, Rung 1 NOP+PREFIX loop starting ---
    PASS Test 1: 0x90 -> ENTRY_NOP_XCHG_AX (0x13)
    PASS Test 2: uPC=0x020 (ENTRY_NOP_XCHG_AX dispatch)
    PASS Test 3: no fault during NOP (fault_pending=0)
    PASS Test 5: microsequencer returned to FETCH_DECODE after NOP
    PASS Test 4: EIP+1 after NOP (0xFFFFFFF0 -> 0xFFFFFFF1)
    PASS Test 6: 10 consecutive NOPs, zero faults
    PASS Test 7: 100 NOPs, zero spurious faults, decode stable
    PASS Test 8: 0x66 -> ENTRY_PREFIX_ONLY (0x12), uPC=0x030,
                no fault, EIP 0x00000054 -> 0x00000055, FETCH_DECODE returned

    === Rung 1 Testbench Summary ===
      Cycles elapsed : 1016
      NOPs completed : 100
      PASS           : 8
      FAIL           : 0
      RESULT: ALL RUNG 1 TESTS PASSED
    ================================

## Rung 0 Baseline Still Passes

`make rung1-regress` runs `tb_rung0_reset_loop.sv` first as a regression
check. The Rung 0 baseline must still output `ALL TESTS PASSED` before
Rung 1 results are reported.

## Timing Notes

### Dispatch ROM Timing
`microcode_rom` provides registered outputs (1-cycle latency). The
microsequencer uses a two-step dispatch handshake so `dispatch_upc_in`
is valid before it is consumed:

- Cycle N: `decode_done` latches `entry_id` and presents it to the ROM
  (`dispatch_rom_pending`)
- Cycle N+1: ROM has sampled the new entry; microsequencer raises
  `dispatch_pending`
- Cycle N+2: `dispatch_upc_in` is valid; microsequencer loads the new `uPC`
  and enters `EXECUTE`

This fixes the dispatch read-after-write hazard that otherwise causes the
previous entry's dispatch address to be used.

### Microinstruction Fetch Timing
`uinst` is also a registered ROM output. After loading a new `uPC`, the
microsequencer inserts a one-cycle `execute_fetch_pending` stall before
consuming the first microinstruction for that entry.

Without this stall, the first `EXECUTE` cycle would see the stale ROM word
from the previous `uPC`, which could process the wrong `ENDI` and destroy
the staged EIP commit before the correct microinstruction arrives.

## Passing Baseline

Rung 1 has been validated in live simulation.

Passing commands:

    make rung0-regress
    make rung1-sim
    make rung1-regress

Observed result:
- Rung 0 regression remains passing
- decoder recognizes `0x90 -> ENTRY_NOP_XCHG_AX`
- dispatch routes NOP to bootstrap `uPC 0x020`
- NOP commits visible `EIP + 1`
- 10 and 100 NOP runs complete with zero spurious faults
- decoder recognizes `0x66 -> ENTRY_PREFIX_ONLY`
- dispatch routes prefix-only to bootstrap `uPC 0x030`
- prefix-only path completes with no fault and `EIP + 1`

Record here when available:
- Date: 2026-04-12
- Commit: abb61d15a5faeaa9e341a692490a88d1a3756204
- Tag: rung1-first-pass

## What Is Not Yet Covered

- Real prefix semantics (operand/address size override)
- Multi-byte instruction decode
- Any instruction family beyond NOP and PREFIX_ONLY
- EIP advancement for `ENTRY_NULL` (fault path — EIP intentionally not committed)