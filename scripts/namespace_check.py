from pathlib import Path

required = [
    'rtl/include/entry_ids.svh',
    'rtl/include/service_ids.svh',
    'rtl/include/fault_defs.svh',
    'rtl/include/commit_defs.svh',
    'rtl/include/field_defs.svh',
    'microcode/tools/generators/exports/entry_ids.inc',
    'microcode/tools/generators/exports/service_ids.inc',
    'microcode/tools/generators/exports/conditions.inc',
    'microcode/tools/generators/exports/commit_masks.inc',
]

missing = [p for p in required if not Path(p).exists()]
if missing:
    print('Missing namespace/export files:')
    for p in missing:
        print(' -', p)
    raise SystemExit(1)

print('Namespace/export scaffold present.')
