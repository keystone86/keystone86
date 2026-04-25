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
| C    | E8 / C3 (×4)  | Nested CALL depth 4: four CALL frames unwind through four RETs to the correct EIP; ESP fully restored |
| D    | FF /2 / C3    | Indirect CALL register form: r/m register target is read through the bounded operand path; return address pushed; RET unwinds correctly |
| E    | FF /2 / C3    | Indirect CALL memory disp32 form: r/m memory target is read through the shared EU bus path; return address pushed; RET unwinds correctly |
| F    | FF /2         | Unsupported FF /2 memory form does not commit a CALL stack effect or redirect |
| G    | EB FE         | Rung 2 regression: JMP SHORT self-loop runs 500 cycles without fault |
| H    | 90 ×10        | Rung 1 regression: 10 consecutive NOPs advance EIP correctly |

---

## Local verification run

```
Date:        2026-04-25T21:19:52Z
Branch:      rung3-codex
HEAD:        f8d870796ddce6ebe05e21044491837b207d5090
Tree state:  dirty before and after the run; Rung 3 blocker fixes were uncommitted
Commands:    make codegen
             make ucode
             make rung2-regress
             make rung3-regress
```

The Rung 3 stack memory path is exercised through `bus_interface` EU
transactions on the main bus. FF /2 register targets and the direct disp32
memory target are exercised through the bounded Rung 3 operand service path;
unsupported FF /2 memory forms fail safely without committing a CALL redirect
or stack effect. There is no dedicated `cpu_top` indirect-call target sideband.

This is not a clean committed acceptance baseline. A final acceptance record
still requires committing the implementation and rerunning the required
regression commands against that exact committed state.

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

--- Test E: Indirect CALL (FF /2, memory direct disp32) ---
  [PASS] E.1 through E.9

--- Test F: Unsupported FF /2 memory form fails safely ---
  [PASS] F.1 through F.4

--- Test G: Rung 2 regression (JMP SHORT self-loop) ---
  [PASS] G.1 through G.3

--- Test H: Rung 1 regression (10 consecutive NOPs) ---
  [PASS] H.1 through H.2

RESULTS: 46 passed, 0 failed
ALL TESTS PASSED — Rung 3 acceptance criteria met.
```

---

## What Rung 3 does not cover

- Far CALL / far RET
- Full CALL r/m addressing matrix: Rung 3 currently proves register form and
  direct disp32 memory form; broader SIB/base/index combinations fail safely
  and are not claimed as successful operand loads
- Stack-limit faults (FC_SS): fault paths are present in Appendix D but not triggered in phase-1
- Full general-purpose register file behavior beyond the bounded Rung 3 operand source
- EFLAGS preservation across CALL/RET (no flags modified by these instructions)
- JCC (Rung 4)
