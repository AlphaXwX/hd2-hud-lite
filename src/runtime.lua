-- Lite-shaped pipeline: resolve -> poll -> cached model -> immediate render.
-- The rule modules are bound once; the source boot hook, GUI and Main are not used.
local Model={commands={},command_pool={},count=0,clock=0,ready=false,reload_white={255,255,255}}
local identity=Engine.Identity.new(generated.identity)
local provider=Engine.Provider.new(generated)
local snapshot=Engine.Snapshot.new(generated)
local model=Engine.Model.new(generated)
local renderer=Engine.Renderer.new(generated)
Model.identity,Model.provider,Model.snapshot,Model.model,Model.renderer=identity,provider,snapshot,model,renderer

-- Normalize the authored 32-bit field keys once, including numeric descriptor ids.
function Model.hash(value)
  if type(value)=="number" then
    if not Fix.finite(value) or value%1~=0 then return nil end
    if value<0 then value=value+4294967296 end
    if value<0 or value>=4294967296 then return nil end
    return "0x"..string.format("%08x",value)
  end
  return Fix.hex(value,8)
end
local identity_reset=identity.reset
function identity:reset()
  identity_reset(self)
  self.scan_progress={}; self.scan_misses={}
  self._squad_at=0
end
identity:reset()
-- A GOID is not an immutable type. Every positive memo is revalidated; every
-- negative memo expires. Unfinished searches resume, rather than restarting.
function identity:scan_types(session,id,missed,scope,rows)
  if type(rows)~="table" then return nil end
  local tag=tostring(scope or "base")
  local progress=self.scan_progress[id]
  if not progress then progress={};self.scan_progress[id]=progress end
  local mark=progress[tag]
  if type(mark)=="table" and mark.until_at and S.clock<mark.until_at then return nil end
  local start=type(mark)=="number" and mark or 1
  for i=start,#rows do
    if not Native.can_scan() then progress[tag]=i;return nil end
    local hash=rows[i]
    local call=Engine.Identity.call_of(self.authored,hash)
    if type(call)=="string" then
      self.counters.type_calls=self.counters.type_calls+1
      if Native.scan_type(session,id,call)==true then
        self.object_type[id]=hash;progress[tag]=nil;return hash
      end
    end
  end
  progress[tag]={until_at=S.clock+1}
  return nil
end
function identity:type_of(session,id,grip)
  if not Native.valid_id(id) or not Native.exists(session,id) then
    self.object_type[id],self.scan_progress[id]=nil,nil;return nil
  end
  local known=self.object_type[id]
  if id==self.player_goid and Native.is_type(session,id,self.player.call)==true then
    self.object_type[id]=self.player.type
    return self.player.type
  end
  if known then
    local call=Engine.Identity.call_of(self.authored,known)
    if Native.is_type(session,id,call)==true then
      if self:used_this_window(known,grip) then return known end
      return nil
    end
    self.object_type[id],self.scan_progress[id]=nil,nil
    self.counters.type_recycled=self.counters.type_recycled+1
  end
  -- Active weapon first. Scanning every backpack before every weapon consumed
  -- the complete budget before reaching the equipped item.
  if grip~=nil and grip~=0 then
    local got=self:scan_types(session,id,{},grip,(self:grip_bucket(grip)))
    if got then return got end
  end
  local base,scope=self:base_candidates()
  return self:scan_types(session,id,{},scope,base)
end
function identity:player_object(session,rows)
  local known=self.player_goid
  if known~=nil and Native.is_type(session,known,self.player.call)==true then
    return {goid=known,type=self.player.type},1
  end
  self.player_goid=nil
  local owned=Native.owned(session,S.peer)
  if type(owned)~="table" then return nil,0 end
  local found,count,seen=nil,0,{}
  -- One known player-type check per owned id, never the whole equipment table.
  -- This must not depend on the optional/background discovery budget.
  local asks=0
  for _,id in pairs(owned) do
    if Native.valid_id(id) and not seen[id] then
      seen[id]=true;asks=asks+1
      if Native.is_type(session,id,self.player.call)==true then
        found={goid=id,type=self.player.type};count=count+1
      end
      if asks>=256 then break end
    end
  end
  if count==1 then self.player_goid=found.goid;self.object_type[found.goid]=self.player.type end
  return found,count
