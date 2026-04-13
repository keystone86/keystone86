# Keystone86 / Aegis — Front-End Payloads

## Status

Design-support note.

This document is subordinate to the frozen project specification.

It does not replace or override the project constitution in `docs/spec/frozen/`. It exists to define the conceptual **payloads** used at front-end stage boundaries so that fetch, decoder, and microsequencer can communicate through explicit, narrow, stable contracts.

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

This note only defines the **payload contracts** that pass between those owners.

---

## Purpose

The purpose of this document is to answer one narrow question:

> What information is allowed to move between front-end stages, and in what conceptual form?

The payloads defined here are intentionally:

- narrow
- stage-local
- ownership-preserving
- stable in meaning even if implementation details change later

This note does **not** define full RTL signal lists.

It defines the conceptual payloads that support:

- explicit stage boundaries
- valid/ready handoff
- hold/stall behavior
- bubble behavior
- squash behavior
- epoch/freshness handling
- later insertion of additional stages if needed

---

## Core design statement

Each front-end stage boundary should carry a **registered payload**.

A stage boundary should not be treated as a loose bundle of wires whose meaning depends on timing assumptions or unstated ownership.

Each payload should answer a small, stage-appropriate question.

Examples:

- fetch payload: “what byte is currently visible?”
- decode payload: “what instruction-local facts have been formed?”
- accepted control packet: “what instruction is now under control ownership?”

The stable thing is the **payload meaning**, not the exact internal implementation.

---

## Payload design rules

All front-end payloads should follow these rules.

### 1. Payloads are narrow
A payload should carry only the information the downstream stage genuinely needs.

### 2. Payloads preserve ownership
A payload may carry facts from one stage to another.
It must not silently transfer ownership of policy.

### 3. Payloads are registered
A payload must be stable while valid and held.

### 4. Payloads are freshness-aware
A payload must carry enough identity to know whether it belongs to the current epoch.

### 5. Payloads are squashable
A payload is provisional until it reaches the appropriate architectural boundary.

### 6. Payload meaning is more important than signal naming
Exact signal names may vary.
The conceptual contents and ownership rules must remain stable.

---

## Common payload fields

Not every payload must contain all of these fields, but these are the main conceptual field classes used in the front end.

### Validity fields
Used to determine whether the payload is meaningful.

Examples:
- `valid`
- `epoch`

### Position fields
Used to locate work within the instruction stream.

Examples:
- byte EIP / byte position
- opcode EIP
- fall-through EIP
- target EIP

### Classification fields
Used to identify what kind of work the payload represents.

Examples:
- entry ID
- control kind
- prefix/class bits
- target-known indication

### Value fields
Used to carry actual content.

Examples:
- current byte
- target address
- next EIP
- mode/class context needed by the next stage

---

## Fetch payload

### Purpose
The fetch payload answers:

> What byte is currently visible in the useful byte stream?

### Ownership
Owned by fetch.

Consumed by decoder.

Fetch remains the owner of byte-stream following and stream-anchor behavior.

### Conceptual contents
A fetch payload should conceptually contain:

- `valid`  
  Whether the payload is presenting a meaningful byte.

- `byte`  
  The currently visible byte value.

- `byte_eip`  
  The byte position / EIP associated with this byte.

- `epoch`  
  Freshness identity for this byte stream element.

- optional narrow fetch-local metadata  
  Only if needed and only if it does not transfer semantic authority.

### What it means
A valid fetch payload means:

- this byte is meaningful
- this byte belongs to the current visible stream
- this byte is associated with this byte position
- this byte belongs to this epoch

### What it does not mean
A fetch payload does **not** mean:

- the instruction is decoded
- the byte is automatically the next correct byte for the current instruction
- a control transfer is architecturally accepted
- redirect has become true

Decoder must still decide whether the fetch payload byte is the expected byte for the current instruction in formation.

---

## Decoder-local formation state

This is not an inter-stage payload, but it is important to name it so it is not confused with one.

### Purpose
Decoder-local formation state answers:

> What partial instruction is currently being assembled?

### Ownership
Owned only by decoder.

Not transferred directly as an architectural truth packet.

### Conceptual contents
May include:

- opcode byte
- opcode EIP
- prefix accumulation
- displacement bytes
- immediate bytes
- partial length/class information
- local target-known / target-unknown status
- epoch

### What it means
This state is provisional local formation state.

It is neither:

- a fetch payload
- nor yet a transferable decode payload
- nor architectural truth

### Why name it here
Naming it here prevents confusion between:

- local formation state
- transferable stage payloads
- committed architectural state

---

## Decode payload

### Purpose
The decode payload answers:

> What authoritative instruction-local facts have been formed for the current instruction?

### Ownership
Owned by decoder.

Consumed by microsequencer.

Decoder remains the owner of instruction formation and instruction-local facts.

### Conceptual contents
A decode payload should conceptually contain:

- `valid`  
  Whether the payload is presenting a meaningful decode result.

- `entry_id`  
  The dispatch/entry-table identifier for this instruction family.

- `opcode_eip`  
  The EIP/position of the opcode byte.

- `next_eip`  
  The fall-through / instruction-end EIP.

- `target_eip`  
  The directly known target EIP when applicable.

- `control_kind`  
  The control-transfer class or equivalent narrow control classification.

