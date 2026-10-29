-- Preserve existing hud.lite.* settings; add any missing options.
option("hud.lite.health", {type="toggle",label="Health ring (outer left)",default=true})
option("hud.lite.backpack", {type="toggle",label="Backpack ring (third right)",default=true})
option("hud.lite.backpack_x", {type="slider",label="Backpack offset X (px @1080p)",default=0,min=-900,max=900,step=1})
option("hud.lite.backpack_y", {type="slider",label="Backpack offset Y from bottom (px @1080p)",default=538,min=0,max=1080,step=1})
option("hud.lite.backpack_radius", {type="slider",label="Backpack ring radius (px @1080p)",default=168.5,min=12,max=280,step=0.5})
option("hud.lite.backpack_thickness", {type="slider",label="Backpack ring thickness (px)",default=3.5,min=1,max=30,step=0.5})
option("hud.lite.backpack_span", {type="slider",label="Backpack arc span (degrees)",default=73,min=30,max=180,step=1})
option("hud.lite.stims", {type="toggle",label="Stim icon and quantity",default=true})
option("hud.lite.grenades", {type="toggle",label="Grenade icon and quantity",default=true})
option("hud.lite.stims_x", {type="slider",label="Unlocked stim position X",default=0,min=-900,max=900,step=1})
option("hud.lite.stims_y", {type="slider",label="Unlocked stim position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.grenades_x", {type="slider",label="Unlocked grenade position X",default=70,min=-900,max=900,step=1})
option("hud.lite.grenades_y", {type="slider",label="Unlocked grenade position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.row_gap", {type="slider",label="Information row visible edge gap (px)",default=8,min=0,max=80,step=1})
option("hud.lite.row_x", {type="slider",label="Information row offset X from approved origin",default=0,min=-900,max=900,step=1})
option("hud.lite.row_unlock", {type="toggle",label="Unlock information row (individual positions)",default=false})
option("hud.lite.items_size", {type="slider",label="Consumable icon size",default=28,min=12,max=96,step=1})
option("hud.lite.items_text_size", {type="slider",label="Consumable quantity text height",default=22,min=8,max=80,step=1})
option("hud.lite.squad", {type="toggle",label="Squad boosters and death icons",default=true})
option("hud.lite.self_booster", {type="toggle",label="Own booster icon",default=true})
option("hud.lite.reserves", {type="toggle",label="Reserve / backpack numbers",default=true})
option("hud.lite.icon_position", {type="choice",label="Weapon icon position",choices={"crosshair","game HUD"},default=1})
option("hud.lite.idle", {type="choice",label="Show when idle",choices={"full brightness","faint (30%)"},default=1})
option("hud.lite.number_mode", {type="choice",label="Centre ammunition format",choices={"rounds / capacity","rounds only"},default=1})
option("hud.lite.reload_animation", {type="toggle",label="Reload progress",default=true})
option("hud.lite.firemode", {type="toggle",label="Fire mode icon (independent)",default=true})
option("hud.lite.firemode_x", {type="slider",label="Unlocked fire mode position X",default=420,min=-900,max=900,step=1})
option("hud.lite.firemode_y", {type="slider",label="Unlocked fire mode position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.firemode_size", {type="slider",label="Fire mode icon size",default=32,min=12,max=96,step=1})
option("hud.lite.ammo_icon_x", {type="slider",label="Unlocked ammo type position X",default=190,min=-900,max=900,step=1})
option("hud.lite.ammo_icon_y", {type="slider",label="Unlocked ammo type position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.ammo_icon_size", {type="slider",label="Ammo type icon size",default=32,min=12,max=96,step=1})
option("hud.lite.zeroing_x", {type="slider",label="Unlocked zeroing position X",default=140,min=-900,max=900,step=1})
option("hud.lite.zeroing_y", {type="slider",label="Unlocked zeroing position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.zeroing_size", {type="slider",label="Zeroing icon size",default=32,min=12,max=96,step=1})
option("hud.lite.rof_icon", {type="toggle",label="Rate of fire setting icon",default=true})
option("hud.lite.rof_x", {type="slider",label="Unlocked rate of fire position X",default=300,min=-900,max=900,step=1})
option("hud.lite.rof_y", {type="slider",label="Unlocked rate of fire position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.rof_size", {type="slider",label="Rate of fire icon size",default=32,min=12,max=96,step=1})
option("hud.lite.reserve_x", {type="slider",label="Unlocked reserve count position X",default=350,min=-900,max=900,step=1})
option("hud.lite.reserve_y", {type="slider",label="Unlocked reserve count position Y",default=0,min=-600,max=600,step=1})
option("hud.lite.reserve_size", {type="slider",label="Reserve magazine count text height",default=22,min=8,max=80,step=1})
option("hud.lite.magazine_icon", {type="toggle",label="Magazine icon beside reserve count",default=true})
option("hud.lite.magazine_icon_size", {type="slider",label="Reserve magazine icon size",default=28,min=12,max=96,step=1})
option("hud.lite.magazine_icon_gap", {type="slider",label="Magazine icon to count gap",default=5,min=0,max=40,step=1})
option("hud.lite.vitals_text", {type="toggle",label="Health and stamina row (armed and unarmed)",default=true})
option("hud.lite.reload_smoothing", {type="slider",label="Reload interpolation response (0 = raw samples)",default=24,min=0,max=60,step=1})

-- Release visual defaults are applied to option specs at registration only;
-- saved player values always win over them.

-- Chef 1.4 exposes per-mod section headings (spec.heading, foldable). Older
-- loaders only draw flat rows, so they keep a searchable bracket prefix instead.
local MENU_SECTIONS={
  {name='01 Display',heading='DISPLAY',ids={'arc','alpha','scale','idle'}},
  {name='02 Ring layout',heading='RING LAYOUT',ids={'x','y','radius','inner_radius','thickness','inner_thickness','span','track','smoothing',
    'backpack','backpack_x','backpack_y','backpack_radius','backpack_thickness','backpack_span'}},
  {name='03 Vitals',heading='VITALS',ids={'health','stamina','vitals_text','info_x','info_y','info_size'}},
  {name='04 Ammunition',heading='AMMUNITION',ids={'ammo','number','number_mode','number_align','number_x','number_y','number_size'}},
  {name='05 Weapon row',heading='WEAPON ROW',ids={'row_unlock','icon_position','row_x','fire_y','row_gap'}},
  {name='06 Fire and ammo icons',heading='FIRE AND AMMO ICONS',ids={'firemode','firemode_x','firemode_y','firemode_size',
    'function_icon','ammo_icon_x','ammo_icon_y','ammo_icon_size'}},
  {name='07 Zeroing and RPM',heading='ZEROING AND RPM',ids={'zeroing','zeroing_x','zeroing_y','zeroing_size','rof_icon','rof_x','rof_y','rof_size'}},
  {name='08 Reserves',heading='RESERVES',ids={'reserves','reserve_x','reserve_y','reserve_size','magazine_icon','magazine_icon_size','magazine_icon_gap'}},
  {name='09 Stims and grenades',heading='STIMS AND GRENADES',ids={'stims','stims_x','stims_y','grenades','grenades_x','grenades_y','items_size','items_text_size'}},
  {name='10 Squad',heading='SQUAD',ids={'self_booster','squad'}},
  {name='11 Animation',heading='ANIMATION',ids={'reload_animation','reload_smoothing'}},
}
do
  local supported=false
  if type(chef.has)=="function" then
    local ok,value=pcall(chef.has,"option_headings")
    supported=ok and value==true
  end
  local registered={}
  for _,section in ipairs(MENU_SECTIONS) do
    local first=true
    for _,suffix in ipairs(section.ids) do
      local id='hud.lite.'..suffix
      local spec=assert(OPTION_IDS[id],'Missing menu option: '..id)
      assert(not registered[id],'Duplicate menu option: '..id)
      registered[id]=true
      if supported then
        if first then spec.heading=section.heading end
      else
        spec.label='['..section.name..'] '..spec.label
      end
      first=false
      pcall(chef.option,id,spec)
    end
  end
  for id in pairs(OPTION_IDS)do assert(registered[id],'Unclassified menu option: '..id)end
end

local function refresh_options()
  local changed=false
  for id,spec in pairs(OPTION_IDS) do
    local ok,value = pcall(chef.get,id)
    if not ok or value==nil then value=spec.default end
    if spec.type=="slider" and type(value)=="number" then
      if value~=value or value==math.huge or value==-math.huge then value=spec.default end
      value=math.max(spec.min or value,math.min(spec.max or value,value))
    end
    if OPTION_CACHE[id]~=value then changed=true;OPTION_CACHE[id]=value end
  end
  if changed then S.option_revision=(S.option_revision or 0)+1 end
end
refresh_options()
if type(chef.on_change)=="function" then
  for id in pairs(OPTION_IDS) do
    local key=id
    pcall(chef.on_change,key,function() S.options_dirty=true end)
  end
end
