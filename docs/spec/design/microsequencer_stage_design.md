# Keystone86 / Aegis — Microsequencer Stage Design

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to clarify the intended role, boundaries, and behavior of the **microsequencer stage** within the staged Keystone86 machine.

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

This note only defines the behavior of **microsequencer** within that existing structure.

---

## Purpose

The microsequencer stage exists to accept an authoritative decode payload, select the correct microcode entry flow, and own control policy for the currently active instruction.

Microsequencer is not the owner of byte-stream formation.

Microsequencer is not the owner of instruction-local fact discovery.

Microsequencer is not the owner of architectural commit visibility.

Microsequencer is the owner of:

- decode-payload acceptance
- microcode entry selection and sequencing
- current instruction control context
- control-transfer policy
- upstream hold / advance decisions at the control boundary
- downstream control intent presented toward commit/service paths

The purpose of this note is to define:

- who microsequencer is
- what microsequencer owns
- when microsequencer may accept and advance control work
- why microsequencer is intentionally narrow and central
- how microsequencer interacts with decoder upstream and commit downstream

---

## Core design statement

Microsequencer is the stage where an authoritative decode payload becomes the **current control packet** for the machine.

Decoder forms facts.

Microsequencer accepts those facts and decides what control flow to enter.

Microsequencer does not redefine the instruction.
Microsequencer decides how the machine sequences that instruction.

Microsequencer is therefore the center of staged control ownership:

- it accepts one decode payload
- it maps that payload into microcode entry flow
- it sequences control steps
- it decides when upstream may continue, hold, or retarget
- it presents control intent toward commit and service paths

Microsequencer owns **control policy**, not **architectural truth**.

---

## Who

Microsequencer owns:

- acceptance of the decode payload as the current instruction under control
- dispatch-table / microcode entry selection from decode facts
- sequencing through the active microcode flow
- ownership of the current control context
- control-transfer policy
- upstream hold/backpressure at the decode boundary
- issue of control intent toward commit and service paths
- local microcode sequencing state
- current control packet validity

Microsequencer does **not** own:

- byte gathering
- instruction-local field discovery
- authoritative fetch payload formation
- architectural commit visibility
- final redirect truth
- memory-side bus ownership by itself
- actual architectural state commitment
- permanent retention of stale work across squash/epoch

Microsequencer is the owner of **control sequencing**, not **architectural finality**.

---

## What

Microsequencer operates on:

- a registered decode payload from decoder
- local dispatch / sequencing state
- a registered control context for the current instruction
- control outputs directed toward commit and service paths

### Accepted control packet
The most important concept in this stage is the **accepted control packet**.

A decode payload becomes an accepted control packet when:

- the decode payload is valid
- microsequencer is ready
- a transfer occurs at the decode-to-microsequencer boundary

At that point, the payload is no longer just a decoder result.
It is now the current instruction under control ownership.

Conceptually, the accepted control packet contains:

- entry identifier
- opcode EIP
- fall-through EIP
- target EIP when directly known
- control kind
- target-known indication
- relevant class/prefix/mode bits
- epoch / freshness identity

### Sequencing state
Microsequencer may hold local state such as:

- current micro-PC
- current dispatch entry
- active control packet fields
- wait / hold / service substate
- local pending control conditions
- local “instruction active” indication

This state is real control state, but it is still pre-architectural.
It is not the same thing as committed machine state.

---

## When

Microsequencer acts when it has an authoritative decode payload or an already-active control packet to sequence.

Microsequencer may accept a new decode payload when:

- the decode payload is valid
- microsequencer is ready to take ownership of a new instruction
- no older active control packet prevents acceptance
- epoch/freshness says the payload is current

Microsequencer may advance sequencing when:

- the current control packet is valid
- local sequencing conditions allow the next micro-step
- required downstream conditions are satisfied
- no hold/wait condition blocks progress

Microsequencer must not accept a decode payload merely because it is visible.

Microsequencer must only accept it when the decode-to-control transfer is real.

Microsequencer must pause when:

- it is busy with the current active control packet
- a service/wait condition prevents the next micro-step
- downstream backpressure prevents advancing control intent
- squash/epoch invalidates the current packet
- the next fetch-stream consequence is not yet legitimately known

Microsequencer moves when it has a truthful current control packet and permission to advance.

---

## Why

Microsequencer exists to keep control centralized and disciplined.

The project is intentionally not adopting ao486’s distributed control organization as the architecture. The frozen intent keeps the microsequencer as the center of the machine.

This means microsequencer should answer the smallest useful set of control questions:

- which entry flow does this instruction use?
- what is the current microcode position?
- may upstream advance?
- is the current control packet a transfer that changes the fetch stream?
- is the next useful stream anchor known yet?
- what control intent must be issued toward commit/service paths?

