from pathlib import Path
import json
import hashlib
import sys
import time
import struct
import zipfile

from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
META=json.loads((ROOT/'project.json').read_text(encoding='utf-8'))
SOURCE=(ROOT/'build/hud_lite.lua').read_text(encoding='utf-8')
if len(sys.argv)>1:
    target=Path(sys.argv[1])
    if target.suffix=='.zip':
        with zipfile.ZipFile(target) as z:
            assert z.testzip() is None
            blob=z.read('9ba626afa44a3aa3.patch_0')
        magic,ntypes,count=struct.unpack_from('<III',blob)
        assert magic==0xf0000011
        found=[]
        for i in range(count):
            row=struct.unpack_from('<7Q6I',blob,72+32*ntypes+80*i)
            if row[1]==0xa14e8dfa2cd117e2:
                length,version=struct.unpack_from('<II',blob,row[2])
                assert length==row[7]-8 and version==2
                found.append(blob[row[2]+8:row[2]+8+length])
        assert len(found)==1
        assert found[0]==SOURCE.encode('utf-8'),'packaged source differs from tested source'
        SOURCE=found[0].decode('utf-8')
    else:
        SOURCE=target.read_text(encoding='utf-8')
FIXTURE=(ROOT/'tests/fixture.lua').read_text(encoding='utf-8')
results=[]

def env(before_load=None,merged_layout=True):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FIXTURE)
    lua.globals().TEST_SOURCE=SOURCE
    if merged_layout:
        # Existing geometry regressions use the old design fixture explicitly;
        # published preset tests below run with no pre-existing settings.
        lua.execute('''
          F.values['hud.lite.alpha']=100
          F.values['hud.lite.ammo_icon_size']=32
          F.values['hud.lite.fire_y']=-74
          F.values['hud.lite.firemode_size']=32
          F.values['hud.lite.info']=false
           F.values['hud.lite.info_x']=0;F.values['hud.lite.info_y']=-46
           F.values['hud.lite.row_x']=84
          F.values['hud.lite.inner_radius']=60;F.values['hud.lite.inner_thickness']=5
          F.values['hud.lite.number_size']=38;F.values['hud.lite.number_x']=0
          F.values['hud.lite.radius']=78;F.values['hud.lite.smoothing']=12
          F.values['hud.lite.span']=100;F.values['hud.lite.status_size']=14
          F.values['hud.lite.thickness']=8;F.values['hud.lite.y']=520
          F.values['hud.lite.zeroing_size']=32
        ''')
    if before_load:lua.execute(before_load)
    load=lua.eval('function(s) local f,e=loadstring(s); assert(f,e);return f end')
    mod=load(SOURCE)(lua.globals().chef)
    lua.globals().setup(mod)
    return lua

def test(name,code,before_load=None,merged_layout=True):
    lua=env(before_load,merged_layout)
    try:
        lua.execute(code+'\nassert_no_errors()')
        results.append({'name':name,'passed':True})
        print('PASS',name,flush=True)
    except Exception as e:
        print('FAIL',name,str(e),flush=True)
        print('LOGS',list(lua.globals().F.logs.values()))
        print('STATE',lua.eval('function() return T.S.channel,T.S.avatar,T.Model.identity.body_binding.status end')())
        raise


