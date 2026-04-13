# Keystone86 / Aegis — Decoder Stage Design

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to clarify the intended role, boundaries, and behavior of the **decoder stage** within the staged Keystone86 front end.

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

This note only defines the behavior of **decoder** within that existing structure.

---

## Purpose

The decoder stage exists to transform a visible byte stream into a compact, authoritative, instruction-local decode payload.

Decoder is not the owner of instruction execution.

Decoder is not the owner of architectural control policy.

Decoder is not the owner of redirect truth.

Decoder is the owner of:

- instruction formation
- byte gathering
- instruction-local field extraction
- coarse classification
- decode payload formation

The purpose of this note is to define:

- who decoder is
- what decoder owns
- when decoder may form and present a decode payload
- why decoder is intentionally narrow
- how decoder interacts with fetch upstream and microsequencer downstream

---

## Core design statement

Decoder forms one instruction-local payload from the current useful byte stream.

Decoder should remain small.

It should gather only the bytes needed to form the current instruction-local facts, classify the instruction into the correct family/entry, and present a compact decode payload for control acceptance.

Decoder does **not** decide what the machine will ultimately do with that instruction.

Decoder does **not** decide whether a control transfer is architecturally accepted.

Decoder does **not** decide when redirect becomes architecturally real.

Decoder forms facts.
Control decides policy.
Commit defines architectural truth.

---

## Who

Decoder owns:

- byte gathering for the current instruction
- instruction boundary recognition
- coarse instruction classification
- extraction of instruction-local fields needed by control
- construction of a registered decode payload
- holding that payload stable until transfer or squash

Decoder does **not** own:

- microcode execution sequencing
- accepted control-packet policy
- redirect/flush policy
- architectural commit visibility
- condition resolution outside instruction-local formation
- indirect target resolution that requires non-local execution state
- stack / return-address semantics
- fault service policy
- memory-side service policy

Decoder is the owner of **instruction formation**, not **instruction policy**.

---

## What

Decoder operates on:

- a registered fetch payload from the fetch stage
- internal byte-gather state for one instruction in formation
- a registered decode payload toward the control stage

### Instruction in formation
Decoder may hold temporary instruction-local formation state such as:

- opcode byte
- opcode position / opcode EIP
- prefixes relevant to current formation
- displacement bytes
- immediate bytes
- current inferred length/state of the instruction under formation
- mode/context bits explicitly supplied to decoder

This state is local, provisional, and squashable.

### Decode payload
Decoder should produce a compact registered payload containing instruction-local facts such as:

- entry identifier
- opcode EIP
- fall-through EIP / instruction-end EIP
- control-transfer target EIP when directly known
- control kind
- target-known indication
- prefix / class / mode bits needed by control
- epoch / freshness identity

The exact signal names may vary.

The important rule is that the payload contains **facts**, not downstream policy decisions.

---

## When

Decoder acts when it has enough truthful information to form the current instruction honestly.

Decoder may consume fetch payload bytes when:

- the fetch payload is valid
- the byte position is the expected byte position for the current instruction in formation
- the byte belongs to the current epoch
- no hold rule prevents further instruction formation

Decoder must not gather bytes by timing guesswork.

Decoder must not assume that “one cycle later” automatically means “next instruction byte.”

Decoder may present a decode payload only when:

- the instruction in formation is complete enough for authoritative decode-payload formation
- the payload fields are stable
- the payload belongs to the current epoch

Decoder must pause when:

- required bytes are not yet available
- the current instruction cannot yet be honestly completed
- downstream is not ready to accept a payload and decoder is already holding a valid one
- the current instruction in formation has been invalidated by squash/epoch

Decoder moves only when instruction-local truth is available.

---

## Why

Decoder exists to keep semantic understanding narrow, local, and structured.

The project goal is to preserve the small-decoder spirit of z8086 while using ao486 donor semantics.

That means decoder should not become:

- a giant semantic engine
- a hidden execution controller
- a hidden redirect controller
- a catch-all block for every bug fix

The decoder should answer the smallest useful set of questions:

- what instruction family is this?
- what bytes belong to it?
- what local fields are present?
- what entry should control see?
- what are the instruction-local EIP facts?
- is there a directly known control target?
- is the target not yet known?

