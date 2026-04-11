# Keystone86

**Keystone86** is a microcoded x86 CPU project aimed at **80486-class architectural compatibility** using a control-first design philosophy.

This project follows:

- **z8086 for structure**
- **ao486 for semantic donor behavior**
- **microcode as the authority**
- **explicit service ABI and pending-commit execution**
- **strict architectural guardrails to prevent drift**

Current internal generation: **Aegis**

---

## Current Status

This repository is the **reviewed bootstrap baseline** for Keystone86/Aegis.

It is **not** a finished CPU core yet.

What is present now:

- frozen constitutional spec imported into the repo
- reviewed repository structure and governance
- namespace/codegen scaffolding aligned to Appendix A
- bootstrap microcode ROM/dispatch seed
- bootstrap smoke checks for:
  - decode/dispatch
  - microsequencer path
  - commit/ENDI behavior
  - service ABI rules
  - prefetch/decode contract
- CI and release/versioning scaffolding
- reviewed corrected baseline after independent consistency pass

What is **not** present yet:

- a complete working RTL implementation
- full decoder RTL
- full microsequencer RTL
- full commit engine RTL
- instruction-complete execution
- full simulation or compliance proof
- protected-mode or paging implementation

This repo should be understood as the **implementation-start seed**, not as a completed processor.

---

## Project Direction

Keystone86 is intended to be:

- **microcoded**
- **modular**
- **small and understandable**
- **guardrail-driven**
- **friendly to later hardware acceleration below stable service boundaries**

The project is **not** trying to reproduce Intel’s internal 80486 microarchitecture, and it is **not** trying to preserve ao486’s pipeline-centric organization.

Instead, it is building a new machine with:

- decoder as classifier/dispatcher
- microsequencer as control center
- explicit entry routines
- shared service helpers
- pending architectural commit through `ENDI`

---

## Repository Role

This repository currently serves five purposes:

1. preserve the **constitutional architecture documents**
2. provide a disciplined **implementation layout**
3. provide a **bootstrap microcode/control seed**
4. provide **early smoke checks** for critical architectural contracts
5. provide a clean baseline for **Rung 0 RTL implementation**

---

## Frozen Constitutional Spec

The project constitution lives in:

    docs/spec/frozen/

That directory contains:

- `master_design_statement.md`
- `appendix_a_field_dictionary.md`
- `appendix_b_ownership_matrix.md`
- `appendix_c_assembler_spec.md`
- `appendix_d_bringup_ladder.md`
- `verification_plan.md`

These files are the architectural source of truth.

Supporting files:

- `IMPORT_MANIFEST.md`
- `STATUS.md`

Changes to frozen constitutional files require explicit architecture review.

---

## Repository Layout

Key areas:

    docs/         architecture, implementation notes, governance, legal/provenance
    rtl/          core RTL, includes, and experimental RTL
    microcode/    microcode source, build artifacts, tools, exports
    sim/          smoke checks, vectors, and future simulation harnesses
    formal/       formal-property placeholder area
    tools/        code generation and spec-derived tooling
    scripts/      repo task scripts and bootstrap checks
    review/       optional preserved review artifacts
    .github/      CI workflows

Important policy split:

- **Frozen / guarded**:
  - `docs/spec/frozen/`
  - `rtl/core/`
  - `rtl/include/`
  - `microcode/src/`

- **Flexible / exploratory**:
  - `docs/spec/working/`
  - `rtl/experimental/`
  - `proposals/`
  - `experiments/`

---

## Bootstrap Checks

The current repository includes bootstrap-level smoke checks.

Useful commands:

    make spec-check
    make frozen-manifest-check
    make namespace-check
    make spec-sync-status
    make codegen
    make ucode
    make ucode-bootstrap-check
    make decode-dispatch-smoke
    make microseq-smoke
    make commit-smoke
    make service-abi-smoke
    make prefetch-decode-smoke
    make bootstrap-report
    make version-status

These checks validate **repository alignment and bootstrap control assumptions**.

They do **not** yet constitute full RTL execution proof.

---

## Bring-Up Plan

Implementation is expected to follow the frozen bring-up order in:

    docs/spec/frozen/appendix_d_bringup_ladder.md

The immediate next step is **Rung 0 RTL work**, centered on:

- `cpu_top`
- `prefetch_queue`
- decoder stub
- `microsequencer`
- `microcode_rom`
- `commit_engine`
- `bus_interface`

Do not skip ahead casually.

---

## Guardrails

This project depends on keeping architectural ownership clear.

Core guardrails include:

- microcode owns instruction meaning
- decoder owns classification and entry selection only
- services are subordinate mechanisms, not instruction engines
- architectural visibility occurs only through pending commit and `ENDI`
- hardware may accelerate mechanisms, but must not take over policy
- do not drift into ao486-style distributed pipeline control

See:

- `docs/spec/frozen/master_design_statement.md`
- `docs/spec/frozen/appendix_b_ownership_matrix.md`

---

## Reviewed Baseline

This repository baseline was independently reviewed and corrected before being adopted as the implementation-start seed.

The review found and corrected bootstrap inconsistencies including:

- dispatch-table mapping errors
- incomplete package namespace export
- incomplete microsequencer seed-state declaration

The corrected reviewed baseline is the one that should be used going forward.

If review artifacts are preserved in this repo, see:

    review/

---

## Naming and Versioning

Public project name:

- **Keystone86**

Current internal generation:

- **Aegis**

Recommended tagging form:

- `Aegis-v0.1.0-bootstrap-reviewed`

This repository should currently be treated as the **Aegis reviewed bootstrap baseline**.

---

## Licensing

This project should be licensed as a mixed package, with licensing finalized at the repository level.

Recommended model:

- hardware/core design: CERN-OHL-W-2.0
- tools/scripts/utilities: Apache-2.0
- prose documentation: CC-BY-4.0 or Apache-2.0

Keep provenance and third-party notes clear.

---

## Contributing

Before contributing, read:

- `CONTRIBUTING.md`
- `GOVERNANCE.md`
- `DCO.md`

Contributions are welcome, but contributors must preserve the architecture and guardrails.

Architecture-changing work should begin as a proposal before touching frozen constitutional files.

---

## Practical Warning

Do not mistake scaffold maturity for implementation completeness.

This repository is **well-prepared to begin implementation**.

It is **not yet the implementation itself**.

That distinction matters.

---

## Near-Term Goals

Near-term goals for Aegis:

- complete Rung 0 RTL implementation
- validate the reset/fetch/decode loop in RTL
- connect bootstrap ROM and dispatch path
- begin Rung 1 NOP/dispatch sanity in actual simulation
- preserve alignment between frozen spec, codegen outputs, and implementation

---

## Summary

Keystone86 is now at the point where:

- the architecture is defined
- the guardrails are explicit
- the repo structure is disciplined
- the baseline has been reviewed
- implementation can begin from a clean foundation

The next milestone is not more scaffolding.

The next milestone is **real Rung 0 RTL execution work**.