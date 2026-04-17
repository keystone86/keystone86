# Bootstrap Status

For a detailed matrix of current bootstrap checks and bring-up rung support, see:

- `docs/implementation/bringup/STATUS_DASHBOARD.md`

## RTL simulation — current passing baseline

```bash
make rung0-sim
make rung1-sim
make rung2-sim
```

To confirm all rungs together (each regression includes all prior rungs):

```bash
make rung1-regress
make rung2-regress
```

## Bootstrap smoke checks

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
