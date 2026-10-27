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

local text_metrics={count=0,rows={},until_at=0}
local function text_width(text, dot_px)
  -- Chef's pixel/game font can change independently of this mod's settings.
  -- Bound the lifetime as well as the size so row widths recover after a swap.
  if S.clock>=text_metrics.until_at then
    Native.clear(text_metrics.rows);text_metrics.count=0;text_metrics.until_at=S.clock+1
  end
  local rows=text_metrics.rows
  local by_size=rows[dot_px]
  if by_size and by_size[text]~=nil then return by_size[text] end
  local width
  if type(chef.text_width) == "function" then
    local ok, w = pcall(chef.text_width, text, dot_px)
    if ok and type(w) == "number" and w > 0 then width=w end
  end
  width=width or math.max(0,#text * 6 * dot_px - dot_px)
  if text_metrics.count>=256 then Native.clear(rows);text_metrics.count=0;by_size=nil end
  if not by_size then by_size={};rows[dot_px]=by_size end
  by_size[text]=width;text_metrics.count=text_metrics.count+1
  return width
end

local function draw_text(cx, baseline, text, height, colour, centred)
  local dot = dot_size(height)
  local x = centred and cx - text_width(text, dot) * 0.5 or cx
  return loader_text(x, baseline, text, dot, colour)
end

-- Exact atlas material and 32x2 UV cell map, not Unicode/text substitutes.
function Fix.icon_available(name)
  return type(name)=='string' and (IconAssets.boosters[name]~=nil or
    type(generated.identity.icon_cells[name])=='number')
end
function Fix.row_icon_metrics(name,size)
  local metric=IconAssets.row_metrics[name]
  if metric then return metric,size*metric.width,size*metric.height end
  return nil,0,0
end
function Fix.draw_row_icon(name,left,cy,size,alpha,tint)
  local metric,w,h=Fix.row_icon_metrics(name,size)
  if not metric or type(chef.bitmap_uv)~='function' then return false end
  tint=tint or COLOUR_GOOD
  local ok,result=pcall(chef.bitmap_uv,metric.texture,metric.u0,metric.v0,metric.u1,metric.v1,
    left,cy-h/2,w,h,chef.color(tint[1],tint[2],tint[3],alpha),LAYER_TEXT)
  return ok and result~=false
end
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
