# Keystone86 / Aegis — Fetch Stage Design

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to clarify the intended role, boundaries, and behavior of the **fetch stage** within the staged Keystone86 front end.

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

This note only defines the behavior of **fetch** within that existing structure.

---

## Purpose

The fetch stage exists to supply a useful byte stream to the rest of the front end as efficiently as possible.

Fetch is not an instruction-semantics engine.

Fetch is not the authoritative decoder.

Fetch is not the architectural control owner.

Fetch is the owner of **byte-stream following**.

The purpose of this note is to define:

- who fetch is
- what fetch owns
- when fetch acts
- why fetch is allowed to act the way it does
- how fetch interacts with the rest of the machine

---

## Core design statement

Fetch follows the current useful byte stream.

Most of the time, that means continuing along the current sequential stream.

Sometimes the byte stream contains an **obvious direct turn** whose next stream location is already fully visible and directly computable from fetch-local byte information and stable mode context.

In those narrow cases, fetch may provisionally follow that turn rather than spending work on a stream already known to be less useful.

Fetch does this for efficiency, not for semantic authority.

The followed stream remains fetch-local and squashable until downstream authoritative acceptance confirms it.

---

## Who

Fetch owns:

- byte-stream following
- memory request generation for the currently followed stream
- prefetch / queue fill for the currently followed stream
- the current **stream anchor**
- stopping, pausing, continuing, or restarting fetch activity for that stream anchor
- provisional following of an **obvious direct stream turn** when that turn is fully visible and directly computable

Fetch does **not** own:

- authoritative instruction classification
- decode packet formation
- microcode entry selection
- architectural control policy
- architectural redirect truth
- commit visibility
- fault semantics
- stack or return-address semantics

Fetch is the owner of **fetching**, not the owner of **instruction meaning**.

---

## What

Fetch operates on a **fetch payload** and a **stream anchor**.

### Stream anchor
The stream anchor is the currently followed origin/path for the byte stream.

Conceptually, the stream anchor answers:

- where the currently useful byte stream is coming from
- whether fetch should continue on the current stream
- whether fetch should pause because the next useful stream is not yet known
- whether fetch should switch to a newly known stream location

### Fetch payload
The fetch stage should conceptually present a registered payload containing at least:

- visible byte value
- byte position / byte EIP
- payload valid
- epoch / freshness identity

The exact signal names may vary.

The important rule is that fetch presents a byte stream with enough information for downstream stages to know:

- whether the byte is meaningful
- where in the stream it belongs
- whether it belongs to the current epoch

---

## When

Fetch acts when it has enough truthful information to follow the stream honestly.

Fetch may continue requesting bytes when:

- the current stream anchor is still valid
- the current stream remains useful
- no hold/suspend rule prevents further fetch work

Fetch must pause when:

- the next useful stream anchor is not yet known
- downstream hold rules prevent further stage advance
- the current provisional stream has been invalidated by squash/epoch

Fetch may switch streams when:

- a new authoritative stream anchor becomes known
- or a narrow, obvious, direct stream turn is fully visible and directly computable in the fetch stage

Fetch must not continue blindly when the stream is no longer honestly known.

---

## Why

Fetch exists to reduce wasted work.

That includes avoiding waste in:

- memory arbitration
- fetch bandwidth
- queue occupancy
- front-end churn
- unnecessary fill of bytes likely to be flushed

If fetch already knows the next useful stream direction in a cheap, obvious, bounded way, it should not spend work on a byte stream already known to be less useful.

This is the reason fetch is allowed to perform limited stream-turn following.

The goal is not to make fetch “smart” in a broad sense.

The goal is to avoid needless work.

---

## How

Fetch works by maintaining and following a stream anchor.

In normal sequential execution:

- fetch follows the current sequential stream
- requests more bytes from that stream
- presents registered fetch payloads downstream

In a narrow direct-turn case:

- fetch sees that the stream contains an obvious direct turn
- the full turn information is already visible
- the new stream anchor is directly computable
- fetch may provisionally follow that new stream instead of continuing down a less useful path

If the stream is not yet knowable:

- fetch pauses rather than pretending certainty

If squash/epoch later invalidates the followed stream:

- fetch drops that provisional stream work
- fetch resumes from the correct authoritative stream anchor

This is a stream-following mechanism, not a semantic-decode mechanism.

---

## Registered payload requirement

Fetch must present a **registered payload** to the next stage.

Fetch output must not be treated as an informal combinational bundle whose meaning depends on fragile cycle-by-cycle timing assumptions.

At the boundary to the next stage, fetch should either:

- hold no valid payload
- or hold one stable registered payload until it transfers or is squashed

This makes fetch compatible with:

- explicit bubble behavior
- explicit hold/stall behavior
- later insertion of new stages
- correct squash/freshness handling

---

## Fetch-stage boundary contract

The fetch-stage output boundary should obey the standard staged contract.

### Valid
Fetch asserts `valid` when it is presenting a meaningful registered payload.

