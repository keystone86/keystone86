# Keystone86 / Aegis — Rung 0 Verification
# docs/implementation/rung0_verification.md

## How to Run

From repo root:

    make rung0-sim       # run main testbench
    make rung0-regress   # run full regression suite

Prerequisites:
- Icarus Verilog installed (iverilog, vvp)
- Bootstrap microcode artifacts present: run `make ucode` if not

## Tests

### Test A — Reset Vector Fetch
**Proves:** first external bus read after reset is at physical address 0xFFFFFFF0.
**Method:** monitors bus_rd and bus_addr, checks first assertion of bus_rd.
**Pass condition:** bus_addr === 32'hFFFFFFF0 on first bus_rd.

### Test B — Decoder decode_done with ENTRY_NULL
**Proves:** decoder asserts decode_done and emits ENTRY_NULL (0x00).
**Method:** monitors decode_done and entry_id debug outputs.
**Pass condition:** when decode_done first asserts, entry_id === 8'h00.

### Test C — Dispatch to Bootstrap uPC 0x010
**Proves:** microsequencer dispatch table correctly routes ENTRY_NULL to
bootstrap uPC 0x010.
**Method:** monitors dbg_upc for value 12'h010.
**Pass condition:** dbg_upc reaches 12'h010 after dispatch.

### Test D — RAISE FC_UD Staged
**Proves:** bootstrap microcode RAISE FC_UD executes, staging fault class 0x6.
**Method:** monitors fault_pending and fault_class debug outputs.
**Pass condition:** fault_pending=1 and fault_class=0x6 (FC_UD) seen.

### Test E — ENDI Pulse
**Proves:** ENDI microinstruction executes.
**Method:** monitors endi_req AND endi_done for simultaneous assertion.
**Pass condition:** dbg_endi_pulse seen.

### Test F — Return to FETCH_DECODE
**Proves:** microsequencer returns to state FETCH_DECODE (2'h0) after ENDI.
**Method:** waits for endi seen, then monitors dbg_mseq_state.
**Pass condition:** dbg_mseq_state === 2'h0 after ENDI.

### Test G — No Deadlock (implicit)
**Proves:** machine does not deadlock; all above tests complete before
TIMEOUT (200 cycles).
**Method:** watchdog counter in testbench terminates simulation with FAIL
if TIMEOUT cycles elapse before all tests complete.
**Pass condition:** all tests complete within 200 cycles.

## Expected Output (passing run)

    --- Reset released, Rung 0 loop starting ---
    PASS Test A: first fetch at 0xFFFFFFF0 (correct reset vector)
    PASS Test B: decode_done asserted, entry_id=ENTRY_NULL (0x00)
    PASS Test C: uPC reached 0x010 (ENTRY_NULL dispatch address)
    PASS Test D: RAISE FC_UD staged (fault_class=0x6 = FC_UD)
    PASS Test E: ENDI occurred
    PASS Test F: microsequencer returned to FETCH_DECODE after ENDI
    
    === Rung 0 Testbench Summary ===
      Cycles elapsed: NN
      PASS: 6
      FAIL: 0
      RESULT: ALL TESTS PASSED
    PASS Test G: no deadlock — all tests completed in NN cycles
    ================================

## What Is NOT Covered

These are correct gaps for Rung 0 — they are verified in later rungs:

- NOP opcode (0x90) execution — Rung 1
- EIP advancement for real instructions — Rung 1
- Queue flush/refill after EIP-changing instruction — Rung 2+
- Real instruction semantics — Rung 6+
- Protected mode behavior — Phase 2
- Paging — Phase 3
- Full service ABI execution — Rung 5+
- Exception delivery via IVT — Rung 5

## Existing Bootstrap Checks

These must continue to pass alongside Rung 0 RTL tests:

    make spec-check
    make frozen-manifest-check
    make namespace-check
    make ucode-bootstrap-check
    make decode-dispatch-smoke
    make microseq-smoke
    make commit-smoke
    make service-abi-smoke
    make prefetch-decode-smoke
