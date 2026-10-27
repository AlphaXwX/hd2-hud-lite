"""Compose the single-file addon from first-party modules and generated data.

Every part comes from ``src/`` or from ``build/`` output produced by
``tools/emit_data.py`` and ``tools/icon_assets.py``. Nothing is sliced out of an
external file at build time.
"""
from pathlib import Path
import hashlib
import json
import sys
from project import ROOT,META,SRC,BUILD,REPORTS,CONFIG,ensure_dirs

CONSTANTS=('local LAYER_TRACK,LAYER_INNER_TRACK,LAYER_FILL,LAYER_INNER_FILL,LAYER_TEXT=905,904,906,907,910\n'
           'local loader_text_state\n')

DIAGNOSTICS='''local function describe_info()
  local parts={}
  if Fix.finite(S.ratio) and S.clock-S.at<=1 then
    if Fix.finite(S.hp) then parts[#parts+1]=string.format("HP %d",math.floor(S.hp+0.5))
    else parts[#parts+1]=string.format("HP %d%%",math.floor(S.ratio*100+0.5)) end
  end
  if Fix.finite(S.stamina) and S.clock-S.stamina_at<=1 then
    parts[#parts+1]=string.format("STA %d%%",math.floor(S.stamina*100+0.5))
  end
  return table.concat(parts,"  ")
end
'''

FRAGMENTS=['weapon','backpack','numbers','icon','iconposition','idle','squad']


def engine_bundle():
    """Assemble the engine model from first-party modules, bound once at load."""
    parts=[(SRC/'engine_core.lua'),(SRC/'identity_core.lua'),None,
           (SRC/'provider.lua'),(SRC/'model.lua')]
    text='-- Engine model: first-party modules bound once at load.\nlocal Engine = (function(SR, chef)\nlocal _G = {stingray=SR, chef=chef}\n'
    for part in parts:
        source=(BUILD/'generated_common.lua') if part is None else part
        text+=source.read_text(encoding='utf-8').rstrip()+'\n'
    text+='return {Identity=IdentityCore,Provider=Provider,Snapshot=Snapshot,Model=HudModel,Renderer=Renderer,Common=GeneratedCommon,Fragments=Fragments}\nend)(Native.sr, chef)\n'
    return text


def fragment_bundle():
    """Merge the feature fragments into the shared layout graph."""
    text='-- Feature fragments merged into the shared layout graph.\n'
    text+=(BUILD/'fragments.lua').read_text(encoding='utf-8').rstrip()+'\n'
    text+='local fragments = {}\nfor k,v in pairs(fragment_data) do fragments[k]=v end\n'
    text+='local generated = Engine.Fragments.merge(Engine.Common, function(name) return fragments[name] end)\n'
    return text


def visual_defaults(preset):
    """Render the published 1080p preset as the option-default table."""
    values=preset['saved_visual_overrides']

    def literal(value):
        if isinstance(value,bool):return 'true' if value else 'false'
        if isinstance(value,(int,float)):return str(value)
        return json.dumps(value)

    text='-- Author-tuned visual preset in 1080p design units; no forced settings.\nlocal PUBLISHED_VISUAL_DEFAULTS = {\n'
    text+=''.join('  ["'+key+'"]='+literal(value)+',\n' for key,value in sorted(values.items()))
    text+='}\n'
    return text


def main():
    ensure_dirs()
    preset=json.loads((CONFIG/'published_visual_defaults.json').read_text(encoding='utf-8'))
    surface=(SRC/'surface.lua').read_text(encoding='utf-8')
    assert surface.count('local OPTION_IDS = {}')==1
    surface=surface.replace('local OPTION_IDS = {}',visual_defaults(preset)+'local OPTION_IDS = {}')
    safety=('local IDENTITY_CURRENT = '+json.dumps(META['resource'])+'\n'
            +(SRC/'safety.lua').read_text(encoding='utf-8'))
    output=(surface
        +safety
        +(SRC/'options.lua').read_text(encoding='utf-8')
        +(SRC/'native.lua').read_text(encoding='utf-8')
        +engine_bundle()
        +fragment_bundle()
        +(BUILD/'weapon_catalog.lua').read_text(encoding='utf-8')
        +(SRC/'compatibility.lua').read_text(encoding='utf-8')
        +(BUILD/'icon_resources.lua').read_text(encoding='utf-8')
        +(SRC/'runtime.lua').read_text(encoding='utf-8')
        +(SRC/'vitals.lua').read_text(encoding='utf-8')
        +CONSTANTS
        +(SRC/'primitives.lua').read_text(encoding='utf-8')
        +(SRC/'draw.lua').read_text(encoding='utf-8')
        +DIAGNOSTICS
        +(SRC/'helpers.lua').read_text(encoding='utf-8')
        +(SRC/'frame.lua').read_text(encoding='utf-8')
        +(SRC/'main.lua').read_text(encoding='utf-8'))
    header=(f'-- HD2-Addon: {META["resource"]}\n'
            f'-- HD2-Requires: chef-shared-loader >= {META["minimum_loader_version"]}\n'
            f'-- {META["name"]} {META["version"]} by {META["author"]}\n'
            '-- Credits and distribution terms: see THIRD_PARTY_NOTICES.md.\n\n')
    output=header+output
    dest=BUILD/'hud_lite.lua'
    dest.write_bytes(output.encode('utf-8'))
    modules={path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(SRC.glob('*.lua'))}
    provenance={'project':META['name'],'version':META['version'],'author':META['author'],
      'source_sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),
      'modules':modules,
      'published_1080p_visual_defaults':preset,
      'changes':['single-file composition from first-party modules',
                 'bounded identity discovery with active-grip priority and search-only timing',
                 'restored local health/stamina fill aliases and ring easing',
                 'Chef-approved full animation state returns; body layer validated by snapshot',
                 'delta and observed lower-bound capacity shared by text/arc',
                 'consumables-first locked compact row; unlocked independent item positions',
                 'energy candidates routed to inner charge and outer cooling',
                 'hash-verified scalar heat/charging/RPM/reserve/self-booster fallback',
                 'independent RPM and reserve items in weapon settings row',
                 'unarmed HP alongside stamina; white interpolated animation reload',
                 'booster resources with verified ID 0..20 mapping',
                 'SVG-derived magazine texture beside reserve count',
                 'HP alongside stamina with or without a held weapon',
                 'author-tuned visual settings published as 1080p defaults; existing saves preserved',
                 'Chef-managed drawing only','safe lifecycle invalidation',
                 'zeroing authored capability or defined live selection; object-scoped proof',
                 'backpack direct geometry integrated with Ring layout controls',
                 'eleven contiguous searchable settings categories; saved positions retained',
                 'sample-driven static graphs; per-frame heat and charge interpolation',
                 'cached compact-row layout and bounded text-width metrics',
                 'visible alpha-bounded icon UVs shared by row advance and rendering',
                 'independent information-row anchor; actual pixel-height quantity alignment',
                 'held weapon continuity independent of unrelated multiplayer ownership churn',
                 'bounded host equipment candidates requiring declared local-owner match',
                 'nonreloadable declarations suppress reserve magazines but preserve loaded ammo']}
    (REPORTS/'SOURCE_PROVENANCE.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
    print('Assembled',dest,len(output.encode('utf-8')),'bytes')


if __name__=='__main__': main()
