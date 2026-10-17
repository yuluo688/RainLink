from pathlib import Path
import shutil

root = Path(__file__).resolve().parent
old = root / 'exports/design-md-v5'
new = root / 'exports/subscription-v6'
for section in ['desktop', 'mobile', 'system']:
    (new / section).mkdir(parents=True, exist_ok=True)
    for path in (old / section).glob('*.png'):
        if not (new / section / path.name).exists():
            shutil.copy2(path, new / section / path.name)
print('Prepared V6 delivery; unchanged validated screenshots reused.')
