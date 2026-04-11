# Keystone86 / Aegis Bootstrap Repository
# Proceed / Hold Recommendation

---

## Decision: PROCEED — after applying corrections in this package

---

## Basis

The bootstrap repository scaffold is architecturally sound and aligned
with the frozen constitutional spec. The three issues found during review
(dispatch table corruption, truncated RTL package, incomplete state model)
have all been corrected in this reviewed deliverable. All five smoke checks
pass. The bootstrap ROM consistency check passes.

The scaffold now has:

- Frozen constitutional spec correctly imported and tracked
- Complete, correct RTL namespace (keystone86_pkg.sv and all svh files)
- Correct dispatch table mapping all four bootstrap entries
- Correct microcode ROM with consistent listing and layout documentation
- Four-state microsequencer model correctly specified
- All smoke check infrastructure functional
- CI and release scaffolding appropriate for phase
- Governance, contribution, and legal documents in place
- Bring-up ladder with gated rungs
- First-phase-only scope discipline visible

---

## What "Proceed" Means

Proceed means: begin Rung 0 RTL implementation.

Rung 0 is: reset path and fetch/decode loop using the bootstrap microcode.

That means implementing these modules first:
1. cpu_top skeleton
2. prefetch_queue (basic byte buffering)
3. decoder stub (outputs ENTRY_NULL for every opcode, asserts decode_done)
4. microsequencer (dispatch table lookup, uPC management, four states)
5. microcode_rom (load from ucode.hex)
6. commit_engine (reset state, ENDI with EIP commit only)
7. bus_interface (basic rd/wr/ready cycle)

Gate criterion for Rung 0: CPU asserts first bus read at physical
0xFFFFFFF0, decode_done fires, ENDI executes, microsequencer returns
to FETCH_DECODE without hanging.

---

## Conditions on Proceeding

These conditions apply during implementation, not before:

1. Use `import keystone86_pkg::*` in all RTL modules. Do not define
   local copies of shared constants.

2. Complete gen_from_appendix_a.py before any namespace change.
   Do not manually edit generated files after the generator exists.

3. Replace each smoke check with a real RTL testbench as each rung
   is completed. Smoke checks are bootstrap scaffolding, not final
   regression infrastructure.

4. Sub_fault_handler.uasm must be expanded at Rung 5 when INT_ENTER
   is implemented. The TODO(rung5) comment is a tracked obligation.

5. Apply the five drift review gates defined in drift_audit.md to all
   implementation PRs.

---

## What Would Change This to HOLD

The following would require stopping and reassessing:

- A proposal to move instruction sequencing out of microcode and into
  hardware (violates the core authority model)
- A proposal to make the decoder perform semantic work
  (violates the decoder contract)
- A discovery that ao486 RTL or Intel microcode was imported into
  the tree (provenance violation)
- A namespace change that cannot be traced to Appendix A
  (violates single-source-of-truth)

None of these conditions currently exist.

---

## Summary Statement

The corrected scaffold is a solid, disciplined implementation-start
repository for the Keystone86 / Aegis phase-1 core. The architecture
is sound, the guardrails are present, the namespace is aligned, and the
bootstrap ROM is correct.

Begin Rung 0.
