from pathlib import Path

version = Path('VERSION')
releases = Path('RELEASES.md')
changelog = Path('CHANGELOG.md')

missing = [str(p) for p in [version, releases, changelog] if not p.exists()]
if missing:
    print('Missing release/version files:')
    for p in missing:
        print(' -', p)
    raise SystemExit(1)

print('VERSION:', version.read_text(encoding='utf-8').strip())
print('Release/version scaffolding present.')
