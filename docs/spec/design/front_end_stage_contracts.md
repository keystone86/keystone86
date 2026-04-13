# Keystone86 / Aegis — Front-End Stage Contracts

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to clarify the interface discipline required to preserve that frozen intent as the implementation moves into deeper control-flow and later-rung work.

---

## Relationship to frozen specification

The frozen constitutional source for this project is defined in:

- `docs/spec/frozen/README.md`
- `docs/spec/frozen/master_design_statement.md`
- `docs/spec/frozen/appendix_b_ownership_matrix.md`
- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This note is written to support those files, not to modify them.

The frozen intent already establishes the following:

- **z8086** is the structural template for the machine
- **ao486** is the semantic donor, not the architectural control template
- the **decoder** is a classifier / instruction-local fact former, not a giant semantic implementation block
- the **microsequencer** is the center of execution sequencing and control policy
- the **commit path** is the architectural visibility boundary for redirect, flush, and state commitment
- top-level glue routes signals between owners and must not silently become a policy owner

This note only clarifies how those existing owners should communicate safely in a staged front end.

If any statement in this document conflicts with the frozen constitutional files, the frozen files take precedence.

---

## Purpose

The project is not merely implementing isolated rung behaviors.

It is building a coherent CPU from two complementary sources:

- **z8086** provides the structural shape:
  - small decoder
  - staged front end
  - queue/loader-style byte flow
  - entry-table to microcode-style control handoff

- **ao486** provides the donor semantics:
  - instruction behavior
  - protected-mode/control/cache semantics
  - microcode-level behavioral intent

Keystone86 must supply the new **systems layer** that allows those two ideas to work together cleanly.

That systems layer is the subject of this note.

This document is the umbrella note for that systems layer. It defines the common front-end discipline, while more detailed stage-specific guidance is captured in the companion design notes listed later in this document.

---

## Core design statement

The front end must be treated as a set of explicit stages with explicit handoff contracts.

The current machine already behaves as a staged design, whether or not it was originally described that way.

The correct response is **not** to collapse those stages or patch timing symptoms one by one.

The correct response is to formalize the stage boundaries and define:

- when data is valid
- when it may advance
- when it must hold
- when it is a bubble
- when it is squashed
- how freshness is preserved across redirect
- how the currently useful byte stream is followed

This is a correctness discipline, not a performance promise.

---

## Architectural ownership remains unchanged

This note does **not** change the frozen ownership model.

The ownership model remains:

- **prefetch/fetch-side logic** owns byte visibility and stream position
- **decoder** owns instruction formation and decode facts
- **microsequencer** owns control acceptance and dispatch policy
- **commit path** owns architectural visibility and redirect/flush effects
- **top-level glue** routes signals between owners and does not become a policy owner

This note only clarifies how those owners communicate safely.

---

## The machine structure being preserved

The intended structure remains:

1. byte stream becomes visible
2. decoder forms an instruction-local result
3. decoder presents an entry to the dispatch table
4. dispatch table produces a microcode entry address
5. microsequencer takes control from that entry point
6. commit path makes architectural effects visible

That is still the correct overall model.

The missing piece is not the existence of that structure.

The missing piece is the rigor of the handoff contracts between stages.

---

## Stage model

The front end should be described as four logical stages.

### Stage F — Fetch / Prefetch visibility
Owner: fetch/prefetch-side logic

Responsibility:
- present the currently visible byte stream element
- identify its byte position
- follow the current useful stream
- expose a registered fetch payload to the decode stage

### Stage D — Decode / instruction formation
Owner: decoder

Responsibility:
- gather instruction bytes
- classify instruction family
- extract instruction-local fields
- form a compact registered decode payload

### Stage X — Dispatch / control acceptance
Owner: microsequencer

Responsibility:
- accept a decode result
- determine the microcode entry flow
- own control-transfer policy
- determine when the front end may advance, hold, or change streams

### Stage C — Commit / architectural visibility
Owner: commit path

Responsibility:
- make architectural state visible
- apply redirect and flush effects
- define the boundary between speculative/in-flight work and architecturally real work

---

## Registered payload requirement

