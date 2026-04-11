# Rung 0 Prefetch / Decode Smoke

## Goal

Validate the earliest queue/decode contract before the real prefetch queue
and decoder FSM are wired into RTL.

This smoke layer checks:
- byte consumption count
- `M_NEXT_EIP` derivation
- `decode_done` / `dec_ack` handshake model
- queue flush behavior after an EIP-changing commit

## Scope

This is a host-side model for the bootstrap repository.
It is not yet a cycle-accurate prefetch queue or decoder implementation.

## Command

```bash
make prefetch-decode-smoke
```
