function Model.draw_reserve(x,y,text,height,scale,tint,alpha)
  local color=colour4(tint or COLOUR_GOOD,alpha or 255)
  if not on("hud.lite.magazine_icon") then
    return draw_text(x,y-height/2,text,height,color,true)
  end
  local size=num("hud.lite.magazine_icon_size",28)*scale
  local gap=num("hud.lite.magazine_icon_gap",5)*scale
  local width=text_width(text,dot_size(height))
  local left=x-(size+gap+width)/2
  local rgb=tint or COLOUR_GOOD
  local ok,result=pcall(chef.bitmap_uv,IconAssets.magazine,0,0,1,1,left,y-size/2,size,size,
    chef.color(rgb[1],rgb[2],rgb[3],color[4]),LAYER_TEXT)
  if not ok or result==false then
    -- Keep the count readable without drawing a placeholder/white square.
    return draw_text(x,y-height/2,text,height,color,true)
  end
  draw_text(left+size+gap,y-height/2,text,height,color,false)
end
function Model.energy_commands(prepared)
  local hand=Model.resolved and Model.resolved.hand_weapon
  local book=type(hand)=="table" and generated.identity.equipment[hand.type]
  if not book then Model.energy=nil;return end
  if Model.heat_entry==nil then
    Model.heat_entry=false
    for _,entry in ipairs(model.entries) do
      if entry.row.value=="heat_shown" then Model.heat_entry=entry;break end
    end
  end
  local heat=Model.heat_entry and prepared.candidates[Model.heat_entry.row]
  if not heat or not Fix.finite(heat.fraction) or not Fix.finite(heat.max) or heat.max<=0 then
    Model.energy=nil;return
  end
  -- Reuse the original HudModel thermal_value/charge_value. Snapshot's shared
  -- slot can pick an ammo entry first, so consume the already-computed heat
  -- candidate directly: no extra engine reads or second prediction algorithm.
  local fraction=1-heat.fraction
  local energy=Model.energy or {}
  energy.heat,energy.cooling,energy.raw,energy.max=fraction,1-fraction,heat.raw,heat.max
  energy.pinned,energy.locked=heat.pinned,heat.locked
  Model.energy=energy
  local function replace(key,column,value)
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
    command.column,command.fraction,command.maximum=column,value,heat.max
    command.alpha=0.9;command.state={tone="normal",level=heat.locked and "locked" or "active"}
  end
  replace(6,"energy_cooling",Model.energy.cooling)
  local raw=(Model.window.reads or {})["hand-weapon"] or {}
  if book.charges_on_heat and raw["0x88b7cf6d"]==true then replace(7,"energy_charge",fraction) end
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
  local function ring(spec,r,t,head,layer)
    local fraction=spec.unit and 1 or spec.fraction
    if not Fix.finite(fraction) then return end
    local ri,ro=math.max(2,r-t*0.5),r+t*0.5
    local rgb,alpha=Model.tint(spec)
    if spec.key==6 then
      if displayed_heat~=nil then
        rgb=S.heat_warn and displayed_heat>=S.heat_warn and COLOUR_BAD or COLOUR_GOOD
      else rgb=health_colour(fraction) end
    elseif spec.key==7 then
      rgb=spec.column=="action_elapsed" and Model.reload_white or COLOUR_WARN
    end
    if on("hud.lite.track") then
      arc(cx,cy,ri,ro,head,head+span,colour4(COLOUR_TRACK,150*alpha),layer==908 and 904 or 905)
    end
    fraction=math.max(0,math.min(1,fraction))
    if fraction>0 then arc(cx,cy,ri,ro,head,head+span*fraction,colour4(rgb,255*alpha),layer) end
  end
  local function wanted_icon(spec)
    if spec.side=="right" then
      if spec.key==8 then return on("hud.lite.firemode") end
      if spec.key==9 then return on("hud.lite.function_icon") end
      if spec.key==10 then return on("hud.lite.zeroing") end
      return false
    end
    return spec.key==2 and on("hud.lite.self_booster") or spec.key~=2 and on("hud.lite.squad")
  end
  local first_number,second_number
  for _,spec in ipairs(commands) do
    if spec.kind=="number" then
      if spec.key==11 then first_number=spec elseif spec.key==12 then second_number=spec end
    end
  end
  local rpm=Model.window and Model.window.cells and Model.window.cells.rof_icon
  local function setting_anchor(dx,dy)
    if num("hud.lite.icon_position",1)==2 then return 529*scale+dx,90*scale+dy end
    return cx+num("hud.lite.info_x",0)*scale+dx,cy+num("hud.lite.fire_y",-74)*scale+dy
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
          Model.reload_visual={key=a.key,fraction=value}
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
        ring(spec,math.max(8,inner-inner_thick-10*scale),inner_thick,left,909)
      end
    elseif spec.kind=="icon" and wanted_icon(spec)
      and not (spec.key==9 and spec.name==rpm and type(rpm)=="string") then
      local rgb,alpha=Model.tint(spec)
      local size=math.max(12,num("hud.lite.icon_size",32)*scale)
      local x,y
      if spec.side=="right" then
        local role=spec.key==8 and "firemode" or spec.key==9 and "ammo_icon" or "zeroing"
        local dx=num("hud.lite."..role.."_x",0)*scale
        local dy=num("hud.lite."..role.."_y",0)*scale
        size=num("hud.lite."..role.."_size",32)*scale
        x,y=setting_anchor(dx,dy)
      else
        -- Stable original seat: self is always bottom, then squad seats 1..3.
        -- Do not compact a missing booster and shift everyone else's icon.
        local position=spec.key-2
        x=42*scale;y=(176+68*position)*scale
        size=64*scale
      end
      Fix.draw_icon(spec.name,x,y,size,math.floor(255*alpha*opacity()+0.5),rgb)
    end
  end
  if type(rpm)=="string" and on("hud.lite.rof_icon") then
    local x,y=setting_anchor(num("hud.lite.rof_x",70)*scale,num("hud.lite.rof_y",0)*scale)
    Fix.draw_icon(rpm,x,y,num("hud.lite.rof_size",32)*scale,math.floor(240*opacity()+0.5))
  end
  -- Original reserve signal honors magazines/spare and spare-pack rules.
  -- Draw independently from central ammo numbers and show a real zero too.
  if on("hud.lite.reserves") and Model.reserve_text then
    local height=num("hud.lite.reserve_size",22)*scale
    local x,y=setting_anchor(num("hud.lite.reserve_x",112)*scale,num("hud.lite.reserve_y",0)*scale)
    Model.draw_reserve(x,y,Model.reserve_text,height,scale,COLOUR_GOOD,255)
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
    if second_number and second_number.column=="pack_spare" and on("hud.lite.reserves") then
      local rgb,alpha=Model.tint(second_number)
      local x,y=setting_anchor(num("hud.lite.reserve_x",112)*scale,num("hud.lite.reserve_y",0)*scale)
      local ph=num("hud.lite.reserve_size",22)*scale
      Model.draw_reserve(x,y,tostring(second_number.text or ""):gsub("^/",""),ph,scale,rgb,230*alpha)
    end
  end
  return has_number
end