Each stage boundary should carry a **registered payload**.

A stage boundary must not be treated as an informal set of combinational wires whose meaning depends on cycle-by-cycle timing assumptions.

Each stage should either:

- hold no valid payload
- or hold one registered payload that remains stable until transferred or squashed

This rule is fundamental to later scalability.

It allows:

- clear bubble behavior
- clear hold/stall behavior
- safe insertion of additional stages later
- safe reasoning about redirect and freshness

The stable thing is the **payload contract**, not the exact number of stages in the machine.

---

## Stage-boundary contract model

Every stage boundary should be governed by a small set of formal concepts.

### Valid
A stage asserts `valid` when it is presenting a meaningful registered output payload.

### Ready
A downstream stage asserts `ready` when it can accept that payload.

### Transfer
A payload transfer occurs only when:

- `valid == 1`
- `ready == 1`

### Hold / stall
If:

- `valid == 1`
- `ready == 0`

then the upstream stage must hold its payload stable.

### Bubble
If `valid == 0`, the stage is presenting no meaningful work.
That is a bubble.

### Squash
A squash invalidates non-committed in-flight work that belongs to an abandoned control-flow stream.

These concepts should be used consistently at stage boundaries.

---

## Epoch / freshness requirement

A redirect boundary needs more than queue flush alone.

A redirect must establish a new front-end generation, referred to here as an **epoch**.

### Epoch rule
Each fetch/decode/dispatch payload belongs to an epoch.

When redirect becomes architecturally visible:

- the current epoch advances
- work from older epochs becomes stale
- stale payloads must not be consumed further

This is how the design distinguishes:

- current-path work
from
- abandoned wrong-path work

without moving policy into the wrong block.

---

## Why epoch is necessary

The current class of control-flow failures shows two distinct symptoms:

1. incorrect byte capture during instruction formation
2. wrong-path decode/dispatch work surviving redirect

Those are not unrelated accidents.

They are signs that the system still lacks an explicit freshness contract across stage boundaries.

Epoch supplies that contract.

---

## Common byte-stream truth rule

Byte gathering and stream following must not rely on timing guesses.

A stage may only treat a byte as meaningful for the current instruction or current stream position when the upstream payload proves that the byte is:

- valid
- at the expected byte position
- from the current epoch

The exact signal names may vary.

The rule must not.

This means the machine must not assume that:

- “one cycle later” means “next byte”
- or
- “visible now” means “belongs to the current instruction”

Truth at stage boundaries must be position-proven and freshness-aware.

---

## Stream-anchor rule

The front end should be reasoned about in terms of the **current useful stream anchor**.

The key front-end systems question is:

**What is the current useful byte stream, and is its continuation already known?**

This is broader and cleaner than phrasing the whole problem as only “jump versus call.”

### If the current useful stream continues sequentially
Then the front end may continue along that stream.

### If a new useful stream anchor is known
Then the machine may move fetch toward that stream.

### If the next useful stream anchor is not yet known
Then the front end must not continue blindly down a possibly wrong stream.

In that case, the machine must hold or bubble as appropriate until the next useful stream becomes known.

---

## Accepted control packet rule

Control transfer must be governed by the **accepted control packet**, not by mere early observation in the decoder.

That means:

- decoder may compute instruction-local facts such as:
  - `next_eip`
  - `target_eip`
  - control kind
  - whether the target is already known

- microsequencer / control decides when that decode payload has been accepted as the current control packet

Only after that acceptance may control-transfer policy take effect.

This preserves ownership correctly:

- decoder forms facts
- control decides what to do with them

---

## Fetch-local direct stream following

Fetch may perform limited **fetch-local direct stream following** for efficiency.

This is intentionally narrow.

It exists so the machine does not waste fetch bandwidth, arbitration, or queue work on a stream already known to be less useful when an obvious direct turn is fully visible and directly computable.

This mechanism is allowed only when:

- the turn form is directly recognizable from fetch-visible bytes
- the full turn information is already visible
- the next useful stream anchor is directly computable from fetch-local byte information and stable mode context
- no external architectural state is needed
- the followed result remains provisional and squashable until downstream acceptance confirms it