test('real Lua 5.1 loads complete feature rules without boot wrapper', '''
 assert(M.installed and M.version=='1.0.1')
 assert(G.identity.equipment and #G.relations>=7)
 assert(T.Model.identity.resolve and T.Model.provider.fill and T.Model.snapshot.assemble)
''')
test('active loader header and embedded fragments use the HUD Lite namespace', '''
 local header=TEST_SOURCE:match('^([^\\n]+)')
 assert(header=='-- HD2-Addon: mods/alpha_f_bloodfallen/hud_lite')
 for _,axis in ipairs(G.axes or {})do
  assert(axis.resource:find('mods/alpha_f_bloodfallen/hud_lite/',1,true)==1)
 end
''')
test('GOID zero player, real weapon chain, HP and stamina', '''
 weapon('0x967a3fed');ticks(1);rendered()
 assert(T.S.avatar==77 and T.S.player==0)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314,T.S.channel)
 assert(math.abs(T.S.ratio-0.8)<1e-8 and T.S.stamina==0.6)
 assert(shape(6) and shape(11),T.S.channel)
 assert(center()=='20/30',tostring(center()))
''')
test('ADS control lock keeps uniquely verified held weapon', '''
 weapon('0x967a3fed');ticks(1)
 F.objects[77].named.motion_enabled=false;F.objects[77].named.rotation_enabled=false
 F.weapon_unit.pos={x=1.2,y=0,z=0}
 ticks(0.3);rendered();assert(center()=='20/30',tostring(center()))
''')
test('valid zero magazine keeps track and shows zero, not HP', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=0;ticks(1);rendered()
 assert(center()=='0/30',tostring(center()))
 local n=0 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[5]<180 then n=n+1 end end
 assert(n>0)
''')
test('capacity comes from original data (10 not guessed 30)', '''
 weapon('0x8c0aee6e');F.weapon.values['0xd7a5d63e']=10;ticks(1);rendered()
 assert(center()=='10/10',tostring(center()))
''')
test('unarmed has no right tracks but retains HP and stamina', '''
 F.body.grip=0;ticks(1);rendered()
 assert(T.S.ratio and T.S.stamina)
 for _,d in ipairs(F.draws) do if d.kind=='arc' then assert(d.args[5]>180) end end
''')
test('weapon destroyed between polls clears all weapon outputs', '''
 weapon('0x967a3fed');ticks(1);F.objects[314]=nil;F.owned['local']={0};F.body.grip=0
 ticks(0.1);rendered();assert(not shape(6) and not shape(11))
''')
test('death and respawn reset body, weapon, charge, heat and avatar', '''
 weapon('0x967a3fed');ticks(1);F.objects[77].named.state=2;ticks(0.1);rendered()
 assert(not shape(6) and not shape(11));assert(T.S.ratio==nil)
 F.objects[78]=F.objects[77];F.objects[77]=nil;F.objects[78].named.state=0
 F.objects[0].named.baegche=78;ticks(1);rendered();assert(T.S.avatar==78 and shape(6))
''')
test('world change hides stale draw even before next update', '''
 weapon('0x967a3fed');ticks(1);F.world={};F.world_id=2;rendered();assert(#F.draws==0)
 F.mission=false;ticks(0.1);assert(not T.Model.ready and not T.S.avatar)
''')
test('Chef batch skip never bypassed or reset after a world change', '''
 weapon('0x967a3fed');F.batch_skip=true
 F.weapon.named['4fqtox']=7;F.weapon.named['gaj_1dw']=true
 ticks(1);rendered();assert(T.Native.blocked and F.raw_batches==0)
 assert(center()=='7/30',tostring(center()))
 local count=F.counts.batch
 F.world={};F.world_id=2;ticks(1);assert(F.counts.batch==count)
''')
test('numbers choice reproduces original rounds plus reserve', '''
 weapon('0x967a3fed');set('hud.lite.number_mode',2);ticks(1);rendered()
 local center_ammo,reserve=false,false
 for _,d in ipairs(F.draws)do if d.kind=='text' then
  center_ammo=center_ammo or d.args[3]=='20'
  reserve=reserve or d.args[3]=='4'
 end end
 assert(center_ammo and reserve,'original ammo/reserve values not drawn')
''')
test('idle faint and full brightness options are independent', '''
 weapon('0x967a3fed');set('hud.lite.idle',2);ticks(6);rendered()
 local s=shape(6);assert(s and s.state.level=='idle')
 set('hud.lite.idle',1);ticks(0.1);rendered();assert(center()=='20/30')
''')
test('reload stage produces a separate progress ring and never adds rounds', '''
 weapon('0x967a3fed');ticks(1);F.weapon.values['0xcd889dbc']=1
 F.anim={layer=1,s1=0,start=F.time,length=3};ticks(0.7);rendered()
 assert(shape(7) and shape(7).fraction>0)
 assert(center()=='20/30',tostring(center()))
 F.anim=nil;F.weapon.values['0xcd889dbc']=0;ticks(0.1);assert(not shape(7))
''')
test('charge dry/reset and original safe-mode clamp', '''
 weapon('0x26acc614');F.weapon.values['0xd7a5d63e']=1;F.weapon.values['0x49c250a6']=5
 F.weapon.values['0x3132608f']=true;ticks(4);assert(shape(7),'charge missing')
 F.weapon.values['0xd7a5d63e']=0;ticks(0.1);assert(not shape(7),'dry charge visible')
''')
test('global opacity applies to track as well as fill', '''
 weapon('0x967a3fed');set('hud.lite.alpha',50);ticks(1);rendered()
 local n=0 for _,d in ipairs(F.draws) do if d.kind=='arc' then
   assert(d.args[7][4]<=128);if d.args[8]==905 then n=n+1 end
 end end assert(n>0)
''')
test('textures are drawn using Chef original atlas UV without white rectangle', '''
 weapon('0x967a3fed');set('hud.lite.self_booster',false);set('hud.lite.magazine_icon',false);ticks(1);rendered()
 local n=0 for _,d in ipairs(F.draws)do if d.kind=='icon' then assert(d.args[1]=='254deec0e6c38888');n=n+1 end end
 assert(n>0)
 F.icon_fail=true;rendered();for _,d in ipairs(F.draws)do assert(d.kind~='rect')end
''')
test('health and stamina options can be turned off separately', '''
 weapon('0x967a3fed');set('hud.lite.health',false);ticks(1);rendered()
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[5]>180 then assert(d.args[8]~=906)end end
 assert(T.S.stamina==0.6)
''')
test('no raw native GUI lifetime or destroy calls on shutdown', '''
 weapon('0x967a3fed');ticks(1);M.shutdown();F.stopped=true
 for _,ns in pairs(stingray)do if type(ns)=='table' then for k,v in pairs(ns)do if type(v)=='function' then ns[k]=function()error('native after teardown')end end end end end
 M.shutdown();M.update(1);M.render();assert(T.S.stopped)
''')

test('backpack ring works independently when unarmed', '''
 F.body.grip=0
 local hash
 for k,row in pairs(G.identity.backpacks) do if row.arc_max and row.arc_max>0 then hash=k;break end end
 assert(hash,'no backpack rule')
 local pack=backpack(hash);pack.values['0x69889752']=1;ticks(2);rendered()
 assert(T.Model.resolved.backpack,T.S.channel)
 assert(shape(1),'backpack gauge missing')
 assert(not shape(6),'unarmed right ring')
''')
test('backpack replacement after previously finding no pack is discovered', '''
 weapon('0x967a3fed');ticks(1)
 local hash for k,row in pairs(G.identity.backpacks)do if row.arc_max and row.arc_max>0 then hash=k;break end end
 backpack(hash);ticks(2);assert(T.Model.resolved.backpack,'pack negative cache stale')
''')
test('squad booster, dead icon, disconnect and reconnect', '''
 weapon('0x967a3fed')
 local boost
 for k in pairs(G.identity.booster) do boost=tonumber(k);break end
 assert(boost)
 F.objects[88]={call='un6y1d',named={booster=boost,gbgqot6=0},values={}}
 F.owned.other={88};F.peers={'local','other'};ticks(2);rendered()
 assert(shape(3),'squad icon missing')
 F.objects[88].named.gbgqot6=256;ticks(0.2)
 assert(shape(3) and shape(3).name=='skull_icon','death icon not updated '..tostring(shape(3) and shape(3).name))
 F.objects[88]=nil;F.peers={'local'};ticks(0.6);assert(not shape(3))
 F.objects[89]={call='un6y1d',named={booster=boost,gbgqot6=0},values={}}
 F.owned.other={89};F.peers={'local','other'};ticks(1);assert(shape(3),'reconnect missing')
''')
test('original thermal model feeds an outer cooling fraction without magazine capacity', '''
 weapon('0x42a6b5ba');F.weapon.values['0xd7a5d63e']=nil
 F.weapon.values['0x04ec5b95']=nil;F.weapon.values['0xe525fa9c']=nil
 F.weapon.values['0xa5023836']=50;F.weapon.values['0x3132608f']=true
 ticks(1);assert(shape(6),'heat arc missing')
 local hot=shape(6).fraction
 F.weapon.values['0x3132608f']=false;F.weapon.values['0xa5023836']=30;ticks(1)
 assert(shape(6) and shape(6).fraction>hot,'outer cooling fraction did not recover')
''')
test('selected multi-magazine group sums only its authored slots', '''
 local hash
 for k,row in pairs(G.identity.equipment)do if row.rounds_groups then hash=k;break end end
 assert(hash)
 weapon(hash);F.weapon.values['0x04ec5b95']=4;F.weapon.values['0xe525fa9c']=7
 F.weapon.values['0xa74ef0d5']=0;F.weapon.values['0x4a893e74']=true
 ticks(1)
 local group=G.identity.equipment[hash].rounds_groups[1]
 local sum=0 for _,i in ipairs(group)do sum=sum+(i==1 and 4 or 7)end
 assert(T.Model.window.cells.ammo==sum,tostring(T.Model.window.cells.ammo)..'/'..sum)
''')
test('unknown capacity never uses stale old weapon capacity', '''
 weapon('0x967a3fed');ticks(1)
 local hash
 for k,row in pairs(G.identity.equipment)do
  if not row.no_hand and not G.authored_base['WeaponMagazineComponentData.capacity'][k]
    and not G.authored_base['WeaponRoundsComponentData.magazine_capacity'][k] then hash=k;break end
 end
 assert(hash)
 weapon(hash);ticks(2);rendered()
 assert(not (center() or ''):find('/30',1,true),tostring(center()))
''')
test('GOID reused as a different weapon type is revalidated', '''
 weapon('0x967a3fed');ticks(1)
 weapon('0x8c0aee6e');F.weapon.values['0xd7a5d63e']=3;ticks(2);rendered()
 assert(center()=='3/10',tostring(center()))
''')
test('duplicate body positions and duplicate weapons fail closed', '''
 weapon('0x967a3fed')
 F.units['4d1c334d294dfa97'][2]={pos={x=0,y=0,z=0},alive=true,grip=10}
 ticks(1);assert(not T.Model.resolved.hand_weapon,'ambiguous body accepted')
''')
test('fixed new-type scan hard bound applies with 150 unknown owned objects', '''
 weapon('0x967a3fed')
 for i=1000,1149 do F.objects[i]={call='unknown',named={},values={}};F.owned['local'][#F.owned['local']+1]=i end
 set('hud.lite.scan_budget',16)
 for i=1,20 do
   local before=T.Native.stats.scans
   ticks(0.05)
 assert(T.Native.stats.scans-before<=40,'scan limit exceeded')
 end
''')
test('sub-poll frames perform no native discovery or field reads', '''
 weapon('0x967a3fed');ticks(1)
 ticks(0.05)
 local before=T.Native.stats.calls
 M.update(0.001);M.render()
 assert(T.Native.stats.calls==before,'render/intermediate update touched engine')
''')
test('transient declaration failure recovers without restart', '''
 weapon('0x967a3fed');F.info_fail=true;ticks(0.7)
 F.info_fail=false;ticks(2);assert(shape(11),'declaration stuck missing')
''')

test('lost player avatar link hides old live avatar rather than freezing it', '''
 weapon('0x967a3fed');ticks(1)
 F.objects[0].named.baegche=nil;ticks(0.1);rendered()
 assert(not T.Model.ready and T.S.avatar==nil and #F.draws==0,'stale avatar retained')
''')
test('fresh zero health is shown and never treated as a missing reading', '''
 weapon('0x967a3fed');F.objects[77].values['0xcb0453ea']=0;F.objects[77].named.health=0
 ticks(1);assert(T.S.ratio==0 and T.S.hp==0)
''')
test('numeric network field ids map to the same declaration slots', '''
 weapon('0x967a3fed')
 for _,info in pairs(F.declarations)do for _,d in ipairs(info.fields)do d.id=tonumber(d.id)end end
 -- Fixture batch must still feed by the original hex keys, like the engine.
 stingray.GameSession.game_object_field_batched=function(_,id,out)
   local obj=F.objects[id];if not obj then return nil end
   for i,d in ipairs(F.declarations[obj.call].fields)do out[i]=obj.values[T.Model.hash(d.id)]end
   return out
 end
 -- Native.batch retains the sandbox function captured at initialization; that
 -- function looks up current declarations. Supply both keys for its mock.
 for _,obj in pairs(F.objects)do
   local additions={} for k,v in pairs(obj.values)do if type(k)=='string' then additions[tonumber(k)]=v end end
   for k,v in pairs(additions)do obj.values[k]=v end
 end
 ticks(1);rendered();assert(center()=='20/30',tostring(center()))
''')
test('infinite health/stamina and NaN ammo never reach drawing', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=0/0
 F.objects[77].named.stamina=math.huge;F.objects[77].named.health=math.huge
 F.objects[77].values['0xcb0453ea']=math.huge;ticks(1);rendered()
 assert(T.S.ratio==nil and T.S.stamina==nil)
 for _,d in ipairs(F.draws)do for _,v in ipairs(d.args)do if type(v)=='number' then assert(v==v and v~=math.huge and v~=-math.huge)end end end
''')
test('underbarrel link changes while the parent stays alive', '''
 weapon('0x967a3fed');ticks(1)
 local hash,row=next(G.identity.underbarrels);assert(hash)
 F.declarations[row.call]=F.fields(F.weapon_fields)
 F.objects[600]={call=row.call,named={underbarrel_goid=32767},values={}}
 local parent={goid=314,type='0x967a3fed'}
 F.weapon.named.underbarrel_goid=600
 -- Refill declaration and frame caches after the changed link is introduced.
 F.declarations[F.weapon.call]=F.fields(F.weapon_fields);T.Native.reset();T.Native.begin()
 local first=T.Model.identity:follow('under_memo','under_cached',1,parent,T.Model.identity.find_underbarrel)
 assert(first and first.goid==600)
 F.objects[601]={call=row.call,named={underbarrel_goid=32767},values={}}
 F.weapon.named.underbarrel_goid=601;T.Native.begin()
 local second=T.Model.identity:follow('under_memo','under_cached',1,parent,T.Model.identity.find_underbarrel)
 assert(second and second.goid==601,'parent link retained stale child')
''')
test('all authored weapon rule rows can be processed without errors', '''
 local total=0
 for hash,row in pairs(G.identity.equipment)do
   if not row.no_hand then
     weapon(hash)
     T.Model.reset();T.Native.reset();T.S.session=1;T.S.peer='local'
     ticks(0.2);rendered();total=total+1
   end
 end
 assert(total>=100,'incomplete weapon table')
''')

test('addon chunk argument works with inherited library/engine sandbox globals', '''
 local env=setmetatable({}, {__index=_G});env._G=env
 local source=TEST_SOURCE
 local chunk=assert(loadstring(source))
 setfenv(chunk,env)
 local addon=chunk(chef)
 assert(addon.installed and addon.update and addon.render)
 addon.update(0.05);addon.render();addon.shutdown()
''')
test('backpack linked shield capacity and charge use the original pack-link rules', '''
 F.body.grip=0
 local pack_hash,pack_book
 for k,row in pairs(G.identity.backpacks)do if row.call then pack_hash,pack_book=k,row;break end end
 assert(pack_hash)
 local pack=backpack(pack_hash)
 local link=G.identity.pack_link_fields[1]
 assert(link and link.call and link.hash)
 F.declarations[pack.call].fields[#F.declarations[pack.call].fields+1]={id=link.hash}
 pack.named[link.call]=600
 local shield=G.identity.pack_links['0x2cd705d1']
 F.declarations[shield.call]=F.fields({'0x1ad6d70f','0x6fee6b03'})
 F.objects[600]={call=shield.call,named={},values={['0x1ad6d70f']=500,['0x6fee6b03']=false}}
 ticks(3)
 local resolved=T.Model.resolved
 assert(resolved.pack_link and resolved.pack_link.goid==600,'shield link missing')
 assert(T.Model.window.cells.pack_arc_max==1000,'shield capacity lost')
 assert(shape(1) and math.abs(shape(1).fraction-0.5)<0.001,'shield resource fraction wrong')
''')
test('active charge takes priority over a concurrent reload stage', '''
 weapon('0x26acc614');F.weapon.values['0xd7a5d63e']=1
 F.weapon.values['0x3132608f']=true;F.weapon.values['0xcd889dbc']=1
 F.weapon.values['0x49c250a6']=5;ticks(1)
 assert(shape(7) and shape(7).column=='trigger_held','reload hid charge')
 assert(T.Model.reload==nil)
''')
test('heat-based charge adds a Lite-style inner progress ring', '''
 local hash='0x366d3622'
 assert(hash);weapon(hash)
 F.weapon.values['0xd7a5d63e']=nil;F.weapon.values['0x04ec5b95']=nil;F.weapon.values['0xe525fa9c']=nil
 F.weapon.values['0x88b7cf6d']=true;F.weapon.values['0xa5023836']=40;ticks(1)
 assert(shape(6) and shape(7),'heat-based charge inner ring missing')
 assert(shape(7).column=='energy_charge' and shape(7).maximum==3)
 assert(shape(7).fraction>0 and shape(7).fraction<0.5,'charge must use its own elapsed interval')
''')


test('health and stamina emit actual colored fill arcs, not tracks alone', '''
 weapon('0x967a3fed');ticks(0.2);rendered()
 local hp,sta=false,false
 for _,d in ipairs(F.draws)do
   local a=d.args
   if d.kind=='arc' and a[5]>180 then
     if a[8]==906 then hp=true;assert(math.abs(a[6]-a[5]-80)<0.001)end
     if a[8]==907 then sta=true;assert(math.abs(a[6]-a[5]-60)<0.001)end
   end
 end
 assert(hp and sta,'fill calls were never emitted')
''')
test('SAFE SCALAR still renders health and stamina fills without weapon', '''
 F.body.grip=0;F.batch_skip=true;ticks(0.2);rendered()
 local hp,sta=false,false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[5]>180 then
   hp=hp or d.args[8]==906;sta=sta or d.args[8]==907
 end end
 assert(hp and sta and T.Native.blocked)
''')
test('native setup time cannot starve first weapon discovery', '''
 local clock=0;local real_call=chef.call_kind
 os.clock=function()return clock end
 chef.call_kind=function(path,kind,...)
   if path~='GameSession.game_object_is_type' then clock=clock+0.002 end
   return real_call(path,kind,...)
 end
 weapon('0x967a3fed');ticks(0.15);rendered()
 assert(shape(11) and center()=='20/30','setup work consumed discovery budget')
''')
test('first weapon display arrives within bounded few polling intervals', '''
 weapon('0x967a3fed')
 local appeared
 for i=1,10 do ticks(0.05);if shape(11) then appeared=i;break end end
 assert(appeared and appeared<=4,'cold weapon recognition too slow '..tostring(appeared))
''')
test('expanded magazine shares a stable denominator with the ammo arc', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=50;ticks(0.3);rendered()
 assert(center()=='50/50',tostring(center()))
 F.weapon.values['0xd7a5d63e']=46;ticks(0.1);rendered()
 assert(center()=='46/50',tostring(center()))
 assert(math.abs(shape(6).fraction-46/50)<0.0001)
 F.weapon.values['0xd7a5d63e']=20;ticks(0.1);rendered()
 assert(center()=='20/50','denominator shrank as rounds fired')
''')
test('expanded magazine observed under SAFE SCALAR no longer uses thirty', '''
 weapon('0x967a3fed');F.batch_skip=true
 F.weapon.named['4fqtox']=46;F.weapon.named['gaj_1dw']=true
 ticks(0.3);rendered();assert(center()=='46/46',tostring(center()))
 F.weapon.named['4fqtox']=40;ticks(0.1);rendered();assert(center()=='40/46')
 assert(math.abs(shape(6).fraction-40/46)<0.001)
''')
test('capacity delta IdString64 wrapper resolves true fifty-round capacity', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=46
 G.authored_delta['WeaponMagazineComponentData.capacity']['0x123456789abcdef0']=50
 F.weapon.values['0x98b4aaf0']={'#ID[123456789abcdef0]'}
 ticks(0.3);rendered();assert(center()=='46/50',tostring(center()))
 assert(math.abs(shape(6).fraction-46/50)<0.001)
''')
test('chamber plus one does not inflate a thirty-round magazine', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=30;F.weapon.values['0x4a893e74']=false
 ticks(0.3);rendered();assert(center()=='31/30',tostring(center()))
 F.weapon.values['0xd7a5d63e']=29;F.weapon.values['0x4a893e74']=1
 ticks(0.1);rendered();assert(center()=='30/30',tostring(center()))
''')
test('Lite ammo arc eases across renders while number updates immediately', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=30;ticks(0.3);rendered()
 F.weapon.values['0xd7a5d63e']=15;ticks(0.05);rendered()
 assert(center()=='15/30');assert(T.S.shown_a>0.5 and T.S.shown_a<1,'ammo arc stepped')
 local before=T.S.shown_a
 M.update(1/120);rendered();assert(T.S.shown_a<before and T.S.shown_a>0.5)
''')
test('smoothing zero immediately snaps to real ammo ratio', '''
 weapon('0x967a3fed');set('hud.lite.smoothing',0)
 F.weapon.values['0xd7a5d63e']=30;ticks(0.2);rendered()
 F.weapon.values['0xd7a5d63e']=15;ticks(0.05);rendered();assert(T.S.shown_a==0.5)
''')
test('animation reload uses elapsed clip time rather than configured timer', '''
 weapon('0x967a3fed');ticks(0.2);F.weapon.values['0xcd889dbc']=1
 F.anim={layer=1,s1=0,elapsed=0,length=3};ticks(0.1)
 F.anim.elapsed=1.4;ticks(0.05);rendered()
 assert(T.Model.resolved.action.animation and not T.Model.resolved.action.estimated)
 assert(math.abs(shape(7).fraction-0.5)<0.001,tostring(shape(7).fraction))
 F.anim.elapsed=0.7;ticks(0.05);assert(not shape(7),'original rewind cut ignored')
 F.anim=nil;F.weapon.values['0xcd889dbc']=0;ticks(0.05);assert(not shape(7),'interruption retained reload')
''')
test('paused animation does not advance with wall-clock time', '''
 weapon('0x967a3fed');F.weapon.values['0xcd889dbc']=1
 F.anim={layer=1,s1=0,elapsed=0.7,length=3};ticks(0.2)
 local before=shape(7).fraction;ticks(1);assert(math.abs(shape(7).fraction-before)<0.0001)
''')
test('missing or skipped animation hides progress without timer fabrication', '''
 weapon('0x967a3fed');F.weapon.values['0xcd889dbc']=1;ticks(0.2)
 assert(not shape(7),'fabricated reload without animation')
 F.anim={layer=1,s1=0,elapsed=1,length=3};F.anim_skip=true;ticks(0.1)
 assert(not shape(7))
 F.anim_skip=false;F.layer_skip=true;ticks(0.1);assert(not shape(7))
''')
test('unreported body layer eleven is never queried', '''
 weapon('0x967a3fed');F.weapon.values['0xcd889dbc']=1
 G.identity.equipment['0x967a3fed'].reload={[11]={[0]={clip=3,tail=0}}}
 F.anim={layer=11,s0=99,s1=99,s2=99,s3=99,elapsed=1,length=3};ticks(0.2)
 assert(not shape(7) and not F.counts.animation_layer,'blind layer 11 query')
''')
test('visible weapon icons compact left to right when an item is disabled', '''
 weapon('0x967a3fed');set('hud.lite.magazine_icon',false);set('hud.lite.self_booster',false);ticks(0.3)
 T.Model.commands={
  {kind='icon',key=8,side='right',name='firemode_auto'},
  {kind='icon',key=9,side='right',name='firemode_single'},
  {kind='icon',key=10,side='right',name='firemode_auto'}}
 rendered()
 local icons={} for _,d in ipairs(F.draws)do if d.kind=='icon' then icons[#icons+1]=d end end
 assert(#icons==3)
 local x1,x3=icons[1].args[6],icons[3].args[6]
 local held={} for i,v in ipairs(T.Model.commands)do held[i]=v end
 set('hud.lite.function_icon',false);M.update(0.001);T.Model.commands=held;rendered()
 icons={} for _,d in ipairs(F.draws)do if d.kind=='icon' then icons[#icons+1]=d end end
 assert(#icons==2 and icons[1].args[6]==x1 and icons[2].args[6]<x3,'hidden item left a hole')
''')
test('fire mode visibility and position do not control zeroing or ammo icons', '''
 weapon('0x967a3fed');set('hud.lite.magazine_icon',false);set('hud.lite.self_booster',false);ticks(0.3)
 set('hud.lite.row_unlock',true)
 set('hud.lite.firemode',false);set('hud.lite.ammo_icon_x',77);M.update(0.001)
 T.Model.commands={
  {kind='icon',key=8,side='right',name='firemode_auto'},
  {kind='icon',key=9,side='right',name='firemode_single'},
  {kind='icon',key=10,side='right',name='firemode_auto'}}
 rendered()
 local icons={} for _,d in ipairs(F.draws)do if d.kind=='icon' then icons[#icons+1]=d end end
  assert(#icons==2 and T.Model.row_layout.by_role.ammo_icon.left==T.Model.row_layout.left+77)
''')

test('late authoritative delta corrects an observed partial-magazine lower bound', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=46;ticks(0.2);rendered()
 assert(center()=='46/46')
 G.authored_delta['WeaponMagazineComponentData.capacity']['0x1111222233334444']=50
 F.weapon.values['0x98b4aaf0']={'#ID[1111222233334444]'}
 ticks(0.1);rendered();assert(center()=='46/50')
 F.weapon.values['0xd7a5d63e']=20;ticks(0.1);rendered();assert(center()=='20/50')
''')
test('expanded capacity is not reused after switching to another weapon', '''
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=50;ticks(0.3)
 weapon('0x8c0aee6e');F.weapon.values['0xd7a5d63e']=8;ticks(0.3);rendered()
 assert(center()=='8/10',tostring(center()))
''')
test('switch to a previously seen weapon does not wait for negative scan TTL', '''
 weapon('0x967a3fed');ticks(0.3)
 weapon('0x8c0aee6e');F.weapon.values['0xd7a5d63e']=7;ticks(0.3);rendered();assert(center()=='7/10')
 weapon('0x967a3fed');F.weapon.values['0xd7a5d63e']=12
 local ready=false
 for i=1,4 do ticks(0.05);rendered();if center()=='12/30' then ready=true;break end end
 assert(ready,'cached type miss delayed switch')
''')
test('wrong animation state never reads an arbitrary available layer', '''
 weapon('0x967a3fed');F.weapon.values['0xcd889dbc']=1
 F.anim={layer=1,s1=999,elapsed=1,length=3};ticks(0.3)
 assert(not shape(7) and not F.counts.animation_layer)
''')
test('invalid animation duration never manufactures a fraction', '''
 weapon('0x967a3fed');F.weapon.values['0xcd889dbc']=1
 F.anim={layer=1,s1=0,elapsed=1,length=-1};ticks(0.3)
 assert(not shape(7))
''')

test('original reload uses BODY layer eleven and emits the inner fill', '''
 weapon('0x967a3fed');set('hud.lite.reload_smoothing',0);ticks(0.2)
 F.anim={layer=1,s1=0,elapsed=2.5,body_elapsed=0.2,length=3}
 -- Known weapon rig is sufficient even when replicated stage still says zero.
 F.weapon.values['0xcd889dbc']=0;ticks(0.05)
 assert(T.Model.identity.action_span and T.Model.identity.action_span.base==0.2)
 F.anim.body_elapsed=1.5;ticks(0.05);rendered()
 assert(shape(7) and math.abs(shape(7).fraction-0.5)<0.001)
 assert(T.Model.animation.unit==F.body and T.Model.animation.layer==11)
 local fill=false
 for _,d in ipairs(F.draws)do
  if d.kind=='arc' and d.args[8]==908 and d.args[5]<180 then
    fill=true;assert(math.abs(d.args[6]-d.args[5]-50)<0.001)
  end
 end
 assert(fill,'no inner reload fill emitted')
''')
test('body snapshot retains twelve layers after Chef four-return truncation', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 local native=T.Native.animation_snapshot(F.body)
 assert(native and native.n==12 and native[12]==7,'body state list truncated')
 F.anim.body_elapsed=0.7;ticks(0.05);assert(shape(7))
''')
test('Chef animation skip does not fall through to the full-return read', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=1,length=3}
 local previous=chef.call
 chef.call=function(path,...)
   if path=='Unit.animation_get_state' then return nil,'skipped' end
   return previous(path,...)
 end
 local reads=F.counts.animation_states or 0
 ticks(0.2)
 assert((F.counts.animation_states or 0)==reads,'native called after guard skip')
 assert(not shape(7))
''')
test('body missing layer eleven prevents layer-info call', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_count=4,body_elapsed=1,length=3};ticks(0.2)
 assert(not shape(7) and not F.counts.animation_layer)
''')
test('original clip length change invalidates the active reload span', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 F.anim.body_elapsed=0.5;ticks(0.05);assert(shape(7))
 F.anim.length=4;F.anim.body_elapsed=0.6;ticks(0.05)
 assert(not shape(7),'original clip-change cut missing')
''')
test('runtime uses original Identity.action_of rather than a substitute', '''
 local original=T.Model.identity.action_of
 local calls=0
 T.Model.identity.action_of=function(self,hand,body,window)
   calls=calls+1;assert(body==F.body)
   return original(self,hand,body,window)
 end
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 F.anim.body_elapsed=0.5;ticks(0.05)
 assert(calls>0 and shape(7))
''')

test('SAFE SCALAR energy charge uses original roles and emits inner charge plus outer cooling', '''
 weapon('0x366d3622');F.batch_skip=true
 F.weapon.named.temperature=40;F.weapon.named.is_charging=true;F.weapon.named.is_overheated=false
 F.weapon.named.a70n1_=false;F.weapon.named.gbgqot6=0
 set('hud.lite.smoothing',0);ticks(0.3);rendered()
 assert(T.Native.blocked and F.raw_batches==0)
 assert(T.Model.energy and shape(6) and shape(7),'energy command missing')
 assert(shape(6).column=='energy_cooling' and shape(7).column=='energy_charge')
 local outer,inner=false,false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[5]<180 then
   if d.args[8]==906 then outer=true end
   if d.args[8]==908 then inner=true end
 end end
 assert(outer and inner,'energy fill calls missing')
 assert(shape(7).maximum==3 and shape(7).fraction>0,'charge interval missing')
''')
test('energy cooldown grows outer progress and stops charge inner when released', '''
 weapon('0x366d3622');F.weapon.values['0xa5023836']=80;F.weapon.values['0x88b7cf6d']=true
 ticks(0.2);local before=shape(6).fraction
 F.weapon.values['0x88b7cf6d']=false;F.weapon.values['0xa5023836']=20;ticks(0.5);rendered()
 assert(shape(6) and shape(6).fraction>before,'outer cooldown did not recover')
 assert(not shape(7) or shape(7).column~='energy_charge','released charge persisted')
''')
test('original heat candidate survives ammo-first slot selection', '''
 weapon('0x366d3622');F.weapon.values['0xa5023836']=50;F.weapon.values['0x88b7cf6d']=true
 F.weapon.values['0xd7a5d63e']=2;ticks(0.3)
 assert(shape(6) and shape(6).column=='energy_cooling')
 assert(shape(7) and shape(7).column=='energy_charge')
''')
test('boolean and zero-one charging reads behave identically', '''
 weapon('0x366d3622');F.batch_skip=true
 F.weapon.named.temperature=25;F.weapon.named.is_charging=1;F.weapon.named.is_overheated=0
 ticks(0.3);assert(shape(7) and T.Model.window.reads['hand-weapon']['0x88b7cf6d']==true)
 F.weapon.named.is_charging=0;ticks(0.1);assert(not shape(7))
''')
test('missing temperature hides cooling without suppressing a valid charge interval', '''
 weapon('0x366d3622');F.batch_skip=true;F.weapon.named.is_charging=true
 ticks(0.3);rendered();assert(T.Model.energy==nil)
 assert(shape(7) and shape(7).column=='energy_charge')
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[5]<180 then assert(d.args[8]~=906,'cooling fill fabricated')end end
''')
test('SAFE SCALAR adjustable RPM draws original atlas icon', '''
 weapon('0xe645b6ee');F.batch_skip=true
 F.weapon.named['4fqtox']=30;F.weapon.named['gaj_1dw']=true
 F.weapon.named.fire_mode=1;F.weapon.named.v7xdy8=760;ticks(0.3);rendered()
 assert(T.Model.window.cells.rof_icon=='rof_medium','original RPM mapping not used')
 local cell=G.identity.icon_cells.rof_medium;local found=false
 local metric=up(T.Model.draw_consumables,'IconAssets').row_metrics.rof_medium
 for _,d in ipairs(F.draws)do if d.kind=='icon' and math.abs(d.args[2]-metric.u0)<1e-9 then found=true end end
 assert(found,'RPM atlas draw missing')
''')
test('RPM stays independent of ammo and zeroing icon toggles', '''
 weapon('0xe645b6ee');F.weapon.values['0x4cbcc2a2']=760;F.weapon.values['0x49c250a6']=1
 set('hud.lite.function_icon',false);set('hud.lite.zeroing',false);ticks(0.3);rendered()
 local rpm=T.Model.row_layout.by_role.rof
 assert(rpm and rpm.left>=T.Model.row_layout.left,'RPM hidden by unrelated toggle')
''')
test('SAFE SCALAR draws own booster from the original self-booster signal', '''
 weapon('0x967a3fed');F.batch_skip=true
 F.objects[0].named.booster=3;F.objects[0].named.gbgqot6=0;ticks(0.3);rendered()
 assert(shape(2) and shape(2).name=='booster_3','self booster missing')
 local texture='1fe1aed14c4ddde7';local found=false
 for _,d in ipairs(F.draws)do if d.kind=='icon' and d.args[6]<100 and d.args[7]<200 then
   found=true;assert(d.args[1]==texture and d.args[2]==0 and d.args[4]==1)
 end end
 assert(found,'self booster draw missing')
''')
test('own booster option does not depend on squad option or weapon', '''
 F.batch_skip=true;F.body.grip=0;F.objects[0].named.booster=2;F.objects[0].named.gbgqot6=0
 set('hud.lite.squad',false);ticks(0.3);rendered();assert(shape(2))
 local found=false for _,d in ipairs(F.draws)do if d.kind=='icon' then found=true end end
 assert(found)
''')
test('reserve magazine scalar is drawn in the weapon settings row not below ammo', '''
 weapon('0x967a3fed');F.batch_skip=true
 F.weapon.named['4fqtox']=20;F.weapon.named['gaj_1dw']=true;F.weapon.named.B9h6f9a4=4
 ticks(0.3);rendered();assert(T.Model.window.cells.reserve==4)
 local found=false
 for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]=='4' then
    found=true;assert(math.abs(d.args[2]-(520-74-10.5))<0.01,'reserve not in settings row')
 end end
 assert(found)
''')
test('zero reserve count remains visible instead of disappearing', '''
 weapon('0x967a3fed');F.batch_skip=true
 F.weapon.named['4fqtox']=20;F.weapon.named['gaj_1dw']=true;F.weapon.named.B9h6f9a4=0
 ticks(0.3);rendered();assert(T.Model.reserve_text=='0')
 local found=false for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]=='0' then found=true end end
 assert(found)
''')
test('reserve fallback uses original spare role when magazines unavailable', '''
 weapon('0x967a3fed');F.batch_skip=true;F.weapon.named.jCr15Dyv=25
 ticks(0.3);assert(T.Model.window.cells.reserve==25 and T.Model.reserve_text=='25')
''')
test('unarmed health moves beside stamina without a central health number', '''
 F.body.grip=0;ticks(0.3);rendered()
 local row=false
 for _,d in ipairs(F.draws)do if d.kind=='text' then
   if d.args[3]:find('HP ',1,true) and d.args[3]:find('STA 60%',1,true) then
     row=true;assert(math.abs(d.args[2]-(520-46))<0.01)
   end
   assert(d.args[3]~='100' and d.args[3]~='80','old central HP retained')
 end end
 assert(row,'health/stamina row missing')
''')
test('reload interpolation advances smoothly between samples and draws pure white', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 F.anim.body_elapsed=0.1;ticks(0.05);rendered()
 local first=T.Model.reload_visual and T.Model.reload_visual.fraction
 assert(first)
 M.update(1/120);rendered();local next=T.Model.reload_visual.fraction
 assert(next>first,'between-sample reload did not move')
 local fill=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==908 then
  fill=true;local c=d.args[7];assert(c[1]==255 and c[2]==255 and c[3]==255,'reload is not white')
 end end assert(fill)
''')
test('paused animation stops render interpolation at the actual sampled fraction', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 F.anim.body_elapsed=0.2;ticks(0.05);rendered()
 ticks(0.1);rendered();local p=T.Model.reload_visual.fraction
 M.update(0.005);rendered();assert(T.Model.reload_visual.fraction==p)
''')

test('every original adjustable-rate weapon maps all its authored RPM icons', '''
 local checked=0
 for hash,row in pairs(G.identity.equipment)do if row.rof then
   weapon(hash);T.Model.reset();T.Native.reset();T.S.session=1;T.S.peer='local'
   for value,name in pairs(row.rof)do
     F.weapon.values['0x4cbcc2a2']=tonumber(value);F.weapon.values['0x49c250a6']=1
     ticks(0.3);assert(T.Model.window.cells.rof_icon==name,hash..' RPM '..value)
     checked=checked+1
   end
 end end
 assert(checked>=20,'incomplete original rate mappings')
''')
test('reserve row is independent of center-number visibility and shows live changes', '''
 weapon('0x967a3fed');set('hud.lite.number',false);ticks(0.3);rendered()
 assert(T.Model.reserve_text=='4')
 F.weapon.values['0xec64918b']=3;ticks(0.1);rendered()
 local found=false for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]=='3' then found=true end end
 assert(found and T.Model.reserve_text=='3')
