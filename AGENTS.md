# Keystone86 Codex Instructions

These instructions apply to the entire repository unless a more specific `AGENTS.md`
exists in a subdirectory.

## Primary rule

Codex must follow the repository authority chain exactly.

Do not rely on chat memory, resume context, prior summaries, or inferred intent as
authority. Always read the relevant repository documents before making changes.

## Authority chain

Use this order of authority:

1. Frozen specifications.
2. Active rung file, for example `docs/implementation/bringup/rung3.md`.
3. Source-of-truth and coding-rule documents.
4. Process and acceptance documents.
5. Verification documents.
6. User task prompt.
7. Reviewer comments, correction briefs, chat context, and implementation notes.

If lower-authority guidance conflicts with higher-authority guidance, the
higher-authority guidance wins.

Correction briefs and review comments may identify suspected issues, but they do
not create new rung requirements by inference.

## Protected authority files

Codex may read, quote, and reference these files, but must not edit, rewrite,
rename, delete, move, reformat, or commit changes to them:

- `docs/spec/frozen/**`
- `docs/implementation/coding_rules/**`
- `docs/process/**`
- `docs/implementation/bringup/rung*.md`
- `AGENTS.md`

These files are authority and guardrail documents.

If a protected file appears to need changes, stop and report:

1. the protected file path,
2. the exact change that appears necessary,
3. why the change appears necessary,
4. whether the issue is a conflict, typo, stale acceptance record, or scope question.

Do not modify the protected file unless the user explicitly gives a new instruction
naming the exact protected file and the exact intended change.

## Protected-file bypass prohibition

Codex must not bypass protected-file controls.

Codex must not:

- use `git commit --no-verify`,
- disable, remove, or alter Git hooks,
- change `core.hooksPath`,
- alter CI workflows to permit protected-file edits,
- alter branch protection or repository protection settings,
- use environment variables or command-line flags to bypass protected-file checks,
- add commit-message tags intended to bypass protected-file checks,
- stage protected files for commit unless the user explicitly authorized the exact file and exact change.

If a command would bypass a hook, guardrail, CI check, branch protection rule, or
protected-file policy, do not run it. Stop and report the issue.

## Rung authority and scope control

For any rung work, Codex must read the active rung file before changing RTL,
tests, generated artifacts, or documentation.

The active rung file defines current-rung scope.

Do not expand a rung by inference from architecture, review comments, correction
briefs, chat context, or implementation assumptions.

Do not narrow a rung to make the current implementation pass.

A suspected issue is a current-rung blocker only if it is explicitly required by:

1. frozen specifications, or
2. the active rung file.

Before editing files, classify planned work as one of:

- **Required blocker**: explicitly required by frozen specifications or the active rung file.
- **Required acceptance cleanup**: needed so documentation, source-of-truth records,
  generated artifacts, or verification evidence accurately match actual tested behavior.
- **Out of scope**: useful, plausible, or architecturally desirable, but not explicitly
  required by frozen specifications or the active rung file.

Only required blockers and required acceptance cleanup may be implemented.

Out-of-scope work must not be implemented as part of the current rung.

## Rung progression

Do not start the next rung until the current rung is accepted.

A rung is accepted only when:

- implementation matches the active rung requirements,
- generated artifacts are current and committed if required,
- regression evidence proves the required behavior,
- prior-rung non-regression checks pass,
- documentation matches the actual tested behavior,
- verification records include the exact tested commit state,
- the working tree state is understood and recorded,
- no README, process, source-of-truth, or verification claim exceeds what was tested.

Do not create deviation specs, exception files, deferred-compliance records, or
alternate acceptance criteria.

## Required read order for rung work

Before making changes for a rung, read the relevant files in this order:

1. Relevant frozen specifications under `docs/spec/frozen/`.
2. The active rung file under `docs/implementation/bringup/`.
3. `docs/implementation/coding_rules/source_of_truth.md`, if present.
4. `docs/process/rung_execution_and_acceptance.md`, if present.
5. Existing rung verification documentation, if present.
6. The specific files to be changed.

