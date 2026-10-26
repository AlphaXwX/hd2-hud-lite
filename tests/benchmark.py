"""Lua-only mock benchmark: NOT a game FPS or native engine timing claim."""
from pathlib import Path
import json
import hashlib
import statistics
import sys
import time

from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
FIXTURE=(ROOT/'tests/fixture.lua').read_text(encoding='utf-8')
SOURCE=(ROOT/'build/hud_lite.lua').read_text(encoding='utf-8')

def measure(extra):
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute(FIXTURE)
    l.globals().perf_clock=time.perf_counter
    f=l.eval('function(s) return assert(loadstring(s)) end')(SOURCE)
    l.globals().setup(f(l.globals().chef))
    l.execute("weapon('0x967a3fed');ticks(1);"+extra)
    value=l.execute('''
      F.logs={} F.draws={}
      local samples={}
      local before=T.Native.stats.scans
      local native=T.Native.stats.calls
      for i=1,1200 do
        local start=perf_clock()
        M.update(1/120)
        M.render()
        samples[i]=(perf_clock()-start)*1000
        F.draws={}
      end
      return samples,T.Native.stats.scans-before,T.Native.stats.calls-native
    ''')
    samples,scans,native=value
    data=sorted(samples.values())
    return {'frames':len(data),'mock_fps':120,'mean_ms':round(statistics.mean(data),5),
            'p95_ms':round(data[int(len(data)*0.95)],5),'max_ms':round(max(data),5),
            'new_type_checks':scans,'guarded_native_mock_calls':native}

report={'kind':'mock Lua-only benchmark (NOT gameplay FPS)',
 'source_sha256':hashlib.sha256(SOURCE.encode('utf-8')).hexdigest(),
 'steady_weapon':measure(''),
 'animation_reload':measure('''
 F.weapon.values['0xcd889dbc']=0
 F.anim={layer=1,s1=0,start=F.time,length=3}
 '''),
 'safe_scalar_energy':measure('''
 weapon('0x366d3622');T.Model.reset();T.Native.reset();T.S.session=1;T.S.peer='local'
 F.batch_skip=true;F.weapon.named.temperature=40;F.weapon.named.is_charging=true
 F.weapon.named.is_overheated=false;F.weapon.named.gbgqot6=0;ticks(0.5)
 '''),
 '150_unknown_objects':measure('''
 for i=1000,1149 do F.objects[i]={call='unknown',named={},values={}};F.owned['local'][#F.owned['local']+1]=i end
 '''),
 'notes':['Uses a real Lua 5.1 interpreter and mocked engine/drawing calls.',
          'Includes update and render; no real GPU or native engine cost.',
          'New type discovery has a count cap and an additional 1.5ms soft time cap per poll.',
          'Check Chef performance monitor in game for authoritative timings.']}
(ROOT/'reports/BENCHMARK.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