That narrowness is intentional.
It keeps the system clean and scalable.

---

## How

Decoder works by assembling one instruction-local view from the byte stream presented by fetch.

In normal operation:

- fetch presents registered byte payloads
- decoder consumes those bytes only when their position matches the expected next byte of the current instruction in formation
- decoder accumulates local formation state
- once the instruction is complete enough, decoder produces a registered decode payload
- decoder holds that payload until it transfers or is squashed

Decoder is therefore a **formation stage**.

It is neither a passive wire nor a policy engine.

It is the place where the byte stream becomes one authoritative instruction-local packet.

---

## Registered payload requirement

Decoder must present a **registered decode payload** to the next stage.

Decoder output must not be treated as an informal combinational bundle whose meaning depends on fragile cycle-by-cycle timing assumptions.

At the boundary to the next stage, decoder should either:

- hold no valid decode payload
- or hold one stable registered decode payload until it transfers or is squashed

This makes decoder compatible with:

- explicit bubble behavior
- explicit hold/stall behavior
- correct squash/freshness handling
- later insertion of new stages if needed

The stable thing is the decode payload contract, not the exact internal state-machine shape.

---

## Decoder-stage boundary contract

The decoder-stage output boundary should obey the standard staged contract.

### Valid
Decoder asserts `valid` when it is presenting a meaningful registered decode payload.

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

then decoder must hold its decode payload stable.

### Bubble
If `valid == 0`, decoder is presenting no meaningful decode payload.
That is a bubble.

### Squash
A squash invalidates decoder-local in-flight work that belongs to an abandoned control-flow stream or stale epoch.

---

## Relationship to fetch

Fetch owns byte-stream following.

Decoder consumes the byte stream; it does not own the stream itself.

Decoder must treat fetch payloads as the authoritative source of:

- visible byte value
- byte position / byte EIP
- payload validity
- epoch / freshness

Decoder may not assume a byte belongs to the current instruction merely because it is visible.

Decoder may only accept a byte when the fetch payload proves that the byte is the expected byte of the current instruction in formation.

This means decoder depends on **byte-position truth**, not timing hope.

---

## Byte gather rule

Byte gathering must be position-proven.

Decoder may only capture a byte when all relevant conditions are true:

- fetch payload is valid
- fetch payload belongs to the current epoch
- fetch payload byte position matches the expected next byte position of the current instruction

Examples:

- opcode byte is accepted only when the byte position matches the opcode start
- first displacement byte is accepted only when the byte position matches `opcode_eip + 1`
- second displacement byte is accepted only when the byte position matches `opcode_eip + 2`

The exact signal names may vary.

The rule must not.

Decoder must never rely on “consume happened earlier, therefore the currently visible byte must now be the next byte.”

---

## Instruction formation state

Decoder may keep local state for the instruction currently being formed.

This state may include:

- current formation state / substate
- opcode byte
- opcode EIP
- prefix accumulation
- displacement bytes
- immediate bytes
- inferred length
- local class bits
- local “target known / target unknown” status

This state is **not architectural state**.

It is provisional front-end formation state.

It must be fully squashable.

It must not leak into later stages as truth unless it becomes a valid decode payload.

---

## Decode payload intent

The decode payload should be compact and instruction-local.

It should contain enough information for the control stage to decide what to do next without forcing decoder to become a control-policy engine.

Conceptually, the payload should contain:

- `entry_id`
- `opcode_eip`
- `next_eip`
- `target_eip` when directly known
- `control_kind`
- `target_known`
- relevant prefix/class/mode bits
- `epoch`
- `valid`

This payload is the authoritative result of decoder work.

It is not the same thing as a fetch hint.
It is not the same thing as architectural commit.
It is the first authoritative instruction-local packet.

---

## Narrow control-transfer role

Decoder may form control-transfer facts.
It does not own control-transfer policy.

Decoder may determine facts such as:

- this instruction is a control-transfer form
- this is the fall-through EIP
- this is the directly known target EIP
- this target is not yet known from instruction-local bytes alone

Decoder must not determine:

- whether the front end must continue or stop
- whether redirect is architecturally accepted
- whether the old stream is dead
- whether control should serialize upstream stages
- whether commit should redirect architectural state