''')
test('unarmed transition clears energy and reserve row data', '''
 weapon('0x366d3622');F.weapon.values['0xa5023836']=40;F.weapon.values['0x88b7cf6d']=true
 ticks(0.3);assert(T.Model.energy)
 F.owned['local']={0};F.objects[314]=nil;F.body.grip=0;ticks(0.1);rendered()
 assert(T.Model.energy==nil and T.Model.reserve_text==nil)
 for _,d in ipairs(F.draws)do if d.kind=='arc' then assert(d.args[5]>180)end end
''')
test('guarded scalar fallback only reads fields declared by the matched weapon type', '''
 weapon('0x967a3fed');F.batch_skip=true
 local fields={} for _,d in ipairs(F.declarations[F.weapon.call].fields)do
  if d.id~='0xa5023836' and d.id~='0x88b7cf6d' and d.id~='0x4cbcc2a2' then fields[#fields+1]=d end
 end F.declarations[F.weapon.call].fields=fields
 F.bad_names={temperature=true,is_charging=true,v7xdy8=true};ticks(0.3)
 assert(not F.counts['field:temperature'] and not F.counts['field:is_charging'] and not F.counts['field:v7xdy8'])
''')
test('render interpolation performs no native reads and never calls original animation again', '''
 weapon('0x967a3fed');ticks(0.2)
 F.anim={layer=1,s1=0,body_elapsed=0,length=3};ticks(0.05)
 F.anim.body_elapsed=0.2;ticks(0.05);rendered()
 local calls=T.Native.stats.calls
 local anim=F.counts.animation_states
 for i=1,5 do M.update(0.001);rendered() end
 assert(T.Native.stats.calls==calls and F.counts.animation_states==anim)
''')

test('all twenty boosters and empty slot use the exact resource mapping', '''
 local expected={
 [0]='902efa9d47e3d8c9','17e268a78bb5420c','ec8137869a17dbae','1fe1aed14c4ddde7',
 'cde44d5aee63712f','518491a9c9e86443','fe76d5b290f40a0a','cd39462c36c91ffd',
 'ed645fa0125d5d67','f6a8f23557c372e7','65b1f4450d9c7128','73ee5c3bdafc3887',
 'd4dd2890d5e2b5d1','43fd0f86069de4e7','706ff804b5c4a02c','75fad34c7a79dd6c',
 '6ea75d114d0dc717','b96f91b35fd9f4d6','da7877c0968d1b61','8b2399333c50c065','1dde867d0793a7de'}
 F.body.grip=0;F.batch_skip=true;F.objects[0].named.gbgqot6=0
 for index=0,20 do
   F.objects[0].named.booster=index;ticks(0.15);rendered()
   assert(shape(2) and shape(2).name=='booster_'..index,'missing ID '..index)
   local found=false
   for _,d in ipairs(F.draws)do if d.kind=='icon' and d.args[6]<100 then
     assert(d.args[1]==expected[index],'wrong 029 texture for '..index)
     assert(d.args[2]==0 and d.args[3]==0 and d.args[4]==1 and d.args[5]==1)
     found=true
   end end
   assert(found,'no draw for '..index)
 end
''')
test('new twentieth booster renders on teammates using original squad relation', '''
 F.body.grip=0;F.batch_skip=true
 F.objects[88]={call='un6y1d',named={booster=20,gbgqot6=0},values={}}
 F.owned.other={88};F.peers={'local','other'};ticks(1);rendered()
 assert(shape(3) and shape(3).name=='booster_20')
 local found=false for _,d in ipairs(F.draws)do
  if d.kind=='icon' and d.args[1]=='1dde867d0793a7de' then found=true end
 end assert(found)
 F.objects[88].named.gbgqot6=256;ticks(0.1);rendered()
 assert(shape(3) and shape(3).name=='skull_icon','death replacement lost')
''')
test('magazine SVG texture is adjacent to reserve count in the same row', '''
 weapon('0x967a3fed');ticks(0.3);rendered()
 local icon,number
 for _,d in ipairs(F.draws)do
   if d.kind=='icon' and d.args[1]==up(T.Model.draw_reserve,'IconAssets').magazine then icon=d end
  if d.kind=='text' and d.args[3]=='4' then number=d end
 end
 assert(icon and number,'magazine/count pair missing')
 assert(icon.args[1]~='254deec0e6c38888')
 assert(icon.args[2]>0 and icon.args[4]<1,'transparent padding was not excluded')
 assert(number.args[1]>=icon.args[6]+icon.args[8],'count overlaps image')
 assert(math.abs((icon.args[7]+icon.args[9]/2)-(number.args[2]+10.5))<0.01)
''')
test('magazine icon toggle preserves reserve count and no native image fallback', '''
 weapon('0x967a3fed');set('hud.lite.magazine_icon',false);ticks(0.3);rendered()
 local found=false for _,d in ipairs(F.draws)do
  if d.kind=='text' and d.args[3]=='4' then found=true end
   if d.kind=='icon' and d.args[1]==up(T.Model.draw_reserve,'IconAssets').magazine then error('magazine drawn while disabled')end
 end assert(found)
''')
test('zero reserve still has magazine icon and literal zero count', '''
 weapon('0x967a3fed');F.weapon.values['0xec64918b']=0;ticks(0.3);rendered()
 local icon,zero=false,false
 for _,d in ipairs(F.draws)do
   if d.kind=='icon' and d.args[1]==up(T.Model.draw_reserve,'IconAssets').magazine then icon=true end
  if d.kind=='text' and d.args[3]=='0' then zero=true end
 end assert(icon and zero)
''')
test('missing reserve data draws neither magazine icon nor fake count', '''
 weapon('0x967a3fed');F.weapon.values['0xec64918b']=nil;F.weapon.values['0x9a34c336']=nil
 ticks(0.3);rendered();assert(T.Model.reserve_text==nil)
 for _,d in ipairs(F.draws)do
   assert(not(d.kind=='icon' and d.args[1]==up(T.Model.draw_reserve,'IconAssets').magazine),'unknown reserve drew icon')
 end
''')
test('magazine and 029 booster alpha both honor global opacity', '''
 weapon('0x967a3fed');F.objects[0].values['0x3b12bd49']=3;F.objects[0].values['0xcd889dbc']=0
 set('hud.lite.alpha',50);ticks(0.3);rendered()
 local n=0 for _,d in ipairs(F.draws)do if d.kind=='icon' then
  assert(d.args[10][4]<=128,'icon ignored opacity');n=n+1
 end end assert(n>=2)
''')
test('image binding failure keeps reserve text without white rectangle', '''
 weapon('0x967a3fed');F.icon_fail=true;ticks(0.3);rendered()
 local found=false for _,d in ipairs(F.draws)do
  if d.kind=='text' and d.args[3]=='4' then found=true end
  assert(d.kind~='rect')
 end assert(found)
''')

test('armed HP uses the same health and stamina row as unarmed', '''
 weapon('0x967a3fed');ticks(0.3);rendered()
 local armed,ax,ay
 for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]:find('HP ',1,true)then
  armed,ax,ay=d.args[3],d.args[1],d.args[2]
 end end
 assert(armed=='HP 100  STA 60%','held weapon hid HP: '..tostring(armed))
 F.owned['local']={0};F.objects[314]=nil;F.body.grip=0;ticks(0.1);rendered()
 local unarmed
 for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]:find('HP ',1,true)then
  unarmed=d.args[3];assert(d.args[1]==ax and d.args[2]==ay,'HP row shifted on unequip')
 end end
 assert(unarmed==armed)
