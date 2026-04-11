# Appendix A Code Generator Stub

This directory is the bridge from frozen Appendix A definitions to generated implementation artifacts.

## Current source-of-truth flow

- Human-readable approved spec lives at:
  - `docs/spec/frozen/appendix_a_field_dictionary.md`
- Machine-readable codegen source currently lives at:
  - `tools/spec_codegen/appendix_a_codegen.json`

The JSON is the generator input for now.
The frozen markdown file is the constitutional source.

## Goal

Generate, from one canonical machine-readable source:
- `rtl/include/entry_ids.svh`
- `rtl/include/service_ids.svh`
- `rtl/include/fault_defs.svh`
- `rtl/include/commit_defs.svh`
- `rtl/include/field_defs.svh`
- `rtl/include/keystone86_pkg.sv`
- `microcode/tools/generators/exports/*.inc`

## Recommended workflow

1. Update/freeze Appendix A markdown.
2. Reflect that content in `appendix_a_codegen.json`.
3. Run `python3 tools/spec_codegen/gen_from_appendix_a.py`.
4. Review generated diffs.
5. Run `make namespace-check`.
6. Commit the spec change and generated namespace outputs together.

## Long-term target

Replace manual JSON maintenance with an Appendix A markdown export/parser step.