This does **not** make fetch the authoritative decoder, control owner, or architectural redirect owner.

It is a fetch-local efficiency mechanism only.

---

## Exact next useful stream rule

The correct control-flow question is not simply:

- “is this a jump?”
- or
- “is this a call?”

The correct question is:

**Does the currently authoritative front-end/control state already define the exact next useful stream anchor?**

### If the exact next useful stream anchor is known
Then the machine may:

- suppress useless continuation of the abandoned stream
- move fetch toward the new useful stream
- restart or retarget fetch as appropriate

### If the exact next useful stream anchor is not yet known
Then the machine must not continue down a possibly wrong stream.

In that case, control must:

- hold the front end
- preserve or bubble stage contents as appropriate
- wait until the exact next useful stream anchor becomes known

This rule generalizes cleanly to later rungs.

---

## Early-rung control-transfer policy

During early control-flow bring-up, the front end may conservatively serialize control transfer.

This means that once a control-transfer payload has been accepted for dispatch, the control layer may temporarily prevent further front-end advance until the next useful stream anchor is resolved and redirect has been issued or completed.

This is permitted because:

- control policy still belongs to the microsequencer
- architectural visibility still belongs to commit
- decoder still only forms facts
- fetch-local direct stream following remains provisional and squashable

This is a correctness-first policy for bring-up, not a claim about final performance architecture.

---

## Hold versus squash

These two concepts must remain distinct.

### Hold / stall
A held payload is still valid.
It is waiting because downstream is not ready or because control has deliberately stopped advancement.

### Squash
A squashed payload is invalid.
It belongs to work that must not continue.

Confusing these two concepts leads directly to stale-work bugs.

The project should treat them as different mechanisms with different meanings.

---

## Companion design notes

This document is the umbrella front-end stage-contract note.

Detailed stage-specific support is captured in:

- `docs/spec/design/fetch_stage_design.md`
- `docs/spec/design/decoder_stage_design.md`
- `docs/spec/design/microsequencer_stage_design.md`
- `docs/spec/design/commit_stage_design.md`
- `docs/spec/design/front_end_payloads.md`

Those documents elaborate the same ownership model from the viewpoint of each stage and of the payload contracts between them.

If more detailed stage-specific interpretation is needed, those notes should be consulted alongside this umbrella note.

---

## What this note permits

This note permits the design to introduce and use:

- explicit stage boundaries
- registered payloads at stage boundaries
- valid/ready semantics
- bubbles
- stage-local holds/stalls
- squash behavior
- epoch/freshness tracking across redirect
- accepted-control-packet semantics for control transfer
- fetch-local direct stream following in the narrow direct-turn case
- movement toward a new useful stream when that stream is known
- conservative control-transfer serialization during bring-up

These are interface-discipline mechanisms.

They do **not** change architectural ownership.

---

## What this note does not permit

This note does **not** permit:

- moving redirect policy into the decoder
- making fetch/prefetch logic the authoritative owner of instruction semantics
- making helper logic a hidden control-policy owner
- overloading architectural signals to hide stage-boundary problems
- using cleanup/refactoring language to justify ownership drift

Those remain outside the intended design direction.

---

## Long-term value

This stage-contract model is not just a Rung 2 patch.

It is the basis for scaling the design later.

Formal stage contracts make it possible to:

- add more stages later
- split stages later
- insert buffering later
- preserve a small decoder
- preserve microcode-oriented control flow
- avoid repeated rediscovery of the same stale-work and byte-validity bugs

The stable thing should be the **contract meaning**, not the exact number of stages.

Later stage count may change.
Contract meaning must remain stable.

---

## Summary

Keystone86 should continue to follow this synthesis:

- **z8086** provides the structural shape
- **ao486** provides the semantic donor intent
- **Keystone86** supplies the systems discipline that makes the combination correct

That systems discipline is:

- explicit stages
- registered payloads
- valid/ready handoff
- bubbles
- stalls/holds
- squash
- epoch/freshness across redirect
- accepted control packets
- stream-anchor reasoning
- narrow fetch-local direct stream following
- unchanged ownership boundaries

This is the intended direction for the front end going forward.