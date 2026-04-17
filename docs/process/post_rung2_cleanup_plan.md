# Keystone86 / Aegis — Post-Rung-2 Cleanup Plan

## Purpose

This document records cleanup and clarification work that should be addressed **after Rung 2 is passing**.

This is a backlog for a controlled cleanup pass.

It is **not** permission to do cleanup before Rung 2 is stable.

---

## Rule

This cleanup pass must be non-functional and non-architectural.

Do **not** use it to:

- widen rung scope
- begin Rung 3 work
- sneak in future-rung behavior
- mix refactoring with new functionality

All cleanup must preserve passing Rung 0 / Rung 1 / Rung 2 behavior.

---

## 1. Shared constants / package discipline

### Current issue

The project has a package intended to be the authoritative shared constant source, but some RTL still uses legacy include headers and duplicated definitions.

### Goal

Reduce duplicated shared semantic definitions.

Clarify which constants are:

- shared architectural definitions
- legacy compatibility headers
- local/private implementation details

### Desired end state

- one real source of truth for shared architectural constants
- reduced duplication
- local constants remain local only if truly private

---

## 2. Clarify authoritative sources

### Current issue

The repo currently has multiple things that may appear authoritative:

- frozen spec docs
- package/include files
- Python generation scripts
- generated outputs

### Goal

Document what is authoritative for what.

### Desired end state

A new developer can tell clearly:

- what defines architecture
- what defines shared RTL constants
- what is generated
- what is bootstrap scaffolding

---

## 3. Python generation model

### Current issue

The current Python layer acts partly as a bootstrap content author, not purely as a neutral parser/generator.

### Goal

Clarify the intended role of Python generation scripts.

### Review questions

- what is hardcoded intentionally for bootstrap?
- what should eventually come from canonical machine-readable sources?
- what duplication exists between Python and RTL/shared definitions?

### Desired end state

The repo clearly distinguishes:

- bootstrap generation
- intended future source flow
- generated outputs

---

## 4. RTL structure / file layout

### Current issue

Early-rung stubs/placeholders and overlapping semantic locations are accumulating.

### Goal

Review whether file/folder structure still reflects architectural ownership cleanly.

### Constraint

Do not reorganize for aesthetics only.

Any structural cleanup must preserve ownership boundaries and improve clarity.

---

## 5. Bring-up artifact labeling

### Current issue

Some files are bootstrap-only or rung-specific, but this is not always obvious from structure alone.

### Goal

Label or document which files are:

- bootstrap-only
- rung-specific scaffolding
- intended long-term architectural sources
- generated artifacts

---

## 6. README update

### Current issue

Project-facing documentation may lag the real implemented milestone state.

### Goal

After Rung 2 passes, update the README to reflect the current actual project baseline.

---

## 7. Usage / build-flow clarification

### Current issue

Current usage is knowable, but spread across multiple notes and verification docs.

### Goal

Add or improve one concise usage note covering:

- current milestone commands
- generated artifacts
- regression entry points
- what defines the current healthy baseline

---

## 8. Debug instrumentation cleanup

### Current issue

Bring-up often requires temporary heavy instrumentation.

### Goal

After Rung 2 stabilizes, classify current instrumentation into:

- permanent useful observability
- optional trace under flags
- temporary logging to remove

---

## 9. Phase / rung boundary clarity

### Current issue

The repo already contains future-facing constants/placeholders, which can blur “defined” vs “implemented”.

### Goal

Clarify:

- defined because the frozen spec names it
- reserved for later phase/rung
- implemented in live RTL now

---

## 10. Cleanup execution order

Recommended order after Rung 2 passes:

### Pass 1 — documentation/clarity only
- README
- source-of-truth clarification
- usage/build-flow note
- bring-up artifact labeling

### Pass 2 — shared-definition cleanup
- package/include audit
- reduce duplicated semantic definitions
- preserve behavior

### Pass 3 — debug cleanup
- retain useful observability
- gate verbose trace
- remove temporary noise

### Pass 4 — file/layout cleanup
- only if still justified
- only where ownership clarity improves

---

## Summary

This cleanup plan exists to:

- reduce source-of-truth ambiguity
- preserve ownership clarity
- make later rungs safer to implement
- keep the project understandable as complexity grows

It begins only after Rung 2 is functionally proven.