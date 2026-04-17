# Rung 2

## Goal

Prove early control-transfer correctness for JMP SHORT.

## Contracts implemented

- **Position-proven byte capture:** decoder only accepts a byte when the fetch-side payload
  proves the byte is valid, at the expected position, and belongs to the current non-stale stream.
- **Real decode acceptance boundary:** decode result becomes the active instruction only on
  explicit transfer into microsequencer ownership. Decoder holds payload stable while not accepted.
- **Control-transfer serialization:** once a JMP decode payload is accepted, the abandoned
  stream is not advanced. Upstream holds until the redirect anchor is known.
- **Commit-owned redirect visibility:** redirect becomes architecturally real only at ENDI
  in `commit_engine`. Nothing upstream makes redirect architecturally visible before this.

## Required instruction coverage

- `0xEB` (JMP SHORT) with 8-bit signed displacement
  - self-loop (EB FE)
  - forward displacement (EB 05)
  - backward displacement (EB F0)

## Microcode additions

- `ENTRY_JMP_SHORT` in `microcode/src/entries/` (or inlined in decoder for bring-up scope)
- ENDI with `CM_EIP | CM_FLUSHQ` mask to commit JMP target EIP and flush the prefetch queue

## Validation

```bash
make rung2-sim
```

Also run the full baseline to confirm earlier rungs remain passing:

```bash
make rung0-sim
make rung1-regress
```

## Notes

Rung 2 uses strict serialization, not fetch-local direct stream following.
Fetch-local stream following (where the fetch side retargets without waiting for commit)
is an allowed future optimization but is explicitly deferred to keep this rung narrow.

Full epoch propagation through RTL is also deferred. The correct baseline for later
optimization work is the serialized commit-visible redirect model proven here.
