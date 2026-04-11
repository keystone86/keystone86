# Governance

## Constitutional files

The following files are constitutional for the project:

- `docs/spec/frozen/master_design_statement.md`
- `docs/spec/frozen/appendix_a_field_dictionary.md`
- `docs/spec/frozen/appendix_b_ownership_matrix.md`
- `docs/spec/frozen/appendix_c_assembler_spec.md`
- `docs/spec/frozen/appendix_d_bringup_ladder.md`
- `docs/spec/frozen/verification_plan.md`

Changes to these files require:
- explicit architecture review
- matching updates to impacted code/tests/tooling
- a changelog entry in `docs/spec/changelogs/architecture_decisions.md`

## Frozen core areas

Treat these directories as guarded:
- `rtl/core/`
- `rtl/include/`
- `microcode/src/`
- `docs/spec/frozen/`

## Flexible areas

These are safe areas for incubation:
- `docs/spec/working/`
- `proposals/`
- `experiments/`
- `rtl/experimental/`

## Naming

Public name: Keystone86  
Current generation: Aegis
