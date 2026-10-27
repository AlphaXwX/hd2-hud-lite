"""Emit Lua data tables from the first-party JSON configuration.

    config/generated_common.json  ->  build/generated_common.lua
    config/fragments.json         ->  build/fragments.lua

Edit the JSON; the generated Lua is never edited by hand.

Encoding: a table whose keys are all integers is stored as ``{"@num": {...}}``
with decimal string keys; every other table is a plain object with string keys.
Numbers, strings and booleans map directly.
"""
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from project import BUILD, CONFIG

DATASETS = [
    ('generated_common.json', 'generated_common.lua', 'local GeneratedCommon = '),
    ('fragments.json', 'fragments.lua', 'local fragment_data = '),
    ('weapon_catalog.json', 'weapon_catalog.lua', 'local WeaponCatalog = '),
]


def to_lua(value, indent=0):
    pad = '  ' * indent
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value,list):
        return '{'+','.join(to_lua(item,indent+1)for item in value)+'}'
    if '@num' in value:
        rows = sorted(value['@num'].items(), key=lambda kv: int(kv[0]))
        if not rows:
            return '{}'
        inner = ''.join(f'{pad}  [{k}] = {to_lua(v, indent + 1)},\n' for k, v in rows)
        return '{\n' + inner + pad + '}'
    if not value:
        return '{}'
    inner = ''.join(f'{pad}  ["{k}"] = {to_lua(v, indent + 1)},\n' for k, v in sorted(value.items()))
    return '{\n' + inner + pad + '}'


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    for source_name, target_name, prefix in DATASETS:
        data = json.loads((CONFIG / source_name).read_text(encoding='utf-8'))
        target = BUILD / target_name
        target.write_text(prefix + to_lua(data) + '\n', encoding='utf-8')
        print(f'Emitted {source_name} -> {target.name} ({target.stat().st_size / 1024:.1f} KB)')


if __name__ == '__main__':
    main()
