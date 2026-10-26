"""Import private upstream packages locally; does not publish or edit games."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import struct
import zipfile
from PIL import Image
from project import ROOT,EXTERNAL,ASSETS,ICON_PACK,PATCH,LUA,ensure_dirs

def import_zip(label,source):
    source=Path(source).expanduser().resolve()
    destination=EXTERNAL/label;destination.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(source) as z:
        assert z.testzip() is None
        for member in z.infolist():
            path=(destination/member.filename).resolve()
            if not path.is_relative_to(destination.resolve()):raise ValueError('Unsafe archive path')
        z.extractall(destination)
    scripts=[]
    for file in destination.rglob('*.patch_*'):
        if file.name.endswith(('.stream','.gpu_resources')):continue
        blob=file.read_bytes()
        magic,ntypes,count=struct.unpack_from('<III',blob)
        if magic!=0xf0000011:continue
        for i in range(count):
            row=struct.unpack_from('<7Q6I',blob,72+32*ntypes+80*i)
            if row[1]!=LUA:continue
            length,version=struct.unpack_from('<II',blob,row[2])
            assert version==2 and length==row[7]-8
            text=blob[row[2]+8:row[2]+row[7]]
            target=file.parent/f'{row[0]:016x}.lua';target.write_bytes(text)
            scripts.append(target.relative_to(ROOT).as_posix())
    return {'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'scripts':scripts}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,help='JSON configuration with neutral input-role keys')
    for name in ['lite','icons029','magazine','preview']:parser.add_argument('--'+name,type=Path)
    args=parser.parse_args()
    if args.config:
        config_path=args.config.expanduser().resolve()
        config=json.loads(config_path.read_text(encoding='utf-8'))
        roles={'runtime_package':'lite','icon_package':'icons029',
          'quantity_icon_svg':'magazine','preview_image':'preview'}
        unknown=set(config)-set(roles)
        if unknown:parser.error('Unknown local input roles: '+', '.join(sorted(unknown)))
        for role,argument in roles.items():
            if role in config and getattr(args,argument) is None:
                path=Path(config[role]).expanduser()
                if not path.is_absolute():path=config_path.parent/path
                setattr(args,argument,path)
    ensure_dirs();provenance={}
    for name,label in [('lite','lite'),('icons029','029')]:
        path=getattr(args,name)
        if path:provenance[label]=import_zip(label,path)
    if args.magazine:
        data=args.magazine.read_bytes();assert b'<svg' in data
        (EXTERNAL/'Magazine_Icon.svg').write_bytes(data)
    if args.preview:
        data=args.preview.read_bytes();(EXTERNAL/'preview-original.png').write_bytes(data)
        with Image.open(args.preview) as im:im.convert('RGBA').save(ASSETS/'preview.png')
    if provenance:
        (EXTERNAL/'input-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
    stage_inputs()
    print('Private inputs imported. external/ and assets/ are excluded from GitHub export.')

def stage_inputs():
    """Copy the build-facing artwork out of external/ into assets/icon-pack/."""
    for name,target in [('Magazine_Icon.svg','magazine'),('preview-original.png','preview')]:
        source=EXTERNAL/name
        if source.is_file():
            (ICON_PACK/target).mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,ICON_PACK/target/name)

if __name__=='__main__':main()
