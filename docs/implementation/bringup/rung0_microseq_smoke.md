# Rung 0/1 Microsequencer Smoke

## Goal

Validate the earliest control-state loop before full RTL simulation exists.

The smoke checks cover:
- reset dispatch to `ENTRY_RESET`
- normal decode dispatch to `ENTRY_NOP_XCHG_AX`
- `ENDI` returning the control machine to fetch/decode
- unknown opcode dispatching to `ENTRY_NULL`

## Current scope

This is a host-side control-path model derived from the bootstrap seed:
- dispatch table
- bootstrap ROM layout
- bootstrap entry ownership

It is not yet a cycle-accurate RTL simulation.

## Command

```bash
make microseq-smoke
```
