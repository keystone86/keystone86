# Keystone86 / Aegis — Commit Stage Design

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to clarify the intended role, boundaries, and behavior of the **commit stage** within the staged Keystone86 machine.

If any statement in this document conflicts with the frozen constitutional files, the frozen files take precedence.

---

## Relationship to frozen specification

This note supports the frozen constitutional source defined in:

- `docs/spec/frozen/README.md`
- `docs/spec/frozen/master_design_statement.md`
- `docs/spec/frozen/appendix_b_ownership_matrix.md`
- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This note does not alter the frozen ownership model.

The frozen intent already establishes that:

- **z8086** is the structural template for the machine
- **ao486** is the semantic donor, not the architectural control template
- the **decoder** is a classifier / instruction-local fact former
- the **microsequencer** is the center of execution sequencing and control policy
- the **commit path** is the architectural visibility boundary for redirect, flush, and state commitment
- top-level glue routes signals between owners and does not become a hidden policy owner

This note only defines the behavior of **commit** within that existing structure.

---

## Purpose

The commit stage exists to turn accepted downstream control intent into **architecturally visible machine state**.

Commit is not the owner of byte-stream formation.

Commit is not the owner of instruction-local field discovery.

Commit is not the owner of microcode sequencing.

Commit is the owner of:

- architectural state visibility
- architectural state update point
- redirect visibility
- flush visibility
- fault-pending / fault-visible architectural boundary
- epoch advancement associated with redirect/freshness change

The purpose of this note is to define:

- who commit is
- what commit owns
- when commit may make machine-visible changes
- why commit must remain narrow and authoritative
- how commit interacts with microsequencer upstream and the front end downstream

---

## Core design statement

Commit is the stage where control intent becomes architectural fact.

Upstream stages may form bytes, facts, packets, and control context.

Commit is the stage that decides when those things become **visible machine state**.

This includes:

- EIP update
- redirect visibility
- flush visibility
- architectural fault visibility
- architectural register/state updates passed into commit

Commit does not decide what instruction means.
Commit decides when the visible machine state changes.

Commit is therefore the **architectural boundary**, not the semantic center of the machine.

---

## Who

Commit owns:

- architectural visibility of state updates
- application of committed EIP updates
- architectural redirect visibility
- architectural flush visibility
- architectural fault-pending / fault-visible state transition
- epoch advance associated with redirect or other freshness-resetting architectural events
- final “this now counts” boundary for state updates presented to it

Commit does **not** own:

- byte gathering
- instruction-local classification
- decode payload formation
- current control-packet acceptance
- microcode sequencing policy
- fetch request generation mechanics
- opportunistic prefetch contents as architectural state
- hidden instruction semantics inference

Commit is the owner of **architectural visibility**, not **instruction formation** or **control sequencing**.

---

## What

Commit operates on:

- registered control intent from upstream
- local architectural state registers and visibility state
- architectural output effects seen by the rest of the machine

### Control intent
Conceptually, commit receives intent such as:

- update architectural EIP to value X
- apply architectural register/state update Y
- raise architectural fault class Z
- perform architectural redirect/flush consequence
- commit fault-visible side effects
- complete/end an instruction’s architectural effects

The exact signal names may vary.

The important rule is that upstream presents **intent**, and commit determines when it becomes visible architectural truth.

### Architectural state
Commit owns or directly updates architectural state such as:

- architectural EIP
- architecturally visible fault state
- architecturally visible control-transfer visibility
- architecturally visible flush / redirect effects
- other architecturally committed machine state routed through commit

The exact committed state set may expand later, but the ownership boundary should remain the same.

---

## When

Commit acts when it has valid control intent that is allowed to become machine-visible.

Commit may update architectural state when:

- upstream presents a valid committed-intent packet or equivalent committed control signals
- commit is ready to apply those updates
- no higher-priority squash/invalidity rule prevents visibility
- the work belongs to the current epoch and is not stale

Commit must not expose state changes merely because upstream local state exists.

Commit may only expose state changes at the architectural boundary.

Commit must pause when:

- upstream intent is not yet valid for visibility
- required architectural conditions are not yet met
- stale work is being invalidated
- the current visibility boundary should not yet advance

