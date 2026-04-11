from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

def walk(p, prefix=''):
    entries = sorted([e for e in p.iterdir()], key=lambda x: (x.is_file(), x.name.lower()))
    for i, e in enumerate(entries):
        last = i == len(entries) - 1
        branch = '└── ' if last else '├── '
        print(prefix + branch + e.name)
        if e.is_dir():
            walk(e, prefix + ('    ' if last else '│   '))

print(root.name)
walk(root)
