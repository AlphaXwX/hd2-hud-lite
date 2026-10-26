"""Verify HUD Lite branding, preview, archive identity and source hygiene."""
from pathlib import Path
import hashlib
import json
import re
import sys
import zipfile
from PIL import Image,ImageChops

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from project import META,BUILD,REPORTS,ICON_PACK
import archive

def verify(package=None):
    source=(BUILD/'hud_lite.lua').read_bytes()
    text=source.decode('utf-8')
    manifest=json.loads((BUILD/'manifest.json').read_text(encoding='utf-8'))
    assert manifest['Version']==1
    assert manifest['Name']=='HUD Lite 1.0.0'
    assert manifest['Author']=='Alpha F. Bloodfallen'
    assert manifest['Description']==META['description_zh']+'\n'+META['description_en']
    assert 'local VERSION = "1.0.0"' in text
    assert '-- HUD Lite 1.0.0 by Alpha F. Bloodfallen' in text
    assert not re.search(r'\b(?:0\.1\.[0-9]+|1\.10\.[0-9]+|1\.12\.[0-9]+)\b',text)
    for folder in ['src','tools','tests','build']:
        for file in (ROOT/folder).glob('*'):
            if file.suffix not in ['.lua','.py','.cjs']:continue
            body=file.read_text(encoding='utf-8')
            assert not re.search(r'\b(?:0\.1\.[0-9]+|1\.10\.[0-9]+)\b',body),file.name
    a=Image.open(ICON_PACK/'preview/preview-original.png').convert('RGBA')
    b=Image.open(BUILD/'icon.png').convert('RGBA')
    assert a.size==b.size and ImageChops.difference(a,b).getbbox() is None
    _,_,rows=archive.read(BUILD/'data/9ba626afa44a3aa3.patch_0')
    lua=[r for r in rows if r['tid']==0xa14e8dfa2cd117e2]
    assert len(lua)==1 and lua[0]['data'][8:]==source
    assert lua[0]['fid']==archive.resource_hash(META['resource'])
    assert META['resource']=='mods/alpha_f_bloodfallen/hud_lite'
    assert META['resource'].rsplit('/',1)[-1]=='hud_lite'
    assert text.splitlines()[0]=='-- HD2-Addon: '+META['resource']
    if package:
        with zipfile.ZipFile(package) as z:
            assert z.testzip() is None
            assert json.loads(z.read('manifest.json'))==manifest
            assert z.read('icon.png')==(BUILD/'icon.png').read_bytes()
            assert z.read('9ba626afa44a3aa3.patch_0')==(BUILD/'data/9ba626afa44a3aa3.patch_0').read_bytes()
            assert 'THIRD_PARTY_NOTICES.md' in z.namelist()
            assert json.loads(z.read('project.json'))['resource']==META['resource']
            assert json.loads(z.read('config/identity.json'))['current_resource']==META['resource']
    report={'passed':True,'name':META['name'],'version':META['version'],'author':META['author'],
       'description_exact':True,'preview_pixel_identical':True,'preview_size':a.size,
       'code_labels_clean':True,'archive_resources':len(rows),
       'loader_resource':META['resource'],'performance_monitor_name':'hud_lite',
       'source_sha256':hashlib.sha256(source).hexdigest()}
    (REPORTS/'RELEASE_VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,indent=2))

if __name__=='__main__':verify(Path(sys.argv[1]) if len(sys.argv)>1 else None)
