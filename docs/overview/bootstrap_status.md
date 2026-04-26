# Bootstrap Status

Current verified/documented bring-up status is recorded in:

- `docs/implementation/rung5_verification.md`

That record documents Rung 5 committed-state verification at implementation
commit `b8e75f9` and documentation closeout commit `79cef97`.

Rung 5 is verified/documented. This status page does not claim human acceptance.
Rung 6 remains blocked until Rung 5 is explicitly accepted and Rung 6 is started
under the proven workflow.

## Current Regression Entry Point

```bash
make rung5-regress
```

`make rung5-regress` invokes the accepted Rung 4 regression path and the Rung 5
Pass 2, Pass 3, Pass 4, and Pass 5 simulations.

## Rung 5 Proof References

```bash
make rung5-pass2-sim
make rung5-pass3-sim
make rung5-pass4-sim
make rung5-pass5-sim
```

For exact commands and observed pass/fail results, use
`docs/implementation/rung5_verification.md`.

## Bootstrap Smoke Checks

```bash
make bootstrap-report
make spec-check
make ucode
make decode-dispatch-smoke
make microseq-smoke
make commit-smoke
make service-abi-smoke
make prefetch-decode-smoke
```