end
function identity:owned_objects(session,peer,grip,owned)
  if owned==nil then owned=Native.owned(session,peer) end
  if type(owned)~="table" then return nil end
  local list,seen={},{}
  for _,id in pairs(owned) do
    if Native.valid_id(id) and not seen[id] then list[#list+1]=id;seen[id]=true end
  end
  -- Bound work even if another mod adds thousands of network objects.
  local count=math.min(#list,256)
  local first=self.scan_cursor or 0
  local rows={}
  local advanced=0
  for offset=1,count do
    local id=list[(first+offset-1)%math.max(1,#list)+1]
    local hash=self:type_of(session,id,grip)
    if hash then rows[#rows+1]={goid=id,type=hash} end
    if (Native.exhausted or Native.left and Native.left<=0) and advanced==0 then advanced=offset end
  end
  self.scan_cursor=(first+(advanced>0 and advanced or count))%math.max(1,#list)
  self.counters.scans=self.counters.scans+1
  self.counters.owned_seen=#list
  return rows
end
function identity:base_candidates()
  if self.base then return self.base,"base" end
  local rows={self.player.type,self.avatar.type}
  local packs={}
  for hash in pairs(self.backpacks) do packs[#packs+1]=hash end
  table.sort(packs)
  for _,hash in ipairs(packs) do rows[#rows+1]=hash end
  self.base=rows
  return rows,"base"
end
-- Keep declarations across object-only invalidations, retry transient failures.
function identity:declared_fields(type_hash,call)
  local info=Native.info(call)
  if not info then return {} end
  local known=self.type_fields[type_hash]
  if known then return known end
  known={}
  for _,row in pairs(info.fields) do
    local hash=type(row)=="table" and Model.hash(row.id)
    if hash then known[hash]=true end
  end
  self.type_fields[type_hash]=known
  return known
end
local original_read=identity.read_field
function identity:read_field(session,type_hash,id,row,call)
  if not Native.exists(session,id) then return nil,"object-gone" end
  return original_read(self,session,type_hash,id,row,call)
end
-- World transitions invalidate every identity cache: stale object ids must not
-- survive a world change. Peer and avatar changes share the same reset path.
function identity:sync(session,world,peer)
  local old=self.scope
  if not old or old.session~=session or old.world~=world or old.peer~=peer then
    self:reset();self.scope={session=session,world=world,peer=peer}
  end
end
function identity:bind_body(session,world,avatar,in_control)
  local state=self:avatar_value(session,avatar,self.avatar.state_field)
  self.avatar_state,self.avatar_state_read=state,true
  if state~=0 then self:release_body(state==2 and "dead" or "state-unconfirmed");return nil end
  local position=self:avatar_value(session,avatar,self.avatar.position_field)
  if not Native.xyz(position) then self:release_body("no-avatar-position");return nil end
  if self.local_body and Native.alive(self.local_body) then
    local p=Native.position(self.local_body,1)
    local d=p and Native.distance(position,p)
    if d and d<=6 then return self.local_body end
  end
  self:release_body("body-unavailable")
  local resource=Engine.Identity.resource_key(self.counters,self.avatar.third_person)
  if resource==nil then return nil end
  local units=Native.units(world,resource)
  if type(units)~="table" then return nil end
  local winner,nearest,tied=nil,6,false
  local seen={}
  for _,unit in pairs(units) do
    if not seen[unit] and Native.alive(unit) then
      seen[unit]=true
      local p=Native.position(unit,1)
      local d=p and Native.distance(position,p)
      if d and d<nearest-0.001 then winner,nearest,tied=unit,d,false
      elseif d and math.abs(d-nearest)<=0.001 then tied=true end
    end
  end
  if not winner or tied then self.body_binding={status="ambiguous"};return nil end
  self.local_body=winner;self.body_binding={status="bound",distance=nearest}
  return winner
end
function identity:at_wield_node(unit,anchor,row)
  local position=Native.position(unit,1)
  local distance=position and Native.distance(anchor,position)
  local offset=row.wield_offset or self.equipment_defaults.wield_offset or 0
  return distance~=nil and math.abs(distance-offset)<=0.025
end
-- Control locks are not proof of a weapon change (ADS also locks them).
local native_control=identity.in_control
function identity:in_control(session,avatar)
  local value=native_control(self,session,avatar)
  local state=self:avatar_value(session,avatar,self.avatar.state_field)
  if state==0 and value==false then return true end
  return value
end
local native_rotation=identity.rotation_free
function identity:rotation_free(session,avatar)
  local value=native_rotation(self,session,avatar)
  if value==false and self.avatar_state==0 and self.local_body then return true end
  return value
end
local narrow_original=identity.narrow_by_wield
function identity:narrow_by_wield(world,candidates)
  local held,why=narrow_original(self,world,candidates)
  if #held>0 then return held,why end
  -- Unique, locally carried and typed object, same proof Lite uses for ADS.
  -- Multiple carry candidates remain ambiguous; do not select nearest weapon.
  local found={}
  for _,row in ipairs(candidates) do
    local book=self.equipment[row.type]
    local mask=book and self:carry_value(S.session,row,book.call)
    if Fix.finite(mask) and mask%4==0 and not self:bound_elsewhere(S.session,row,book.call) then
      row.mask=mask;found[#found+1]=row
    end
  end
  if #found==1 and why~="multiple-wield-units" then return found,"unique-local-carry" end
  return held,why
end
local follow_original=identity.follow
function identity:follow(slot,counter,session,parent,find)
  -- A live parent can point at a different live child after a mode switch.
  -- Revalidate its authored link, rather than keeping a child forever.
  self[slot]=nil
  return follow_original(self,slot,counter,session,parent,find)
end
function identity:squad(session,peer)
  if not on("hud.lite.squad") and not on("hud.lite.self_booster") then return nil end
  if S.clock<(self._squad_at or 0) and self.squad_memo then return self.squad_memo.rows end
  self._squad_at=S.clock+0.5
  local peers=Native.read("GameSession","peers","players",session)
  if type(peers)~="table" then return nil end
  local memo=self.squad_memo or {found={},rows={}}
  self.squad_memo=memo
  local seat=0
  for _,other in ipairs(peers) do
    if other~=peer then
      seat=seat+1
      if seat>self.seats then break end
      local row=memo.found[seat]
      if not row or row.peer~=other or not Native.is_type(session,row.goid,self.player.call) then
        row=nil
        local owned=Native.owned(session,other)
        if type(owned)=="table" then
          local n=0
          for _,id in pairs(owned) do
            if Native.is_type(session,id,self.player.call)==true then
              if row then row=nil;break end
              row={goid=id,type=self.player.type,peer=other}
            end
            n=n+1;if n>=256 then break end
          end
        end
      end
      memo.found[seat],memo.rows[seat]=row,row or {}
    end
  end
  for i=seat+1,self.seats do memo.found[i]=nil;memo.rows[i]=false end
  return memo.rows
end

local SCALARS={
 ["0xd7a5d63e"]="4fqtox",["0x4a893e74"]="gaj_1dw",["0x04ec5b95"]="ip47m3",
 ["0xe525fa9c"]="bblnvyx",["0xa74ef0d5"]="agzh10j",["0xcd889dbc"]="gbgqot6",
 ["0x3132608f"]="a70n1_",["0x49c250a6"]="fire_mode",["0x31f86165"]="gahi551",
 ["0x4cbcc2a2"]="v7xdy8",
 -- Offline verified against authored role hashes; never probe names.
 ["0xa5023836"]="temperature",["0x88b7cf6d"]="is_charging",
 ["0xec64918b"]="B9h6f9a4",["0x9a34c336"]="jCr15Dyv",
 ["0xf6275c53"]="is_overheated",
}
function provider:slots_of(hash)
  if hash==nil then return nil end
  if self.slots[hash] then return self.slots[hash] end
  local call=self:call_of(hash)
  local info=call and Native.info(call)
  if not info then return nil end
  local slots={}
  for index,desc in pairs(info.fields) do
    if type(index)=="number" and index%1==0 and type(desc)=="table" then
      local key=Model.hash(desc.id)
      if key then slots[key]=index end
    end
  end
  if next(slots)==nil then return nil end
  self.slots[hash]=slots
  return slots
end
function provider:batched(session,id,relation,hash)
  local slots=self:slots_of(hash)
  if not slots then return nil end
  local batch=Native.batch(session,id)
  local values={}
  for _,key in ipairs(self:hashes_of(relation)) do
    local index=slots[key]
    local value=index and batch and batch[index]
    if value==nil and index and batch then
      for _,group in pairs(batch) do if type(group)=="table" and group[index]~=nil then value=group[index];break end end
    end
    local scalar=SCALARS[key]
    -- The player relation must use the same verified names as squad peers;
    -- hash cd889dbc means a different field on a weapon and on a player.
    if relation=="player" then
      scalar=key=="0x3b12bd49" and "booster" or key=="0xcd889dbc" and "gbgqot6" or nil
    end
    if value==nil and index and scalar then value=Native.field(session,id,scalar) end
    if value~=nil and (type(value)~="number" or Fix.finite(value)) then values[key]=value end
  end
  self.counters.batched_calls=self.counters.batched_calls+1
  return next(values) and values or nil
end
function provider:one_by_one(session,id,relation)
  local call=identity.player.call
  if not Native.is_type(session,id,call) then return nil end
  local fields=identity:declared_fields(identity.player.type,call)
  local held=self.steady[relation]
  if not held or held.goid~=id or S.clock>=(held.until_at or 0) then
    held={goid=id,values={},until_at=S.clock+1};self.steady[relation]=held
  end
  local result={}
  for hash,name in pairs(self.foreign_calls[relation] or {}) do
    if fields[hash] then
      local value=held.values[hash]
      if value==nil then value=Native.field(session,id,name) end
      result[hash]=value
      if (self.foreign_steady[relation] or {})[hash] and value~=nil then held.values[hash]=value end
    end
  end
  return result
end
function provider:seated(resolved,slot)
  local row=slot and resolved and resolved[slot]
  return type(row)=="table" and row.type or nil
end
local plus_original=provider.plus
function provider:plus(name,reads,base,resolved)
  if name=="ammo" then
    local chamber=self:cell_of(reads,name,"chamber")
    if Fix.finite(chamber) and chamber>=0 and chamber<=1 then
      if base==nil then return chamber>0 and chamber or nil end
      return base+chamber
    end
  end
  return plus_original(self,name,reads,base,resolved)
end
-- Preserve all 64 hash bits. tostring(IdString64) is often '#ID[hex]', not
-- plain hex; the original pad16 silently missed those capacity delta entries.
function Model.hash64(value)
  if type(value)=="number" then
    if not Fix.finite(value) or value<0 or value%1~=0 or value>9007199254740991 then return nil end
    local hi=math.floor(value/4294967296)
    return "0x"..string.format("%08x%08x",hi,value-hi*4294967296)
  end
  local text=tostring(value):lower()
  local hex=text:match("^#id%[(%x+)%]$") or text:match("^0x(%x+)$") or text:match("^(%x+)$")
  if not hex or #hex>16 then return nil end
  return "0x"..string.rep("0",16-#hex)..hex
end
local overridden_original=provider.overridden
function provider:overridden(name,reads,resolved,entry)
  if entry.delta_from then
    local array=self:cell_of(reads,name,entry.delta_from)
    local book=self.authored_delta[entry.authored] or {}
    local found,unique=nil,{}
    if type(array)=="table" then
      for _,raw in pairs(array) do
        local hash=Model.hash64(raw)
        local value=hash and book[hash]
        if Fix.finite(value) and value>0 then unique[value]=true;found=value end
      end
    end
    if found then
      local n=0 for _ in pairs(unique) do n=n+1 end
      if n==1 then return found end
      return nil
    end
  end
  return overridden_original(self,name,reads,resolved,entry)
end
function Model.capacity(window,resolved)
  local hand=resolved and resolved.hand_weapon
  if type(hand)~="table" then return end
  local cells=window.cells
  local ammo=cells.ammo
  if not Fix.finite(ammo) or ammo<0 then return end
  local raw=(window.reads or {})["hand-weapon"] or {}
  -- The magazine body excludes the chamber; this distinguishes 31/30 from an
  -- actual 46-round magazine. Never let chamber-only +1 inflate capacity.
  local chamber=raw["0x4a893e74"]
  local extra=(chamber==false) and 1 or 0
  if Fix.finite(chamber) and chamber>=0 and chamber<=1 then extra=chamber end
  local loaded=math.max(0,ammo-extra)
  local selected=raw["0xa74ef0d5"]
  local key=tostring(hand.goid)..":"..tostring(hand.type)..":"..tostring(selected)
  Model.capacities=Model.capacities or {}
  local known=Model.capacities[key] or {loaded=0}
  Model.capacities[key]=known
  local authored=cells.ammo_max
  local cap=Fix.finite(authored) and authored>0 and authored or nil
  if cap then
    if known.authored and known.authored~=cap then known.loaded=0 end
    known.authored=cap
    -- A guarded channel can be unavailable, including the delta array (the
    -- supplied launch log confirms SAFE SCALAR). Use the actual observed
    -- loaded count as a lower bound, retaining it as rounds are fired.
    known.loaded=math.max(known.loaded,loaded)
    cells.ammo_max=math.max(cap,known.loaded)
    Model.capacity_source=known.loaded>cap and "observed lower bound" or "authored/delta"
  end
  -- Unknown capacity remains unknown: a partially used magazine alone cannot
  -- reveal its true maximum. Do not synthesize /30 for unknown equipment.
end
local signal_original=provider.signal
local no_signal={}
function provider:signal(name,reads,resolved)
  if self.signal_reads~=reads then self.signal_reads=reads;self.signal_cache={} end
  local known=self.signal_cache[name]
  if known then
    if known==no_signal then return nil,"no-answer" end
    return known[1],known[2],known[3]
  end
  -- A malformed or newly added rule must not recurse forever.
  self.signal_cache[name]=no_signal
  local value,why,still=signal_original(self,name,reads,resolved)
  if value~=nil then self.signal_cache[name]={value,why,still} end
  return value,why,still
end
function Model.auxiliary(window,resolved)
  -- These are the original signals, evaluated by the Provider. Keep RPM
  -- as a separate setting item so the original first-match function icon
  -- cannot silently consume it when a gun exposes both ammo type and ROF.
  local cells=window.cells
  cells.rof_icon=provider:signal("rof_icon",window.reads,resolved)
  cells.reserve=provider:signal("reserve",window.reads,resolved)
  if Fix.finite(cells.reserve) and cells.reserve>=0 then
    Model.reserve_text=tostring(math.floor(cells.reserve+0.5))
  else Model.reserve_text=nil end
end
function Model.scalar_flags(window)
  local raw=(window.reads or {})["hand-weapon"]
  if not raw then return end
  for _,key in ipairs({"0x3132608f","0x88b7cf6d","0xf6275c53"}) do
    local value=raw[key]
    if value==0 or value==1 then raw[key]=value==1 end
  end
end
local host={}
function host:arc(spec) Model.record(spec) end
host.icon,host.number=host.arc,host.arc
function Model.record(spec)
  Model.count=Model.count+1
  local command=Model.command_pool[Model.count]
  if not command then command={};Model.command_pool[Model.count]=command end
  clear(command)
  for key,value in pairs(spec) do command[key]=value end
  local shape=Model.shape_by_key and Model.shape_by_key[spec.key]
  if shape then
    command.column,command.raw,command.maximum=shape.column,shape.raw,shape.max
    if shape.column=="heat_shown" and Fix.finite(command.fraction) then
      -- Original retained rendering clips its "fill" fraction the opposite
      -- way. Lite's screen arc grows with heat, not with remaining cooling.
      command.fraction=1-command.fraction
    end
  end
  Model.commands[Model.count]=command
end
function Model.build()
  Model.count=0;clear(Model.commands)
  if not Model.window then return end
  -- Reload values are the original action_of result. Do not replace
  -- body elapsed with weapon elapsed or extrapolate it using wall-clock time.
  local prepared=model:prepare(Model.window,S.clock)
  local assembled=snapshot:assemble(prepared)
  local shapes=model:shapes(assembled)
  Model.shape_by_key=Model.shape_by_key or {}
  clear(Model.shape_by_key)
  for _,side in ipairs(generated.sides) do
    local sources={}
    for _,entry in ipairs(assembled[side] or {}) do sources[entry.key]=entry end
    for _,shape in ipairs(shapes[side] or {}) do
      shape.column=sources[shape.key] and sources[shape.key].column
      Model.shape_by_key[shape.key]=shape
    end
  end
  renderer:draw(shapes,host)
  Model.energy_commands(prepared)
  Model.shapes=shapes
end
function Model.reset()
  identity:reset();identity.scope=nil
  provider:reset_objects();model:reset_objects()
  Model.ready=false;Model.window=nil;Model.resolved=nil
  Model.commands={};Model.count=0
  Model.reload=nil
  Model.pack_retry=nil;Model.equipment_key=nil
  Model.independent_pack=nil
  Model.capacities=nil;Model.animation=nil
  Model.reserve_text=nil
  Model.energy=nil;Model.reload_visual=nil
  S.shown_a,S.thermal,S.energy,S.heat_sample_at=nil,nil,nil,nil
  S.ratio,S.hp,S.max,S.at=nil,nil,nil,-1e9
  S.stamina,S.stamina_at,S.stamina_next=nil,-1e9,nil
  S.shown_h,S.shown_s=nil,nil
  S.player,S.avatar,S.body,S.weapon_obj=nil,nil,nil,nil
  S.health_index,S.health_index_missing=nil,nil
  S.channel="waiting";S.dumped=nil
end
function Model.valid_world()
  if not Model.ready then return false end
  if S.clock-(Model.sample_at or -1e9)>0.3 then return false end
  if type(chef.world_id)=="function" and chef.world_id()~=S.world_id then return false end
  if type(chef.world)=="function" and chef.world()~=S.world then return false end
  return true
end
function Model.action(resolved,window)
  local hand=resolved.hand_weapon
  if type(hand)~="table" then identity.action_span=nil;Model.reload=nil;Model.animation=nil;return nil end
  local raw=(window.reads or {})["hand-weapon"] or {}
  local held=raw["0x3132608f"]
  local charging=raw["0x88b7cf6d"]
  local top=provider:signal("charge_top",window.reads,resolved)
  local book=generated.identity.equipment[hand.type] or {}
  local is_held=held==true or Fix.finite(held) and held>0
  local is_charging=charging==true or Fix.finite(charging) and charging>0
  if (Fix.finite(top) and top>0 and is_held) or (book.charges_on_heat and is_charging) then
    identity.action_span=nil;Model.reload=nil;Model.animation=nil;return nil
  end
  if not on("hud.lite.reload_animation") then
    identity.action_span=nil
    Model.animation=nil;Model.reload=nil;return nil
  end
  -- Verbatim original algorithm: weapon reload rig selects seat/layer/state;
  -- local BODY animation layer 11 supplies elapsed and runtime clip length;
  -- authored clip/tail and first observed body elapsed supply normalization.
  -- Do not gate this on replicated reload_stage: that is only the original
  -- fallback for an unlisted equipment row, not a prerequisite for known rigs.
  local reading=identity:action_of(hand,identity.local_body,window)
  if not reading or not Fix.finite(reading.elapsed) or not Fix.finite(reading.length) or reading.length<=0 then
    Model.animation=nil;Model.reload=nil;return nil
  end
  local unit=identity.local_body
  local span=identity.action_span
  local layer=(generated.identity.action or {}).layer
  local state=span and span.index or reading.state
  local length=reading.length
  local prior=Model.animation
  local key=tostring(hand.goid)..":"..tostring(hand.type)..":"..tostring(layer)..":"..tostring(state)
  local speed=0
  local continuous=prior and prior.key==key and prior.length==length and reading.elapsed>=prior.elapsed
  if continuous and S.clock>prior.at then
    speed=math.max(0,math.min(4,(reading.elapsed-prior.elapsed)/(S.clock-prior.at)))
  end
  local current={key=key,goid=hand.goid,unit=unit,layer=layer,state=state,elapsed=reading.elapsed,
    length=length,at=S.clock,speed=speed,continuous=continuous==true}
  Model.animation=current;Model.reload=nil
  reading.animation=true
  return reading
end
function Model.sample()
  Native.begin()
  local resolved=identity:resolve(S.session,S.world,S.peer)
  Model.resolved=resolved
  S.channel=resolved and (resolved.reason or resolved.status) or "unresolved"
  local avatar=resolved and type(resolved.avatar)=="table" and resolved.avatar.goid or nil
  if not Native.valid_id(avatar) or not Native.is_type(S.session,avatar,identity.avatar.call) then avatar=nil end
  if Model.generation~=identity.generation or S.avatar~=avatar then
    Model.generation=identity.generation
    provider:reset_objects();model:reset_objects();Model.window=nil;Model.reload=nil
    S.ratio,S.hp,S.max,S.at=nil,nil,nil,-1e9
    S.stamina,S.stamina_at,S.stamina_next=nil,-1e9,nil
    S.shown_h,S.shown_s=nil,nil
    Model.independent_pack,Model.pack_retry,Model.equipment_key=nil,nil,nil
    Model.capacities=nil;Model.animation=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
  end
  S.avatar,S.player,S.body=avatar,identity.player_goid,identity.local_body
  Model.ready=avatar~=nil and resolved and resolved.status~="aboard"
  Model.sample_at=S.clock
  if not Model.ready then
    Model.window=nil;Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
    clear(Model.commands);return
  end
  local state=identity.avatar_state
  if state==2 then
    Model.window=nil;Model.reload=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
    S.ratio,S.hp,S.at=nil,nil,-1e9;S.stamina,S.stamina_at=nil,-1e9
    clear(Model.commands);return
  end
  -- Original resolve exits before backpack discovery when unarmed/no grip.
  -- Resolve the pack independently so dropping a weapon never hides its gauge.
  if resolved.backpack==nil and Model.independent_pack then
    local pack=Model.independent_pack
    if Native.exists(S.session,pack.goid) and Native.is_type(S.session,pack.goid,Engine.Identity.call_of(identity.authored,pack.type))
      and identity:on_my_body(S.session,pack)==true then
      resolved.backpack=pack;resolved.pack_link=identity:find_pack_link(S.session,pack)
    else Model.independent_pack=nil end
  end
  if resolved.backpack==nil and S.clock>=(Model.pack_retry or 0) then
    Model.pack_retry=S.clock+0.5
    local rows=identity:owned_objects(S.session,S.peer,resolved.grip,Native.owned(S.session,S.peer))
    local pack,reason=identity:find_backpack(S.session,rows or {})
    resolved.backpack,resolved.backpack_reason=pack,reason
    Model.independent_pack=pack
    if pack then resolved.pack_link=identity:find_pack_link(S.session,pack) end
  end
  if resolved.backpack then Model.independent_pack=resolved.backpack end
  local hand,pack=resolved.hand_weapon,resolved.backpack
  local key=(type(hand)=="table" and tostring(hand.goid)..":"..tostring(hand.type) or "-")..
    "/"..(type(pack)=="table" and tostring(pack.goid)..":"..tostring(pack.type) or "-")
  if Model.equipment_key~=key then
    Model.equipment_key=key;model:reset_objects();Model.reload=nil;Model.animation=nil
    S.shown_a,S.thermal,S.energy,S.heat_sample_at=nil,nil,nil,nil
    identity.action_span=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
  end
  local window=provider:read(resolved,S.session)
  Model.scalar_flags(window)
  resolved.action=Model.action(resolved,window)
  provider:fill(resolved,window)
  Model.auxiliary(window,resolved)
  Model.capacity(window,resolved)
  Model.sample_visual(window,resolved)
  Model.window=window
  S.weapon_obj=resolved.hand_weapon
end
Model.generated=generated
