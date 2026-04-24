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
| A    | E8 / C3       | Direct CALL pushes correct return address; ESP decrements by 4; RET restores EIP and ESP exactly |
| B    | E8 / C2       | RET imm16 applies post-pop stack adjustment; ESP = pre-CALL ESP + 8 |
| C    | E8 / C3 (×3)  | Nested CALL/RET depth 4: all frames unwind to correct EIP; ESP fully restored |
| D    | FF /2 / C3    | Indirect CALL (register form): correct target EIP, correct return address pushed, RET unwinds correctly |
| E    | EB FE         | Rung 2 regression: JMP SHORT self-loop runs 500 cycles without fault |
| F    | 90 ×10        | Rung 1 regression: 10 consecutive NOPs advance EIP correctly |

---

## Passing baseline

```
Date:        2026-04-24
Commit:      (see git log — Rung 3 re-proof from Rung 2 baseline)
Commands:    make codegen && make ucode && make rung3-regress
```

### Rung 0 + Rung 1 regression

```
Running: rung0_reset_loop
  RESULT: PASS

Running: rung1_nop_loop
  RESULT: PASS

RESULT: ALL RUNG 1 TESTS PASSED
```

### Rung 2 regression

```
RESULT: ALL RUNG 2 TESTS PASSED
```

### Rung 3 testbench

```
--- Test A: Direct CALL + RET pair ---
  [PASS] A.1: CALL ENDI fires
  [PASS] A.2: EIP = CALL target (0xFFFFFFF5)
  [PASS] A.3: ESP decremented by 4
  [PASS] A.4: no fault after CALL
  [PASS] A.5: return address on stack = 0xFFFFFFF3
  [PASS] A.6: RET ENDI fires
  [PASS] A.7: EIP = return address (0xFFFFFFF3)
  [PASS] A.8: ESP restored to RESET_ESP
  [PASS] A.9: no fault after RET

--- Test B: RET imm16 (C2 08 00) ---
  [PASS] B.1: CALL ENDI fires
  [PASS] B.2: EIP = 0xFFFFFFF5 after CALL
  [PASS] B.3: RET imm16 ENDI fires
  [PASS] B.4: EIP = return address (0xFFFFFFF3)
  [PASS] B.5: ESP = RESET_ESP + 8
  [PASS] B.6: no fault after RET imm16

--- Test C: Nested CALL/RET depth 4 ---
  [PASS] C.1: all 7 ENDIs fire without timeout
  [PASS] C.2: EIP = 0xFFFFFFE3 (depth-1 return)
  [PASS] C.3: ESP = RESET_ESP (fully unwound)
  [PASS] C.4: no fault during nested CALL/RET

--- Test D: Indirect CALL (FF /2, register form) ---
  [PASS] D.1: indirect CALL ENDI fires
  [PASS] D.2: EIP = indirect target (0xFFFFFFA0)
  [PASS] D.3: ESP decremented by 4
  [PASS] D.4: no fault after indirect CALL
  [PASS] D.5: return address on stack = 0xFFFFFFF2
  [PASS] D.6: RET after indirect CALL fires
  [PASS] D.7: EIP = 0xFFFFFFF2 (return address)
  [PASS] D.8: ESP restored
  [PASS] D.9: no fault after RET

--- Test E: Rung 2 regression (JMP SHORT self-loop) ---
  [PASS] E.1: no fault in 500 cycles (JMP loop)
  [PASS] E.2: JMP ENDIs fired in 500 cycles
  [PASS] E.3: EIP stays at reset vector

--- Test F: Rung 1 regression (10 consecutive NOPs) ---
  [PASS] F.1: EIP advanced by 10 after 10 NOPs
  [PASS] F.2: no fault during NOP regression

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
