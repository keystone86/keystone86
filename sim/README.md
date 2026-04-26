# Simulation Layers

The current Rung 5 regression entry point is:

```bash
make rung5-regress
```

Detailed Rung 5 proof status and observed results are recorded in:

- `docs/implementation/rung5_verification.md`

Useful Rung 5 individual simulation targets:

```bash
make rung5-pass2-sim
make rung5-pass3-sim
make rung5-pass4-sim
make rung5-pass5-sim
```

Bootstrap host-side smoke checks:

```bash
make decode-dispatch-smoke
make microseq-smoke
make commit-smoke
make service-abi-smoke
make prefetch-decode-smoke
```
