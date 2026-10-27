-- Per-frame composition: reads the model and issues draw commands.
local function render()
  if S.stopped or not on("hud.lite.arc") then return end
  if not Model.valid_world() then return end
  if not in_mission() then return end

  local w, h = 1920, 1080
  if type(chef.screen) == "function" then
    local ok, a, b = pcall(chef.screen)
    if ok and type(a) == "number" and type(b) == "number" and a > 0 and b > 0 then w, h = a, b end
  end

  -- Flat cluster: two nested arcs on the left (health outside, stamina
  -- inside); right rings are ammo/cooling, reload/charge and backpack supply.
  local scale = math.min(w / 1920, h / 1080) * num("hud.lite.scale", 1)
  local radius = num("hud.lite.radius", 78) * scale
  local inner = math.min(radius - 2, num("hud.lite.inner_radius", 60) * scale)
  local thick = math.max(1, num("hud.lite.thickness", 8) * scale)
  local inner_thick = math.max(1, num("hud.lite.inner_thickness", 5) * scale)
  local span = num("hud.lite.span", 100)
  local cx = w * 0.5 + num("hud.lite.x", 0) * scale
  local cy = num("hud.lite.y", 520) * scale

  local left = (270 - span * 0.5) % 360
  local right = (90 - span * 0.5) % 360
  local o_in, o_out = math.max(2, radius - thick * 0.5), radius + thick * 0.5
  local i_in, i_out = math.max(2, inner - inner_thick * 0.5), inner + inner_thick * 0.5


  local ratio = S.ratio
  local live = ratio ~= nil and S.clock - S.at <= 1.0
  if live then
    ratio = math.max(0, math.min(1, ratio))
  end

  -- Smooth the ring lengths: the values arrive at 4 Hz, the rings move every
  -- frame. k = 1 - exp(-rate*dt) is frame-rate independent; rate 0 snaps.
  local rate = num("hud.lite.smoothing", 12)
  local dt = S.dt or 0.016667
  local k
  if rate <= 0 then k = 1 else k = 1 - math.exp(-rate * dt) end
  local function ease(cur, target)
    if target == nil then return nil end
    if cur == nil then return target end
    return cur + (target - cur) * k
  end

  local stamina_target = nil
  if S.stamina ~= nil and S.clock - (S.stamina_at or -1e9) <= 1.0 then
    stamina_target = math.max(0, math.min(1, S.stamina))
  end
  S.shown_h = ease(S.shown_h, live and ratio or nil)
  S.shown_s = ease(S.shown_s, stamina_target)

  local shown_h, shown_s = S.shown_h, S.shown_s

  if on("hud.lite.track") then
    if on("hud.lite.health") and live then arc(cx, cy, o_in, o_out, left, left + span, colour4(COLOUR_TRACK), LAYER_TRACK) end
    if on("hud.lite.stamina") and stamina_target ~= nil then
      arc(cx, cy, i_in, i_out, left, left + span, colour4(COLOUR_TRACK), LAYER_INNER_TRACK)
    end

  end

  -- health: outer arc on the left (smoothed length, live colour)
  if on("hud.lite.health") and shown_h ~= nil and shown_h > 0 then
    arc(cx, cy, o_in, o_out, left, left + span * shown_h,
      colour4(health_colour(live and ratio or nil), 255), LAYER_FILL)
  end

  -- stamina: inner arc on the left
  if shown_s ~= nil and shown_s > 0 and on("hud.lite.stamina") then
    arc(cx, cy, i_in, i_out, left, left + span * shown_s, colour4(COLOUR_GOOD, 216), LAYER_INNER_FILL)
  end

  local has_number = Model.draw(cx,cy,scale,radius,inner,thick,inner_thick,span)
  Model.draw_consumables(cx,cy,scale)

  if on("hud.lite.vitals_text") then
    local text = describe_info()
    if text ~= "" then
      local height = math.max(7, num("hud.lite.info_size", 14) * scale)
      local ix = cx + num("hud.lite.info_x", 0) * scale
      local iy = cy + num("hud.lite.info_y", -46) * scale
      draw_text(ix, iy, text, height, colour4(COLOUR_STATUS, 210), true)
    end
  end

end
