# Keystone86 / Aegis — Rung 2 Verification

## How to Run

    make rung2-sim      # compile and run Rung 2 testbench

Prerequisites: `iverilog` installed, repo root as working directory.
Run `make ucode` first if `microcode/build/` is empty.

Also confirm earlier rungs remain passing:

    make rung0-sim
    make rung1-regress

## Tests

### Test A — JMP SHORT self-loop (EB FE)
**Proves:** JMP SHORT with displacement -2 produces a stable self-loop at the reset vector.
**Memory:** `EB FE` repeating from `0xFFFFFFF0`.
**Pass conditions:**
- No fault in 1000 cycles.
- At least 10 JMP ENDIs fire.
- `dbg_eip` stays at `0xFFFFFFF0` throughout.
- No spurious fault class.

### Test B — JMP SHORT forward (EB 05)
**Proves:** JMP SHORT with positive displacement computes and commits the correct target EIP.
**Memory:** `EB 05` at `0xFFFFFFF0`; `EB FE` self-loop at `0xFFFFFFF7`.
**Pass conditions:**
- First ENDI fires without timeout.
- `dbg_eip == 0xFFFFFFF7` after first ENDI (`0xFFFFFFF0 + 2 + 5`).
- No fault after JMP.
- Second ENDI fires (CPU is now stable at new location).
- `dbg_eip` stays at `0xFFFFFFF7`.

### Test C — JMP SHORT backward (EB F0)
**Proves:** JMP SHORT with negative displacement computes and commits the correct target EIP,
and the prefetch queue correctly retargets to an address below the starting address.
**Memory:** `EB F0` at `0xFFFFFFF0`; `EB FE` self-loop at `0xFFFFFFE2`.
**Pass conditions:**
- ENDI fires without timeout.
- `dbg_eip == 0xFFFFFFE2` (`0xFFFFFFF0 + 2 - 16`).
- No fault after backward JMP.
- Second ENDI fires at new location.
- `dbg_eip` stays at `0xFFFFFFE2`.

### Test D — Rung 1 regression (10 consecutive NOPs)
**Proves:** Rung 1 NOP path is unaffected by Rung 2 changes.
**Memory:** all `0x90` (NOP).
**Pass conditions:**
- 10 ENDIs fire without timeout.
- `dbg_eip == 0xFFFFFFF0 + 10` after 10 NOPs.
- No fault during NOP regression.

### Test E — Byte ordering (NOP then JMP)
**Proves:** position-proven byte capture correctly distinguishes the NOP byte from the
JMP opcode byte on the very next fetch, with no confusion between adjacent bytes.
**Memory:** `0x90` at `0xFFFFFFF0`; `EB FE` self-loop at `0xFFFFFFF1`.
**Pass conditions:**
- First ENDI fires (NOP).
- `dbg_eip == 0xFFFFFFF1` after NOP.
- Second ENDI fires (JMP self-loop).
- `dbg_eip == 0xFFFFFFF1` after JMP (self-loop at new location).
- No fault throughout.

## Expected Output

    ============================================================
     Keystone86 / Aegis — Rung 2 Testbench
    ============================================================
    --- Test A: JMP SHORT self-loop (EB FE) ---
      [PASS] A.1: no fault in 1000 cycles
      [PASS] A.2: at least 10 JMP ENDIs fired
      [PASS] A.3: EIP stays at reset vector
      [PASS] A.4: no spurious fault_class
    --- Test B: JMP SHORT +5 (EB 05) ---
      [PASS] B.1: first ENDI fires without timeout
      [PASS] B.2: EIP = 0xFFFFFFF7 after JMP +5
      [PASS] B.3: no fault after JMP
      [PASS] B.4: second ENDI fires (self-loop stable)
      [PASS] B.5: EIP stays at 0xFFFFFFF7
    --- Test C: JMP SHORT backward (EB F0, target 0xFFFFFFE2) ---
      [PASS] C.1: ENDI fires without timeout
      [PASS] C.2: EIP = 0xFFFFFFE2 (backward target)
      [PASS] C.3: no fault after backward JMP
      [PASS] C.4: second ENDI fires at new location
      [PASS] C.5: EIP stays at backward target
    --- Test D: Rung 1 regression (10 consecutive NOPs) ---
      [PASS] D.1: EIP advances by 10 after 10 NOPs
      [PASS] D.2: no fault during NOP regression
    --- Test E: NOP then JMP, verify correct byte ordering ---
      [PASS] E.1: first ENDI fires (NOP)
      [PASS] E.2: EIP = 0xFFFFFFF1 after NOP
      [PASS] E.3: second ENDI fires (JMP self-loop)
      [PASS] E.4: EIP = 0xFFFFFFF1 after JMP self
      [PASS] E.5: no fault throughout
    ============================================================
     RESULTS: 19 passed, 0 failed
    ============================================================
     ALL TESTS PASSED — Rung 2 acceptance criteria met.

## Rung 0 and Rung 1 Baselines Still Pass

`make rung0-sim` and `make rung1-regress` must still output `ALL TESTS PASSED`
before Rung 2 results are considered valid.

## What Rung 2 Does Not Cover

- JMP NEAR (32-bit displacement): not yet in scope.
- CALL / RET / JCC: deferred to Rung 3+.
- Prefix bytes before JMP: deferred to later rungs.
- Fetch-local stream following: deferred optimization, not part of this baseline.

## Passing Baseline

Fill in from `git log` after confirming all tests pass on the committed state:

    git log --oneline -5

- Date: _(run `git log -1 --format="%ci"` on the passing commit)_
- Commit: _(run `git log -1 --format="%H"` on the passing commit)_
- Tag: _(optional — `git tag` if a tag was applied)_
