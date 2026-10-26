"""Check all English/Chinese guides and links without local build inputs."""
from pathlib import Path
import hashlib
import json
import re
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PAIRS=[
 ('README.md','README.zh-CN.md'),
 ('CHANGELOG.md','CHANGELOG.zh-CN.md'),
 ('THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.zh-CN.md'),
 ('LICENSE','LICENSE.zh-CN.md'),
 ('docs/INDEX.md','docs/INDEX.zh-CN.md'),
 ('docs/BUILD.md','docs/BUILD.zh-CN.md'),
 ('docs/ARCHITECTURE.md','docs/ARCHITECTURE.zh-CN.md'),
 ('docs/SETTINGS.md','docs/SETTINGS.zh-CN.md'),
 ('docs/IDENTITY.md','docs/IDENTITY.zh-CN.md'),
]

def main(package=None):
    checked=[]
    for english,chinese in PAIRS:
        a,b=ROOT/english,ROOT/chinese
        assert a.is_file() and b.is_file(),(english,chinese)
        assert re.search(r'[\u4e00-\u9fff]',b.read_text(encoding='utf-8')),chinese
        for file in [a,b]:
            text=file.read_text(encoding='utf-8')
            assert not re.search(r'\b(?:0\.1\.[0-9]+|1\.10\.[0-9]+|1\.12\.[0-9]+)\b',text),file
            assert not re.search(r'\.patch_[0-9]|gpu_resources',text),file
            assert not re.search(r'(?<![A-Za-z0-9_])[A-Za-z]:[\\/]',text),file
            for target in re.findall(r'\]\(([^)]+)\)',text):
                if re.match(r'^[a-z]+://|^#',target):continue
                local=target.split('#',1)[0]
                if local:assert (file.parent/local).resolve().exists(),(file,target)
            checked.append(file.relative_to(ROOT).as_posix())
    notices=(ROOT/'THIRD_PARTY_NOTICES.md').read_text(encoding='utf-8')
    assert '## Artwork credit' in notices
    example=json.loads((ROOT/'local.config.example.json').read_text(encoding='utf-8'))
    assert set(example)=={'runtime_package','icon_package','quantity_icon_svg','preview_image'}
    if package:
        with zipfile.ZipFile(package) as z:
            assert z.testzip() is None
            for name in checked:assert z.read(name)==(ROOT/name).read_bytes(),name
    print(json.dumps({'passed':True,'document_pairs':len(PAIRS),'documents':len(checked),
      'local_links_verified':True,'historical_file_references_removed':True,
      'required_notices_retained':True,'package_verified':bool(package)},indent=2))

if __name__=='__main__':main(Path(sys.argv[1]) if len(sys.argv)>1 else None)
