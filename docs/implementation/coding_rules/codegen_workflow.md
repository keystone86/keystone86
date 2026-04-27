# Appendix A Codegen Workflow

## Constitutional source

- `docs/spec/frozen/appendix_a_field_dictionary.md`

## Current generator source

- `tools/spec_codegen/appendix_a_codegen.json`

## Generated outputs

- `rtl/include/*.svh`
- `rtl/include/keystone86_pkg.sv`
- `microcode/tools/generators/exports/*.inc`

## Required discipline

When Appendix A changes:
Appendix A is frozen/protected; editing it requires explicit protected-file authorization/proposal before this workflow proceeds.
1. Update the frozen markdown file.
2. Update `appendix_a_codegen.json` to match.
3. Run:
   ```bash
   python3 tools/spec_codegen/gen_from_appendix_a.py
   make namespace-check
   ```
4. Review the generated diffs.
5. Commit spec and generated namespace changes together.

## Future improvement

Implement a parser/export step that extracts the JSON directly from the approved Appendix A content.
