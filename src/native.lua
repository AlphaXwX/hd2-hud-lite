-- No FFI, unsafe field probing, private loader state edits or custom GUI.
local Native = {frame=0,epoch=0,blocked=false,stats={calls=0,cache_hits=0,scans=0},declarations={}}
local function clear(t) for k in pairs(t) do t[k]=nil end end
Native.clear=clear
local original = SR or {}
Native.source=original
Native.names={}
Native.sr={}
for k,v in pairs(original) do Native.sr[k]=v end
local cached = {exists={},types={},fields={},resources={},alive={},anim={},nodes={},positions={},states={},layers={},owned={}}
local missing={}
local function finite(v) return Fix.finite(v) end
local function valid_id(id) return finite(id) and id>=0 and id%1==0 and id~=32767 end
Native.valid_id=valid_id
function Native.invoke(path,fn,kind,...)
  if IdentitySafety.blocked(path,kind) then return nil,"skipped" end
  if type(fn)~="function" then return nil,"missing" end
  Native.stats.calls=Native.stats.calls+1
  -- Batched must use the sandbox wrapper, NOT chef.call (which resolves the
  -- underlying function and would bypass Chef's persisted read-skip guard).
  if path~="GameSession.game_object_field_batched" and type(chef.call_kind)=="function" then
    return chef.call_kind(path,kind or "hud",...)
  end
  local ok,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p=pcall(fn,...)
  if not ok then return nil,"lua-error" end
  return a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p
end
function Native.read(ns,name,kind,...)
  local source=original[ns]
  local fn=type(source)=="table" and source[name]
  return Native.invoke(ns.."."..name,fn,kind,...)
end
function Native.begin()
  Native.frame=Native.frame+1
  Native.left=40
  -- Other poll work (declarations, avatar, squad) is not search time. Starting
  -- the timer before that work starved every scan on real, slower native APIs.
  Native.started=nil
  Native.scan_spent=0
  Native.exhausted=false
  for _,t in pairs(cached) do clear(t) end
  Native.batches={}
end
function Native.can_scan()
  if Native.left<=0 then Native.exhausted=true;return false end
  if Native.scan_spent>=0.0015 then Native.exhausted=true;return false end
  Native.left=Native.left-1
  Native.stats.scans=Native.stats.scans+1
  return true
end
function Native.scan_type(session,id,call)
  local start=os and os.clock and os.clock() or nil
  local result=Native.is_type(session,id,call)
  if start then Native.scan_spent=Native.scan_spent+math.max(0,os.clock()-start) end
  return result
end
function Native.exists(session,id)
  if not valid_id(id) then return false end
  local value=cached.exists[id]
  if value~=nil then Native.stats.cache_hits=Native.stats.cache_hits+1;return value end
  value=Native.read("GameSession","game_object_exists","object",session,id)==true
  cached.exists[id]=value
  return value
end
function Native.is_type(session,id,call)
  if not Native.exists(session,id) or type(call)~="string" then return false end
  local row=cached.types[id]
  if not row then row={};cached.types[id]=row end
  if row[call]~=nil then Native.stats.cache_hits=Native.stats.cache_hits+1;return row[call] end
  local result=Native.read("GameSession","game_object_is_type",call,session,id,call)
  if result==true or result==false then row[call]=result end
  return result
end
function Native.field(session,id,name)
  if not Native.exists(session,id) or type(name)~="string" then return nil end
  local row=cached.fields[id]
  if not row then row={};cached.fields[id]=row end
  if row[name]~=nil then
    Native.stats.cache_hits=Native.stats.cache_hits+1
    if row[name]==missing then return nil end
    return row[name]
  end
  local value=Native.read("GameSession","game_object_field",name,session,id,name)
  row[name]=value==nil and missing or value
  return value
end
function Native.info(call)
  local known=Native.declarations[call]
  if known and known.value then return known.value end
  if known and S.clock<known.retry then return nil end
  local value=Native.read("Network","object_info",call,call)
  if type(value)~="table" or type(value.fields)~="table" then
    Native.declarations[call]={retry=S.clock+1};return nil
  end
  Native.declarations[call]={value=value}
  return value
end
function Native.batch(session,id)
  if Native.blocked or not Native.exists(session,id) then return nil end
  local value=Native.batches[id]
  if value~=nil then if value==missing then return nil end return value end
  local out={}
  local result,why=Native.read("GameSession","game_object_field_batched","object",session,id,out)
  if why=="skipped" then
    Native.blocked=true;S.batch_blocked=true
    logf("Chef batched-read skip retained; declared known scalar fallback only")
  end
  if type(result)~="table" and next(out)~=nil then result=out end
  if type(result)~="table" or next(result)==nil then result=nil end
  Native.batches[id]=result or missing
  return result
end
function Native.reset()
  Native.epoch=Native.epoch+1
  for _,t in pairs(cached) do clear(t) end
  Native.batches={}
  Native.declarations={}
  -- Never reset Native.blocked: a skip is launch-wide safety state.
end
function Native.xyz(v)
  if v==nil then return nil end
  local V=original.Vector3
  if type(V)=="table" and type(V.x)=="function" then
    local ok,x,y,z=pcall(function() return V.x(v),V.y(v),V.z(v) end)
    if ok and finite(x) and finite(y) and finite(z) then return x,y,z end
  end
  local ok,x,y,z=pcall(function() return v.x or v[1],v.y or v[2],v.z or v[3] end)
  if ok and finite(x) and finite(y) and finite(z) then return x,y,z end
end
function Native.distance(a,b)
  local ax,ay,az=Native.xyz(a)
  local bx,by,bz=Native.xyz(b)
  if ax and bx then return math.sqrt((ax-bx)^2+(ay-by)^2+(az-bz)^2) end
  local value=Native.read("Vector3","distance","position",a,b)
  if finite(value) and value>=0 then return value end
end
function Native.alive(unit)
  if unit==nil then return false end
  local value=cached.alive[unit]
  if value~=nil then return value end
  value=Native.read("Unit","alive","unit",unit)==true
  cached.alive[unit]=value
  return value
end
function Native.position(unit,node)
  if not Native.alive(unit) or not finite(node) or node<1 or node%1~=0 then return nil end
  local per=cached.positions[unit]
  if not per then per={};cached.positions[unit]=per end
  local value=per[node]
  if value==nil then value=Native.read("Unit","world_position","unit",unit,node) or missing;per[node]=value end
  if value~=missing then return value end
end
function Native.units(world,resource)
  if world==nil then return nil end
  local known=cached.resources[resource]
  if known then return known end
  local units=Native.read("World","units_by_resource","resource",world,resource)
  if type(units)~="table" then return nil end
  cached.resources[resource]=units
  return units
end
function Native.owned(session,peer)
  if peer==nil then return nil end
  local value=cached.owned[peer]
  if value~=nil then if value==missing then return nil end return value end
  value=Native.read("GameSession","objects_owned_by","owned",session,peer)
  cached.owned[peer]=type(value)=="table" and value or missing
  return type(value)=="table" and value or nil
end
for _,ns in ipairs({"GameSession","Network","World","Unit"}) do
  local copy={}
  Native.sr[ns]=copy
  for name,fn in pairs(type(original[ns])=="table" and original[ns] or {}) do
    if type(fn)=="function" then
      local path,raw=ns.."."..name,fn
      copy[name]=function(...) return Native.invoke(path,raw,"hud",...) end
    else copy[name]=fn end
  end
end
local GS0,U0=Native.sr.GameSession,Native.sr.Unit
GS0.game_object_exists=Native.exists
GS0.game_object_is_type=Native.is_type
GS0.game_object_field=Native.field
GS0.game_object_field_batched=Native.batch
GS0.objects_owned_by=Native.owned
Native.sr.Network.object_info=Native.info
Native.sr.World.units_by_resource=Native.units
U0.alive,U0.world_position=Native.alive,Native.position
for _,name in ipairs({"animation_has_variable","animation_find_variable","animation_get_variable","node"}) do
  local method=name
  U0[method]=function(unit,key)
    if not Native.alive(unit) then return nil end
    if method=="animation_get_variable" and (not finite(key) or key<1 or key%1~=0) then return nil end
    local per=cached.anim[unit]
    if not per then per={};cached.anim[unit]=per end
    local slot=method..":"..tostring(key)
    if per[slot]~=nil then if per[slot]==missing then return nil end return per[slot] end
    local value=Native.read("Unit",method,"unit",unit,key)
    if (method=="node" or method=="animation_find_variable") and (not finite(value) or value<1 or value%1~=0) then value=nil end
    per[slot]=value==nil and missing or value
    return value
  end
end
local function pack(...) return {n=select("#",...),...} end
function Native.animation_states(unit)
  if IdentitySafety.blocked("Unit.animation_get_state") then return nil end
  if not Native.alive(unit) then return nil end
  if Native.read("Unit","has_animation_state_machine","unit",unit)~=true then return nil end
  local per=cached.states[unit]
  if per then return per~=missing and per or nil end
  -- Use Chef's established, non-kind key so any earlier animation-read skip
  -- remains effective. Chef 1.2.3 caps multi-returns at four: never assume an
  -- unreturned layer (notably body layer 11) exists beyond that boundary.
  local values
  if type(chef.call)=="function" then
    values=pack(chef.call("Unit.animation_get_state",unit))
  else values=pack(Native.read("Unit","animation_get_state","hud",unit)) end
  if values[1]==nil then cached.states[unit]=missing;return nil end
  local result={}
  if type(values[1])=="table" then
    local states=values[1].states or values[1]
    for key,value in pairs(states) do
      if type(key)=="number" and key>=1 and key%1==0 then result[key-1]=value end
    end
    if states[0]~=nil then
      result={}
      for key,value in pairs(states) do if type(key)=="number" and key>=0 and key%1==0 then result[key]=value end end
    end
  else
    for i=1,values.n do
      if type(values[i])=="number" or type(values[i])=="string" then result[i-1]=values[i] end
    end
  end
  cached.states[unit]=result
  return result
end
function Native.animation_snapshot(unit)
  if IdentitySafety.blocked("Unit.animation_get_state") then return nil end
  if not Native.alive(unit) then return nil end
  if Native.read("Unit","has_animation_state_machine","unit",unit)~=true then return nil end
  local per=cached.states[unit]
  if per then return per~=missing and per or nil end
  local raw=original.Unit and original.Unit.animation_get_state
  if type(raw)~="function" or type(chef.call)~="function" then return nil end
  -- Chef 1.2.3 returns only a,b,c,d. Approval MUST precede the full-return
  -- sandbox read: nil/skipped/error never reaches the direct accessor. This
  -- retains the existing animation key and does not clear any loader state.
  local approved=pack(chef.call("Unit.animation_get_state",unit))
  if approved[1]==nil then cached.states[unit]=missing;return nil end
  local all=pack(pcall(raw,unit))
  if all[1]~=true or all[2]==nil then cached.states[unit]=missing;return nil end
  local result={n=all.n-1}
  for i=2,all.n do result[i-1]=all[i] end
  -- Reject a changed/refused snapshot; never turn a reason string into a state.
  if type(result[1])~="table" and result[1]~=approved[1] then cached.states[unit]=missing;return nil end
  if type(result[1])=="table" then
    local source=result[1].states or result[1]
    local first=source[0]~=nil and 0 or 1
    local ordered={n=0}
    while source[first+ordered.n]~=nil do
      ordered.n=ordered.n+1
      ordered[ordered.n]=source[first+ordered.n-1]
      if ordered.n>=128 then break end
    end
    result=ordered
  end
  cached.states[unit]=result
  return result
end
function Native.animation_layer(unit,layer,states)
  if IdentitySafety.blocked("Unit.animation_layer_info") then return nil end
  if not Native.alive(unit) or not finite(layer) or layer<0 or layer%1~=0 then return nil end
  if type(states)~="table" or states[layer]==nil then return nil end
  local per=cached.layers[unit]
  if not per then per={};cached.layers[unit]=per end
  if per[layer]~=nil then return per[layer]~=missing and per[layer] or nil end
  local elapsed,length
  if type(chef.call)=="function" then elapsed,length=chef.call("Unit.animation_layer_info",unit,layer)
  else elapsed,length=Native.read("Unit","animation_layer_info","hud",unit,layer) end
  local result
  if finite(elapsed) and elapsed>=0 and finite(length) and length>0 and length<1e6 then
    result={elapsed=elapsed,length=length,state=states[layer]}
  end
  per[layer]=result or missing
  return result
end
-- Keep the imported EngineCall.call_many -> Identity.action_of chain.
-- Returned state #layer+1 proves the exact requested layer exists. In
-- particular, body layer 11 must actually occur in the full state snapshot.
U0.animation_get_state=function(unit)
  local snapshot=Native.animation_snapshot(unit)
  if not snapshot then return nil end
  return unpack(snapshot,1,snapshot.n)
end
U0.animation_layer_info=function(unit,layer)
  if IdentitySafety.blocked("Unit.animation_layer_info") then return nil end
  if not Native.alive(unit) or not finite(layer) or layer<0 or layer%1~=0 then return nil end
  local snapshot=Native.animation_snapshot(unit)
  if not snapshot or layer>=snapshot.n or snapshot[layer+1]==nil then return nil end
  local per=cached.layers[unit]
  if not per then per={};cached.layers[unit]=per end
  local value=per[layer]
  if value==missing then return nil end
  if not value then
    if type(chef.call)~="function" then return nil end
    local elapsed,length=chef.call("Unit.animation_layer_info",unit,layer)
    if not finite(elapsed) or elapsed<0 or not finite(length) or length<=0 or length>=1e30 then
      per[layer]=missing;return nil
    end
    value={elapsed,length};per[layer]=value
  end
  return value[1],value[2]
end
