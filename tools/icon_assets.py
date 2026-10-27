"""Build icon lookup data from verified attachments, never filename ordering."""
from pathlib import Path
import hashlib
import io
import json
import struct
import subprocess
from PIL import Image
import archive
from project import ROOT,META,BUILD,REPORTS,CONFIG,ASSETS,ICON_PACK,ensure_dirs

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

def visible_metric(image,texture,cell=None):
    """UV crop plus natural dimensions, excluding transparent tile padding."""
    x,y,w,h=cell or (0,0,image.width,image.height)
    bounds=image.crop((x,y,x+w,y+h)).getchannel('A').getbbox()
    if bounds is None:return None
    # One source-pixel gutter preserves antialiasing at the visible boundary.
    left,top,right,bottom=bounds
    left,top=max(0,left-1),max(0,top-1)
    right,bottom=min(w,right+1),min(h,bottom+1)
    return {'texture':texture,'u0':(x+left)/image.width,'v0':(y+top)/image.height,
      'u1':(x+right)/image.width,'v1':(y+bottom)/image.height,
      'width':(right-left)/w,'height':(bottom-top)/h}

def prepare():
    ensure_dirs()
    subprocess.run(['node',str(HERE/'render_magazine.cjs')],check=True)
    subprocess.run(['node',str(HERE/'render_items.cjs')],check=True)
    item_rows=[];item_provenance={};row_metrics={}
    for name in ['cura','grenade']:
        source=ICON_PACK/'consumables'/f'{name}.svg'
        image=Image.open(ASSETS/f'{name}.png').convert('RGBA')
        assert image.size==(512,512) and image.getchannel('A').getextrema()==(0,255)
        small=image.resize((256,256),Image.Resampling.LANCZOS)
        small.save(ASSETS/f'{name}_256.png')
        resource=META['resource']+'/icons/'+name
        ident=archive.resource_hash(resource)
        row_metrics[name]=visible_metric(small,f'{ident:016x}')
        item_rows.append(dict(fid=ident,tid=TEXTURE,data=dds_rgba(256,256),stream=b'',gpu=small.tobytes(),ha=16,hb=64,seq=0))
        item_provenance[name]={'svg_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
          'texture_id':f'{ident:016x}','resource':resource,
          'png512_sha256':hashlib.sha256((ASSETS/f'{name}.png').read_bytes()).hexdigest()}
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
    row_metrics['magazine']=visible_metric(runtime,f'{magazine_id:016x}')
    atlas_id='254deec0e6c38888'
    entry=next(row for row in pack['textures'] if row['id']==atlas_id)
    key=f'{entry["id"]}-{entry["type"]}'
    data=(ASSETS/'icon-pack/raw'/f'{key}.data').read_bytes()
    gpu=(ASSETS/'icon-pack/raw'/f'{key}.gpu').read_bytes()
    atlas=Image.open(io.BytesIO(data[data.index(b'DDS '):]+gpu)).convert('RGBA')
    icons=json.loads((CONFIG/'generated_common.json').read_text(encoding='utf-8'))['identity']['icon_cells']
    w,h=atlas.width//32,atlas.height//2
    for name,index in icons.items():
        metric=visible_metric(atlas,atlas_id,((index%32)*w,(index//32)*h,w,h))
        if metric is not None:row_metrics[name]=metric
    text='-- Generated from verified attachment resource mappings.\nlocal IconAssets = {\n'
    text+=f'  magazine="{magazine_id:016x}",\n'
    for name,row in item_provenance.items():text+=f'  {name}="{row["texture_id"]}",\n'
    text+='  boosters={\n'
    for row in mapping['rows']:
        text+=f'    ["booster_{row["id"]}"]="{row["texture"]}",\n'
    text+='  },\n  by_native={\n'
    for row in mapping['rows']:
        text+=f'    ["{row["native"]}"]="{row["texture"]}",\n'
    text+='  },\n  row_metrics={\n'
    for name,metric in sorted(row_metrics.items()):
        values=','.join(key+'='+json.dumps(value) for key,value in metric.items())
        text+=f'    ["{name}"]={{{values}}},\n'
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
      'consumables':item_provenance,
      'information_row_metrics':row_metrics,
      'counts':{'booster_resources':21,'actual_boosters':20,'none_placeholder':1},
      'runtime':'21 existing icon textures reused; three 256px RGBA textures added; no runtime SVG parsing or game.dll reads'}
    (REPORTS/'ICON_PROVENANCE.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
    return [dict(fid=magazine_id,tid=TEXTURE,data=dds_rgba(256,256),stream=b'',gpu=runtime.tobytes(),ha=16,hb=64,seq=0),*item_rows]
