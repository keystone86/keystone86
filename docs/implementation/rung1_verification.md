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
**Proves:** 100 NOPs complete cleanly, zero spurious faults.  
**Pass:** `nop_count` reaches 100, `fault_count=0`.

### Test 8 — Prefix-Only Placeholder Path
**Proves:** representative prefix byte `0x66` is treated as `ENTRY_PREFIX_ONLY` and executes correctly as the current Rung 1 placeholder path.  
**Pass:** all of the following are observed:
- decoder classifies `0x66` as `ENTRY_PREFIX_ONLY` (`0x12`)
- dispatch reaches `uPC 0x030`
- no fault is raised
- architectural EIP advances by 1
- microsequencer returns to `FETCH_DECODE`

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
                no fault, EIP 0xXXXXXXXX -> 0xXXXXXXXX, FETCH_DECODE returned

    === Rung 1 Testbench Summary ===
      Cycles elapsed : NN
      NOPs completed : 100
      PASS           : 8
      FAIL           : 0
      RESULT: ALL RUNG 1 TESTS PASSED
    ================================

## Rung 0 Baseline Still Passes

`make rung1-regress` runs `tb_rung0_reset_loop.sv` first as a regression
check. The Rung 0 baseline must still output `ALL TESTS PASSED` before
Rung 1 results are reported.

## What Is Not Yet Covered

- Real prefix semantics (operand/address size override behavior)
- Multi-byte instruction decode
- EIP advancement for any instruction other than NOP / PREFIX_ONLY
- Any instruction family beyond Rung 1 scope