That narrowness is intentional.

Microsequencer should remain the **control center**, not a giant merged semantics/commit/fetch block.

---

## How

Microsequencer works by accepting one authoritative decode payload and turning it into an active control context.

In normal operation:

- decoder presents a registered decode payload
- microsequencer accepts that payload when the boundary transfer occurs
- the accepted payload becomes the active control packet
- dispatch logic maps entry ID to a microcode entry point
- microsequencer sequences through the active control flow
- microsequencer issues control intent downstream
- microsequencer applies hold/backpressure upstream when needed
- when the active instruction is complete, microsequencer returns to a state where it may accept the next decode payload

Microsequencer is therefore a **control ownership stage**.

It is neither a passive dispatch lookup nor a commit engine.

It is where instruction-local facts become active machine control flow.

---

## Registered payload requirement

Microsequencer must hold a **registered control context** for the currently active instruction.

The accepted control packet must not be treated as an informal set of transient wires whose meaning depends on fragile cycle-by-cycle timing assumptions.

At the decode boundary, microsequencer should either:

- hold no valid accepted control packet
- or hold one stable registered control context until it advances, completes, or is squashed

Likewise, downstream-facing control intent should be treated as registered/owned stage output rather than casual combinational implication.

This makes microsequencer compatible with:

- explicit hold/stall behavior
- explicit wait/service behavior
- explicit squash/freshness handling
- later insertion of new control-adjacent stages if needed

The stable thing is the control-packet contract, not the exact local implementation style.

---

## Microsequencer-stage boundary contract

The decode-to-microsequencer boundary should obey the standard staged contract.

### Valid
Decoder asserts `valid` when it is presenting a meaningful registered decode payload.

### Ready
Microsequencer asserts `ready` when it can accept that payload as the next current instruction.

### Transfer
A payload transfer occurs only when:

- `valid == 1`
- `ready == 1`

### Hold / stall
If:

- `valid == 1`
- `ready == 0`

then decoder must hold its payload stable and microsequencer is explicitly applying backpressure.

### Bubble
If `valid == 0`, there is no meaningful decode payload to accept.
That is a bubble at the control input boundary.

### Squash
A squash invalidates the current control packet and any local microsequencer state that belongs to abandoned or stale work.

---

## Accepted control packet rule

A decode payload is not yet the current instruction merely because decoder has produced it.

It becomes the current instruction only after decode-to-microsequencer transfer.

This distinction is crucial.

### Before transfer
The payload is:

- authoritative as a decoder result
- but not yet owned by the control stage

### After transfer
The payload becomes:

- the accepted control packet
- the current instruction under microsequencer ownership
- the basis for dispatch, sequencing, hold, and control-transfer policy

This is the boundary where instruction-local facts become active control work.

---

## Relationship to decoder

Decoder remains the first authoritative instruction classifier and fact former.

Microsequencer must consume decoder results as facts, not force decoder to become a control-policy stage.

Microsequencer may rely on decoder for:

- entry ID
- instruction-local EIP facts
- control kind
- target-known / target-unknown classification
- prefix/class/mode bits needed by control
- epoch/freshness identity

Microsequencer must not force decoder to decide:

- whether fetch continues
- whether control serializes
- whether redirect is accepted
- whether architectural side effects are visible

Those remain microsequencer or downstream responsibilities.

This boundary must stay clean.

---

## Relationship to fetch

Fetch owns byte-stream following.
Microsequencer does not own fetch-side byte visibility.

However, microsequencer does own the control consequence of an accepted control packet.

That means microsequencer may determine, based on the accepted control packet, whether:

- normal sequential stream following may continue
- upstream should hold because the next useful stream anchor is not yet known
- a known control-transfer consequence justifies retargeting the fetch stream

Microsequencer does **not** become fetch.
It does not own memory request mechanics or byte-stream formation.

But it does own the **control policy** that tells the machine whether continuing the current stream is still correct.

---

## Stream-control policy

From microsequencer’s point of view, the key question is not merely:

- “is this a jump?”
- “is this a call?”

The real systems question is:

**Does the accepted control packet already define the exact next useful stream anchor?**

### If the exact next stream anchor is known
Then microsequencer may permit the machine to move the fetch stream toward that anchor.

This may result in:

- allowing fetch to follow a known direct turn
- issuing retarget-related control intent
- suppressing useless continuation of the abandoned stream

### If the exact next stream anchor is not yet known
Then microsequencer must prevent the machine from continuing blindly down a potentially wrong stream.

In that case, microsequencer may:

- hold upstream progress
- prevent acceptance of additional decode work
- wait until the needed control fact becomes known

