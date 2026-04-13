# Keystone86 / Aegis — Rung 2 Front-End Rework Plan

## Status

Implementation plan.

This plan is subordinate to:

- `docs/spec/frozen/README.md`
- `docs/spec/design/front_end_stage_contracts.md`
- `docs/spec/design/fetch_stage_design.md`
- `docs/spec/design/decoder_stage_design.md`
- `docs/spec/design/microsequencer_stage_design.md`
- `docs/spec/design/commit_stage_design.md`
- `docs/spec/design/front_end_payloads.md`

This plan is intentionally narrow.

It exists to make **Rung 2** correct by implementing the minimum front-end/control contracts required to eliminate the current bug family without widening scope into later-rung cleanup or full front-end optimization.

---

## Objective

Rework the current Rung 2 front-end/control path so that:

1. instruction bytes are captured using position-proven rules
2. decode results become active only through an explicit decode/control acceptance boundary
3. control transfer does not allow stale old-path work to survive redirect
4. redirect becomes architecturally real only at commit
5. Rung 2 passes without papering over the issue in the testbench

This is a contract-implementation pass, not a symptom-fix pass.

---

## Implementation strategy decision

### Chosen strategy
**Strict control-transfer serialization first.**

### Architectural status
Epoch/freshness remains part of the architectural model and stays in the design notes.

### RTL status for this pass
Full epoch plumbing through every RTL boundary is **deferred**.

For this rework pass, the machine should instead use:

- strict control-transfer serialization
- explicit stale-work kill/squash behavior
- commit-owned redirect visibility
- no continued advancement of the abandoned stream once the accepted control packet says it is no longer useful

### Deferred optimization
Fetch-local direct stream following is **not** part of this rework pass.

It remains an allowed future optimization after Rung 2 is green and stable.

---

## Scope

This pass is limited to the contracts needed for correct Rung 2 control transfer.

### In scope
- fetch/decode byte-position correctness
- decode/control acceptance correctness
- control-transfer serialization correctness
- redirect/flush visibility correctness
- stale-work suppression correctness
- testbench proof of the above

### Out of scope
- later-rung functionality
- Makefile cleanup
- package/include cleanup
- broad refactoring
- fetch-local direct stream-follow optimization
- full epoch propagation implementation
- cosmetic redesign

---

## Contract implementation targets

### 1. Fetch → Decoder contract
Implement the fetch/decode boundary so decoder only consumes bytes that are proven to be the expected bytes of the current instruction in formation.

Required behavior:

- decoder must not rely on cycle timing intuition
- decoder must not assume “one cycle later” means “next byte”
- decoder must only capture a byte when the fetch-side payload proves:
  - byte valid
  - byte position matches expected byte position
  - byte belongs to the current non-stale stream

This is the immediate fix for the first-byte/displacement capture failure seen in Rung 2.

Likely files:
- `rtl/core/prefetch_queue.sv`
- `rtl/core/decoder.sv`

---

### 2. Decoder → Microsequencer contract
Implement the decode/control boundary so a decode result becomes the current instruction only on a real transfer.

Required behavior:

- decoder forms a stable registered decode result
- microsequencer accepts it only when ready
- decoder must hold the payload stable when not accepted
- the decode result is not yet the active instruction merely because decoder formed it
- the decode result becomes the active instruction only after transfer into microsequencer ownership

This is the immediate fix for weak decode acceptance semantics.

Likely files:
- `rtl/core/decoder.sv`
- `rtl/core/microsequencer.sv`

---

### 3. Control-transfer serialization
For this pass, control-transfer instructions must serialize the front end.

Required behavior:

- once a control-transfer decode payload has been accepted as the current control packet,
  the machine must not continue advancing the abandoned stream
- if the next useful stream anchor is not yet known, upstream must hold
- if the next useful stream anchor is known, the machine may prepare to retarget fetch,
  but old-stream work must not continue as though still current
- no stale old-path non-control decode/dispatch work may survive after accepted control says the stream changed

This is the immediate fix for the repeated stale non-JMP dispatch problem.

Likely files:
- `rtl/core/microsequencer.sv`
- `rtl/core/cpu_top.sv`
- `rtl/core/prefetch_queue.sv`
- `rtl/core/decoder.sv`

---

### 4. Commit-owned redirect visibility
Redirect must become architecturally real only at commit.

Required behavior:

- microsequencer may know a redirect consequence exists
- microsequencer may hold upstream accordingly
- commit is the stage that makes redirect/flush architecturally visible
- once commit makes redirect visible, abandoned upstream work must be invalidated
- top-level glue may route squash/flush consequences, but must not become a policy owner

This preserves the architectural visibility boundary.

Likely files:
- `rtl/core/commit_engine.sv`
- `rtl/core/microsequencer.sv`
- `rtl/core/cpu_top.sv`

---

## Practical implementation rules

### Rule A
Do not implement fetch-local direct stream following in this pass.

Reason:
- it is architecturally allowed
- but it is an efficiency optimization, not a prerequisite for correctness
- it would increase change scope before the contract baseline is proven

### Rule B
Do not implement broad payload refactors beyond what is necessary for the current boundaries.

Reason:
- the goal is to make the current structure obey the contracts
- not to redesign the whole front end in one pass

### Rule C
Prefer explicit hold/squash semantics over ad hoc timing tricks.

Reason:
- the current failure mode is fundamentally a contract problem

### Rule D
Do not bypass ownership to “make the test pass.”

Reason:
- that would create later-rung debt immediately

---

## Expected RTL focus

The most likely files for this rework are:

- `rtl/core/prefetch_queue.sv`
- `rtl/core/decoder.sv`
- `rtl/core/microsequencer.sv`
- `rtl/core/commit_engine.sv`
- `rtl/core/cpu_top.sv`

The intended change pattern is:

- strengthen boundary semantics
- keep ownership where it already belongs
- avoid widening decoder
- avoid making fetch a hidden decoder
- avoid making commit a hidden microsequencer

---

## Testbench requirements

The Rung 2 testbench should be used to prove the contracts, not just to count failures.

The rework is not complete unless the testbench demonstrates:

### A. Position-proven byte capture
The first short-JMP case must capture the displacement byte correctly from the correct byte position.

### B. Real decode/control acceptance boundary
The decode result must become active only when accepted by microsequencer.

### C. No stale old-path dispatch survives redirect
After the accepted control packet says the stream changed, old-path work must not continue.

### D. Redirect becomes visible only at commit
The visible stream change must align with commit-owned redirect visibility.

### E. Earlier rungs remain passing
Rung 0 and Rung 1 must remain green.

---

## Acceptance criteria

This rework pass is complete only when all of the following are true:

1. Rung 2 no longer exhibits the first-byte/displacement capture failure.
2. Rung 2 no longer exhibits stale old-path decode/dispatch after redirect.
3. The control-transfer path is serialized correctly for the current rung scope.
4. Redirect visibility remains commit-owned.
5. Rung 0 still passes.
6. Rung 1 still passes.
7. Rung 2 passes.

If any of the above are false, this pass is not complete.

---

## Deferred items after this pass

These are intentionally deferred until after the baseline is green:

- full epoch propagation through RTL
- fetch-local direct stream following optimization
- broader front-end optimization beyond current rung needs
- non-essential cleanup/refactor work

These may be addressed in a follow-on pass after Rung 2 is stable.

---

## Summary

This rework pass implements the minimum contract set needed to make Rung 2 correct:

- position-proven byte capture
- real decode/control acceptance
- strict control-transfer serialization
- commit-owned redirect visibility
- stale-work suppression

It does not attempt to solve every future optimization now.

It establishes the correct baseline first.