''')
test('HP stays beside stamina for energy weapon and zero health readings', '''
 weapon('0x366d3622');F.weapon.values['0xa5023836']=30;F.weapon.values['0x88b7cf6d']=true
 F.objects[77].values['0xcb0453ea']=0;F.objects[77].named.health=0
 ticks(0.3);rendered()
 local found=false for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]=='HP 0  STA 60%' then found=true end end
 assert(found and T.Model.energy,'energy/zero-HP display missing')
''')
test('stale health is not displayed as live HP while holding weapon', '''
 weapon('0x967a3fed');ticks(0.3)
 F.objects[77].values['0xcb0453ea']=nil;F.objects[77].named.health=nil
 ticks(1.2);rendered()
 for _,d in ipairs(F.draws)do if d.kind=='text'then assert(not d.args[3]:find('HP ',1,true))end end
''')
test('author defaults never overwrite existing saved visual settings', '''
 assert(F.values['hud.lite.x']==180 and F.values['hud.lite.y']==538)
 assert(F.values['hud.lite.number_x']==199 and F.values['hud.lite.number_y']==53)
 assert(F.values['hud.lite.info_x']==-84 and F.values['hud.lite.info_y']==-95)
 assert(F.values['hud.lite.fire_y']==-111 and F.values['hud.lite.icon_position']==2)
 assert(F.saved.layout1080_positions_v1125==nil)
 assert(F.values['hud.lite.radius']==193 and F.values['hud.lite.scale']==1.4)
 assert(F.values['hud.lite.alpha']==45 and F.values['hud.lite.number_size']==28)
 assert(F.values['hud.lite.manual_capacity']==true and F.values['hud.lite.reserves']==false)
 F.body.grip=0;ticks(0.2);rendered()
 for _,d in ipairs(F.draws)do if d.kind=='arc'then assert(d.args[1]==960+180*1.4 and d.args[2]==538*1.4)end end
''', '''
 F.values['hud.lite.x']=180;F.values['hud.lite.y']=538
 F.values['hud.lite.number_x']=199;F.values['hud.lite.number_y']=53
 F.values['hud.lite.info_x']=-84;F.values['hud.lite.info_y']=-95
 F.values['hud.lite.fire_y']=-111;F.values['hud.lite.icon_position']=2
 F.values['hud.lite.radius']=193;F.values['hud.lite.scale']=1.4
 F.values['hud.lite.alpha']=45;F.values['hud.lite.number_size']=28
 F.values['hud.lite.manual_capacity']=true;F.values['hud.lite.reserves']=false
''')
test('addon reload never resets subsequent personal position edits', '''
 set('hud.lite.x',123);set('hud.lite.y',555)
 local fresh=assert(loadstring(TEST_SOURCE))(chef)
 assert(F.values['hud.lite.x']==123 and F.values['hud.lite.y']==555,'repeated reset lost user edits')
 fresh.shutdown()
''')
test('author 1080p preset scales to other resolutions without changing display mode', '''
 F.width,F.height=2560,1440;weapon('0x967a3fed');ticks(0.3);rendered()
 local ring=false
 for _,d in ipairs(F.draws)do if d.kind=='arc'then
  ring=true;assert(math.abs(d.args[1]-1280)<0.001 and math.abs(d.args[2]-538*4/3)<0.001)
 end end
 assert(ring and F.width==2560 and F.height==1440)
''',merged_layout=False)

test('fresh install uses the captured author 1080p visual configuration', '''
 assert(F.defaults['hud.lite.y']==538 and F.defaults['hud.lite.radius']==189)
 assert(F.defaults['hud.lite.inner_radius']==182 and F.defaults['hud.lite.span']==73)
 assert(F.defaults['hud.lite.thickness']==6.5 and F.defaults['hud.lite.inner_thickness']==3.5)
 assert(F.defaults['hud.lite.alpha']==45 and F.defaults['hud.lite.smoothing']==27)
 assert(F.defaults['hud.lite.number_x']==199 and F.defaults['hud.lite.number_size']==28)
 assert(F.defaults['hud.lite.info_x']==-84 and F.defaults['hud.lite.info_y']==-95)
 assert(F.defaults['hud.lite.fire_y']==-111)
 assert(F.defaults['hud.lite.firemode_size']==76 and F.defaults['hud.lite.ammo_icon_size']==96)
 assert(F.defaults['hud.lite.zeroing_size']==40)
 assert(F.defaults['hud.lite.manual_capacity']==nil and F.defaults['hud.lite.debug']==nil)
 assert(next(F.values)==nil and next(F.saved)==nil,'startup wrote settings')
 weapon('0x967a3fed');ticks(0.3);rendered()
 local row,fill=false,false
 for _,d in ipairs(F.draws)do
  if d.kind=='text' and d.args[3]=='HP 100  STA 60%' then
   row=true;assert(d.args[2]==443,'preset HP baseline wrong')
  end
  if d.kind=='arc' and d.args[8]==906 and d.args[5]>180 then
   fill=true;assert(d.args[1]==960 and d.args[2]==538)
   assert(d.args[3]==185.75 and d.args[4]==192.25,'preset radii wrong')
  end
 end
 assert(row and fill)
''',merged_layout=False)

test('release menu registers no diagnostics probes manual overrides or internal tuning', '''
 local removed={'debug','probe','status','status_size','status_x','status_y','manual_capacity',
   'ammo_cap','scan_budget','body_radius','weapon_auto','max_hp','deep_scan',
   'stamina_from_exertion','reload_time','info','font','fire_size','icon_size'}
 for _,name in ipairs(removed)do assert(F.defaults['hud.lite.'..name]==nil,'test setting registered: '..name)end
 assert(F.defaults['hud.lite.vitals_text']==true)
 assert(F.defaults['hud.lite.reload_animation']==true,'normal reload control removed')
 assert(F.defaults['hud.lite.radius']==189,'normal geometry control removed')
