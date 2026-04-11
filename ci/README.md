# CI and Automation

This repository uses CI to enforce:
- frozen spec presence
- import manifest completeness
- namespace/codegen consistency
- reproducible generated namespace outputs
- basic microcode/bootstrap smoke checks

## Current CI lanes

- spec-and-namespace
- codegen
- microcode-bootstrap
- smoke

## Expected future lanes

- Verilog lint
- unit test smoke
- service-level regression subsets
- formal property subsets
- packaging and release notes generation