This is control policy.
That is why it belongs here.

---

## CALL and JMP from microsequencer’s point of view

From microsequencer’s point of view, `JMP` and `CALL` are both control-transfer forms.

Microsequencer should not primarily care about mnemonic names.
It should care about control properties such as:

- `control_kind`
- `target_known`
- `target_eip`
- `next_eip`
- any additional semantics to be carried downstream

For front-end control purposes:

- a direct `JMP` with known target says the stream anchor changes
- a direct `CALL` with known target also says the stream anchor changes

The difference is not the existence of a new stream.
The difference is the additional architectural meaning that must later be honored downstream, such as return-address semantics.

Microsequencer owns the control-side interpretation of that difference.

---

## Relationship to commit / redirect

Commit remains the architectural visibility boundary.

Microsequencer may decide control policy such as:

- whether an accepted control packet changes the useful stream
- whether upstream must hold
- whether a redirect consequence exists

But microsequencer does not make redirect architecturally true by itself.

That distinction must remain explicit:

- microsequencer owns control acceptance and sequencing
- commit owns architectural visibility

Microsequencer therefore presents **control intent** downstream.
Commit determines when that intent becomes architectural fact.

---

## Relationship to service paths

Microsequencer may interact with service-side or helper-side paths as part of control sequencing.

However:

- service paths do not silently become policy owners
- microsequencer does not offload core control ownership by accident
- helper/service routing remains routing or service participation, not hidden control authority

If implementation drift occurs, the ownership matrix remains the arbiter.

---

## Local sequencing state

Microsequencer may hold local sequencing state for the active instruction, including:

- current micro-PC
- dispatch-pending or dispatch-active state
- wait-for-service conditions
- execution-in-progress state
- pending control substate
- control-transfer progress state

This state is meaningful and necessary.

But it is still **local control state**, not committed architectural state.

It must remain squashable when stale.

It must not be allowed to outlive its epoch truth.

---

## Epoch / freshness in microsequencer

Microsequencer-stage work must participate in epoch/freshness rules.

Each accepted control packet and its local sequencing state belongs to an epoch.

When redirect commits:

- the current epoch advances
- older active control packets become stale if they belong to the abandoned stream
- stale local sequencing state must be invalidated
- stale downstream control intent must not continue as if still current

This prevents wrong-path or abandoned control work from surviving past its legitimacy.

---

## Hold versus squash in microsequencer

These two concepts must remain distinct.

### Hold / stall
A held accepted control packet is still valid.
Microsequencer is waiting because sequencing cannot advance or because upstream must be paused.

### Squash
A squashed control packet or local sequencing state is invalid.
It belongs to stale or abandoned work that must not continue.

Confusing hold and squash causes stale-control bugs.

---

## Microsequencer must stay narrow

Microsequencer is central, but it must still remain narrow in ownership.

That means microsequencer should not gradually absorb:

- byte-stream formation
- decoder-local classification work
- final architectural commit authority
- fetch mechanics
- helper/service ownership
- “temporary” bug-fix logic that silently moves responsibilities from other stages

Microsequencer should remain the place where:

- facts are accepted
- control is sequenced
- policy is applied

It should not become the entire machine collapsed into one block.

---

## What microsequencer must not do

Microsequencer must not become:

- a hidden decoder
- a hidden fetch engine
- a hidden commit engine
- a place where stale work survives because ownership boundaries were blurred

Specifically, microsequencer must not own:

- byte gathering
- instruction-local field discovery as a substitute for decoder
- direct memory-request generation as a substitute for fetch
- final architectural commitment
- architectural redirect truth without commit
- helper/service logic taking over control policy by accident

Microsequencer may be central.
It must not erase the stage boundaries around it.

---

## Scalability value

A properly defined microsequencer stage helps the machine scale later.

By keeping microsequencer narrow and central, the design preserves:

- a small decoder
- explicit control ownership
- a clean commit boundary
- the ability to add more stages later if needed
- the ability to grow microcode/control complexity without making every other stage semantically heavier

The stable thing is the **microsequencer contract**, not the exact microcode implementation details.

---

## Summary

Microsequencer is the owner of **accepted control and sequencing**.

Microsequencer:

- accepts authoritative decode payloads
- turns them into the current control packet
- selects dispatch / microcode entry flow
- sequences the active instruction
- applies upstream hold/backpressure when needed
- owns control-transfer policy
- presents control intent downstream
- obeys valid/ready/hold/bubble/squash discipline
- participates in epoch/freshness rules
- remains central but narrow
- does not become fetch, decoder, or commit

Microsequencer is not a hidden catch-all block.

Microsequencer is the stage where an authoritative decode payload becomes active machine control flow.