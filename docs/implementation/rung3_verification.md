# Keystone86 / Aegis — Rung 3 Verification Record

## How to run

From repo root with `iverilog` installed:

```bash
make codegen
make ucode
make rung3-regress
```

`rung3-regress` runs the Rung 0 + Rung 1 Python regression harness, then the
Rung 2 testbench, then the Rung 3 testbench. All must pass.

For Rung 3 alone:

```bash
make ucode && make rung3-sim
```

---

## What each test proves

| Test | Instruction(s) | Proof point |
|------|---------------|-------------|
| A    | E8 / C3       | Direct CALL pushes correct return address through the shared bus path; ESP decrements by 4; RET restores EIP and ESP exactly |
| B    | E8 / C2       | RET imm16 applies post-pop stack adjustment; ESP = pre-CALL ESP + 8 |
| C    | E8 / C3 (×3)  | Nested CALL/RET depth 4: all frames unwind to correct EIP; ESP fully restored |
| D    | FF /2 / C3    | Indirect CALL (register form): correct target EIP, correct return address pushed, RET unwinds correctly |
| E    | EB FE         | Rung 2 regression: JMP SHORT self-loop runs 500 cycles without fault |
| F    | 90 ×10        | Rung 1 regression: 10 consecutive NOPs advance EIP correctly |

---

## Passing baseline

```
Date:        2026-04-25
Branch:      rung3-codex
Commit:      working tree
Commands:    make codegen
             make ucode
             make rung3-regress
```

The Rung 3 stack memory path is exercised through `bus_interface` EU
transactions on the main bus. There is no dedicated `cpu_top` stack sideband
port in the passing baseline.

### Rung 0 + Rung 1 regression

```
Keystone86 / Aegis — Rung 1 Regression
Root: /work

Running: rung0_reset_loop
  Rung 0 baseline: reset, ENTRY_NULL, RAISE FC_UD, ENDI, FETCH_DECODE
  RESULT: PASS

Running: rung1_nop_loop
  Rung 1: NOP classification, dispatch, EIP+1, 10 NOPs, 100 NOPs, no faults
  RESULT: PASS

================================================
Rung 1 Regression Summary
  Passed: 2
  Failed: 0
  Total:  2

RESULT: ALL RUNG 1 TESTS PASSED
```

### Rung 2 regression

```
Rung 2 Regression Summary
  [x] Rung 0 baseline still passes
  [x] Rung 1 baseline still passes
  [x] No fault during bounded direct JMP loop
  [x] Committed JMP retires observed: 2
  [x] Committed redirect flushes observed: 3
  [x] Active decoded entry remains ENTRY_JMP_NEAR

RESULT: ALL RUNG 2 TESTS PASSED
```

### Rung 3 testbench

```
--- Test A: Direct CALL + RET pair ---
  [PASS] A.1 through A.9

--- Test B: RET imm16 (C2 08 00) ---
  [PASS] B.1 through B.6

--- Test C: Nested CALL/RET depth 4 ---
  [PASS] C.1 through C.4

--- Test D: Indirect CALL (FF /2, register form) ---
  [PASS] D.1 through D.9

--- Test E: Rung 2 regression (JMP SHORT self-loop) ---
  [PASS] E.1 through E.3

--- Test F: Rung 1 regression (10 consecutive NOPs) ---
  [PASS] F.1 through F.2

RESULTS: 33 passed, 0 failed
ALL TESTS PASSED — Rung 3 acceptance criteria met.
```

---

## What Rung 3 does not cover

- Far CALL / far RET
- CALL r/m with memory-form ModRM (phase-1: register form only; FF with non-/2 ModRM returns ENTRY_NULL)
- Stack-limit faults (FC_SS): fault paths are present in Appendix D but not triggered in phase-1
- General-purpose register file (EAX–EDI): not implemented; indirect CALL target is supplied externally via `indirect_call_target` input
- EFLAGS preservation across CALL/RET (no flags modified by these instructions)
- JCC (Rung 4)