Those remain downstream responsibilities.

---

## CALL and JMP from decoder’s point of view

From decoder’s point of view, `JMP` and `CALL` are both control-transfer instruction forms.

Decoder’s job is to form the instruction-local facts relevant to them.

For a directly resolvable control transfer, decoder may provide:

- `next_eip`
- `target_eip`
- `control_kind`
- `target_known = 1`

For a control transfer whose target is not instruction-local, decoder may provide:

- `next_eip`
- `control_kind`
- `target_known = 0`

Decoder does not decide what the machine does with those facts.

That is why decoder can remain narrow even as control-transfer complexity grows later.

---

## Relationship to microsequencer

Microsequencer remains the owner of control acceptance and control policy.

Decoder’s job ends at authoritative decode-payload formation and transfer.

Once a decode payload transfers downstream:

- decoder no longer owns policy for that instruction
- decoder no longer owns whether fetch continues
- decoder no longer owns whether redirect occurs
- decoder no longer owns whether control serializes the front end

Decoder provides the facts.
Microsequencer decides how the machine uses them.

This boundary must remain explicit.

---

## Relationship to commit / redirect

Commit remains the architectural visibility boundary.

Decoder-local work is never architectural truth.

Decoder payloads and instruction formation state are provisional front-end state until used downstream and ultimately reflected through control and commit.

When redirect commits:

- decoder-local work from older epochs becomes stale
- stale in-flight decoder state must be squashed
- stale decode payloads must not be consumed further

This preserves the distinction between:

- instruction-local formation truth
and
- architectural machine truth

---

## Epoch / freshness in decoder

Decoder-stage work must participate in epoch/freshness rules.

Each instruction in formation and each decode payload belongs to an epoch.

When redirect commits:

- the current epoch advances
- older decoder-local work becomes stale
- stale in-flight formation state must be invalidated
- stale decode payloads must not transfer further

This prevents wrong-path or abandoned decode work from leaking into control.

---

## Hold versus squash in decoder

These two concepts must remain distinct.

### Hold / stall
A held decode payload is still valid.
Decoder is waiting because downstream is not ready.

A held instruction-in-formation state is also still valid if no squash has occurred and no stale-epoch condition exists.

### Squash
A squashed decoder state or payload is invalid.
It belongs to abandoned or stale work that must not continue.

Confusing hold and squash causes stale-decode bugs.

---

## Decoder must stay small

Decoder must remain narrow by design.

That means decoder should not gradually absorb:

- redirect policy
- commit policy
- service-routing policy
- recovery policy
- later-stage execution policy
- “temporary” bug-fix behaviors that make decoder a hidden controller

When a bug appears at a stage boundary, the preferred fix is to strengthen the boundary contract, not to silently widen decoder ownership.

This is one of the main reasons for this note.

---

## What decoder must not do

Decoder must not become:

- a hidden microsequencer
- a hidden commit engine
- a hidden fetch controller
- a giant semantic execution block

Specifically, decoder must not own:

- architectural redirect truth
- fetch-stream kill/continue authority
- execution sequencing
- service dispatch policy
- architectural fault/commit behavior
- non-local operand resolution as a substitute for later stages

Decoder may know many instruction-local facts.
It must not become the owner of what the machine does with them.

---

## Scalability value

A properly defined decoder stage helps the machine scale later.

By keeping decoder narrow and authoritative only over instruction-local facts, the design preserves:

- a small decoder
- tight coupling to microsequencer without ownership drift
- clear stage boundaries
- the ability to add more stages later if needed
- the ability to grow control complexity without turning decoder into a semantic catch-all

The stable thing is the **decoder contract**, not the exact internal implementation depth.

---

## Summary

Decoder is the owner of **instruction formation**.

Decoder:

- consumes proven-position bytes from fetch
- gathers only the bytes needed for the current instruction
- forms a compact registered decode payload
- presents authoritative instruction-local facts
- obeys valid/ready/hold/bubble/squash discipline
- participates in epoch/freshness rules
- remains narrow by design
- does not become the control-policy owner
- does not become the architectural truth owner

Decoder is not a hidden controller.

Decoder is the stage where the byte stream becomes one authoritative instruction-local packet.