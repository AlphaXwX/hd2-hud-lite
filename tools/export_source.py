"""Create source-only ZIP; never include local upstream code/game assets."""
import hashlib
import zipfile
from project import ROOT,META,ensure_dirs
from check_repository import public_files,main as check
import subprocess
import sys

def main():
    check()
    subprocess.run([sys.executable,str(ROOT/'tests/verify_docs.py')],check=True)
    ensure_dirs()
    target=ROOT/'dist'/f'HUD-Lite-{META["version"]}-Source.zip'
    files=public_files()
    with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for file in files:z.write(file,PathName(file))
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        for name in z.namelist():
            assert name.split('/')[0] not in {'external','assets','build','dist','reports','.venv','node_modules'}
            assert not name.endswith(('.dll','.exe','.png','.svg','.patch_0','.gpu_resources'))
    print('SOURCE EXPORT:',target)
    print('FILES:',len(files),'SHA256:',hashlib.sha256(target.read_bytes()).hexdigest())

def PathName(path):return path.relative_to(ROOT).as_posix()

if __name__=='__main__':main()
