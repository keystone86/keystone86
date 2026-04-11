from pathlib import Path
import json

appendix = Path('docs/spec/frozen/appendix_a_field_dictionary.md')
json_src = Path('tools/spec_codegen/appendix_a_codegen.json')
required_outputs = [
    Path('rtl/include/entry_ids.svh'),
    Path('rtl/include/service_ids.svh'),
    Path('rtl/include/fault_defs.svh'),
    Path('rtl/include/commit_defs.svh'),
    Path('rtl/include/field_defs.svh'),
    Path('rtl/include/keystone86_pkg.sv'),
    Path('microcode/tools/generators/exports/entry_ids.inc'),
    Path('microcode/tools/generators/exports/service_ids.inc'),
    Path('microcode/tools/generators/exports/conditions.inc'),
    Path('microcode/tools/generators/exports/commit_masks.inc'),
]

print('Appendix A imported:', 'YES' if appendix.exists() else 'NO')
print('Codegen JSON present:', 'YES' if json_src.exists() else 'NO')

missing = [str(p) for p in required_outputs if not p.exists()]
if missing:
    print('Missing generated namespace outputs:')
    for p in missing:
        print(' -', p)
    raise SystemExit(1)

# light validation
data = json.loads(json_src.read_text(encoding='utf-8'))
print('Codegen JSON keys:', ', '.join(sorted(data.keys())))
print('Namespace outputs present: YES')