After reading, restate the current rung scope and planned-change classification
before making edits.

## Architectural ownership

Preserve the intended ownership model unless the active rung file or frozen specs
explicitly say otherwise.

Decoder:

- may collect instruction bytes, immediates, and payload metadata,
- may identify decode entry points,
- must not own final architectural redirect semantics,
- must not directly update architectural EIP/ESP/SP.

Microsequencer:

- may issue service calls,
- may wait for service completion,
- may sequence instruction behavior,
- must not directly commit architectural EIP/ESP/SP outside the commit path.

Service engines:

- may compute pending effects,
- may generate pending writes or results,
- must not expose architectural state early,
- must not bypass commit ownership.

Commit engine:

- owns final architectural visibility,
- owns committed redirect cleanup,
- owns committed stack/register/memory visibility as defined by the current rung.

## Code comments and documentation

Code must be understandable to a human maintainer.

Do not produce clever, opaque, or unexplained RTL, microcode, scripts, or
testbench logic. If behavior is non-obvious, add concise comments explaining
the intent.

Comment the reason for behavior, not obvious syntax.

Add or update comments when changing:

- architectural ownership boundaries,
- microcode-controlled instruction behavior,
- service-call handshakes,
- pending versus committed architectural state,
- ENDI/commit visibility timing,
- stack, redirect, or control-flow sequencing,
- decode metadata assumptions,
- testbench scenario intent and expected architectural results,
- generated-artifact assumptions,
- workaround logic,
- temporary bootstrap behavior,
- intentionally bounded or deferred behavior.

Comments must stay accurate. When code changes, update nearby comments that no
longer describe the actual behavior.

Do not use comments to justify scope creep. If behavior is not required by the
active rung file or frozen specifications, classify it as out of scope instead
of implementing and commenting it.

Documentation must be updated when a change affects an authoritative source
relationship, ownership boundary, generated artifact flow, verification claim,
or rung acceptance status.

When adding new shared fields, enums, service IDs, metadata, ownership rules, or
authoritative-source relationships, update the appropriate documentation first
or stop and report that the change touches protected authority docs.

Do not claim behavior in README, process docs, source-of-truth docs, verification
docs, comments, or handoff text unless the behavior is implemented and verified.

Comments and documentation are part of the deliverable. A change is not complete
if the implementation passes but the surrounding comments or documentation leave
the behavior unclear or misleading.

## Generated artifacts

If a task changes sources that feed generated RTL, packages, ROMs, microcode, or
other generated artifacts, run the appropriate generation command from the
Makefile or project documentation.

Do not invent generation targets.

If generation changes tracked files, include those generated changes in the
review unless the project documentation says they are intentionally untracked.

Do not claim verification from a dirty, stale, or untracked generated state.

## Verification and completion claims

Do not claim a rung is complete until the required regression commands have been
run and the verification documentation has been updated from the actual run.

Use existing Makefile targets and process docs. Do not invent target names.

Record:

- exact commands run,
- pass/fail result,
- tested commit hash,
- whether the working tree was clean before the run,
- whether the working tree was clean after the run or what changed,
- any unresolved blocker.

If verification documentation must be updated after a clean committed test run,
record the tested implementation commit separately from the documentation commit.

## Git behavior

Before making changes, inspect current status:

    git status --short

After making changes, show:

    git status --short
    git diff --stat
    git diff

Do not commit unless the user explicitly asks for a commit.

Do not push unless the user explicitly asks for a push.

Do not force-push.

Do not rewrite history unless the user explicitly asks and the risk is explained.

Do not stage unrelated files.

## Final response requirements

When work is complete or stopped, report:

- files changed,
- files intentionally not changed,
- classification of each change,
- commands run,
- test/regression results,
- generated artifact status,
- protected-file issues, if any,
- unresolved blockers, if any,
- whether the next rung remains blocked.

## If unsure

If Codex is unsure whether something is required by the current rung, do not
implement it by default.

Classify it as a scope question and report it.