Commit acts only when machine-visible truth is ready to change.

---

## Why

Commit exists to keep architectural truth separate from front-end and control-stage provisional work.

This is essential because:

- fetch work is opportunistic
- decoder work is instruction-local formation
- microsequencer work is active control context
- none of those should automatically count as architecturally real

Without a clean commit boundary, the machine blurs:

- provisional work
- active control work
- architectural truth

That is exactly how stale-work and redirect bugs spread.

Commit exists so the machine has one clear answer to:

> “When does this become real?”

---

## How

Commit works by receiving control intent from upstream and deciding when that intent becomes visible machine state.

In normal operation:

- upstream control sequencing reaches a point where architectural effects should be exposed
- commit receives that intent
- commit applies the state updates
- commit exposes redirect/flush/fault effects as appropriate
- commit updates the architectural state registers
- commit signals completion/visibility back as needed

Commit is therefore a **visibility stage**.

It is not a decoder.
It is not a fetch stage.
It is not the microsequencer.

It is the point where machine-visible state is updated.

---

## Registered intent requirement

Commit should receive **registered control intent** from upstream.

Architectural visibility must not depend on fragile combinational implication from transient control signals.

At the upstream boundary, commit should conceptually see either:

- no valid architectural-intent payload
- or one stable registered intent payload until accepted, applied, or invalidated

This makes commit compatible with:

- explicit hold/stall behavior
- explicit completion/visibility acknowledgment
- explicit squash/freshness handling
- later insertion of new stages if needed

The stable thing is the architectural-intent contract, not the exact local register implementation.

---

## Commit-stage boundary contract

The upstream-to-commit boundary should obey the standard staged contract.

### Valid
Upstream presents valid architectural-intent information when it is ready for visibility consideration.

### Ready
Commit asserts ready when it can accept and apply that intent.

### Transfer
A transfer occurs only when:

- `valid == 1`
- `ready == 1`

### Hold / stall
If:

- `valid == 1`
- `ready == 0`

then upstream must hold the intent stable.

### Bubble
If `valid == 0`, there is no meaningful architectural-intent payload to apply.
That is a bubble at the commit boundary.

### Squash
A squash invalidates stale or abandoned pre-architectural work before it becomes visible architectural truth.

---

## Architectural visibility rule

The central rule of commit is:

> Nothing becomes architecturally true merely because an upstream stage has formed it, accepted it, or sequenced it.

It becomes architecturally true only when commit applies it.

This rule applies to:

- EIP changes
- redirect/flush visibility
- fault visibility
- state updates routed through commit

This keeps the machine honest about the difference between:

- local stage truth
- architectural truth

---

## Relationship to microsequencer

Microsequencer remains the owner of control acceptance and sequencing.

Commit does not decide:

- which instruction is active
- which microcode path is being executed
- what the control policy should be
- whether a decode payload should have been accepted

Microsequencer presents **control intent**.

Commit decides whether and when that intent becomes architecturally visible.

This boundary must remain explicit:

- microsequencer owns control
- commit owns visibility

Commit must not silently become another control sequencer.

---

## Relationship to decoder

Decoder remains the owner of instruction-local fact formation.

Commit must not consume decoder-level facts as though they were already architectural truth.

For example:

- `next_eip`
- `target_eip`
- control kind
- target-known indication

are not architectural truth merely because decoder formed them.

They only matter architecturally if and when upstream control sequencing chooses to present corresponding architectural intent to commit.

This keeps decoder narrow and prevents semantic drift into commit.

---

## Relationship to fetch and prefetch

Fetch/prefetch contents are not architectural state.

Commit must treat fetch-side stream data and queue contents as opportunistic front-end state.

When redirect becomes architecturally visible at commit:

- the machine-visible fetch stream changes
- flush becomes real
- stale fetch-side work becomes invalid by architectural consequence

This is exactly why fetch-side provisional work must remain squashable.

Commit does not fetch bytes.
Commit defines when the machine has officially changed streams.

---

## Redirect and flush ownership

Redirect is not merely a fetch optimization.

Redirect is an architectural event.

That means:

- upstream may determine that a control-transfer consequence exists
- upstream may prepare the new target
- commit is the stage where redirect becomes architecturally visible
- flush is the visible consequence that invalidates abandoned stream work

This ownership split is essential.

If redirect becomes “real” earlier than commit, then the architectural boundary is blurred.

If redirect is delayed past commit visibility, then stale work can leak forward.

So the rule is:

- control may know redirect is coming
- commit makes redirect true

---

## Epoch / freshness in commit

Commit is the correct place to advance the architectural epoch for redirect/freshness purposes.

Each in-flight payload or control context belongs to an epoch.

When redirect becomes architecturally visible:

- the epoch advances
- older in-flight work becomes stale
- stale upstream work must be squashed or ignored
- subsequent work must belong to the new epoch

This is the cleanest place to define freshness change because commit is already the architectural boundary.

Commit therefore owns:

- the machine-visible freshness boundary
- not every local stale check in upstream stages, but the event that makes them stale

---

## Fault visibility

Fault signaling must also respect the architectural boundary.

Upstream stages may discover or carry fault intent.

Commit determines when the fault becomes architecturally visible and when corresponding visible machine state reflects that fact.

This keeps fault behavior aligned with the same general principle:

- formation/discovery upstream
- visibility at commit

Commit should not become a semantic fault-analysis block.
It should remain the visibility boundary for fault state.

---

## Local commit state

Commit may hold local state such as:

- architectural EIP register
- architectural fault-pending / visible state
- redirect-visible / flush-visible state
- completion/done indication state
- epoch register or equivalent freshness boundary state

This state is architectural or directly tied to architectural visibility.

Unlike upstream formation state, commit-local state is closer to machine truth.

It must therefore be treated carefully and not casually widened into a broader control engine.

---

## Hold versus squash in commit

These two concepts must remain distinct.

### Hold / stall
A held architectural-intent payload is still valid.
Commit is not yet ready to make it visible.

### Squash
A squashed payload is invalid.
It must not become visible because it belongs to stale or abandoned work.

At commit, this distinction is especially important because once something becomes visible, it is no longer just provisional work.

---

## Commit must stay narrow

Commit is crucial, but it must remain narrow in ownership.

That means commit should not gradually absorb:

- byte-stream policy
- decoder-local classification work
- microsequencer sequencing policy
- helper/service routing policy
- “temporary” fixes that move control semantics into commit

Commit should remain the place where:

- architectural state changes become visible
- freshness boundaries are made real
- redirect/flush become real
- fault visibility becomes real

It should not become the entire machine’s policy engine.

---

## What commit must not do

Commit must not become:

- a hidden decoder
- a hidden fetch controller
- a hidden microsequencer
- a block that infers instruction semantics from raw or partially processed information

Specifically, commit must not own:

- byte gathering
- decode payload formation
- accepted control-packet selection
- microcode dispatch sequencing
- stream-following mechanics
- opportunistic prefetch policy

Commit may receive the results of those stages.
It must not become a substitute for them.

---

## Relationship to squash propagation

Commit is the architectural source of visibility-changing events such as redirect.

Top-level glue may route squash/flush/freshness consequences outward.

That routing must remain routing.

Top-level glue must not become a hidden policy owner merely because it distributes the commit-visible consequences.

This preserves the same ownership discipline used throughout the machine.

---

## Scalability value

A properly defined commit stage helps the machine scale later.

By keeping commit narrow and authoritative over visibility only, the design preserves:

- clear distinction between provisional work and architectural truth
- clean redirect and freshness boundaries
- a narrow decoder
- a narrow but central microsequencer
- the ability to add more stages later without losing the “what is real?” boundary

The stable thing is the **commit contract**, not the exact local implementation detail.

---

## Summary

Commit is the owner of **architectural visibility**.

Commit:

- receives registered control intent
- applies machine-visible state updates
- makes EIP/redirect/flush/fault consequences real
- defines the architectural freshness boundary
- advances epoch when redirect becomes visible
- obeys valid/ready/hold/bubble/squash discipline
- remains narrow by design
- does not become decoder, fetch, or microsequencer

Commit is not a hidden control engine.

Commit is the stage where machine intent becomes architecturally visible truth.