function Model.draw_reserve(x,y,text,height,scale,tint,alpha)
  local color=colour4(tint or COLOUR_GOOD,alpha or 255)
  local text_height=7*dot_size(height)
  if not on("hud.lite.magazine_icon") then
    return draw_text(x,y-text_height/2,text,height,color,true)
  end
  local size=num("hud.lite.magazine_icon_size",28)*scale
  local metric,icon_width,icon_height=Fix.row_icon_metrics('magazine',size)
  local gap=num("hud.lite.magazine_icon_gap",5)*scale
  local width=text_width(text,dot_size(height))
  local left=x-(icon_width+gap+width)/2
  local rgb=tint or COLOUR_GOOD
  local ok,result=pcall(chef.bitmap_uv,IconAssets.magazine,metric.u0,metric.v0,metric.u1,metric.v1,
    left,y-icon_height/2,icon_width,icon_height,
    chef.color(rgb[1],rgb[2],rgb[3],color[4]),LAYER_TEXT)
  if not ok or result==false then
    -- Keep the count readable without drawing a placeholder/white square.
    return draw_text(x,y-text_height/2,text,height,color,true)
  end
  draw_text(left+icon_width+gap,y-text_height/2,text,height,color,false)
end
function Model.energy_commands(prepared)
  local hand=Model.resolved and Model.resolved.hand_weapon
  local book=type(hand)=="table" and generated.identity.equipment[hand.type]
  if not book then Model.energy=nil;return end
  if Model.heat_entry==nil then
    Model.heat_entry=false
    Model.charge_entry=false
    for _,entry in ipairs(model.entries) do
      if entry.row.value=="heat_shown" then Model.heat_entry=entry
      elseif entry.row.value=='trigger_held' then Model.charge_entry=entry end
    end
  end
  local heat=Model.heat_entry and prepared.candidates[Model.heat_entry.row]
  -- Reuse the original HudModel thermal_value/charge_value. Snapshot's shared
  -- slot can pick an ammo entry first, so consume the already-computed heat
  -- candidate directly: no extra engine reads or second prediction algorithm.
  local valid_heat=heat and Fix.finite(heat.fraction) and Fix.finite(heat.max) and heat.max>0
  if valid_heat then
    local fraction=1-heat.fraction
    local energy=Model.energy or {};Model.energy=energy
    energy.heat,energy.cooling,energy.raw,energy.max=fraction,1-fraction,heat.raw,heat.max
    energy.pinned,energy.locked=heat.pinned,heat.locked
  else Model.energy=nil end
  local function replace(key,column,value,maximum,locked)
    local command
    for _,spec in ipairs(Model.commands) do if spec.key==key then command=spec;break end end
    if not command then
      Model.count=Model.count+1
      command=Model.command_pool[Model.count] or {}
      Model.command_pool[Model.count]=command
      Model.commands[#Model.commands+1]=command
    end
    Native.clear(command)
    command.key,command.kind,command.side,command.place=key,"arc","right","arc-primary"
    command.column,command.fraction,command.maximum=column,value,maximum
    command.alpha=0.9;command.state={tone="normal",level=locked and "locked" or "active"}
  end
  if valid_heat then replace(6,"energy_cooling",Model.energy.cooling,heat.max,heat.locked) end
  local raw=(Model.window.reads or {})["hand-weapon"] or {}
  if book.charges_on_heat and raw["0x88b7cf6d"]==true then
    local shown,maximum
    if Model.charge_entry then
        local charge=prepared.candidates[Model.charge_entry.row]
        if charge and Fix.finite(charge.fraction) and Fix.finite(charge.max) and charge.max>0 then
          shown,maximum=charge.fraction,charge.max
        end
    end
    if shown~=nil then replace(7,"energy_charge",shown,maximum,false) end
  end
end

local ROW_ROLES={
  {role='zeroing',key=10,toggle='zeroing'},
  {role='ammo_icon',key=9,toggle='function_icon'},
}
local CONSUMABLE_ROLES={{role='stims',icon='cura',label='STIM '},
  {role='grenades',icon='grenade',label='GREN '}}
local ROW_ORIGIN_X=PUBLISHED_VISUAL_DEFAULTS['hud.lite.info_x'] or 0
function Model.layout_row(cx,cy,scale)
  local row=Model.row_layout
  if not row then row={pool={},by_role={},count=0};Model.row_layout=row end
  local items=Model.items
  local items_fresh=items and items.avatar==S.avatar and S.clock-items.at<=0.3
  local same_specs=true
  for i=1,row.count do
    local item=row.pool[i]
    if item.spec and (item.spec.kind~='icon' and item.role~='reserve' or
      item.role~='reserve' and item.spec.name~=item.name) then same_specs=false;break end
  end
  if row.window==Model.window and row.commands==Model.commands and row.options==S.option_revision
    and row.cx==cx and row.cy==cy and row.scale==scale and row.items==items
    and row.items_at==(items and items.at) and row.items_fresh==items_fresh
    and row.reserve_text==Model.reserve_text and same_specs then return row end
  row.window,row.commands,row.options=Model.window,Model.commands,S.option_revision
  row.cx,row.cy,row.scale=cx,cy,scale
  row.items,row.items_at,row.items_fresh=items,items and items.at,items_fresh
  row.reserve_text=Model.reserve_text
  Model.row_builds=(Model.row_builds or 0)+1
  Native.clear(row.by_role);row.count=0
  local x,y=cx+ROW_ORIGIN_X*scale,cy+num('hud.lite.fire_y',-74)*scale
  if num('hud.lite.icon_position',1)==2 then x,y=529*scale,90*scale end
  x=x+num('hud.lite.row_x',0)*scale
  row.left,row.y=x,y
  local cursor=0
  local unlocked=on('hud.lite.row_unlock')
  row.unlocked=unlocked
  local gap=num('hud.lite.row_gap',8)*scale
  local function add(role,name,text,spec)
    row.count=row.count+1
    local item=row.pool[row.count]
    if not item then item={};row.pool[row.count]=item end
    local size,height,inner_gap
    if role=='reserve' then
      size=on('hud.lite.magazine_icon') and num('hud.lite.magazine_icon_size',28)*scale or 0
      height=num('hud.lite.reserve_size',22)*scale
      inner_gap=size>0 and num('hud.lite.magazine_icon_gap',5)*scale or 0
    elseif role=='stims' or role=='grenades' then
      size=num('hud.lite.items_size',28)*scale
      height=num('hud.lite.items_text_size',22)*scale;inner_gap=5*scale
    else size=num('hud.lite.'..role..'_size',32)*scale;height=0;inner_gap=0 end
    local metric,icon_width,icon_height=Fix.row_icon_metrics(name,size)
    local width=icon_width
    if text then width=width+inner_gap+text_width(text,dot_size(height)) end
    item.role,item.name,item.text,item.spec=role,name,text,spec
    item.size,item.height,item.gap,item.width=size,height,inner_gap,width
    item.icon_width,item.icon_height=icon_width,icon_height
    item.text_height=height>0 and 7*dot_size(height) or 0
    if unlocked then
      -- Each item is anchored directly to the shared origin. Missing icons
      -- cannot move any other item, and old saved per-item positions remain.
      item.left=x+num('hud.lite.'..role..'_x',0)*scale
      item.y=y+num('hud.lite.'..role..'_y',0)*scale
    else item.left=x+cursor;item.y=y end
    row.by_role[role]=item
    cursor=cursor+width+gap
  end
  local cells=Model.window and Model.window.cells
  local rpm=cells and cells.rof_icon
  local found=Model.row_icons or {};Model.row_icons=found;Native.clear(found)
  local spare
  for _,command in ipairs(Model.commands) do
    if command.kind=='icon' and command.side=='right' then found[command.key]=command
    elseif command.kind=='number' and command.key==12 and command.column=='pack_spare' then spare=command end
  end
  -- Fixed priority while locked: stims, grenades, zeroing, ammo/function,
  -- rate of fire, reserve magazines, then remaining weapon indicators.
  if items_fresh then
    for _,definition in ipairs(CONSUMABLE_ROLES) do
      local value=items[definition.role]
      if on('hud.lite.'..definition.role) and Fix.finite(value) then
        add(definition.role,definition.icon,tostring(value))
      end
    end
  end
  for _,definition in ipairs(ROW_ROLES) do
    local command=found[definition.key]
    if command and on('hud.lite.'..definition.toggle)
      and not (definition.key==9 and command.name==rpm and type(rpm)=='string')
      and Fix.icon_available(command.name) then add(definition.role,command.name,nil,command) end
  end
  if type(rpm)=='string' and on('hud.lite.rof_icon') and Fix.icon_available(rpm) then add('rof',rpm) end
  local hand=Model.resolved and Model.resolved.hand_weapon
  local book=type(hand)=='table' and generated.identity.equipment[hand.type]
  if not (book and book.no_reserves) and on('hud.lite.reserves') then
    -- A pack-spare command is an alternate source, not a second reserve item.
    local text=Model.reserve_text or (spare and tostring(spare.text or ''):gsub('^/',''))
    if text and text~='' then add('reserve','magazine',text,spare) end
  end
  local mode=found[8]
  if mode and on('hud.lite.firemode') and Fix.icon_available(mode.name) then
    add('firemode',mode.name,nil,mode)
  end
  row.width=math.max(0,cursor-gap)
  return row
end
function Model.draw_consumables(cx,cy,scale)
  -- Both row modes share one anchor; manual offsets apply only when unlocked.
  local row=Model.row_layout
  if not row then return end
  local alpha=math.floor(255*opacity()+0.5)
  for _,definition in ipairs(CONSUMABLE_ROLES) do
    local item=row.by_role[definition.role]
    if item then
      local metric=IconAssets.row_metrics[definition.icon]
      local ok,result=pcall(chef.bitmap_uv,IconAssets[definition.icon],metric.u0,metric.v0,metric.u1,metric.v1,
        item.left,item.y-item.icon_height/2,item.icon_width,item.icon_height,chef.color(255,255,255,alpha),LAYER_TEXT)
      local text=item.text
      if not ok or result==false then text=definition.label..text end
      draw_text(item.left+item.icon_width+item.gap,item.y-item.text_height/2,text,item.height,colour4(COLOUR_GOOD,255),false)
    end
  end
end
function Model.sample_visual(window,resolved)
  -- All heat interpolation now belongs to original HudModel. Do not keep a
  -- competing Lite predictor that can disagree with its charge/discharge phase.
  S.heat_warn=window.cells.heat_warn
end
function Model.tint(spec)
  local style=generated.layout.style or {}
  local state=spec.state or {}
  local tone=(generated.layout.palette or {})[state.tone or "normal"] or {}
  local alpha=spec.alpha or style.alpha or 1
  if state.level=="locked" then alpha=alpha*(style.locked_ratio or 0.45)
  elseif state.level=="idle" and num("hud.lite.idle",1)==2 then alpha=alpha*0.3 end
  return tone.body or COLOUR_GOOD,math.max(0,math.min(1,alpha*(tone.lift or 1)))
end
function Model.draw(cx,cy,scale,radius,inner,thick,inner_thick,span)
  local commands=Model.commands
  local has_number=false
  local right=(90-span*0.5)%360
  local left=(270-span*0.5)%360
  local displayed_heat=Model.energy and Model.energy.heat*Model.energy.max or nil
  local hand=Model.resolved and Model.resolved.hand_weapon
  local book=type(hand)=='table' and generated.identity.equipment[hand.type]
  local show_reserves=not (book and book.cooldown_only)
  local primary,inner_command
  for _,spec in ipairs(commands) do
    if spec.key==6 then primary=spec elseif spec.key==7 then inner_command=spec end
  end
  local target=primary and (primary.unit and 1 or primary.fraction) or nil
  local rate=num("hud.lite.smoothing",12)
  local k=rate<=0 and 1 or 1-math.exp(-rate*(S.dt or 1/60))
  if not Fix.finite(target) then S.shown_a=nil
  elseif S.shown_a==nil then S.shown_a=target
  else S.shown_a=S.shown_a+(target-S.shown_a)*k end
  local function ring(spec,r,t,head,layer,ring_x,ring_y,ring_span,alpha_scale,show_track)
    ring_x,ring_y,ring_span=ring_x or cx,ring_y or cy,ring_span or span
    local fraction=spec.unit and 1 or spec.fraction
    if not Fix.finite(fraction) then return end
    local ri,ro=math.max(2,r-t*0.5),r+t*0.5
    local rgb,alpha=Model.tint(spec)
    alpha=alpha*(alpha_scale or 1)
    if spec.key==6 then
      if displayed_heat~=nil then
        rgb=S.heat_warn and displayed_heat>=S.heat_warn and COLOUR_BAD or COLOUR_GOOD
      else rgb=health_colour(fraction) end
    elseif spec.key==7 then
      rgb=spec.column=="action_elapsed" and Model.reload_white or COLOUR_WARN
    end
    if on("hud.lite.track") and show_track~=false then
      arc(ring_x,ring_y,ri,ro,head,head+ring_span,colour4(COLOUR_TRACK,150*alpha),layer==908 and 904 or 905)
    end
    fraction=math.max(0,math.min(1,fraction))
    if fraction>0 then arc(ring_x,ring_y,ri,ro,head,head+ring_span*fraction,colour4(rgb,255*alpha),layer) end
  end
  local first_number,second_number
  for _,spec in ipairs(commands) do
    if spec.kind=="number" then
      if spec.key==11 then first_number=spec elseif spec.key==12 then second_number=spec end
    end
  end
  for _,spec in ipairs(commands) do
    if spec.kind=="arc" then
      if spec.key==6 and on("hud.lite.ammo") then
        local shown=Model.primary_visual or {};Model.primary_visual=shown
        Native.clear(shown)
        for key,value in pairs(spec) do shown[key]=value end
        shown.fraction=S.shown_a
        ring(shown,radius,thick,right,906)
      elseif spec.key==7 and on("hud.lite.ammo") then
        local cells=Model.window and Model.window.cells or {}
        if spec.column=="action_elapsed" and Model.animation then
          local a=Model.animation
          local now=S.clock
          local target=math.max(0,math.min(1,a.elapsed/a.length))
          local ahead=math.min(0.05,math.max(0,now-a.at))
          target=math.max(0,math.min(1,(a.elapsed+(a.speed or 0)*ahead)/a.length))
          local previous=Model.reload_visual
          local response=num("hud.lite.reload_smoothing",24)
          local reset=not previous or previous.key~=a.key or not a.continuous
          local value=target
          if response>0 and not reset and (a.speed or 0)>0 then
            local gain=1-math.exp(-response*(S.dt or 1/60))
            value=previous.fraction+(target-previous.fraction)*gain
          elseif response==0 then value=math.max(0,math.min(1,a.elapsed/a.length)) end
          local visual=Model.reload_visual or {};Model.reload_visual=visual
          visual.key,visual.fraction=a.key,value
          local shown=Model.reload_command or {};Model.reload_command=shown;Native.clear(shown)
          for key,value0 in pairs(spec) do shown[key]=value0 end
          shown.fraction=value
          ring(shown,inner,inner_thick,right,908)
        elseif spec.column=="trigger_held" and Fix.finite(cells.charge_safe) and cells.charge_safe>0
          and cells.charge_fire_mode==cells.charge_safe_mode and Fix.finite(spec.maximum) then
          local safe=Model.inner_visual or {};Model.inner_visual=safe;Native.clear(safe)
          for key,value in pairs(spec) do safe[key]=value end
          safe.fraction=math.max(0,math.min(1,(spec.fraction or 0)*spec.maximum/cells.charge_safe))
          ring(safe,inner,inner_thick,right,908)
        else ring(spec,inner,inner_thick,right,908) end
      elseif spec.key==1 and on("hud.lite.backpack") then
        -- Same direct radius/width/span units and global track/opacity as the
        -- other Ring layout controls; no automatic-zero or multiplier mode.
        local r=num('hud.lite.backpack_radius',168.5)*scale
        local t=num('hud.lite.backpack_thickness',3.5)*scale
        local degrees=num('hud.lite.backpack_span',73)
        local head=(90-degrees/2)%360
        ring(spec,r,t,head,909,cx-num('hud.lite.x',0)*scale+num('hud.lite.backpack_x',0)*scale,
          num('hud.lite.backpack_y',538)*scale,degrees)
      end
    elseif spec.kind=="icon" and spec.side~='right' and
      (spec.key==2 and on('hud.lite.self_booster') or spec.key~=2 and on('hud.lite.squad')) then
      local rgb,alpha=Model.tint(spec)
      local size=math.max(12,num("hud.lite.icon_size",32)*scale)
      local x,y
        -- Stable original seat: self is always bottom, then squad seats 1..3.
        -- Do not compact a missing booster and shift everyone else's icon.
        local position=spec.key-2
        x=42*scale;y=(176+68*position)*scale
        size=64*scale
      Fix.draw_icon(spec.name,x,y,size,math.floor(255*alpha*opacity()+0.5),rgb)
    end
  end
  local row=Model.layout_row(cx,cy,scale)
  for i=1,row.count do
    local item=row.pool[i]
    if item.role=='reserve' then
      Model.draw_reserve(item.left+item.width/2,item.y,item.text,item.height,scale,COLOUR_GOOD,255)
    elseif item.role~='stims' and item.role~='grenades' then
      local rgb,alpha=COLOUR_GOOD,1
      if item.spec then rgb,alpha=Model.tint(item.spec) end
      Fix.draw_row_icon(item.name,item.left,item.y,item.size,math.floor(255*alpha*opacity()+0.5),rgb)
    end
  end
  if not inner_command then Model.reload_visual=nil end
  if on("hud.lite.number") then
    local height=math.max(8,num("hud.lite.number_size",38)*scale)
    local nx=cx+num("hud.lite.number_x",0)*scale
    local ny=cy+num("hud.lite.number_y",0)*scale
    local mode=num("hud.lite.number_mode",1)
    if first_number then
      local text=first_number.text or ""
      if mode==1 then
        local cells=Model.window and Model.window.cells or {}
        -- A backpack guest uses its own capacity, never the weapon capacity.
        local cap=text~="" and (first_number.column=="pack_ammo" and cells.pack_ammo_max or cells.ammo_max)
        if Fix.finite(cap) and cap>0 then text=text.."/"..tostring(math.floor(cap+0.5)) end
      elseif mode==2 then
        -- Reserves now live in the settings row, never under/in the center.
      end
      local rgb,alpha=Model.tint(first_number)
      draw_text(nx,ny-height/2,text,height,colour4(rgb,255*alpha),num("hud.lite.number_align",1)==2)
      has_number=true
    elseif mode==1 then
      -- Energy weapons may have an arc without an ammo number. Keep the
      -- heat percent center, while using the shared thermal model fraction.
      local cells=Model.window and Model.window.cells or {}
      if Fix.finite(cells.heat_max) and cells.heat_max>0 then
        for _,spec in ipairs(commands) do
          if spec.key==6 and Fix.finite(spec.fraction) then
            local rgb,alpha=Model.tint(spec)
            local text=tostring(math.floor(100*spec.fraction+0.5)).."%"
            draw_text(nx,ny-height/2,text,height,colour4(rgb,255*alpha),num("hud.lite.number_align",1)==2)
            has_number=true;break
          end
        end
      end
    end
  end
  return has_number
end
