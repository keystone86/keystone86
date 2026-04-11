# Keystone86 / Aegis Bootstrap Repository
# Review Report
## Reviewer: Claude (acting under reviewer brief from project owner)
## Source: keystone86_bootstrap_v15.zip
## Date: Review pass against full spec package

---

## Executive Summary

The bootstrap repository scaffold is structurally sound and architecturally
aligned with the frozen spec. The directory layout, governance structure,
frozen spec placement, and smoke check infrastructure are all correct in
intent and largely correct in detail.

Three issues required correction before the package was implementation-ready:
one critical (dispatch table corruption), one major (truncated RTL package),
and one major (incomplete microsequencer state model). All three have been
corrected in the reviewed deliverable.

After corrections, all five smoke checks pass and the bootstrap ROM
consistency check passes.

---

## Alignment Verdict

| Concern | Status |
|---------|--------|
| Follows master design statement | YES |
| Follows z8086 structural philosophy | YES |
| Follows ao486 semantic-donor direction | YES |
| Follows frozen Appendix A field dictionary | YES (after corrections) |
| Follows Appendix B ownership matrix | YES |
| Follows Appendix C assembler spec structure | YES |
| Follows Appendix D bring-up ladder | YES |
| Constitutional files present and correct | YES |
| Microcode authority model intact | YES |
| Decoder-as-classifier model intact | YES |
| Service-as-leaf model intact | YES |
| Pending commit / ENDI authority intact | YES |
| Anti-drift guardrails present | YES |

---

## Issues Found

### CRITICAL

**ISSUE-001: dispatch.hex entries 0x12 and 0x13 were swapped**

File: `microcode/build/dispatch.hex`

