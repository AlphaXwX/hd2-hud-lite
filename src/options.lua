-- Preserve existing hud.lite.* settings; add any missing options.
option("hud.lite.health", {type="toggle",label="Health ring (outer left)",default=true})
option("hud.lite.backpack", {type="toggle",label="Backpack ring (third left)",default=true})
option("hud.lite.squad", {type="toggle",label="Squad boosters and death icons",default=true})
option("hud.lite.self_booster", {type="toggle",label="Own booster icon",default=true})
option("hud.lite.reserves", {type="toggle",label="Reserve / backpack numbers",default=true})
option("hud.lite.icon_position", {type="choice",label="Weapon icon position",choices={"crosshair","game HUD"},default=1})
option("hud.lite.idle", {type="choice",label="Show when idle",choices={"full brightness","faint (30%)"},default=1})
option("hud.lite.number_mode", {type="choice",label="Centre ammunition format",choices={"rounds / capacity","rounds only"},default=1})
option("hud.lite.reload_animation", {type="toggle",label="Reload progress",default=true})
option("hud.lite.firemode", {type="toggle",label="Fire mode icon (independent)",default=true})
option("hud.lite.firemode_x", {type="slider",label="Fire mode icon offset X",default=-35,min=-900,max=900,step=1})
option("hud.lite.firemode_y", {type="slider",label="Fire mode icon offset Y",default=0,min=-600,max=600,step=1})
option("hud.lite.firemode_size", {type="slider",label="Fire mode icon size",default=32,min=12,max=96,step=1})
option("hud.lite.ammo_icon_x", {type="slider",label="Ammo type icon offset X",default=0,min=-900,max=900,step=1})
option("hud.lite.ammo_icon_y", {type="slider",label="Ammo type icon offset Y",default=0,min=-600,max=600,step=1})
option("hud.lite.ammo_icon_size", {type="slider",label="Ammo type icon size",default=32,min=12,max=96,step=1})
option("hud.lite.zeroing_x", {type="slider",label="Zeroing icon offset X",default=35,min=-900,max=900,step=1})
option("hud.lite.zeroing_y", {type="slider",label="Zeroing icon offset Y",default=0,min=-600,max=600,step=1})
option("hud.lite.zeroing_size", {type="slider",label="Zeroing icon size",default=32,min=12,max=96,step=1})
option("hud.lite.rof_icon", {type="toggle",label="Rate of fire setting icon",default=true})
option("hud.lite.rof_x", {type="slider",label="Rate of fire icon offset X",default=70,min=-900,max=900,step=1})
option("hud.lite.rof_y", {type="slider",label="Rate of fire icon offset Y",default=0,min=-600,max=600,step=1})
option("hud.lite.rof_size", {type="slider",label="Rate of fire icon size",default=32,min=12,max=96,step=1})
option("hud.lite.reserve_x", {type="slider",label="Reserve magazine count offset X",default=132,min=-900,max=900,step=1})
option("hud.lite.reserve_y", {type="slider",label="Reserve magazine count offset Y",default=0,min=-600,max=600,step=1})
option("hud.lite.reserve_size", {type="slider",label="Reserve magazine count text height",default=22,min=8,max=80,step=1})
option("hud.lite.magazine_icon", {type="toggle",label="Magazine icon beside reserve count",default=true})
option("hud.lite.magazine_icon_size", {type="slider",label="Reserve magazine icon size",default=28,min=12,max=96,step=1})
option("hud.lite.magazine_icon_gap", {type="slider",label="Magazine icon to count gap",default=5,min=0,max=40,step=1})
option("hud.lite.vitals_text", {type="toggle",label="Health and stamina row (armed and unarmed)",default=true})
option("hud.lite.reload_smoothing", {type="slider",label="Reload interpolation response (0 = raw samples)",default=24,min=0,max=60,step=1})

-- Release visual defaults are applied to option specs at registration only;
-- saved player values always win over them.

local function refresh_options()
  for id,spec in pairs(OPTION_IDS) do
    local ok,value = pcall(chef.get,id)
    if not ok or value==nil then value=spec.default end
    if spec.type=="slider" and type(value)=="number" then
      if value~=value or value==math.huge or value==-math.huge then value=spec.default end
      value=math.max(spec.min or value,math.min(spec.max or value,value))
    end
    OPTION_CACHE[id]=value
  end
end
refresh_options()
if type(chef.on_change)=="function" then
  for id in pairs(OPTION_IDS) do
    local key=id
    pcall(chef.on_change,key,function() S.options_dirty=true end)
  end
end
