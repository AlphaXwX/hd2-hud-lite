"""Build HUD Lite locally. No network, game edits or process access."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import zipfile
from PIL import Image
import archive
import icon_assets
from project import ROOT,META,BUILD,REPORTS,CONFIG,ASSETS,ICON_PACK,PATCH,LUA,ensure_dirs

def pack_resources():
    """Read the local icon pack: archive header, type table and every raw resource."""
    manifest=json.loads((ASSETS/'icon-pack/manifest.json').read_text(encoding='utf-8'))
    rows=[]
    for entry in manifest['textures']+manifest['resources']:
        key=f'{entry["id"]}-{entry["type"]}'
        data=(ASSETS/'icon-pack/raw'/f'{key}.data').read_bytes()
        gpu=(ASSETS/'icon-pack/raw'/f'{key}.gpu').read_bytes()
        assert hashlib.sha256(data+gpu).hexdigest()==entry['sha256'],entry['id']
        rows.append(dict(fid=int(entry['id'],16),tid=int(entry['type'],16),data=data,
                         gpu=gpu,stream=b'',ha=entry['ha'],hb=entry['hb'],seq=0))
    header=bytes.fromhex(manifest['archive']['header'])
    types=[(int(item['a']),int(item['type'],16),0,item['ha'],item['hb'])
           for item in manifest['archive']['types']]
    return manifest['archive'],header,types,rows

def build(source_only=False):
    ensure_dirs()
    for name,aliases in json.loads((CONFIG/'scalar-field-matches.json').read_text()).items():
        for alias in aliases:assert archive.resource_hash(alias)>>32==int(name,16),(name,alias)
    catalog=json.loads((CONFIG/'weapon_catalog.json').read_text(encoding='utf-8'))
    attribution=json.loads((ROOT/'third_party/COMPATIBILITY-SOURCE.json').read_text(encoding='utf-8'))
    assert (ROOT/attribution['license']).is_file(),'Compatibility license is required'
    assert hashlib.sha256((CONFIG/'weapon_catalog.json').read_bytes()).hexdigest()==attribution['catalog_sha256']
    for kind,entry in [*catalog['weapons'].items(),*catalog['backpacks'].items()]:
        assert archive.resource_hash(entry['call'])>>32==int(kind,16)
    for role in catalog['roles'].values():assert archive.resource_hash(role['name'])>>32==int(role['id'],16)
    for role,field in [('stims',0x5f8eb478),('grenades',0xd92082f9)]:
        assert archive.resource_hash(catalog['avatar'][role])>>32==field,role
    icons=icon_assets.prepare()
    subprocess.run([sys.executable,str(ROOT/'tools/emit_data.py')],check=True,cwd=ROOT)
    subprocess.run([sys.executable,str(ROOT/'tools/assemble.py')],check=True,cwd=ROOT)
    source=(BUILD/'hud_lite.lua').read_bytes()
    assert source.startswith(f'-- HD2-Addon: {META["resource"]}\n'.encode())
    archive_meta,header,types,rows=pack_resources()
    assert not any(row['tid']==LUA for row in rows)
    rows.append(dict(fid=archive.resource_hash(META['resource']),tid=LUA,
      data=struct.pack('<II',len(source),2)+source,stream=b'',gpu=b'',
      ha=archive_meta['lua']['ha'],hb=archive_meta['lua']['hb'],seq=0))
    for icon in icons:
        assert not any(r['fid']==icon['fid'] and r['tid']==icon['tid'] for r in rows)
        rows.append(icon)
    expected={(r['fid'],r['tid']):(r['data'],r['gpu']) for r in rows if r['tid']!=LUA}
    output=BUILD/'data';output.mkdir(exist_ok=True)
    archive.write(output/PATCH,header,types,rows)
    _,_,actual=archive.read(output/PATCH)
    assert len(actual)==42 and not any(r['fid']==archive.resource_hash('boot') for r in actual)
    for row in actual:
        if row['tid']==LUA:assert row['data'][8:]==source
        else:assert (row['data'],row['gpu'])==expected[(row['fid'],row['tid'])]
    manifest={'Version':1,'Guid':META['guid'],'Name':META['name']+' '+META['version'],
      'Author':META['author'],'Description':META['description_zh']+'\n'+META['description_en'],
      'IconPath':'icon.png'}
    (BUILD/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    preview=ASSETS/'preview.png'
    if not preview.is_file():
        preview=ASSETS/'icon-pack/preview/preview-original.png'
    with Image.open(preview) as im:
        im.load();im.convert('RGBA').save(BUILD/'icon.png')
    print('Verified:',len(actual),'resources; icon pack unchanged; confirmed preview applied')
    if source_only:return
    subprocess.run([sys.executable,str(ROOT/'tests/verify_docs.py')],check=True,cwd=ROOT)
    digest=hashlib.sha256(source).hexdigest()
    for name in ['VERIFICATION.json','ICON_VERIFICATION.json','BENCHMARK.json','RELEASE_VERIFICATION.json']:
        report=json.loads((REPORTS/name).read_text())
        assert report['source_sha256']==digest,'Stale report: '+name
        assert report.get('failed',0)==0 and report.get('passed',True),name
    target=ROOT/'dist'/f'HUD-Lite-{META["version"]}-Chef.zip'
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for file in sorted(output.iterdir()):z.write(file,file.name)
        z.write(BUILD/'manifest.json','manifest.json');z.write(BUILD/'icon.png','icon.png')
        for name in ['README.md','README.zh-CN.md','THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.zh-CN.md',
                     'LICENSE','LICENSE.zh-CN.md','CHANGELOG.md','CHANGELOG.zh-CN.md']:z.write(ROOT/name,name)
        for file in sorted((ROOT/'docs').glob('*.md')):z.write(file,'docs/'+file.name)
        for file in sorted((ROOT/'third_party').glob('*')):
            if file.is_file():z.write(file,'third_party/'+file.name)
        z.write(CONFIG/'weapon_catalog.json','config/weapon_catalog.json')
        for name in ['VERIFICATION.json','ICON_VERIFICATION.json','ICON_PROVENANCE.json','BENCHMARK.json','SOURCE_PROVENANCE.json','RELEASE_VERIFICATION.json']:
            z.write(REPORTS/name,'reports/'+name)
        z.write(CONFIG/'published_visual_defaults.json','config/published_visual_defaults.json')
        z.write(ROOT/'project.json','project.json')
        z.write(CONFIG/'identity.json','config/identity.json')
        for name in ['project.py']:z.write(ROOT/'tools'/name,'tools/'+name)
        for name in ['Magazine_Icon.svg','Magazine_Icon.png']:z.write(ASSETS/name,'assets/'+name)
        for name in ['cura','grenade']:
            z.write(ICON_PACK/'consumables'/f'{name}.svg',f'assets/consumables/{name}.svg')
            z.write(ASSETS/f'{name}.png',f'assets/{name}.png')
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None and z.read(PATCH)==(output/PATCH).read_bytes()
    print('RELEASE:',target)
    print('SHA256:',hashlib.sha256(target.read_bytes()).hexdigest())

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-only',action='store_true')
    build(parser.parse_args().source_only)
