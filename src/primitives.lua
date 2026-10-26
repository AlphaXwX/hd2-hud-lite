-- Drawing primitives: arcs, text metrics, icons and colour helpers.
local function loader_text(x, y, text, dot_px, colour)
  if type(chef.text) ~= "function" then return false end
  local c = eval(function() return chef.color(colour[1], colour[2], colour[3], colour[4] or 255) end)
  local ok = pcall(chef.text, x, y, text, dot_px, c, LAYER_TEXT)
  if ok and loader_text_state ~= "ok" then
    loader_text_state = "ok"
    logf("loader font accepted " .. text)
  end
  return ok
end

-- chef.text is a 5x7 dot font where the 4th argument is the size of ONE dot:
-- a glyph is 7 dots tall and advances 6 dots. Centring therefore needs the dot
-- size derived from the wanted text height, not the height itself.
local function dot_size(height)
  local px = math.floor((height or 40) / 7 + 0.5)
  if px < 1 then px = 1 end
  return px
end

local function text_width(text, dot_px)
  if type(chef.text_width) == "function" then
    local ok, w = pcall(chef.text_width, text, dot_px)
    if ok and type(w) == "number" and w > 0 then return w end
  end
  return #text * 6 * dot_px - dot_px
end

local function draw_text(cx, baseline, text, height, colour, centred)
  local dot = dot_size(height)
  local x = centred and cx - text_width(text, dot) * 0.5 or cx
  return loader_text(x, baseline, text, dot, colour)
end

-- Exact atlas material and 32x2 UV cell map, not Unicode/text substitutes.
function Fix.draw_icon(name, cx, cy, size, alpha, tint)
  local texture=IconAssets.boosters[name]
  if texture then
    if type(chef.bitmap_uv)~="function" then return false end
    tint=tint or COLOUR_GOOD
    local ok,result=pcall(chef.bitmap_uv,texture,0,0,1,1,cx-size/2,cy-size/2,size,size,
      chef.color(tint[1],tint[2],tint[3],alpha),LAYER_TEXT)
    return ok and result~=false
  end
  local cell = generated.identity.icon_cells[name]
  if type(cell) ~= "number" or type(chef.bitmap_uv) ~= "function" then return false end
  local u,v = (cell % 32)/32, math.floor(cell/32)/2
  tint = tint or COLOUR_GOOD
  local ok,result = pcall(chef.bitmap_uv, "254deec0e6c38888", u,v,u+1/32,v+1/2,
    cx-size/2,cy-size/2,size,size,chef.color(tint[1],tint[2],tint[3],alpha),LAYER_TEXT)
  if (not ok or result==false) and not S.icon_error then
    S.icon_error=true; logf("icon texture unavailable; icon hidden (no white-square fallback)")
  end
  return ok and result~=false
end

local function opacity()
  local v = num("hud.lite.alpha", 100)
  if type(v) ~= "number" or v ~= v then return 1 end
  return math.max(0, math.min(1, v / 100))
end

local function colour4(c, alpha)
  local a = alpha or c[4] or 255
  return { c[1], c[2], c[3], math.floor(a * opacity() + 0.5) }
end

local function arc(cx, cy, r_in, r_out, a0, a1, colour, layer)
  if type(chef.arc) == "function" then
    local c = eval(function() return chef.color(colour[1], colour[2], colour[3], colour[4]) end)
    if c ~= nil and pcall(chef.arc, cx, cy, r_in, r_out, a0, a1, c, layer) then return true end
  end
  local span = a1 - a0
  if span == 0 then return false end
  local mid = (r_in + r_out) * 0.5
  local thick = math.max(1, r_out - r_in)
  local steps = math.max(2, math.floor(math.abs(span) / 2.5))
  local step = span / steps
  local deg = math.pi / 180
  for i = 0, steps - 1 do
    local a = (a0 + step * (i + 0.5)) * deg
    local c = eval(function() return chef.color(colour[1], colour[2], colour[3], colour[4]) end)
    if c ~= nil then
      pcall(chef.rect, cx + math.sin(a) * mid - thick * 0.5, cy + math.cos(a) * mid - thick * 0.5,
        thick, thick * 1.35, c, layer)
    end
  end
  return true
end

local function text_of()
  if S.ratio == nil then return "--" end
  if S.hp ~= nil then return string.format("%d", math.floor(S.hp + 0.5)) end
  return string.format("%d", math.floor(S.ratio * 100 + 0.5))
end
