-- Lite-shaped pipeline: resolve -> poll -> cached model -> immediate render.
-- The rule modules are bound once; the source boot hook, GUI and Main are not used.
local Model={commands={},command_pool={},count=0,clock=0,ready=false,reload_white={255,255,255}}
local identity=Engine.Identity.new(generated.identity)
local provider=Engine.Provider.new(generated)
-- Zeroing combines authored capability with the live selected option. Missing
-- attachment metadata is unavailable evidence, not proof of an unsupported gun.
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
  self.host_objects={};self.host_peer=nil;self.host_check_at=nil
end
identity:reset()
local original_grip_bucket=identity.grip_bucket
function identity:grip_bucket(grip)
  local rows,set=original_grip_bucket(self,grip)
  if not rows or not set then return rows,set end
  local bucket=self.buckets[grip]
  if not bucket.catalog_added then
    for hash,entry in pairs(Compatibility.weapons) do
      if self.equipment[hash] and entry.grips then
        for _,pose in ipairs(entry.grips) do
          if pose==grip and not set[hash] then rows[#rows+1]=hash;set[hash]=true end
        end
      end
    end
    table.sort(rows);bucket.catalog_added=true
  end
  return rows,set
end
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
  local origins={}
  local provenance=self.host_objects
  for _,id in pairs(owned) do
    if Native.valid_id(id) and not seen[id] then
      list[#list+1]=id;seen[id]=true;provenance[id]=nil
    end
  end
  -- Client equipment can remain network-owned by the host. That list is a
  -- candidate source only: no host player/avatar is admitted, and equipment
  -- requires a fresh declared owner field matching the local peer.
  if grip~=nil then
    if S.clock>=(self.host_check_at or 0) then
      self.host_check_at=S.clock+0.5
      self.host_peer=Native.read('GameSession','game_session_host','players',session)
    end
    local host=self.host_peer
    if host~=nil and host~=peer then
      local remote=Native.owned(session,host)
      if type(remote)=='table' then
        for _,id in pairs(remote) do
          if Native.valid_id(id) and not seen[id] then
            list[#list+1]=id;seen[id]=true;origins[id]=true;provenance[id]=true
          end
        end
      end
    end
  end
  -- Do not forget host provenance when its list is temporarily unavailable;
  -- a previously remote object must still supply a local-owner proof.
  -- Bound work even if another mod adds thousands of network objects.
  local count=math.min(#list,256)
  local first=self.scan_cursor or 0
  local rows={}
  local advanced=0
  for offset=1,count do
    local id=list[(first+offset-1)%math.max(1,#list)+1]
    local hash=self:type_of(session,id,grip)
    if hash and (not origins[id] or (self.equipment[hash] or self.backpacks[hash])
      and self:ownership_ok(session,{goid=id,type=hash})==true) then
      rows[#rows+1]={goid=id,type=hash}
    end
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
  local value,why=original_read(self,session,type_hash,id,row,call)
  if value==nil and why==nil and type(row)=="table" then
    local alias=Compatibility.roles[row.hash]
    if type_hash==identity.player.type and row.hash==identity.player.avatar_field.hash then alias=Compatibility.player_avatar end
    if alias and alias~=row.call then value=Native.field(session,id,alias) end
  end
  return value,why
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
 ["0x69889752"]="c60sehb",["0x1ad6d70f"]="charge",
 ["0x6fee6b03"]="broken",["0xf8d23bd2"]="vnbwh6a",
 ["0x67526982"]="te9ea3",
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
    -- Reviewed stand-in aliases can change between builds while retaining the
    -- exact field hash. Never ask an undeclared field or a guessed name.
    local alternative=Compatibility.roles[key]
    if relation~="player" and value==nil and index and alternative and alternative~=scalar then
      value=Native.field(session,id,alternative)
    end
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
function Model.zeroing_value(reads,resolved)
  local hand=resolved and resolved.hand_weapon
  if type(hand)~='table' then Model.scope_proof=nil;return nil,'no-hand' end
  local raw=reads and reads['hand-weapon']
  local options=raw and raw['0x31f86165']
  if not Fix.finite(options) or options<0 or options%1~=0 then return nil,'unread-options' end
  local selected=math.floor(options/16)%4
  local icon=generated.identity.zeroing[tostring(selected)]
  if icon==nil then return nil,'reserved-zeroing-state' end
  local base=(generated.authored_base['WeaponDataComponentData.scope_zeroing'] or {})[hand.type]
  local deltas=raw['0x98b4aaf0']
  local known=generated.authored_delta['WeaponDataComponentData.scope_zeroing'] or {}
  local value,conflict
  if type(deltas)=='table' then
    for _,id in pairs(deltas) do
      local hash=Model.hash64(id);local found=hash and known[hash]
      if Fix.finite(found) and found>0 then
        if value and value~=found then conflict=true end;value=found
      end
    end
  end
  if conflict then Model.scope_proof=nil;return nil,'ambiguous-scope' end
  local key=tostring(hand.goid)..':'..tostring(hand.type)
  local prior=Model.scope_proof
  if prior and prior.key~=key then prior=nil;Model.scope_proof=nil end
  local authored=Fix.finite(base) and base>0 or value~=nil
  local book=generated.identity.equipment[hand.type]
  if not authored and book and book.no_reserves then
    Model.scope_proof=nil;return nil,'unsupported-scope'
  end
  if not authored and book and (book.ammo_pack or book.spare_pack) then
    Model.scope_proof=nil;return nil,'unsupported-scope'
  end
  -- A positive, defined zeroing choice is runtime evidence. Zero by itself
  -- is common default padding and must never create a scope on support guns.
  if authored or (selected>0 and deltas==nil) then
    Model.scope_proof={key=key,source=authored and 'authored' or 'selection'}
    return icon
  end
  if prior and deltas==nil then return icon end
  Model.scope_proof=nil
  return nil,'zeroing-unconfirmed'
end
function provider:signal(name,reads,resolved)
  if self.signal_reads~=reads then self.signal_reads=reads;self.signal_cache={} end
  local known=self.signal_cache[name]
  if known then
    if known==no_signal then return nil,"no-answer" end
    return known[1],known[2],known[3]
  end
  -- A malformed or newly added rule must not recurse forever.
  self.signal_cache[name]=no_signal
  local value,why,still
  if name=='zeroing' then value,why=Model.zeroing_value(reads,resolved)
  else value,why,still=signal_original(self,name,reads,resolved) end
  if value~=nil then self.signal_cache[name]={value,why,still} end
  return value,why,still
end
function Model.auxiliary(window,resolved)
  -- These are the original signals, evaluated by the Provider. Keep RPM
  -- as a separate setting item so the original first-match function icon
  -- cannot silently consume it when a gun exposes both ammo type and ROF.
  local cells=window.cells
  cells.rof_icon=provider:signal("rof_icon",window.reads,resolved)
  if cells.rof_icon==nil and type(resolved.hand_weapon)=='table' then
    local book=generated.identity.equipment[resolved.hand_weapon.type]
    local read=(window.reads or {})['hand-weapon'] or {}
    local rpm=read['0x4cbcc2a2']
    -- Same-setting matching only: planetary cold can report 90% of the menu
    -- rate. Do not learn a second setting or label arbitrary weapon RPM.
    if book and book.rof and Fix.finite(rpm) and rpm>0 then
      local found,ambiguous=nil,false
      for rate,icon in pairs(book.rof)do
        local value=tonumber(rate)
        if value and (math.abs(rpm-value)<=1.5 or math.abs(rpm-value*0.9)<=1.5)then
          if found and found~=icon then ambiguous=true end;found=icon
        end
      end
      if not ambiguous then cells.rof_icon=found end
    end
  end
  cells.reserve=provider:signal("reserve",window.reads,resolved)
  local hand=resolved.hand_weapon
  local book=type(hand)=="table" and generated.identity.equipment[hand.type]
  if book and book.no_reserves then cells.reserve=nil end
  if Fix.finite(cells.reserve) and cells.reserve>=0 then
    Model.reserve_text=tostring(math.floor(cells.reserve+0.5))
  else Model.reserve_text=nil end
end
function Model.pack_supply(window,resolved)
  local hand,pack=resolved.hand_weapon,resolved.backpack
  Model.pack_ammo=nil
  if type(hand)~="table" or type(pack)~="table" then return end
  local book=generated.identity.equipment[hand.type]
  if not book then return end
  local supply=(window.reads or {}).backpack
  local remaining=supply and supply['0x69889752']
  if not Fix.finite(remaining) or remaining<0 then return end
  local catalog=Compatibility.weapons[hand.type]
  local allowed=book.ammo_pack and book.ammo_pack[pack.type]
  local reload_pack=book.spare_pack and book.spare_pack[pack.type]
  -- A typed worn backpack is not automatically this weapon's ammunition:
  -- require its authored pair, or a catalog-confirmed pack-reload rule.
  if not allowed and not reload_pack then return end
  if not Native.exists(S.session,pack.goid) or not Native.is_type(S.session,pack.goid,Engine.Identity.call_of(identity.authored,pack.type)) then return end
  if identity:on_my_body(S.session,pack)~=true then return end
  local owner=identity:read_field(S.session,pack.type,pack.goid,{hash='0x3ccffa7f',call='g5g7b9d'})
  if owner~=nil then
    local function peer_key(value)
      if type(value)~='string' then return nil end
      return value:lower():gsub('^0x',''):gsub('^0+','')
    end
    local mine,actual=peer_key(S.peer),peer_key(owner)
    if not mine or not actual or mine~=actual then return end
  end
  if allowed then
    local pack_info=Compatibility.packs[pack.type]
    local maximum=(pack_info and pack_info.observed_capacity) or (generated.identity.backpacks[pack.type] or {}).arc_max
    Model.pack_tops=Model.pack_tops or {}
    local key=tostring(pack.goid)..':'..tostring(pack.type)
    local top=Model.pack_tops[key] or maximum
    if Fix.finite(top) and top>0 then top=math.max(top,remaining)
    elseif remaining>0 then top=remaining end
    Model.pack_tops[key]=top
    window.cells.ammo=remaining
    window.cells.ammo_max=top
    window.cells.pack_ammo=remaining
    window.cells.pack_ammo_max=top
    Model.pack_ammo={goid=pack.goid,type=pack.type,value=remaining,maximum=top}
    -- Count and arc belong to the held weapon's display, but their values
    -- originate from this verified pack, not an unrelated local magazine.
    window.bearers['hand-weapon']=hand.goid
    window.cells.reserve=nil;Model.reserve_text=nil
  elseif reload_pack then
    window.cells.reserve=remaining
    Model.reserve_text=tostring(math.floor(remaining+0.5))
  end
end
function Model.scalar_flags(window)
  local raw=(window.reads or {})["hand-weapon"]
  if not raw then return end
  for _,key in ipairs({"0x3132608f","0x88b7cf6d","0xf6275c53"}) do
    local value=raw[key]
    if value==0 or value==1 then raw[key]=value==1 end
  end
end
local OWNER_FIELD={hash='0x3ccffa7f',call='g5g7b9d'}
local function peer_token(value)
  if type(value)~='string' then return nil end
  local key=value:lower():gsub('^0x',''):gsub('^0+','')
  return key~='' and key or '0'
end
function identity:ownership_ok(session,row,call)
  local value,why=self:read_field(session,row.type,row.goid,OWNER_FIELD,call)
  local mine,owner=peer_token(S.peer),peer_token(value)
  if why==nil and mine~=nil and owner~=nil then return mine==owner end
  return not self.host_objects[row.goid]
end
function Model.energy_inputs(window,resolved)
  local hand=resolved.hand_weapon
  local entry=type(hand)=='table' and Compatibility.weapons[hand.type]
  if not entry or not entry.fields.heat then Model.heat_limit=nil;return end
  local raw=(window.reads or {})['hand-weapon'] or {}
  local temperature=raw['0xa5023836']
  local cells=window.cells
  if Fix.finite(cells.heat_max) and cells.heat_max>0 then return end
  local key=tostring(hand.goid)..':'..tostring(hand.type)
  local limit=Model.heat_limit
  if not limit or limit.key~=key then limit={key=key};Model.heat_limit=limit end
  -- An unavailable authored range is not assumed to be 100. Only an actual
  -- overheated sample establishes this object's observed full-heat reference.
  if raw['0xf6275c53']==true and Fix.finite(temperature) and temperature>0 then
    limit.value=math.max(limit.value or 0,temperature)
  end
  if Fix.finite(limit.value) and limit.value>0 and Fix.finite(temperature) and temperature>=0 then
    cells.heat_max=limit.value;cells.heat_shown=temperature
    cells.heat_range_source='observed-overheat'
  else cells.heat_shown=nil end
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
  local window=Model.window
  if window and Model.built_window==window and not Model.animate_model then return end
  Model.count=0;clear(Model.commands)
  if not window then Model.built_window=nil;return end
  local cells=window.cells
  Model.animate_model=Fix.finite(cells.heat_shown) or
    (cells.trigger_held==true and Fix.finite(cells.charge_top) and cells.charge_top>0)
  Model.built_window=window
  Model.builds=(Model.builds or 0)+1
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
  local hand=Model.resolved and Model.resolved.hand_weapon
  local book=type(hand)=="table" and generated.identity.equipment[hand.type]
  if book and book.no_reserves then
    for i=#Model.commands,1,-1 do
      local command=Model.commands[i]
      if command.kind=='number' and (command.column=='reserve' or command.column=='pack_spare') then
        table.remove(Model.commands,i)
      end
    end
    Model.count=#Model.commands
  end
  Model.shapes=shapes
end
function Model.reset()
  Model.scope_proof=nil
  Model.row_layout=nil
  Model.built_window=nil;Model.animate_model=nil
  Model.heat_limit=nil
  identity:reset();identity.scope=nil
  provider:reset_objects();model:reset_objects()
  Model.ready=false;Model.window=nil;Model.resolved=nil
  Model.commands={};Model.count=0
  Model.reload=nil
  Model.pack_retry=nil;Model.equipment_key=nil
  Model.independent_pack=nil
  Model.capacities=nil;Model.animation=nil
  Model.reserve_text=nil
  Model.items=nil
  Model.pack_ammo=nil;Model.pack_tops=nil
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
  if book.no_reserves then
    identity.action_span=nil;Model.reload=nil;Model.animation=nil;return nil
  end
  local is_held=held==true or Fix.finite(held) and held>0
  local is_charging=charging==true or Fix.finite(charging) and charging>0
  if (Fix.finite(top) and top>0 and is_held) or (book.charges_on_heat and is_charging) then
    identity.action_span=nil;Model.reload=nil;Model.animation=nil;return nil
  end
  if not on("hud.lite.reload_animation") then
    identity.action_span=nil
    Model.animation=nil;Model.reload=nil;return nil
  end
  -- Authored weapon rigs remain authoritative when present. Otherwise a
  -- declared positive reload stage gates the same validated BODY layer 11.
  -- Both paths use sampled animation elapsed/length, not a fixed reload timer.
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
    Model.scope_proof=nil
    Model.heat_limit=nil
    Model.items=nil
    Model.generation=identity.generation
    provider:reset_objects();model:reset_objects();Model.window=nil;Model.reload=nil
    S.ratio,S.hp,S.max,S.at=nil,nil,nil,-1e9
    S.stamina,S.stamina_at,S.stamina_next=nil,-1e9,nil
    S.shown_h,S.shown_s=nil,nil
    Model.independent_pack,Model.pack_retry,Model.equipment_key=nil,nil,nil
    Model.capacities=nil;Model.animation=nil
    Model.pack_ammo=nil;Model.pack_tops=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
  end
  S.avatar,S.player,S.body=avatar,identity.player_goid,identity.local_body
  Model.ready=avatar~=nil and resolved and resolved.status~="aboard"
  Model.sample_at=S.clock
  if not Model.ready then
    Model.heat_limit=nil
    Model.items=nil
    Model.window=nil;Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
    Model.pack_ammo=nil
    clear(Model.commands);return
  end
  local state=identity.avatar_state
  if state==2 then
    Model.scope_proof=nil
    Model.heat_limit=nil
    Model.items=nil
    Model.window=nil;Model.reload=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
    Model.pack_ammo=nil;Model.pack_tops=nil
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
    Model.heat_limit=nil
    Model.equipment_key=key;model:reset_objects();Model.reload=nil;Model.animation=nil
    S.shown_a,S.thermal,S.energy,S.heat_sample_at=nil,nil,nil,nil
    identity.action_span=nil
    Model.energy=nil;Model.reserve_text=nil;Model.reload_visual=nil
    Model.pack_ammo=nil
  end
  local window=provider:read(resolved,S.session)
  Model.scalar_flags(window)
  resolved.action=Model.action(resolved,window)
  provider:fill(resolved,window)
  Model.energy_inputs(window,resolved)
  local hand_entry=type(resolved.hand_weapon)=='table' and Compatibility.weapons[resolved.hand_weapon.type]
  local hand_book=type(resolved.hand_weapon)=='table' and generated.identity.equipment[resolved.hand_weapon.type]
  if hand_entry and hand_book and hand_entry.observed_charge_seconds and hand_entry.fields.heat then
    local raw=(window.reads or {})['hand-weapon'] or {}
    window.cells.trigger_held=raw['0x88b7cf6d']
    window.cells.charge_rounds=nil
  end
  Model.auxiliary(window,resolved)
  Model.capacity(window,resolved)
  Model.pack_supply(window,resolved)
  Model.sample_visual(window,resolved)
  Model.window=window
  S.weapon_obj=resolved.hand_weapon
end
Model.generated=generated
