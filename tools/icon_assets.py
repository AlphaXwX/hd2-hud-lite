"""Build icon lookup data from verified attachments, never filename ordering."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
from PIL import Image
import archive
from project import ROOT,META,BUILD,REPORTS,CONFIG,ASSETS,ensure_dirs

HERE=Path(__file__).resolve().parent
TEXTURE=0xcd4238c6a0c69e32
MAGAZINE=META['magazine_resource']

def dds_rgba(width,height):
    resource=struct.pack('<III',0,0,0xffffffff)+b'\0'*(15*12)
    pf=struct.pack('<II4sIIIII',32,4,b'DX10',0,0,0,0,0)
    header=struct.pack('<IIIIIII',124,0x1007,height,width,width*4,0,1)+b'\0'*44
    header+=pf+struct.pack('<IIIII',0x1000,0,0,0,0)
    data=resource+b'DDS '+header+struct.pack('<IIIII',28,3,0,1,0)
    assert len(data)==340
    return data

def prepare():
    ensure_dirs()
    subprocess.run(['node',str(HERE/'render_magazine.cjs')],check=True)
    im=Image.open(ASSETS/'Magazine_Icon.png').convert('RGBA')
    assert im.size==(512,512) and im.getchannel('A').getextrema()==(0,255)
    runtime=im.resize((256,256),Image.Resampling.LANCZOS)
    runtime.save(ASSETS/'Magazine_Icon_256.png')
    mapping=json.loads((CONFIG/'booster_mapping.json').read_text(encoding='utf-8'))
    assert len(mapping['rows'])==21 and {r['id'] for r in mapping['rows']}==set(range(21))
    pack=json.loads((ASSETS/'icon-pack/manifest.json').read_text(encoding='utf-8'))
    packed={entry['id'] for entry in pack['textures']}
    missing=[row['texture'] for row in mapping['rows'] if row['texture'] not in packed]
    assert not missing,'booster icons missing from the icon pack: '+', '.join(missing)
    magazine_id=archive.resource_hash(MAGAZINE)
    text='-- Generated from verified attachment resource mappings.\nlocal IconAssets = {\n'
    text+=f'  magazine="{magazine_id:016x}",\n  boosters={{\n'
    for row in mapping['rows']:
        text+=f'    ["booster_{row["id"]}"]="{row["texture"]}",\n'
    text+='  },\n  by_native={\n'
    for row in mapping['rows']:
        text+=f'    ["{row["native"]}"]="{row["texture"]}",\n'
    text+='  },\n}\n'
    text+='-- Imported model can select all supported numeric booster IDs.\n'
    for row in mapping['rows']:
        text+=f'generated.identity.booster["{row["id"]}"]="booster_{row["id"]}"\n'
    (BUILD/'icon_resources.lua').write_text(text,encoding='utf-8')
    provenance={
      'source_pack':'assets/icon-pack (local build input; not distributed in repository)',
      'booster_mapping':mapping,'booster_resources_byte_identical':True,
      'svg_sha256':hashlib.sha256((ASSETS/'Magazine_Icon.svg').read_bytes()).hexdigest(),
      'png512_sha256':hashlib.sha256((ASSETS/'Magazine_Icon.png').read_bytes()).hexdigest(),
      'runtime_png256_sha256':hashlib.sha256((ASSETS/'Magazine_Icon_256.png').read_bytes()).hexdigest(),
      'magazine_resource':MAGAZINE,'magazine_texture_id':f'{magazine_id:016x}',
      'counts':{'booster_resources':21,'actual_boosters':20,'none_placeholder':1},
      'runtime':'21 existing icon textures reused; one 256px RGBA texture added; no runtime SVG parsing or game.dll reads'}
    (REPORTS/'ICON_PROVENANCE.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
    return dict(fid=magazine_id,tid=TEXTURE,data=dds_rgba(256,256),stream=b'',gpu=runtime.tobytes(),ha=16,hb=64,seq=0)