''')
test('release menu has only current product display labels', '''
 local forbidden={'test','debug','probe','unverified','manual capacity','scan budget','body search','status line'}
 for id,spec in pairs(F.specs)do
   local label=spec.label:lower()
   for _,word in ipairs(forbidden)do assert(not label:find(word,1,true),id..' testing label '..word)end
   assert(not spec.label:find('%d+%.%d+%.%d+'),'historical label in menu')
 end
 assert(#F.specs['hud.lite.number_mode'].choices==2)
''')
test('saved diagnostic switches never draw internal status text or state logs', '''
 weapon('0x967a3fed');ticks(0.3);rendered()
 for _,d in ipairs(F.draws)do if d.kind=='text'then
  assert(not d.args[3]:find('SAFE SCALAR',1,true) and not d.args[3]:find('HAND-',1,true))
 end end
 for _,line in ipairs(F.logs)do
  assert(not line:find('state ratio=',1,true) and not line:find('avatar batched:',1,true))
 end
''', '''
 F.values['hud.lite.debug']=true;F.values['hud.lite.probe']=true;F.values['hud.lite.status']=true
''')
test('removed information overlay cannot force a disabled vitals row on', '''
 weapon('0x967a3fed');set('hud.lite.vitals_text',false);ticks(0.3);rendered()
 for _,d in ipairs(F.draws)do if d.kind=='text'then
  assert(not d.args[3]:find('HP ',1,true) and not d.args[3]:find('STA ',1,true))
 end end
''', "F.values['hud.lite.info']=true")
test('saved manual capacity and reader test switches no longer change sampled values', '''
 weapon('0x967a3fed')
 G.authored_base['WeaponMagazineComponentData.capacity']['0x967a3fed']=nil
 G.authored_base['WeaponRoundsComponentData.magazine_capacity']['0x967a3fed']=nil
 ticks(0.3);rendered()
 assert(T.Model.resolved.hand_weapon,'removed reader test switch disabled identification')
 assert(T.Model.window.cells.ammo_max==nil,'hidden manual override used')
 assert(center()=='20',tostring(center()))
''', '''
 F.values['hud.lite.manual_capacity']=true;F.values['hud.lite.ammo_cap']=123
 F.values['hud.lite.weapon_auto']=false;F.values['hud.lite.body_radius']=0
''')
test('fixed discovery budget ignores stale saved test tuning', '''
 weapon('0x967a3fed')
 for i=1000,1149 do F.objects[i]={call='unknown',named={},values={}};F.owned['local'][#F.owned['local']+1]=i end
 for i=1,8 do local before=T.Native.stats.scans;ticks(0.05)
  assert(T.Native.stats.scans-before<=40,'stale testing budget was used')
 end
''', "F.values['hud.lite.scan_budget']=100000")

test('unreadable Chef state fails closed for risky native channels', '''
 weapon('0x967a3fed');ticks(0.3)
 assert(F.raw_batches==0,'missing protection state allowed batch retry')
 assert((F.counts.animation_states or 0)==0)
''', '''
 chef.log_directory='test-settings';io={open=function()return nil end}
''')

test('SAFE SCALAR directly fed weapon shows its verified backpack ammo and full capacity', '''
 weapon('0x15f1a9f0');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc','0x49c250a6'})
 local pack=backpack('0x6c17c3b1');pack.named.c60sehb=420
 ticks(2);rendered()
 assert(T.Model.resolved.hand_weapon,'fed weapon not identified')
 assert(T.Model.pack_ammo and T.Model.pack_ammo.value==420,'pack source not selected')
 assert(center()=='420/500',tostring(center()))
 assert(math.abs(shape(6).fraction-420/500)<0.001,'right ammo arc not pack based')
 assert(T.Native.blocked and F.raw_batches==0,'batch protection lost')
''')
test('minigun and belt-fed launcher have their own matching supply backpack denominators', '''
 weapon('0xb3246bb7');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x32fd58bf');p.named.c60sehb=900;ticks(2);rendered()
 assert(center()=='900/1000',tostring(center()))
''')
test('belt-fed launcher uses its one hundred twenty round supply pack', '''
 weapon('0x6b47e064');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x139293f3');p.named.c60sehb=75;ticks(2);rendered()
 assert(center()=='75/120',tostring(center()))
''')
test('zero pack ammo remains a real zero with known capacity and track', '''
 weapon('0x15f1a9f0');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x6c17c3b1');p.named.c60sehb=0;ticks(2);rendered()
 assert(center()=='0/500',tostring(center()))
 assert(T.Model.pack_ammo and T.Model.pack_ammo.value==0)
''')
test('dropped supply pack cannot keep stale weapon ammo visible', '''
 weapon('0x15f1a9f0');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x6c17c3b1');p.named.c60sehb=300;ticks(2);assert(T.Model.pack_ammo)
 p.named.enabled_mask=2;ticks(0.2);rendered()
 assert(T.Model.pack_ammo==nil,'dropped supply retained')
 assert(not shape(11) and not shape(6),'stale fed ammo remains')
''')
test('unrelated supply backpack never replaces weapon ammo', '''
 weapon('0x15f1a9f0');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x32fd58bf');p.named.c60sehb=900;ticks(2);rendered()
 assert(T.Model.pack_ammo==nil and not shape(11),'wrong backpack supplied weapon')
''')
test('foreign owner supply is rejected even if local carry mask says worn', '''
 weapon('0x15f1a9f0');F.batch_skip=true
 F.declarations[F.weapon.call]=F.fields({'0x788b9753','0xc3a3f66c','0xcd889dbc'})
 local p=backpack('0x6c17c3b1');p.named.c60sehb=450;p.named.g5g7b9d='other'
 F.declarations[p.call].fields[#F.declarations[p.call].fields+1]={id='0x3ccffa7f'}
 ticks(2);assert(T.Model.pack_ammo==nil)
''')
test('backpack-reloaded weapon keeps local magazine and shows pack reserve separately', '''
 weapon('0xb2bfd847');F.weapon.values['0xd7a5d63e']=1
 local p=backpack('0x9f9ef431');p.values['0x69889752']=5;ticks(2);rendered()
 assert(T.Model.window.cells.ammo==1,'pack replaced loaded shell')
 assert(T.Model.window.cells.reserve==5 and T.Model.reserve_text=='5','pack reserve missing')
 assert(T.Model.pack_ammo==nil)
''')
test('all newly seeded handheld types have deterministic ammo or energy display', '''
 local types={'0x17b02218','0x2166c7a1','0x30294946','0x56e55184','0x8fcdd35c','0xa4eff4fa','0xf94a73b3'}
 for _,hash in ipairs(types)do
  weapon(hash);F.weapon.values['0xd7a5d63e']=3
  T.Model.reset();T.Native.reset();T.S.session=1;T.S.peer='local'
  ticks(1)
  assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.type==hash,hash..' not identified '..T.S.channel)
  assert(shape(11),hash..' ammo number missing')
 end
''')
test('current catalog field names are used only after declaration validation', '''
 weapon('0x30294946');F.batch_skip=true
 F.weapon.named.hhrfiqc=7;F.weapon.named.q6nx6da=true
 F.weapon.named.n5jmvf=0;F.weapon.named.enabled_mask=nil
 ticks(1);rendered()
 assert(center()=='7/10',tostring(center()))
''')
test('catalog type alias works when old stand-in type call no longer resolves', '''
 weapon('0x967a3fed');F.batch_skip=true
 local row=G.identity.equipment['0x967a3fed']
 local catalog=up(T.Model.pack_supply,'Compatibility').weapons['0x967a3fed']
 assert(catalog and catalog.call~=F.weapon.call)
 F.declarations[catalog.call]=F.declarations[F.weapon.call];F.declarations[F.weapon.call]=nil
 F.weapon.call=catalog.call;F.weapon.named.hhrfiqc=9;F.weapon.named.q6nx6da=true
 ticks(1);rendered();assert(center()=='9/30',tostring(center()))
''')
test('additional catalog hand pose is recognized without replacing authored grip', '''
 weapon('0x56e55184');F.body.grip=36;ticks(1)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.type=='0x56e55184',T.S.channel)
''')
test('catalog without a verified pose is not silently promoted into equipment', '''
 local n=0 for hash,row in pairs(G.identity.equipment)do if row.catalog_type then n=n+1 end end
 assert(n==9,'unverified poses were admitted: '..n)
''')
test('new-type extension keeps fixed discovery budget with unknown owned objects', '''
 weapon('0x30294946')
 for i=1000,1149 do F.objects[i]={call='unknown',named={},values={}};F.owned['local'][#F.owned['local']+1]=i end
 for i=1,15 do local before=T.Native.stats.scans;ticks(0.05)
  assert(T.Native.stats.scans-before<=40,'catalog increased search budget')
 end
''')

test('new catalog energy charge progresses even when replicated heat stays at rest', '''
 weapon('0x17783758');F.batch_skip=true
 F.weapon.named.v0zaf3=5;F.weapon.named.sadziaa=true;F.weapon.named.bybgjfa=false
 ticks(0.3);assert(T.Model.energy and shape(7),'new energy type missing charge')
 local before=shape(7).fraction;ticks(0.3)
 assert(shape(7).fraction>before,'charge did not advance between static heat reads')
 F.weapon.named.sadziaa=false;ticks(0.1);assert(not shape(7),'released charge persisted')
''')
test('cold-adjusted rate maps to authored RPM setting rather than a nonexistent setting', '''
 weapon('0xe645b6ee');F.weapon.values['0x4cbcc2a2']=760*0.9
 ticks(0.3);assert(T.Model.window.cells.rof_icon=='rof_medium','cold rate icon missing')
''')
test('unrecognized adjustable RPM is not assigned an arbitrary icon', '''
 weapon('0xe645b6ee');F.weapon.values['0x4cbcc2a2']=123
 ticks(0.3);assert(T.Model.window.cells.rof_icon==nil)
''')

test('new catalog weapon without rig reads actual body elapsed and clip length', '''
 weapon('0x30294946');ticks(0.3)
 F.weapon.values['0xcd889dbc']=1;F.anim={body_elapsed=1,length=4};ticks(0.05);rendered()
 assert(shape(7) and math.abs(shape(7).fraction-0.25)<0.001)
 assert(T.Model.animation.unit==F.body and T.Model.animation.layer==11)
 F.anim.body_elapsed=2;ticks(0.05);assert(math.abs(shape(7).fraction-0.5)<0.001)
 local white=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==908 then
   local c=d.args[7];white=c[1]==255 and c[2]==255 and c[3]==255
 end end
 assert(white,'catalog reload fill is not white')
''')
test('catalog reload requires positive declared stage and clears on interruption', '''
 weapon('0x30294946');F.anim={body_elapsed=1,length=4};ticks(0.2);assert(not shape(7))
 F.weapon.values['0xcd889dbc']=1;ticks(0.1);assert(shape(7))
 F.weapon.values['0xcd889dbc']=0;ticks(0.1);assert(not shape(7))
 F.weapon.values['0xcd889dbc']=-1;ticks(0.1);assert(not shape(7))
 F.weapon.values['0xcd889dbc']=0/0;ticks(0.1);assert(not shape(7))
''')
test('catalog reload respects Chef skips and missing body-layer proof', '''
 weapon('0x30294946');F.weapon.values['0xcd889dbc']=1
 F.anim={body_elapsed=1,length=4,body_count=4};ticks(0.3)
 assert(not shape(7) and not F.counts.animation_layer)
 F.anim.body_count=12;F.layer_skip=true;ticks(0.1);assert(not shape(7))
 F.layer_skip=false;F.anim_skip=true;ticks(0.1);assert(not shape(7))
 F.anim_skip=false;ticks(0.1);assert(shape(7))
''')
test('catalog reload pause rewind and clip replacement never invent elapsed time', '''
 weapon('0x30294946');F.weapon.values['0xcd889dbc']=1
 F.anim={body_elapsed=1,length=4};ticks(0.3);local p=shape(7).fraction
 ticks(0.4);assert(shape(7).fraction==p)
 F.anim.body_elapsed=0.5;ticks(0.05);assert(not shape(7),'rewind not cut')
 ticks(0.05);assert(shape(7))
 F.anim.length=6;ticks(0.05);assert(not shape(7),'clip replacement not cut')
''')
test('catalog reload scalar aliases work without weapon resource unit', '''
 weapon('0x17b02218');F.batch_skip=true
 F.weapon.named.gbgqot6=1;F.anim={body_elapsed=0.75,length=3};ticks(0.3)
 assert(shape(7) and math.abs(shape(7).fraction-0.25)<0.001)
 assert(F.raw_batches==0 and T.Model.identity.hand_unit==nil)
''')
test('all added reload-stage catalog types use body animation fallback', '''
 local C=up(T.Model.pack_supply,'Compatibility')
 for hash,row in pairs(G.identity.equipment)do
  if row.catalog_type and C.weapons[hash].fields.reload_stage then
   weapon(hash);F.weapon.values['0xcd889dbc']=1;F.anim={body_elapsed=1,length=4}
   T.Model.reset();T.Native.reset();ticks(0.5)
   assert(shape(7) and shape(7).column=='action_elapsed',hash..' reload missing')
  end
 end
''')
test('charge remains available without temperature or a heat candidate', '''
 weapon('0x17783758');F.batch_skip=true;F.weapon.named.sadziaa=true
 ticks(0.4)
 assert(T.Model.energy==nil and shape(7) and shape(7).column=='energy_charge')
 assert(shape(7).fraction>0 and shape(7).maximum==1.6)
 F.weapon.named.sadziaa=false;ticks(0.1);assert(not shape(7))
''')
test('existing cooldown charge progresses on static heat independently from cooling', '''
 weapon('0x366d3622');F.batch_skip=true
 F.weapon.named.v0zaf3=5;F.weapon.named.sadziaa=true;F.weapon.named.bybgjfa=false
 ticks(0.3);local p=shape(7).fraction;local cooling=shape(6).fraction
 ticks(0.3);assert(shape(7).fraction>p and shape(7).maximum==3)
 assert(shape(6).column=='energy_cooling' and shape(6).maximum==100)
 assert(math.abs(shape(6).fraction+shape(7).fraction-1)>0.01,'cooling copied the charge fraction')
''')
test('cooldown-only energy hides reserves and any spare-number draw command', '''
 for _,hash in ipairs({'0x17783758','0x366d3622'})do
  weapon(hash);F.weapon.values['0xa5023836']=30
  T.Model.reset();T.Native.reset();ticks(0.4);rendered()
  assert(G.identity.equipment[hash].cooldown_only and T.Model.reserve_text==nil)
  assert(T.Model.window.cells.reserve==nil and not T.Model.animation)
  for _,cmd in ipairs(T.Model.commands)do
   assert(not(cmd.kind=='number' and (cmd.column=='reserve' or cmd.column=='pack_spare')))
  end
 end
''')
test('hybrid overheat weapons keep spare magazines and animation reload', '''
 for _,hash in ipairs({'0xd100e0c8','0x42a6b5ba','0x3622f8dc'})do
  weapon(hash);F.weapon.values['0xa5023836']=40
  T.Model.reset();T.Native.reset();ticks(0.4)
  assert(not G.identity.equipment[hash].cooldown_only,hash..' treated as cooldown-only')
  assert(T.Model.reserve_text=='4',hash..' reserve hidden')
 end
 F.weapon.values['0xcd889dbc']=1;F.anim={body_elapsed=1,length=4};ticks(0.1)
 assert(shape(7) and shape(7).column=='action_elapsed')
''')
test('unknown heat range is hidden until a real overheat reference is sampled', '''
 weapon('0x3622f8dc');F.weapon.values['0xa5023836']=25;ticks(0.3)
 assert(T.Model.window.cells.heat_max==nil and T.Model.energy==nil)
 F.weapon.values['0xa5023836']=160;F.weapon.values['0xf6275c53']=true;ticks(0.1)
 assert(T.Model.window.cells.heat_max==160 and T.Model.energy)
 assert(T.Model.window.cells.heat_range_source=='observed-overheat')
 F.weapon.values['0xf6275c53']=false;F.weapon.values['0xa5023836']=80;ticks(0.5)
 assert(shape(6) and shape(6).column=='energy_cooling' and shape(6).fraction>0)
 T.Model.reset();assert(T.Model.heat_limit==nil)
''')
test('known cooling continues while cooldown-only weapon is overheated', '''
 weapon('0x17783758');F.weapon.values['0xa5023836']=80;F.weapon.values['0xf6275c53']=true
 ticks(0.2);local p=shape(6).fraction
 F.weapon.values['0xa5023836']=40;ticks(0.5)
 assert(shape(6).fraction>p,'overheated flag pinned cooling to empty')
''')
test('backpack fill is the separate third ring on the right', '''
 set('hud.lite.backpack_radius',45);set('hud.lite.backpack_thickness',5);ticks(0.3)
 T.Model.commands={{kind='arc',key=1,side='left',fraction=0.5,alpha=1,state={tone='normal'}}}
 rendered();local found=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==909 then
  found=true;assert(d.args[5]<180,'pack ring remains on left')
  assert(d.args[4]<57.5,'pack overlaps reload ring')
 end end
 assert(found)
''')
test('declared consumable scalar reads draw attached stim and grenade textures', '''
 ticks(0.3);rendered()
 assert(T.Model.items.stims==3 and T.Model.items.grenades==4)
 local icons=up(T.Model.draw_consumables,'IconAssets');local cura,grenade=false,false
 for _,d in ipairs(F.draws)do if d.kind=='icon' then
  cura=cura or d.args[1]==icons.cura;grenade=grenade or d.args[1]==icons.grenade
 end end
 assert(cura and grenade and icons.cura~=icons.grenade)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0xd92082f9'};F.objects[77].named.ei6_t2=3;F.objects[77].named.du7kbt=4")
test('consumable zero counts display while invalid values disappear immediately', '''
 ticks(0.3);rendered();assert(T.Model.items.stims==0 and T.Model.items.grenades==0)
 F.objects[77].named.ei6_t2=-1;F.objects[77].named.du7kbt=1.5;ticks(0.1)
 assert(T.Model.items.stims==nil and T.Model.items.grenades==nil)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0xd92082f9'};F.objects[77].named.ei6_t2=0;F.objects[77].named.du7kbt=0")
test('undeclared consumable fields are never queried by name', '''
 F.bad_names={ei6_t2=true,du7kbt=true};ticks(0.3);rendered()
 assert(T.Model.items and T.Model.items.stims==nil and T.Model.items.grenades==nil)
 assert(not F.counts['field:ei6_t2'] and not F.counts['field:du7kbt'])
''')
test('consumables work unarmed with batch protection and clear on death', '''
 F.batch_skip=true;ticks(0.3);assert(T.Model.items.stims==2 and not T.Model.resolved.hand_weapon)
 assert(F.raw_batches==0)
 F.objects[77].named.state=2;ticks(0.1);assert(T.Model.items==nil)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.objects[77].named.ei6_t2=2")
test('item visibility independent toggles and stale-avatar guard hold', '''
 ticks(0.3);local icons=up(T.Model.draw_consumables,'IconAssets')
 set('hud.lite.stims',false);ticks(0.1);rendered()
 local grenade=false
 for _,d in ipairs(F.draws)do if d.kind=='icon' then assert(d.args[1]~=icons.cura);grenade=grenade or d.args[1]==icons.grenade end end
 assert(grenade)
 T.Model.items.avatar=999;rendered()
 for _,d in ipairs(F.draws)do if d.kind=='icon' then assert(d.args[1]~=icons.grenade) end end
 T.Model.reset();assert(T.Model.items==nil)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0xd92082f9'};F.objects[77].named.ei6_t2=3;F.objects[77].named.du7kbt=4")

test('consumables clear when avatar disappears and recover only on the new avatar', '''
 ticks(0.3);assert(T.Model.items.stims==3)
 local old=F.objects[77];F.objects[77]=nil;ticks(0.1);assert(T.Model.items==nil)
 F.objects[78]=old;F.objects[78].named.ei6_t2=1;F.objects[0].named.baegche=78
 ticks(0.5);assert(T.Model.items and T.Model.items.avatar==78 and T.Model.items.stims==1)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.objects[77].named.ei6_t2=3")
test('consumable stale data and world changes cannot leave quantities visible', '''
 ticks(0.3);assert(T.Model.items.stims==3)
 T.Model.items.at=T.S.clock-1;rendered()
 local icons=up(T.Model.draw_consumables,'IconAssets')
 for _,d in ipairs(F.draws)do if d.kind=='icon' then assert(d.args[1]~=icons.cura) end end
 F.mission=false;ticks(0.1);assert(T.Model.items==nil)
 F.mission=true;F.world={};F.world_id=2;F.objects[77].named.ei6_t2=nil;ticks(0.3)
 assert(not T.Model.items or T.Model.items.stims==nil)
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.objects[77].named.ei6_t2=3")
test('consumable icons honor opacity and show labeled text if bitmap is unavailable', '''
 set('hud.lite.alpha',50);ticks(0.3);rendered()
 local icons=up(T.Model.draw_consumables,'IconAssets');local found=false
 for _,d in ipairs(F.draws)do if d.kind=='icon' and d.args[1]==icons.cura then
  found=true;assert(d.args[10][4]<=128)
 end end
 assert(found)
 F.icon_fail=true;rendered();local label=false
 for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]=='STIM 3' then label=true end end
 assert(label,'bitmap failure hid the quantity')
''',before_load="F.declarations.gl7xl2w.fields[#F.declarations.gl7xl2w.fields+1]={id='0x5f8eb478'};F.objects[77].named.ei6_t2=3")
test('energy range reference never leaks to another object with the same type', '''
 weapon('0x3622f8dc');F.weapon.values['0xa5023836']=160;F.weapon.values['0xf6275c53']=true
 ticks(0.3);assert(T.Model.heat_limit and T.Model.heat_limit.value==160)
 F.objects[314]=nil;weapon('0x3622f8dc',315);F.weapon.values['0xa5023836']=25
 ticks(0.5);assert(T.Model.energy==nil and T.Model.window.cells.heat_max==nil)
''')

test('authored scope draws zeroing from declared options without requiring an attachment delta', '''
 weapon('0xa6445802');F.weapon.values['0x31f86165']=16;ticks(0.3);rendered()
 assert(T.Model.window.cells.zeroing=='zeroing_medium' and shape(10))
 local cell=G.identity.icon_cells.zeroing_medium;local found=false
 local metric=up(T.Model.draw_consumables,'IconAssets').row_metrics.zeroing_medium
 for _,d in ipairs(F.draws)do if d.kind=='icon' and d.args[1]=='254deec0e6c38888'
  and d.args[2]==metric.u0 and d.args[3]==metric.v0 then found=true end end
 assert(found,'zeroing atlas not drawn')
 F.weapon.values['0x31f86165']=32;ticks(0.1)
 assert(T.Model.window.cells.zeroing=='zeroing_high' and shape(10))
''')
test('zeroing scalar option aliases work while Chef batch is blocked', '''
 weapon('0xa6445802');F.batch_skip=true;F.weapon.named.ozvglfc=16;ticks(0.4);rendered()
 assert(T.Model.window.cells.zeroing=='zeroing_medium' and T.Model.row_layout.by_role.zeroing)
 assert(F.raw_batches==0)
''')
test('invalid absent and reserved zeroing options never fabricate scope icons', '''
 weapon('0xa6445802')
 for _,value in ipairs({-1,1.5,math.huge,48})do
  F.weapon.values['0x31f86165']=value;ticks(0.1);assert(not shape(10))
 end
 F.weapon.values['0x31f86165']=nil;ticks(0.1);assert(not shape(10))
 F.weapon.values['0x31f86165']=0;ticks(0.1);assert(shape(10) and shape(10).name=='zeroing_low')
''')
test('single visible icon starts at the shared row left edge without vacant slots', '''
 weapon('0xa6445802');set('hud.lite.firemode',false);set('hud.lite.function_icon',false)
 set('hud.lite.rof_icon',false);set('hud.lite.reserves',false);set('hud.lite.stims',false);set('hud.lite.grenades',false)
 F.weapon.values['0x31f86165']=32;ticks(0.3);rendered()
 local row=T.Model.row_layout
 assert(row.count==1 and row.pool[1].role=='zeroing' and row.pool[1].left==row.left)
''')
test('all visible row items keep deterministic order and non-overlapping variable widths', '''
 weapon('0x967a3fed');ticks(0.3)
 T.Model.commands={{kind='icon',key=10,side='right',name='zeroing_high'},
  {kind='icon',key=9,side='right',name='firemode_single'},
  {kind='icon',key=8,side='right',name='firemode_auto'}}
 T.Model.window.cells.rof_icon='rof_medium';T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4}
 rendered();local row=T.Model.row_layout
 local order={'stims','grenades','zeroing','ammo_icon','rof','reserve','firemode'}
 assert(row.count==#order)
 for i,name in ipairs(order)do
  local item=row.pool[i];assert(item.role==name,name)
  assert(item.y==row.y,'not in shared row')
  if i>1 then local prior=row.pool[i-1];assert(item.left>=prior.left+prior.width+8)end
 end
''')
test('missing unknown and duplicate RPM icons do not reserve invisible row slots', '''
 weapon('0x967a3fed');set('hud.lite.reserves',false);ticks(0.3)
 T.Model.commands={{kind='icon',key=9,side='right',name='rof_medium'},
 {kind='icon',key=10,side='right',name='unavailable_icon'}}
 T.Model.window.cells.rof_icon='rof_medium';rendered()
 local row=T.Model.row_layout
 assert(row.count==1 and row.pool[1].role=='rof' and row.pool[1].left==row.left)
''')
test('stim and grenade offsets adjust independently without moving sibling items', '''
 set('hud.lite.row_unlock',true);set('hud.lite.grenades_x',0)
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4};rendered()
 local row=T.Model.row_layout;local sx,sy=row.by_role.stims.left,row.by_role.stims.y
 local gx,gy=row.by_role.grenades.left,row.by_role.grenades.y
 set('hud.lite.stims_x',27);set('hud.lite.stims_y',-12);M.update(0.001);rendered()
   assert(row.by_role.stims.left==sx+27 and row.by_role.stims.y==sy-12)
 assert(row.by_role.grenades.left==gx and row.by_role.grenades.y==gy)
 set('hud.lite.grenades_x',-8);set('hud.lite.grenades_y',9);M.update(0.001);rendered()
 assert(row.by_role.grenades.left==gx-8 and row.by_role.grenades.y==gy+9)
 assert(row.by_role.stims.left==sx+27 and row.by_role.stims.y==sy-12)
''')
test('consumables compact left while unarmed and stay with the weapon row anchor', '''
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=2,grenades=0};rendered()
 local row=T.Model.row_layout
 assert(row.pool[1].role=='stims' and row.by_role.stims.left==row.left)
 assert(row.by_role.stims.y==520-74 and row.by_role.grenades.y==520-74)
 set('hud.lite.stims',false);M.update(0.001);rendered()
 assert(row.count==1 and row.by_role.grenades.left==row.left)
 set('hud.lite.icon_position',2);set('hud.lite.row_x',0);M.update(0.001);rendered()
 assert(row.left==529 and row.y==90 and row.by_role.grenades.left==529)
''')
test('pack reserve source and normal reserve never draw duplicate magazine quantities', '''
 weapon('0xb2bfd847');local p=backpack('0x9f9ef431');p.values['0x69889752']=5;ticks(2);rendered()
 local row=T.Model.row_layout;local n=0
 for i=1,row.count do if row.pool[i].role=='reserve' then n=n+1;assert(row.pool[i].text=='5')end end
 assert(n==1)
''')
test('backpack uses direct Ring layout coordinates dimensions and shared opacity', '''
 ticks(0.3)
 set('hud.lite.backpack_x',30);set('hud.lite.backpack_y',500)
 set('hud.lite.backpack_radius',90);set('hud.lite.backpack_thickness',4)
 set('hud.lite.backpack_span',80);set('hud.lite.alpha',50);M.update(0.001)
 T.Model.commands={{kind='arc',key=1,side='left',fraction=0.5,alpha=1,state={tone='normal'}}}
 rendered();local fill=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==909 then
  fill=true;assert(d.args[1]==990 and d.args[2]==500)
   assert(d.args[3]==88 and d.args[4]==92 and d.args[5]==50 and d.args[6]==90)
  assert(d.args[7][4]<=128)
 end end
 assert(fill)
''')
test('backpack has direct numeric defaults and never alters health or reload geometry', '''
 ticks(0.3);set('hud.lite.backpack_x',150);set('hud.lite.backpack_radius',120);M.update(0.001)
 T.Model.commands={{kind='arc',key=1,fraction=0.5,alpha=1,state={tone='normal'}},
 {kind='arc',key=7,column='trigger_held',fraction=0.5,alpha=1,state={tone='normal'}}}
 rendered();local hp,reload=false,false
 for _,d in ipairs(F.draws)do if d.kind=='arc' then
  if d.args[8]==906 and d.args[5]>180 then hp=true;assert(d.args[1]==960 and d.args[3]==74)end
  if d.args[8]==908 then reload=true;assert(d.args[1]==960 and d.args[3]==57.5)end
 end end
 assert(hp and reload)
 assert(F.defaults['hud.lite.backpack_radius']==168.5 and F.defaults['hud.lite.backpack_thickness']==3.5)
''')
test('steady weapon avoids per-frame graph rebuilding and text metric engine calls', '''
 weapon('0x967a3fed');ticks(0.3);rendered()
 local builds=T.Model.builds;local rows=T.Model.row_builds;local native=T.Native.stats.calls
 local widths=F.counts.text_width or 0
 for i=1,5 do M.update(0.001);rendered()end
 assert(T.Model.builds==builds and T.Model.row_builds==rows,'static graphs rebuilt each frame')
 assert(T.Native.stats.calls==native and (F.counts.text_width or 0)==widths)
''')
test('charge model keeps per-frame interpolation while static graphs are cached', '''
 weapon('0x17783758');F.weapon.values['0xa5023836']=5;F.weapon.values['0x88b7cf6d']=true;ticks(0.3)
 local builds=T.Model.builds;local p=shape(7).fraction
 M.update(0.001);rendered()
 assert(T.Model.builds>builds and shape(7).fraction>p,'charge interpolation became poll-only')
''')
test('static model cache invalidates on samples death equipment changes and reset', '''
 weapon('0x967a3fed');ticks(0.3);local builds=T.Model.builds
 F.weapon.values['0xd7a5d63e']=7;ticks(0.1);rendered()
 assert(T.Model.builds>builds and T.Model.window.cells.ammo==7)
 F.objects[77].named.state=2;ticks(0.1);assert(#T.Model.commands==0)
 T.Model.reset();assert(T.Model.built_window==nil and T.Model.row_layout==nil)
''')

test('settings register once in eleven contiguous categorized blocks with backpack under Ring layout', '''
 local last,groups,seen=0,0,{}
 for _,id in ipairs(F.option_order)do
  assert(not seen[id],'option registered twice: '..id);seen[id]=true
  local spec=F.specs[id];local n=tonumber(spec.label:match('^%[(%d+) '))
  assert(n and n>=last,'categories not contiguous: '..id)
  if n~=last then groups=groups+1;last=n end
  assert(spec.type=='toggle' or spec.type=='slider' or spec.type=='choice')
 end
 assert(groups==11)
 assert(F.specs['hud.lite.backpack_radius'].label:find('[02 Ring layout]',1,true))
 assert(F.specs['hud.lite.stims_x'].label:find('[09 Stims and grenades]',1,true))
 assert(F.specs['hud.lite.zeroing'].label:find('[07 Zeroing and RPM]',1,true))
''')
test('menu classification preserves saved player values and independent backpack controls', '''
 assert(F.saved['opt.hud.lite.backpack_x']==57 and F.saved['opt.hud.lite.stims_y']==-18)
 ticks(0.3)
 assert(chef.get('hud.lite.backpack_x')==57 and chef.get('hud.lite.stims_y')==-18)
 assert(chef.get('hud.lite.firemode_x')==31 and chef.get('hud.lite.grenades_x')==9)
 assert(F.saved['opt.hud.lite.firemode_x']==31,'saved value rewritten')
''',before_load="F.saved['opt.hud.lite.backpack_x']=57;F.saved['opt.hud.lite.stims_y']=-18;F.saved['opt.hud.lite.firemode_x']=31;F.saved['opt.hud.lite.grenades_x']=9")
test('backpack direct geometry scales with resolution and uses the shared track toggle', '''
 F.width=1280;F.height=720;ticks(0.3)
 set('hud.lite.backpack_radius',90);set('hud.lite.backpack_thickness',6)
 set('hud.lite.backpack_x',30);set('hud.lite.backpack_y',500)
 set('hud.lite.track',false);M.update(0.001)
 T.Model.commands={{kind='arc',key=1,fraction=0.5,alpha=1,state={tone='normal'}}}
 rendered();local found=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==909 then
  found=true;assert(math.abs(d.args[1]-660)<0.001)
  assert(math.abs(d.args[3]-58)<0.001 and math.abs(d.args[4]-62)<0.001)
 end end
 assert(found)
 set('hud.lite.backpack',false);M.update(0.001);rendered()
 for _,d in ipairs(F.draws)do assert(not(d.kind=='arc' and d.args[8]==909))end
''')
test('zeroing never reads undeclared packed options or survives a lost channel', '''
 weapon('0xa6445802');F.batch_skip=true;F.weapon.named.ozvglfc=16;ticks(0.3);assert(shape(10))
 F.weapon.named.ozvglfc=nil;ticks(0.1);assert(not shape(10))
''')
test('repeated frame renders reuse row entries and a bounded text metric cache', '''
 weapon('0x967a3fed');ticks(0.3);rendered()
 local row=T.Model.row_layout;local item=row.pool[1];local rows=T.Model.row_builds
 local widths=F.counts.text_width or 0
 for i=1,50 do rendered()end
 assert(T.Model.row_layout==row and row.pool[1]==item and T.Model.row_builds==rows)
 assert((F.counts.text_width or 0)==widths)
 local metrics=up(up(T.Model.layout_row,'text_width'),'text_metrics')
 assert(metrics.count<=256)
''')

test('locked row ignores all manual offsets and follows requested consumables-first order', '''
 weapon('0xa6445802');ticks(0.3)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4}
 T.Model.commands={{kind='icon',key=10,side='right',name='zeroing_low'},
 {kind='icon',key=9,side='right',name='firemode_single'},
 {kind='icon',key=8,side='right',name='firemode_auto'}}
 T.Model.window.cells.rof_icon='rof_medium';T.Model.reserve_text='4'
 set('hud.lite.stims_x',130);set('hud.lite.grenades_y',90);set('hud.lite.zeroing_x',-100)
 M.update(0.001);rendered()
 local row=T.Model.row_layout;assert(not row.unlocked and F.defaults['hud.lite.row_unlock']==false)
 local order={'stims','grenades','zeroing','ammo_icon','rof','reserve','firemode'}
 local cursor=row.left
 for i,role in ipairs(order)do local item=row.pool[i]
  assert(item.role==role and item.left==cursor and item.y==row.y,role)
  cursor=cursor+item.width+8
 end
''')
test('locked missing leading and middle icons compact without gaps', '''
 weapon('0xa6445802');ticks(0.3);set('hud.lite.firemode',false)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,grenades=4}
 T.Model.commands={{kind='icon',key=10,side='right',name='zeroing_low'}}
 T.Model.reserve_text='2';M.update(0.001);rendered()
 local row=T.Model.row_layout
 assert(row.pool[1].role=='grenades' and row.pool[1].left==row.left)
 local old=row.by_role.reserve.left
 set('hud.lite.zeroing',false);M.update(0.001);rendered()
 assert(row.by_role.reserve.left<old and row.by_role.reserve.left==row.left+row.by_role.grenades.width+8)
''')
test('unlocked coordinates do not move when earlier icons vanish or quantity width changes', '''
 ticks(0.3);set('hud.lite.row_unlock',true)
 set('hud.lite.stims_x',12);set('hud.lite.grenades_x',180);set('hud.lite.grenades_y',-9)
 set('hud.lite.zeroing_x',310);M.update(0.001)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4}
 T.Model.commands={{kind='icon',key=10,side='right',name='zeroing_low'}}
 rendered();local row=T.Model.row_layout
 assert(row.unlocked and row.by_role.grenades.left==row.left+180)
 local gx,zx=row.by_role.grenades.left,row.by_role.zeroing.left
 set('hud.lite.stims',false);M.update(0.001);rendered()
 assert(row.by_role.grenades.left==gx and row.by_role.zeroing.left==zx)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=123};rendered()
 assert(row.by_role.zeroing.left==zx and row.by_role.grenades.y==row.y-9)
