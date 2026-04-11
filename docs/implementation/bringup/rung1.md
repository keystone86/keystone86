# Rung 1

## Goal

Prove minimal decode and dispatch sanity for the earliest entry set.

## Required mappings

- `0x90` -> `ENTRY_NOP_XCHG_AX`
- unknown opcode -> `ENTRY_NULL`
- prefix-only placeholder path -> `ENTRY_PREFIX_ONLY`
- reset dispatch -> `ENTRY_RESET`

## Smoke checks

```bash
make decode-dispatch-smoke
```

## Notes

This is a host-side smoke layer, not yet a full RTL simulation of the decoder FSM.
It exists to pin down the intended early decode/dispatch behavior before deeper RTL and sim work.
