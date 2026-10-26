from pathlib import Path
import hashlib
import io
import json
import re
import struct
import sys
import zipfile
from PIL import Image,ImageChops

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import archive

def main():
    p=json.loads((ROOT/'reports/ICON_PROVENANCE.json').read_text(encoding='utf-8'))
    svg=(ROOT/'assets/Magazine_Icon.svg').read_bytes()
    assert b'<svg' in svg and hashlib.sha256(svg).hexdigest()==p['svg_sha256']
    png=Image.open(ROOT/'assets/Magazine_Icon.png').convert('RGBA')
    assert png.size==(512,512)
    assert png.getchannel('A').getextrema()==(0,255)
    assert png.getchannel('A').getbbox() is not None
    pixels=list(png.get_flattened_data())
    assert all((r,g,b)==(255,255,255) for r,g,b,a in pixels if a>0)
    assert any(0<a<255 for r,g,b,a in pixels),'antialiasing missing'
    _,_,rows=archive.read(ROOT/'build/data/9ba626afa44a3aa3.patch_0')
    textures={f'{r["fid"]:016x}':r for r in rows if r['tid']==0xcd4238c6a0c69e32}
    magazine=textures[p['magazine_texture_id']]
    start=magazine['data'].index(b'DDS ')
    decoded=Image.open(io.BytesIO(magazine['data'][start:]+magazine['gpu'])).convert('RGBA')
    runtime=Image.open(ROOT/'assets/Magazine_Icon_256.png').convert('RGBA')
    assert decoded.size==(256,256)
    assert ImageChops.difference(decoded,runtime).getbbox() is None
    mapping=p['booster_mapping']['rows']
    assert len(mapping)==21 and set(x['id']for x in mapping)==set(range(21))
    assert len({x['texture'] for x in mapping})==21
    pack=json.loads((ROOT/'assets/icon-pack/manifest.json').read_text(encoding='utf-8'))
    packed={e['id'] for e in pack['textures']}
    for entry in mapping:
        ident=entry['texture']
        assert ident in packed,ident
        row=textures[ident]
        key=f'{ident}-{row["tid"]:016x}'
        data=(ROOT/'assets/icon-pack/raw'/f'{key}.data').read_bytes()
        gpu=(ROOT/'assets/icon-pack/raw'/f'{key}.gpu').read_bytes()
        assert row['data']==data and row['gpu']==gpu,ident
    assert len(rows)==40 and len([r for r in rows if r['tid']==0xa14e8dfa2cd117e2])==1
    assert not any(r['fid']==archive.resource_hash('boot') for r in rows)
    report={'passed':True,'booster_textures_verified':21,'actual_boosters':20,'none_slot':0,
      'archive_resources':len(rows),'magazine_png':'512x512 RGBA, white transparent antialiased',
      'runtime_texture':'256x256, DDS decoded pixels identical to PNG',
      'svg_unchanged':True,'magazine_id':p['magazine_texture_id'],
      'source_sha256':hashlib.sha256((ROOT/'build/hud_lite.lua').read_bytes()).hexdigest()}
    (ROOT/'reports/ICON_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
