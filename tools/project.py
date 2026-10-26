"""Shared paths and public metadata for HUD Lite build tools."""
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parents[1]
META=json.loads((ROOT/'project.json').read_text(encoding='utf-8'))
SRC=ROOT/'src'
BUILD=ROOT/'build'
REPORTS=ROOT/'reports'
CONFIG=ROOT/'config'
EXTERNAL=ROOT/'external'
ASSETS=ROOT/'assets'
ICON_PACK=ASSETS/'icon-pack'
PATCH='9ba626afa44a3aa3.patch_0'
LUA=0xa14e8dfa2cd117e2
TEXTURE=0xcd4238c6a0c69e32

def ensure_dirs():
    for path in [BUILD,REPORTS,ASSETS,ROOT/'dist']:path.mkdir(parents=True,exist_ok=True)
