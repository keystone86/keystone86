# Keystone86 Development Environment

## Purpose

Keystone86 uses a Docker-based development environment so the RTL, simulation,
formal, synthesis, git, and AI-coding-agent tooling are reproducible across
machines.

The development image is intentionally project-local. Contributors should not
need to install the Keystone86 toolchain directly on the host system beyond
Docker itself.

## Image contents

The `keystone86-dev` image includes:

- `iverilog` + `vvp` for RTL simulation
- `verilator` for fast simulation and lint
- `gtkwave` for waveform inspection
- `yosys` for synthesis frontend work
- `nextpnr-ecp5` + `prjtrellis` / `ecppack` for ECP5 place and route
- `openFPGALoader` for ECP5 hardware flashing
- `symbiyosys` + `z3` for formal verification
- `sv2v` from OSS CAD Suite
- `python3`, `pytest`, `pyyaml`, `jinja2`, and `click`
- `make`, `git`, `openssh-client`, `ripgrep`, `jq`, `tree`, `dos2unix`, and `entr`
- `claude` for Claude Code
- `codex` for OpenAI Codex CLI

Claude Code and Codex CLI coexist in the same image. Use one AI coding agent at
a time.

## Build the image

From the repository root:

```bash
make dev-build
```

This builds:

```text
keystone86-dev
```

Rebuild the image after changing:

```text
docker/Dockerfile
Makefile
.devcontainer/devcontainer.json
```

## Enter the normal development container

From the repository root:

```bash
make dev
```

This starts an interactive shell in `/work`, with the repository mounted from the
host.

The normal development container is for:

- RTL editing
- simulation
- formal checks
- code generation
- git operations
- Claude Code
- Codex CLI

## Enter the FPGA/hardware container

For USB passthrough and ECP5 flashing:

```bash
make dev-fpga
```

This uses the same image but adds USB device passthrough and privileged access so
tools such as `openFPGALoader` can access hardware.

This target is not expected to work in GitHub Codespaces because Codespaces does
not provide local USB device access.

## Mounted host resources

The Makefile mounts several host resources into the container.

### Repository

```text
host repo -> /work
```

The current working tree is mounted into the container at `/work`.

### SSH keys

```text
$(HOME)/.ssh -> /root/.ssh:ro
```

The host SSH directory is mounted read-only. This allows git operations over SSH,
such as:

```bash
git push
```

The Docker image includes `openssh-client` so the mounted keys can actually be
used by git.

Recommended GitHub remote format:

```text
git@github.com:keystone86/keystone86.git
```

If the remote is still HTTPS, switch it with:

```bash
git remote set-url origin git@github.com:keystone86/keystone86.git
```

Test SSH access with:

```bash
ssh -T git@github.com
```

### Git configuration

```text
$(HOME)/.gitconfig -> /root/.gitconfig:ro
```

The host git identity is mounted read-only so commits made inside the container
use the same author identity.

The container also marks `/work` as a safe git directory.

## AI coding agents

The image includes both Claude Code and OpenAI Codex CLI.

They are installed side by side so the user can choose which tool to use for a
given session.

Do not run both agents against the same working tree at the same time.

### Claude Code

Start Claude Code from inside the container:

```bash
claude
```

Claude credentials are stored in:

```text
/root/.claude
```

The Makefile mounts this path from a named Docker volume:

```text
keystone86-claude-auth:/root/.claude
```

This preserves Claude login state across container restarts.

The environment may also pass through:

```text
ANTHROPIC_API_KEY
```

This is useful for Codespaces or other API-key-based workflows.

### OpenAI Codex CLI

Start Codex CLI from inside the container:

```bash
codex
```

Codex credentials are stored in:

```text
/root/.codex
```

The Makefile mounts this path from a named Docker volume:

```text
keystone86-codex-auth:/root/.codex
```

This preserves Codex login state across container restarts.

The environment may also pass through:

```text
OPENAI_API_KEY
```

This is useful for Codespaces or other API-key-based workflows.

## Safe AI-agent workflow

Use AI coding agents as implementation helpers, not as the source of truth.

Recommended workflow:

```bash
git status
git checkout -b <small-task-branch>
```

Then start one agent:

```bash
claude
```

or:

```bash
codex
```

Give the agent a narrow task.

After it finishes:

```bash
git status
git diff
```

Then run the relevant validation targets before committing.

For the current authoritative baseline:

```bash
make codegen
make ucode
make namespace-check
make ucode-bootstrap-check
make rung2-regress
```

Only commit after reviewing the diff and understanding the change.

## Baseline validation

After entering the container, a fresh clone should be validated with:

```bash
make codegen
make ucode
make namespace-check
make ucode-bootstrap-check
make rung2-regress
```

`rung2-regress` is the current authoritative passing baseline.

Rung 3 exists, but it is being re-proven from the clean Rung 2 baseline.

## GitHub authentication notes

GitHub no longer accepts account passwords for HTTPS git pushes.

Use SSH where possible.

Check the current remote:

```bash
git remote -v
```

Preferred remote:

```text
origin  git@github.com:keystone86/keystone86.git
```

If the remote is HTTPS, update it:

```bash
git remote set-url origin git@github.com:keystone86/keystone86.git
```

Then test:

```bash
ssh -T git@github.com
```

Then push:

```bash
git push --set-upstream origin <branch-name>
```

## Codespaces

The repo includes:

```text
.devcontainer/devcontainer.json
```

Codespaces uses the same Dockerfile.

For Codespaces, configure secrets as needed:

```text
ANTHROPIC_API_KEY
OPENAI_API_KEY
```

Codespaces can use the normal development workflow, but hardware flashing through
`make dev-fpga` is not available because USB passthrough is not available.

## File ownership

Development environment behavior is split across these files:

```text
docker/Dockerfile
Makefile
.devcontainer/devcontainer.json
README.md
docs/process/dev_environment.md
```

Responsibilities:

- `docker/Dockerfile` defines what is installed in the image.
- `Makefile` defines how the image is built and how containers are launched.
- `.devcontainer/devcontainer.json` defines Codespaces / VS Code container behavior.
- `README.md` gives the short user-facing quick-start.
- `docs/process/dev_environment.md` gives the longer operational explanation.

## Non-goals

This development environment document does not define RTL behavior, instruction
semantics, rung acceptance rules, or microarchitecture ownership boundaries.

Those belong in the relevant specs and process documents.

This document only defines how to enter and use the development environment.