- `target_known`  
  Whether the exact next stream target is already known from instruction-local facts.

- relevant prefix/class/mode bits  
  Only those needed by the control stage.

- `epoch`  
  Freshness identity for the payload.

### What it means
A valid decode payload means:

- decoder has formed one authoritative instruction-local result
- the fields are stable
- the payload is ready for control-stage acceptance

### What it does not mean
A decode payload does **not** mean:

- the instruction is yet the active control packet
- control has accepted it
- redirect is architecturally true
- commit has made anything visible

That happens only after the next stage accepts it.

---

## Accepted control packet

### Purpose
The accepted control packet answers:

> Which instruction is currently under control ownership?

### Ownership
Owned by microsequencer after transfer from decoder.

This is the decode payload after it crosses the decoder-to-microsequencer boundary.

### Conceptual contents
The accepted control packet should conceptually contain:

- all decode-payload facts required by control
- current entry ID
- current opcode EIP
- current next EIP
- current target EIP when known
- control kind
- target-known indication
- relevant mode/class bits
- epoch
- local control-valid ownership

### What it means
An accepted control packet means:

- microsequencer has accepted this instruction as the current instruction under control
- control policy may now be applied to it
- dispatch/sequence ownership is active

### What it does not mean
An accepted control packet does **not** yet mean:

- architectural visibility has changed
- redirect has become architecturally true
- commit has applied state updates

That remains downstream.

---

## Commit intent payload

This note is focused on the front end, but it is useful to name the next conceptual payload so the boundary remains clean.

### Purpose
The commit intent payload answers:

> What control consequence is now ready to become architecturally visible?

### Ownership
Produced by control-side sequencing.

Consumed by commit.

### Conceptual contents
May include:

- architectural EIP update intent
- redirect/flush intent
- fault-visible intent
- state-update intent routed through commit
- epoch-relevant visibility intent

### What it means
This is no longer just instruction-local fact.
It is intent to change visible machine state.

### Why include it here
Only to keep the stage chain conceptually complete:

- fetch payload
- decode payload
- accepted control packet
- commit intent payload

This note does not attempt to fully define commit internals.

---

## Payload transfer model

Every transferable payload should obey the same staged rule:

### Valid
The upstream stage asserts that the payload is meaningful.

### Ready
The downstream stage asserts that it can accept the payload.

### Transfer
The payload transfers only when:

- `valid == 1`
- `ready == 1`

### Hold
If:

- `valid == 1`
- `ready == 0`

then the payload must remain stable.

### Bubble
If `valid == 0`, there is no meaningful payload at that boundary.

### Squash
If squash/freshness invalidates the payload, it must not continue forward as if still current.

---

## Epoch / freshness in payloads

Every transferable front-end payload should carry epoch/freshness identity.

This is required because the machine must distinguish between:

- current-path work
- abandoned stale work

### Epoch rule
When redirect becomes architecturally visible:

- the current epoch advances
- payloads from older epochs become stale
- stale payloads must not continue as if valid

This is why epoch belongs in the payload model, not merely in local implementation notes.

---

## Payloads and ownership boundaries

Payloads carry information.
They do **not** silently transfer ownership.

Examples:

- fetch payload carries byte-stream facts, but does not make decoder redundant
- decode payload carries instruction-local facts, but does not make microsequencer unnecessary
- accepted control packet carries control ownership, but does not make commit unnecessary

This rule is important because many architectural drifts happen when a payload begins carrying facts that are then mistaken for transferred policy ownership.

Payloads must be designed to avoid that confusion.

---

## Payloads must stay narrow

The correct way to fix stage-boundary bugs is not to keep stuffing more and more unrelated fields into every payload.

Payloads should remain narrow and stage-appropriate.

### Good payload growth
- add a field because the next stage truly needs it
- add a field because freshness/identity requires it
- add a field because a contract was previously underspecified

### Bad payload growth
- add a field just to bypass the next stage’s responsibility
- add a field that moves policy into the wrong stage
- add a field that duplicates another stage’s ownership for convenience

This note exists partly to prevent that kind of drift.

---

## Payloads and later stage insertion

One of the reasons to define payloads explicitly is to make later stage insertion possible without changing the meaning of the machine.

If the payload contracts are stable, the implementation may later:

- split stages
- insert buffering
- add intermediate holding stages
- change internal timing structure

without changing the architectural meaning of the stage boundaries.

That is one of the most important long-term benefits of this note.

---

## What this note does not do

This note does **not**:

- define exact RTL ports
- define exact bit widths for every future implementation
- redefine stage ownership
- replace frozen spec
- force a deep pipeline immediately
- make every payload architecturally visible

It only defines the conceptual payloads needed for a clean staged front end.

---

## Summary

The front-end payload model should remain simple and stable:

- **Fetch payload**  
  What byte is currently visible?

- **Decoder-local formation state**  
  What partial instruction is being assembled?

- **Decode payload**  
  What authoritative instruction-local facts have been formed?

- **Accepted control packet**  
  What instruction is currently under control ownership?

- **Commit intent payload**  
  What is now ready to become architecturally visible?

These payloads should remain:

- narrow
- registered
- valid/ready governed
- squashable
- epoch/freshness aware
- ownership-preserving

This is the intended front-end payload discipline going forward.