"""One-off importer: build ``assets/icon-pack`` from a supplied resource package.

Pass ``--package`` with the archive you own, for example a previously imported
copy under ``external/``. The output is a neutral, self-contained pack:

  textures/<id>.png   viewable first mip level (edit these)
  raw/<id>.data       original resource header bytes, byte-exact
  raw/<id>.gpu        original pixel payload, byte-exact
  resources/<id>.bin  non-texture resources, byte-exact
  manifest.json       identifiers, sizes, formats and hashes

Attribution belongs in THIRD_PARTY_NOTICES.md, not in this folder.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive
from project import ASSETS, LUA

TEXTURE = 0xcd4238c6a0c69e32
SHARED = ASSETS / 'icon-pack'


def dds_header(width, height, mips, fmt):
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | (0x80000 if mips > 1 else 0)
    if fmt == 'rgba':
        pixel = struct.pack('<II4sIIIII', 32, 0x41, b'\0\0\0\0', 32,
                            0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000)
        pitch = width * 4
    else:
        pixel = struct.pack('<II4sIIIII', 32, 0x4, fmt.encode(), 0, 0, 0, 0, 0)
        pitch = max(1, width // 4) * 16
    caps = 0x1000 | (0x400000 if mips > 1 else 0) | 0x8
    return (b'DDS ' + struct.pack('<7I', 124, flags, height, width, pitch, 0, mips)
            + b'\0' * 44 + pixel + struct.pack('<5I', caps, 0, 0, 0, 0))


def expected(width, height, mips, fmt):
    total = 0
    for i in range(mips):
        w, h = max(1, width >> i), max(1, height >> i)
        total += max(1, w // 4) * max(1, h // 4) * 16 if fmt == 'DXT5' else w * h * 4
    return total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True,
                        help='resource archive you own and may redistribute')
    args = parser.parse_args()
    package = args.package.expanduser().resolve()
    if not package.is_file():
        raise SystemExit(f'input package not found: {package}')

    for name in ['raw', 'textures', 'resources']:
        (SHARED / name).mkdir(parents=True, exist_ok=True)

    archive_header, archive_types, rows = archive.read(package)
    manifest = {'source_package': package.name, 'attribution': 'THIRD_PARTY_NOTICES.md',
                'archive': {'header': archive_header.hex(),
                            'types': [{'type': f'{t[1]:016x}', 'a': str(t[0]),
                                       'ha': t[3], 'hb': t[4]} for t in archive_types]},
                'textures': [], 'resources': []}
    textures = others = 0

    for row in rows:
        if row['tid'] == LUA:
            manifest['archive']['lua'] = {'ha': row['ha'], 'hb': row['hb']}
            continue
        fid = f'{row["fid"]:016x}'
        key = f'{fid}-{row["tid"]:016x}'
        (SHARED / 'raw' / f'{key}.data').write_bytes(row['data'])
        (SHARED / 'raw' / f'{key}.gpu').write_bytes(row['gpu'])
        entry = {'id': fid, 'type': f'{row["tid"]:016x}',
                 'data_bytes': len(row['data']), 'gpu_bytes': len(row['gpu']),
                 'ha': row['ha'], 'hb': row['hb'],
                 'sha256': hashlib.sha256(row['data'] + row['gpu']).hexdigest()}

        if row['tid'] != TEXTURE:
            (SHARED / 'resources' / f'{fid}.bin').write_bytes(row['data'])
            others += 1
            manifest['resources'].append(entry)
            continue

        header = row['data'][row['data'].find(b'DDS '):][:128]
        height, width = struct.unpack_from('<II', header, 12)
        mips = struct.unpack_from('<I', header, 28)[0] or 1
        fmt = 'rgba' if len(row['gpu']) >= expected(width, height, mips, 'rgba') - 16 else 'DXT5'
        payload = row['gpu'][:expected(width, height, mips, fmt)]
        dds = dds_header(width, height, mips, fmt) + payload
        if expected(width, height, mips, fmt) > len(payload):
            dds += b'\0' * (expected(width, height, mips, fmt) - len(payload))

        try:
            from PIL import Image
            image = Image.open(io.BytesIO(dds))
            image.load()
            image.convert('RGBA').save(SHARED / 'textures' / f'{fid}.png')
            entry['png'] = f'textures/{fid}.png'
        except Exception as error:  # keep the raw resource even if preview fails
            entry['png_error'] = f'{type(error).__name__}: {error}'

        entry.update({'width': width, 'height': height, 'mips': mips, 'format': fmt})
        textures += 1
        manifest['textures'].append(entry)

    (SHARED / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    size = sum(p.stat().st_size for p in SHARED.rglob('*') if p.is_file())
    print(f'Extracted {textures} textures and {others} resources')
    print(f'Output: {SHARED}  ({size / 1048576:.1f} MB)')


if __name__ == '__main__':
    main()
