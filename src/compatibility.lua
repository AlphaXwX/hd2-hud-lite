-- Reviewed weapon/field compatibility integration.
-- Attribution and applicable terms are centralized in THIRD_PARTY_NOTICES.md.
local Compatibility={new_types=0,aliases={},roles={},packs={},weapons={}}
do
  local identity=generated.identity
  for hash,role in pairs(WeaponCatalog.roles) do
    Compatibility.roles["0x"..role.id]=role.name
  end
  local function call_alias(hash,old,current)
    if old and current and old~=current then Compatibility.aliases[old]=current end
  end
  call_alias(identity.avatar.type,identity.avatar.call,WeaponCatalog.avatar.name)
  Compatibility.player_avatar=WeaponCatalog.player.avatar
  for hash,entry in pairs(WeaponCatalog.weapons) do
    Compatibility.weapons[hash]=entry
    local old=identity.equipment[hash]
    if old then call_alias(hash,old.call,entry.call)
    elseif entry.grips and entry.fields.owner then
      identity.equipment[hash]={call=entry.call,grip=entry.grips[1],catalog_type=true}
      Compatibility.new_types=Compatibility.new_types+1
      -- Seed observations are only a fallback for an absent authored maximum;
      -- no existing weapon's attachment-specific capacity is overwritten.
      if entry.observed_capacity and entry.observed_capacity>0 then
        generated.authored_base['WeaponMagazineComponentData.capacity'][hash]=entry.observed_capacity
      end
      if entry.observed_heat_max and entry.observed_heat_max>0 then
        generated.authored_base['WeaponHeatComponentData.overheat_temperature'][hash]=entry.observed_heat_max
      end
      if entry.observed_cooling_rate and entry.observed_cooling_rate>0 then
        generated.authored_base['WeaponHeatComponentData.temp_loss_per_second'][hash]=entry.observed_cooling_rate
      end
      if entry.observed_charge_seconds and entry.observed_charge_seconds>0 then
        generated.authored_base['WeaponChargeComponentData.charge_top'][hash]=entry.observed_charge_seconds
        generated.authored_base['WeaponChargeComponentData.charge_full_at'][hash]=entry.observed_charge_seconds
        if entry.fields.heat then identity.equipment[hash].charges_on_heat=true end
      end
    end
    local book=identity.equipment[hash]
    if book then
      -- A magazine counter alone does not establish a reload mechanism.
      -- Only reviewed charge/heat types without a reload stage or rig qualify.
      book.cooldown_only=entry.fields.heat==true and entry.observed_charge_seconds~=nil
        and not entry.fields.reload_stage and book.reload==nil
      -- Shared magazine counters exist even on throw-away launchers. No
      -- reload declaration/rig or authored supply relationship means that
      -- reserve magazines are not an applicable display (including zero).
      book.no_reserves=book.cooldown_only or (entry.fields.rounds==true
        and not entry.fields.heat and not entry.fields.reload_stage and book.reload==nil
        and not book.spare_pack and not book.ammo_pack and not entry.pack_reserve and not entry.fed)
      if book.cooldown_only then book.cools_while_overheated=true end
      local defaults={
        ['WeaponHeatComponentData.overheat_temperature']=entry.observed_heat_max,
        ['WeaponHeatComponentData.temp_loss_per_second']=entry.observed_cooling_rate,
        ['WeaponChargeComponentData.charge_top']=entry.observed_charge_seconds,
        ['WeaponChargeComponentData.charge_full_at']=entry.observed_charge_seconds,
      }
      for field,value in pairs(defaults) do
        local values=generated.authored_base[field]
        if values and values[hash]==nil and type(value)=='number' and value>0 then values[hash]=value end
      end
      if entry.fields.heat and entry.observed_charge_seconds then book.charges_on_heat=true end
    end
  end
  for hash,entry in pairs(WeaponCatalog.backpacks) do
    Compatibility.packs[hash]=entry
    local old=identity.backpacks[hash]
    if not old then old={call=entry.call};identity.backpacks[hash]=old
    else call_alias(hash,old.call,entry.call) end
    if entry.observed_capacity and not old.arc_max then old.arc_max=entry.observed_capacity end
  end
end

-- Resolve literal stand-in names from either supported declaration set. Every
-- alternative was verified offline to hash to the same exact type/field ID.
local original_is_type=Native.is_type
function Native.is_type(session,id,call)
  local value=original_is_type(session,id,call)
  if value==true then return value end
  local alias=Compatibility.aliases[call]
  if alias then return original_is_type(session,id,alias) end
  return value
end
Native.sr.GameSession.game_object_is_type=Native.is_type
local original_info=Native.info
function Native.info(call)
  local info=original_info(call)
  if info then return info end
  local alias=Compatibility.aliases[call]
  return alias and original_info(alias) or nil
end
Native.sr.Network.object_info=Native.info
