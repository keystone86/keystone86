# Keystone86 / Aegis Bootstrap Repository
# Drift Audit

---

## What Is Now Well Protected

**Microcode authority model**
The frozen spec, ownership matrix (Appendix B), and GOVERNANCE.md
all state explicitly that microcode owns instruction meaning and sequencing.
The directory structure reinforces this: docs/spec/frozen/ is visibly
separate, rtl/core/ is separate from rtl/experimental/, and the proposal
lane exists. No RTL module in the scaffold contains instruction-level logic.
Risk: LOW.

**Decoder-as-classifier model**
The decoder section of Appendix A (Section 8) explicitly freezes the
decoder contract including the official decision that the decoder is a
sequential byte-consuming FSM with combinational classification logic
inside each state. The ownership matrix forbids the decoder from
accessing registers, memory, or architectural state. The review checklist
in docs/implementation/coding_rules/review_checklist.md includes this
as an explicit check. Risk: LOW.

**Service-as-leaf model**
The ownership matrix explicitly states services are leaf functions that
must not call other services and must not own instruction policy.
The service_ids.svh and keystone86_pkg.sv provide the correct service
namespace without any policy encoding. Risk: LOW.

**Commit/ENDI as the only architectural visibility boundary**
The pending-commit model is fully specified in Appendix A Sections 3
and 7. The commit_defs.svh provides correct CM_* constants. The
bootstrap microcode uses CM_NOP and CM_FAULT_END correctly.
Risk: LOW.

**Namespace alignment**
The corrected keystone86_pkg.sv, the svh files, and the microcode
.inc exports now all match Appendix A. The namespace_check.py script
verifies this alignment is present. Risk: LOW-MEDIUM (see below).

**Frozen spec vs working spec separation**
docs/spec/frozen/ is clearly separated from docs/spec/working/.
The IMPORT_MANIFEST.md and STATUS.md make the constitutional status
of the frozen files explicit. Frozen spec cannot be casually changed
by a PR affecting working/ docs. Risk: LOW.

---

## Where Drift Risk Still Exists

**1. Codegen workflow is a stub (MEDIUM risk)**

The appendix_a_codegen.json drives the generated namespace files, but
gen_from_appendix_a.py is not yet a functioning generator. This means:

- A maintainer could update the JSON without updating the frozen Appendix A markdown
- A maintainer could update the frozen Appendix A markdown without updating the JSON
- The generated svh and .inc files could go stale relative to either source

Mitigation already in place: spec_sync_status.py checks that both
sources exist. The IMPORT_MANIFEST records when files were imported.

Mitigation still needed: gen_from_appendix_a.py must be implemented
so that the JSON is the single authoritative input that generates all
output files. Until then, human review of all three layers is required
on any namespace change.

**Gate:** Do not accept any namespace change without running
`make codegen` and verifying the outputs match expectation.

**2. RTL include files are not yet imported by any RTL module (LOW-MEDIUM risk)**

The svh files and keystone86_pkg.sv exist but there is no RTL yet to
import them. When RTL implementation begins, there is a risk that
implementers define local parameters instead of importing the package.

Mitigation: The rtl/include/README (if added) and the coding rules doc
should explicitly state that all RTL modules must use
`import keystone86_pkg::*` and must not define local copies of shared
constants.

**Gate:** First RTL module PR must use keystone86_pkg. Reviewer checklist
should include this check.

**3. Smoke checks test seed data, not RTL (LOW risk at bootstrap, MEDIUM later)**

All five smoke checks are host-side Python scripts checking seed JSON
data and static files. They do not run RTL simulation. This is correct
for the bootstrap phase, but as RTL is implemented there is a risk that
the smoke checks continue to pass even if the RTL diverges from the spec.

Mitigation already in place: The bringup docs note that smoke checks
are host-side only. The verification plan defines L1-L5 layers with RTL
simulation as L1+.

Mitigation still needed: As each rung is completed, the corresponding
smoke check should be supplemented with an RTL testbench that actually
simulates the behavior.

**Gate:** Each completed rung should replace or supplement its smoke check
with a real L1/L2 simulation testbench.

**4. Phase-2/3 entries currently raise #UD silently (ACCEPTABLE risk)**

Phase-2+ entries (ENTRY_JMP_FAR, ENTRY_CALL_FAR, ENTRY_RET_FAR, etc.)
are not yet in the microcode source. Any opcode dispatching to them
would fall through to ENTRY_NULL and raise #UD. This is correct behavior
for bootstrap phase but should be explicitly documented.

Mitigation: The uasm source includes a note at the bottom listing which
entries raise #UD explicitly in phase-1. This is sufficient.

**5. sub_fault_handler is a bootstrap stub (ACCEPTABLE risk, tracked)**

The stub correctly issues ENDI CM_FAULT_END as a safe landing, but does
not deliver the exception via the IVT. This means any fault in bootstrap
phase silently terminates the instruction rather than delivering #UD or
#GP to the running code. This is acceptable for bootstrap phase.

Mitigation: The TODO(rung5) comment makes the expansion requirement
explicit and traceable.

---

## Review Gates That Should Remain in Place During Implementation

**Gate 1: Namespace change review**
Any PR changing Appendix A (frozen spec), appendix_a_codegen.json,
keystone86_pkg.sv, any svh file, or any .inc export must include a
demonstration that all four remain in alignment. Run `make namespace-check`.

**Gate 2: Decoder scope review**
Any PR touching the decoder module must explicitly answer:
- Does this add semantic behavior to the decoder?
- Does this access registers, memory, or architectural state from the decoder?
If yes to either, the PR must be rejected or reworked.

**Gate 3: Service scope review**
Any PR adding or modifying a service module must explicitly answer:
- Does this service call another service internally?
- Does this service own instruction-level policy or sequencing?
- Does this service modify architectural state directly?
If yes to any, the PR must be rejected or reworked.

**Gate 4: Commit bypass review**
Any PR touching the commit_engine must explicitly answer:
- Does any path apply architectural state change outside of ENDI processing?
If yes, the PR must be rejected or reworked.

**Gate 5: Rung completion review**
Any PR claiming rung completion must pass the rung's gate criterion as
defined in Appendix D. The gate criteria are not negotiable.
