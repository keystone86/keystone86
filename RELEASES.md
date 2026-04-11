# Release and Tagging Policy

## Public project name

Keystone86

## Current generation

Aegis

## Versioning model

Use:

`<Generation>-v<major>.<minor>.<patch>`

Examples:
- `Aegis-v0.1.0`
- `Aegis-v0.2.0`
- `Aegis-v1.0.0`

Optional repo tag aliases:
- `keystone86-aegis-v0.1.0`

## Meaning

### major
Architecture or milestone boundary.
Examples:
- first fully working phase-1 core
- first full compliance milestone
- first protected-mode milestone

### minor
Feature-complete increments within the same architectural generation.
Examples:
- new instruction family completion
- new verified service family
- major tooling maturity step

### patch
Bug-fix or regression-only release with no intentional architectural change.

## Release discipline

A release should not be tagged until:
- frozen spec is present and tracked
- import manifest is complete
- codegen outputs are synchronized
- bootstrap/CI checks pass
- release notes are written
