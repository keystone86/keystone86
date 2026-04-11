from pathlib import Path
version = Path('VERSION').read_text(encoding='utf-8').strip()
print(f'# Release Notes for {version}')
print()
print('- summarize completed milestones')
print('- summarize verification status')
print('- summarize known limitations')