''')
test('relocking restores compact order without erasing saved manual positions', '''
 ticks(0.3);set('hud.lite.stims_x',200);set('hud.lite.grenades_x',350)
 set('hud.lite.row_unlock',true);M.update(0.001)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=1,grenades=2};rendered()
 local row=T.Model.row_layout;assert(row.by_role.stims.left==row.left+200)
 set('hud.lite.row_unlock',false);M.update(0.001);rendered()
 assert(row.by_role.stims.left==row.left and row.by_role.grenades.left==row.left+row.by_role.stims.width+8)
 set('hud.lite.row_unlock',true);M.update(0.001);rendered()
 assert(row.by_role.stims.left==row.left+200 and row.by_role.grenades.left==row.left+350)
''')
test('zero default option padding never creates unsupported scope icons', '''
 for _,hash in ipairs({'0x15f1a9f0','0xb3246bb7','0x366d3622','0x3622f8dc','0x967a3fed'})do
  weapon(hash);T.Model.reset();T.Native.reset()
  for _,value in ipairs({0})do
   F.weapon.values['0x31f86165']=value;ticks(0.3);rendered()
   assert(not shape(10) and T.Model.window.cells.zeroing==nil,hash..' false zeroing')
   assert(T.Model.row_layout.by_role.zeroing==nil)
  end
 end