ENTRY_PREFIX_ONLY (0x12) mapped to uPC 0x010 (ENTRY_NULL's address).
ENTRY_NOP_XCHG_AX (0x13) mapped to uPC 0x030 (ENTRY_PREFIX_ONLY's address).
ENTRY_RESET (0xFF) mapped to uPC 0x010 (ENTRY_NULL's address) instead of 0x040.

This would cause the very first simulation run to dispatch NOP incorrectly
and produce confusing failures. It would also make ENTRY_RESET unreachable.

Root cause: The dispatch table was generated with an off-by-one or
swap error in the bootstrap seed generation step.

**Fixed.** Dispatch table now correctly maps:
- ENTRY_NULL (0x00) → 0x010
- ENTRY_PREFIX_ONLY (0x12) → 0x030
- ENTRY_NOP_XCHG_AX (0x13) → 0x020
- ENTRY_RESET (0xFF) → 0x040
- All others → 0x010 (ENTRY_NULL bootstrap fallback)

---

### MAJOR

**ISSUE-002: keystone86_pkg.sv was a severely truncated stub**

File: `rtl/include/keystone86_pkg.sv`

The file contained only 4 of 20+ entry IDs, 3 of 60+ service IDs,
and 3 of 14 fault codes. All other sections (commit masks, stage selectors,
register namespace, conditions, microsequencer states) were completely absent.

This would cause RTL compile failures for any module importing the package.
It also created a namespace mismatch between RTL and microcode includes,
violating the single-source-of-truth principle the codegen infrastructure
was designed to enforce.

Root cause: The package was a placeholder that was never expanded to match
the full Appendix A definition.

**Fixed.** The package now contains the complete set from Appendix A:
all entry IDs, all phase-1 service IDs, all phase-2/3 service IDs with
phase markers, all fault codes, commit mask bits and combined masks,
stage field selectors, register namespace, condition codes, and
microsequencer states (all four: FETCH_DECODE, EXECUTE, WAIT_SERVICE,
FAULT_HOLD).

---

**ISSUE-003: Microsequencer bootstrap seed missing WAIT_SERVICE and FAULT_HOLD states**

File: `tools/spec_codegen/microseq_bootstrap_seed.json`

The seed declared only FETCH_DECODE and EXECUTE states. The spec defines
four states including WAIT_SERVICE (stalled on SVCW) and FAULT_HOLD (fault
staged, awaiting microcode decision). These states are architecturally
required even in bootstrap phase — WAIT_SERVICE is needed as soon as any
wait-capable service is invoked.

Root cause: The seed was created with only the happy-path states and
not updated when the full state machine was defined in the design spec.

**Fixed.** All four states are now declared with documentation of their
transitions and purpose. Also propagated to keystone86_pkg.sv as
MSEQ_FETCH_DECODE, MSEQ_EXECUTE, MSEQ_WAIT_SERVICE, MSEQ_FAULT_HOLD.

---

### MINOR

**ISSUE-004: sub_fault_handler.uasm did not document its bootstrap limitation**

File: `microcode/src/shared/sub_fault_handler.uasm`

The stub correctly issues ENDI CM_FAULT_END as a safe landing, but did
not explain that the full delivery path (EXTRACT vector + SVCW INT_ENTER)
cannot be implemented until Rung 5 of the bring-up ladder when INT_ENTER
is available.

**Fixed.** Added explicit TODO(rung5) comment with the full delivery
sequence, making the bootstrap limitation visible and actionable.

---

**ISSUE-005: ucode.lst and ucode.hex were inconsistent with each other**

Files: `microcode/build/ucode.lst`, `microcode/build/ucode.hex`

The listing showed encoding in a slightly different format than the hex file,
and neither clearly documented the placeholder encoding scheme.

**Fixed.** Both files now use consistent 8-digit hex word format.
BOOTSTRAP_ROM_LAYOUT.md updated with a clear encoding table explaining
what each placeholder word means.

---

### CLEANUP

**ISSUE-006: Bootstrap status dashboard references WAIT_SERVICE state indirectly**

The dashboard and bring-up docs did not call out WAIT_SERVICE as a gate
criterion for Rung 4 (JMP) since JMP does not require a wait-capable service.
However, WAIT_SERVICE first becomes required at Rung 5 (INT) via INT_ENTER.
No change needed to the rung docs — this is correctly staged.

**ISSUE-007: decode_dispatch_smoke.py overstates what is checked**

The script checks symbolic mapping from a seed file, not actual hardware
decode behavior. The smoke checks are correctly labeled as host-side
bootstrap checks in the bringup docs but the script output message says
"passed" without qualification. This is acceptable for scaffold phase but
should be made explicit in Rung 1 gate criteria documentation.

No code change made — this is a documentation improvement for later.

---

## Specific Answers to Reviewer Questions

**Does the scaffold follow the guardrails?**
Yes. Microcode owns instruction policy. Decoder is classifier only.
Services are leaf contracts. Commit is ENDI-gated. No drift visible.

**Does it follow the master design statement?**
Yes. z8086 structure, ao486 semantics, microcode authority, service
subordination, pending-commit model — all intact.

**Does it follow the z8086 structural philosophy?**
Yes. Decoder → dispatch table → microsequencer → explicit routines.
No distributed control. ROM-first default. Hardware-leaf-only services.

**Does it follow ao486 semantic-donor direction?**
Yes. No ao486 RTL was imported. The spec translation recipe is present.
The semantic corpus is referenced, not copied.

**Are any generated files inconsistent with the frozen spec?**
Three were (dispatch.hex, keystone86_pkg.sv, microseq seed). All corrected.

**Are any smoke checks misleading, wrong, or too optimistic?**
The smoke checks are host-side static/logic checks, not RTL simulation.
They are correctly scoped and labeled. The decode_dispatch_smoke could
be more explicit that it checks seed data, not hardware — minor cleanup.

**Is anything in the repo structure likely to cause drift later?**
The main drift risk is the codegen workflow. If appendix_a_codegen.json
diverges from the frozen Appendix A markdown, the RTL includes will
silently go stale. The namespace_check.py script mitigates this but
the codegen tool (gen_from_appendix_a.py) is still a stub. This must
be completed before the codegen workflow becomes reliable.

**What must be fixed before the first real RTL implementation pass?**
The three corrected issues above were the blockers. No remaining blockers.

**What is acceptable as scaffold/placeholder, and what is not?**
Acceptable: placeholder uasm source files for phase-2+ entries, stub
tool implementations, empty .gitkeep directories, placeholder proposals.
Not acceptable: incorrect dispatch tables, truncated shared namespaces,
missing state definitions. Those have been corrected.

**Is the package now a good implementation-start repository seed?**
Yes. With corrections applied, this is a solid implementation-start seed.

---

## Confidence Level

Architecture alignment: HIGH
Namespace consistency: HIGH (after corrections)
Smoke check accuracy: MEDIUM-HIGH (correctly scoped as bootstrap checks)
Implementation readiness: HIGH

---

## Proceed / Hold Recommendation

See: `review/proceed_recommendation.md`
