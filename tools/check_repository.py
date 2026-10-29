"""Validate portable source syntax/metadata without requiring private inputs."""
import ast
import json
import re
import subprocess
import sys
from pathlib import Path
from project import ROOT,META

def public_files():
    names=['project.json','package.json','package-lock.json','requirements-dev.txt',
      'README.md','README.zh-CN.md','LICENSE','LICENSE.zh-CN.md',
      'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.zh-CN.md',
      'CHANGELOG.md','CHANGELOG.zh-CN.md','local.config.example.json','.gitignore','.gitattributes']
    paths=[ROOT/name for name in names]
    for folder in ['src','tools','tests','config','docs','.github']:
        paths.extend(p for p in (ROOT/folder).rglob('*') if p.is_file()
          and '__pycache__' not in p.parts and p.suffix not in ['.pyc','.log'])
    paths.extend(p for p in (ROOT/'third_party').rglob('*')if p.is_file())
    return sorted(set(paths))

def main():
    assert META['name']=='HUD Lite' and META['version']=='1.0.3'
    assert META['author']=='Alpha F. Bloodfallen'
    assert META['resource']=='mods/alpha_f_bloodfallen/hud_lite'
    identity=json.loads((ROOT/'config/identity.json').read_text(encoding='utf-8'))
    assert identity['current_resource']==META['resource']
    assert META['description_zh']=='适用于《绝地潜兵2》的可配置游戏内 HUD 模组，需要 chef loader 1.2.3+'
    assert META['description_en']=='A configurable in-game HUD mod for Helldivers 2. Requires Chef Loader 1.2.3+.'
    checked=0
    for path in public_files():
        assert path.exists(),path
        text=path.read_text(encoding='utf-8')
        if path.suffix=='.py':ast.parse(text,filename=path.name)
        elif path.suffix=='.json':json.loads(text)
        elif path.suffix=='.cjs':subprocess.run(['node','--check',str(path)],check=True)
        assert not re.search(r'(?<![A-Za-z0-9_])[A-Za-z]:[\\/]',text),'Absolute Windows path in '+str(path.relative_to(ROOT))
        assert not re.search(r'1\.12\.[0-9]+',text),'Private version label in '+str(path.relative_to(ROOT))
        checked+=1
    assert not (ROOT/'src/hud_lite.lua').exists(),'Combined upstream output must remain ignored in build/'
    subprocess.run(['node',str(ROOT/'tools/check_lua.cjs')],check=True)
    print('Repository checks passed:',checked,'public source files; private assets excluded')

if __name__=='__main__':main()
