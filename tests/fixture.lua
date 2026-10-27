F={time=0,world={},world_id=1,mission=true,session=1,peer="local",logs={},draws={},defaults={},values={},
  objects={},owned={},declarations={},units={},counts={},stopped=false,raw_batches=0}
F.saved={}
F.specs={}
F.option_order={}
local function count(key) F.counts[key]=(F.counts[key] or 0)+1 end
local function vec(x,y,z) return {x=x,y=y,z=z} end
local function fields(ids)
  local result={}
  for _,id in ipairs(ids) do result[#result+1]={id=id,type="number"} end
  return {fields=result}
end
F.fields=fields
F.declarations.un6y1d=fields({"0x0f27c68e","0x3b12bd49","0xcd889dbc"})
F.declarations.gl7xl2w=fields({"0xcb0453ea","0x82830aed","0xd49efb40","0x4441caf8","0x8bbeb160","0xdae681f4"})
F.weapon_fields={"0x788b9753","0xc3a3f66c","0xd7a5d63e","0x4a893e74","0x04ec5b95","0xe525fa9c","0xa74ef0d5",
 "0xcd889dbc","0x3132608f","0x49c250a6","0x31f86165","0xa5023836","0xf6275c53","0x98b4aaf0","0x88b7cf6d",
 "0x4cbcc2a2","0xf8d23bd2","0x67526982","0xec64918b","0x9a34c336"}
F.objects[0]={call="un6y1d",named={baegche=77,booster=0,gbgqot6=256},values={ ["0x3b12bd49"]=0,["0xcd889dbc"]=256}}
F.objects[77]={call="gl7xl2w",named={health=0.8,max_health=125,stamina=0.6,state=0,motion_enabled=true,rotation_enabled=true,
 position=vec(0,0,0),gls4w9b=0},values={["0xcb0453ea"]=0.8}}
F.owned["local"]={0}
F.body={tag="body",pos=vec(0,0,0),anchor=vec(1,0,0),alive=true,grip=10}
F.units["4d1c334d294dfa97"]={F.body}

stingray={
 GameSession={
   in_session=function() return F.session~=nil end,
   game_object_exists=function(_,id)count("exists");return F.objects[id]~=nil end,
   objects_owned_by=function(_,peer)count("owned");return F.owned[peer] or {} end,
   game_object_is_type=function(_,id,call)count("type");return F.objects[id]~=nil and F.objects[id].call==call end,
   game_object_field=function(_,id,name)
     count("field:"..name)
     assert(F.objects[id],"read of missing object "..tostring(id))
     if F.bad_names and F.bad_names[name] then error("forbidden field probe "..name) end
     return F.objects[id].named[name]
   end,
   game_object_field_batched=function(_,id,out)
     count("batch")
     if F.batch_skip then return nil,"skipped" end
     F.raw_batches=F.raw_batches+1
     assert(F.objects[id],"batch of missing object")
     if F.batch_empty then return nil end
     local object=F.objects[id]
     local info=F.declarations[object.call]
     if not info then return nil end
     for i,desc in ipairs(info.fields) do out[i]=object.values[desc.id] end
     return out
   end,
   peers=function()count("peers");return F.peers or {"local"} end,
   game_session_host=function()count('host');return F.host end,
 },
 Network={game_session=function()return F.session end,peer_id=function()return F.peer end,
 object_info=function(call)count("info");if F.info_fail then return nil end;return F.declarations[call] end},
 World={units_by_resource=function(_,res)count("units");return F.units[tostring(res):gsub("^0x","")] or {} end},
 Unit={alive=function(u)count("alive");return type(u)=="table" and u.alive~=false end,
 node=function(u,name)count("node");return name=="attach_hand_r" and 2 or nil end,
 world_position=function(u,node)count("position");return node==2 and u.anchor or u.pos end,
 has_animation_state_machine=function()return true end,
 animation_has_variable=function(_,name)return name=="weapon_selected" end,
 animation_find_variable=function(_,name)return name=="weapon_selected" and 1 or nil end,
 animation_get_variable=function(u,id)assert(id>=1);return u.grip end,
 num_scene_graph_items=function()return 12 end,
 animation_get_state=function(unit)
   count('animation_states')
   if not F.anim then return nil end
   if F.anim_skip then return nil,'skipped' end
   if unit==F.body then
     count('body_states')
     if F.anim.body_missing then return nil end
     local states={}
     for i=1,(F.anim.body_count or 12)do states[i]=99 end
     states[12]=F.anim.body_state or 7
     if (F.anim.body_count or 12)<12 then states[12]=nil end
     return unpack(states,1,F.anim.body_count or 12)
   end
   count('weapon_states')
   if F.anim.state_table then return F.anim.state_table end
   return F.anim.s0 or 99,F.anim.s1 or 99,F.anim.s2 or 99,F.anim.s3 or 99
 end,
 animation_layer_info=function(unit,layer)
   count('animation_layer')
   assert(F.anim and unit==F.body and layer==11,'not original body-layer read: '..tostring(layer))
   if F.layer_skip then return nil,'skipped' end
   local elapsed=F.anim.body_elapsed or F.anim.elapsed or ((F.time-(F.anim.start or 0))*(F.anim.speed or 1))
   return elapsed,F.anim.length or 3
 end,
 },
 Vector3={x=function(v)return v.x end,y=function(v)return v.y end,z=function(v)return v.z end,
 distance=function(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end},
 IdString64={from_hex=function(s)return s end},
 Application={time_since_launch=function()return F.time end},
 Gui={},
}
local function draw(kind,...)
  assert(not F.stopped,"drawing after shutdown")
  F.draws[#F.draws+1]={kind=kind,args={...}}
end
chef={api=3,loader_version="1.2.3",options={},
 log=function(fmt,...) F.logs[#F.logs+1]=string.format(fmt,...) end,
 title=function()end,own_log=function()end,
 option=function(id,s)F.option_order[#F.option_order+1]=id;F.specs[id]=s;F.defaults[id]=s.default;if F.saved['opt.'..id]~=nil then return F.saved['opt.'..id]end return s.default end,
 get=function(id)if F.values[id]~=nil then return F.values[id] end if F.saved['opt.'..id]~=nil then return F.saved['opt.'..id] end return F.defaults[id] end,
 set=function(id,value)F.values[id]=value;return value end,
 load=function(id,default)if F.saved[id]~=nil then return F.saved[id]end return default end,
 save=function(id,value)F.saved[id]=value;return true end,
 on_change=function(id,fn)F.changes=F.changes or {};F.changes[id]=fn end,
 world=function()return F.world end,world_id=function()return F.world_id end,
 in_mission=function()return F.mission end,
 screen=function()return F.width or 1920,F.height or 1080 end,
 color=function(r,g,b,a)return {r,g,b,a} end,
 text=function(...)draw("text",...)end,text_width=function(s,px)count('text_width');return #s*6*px-px end,
 bitmap_uv=function(...)draw("icon",...);return not F.icon_fail end,
 arc=function(...)draw("arc",...)end,rect=function(...)draw("rect",...)end,
 call_kind=function(path,kind,...)
   count("guard")
   assert(path~="GameSession.game_object_field_batched","bypassed Chef sandbox batch guard")
   local ns,name=path:match("^([^.]+)%.(.+)$")
   local t=stingray[ns]
   if not t or type(t[name])~="function" then return nil,"missing" end
   return t[name](...)
 end,
 call=function(path,...)
   local ns,name=path:match('^([^.]+)%.(.+)$')
   local fn=stingray[ns] and stingray[ns][name]
   if not fn then return nil,'missing' end
   -- Match real Chef 1.2.3, which only returns a,b,c,d even when the engine
   -- returns twelve body layers. This was absent from the old mock.
   local a,b,c,d=fn(...)
   return a,b,c,d
 end,
}
function up(fn,name)
 for i=1,200 do local k,v=debug.getupvalue(fn,i);if not k then break end;if k==name then return v end end
 error("missing upvalue "..name)
end
function setup(mod)
 M=mod;T={Model=up(M.update,"Model"),S=up(M.update,"S"),Native=up(M.update,"Native")}
 G=T.Model.generated
end
function weapon(hash,id)
 id=id or 314
 local book=assert(G.identity.equipment[hash],hash)
 F.declarations[book.call]=fields(F.weapon_fields)
 F.body.grip=book.grip
 local object={hash=hash,call=book.call,named={enabled_mask=0,dvpupm=32767,underbarrel_goid=32767},values={}}
 local v=object.values
 v["0xd7a5d63e"],v["0x4a893e74"],v["0x04ec5b95"],v["0xe525fa9c"]=20,true,20,0
 v["0xa74ef0d5"],v["0xcd889dbc"],v["0x49c250a6"],v["0x31f86165"]=0,0,1,0
 v["0x3132608f"],v["0x88b7cf6d"],v["0xf6275c53"]=false,false,false
 v["0xec64918b"],v["0x9a34c336"]=4,80
 F.objects[id]=object
 F.owned.localpeer=nil
 F.owned["local"]={0,id}
 local unit={pos=vec(1,0,0),alive=true,grip=book.grip}
 if book.resource then F.units[book.resource:gsub("^0x","")]={unit} end
 F.weapon_unit=unit;F.weapon=object;F.weapon_id=id
 return object
end
function backpack(hash,id)
 id=id or 500
 local row=assert(G.identity.backpacks[hash],hash)
 local decl={"0x788b9753","0xc3a3f66c","0x69889752","0x1ad6d70f","0x0d402cf0","0x6fee6b03"}
 F.declarations[row.call]=fields(decl)
 local object={hash=hash,call=row.call,named={enabled_mask=0,dvpupm=32767},values={}}
 object.values['0x69889752']=50
 F.objects[id]=object
 F.owned['local'][#F.owned['local']+1]=id
 return object
end
function ticks(seconds,fps)
 fps=fps or 60
 for i=1,math.floor(seconds*fps+0.5) do F.time=F.time+1/fps;M.update(1/fps) end
end
function set(id,value)F.values[id]=value;if F.changes[id] then F.changes[id]() end end
function rendered()F.draws={};M.render();return F.draws end
function shape(key)
 for _,v in ipairs(T.Model.commands) do if v.key==key then return v end end
end
function center()
 local found,size
 for _,v in ipairs(F.draws) do
  if v.kind=="text" and (not size or v.args[4]>size) then found,size=v.args[3],v.args[4] end
 end
 return found
end
function assert_no_errors()
 for _,line in ipairs(F.logs) do assert(not line:find("poll error",1,true) and not line:find("model error",1,true),line) end
end
