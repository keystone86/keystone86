# Keystone86 Codex Workflow

This workflow captures the process that worked during the Rung3 recovery.

## Goal

Use Codex as a controlled implementation agent, not as the project authority.

The working model is:

```text
Repo files + Git history = authority
Codex session memory = convenience only
Docker container = execution boundary
Project-scoped Docker volumes = persistent auth/session convenience
```

Codex may run with broad permissions inside the container, but it must always
re-anchor itself to the repository authority before doing work.

Do not let Codex infer which rung is active. The user must explicitly name the
active rung and, whenever possible, the exact active rung directive file.

---

## 1. Session setup

Start from a clean shell, inside the container:

```sh
make dev
```

Then start Codex:

```sh
codex
```

Codex should show:

```text
model:       gpt-5.5 high
directory:   /work
permissions: YOLO mode
```

If not, check:

```sh
cat ~/.codex/config.toml
```

Expected:

```toml
sandbox_mode = "danger-full-access"
approval_policy = "never"
model_reasoning_effort = "high"

[projects."/work"]
trust_level = "trusted"

[tui.model_availability_nux]
"gpt-5.5" = 4

[plugins."github@openai-curated"]
enabled = true
```

Do not resume an old large Codex session for new rung work unless auditing that
exact prior session.

For new work, start fresh.

---

## 2. Always begin with authority anchoring

First prompt should never be "implement feature" or "explain this codebase."

The user must explicitly identify the active rung. Do not ask Codex to determine
the active rung from repo state, prior session memory, or inference.

Use this bounded review prompt:

```text
Read AGENTS.md first and follow it exactly.

The active rung for this session is Rung<N>.
The active rung directive is:
docs/implementation/bringup/rung<N>.md

Then read the active rung directive, relevant frozen specs, source-of-truth docs, process docs, and current verification docs.

Do not rely on resume context or prior session memory as authority.

Task:
Review Rung<N> only.

Before editing anything:
1. Report which authority files you read.
2. Summarize what Rung<N> explicitly requires.
3. Classify suspected issues as:
   - Required blocker,
   - Required acceptance cleanup,
   - Out of scope.
4. State which files you plan to edit.

Do not edit files yet.
Do not start Rung<N+1>.
Do not expand Rung<N> by inference.
```

This saves usage because Codex does not immediately explore the whole repo or
start implementing inferred work.

It also prevents drift.

---

## 3. Use a two-pass review before edits

If Codex reports blockers, do not authorize implementation immediately.

Use this refinement prompt:

```text
Before editing anything, refine the blocker classification.

For each suspected Required blocker, quote or cite the exact section from AGENTS.md, the active Rung<N> directive, or frozen specs that makes it required now.

If a suspected issue is not explicitly required by the active Rung<N> directive or frozen specs, reclassify it as Required acceptance cleanup or Out of scope.

Do not edit files yet.
Do not start Rung<N+1>.
Do not expand Rung<N> by inference.
```

This step separates real rung blockers from reasonable-but-out-of-scope
architecture work.

---

## 4. Authorize only a bounded implementation

Only after classification is clean, authorize implementation with a narrow scope:

```text
Proceed with only the items classified as Required blockers for Rung<N>.

You are authorized to edit implementation, tests, generated artifacts, and non-protected verification documentation needed to resolve those blockers.

Do not implement Out-of-scope items.
Do not edit protected authority files unless I explicitly authorize the exact file and exact intended change.
Do not create deviation specs, exception files, deferred-compliance records, or alternate acceptance criteria.
Do not start Rung<N+1>.

Before changing files, state the planned implementation approach for each blocker and the files expected to change.

After changes:
1. run required generation commands,
2. run required Rung<N> regression commands,
3. report changed files,
4. report commands run and results,
5. report unresolved blockers,
6. report whether Rung<N+1> remains blocked.
```

This keeps Codex from turning one issue into a subsystem rewrite.

---

## 5. Stop after implementation and review the dirty diff

After Codex implements and tests, stop it before committing.

Use this review prompt:

```text
Stop implementation work.

Do not edit files yet.

Review the current dirty diff against AGENTS.md, the active Rung<N> directive, and frozen specs.

Focus on whether the implementation stayed bounded to Rung<N>:
1. no broad subsystem expansion,
2. no Rung<N+1> implementation,
3. no protected authority files edited,
4. generated artifacts status,
5. verification claims match actual tests.

Report any concerns before I commit.
```

This is where scope-creep concerns should be caught before commit.

---

## 6. Tighten scope before commit

If Codex finds a scope concern, do not accept the implementation yet.

Use a tightening prompt like:

```text
Tighten the current dirty implementation before commit.

Do not broaden Rung<N>.

Limit successful behavior to the verified Rung<N> slice.
For unsupported or unverified forms, fail safely through the existing mechanism.

Do not add broad infrastructure.
Do not edit protected authority files.
Do not start Rung<N+1>.

After tightening, rerun the required generation and Rung<N> regression commands.

Report changed files, results, and whether the implementation is now bounded to the verified Rung<N> slice.
```

This produces higher-quality code because unsupported behavior is explicit instead
of accidental.

---

## 7. Commit implementation yourself

Do commits from the container shell, not inside Codex.

This keeps commits as deliberate human checkpoints.

Example:

```sh
git status --short

git add <implementation files> <test files> <verification doc if updated>

git commit -m "rung<N>: implement bounded active-rung behavior"
```

Then run clean verification from the committed state.

Example:

```sh
make codegen && make ucode && make rung<N-1>-regress && make rung<N>-regress
```

Use the actual required commands from the active rung directive and process docs.
Do not assume these exact target names for every rung.

---

## 8. Update verification as a separate commit

After clean committed verification passes, ask Codex to update only the
verification doc:

```text
Read AGENTS.md first and follow it exactly.

Update only the Rung<N> verification document to record the clean committed verification run.

Use this committed implementation hash:
<hash>

Commands run after commit:
<commands>

Results:
<results>

Record that this was run after committing the implementation.
Check git status before and after.
Do not edit protected files.
Do not start Rung<N+1>.
```

Then commit manually:

```sh
git add docs/implementation/<rung>_verification.md
git commit -m "docs: record committed rung<N> verification"
```

This keeps implementation and verification evidence separate.

---

## 9. Protected docs require a separate review/authorization cycle

Protected docs should not be edited during implementation.

First ask Codex to review only:

```text
Read AGENTS.md first and follow it exactly.

Rung<N> implementation and clean committed verification are now complete.

Task:
Review only the protected acceptance/source-of-truth docs that may be stale after the committed Rung<N> verification.

Do not edit yet.

For each file:
1. Quote or cite the stale text.
2. Explain why it conflicts with the committed Rung<N> verification state.
3. Propose the exact replacement text.
4. Classify the change as Required acceptance cleanup or Out of scope.

Do not start Rung<N+1>.
Do not change RTL, tests, generated artifacts, verification docs, or unlisted docs.
```

Then authorize exact files:

```text
Proceed with the protected acceptance/source-of-truth cleanup exactly as proposed.

You are authorized to edit only:
- <exact file 1>
- <exact file 2>
- <exact file 3>

Do not edit any unlisted file.
Do not edit RTL, tests, generated artifacts, AGENTS.md, frozen specs, or rung files.
Do not start Rung<N+1>.

After edits:
1. Run git status --short.
2. Run git diff --stat.
3. Run git diff for the edited files.
4. Report whether the edits only align docs with the committed Rung<N> verification state.
```

Then commit manually:

```sh
git add <authorized protected docs>
git commit -m "docs: align process docs with accepted rung<N> baseline"
```

---

## 10. Keep sessions small to reduce usage and avoid wait windows

Large all-in-one sessions burn usage quickly.

Use smaller sessions:

```text
Session 1: Review/classify only.
Session 2: Implement required blockers only.
Session 3: Dirty diff scope review.
Session 4: Verification doc update.
Session 5: Protected doc cleanup.
```

After each session:

```text
- Commit durable work.
- Close Codex.
- Start fresh for the next phase.
```

Do not resume a giant session for new work. Resume is useful for auditing, but
fresh sessions are cheaper and cleaner.

---

## 11. Prompts to avoid

Avoid broad prompts:

```text
Explain this codebase
Implement feature
Fix everything
Continue
Make it complete
Determine the active rung
Figure out what rung is next
```

These cause Codex to read too much, infer too much, and burn tokens.

Use scoped prompts:

```text
Review only.
Do not edit.
Classify against authority.
Quote exact requirement.
Edit only these files.
Run only these commands.
Do not start next rung.
The active rung is Rung<N>.
The active rung directive is docs/implementation/bringup/rung<N>.md.
```

---

## 12. Branch promotion workflow

For normal work, prefer:

```text
rung<N>-codex branch
review
commit
verify
merge or PR to main
```

For drift correction, where the branch is the final authority and `main` must be
overwritten:

```sh
git status --short
git fetch origin

git checkout main
git pull origin main

git branch backup-main-before-rung<N>-overwrite
git push origin backup-main-before-rung<N>-overwrite

git reset --hard origin/rung<N>-codex
git push --force-with-lease origin main
```

Then verify:

```sh
git rev-parse main
git rev-parse origin/rung<N>-codex
git status --short
```

Hashes should match and status should be clean.

Use this overwrite workflow only when intentionally correcting drift and when the
rung branch is explicitly declared the final authority.

---

## 13. Recommended next-rung starting workflow

When starting the next rung, do not resume the previous rung's large session.

Start fresh:

```sh
make dev
codex
```

Then use:

```text
Read AGENTS.md first and follow it exactly.

The active rung for this session is Rung<N>.
The active rung directive is:
docs/implementation/bringup/rung<N>.md

Then read the active rung directive, relevant frozen specs, source-of-truth docs, process docs, and current verification docs.

Do not rely on resume context or prior session memory as authority.

Task:
Review Rung<N> only.

Before editing anything:
1. Report which authority files you read.
2. Summarize what Rung<N> explicitly requires.
3. Classify required work as Required blocker, Required acceptance cleanup, or Out of scope.
4. State which files you plan to edit.

Do not edit files yet.
Do not expand Rung<N> by inference.
Do not modify protected authority files unless I explicitly authorize the exact file and exact intended change.
Do not start Rung<N+1>.
```

---

## 14. Workflow summary

```text
Name the active rung explicitly.
Name the active rung directive file explicitly.
Read authority.
Classify first.
Refine blockers.
Implement only authorized blockers.
Review dirty diff.
Tighten scope if needed.
Commit implementation manually.
Verify from committed state.
Commit verification docs separately.
Review protected docs separately.
Commit protected-doc cleanup separately.
Start fresh sessions between phases.
Never let Codex infer the active rung.
```

This workflow is slower than "just code," but it prevents drift, keeps token usage
lower, and produces better project-quality results.