### Ready
The downstream stage asserts `ready` when it can accept that payload.

### Transfer
A payload transfer occurs only when:

- `valid == 1`
- `ready == 1`

### Hold / stall
If:

- `valid == 1`
- `ready == 0`

then fetch must hold its payload stable.

### Bubble
If `valid == 0`, fetch is presenting no meaningful work.
That is a bubble.

### Squash
A squash invalidates non-committed fetch-side work that belongs to an abandoned control-flow stream.

---

## Fetch-local stream following

Fetch may perform limited **stream-turn following**.

This is a narrow efficiency mechanism.

It does **not** give fetch broad instruction-semantic authority.

### Allowed case
Fetch may provisionally follow a turn only when all of the following are true:

- the turn form is directly recognizable from fetch-visible bytes
- the full turn information is already visible
- the exact next stream anchor is fully computable
- no external architectural state is needed
- no condition evaluation is needed
- the followed result remains provisional and squashable until downstream acceptance confirms it

### Purpose
This exists to avoid:

- fetching bytes on a stream already known to be less useful
- unnecessary flush/restart churn
- wasting arbitration and bandwidth on obviously poor continuation paths

---

## Obvious direct turns

The phrase **obvious direct turn** is intentionally narrow.

It means a stream turn whose next useful stream location is:

- directly encoded in the currently visible bytes
- fully available now
- directly computable from fetch-local information plus stable mode context

Examples may include:

- direct short relative turn forms
- direct near relative turn forms
- direct call target forms when the full target information is visible

This does **not** automatically generalize to all control-transfer instructions.

---

## What fetch must not do

Fetch must not become a hidden second decoder or control engine.

Fetch must not own:

- authoritative instruction classification
- entry-ID generation
- microcode dispatch policy
- architectural acceptance of a control transfer
- condition evaluation
- indirect-target resolution
- return-target resolution
- fault/exception resolution
- architectural redirect truth

Fetch may follow a stream.

Fetch must not redefine what the instruction means.

---

## Relationship to decoder

Decoder remains the first authoritative instruction classifier.

Fetch may present:

- bytes
- byte position
- epoch/freshness
- optional fetch-local stream-following state

Decoder still owns:

- instruction formation
- entry selection inputs
- instruction-local facts such as fall-through EIP and target EIP
- authoritative decode packet formation

Fetch must not replace decoder authority.

---

## Relationship to microsequencer

Microsequencer remains the owner of control acceptance and control policy.

Fetch may provisionally follow an obvious direct turn for efficiency.

But the microsequencer still owns:

- accepted control-packet meaning
- hold/squash policy
- control-transfer policy
- when the machine has authoritatively accepted the new control flow

This keeps fetch efficient without making it a hidden control owner.

---

## Relationship to commit / redirect

Commit remains the architectural visibility boundary.

Fetch-local stream following is provisional front-end behavior.

Commit/redirect remains the point where redirect becomes architecturally real and squash/epoch rules invalidate abandoned work.

This distinction must remain explicit:

- fetch may follow a useful stream locally
- commit defines architectural truth

---

## Epoch / freshness in fetch

Fetch-side work must still participate in epoch/freshness rules.

Each fetch payload belongs to an epoch.

When redirect commits:

- the current epoch advances
- older fetch-side work becomes stale
- stale payloads must not be consumed further

This ensures that provisional stream following cannot leak stale work into later stages.

---

## Hold versus squash in fetch

These two concepts must remain distinct.

### Hold / stall
A held fetch payload is still valid.
Fetch is waiting because downstream is not ready or because advancement is temporarily suspended.

### Squash
A squashed fetch payload is invalid.
It belongs to work that must not continue.

Confusing these two concepts causes stale-stream bugs.

---

## Memory arbitration principle

Fetch should not continue consuming memory arbitration for a stream that no longer makes sense to follow.

If fetch already knows, in a narrow and honest way, that the next useful stream lies elsewhere, it should avoid wasting requests on the less useful stream.

This is one of the primary motivations for limited fetch-local stream following.

Efficiency matters.

Work costs something.

The machine should avoid doing work that it already knows is poor-value work.

---

## Scalability value

A properly defined fetch stage helps the whole machine scale later.

By keeping fetch focused on stream following rather than broad semantic ownership, the design preserves:

- a small decoder
- a tight decoder-to-microsequencer relationship
- clear ownership boundaries
- a clean path for inserting later stages if needed

The stable thing is the **fetch contract**, not the exact implementation depth.

---

## Summary

Fetch is the owner of **byte-stream following**.

Fetch:

- follows the current useful stream
- presents registered fetch payloads
- obeys valid/ready/hold/bubble/squash discipline
- may provisionally follow an **obvious direct stream turn**
- does so for efficiency
- remains subordinate to downstream authoritative decode/control/commit ownership
- must keep all provisional work squashable and freshness-aware

Fetch is not a hidden decoder.

Fetch is not a hidden control engine.

Fetch is the stage that follows the byte stream honestly and efficiently.