''')
test('recognized scope attachment enables zeroing and removing it hides the icon', '''
 weapon('0x967a3fed');F.weapon.values['0x31f86165']=16
 F.weapon.values['0x98b4aaf0']={'#ID[19fc5c5b031a4af2]'};ticks(0.3);rendered()
 assert(shape(10) and shape(10).name=='zeroing_medium')
 F.weapon.values['0x98b4aaf0']={};ticks(0.1);rendered()
 assert(not shape(10) and not T.Model.row_layout.by_role.zeroing)
''')
test('unsupported delta identifiers and ambiguous scope capability stay hidden', '''
 weapon('0x967a3fed');F.weapon.values['0x31f86165']=16
 F.weapon.values['0x98b4aaf0']={'#ID[0123456789abcdef]'};ticks(0.3);assert(not shape(10))
 F.weapon.values['0x98b4aaf0']={'#ID[19fc5c5b031a4af2]','#ID[3d18c135000c36dc]'}
 ticks(0.1);assert(not shape(10),'ambiguous scope treated as supported')
''')
test('scope capability cannot leak after a weapon switch or into an unavailable channel', '''
 weapon('0xa6445802');F.weapon.values['0x31f86165']=16;ticks(0.3);assert(shape(10))
 F.objects[314]=nil;weapon('0x30294946',315);F.weapon.values['0x31f86165']=0
 ticks(0.5);assert(not shape(10))
''')
test('backpack controls share Ring layout units and removed special controls are not registered', '''
 assert(F.specs['hud.lite.backpack_radius'].min==F.specs['hud.lite.inner_radius'].min)
 assert(F.specs['hud.lite.backpack_thickness'].min==F.specs['hud.lite.inner_thickness'].min)
 assert(F.specs['hud.lite.backpack_span'].min==F.specs['hud.lite.span'].min)
 assert(F.specs['hud.lite.backpack_y'].min==F.specs['hud.lite.y'].min)
 assert(F.specs['hud.lite.backpack_y'].max==F.specs['hud.lite.y'].max)
 assert(not F.specs['hud.lite.backpack_angle'] and not F.specs['hud.lite.backpack_alpha'] and not F.specs['hud.lite.backpack_track'])
 ticks(0.3);set('hud.lite.x',200);set('hud.lite.y',600)
 set('hud.lite.backpack_x',20);set('hud.lite.backpack_y',500);M.update(0.001)
 T.Model.commands={{kind='arc',key=1,fraction=0.5,alpha=1,state={tone='normal'}}}
 rendered();local found=false
 for _,d in ipairs(F.draws)do if d.kind=='arc' and d.args[8]==909 then
  found=true;assert(d.args[1]==980 and d.args[2]==500,'not direct Ring layout coordinates')
 end end
 assert(found)
''')

test('information row horizontal anchor is independent of health text position', '''
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4};rendered()
 local row=T.Model.row_layout;local x=row.left;local y=row.y
 set('hud.lite.info_x',215);set('hud.lite.info_y',120);M.update(0.001);rendered()
 assert(row.left==x and row.y==y,'vitals moved the information row')
 set('hud.lite.row_x',-40);M.update(0.001);rendered()
 assert(row.left==836 and row.pool[1].left==836)
 assert(chef.get('hud.lite.info_x')==215)
''')
test('information row gap measures cropped visible edges rather than square texture tiles', '''
 weapon('0xa6445802');ticks(0.3)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4}
 T.Model.commands={{kind='icon',key=10,side='right',name='zeroing_low'},
 {kind='icon',key=9,side='right',name='ammo_he'}}
 T.Model.window.cells.rof_icon='rof_medium';rendered()
 local row=T.Model.row_layout
 assert(row.by_role.zeroing.icon_width<row.by_role.zeroing.size/2,'atlas padding counted')
 assert(row.by_role.grenades.icon_width<row.by_role.grenades.size,'standalone padding counted')
 for i=2,row.count do local prev,item=row.pool[i-1],row.pool[i]
  assert(math.abs(item.left-prev.left-prev.width-8)<0.0001)
 end
 local metrics=up(T.Model.draw_consumables,'IconAssets').row_metrics
 for _,d in ipairs(F.draws)do if d.kind=='icon' and d.args[1]==metrics.zeroing_low.texture
  and d.args[2]==metrics.zeroing_low.u0 and d.args[3]==metrics.zeroing_low.v0 then
   local item=row.by_role.zeroing
   assert(d.args[6]==item.left and d.args[8]==item.icon_width)
   assert(math.abs(d.args[7]+d.args[9]/2-item.y)<0.0001)
 end end
