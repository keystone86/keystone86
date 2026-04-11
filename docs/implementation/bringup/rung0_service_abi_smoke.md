# Rung 0 Service ABI Smoke

## Goal

Validate the earliest service ABI discipline before the real service RTL is in place.

This smoke layer checks:
- service return codes `SR_OK`, `SR_WAIT`, `SR_FAULT`
- invocation discipline for `SVC` vs `SVCW`
- wait-capable service metadata
- fault-capable service metadata

## Scope

This is a host-side contract model for the service ABI.
It is not yet a cycle-accurate service or microsequencer implementation.

## Command

```bash
make service-abi-smoke
```
