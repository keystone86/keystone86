# Rung 0 Commit / ENDI Smoke

## Goal

Validate the earliest architectural-boundary behavior around ENDI and commit masks.

This smoke layer checks:
- `CM_NOP`
- `CM_FAULT_END`
- EIP-only commit path
- clear-fault behavior

## Scope

This is a host-side bootstrap model for commit semantics.  
It is not yet the real `commit_engine` RTL.

## Command

```bash
make commit-smoke
```