''')
test('consumable and magazine quantity pixel centers match their visible icon centers', '''
 weapon('0xa6445802');ticks(0.3)
 T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=7,grenades=9};T.Model.reserve_text='6';rendered()
 local row=T.Model.row_layout
 for role,text in pairs({stims='7',grenades='9',reserve='6'})do
  local item=row.by_role[role];local found=false
  for _,d in ipairs(F.draws)do if d.kind=='text' and d.args[3]==text then
   found=true;assert(math.abs(d.args[2]+7*d.args[4]/2-item.y)<0.0001)
   assert(math.abs(d.args[1]-item.left-item.icon_width-item.gap)<0.0001)
  end end
  assert(found,role..' count not drawn')
 end
''')
test('row visible gap scales once with screen resolution and keeps alpha untouched', '''
 F.width=1280;F.height=720;set('hud.lite.row_x',30);set('hud.lite.row_gap',12)
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=7,grenades=9};rendered()
 local row=T.Model.row_layout
 assert(math.abs(row.left-604)<0.001)
 assert(math.abs(row.by_role.grenades.left-row.by_role.stims.left-row.by_role.stims.width-8)<0.001)
''')
test('published row anchor preserves the approved left edge without coupling to vitals settings', '''
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=7};rendered()
 assert(F.defaults['hud.lite.row_x']==0 and T.Model.row_layout.left==876)
 set('hud.lite.info_x',350);M.update(0.001);rendered()
 assert(T.Model.row_layout.left==876)
''',merged_layout=False)

test('saved row offset keeps its approved-origin meaning without following saved vitals position', '''
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3};rendered()
 assert(T.Model.row_layout.left==876+25)
 assert(F.saved['opt.hud.lite.row_x']==25 and F.saved['opt.hud.lite.info_x']==200)
''',before_load="F.saved['opt.hud.lite.row_x']=25;F.saved['opt.hud.lite.info_x']=200",merged_layout=False)
test('font metric changes refresh row widths without unbounded cache growth', '''
 ticks(0.3);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4};rendered()
 local width=T.Model.row_layout.by_role.stims.width
 local metrics=up(up(T.Model.layout_row,'text_width'),'text_metrics')
 chef.text_width=function(text,px)return #text*30 end
 ticks(1.1);T.Model.items={avatar=T.S.avatar,at=T.S.clock,stims=3,grenades=4};rendered()
 assert(T.Model.row_layout.by_role.stims.width>width,'font switch kept old width')
 assert(metrics.count<=256)
''')

test('unrelated multiplayer ownership churn never clears a freshly verified hand', '''
 weapon('0x967a3fed');ticks(0.4);assert(T.Model.resolved.hand_weapon)
 local found=T.Model.identity.counters.fast_hand
 for i=1,20 do
  F.objects[1000+i]={call='unknown',named={},values={}}
  F.owned['local']={0,1000+i,314};F.weapon.values['0xd7a5d63e']=20-i
  ticks(0.05)
  assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314,'hand lost to ownership churn')
  assert(T.Model.window.cells.ammo==20-i,'ammo value was retained instead of refreshed')
 end
 assert(T.Model.identity.counters.fast_hand>found)
''')
test('client finds host-owned weapon only with a declared matching local owner', '''
 weapon('0x967a3fed');F.host='host';F.peers={'host','local'}
 F.owned['local']={0};F.owned.host={314}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='local';ticks(1);rendered()
 assert(T.Model.resolved.player.goid==0 and T.S.avatar==77)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314,T.S.channel)
 assert(center()=='20/30',tostring(center()))
 F.weapon.values['0xd7a5d63e']=7;ticks(0.1);assert(T.Model.window.cells.ammo==7)
''')
test('host equipment scan never admits a foreign or unreadable owner', '''
 weapon('0x967a3fed');F.host='host';F.peers={'host','local'}
 F.owned['local']={0};F.owned.host={314}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='host';ticks(1);assert(not T.Model.resolved.hand_weapon)
 F.weapon.named.g5g7b9d=nil;ticks(0.5);assert(not T.Model.resolved.hand_weapon)
 F.weapon.named.g5g7b9d='local';ticks(0.5);assert(T.Model.resolved.hand_weapon)
 F.weapon.named.g5g7b9d='host';ticks(0.1);assert(not T.Model.resolved.hand_weapon,'foreign transfer kept old weapon')
''')
test('host player and avatar are never substituted for the local player during candidate merging', '''
 weapon('0x967a3fed');F.host='host';F.peers={'host','local'}
 F.objects[88]={call='un6y1d',named={baegche=99},values={}}
 F.objects[99]={call='gl7xl2w',named={health=0.1,state=0},values={}}
 F.owned.host={88,99,314};F.owned['local']={0}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='local';ticks(1)
 assert(T.S.player==0 and T.S.avatar==77 and T.S.hp==100)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314)
''')
test('local network ownership cannot override an explicitly foreign carried weapon owner', '''
 weapon('0x967a3fed')
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='other';ticks(0.5);assert(not T.Model.resolved.hand_weapon)
''')
test('host and local peer identifier formatting is normalized for equipment owner matching', '''
 F.peer='0x000a';F.owned['0x000a']={0};F.host='0x000b';F.peers={'0x000a','0x000b'}
 weapon('0x967a3fed');F.owned['local']={};F.owned['0x000a']={0};F.owned['0x000b']={314}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='000A';ticks(1)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314)
''')
test('drop death grip change and type reuse still invalidate held weapon under ownership churn', '''
 weapon('0x967a3fed');ticks(0.4)
 F.owned['local']={0,314,1000};F.weapon.named.enabled_mask=1;ticks(0.1)
 assert(not T.Model.resolved.hand_weapon)
 F.weapon.named.enabled_mask=0;F.body.grip=0;ticks(0.1);assert(not T.Model.resolved.hand_weapon)
 F.body.grip=10;ticks(0.3);assert(T.Model.resolved.hand_weapon)
 F.objects[77].named.state=2;ticks(0.1);assert(not shape(11))
''')
test('host candidate search retains the fixed type-check budget in large multiplayer lists', '''
 weapon('0x967a3fed');F.host='host';F.peers={'host','local'}
 F.owned['local']={0};F.owned.host={314}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='local'
 for i=1000,1149 do F.objects[i]={call='unknown',named={},values={}};F.owned.host[#F.owned.host+1]=i end
 for i=1,30 do local n=T.Native.stats.scans;ticks(0.05);assert(T.Native.stats.scans-n<=40)end
 assert(T.Model.resolved.hand_weapon)
''')
test('disposable launcher families retain loaded ammo but never draw zero reserve magazines', '''
 for _,hash in ipairs({'0xc0ff5282','0x6ec2a850','0xd724a2f9','0x3d538455','0x9c2e7f43'})do
  weapon(hash);T.Model.reset();T.Native.reset();F.weapon.values['0xd7a5d63e']=1
  F.weapon.values['0xec64918b']=0;F.weapon.values['0x9a34c336']=0;ticks(0.5);rendered()
  assert(G.identity.equipment[hash].no_reserves,hash..' no-reload policy absent')
  assert(T.Model.window.cells.ammo==1 and shape(11),hash..' loaded ammo hidden')
  assert(T.Model.reserve_text==nil and T.Model.row_layout.by_role.reserve==nil,hash..' zero magazines shown')
  for _,command in ipairs(T.Model.commands)do
   assert(not(command.kind=='number' and(command.column=='reserve'or command.column=='pack_spare')))
  end
 end
''')
test('single-shot reloadable weapons and ordinary empty reserves still show a real zero', '''
 for _,hash in ipairs({'0x26acc614','0x2df95dfe','0x756a4e4d','0x967a3fed'})do
  weapon(hash);T.Model.reset();T.Native.reset();F.weapon.values['0xd7a5d63e']=1
  F.weapon.values['0xec64918b']=0;ticks(0.5);rendered()
  assert(not G.identity.equipment[hash].no_reserves,hash..' reloadable treated as disposable')
  assert(T.Model.reserve_text=='0' and T.Model.row_layout.by_role.reserve)
 end
''')
test('safe scalar actual nondefault zeroing survives absent attachment metadata then lowest setting', '''
 weapon('0x967a3fed');F.batch_skip=true;F.weapon.named.ozvglfc=16;ticks(0.4);rendered()
 assert(shape(10) and shape(10).name=='zeroing_medium' and T.Model.row_layout.by_role.zeroing)
 F.weapon.named.ozvglfc=0;ticks(0.1);assert(shape(10) and shape(10).name=='zeroing_low')
 F.weapon.named.ozvglfc=nil;ticks(0.1);assert(not shape(10),'missing reading kept old icon')
 F.weapon.named.ozvglfc=32;ticks(0.1);assert(shape(10) and shape(10).name=='zeroing_high')
''')
test('scope capability persists through missing delta reads but not explicit removal', '''
 weapon('0x967a3fed');F.weapon.values['0x31f86165']=0
 F.weapon.values['0x98b4aaf0']={'#ID[19fc5c5b031a4af2]'};ticks(0.4);assert(shape(10))
 F.weapon.values['0x98b4aaf0']=nil;ticks(0.1);assert(shape(10),'temporary delta loss hid confirmed scope')
 F.weapon.values['0x98b4aaf0']={};ticks(0.1);assert(not shape(10),'removed scope retained')
''')
test('nonreloadable and supply-only weapons do not gain scopes from generic option bits', '''
 for _,hash in ipairs({'0xc0ff5282','0x6ec2a850','0xd724a2f9','0x15f1a9f0','0xb3246bb7','0x366d3622'})do
  weapon(hash);T.Model.reset();T.Native.reset()
  for _,options in ipairs({0,16,32})do
   F.weapon.values['0x31f86165']=options;ticks(0.3);assert(not shape(10),hash..' false scope')
  end
 end
''')

test('network ownership list migration does not interrupt live locally held ammo', '''
 weapon('0x967a3fed');F.host='host';F.peers={'local','host'}
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d='local';ticks(0.4)
 for i=1,20 do
  if i%2==0 then F.owned['local']={0,314};F.owned.host={}else F.owned['local']={0};F.owned.host={314}end
  F.weapon.values['0xd7a5d63e']=20-i;ticks(0.05)
  assert(T.Model.resolved.hand_weapon and T.Model.resolved.hand_weapon.goid==314)
  assert(T.Model.window.cells.ammo==20-i)
 end
''')
test('dropped carry mask two clears weapon even when its stale unit remains at hand position', '''
 weapon('0x967a3fed');ticks(0.4);F.weapon.named.enabled_mask=2
 ticks(0.1);assert(not T.Model.resolved.hand_weapon and not shape(11))
''')
test('host read skips never select unverified equipment or another player', '''
 weapon('0x967a3fed');F.host='host';F.peers={'local','host'}
 F.owned['local']={0};F.owned.host={314};F.batch_skip=true
 F.declarations[F.weapon.call].fields[#F.declarations[F.weapon.call].fields+1]={id='0x3ccffa7f'}
 F.weapon.named.g5g7b9d=nil;ticks(1)
 assert(not T.Model.resolved.hand_weapon and T.S.player==0 and T.S.avatar==77)
 assert(F.raw_batches==0)
''')
test('disposable weapon never gains fabricated reload progress from a shared stage value', '''
 weapon('0xc0ff5282');F.weapon.values['0xd7a5d63e']=0;F.weapon.values['0xcd889dbc']=1
 F.anim={body_elapsed=1,length=4};ticks(0.4);rendered()
 assert(not shape(7) and T.Model.animation==nil)
 assert(shape(11) and T.Model.window.cells.ammo==0 and T.Model.reserve_text==nil)
''')

test('backpack disappearance never clears an independently verified magazine weapon', '''
 weapon('0x967a3fed');backpack('0x6c17c3b1');ticks(1)
 assert(T.Model.resolved.hand_weapon and T.Model.resolved.backpack)
 F.objects[500]=nil;F.owned['local']={0,314,1001}
 ticks(0.1)
 assert(T.Model.resolved.hand_weapon and T.Model.window.cells.ammo==20)
 assert(not T.Model.resolved.backpack)
''')

test('temporary owned-list failure keeps physically verified hand and fresh ammo only', '''
 weapon('0x967a3fed');ticks(0.4)
 local original=stingray.GameSession.objects_owned_by
 stingray.GameSession.objects_owned_by=function()return nil,'skipped'end
 F.weapon.values['0xd7a5d63e']=8;ticks(0.1)
 assert(T.Model.resolved.hand_weapon and T.Model.window.cells.ammo==8)
 F.objects[314]=nil;ticks(0.1);assert(not T.Model.resolved.hand_weapon and not shape(11))
 stingray.GameSession.objects_owned_by=original
''')

test('lowest zeroing remains on the same gun after backpack replacement', '''
 weapon('0x967a3fed');F.batch_skip=true;F.weapon.named.ozvglfc=16;ticks(0.4);assert(shape(10))
 F.weapon.named.ozvglfc=0;ticks(0.1);assert(shape(10))
 backpack('0x6c17c3b1');F.objects[500].named.c60sehb=100;ticks(1)
 assert(shape(10) and shape(10).name=='zeroing_low','pack change cleared gun scope proof')
''')

report={'runtime':'Lua 5.1 (lupa.lua51)','checks':len(results),'failed':0,'tests':results,
        'source_sha256':hashlib.sha256(SOURCE.encode('utf-8')).hexdigest(),
        'game_tested':False}
(ROOT/'reports/VERIFICATION.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
