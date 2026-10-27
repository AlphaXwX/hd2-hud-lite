-- Chef surface: loader access, option registration, colour and numeric helpers.
-- HD2-Addon: mods/alpha_f_bloodfallen/hud_lite
-- HD2-Requires: chef-shared-loader >= 1.2.3
-- HUD Lite 1.0.1 by Alpha F. Bloodfallen
-- Imported implementation/art retains its original terms; see THIRD_PARTY_NOTICES.md.

local chef = ...
if type(chef) ~= "table" then chef = rawget(_G, "chef") end
if type(chef) ~= "table" then return { version = "1.0.1", installed = false } end

local VERSION = "1.0.1"
local PREFIX = "HUD Lite: "

-- ---------------------------------------------------------------------------
-- loader surface
-- ---------------------------------------------------------------------------

local function logf(text)
  if type(chef.log) == "function" then pcall(chef.log, "%s", PREFIX .. tostring(text)) end
end

local function api_level()
  local ok, v = pcall(function() return chef.api end)
  if ok and type(v) == "number" then return v end
  return 1
end

local API = api_level()

-- ---------------------------------------------------------------------------
-- engine globals (a Chef addon inherits them through the env metatable)
-- ---------------------------------------------------------------------------

local function eval(fn)
  local ok, a = pcall(fn)
  if ok then return a end
  return nil
end

local GL = {
  stingray = function() return stingray end,
  GameSession = function() return GameSession end,
  Network = function() return Network end,
  World = function() return World end,
  Unit = function() return Unit end,
  Gui = function() return Gui end,
  Vector2 = function() return Vector2 end,
  Vector3 = function() return Vector3 end,
  Color = function() return Color end,
  IdString64 = function() return IdString64 end,
}

local SR = eval(GL.stingray) or rawget(_G, "stingray")

local function engine(name)
  if SR ~= nil then
    local ok, v = pcall(function() return SR[name] end)
    if ok and v ~= nil then return v end
  end
  return eval(GL[name])
end

local GS = engine("GameSession")
local Net = engine("Network")
local World = engine("World")
local Unit = engine("Unit")
local Gui = engine("Gui")
local Vector2 = engine("Vector2")
local Vector3 = engine("Vector3")
local Color = engine("Color")

local function game_fn(t, name)
  if t == nil then return nil end
  local ok, v = pcall(function() return t[name] end)
  if ok and type(v) == "function" then return v end
  return nil
end

local function gcall(fn, ...)
  if type(fn) ~= "function" then return nil, "missing" end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil, tostring(a)
end

local get_session = game_fn(Net, "game_session")
local get_peer = game_fn(Net, "peer_id")
local obj_owned = game_fn(GS, "objects_owned_by")
local obj_exists = game_fn(GS, "game_object_exists")
local obj_is_type = game_fn(GS, "game_object_is_type")
local obj_field = game_fn(GS, "game_object_field")
local obj_batched = game_fn(GS, "game_object_field_batched")
local object_info = game_fn(Net, "object_info")
local in_session = game_fn(GS, "in_session")

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

local OPTION_IDS = {}

local function option(id, spec)
  if PUBLISHED_VISUAL_DEFAULTS[id]~=nil then spec.default=PUBLISHED_VISUAL_DEFAULTS[id] end
  OPTION_IDS[id] = spec
  -- Queue definitions until options.lua registers contiguous category blocks.
  -- No key is renamed and no saved setting is rewritten for menu grouping.
  return spec.default
end

local OPTION_CACHE = {}
local function opt(id)
  if OPTION_CACHE[id] ~= nil then return OPTION_CACHE[id] end
  local spec = OPTION_IDS[id]
  if spec == nil then return nil end
  local ok, v = pcall(chef.get, id)
  if ok and v ~= nil then return v end
  return spec.default
end

local function num(id, fallback)
  local v = opt(id)
  if type(v) == "number" and v == v and v > -math.huge and v < math.huge then return v end
  return fallback
end

-- toggles may come back as boolean, 0/1, or their choice label
local function on(id)
  local v = opt(id)
  if v == true then return true end
  if v == false then return false end
  if type(v) == "number" then return v ~= 0 end
  if type(v) == "string" then
    v = v:lower()
    return v == "on" or v == "true" or v == "yes" or v == "1"
  end
  return false
end

if type(chef.title) == "function" then pcall(chef.title, "HUD Lite " .. VERSION) end
if type(chef.own_log) == "function" then pcall(chef.own_log, "hud_lite") end

option("hud.lite.arc", { type = "toggle", label = "HUD cluster", default = true })
option("hud.lite.number", { type = "toggle", label = "Centre number", default = true })
option("hud.lite.track", { type = "toggle", label = "Arc tracks", default = true })
option("hud.lite.stamina", { type = "toggle", label = "Stamina ring (inner left)", default = true })
option("hud.lite.ammo", { type = "toggle", label = "Ammo ring (right)", default = true })
option("hud.lite.span", { type = "slider", label = "Arc span (degrees)",
  default = 100, min = 30, max = 180, step = 1 })
option("hud.lite.radius", { type = "slider", label = "Outer ring radius (px @1080p)",
  default = 78, min = 24, max = 300, step = 1 })
option("hud.lite.inner_radius", { type = "slider", label = "Inner ring radius (px @1080p)",
  default = 60, min = 12, max = 280, step = 1 })
option("hud.lite.thickness", { type = "slider", label = "Outer ring thickness (px)",
  default = 8, min = 1, max = 40, step = 0.5 })
option("hud.lite.inner_thickness", { type = "slider", label = "Inner ring thickness (px)",
  default = 5, min = 1, max = 30, step = 0.5 })
option("hud.lite.x", { type = "slider", label = "Offset X (px @1080p)",
  default = 0, min = -900, max = 900, step = 1 })
option("hud.lite.y", { type = "slider", label = "Offset Y from bottom (px @1080p)",
  default = 520, min = 0, max = 1080, step = 1 })
option("hud.lite.scale", { type = "slider", label = "Scale", default = 1, min = 0.4, max = 3, step = 0.05 })
option("hud.lite.number_size", { type = "slider", label = "Centre number height (px @1080p)",
  default = 38, min = 8, max = 220, step = 1 })
option("hud.lite.number_x", { type = "slider", label = "Centre number offset X (px)",
  default = 0, min = -500, max = 500, step = 1 })
option("hud.lite.alpha", { type = "slider", label = "Opacity (%)",
  default = 100, min = 10, max = 100, step = 5 })
option("hud.lite.number_align", { type = "choice", label = "Number alignment",
  choices = { "left", "centre" }, default = 1 })
option("hud.lite.number_y", { type = "slider", label = "Number offset Y (px, + is up)",
  default = 0, min = -500, max = 500, step = 1 })
option("hud.lite.function_icon", { type = "toggle", label = "Ammo type / weapon function icon", default = true })
option("hud.lite.zeroing", { type = "toggle", label = "Scope zeroing icon", default = true })
option("hud.lite.fire_y", { type = "slider", label = "Information row offset Y (px, + is up)",
  default = -74, min = -600, max = 400, step = 1 })
option("hud.lite.info_size", { type = "slider", label = "Health and stamina text height (px @1080p)",
  default = 14, min = 7, max = 40, step = 1 })
option("hud.lite.info_x", { type = "slider", label = "Health and stamina text offset X (px)",
  default = 0, min = -900, max = 900, step = 1 })
option("hud.lite.info_y", { type = "slider", label = "Health and stamina row offset Y (px, + is up)",
  default = -46, min = -600, max = 400, step = 1 })
option("hud.lite.smoothing", { type = "slider", label = "Ring smoothing (0 = off)",
  default = 12, min = 0, max = 30, step = 1 })
-- The unit layer exposes "exertion", but its meaning is not documented: we only
-- ever saw exertion = 0 while standing. 1 - exertion is therefore a GUESS, so it
-- is off by default. Switch it on and compare with the game's own stamina bar
-- before trusting it.

-- ---------------------------------------------------------------------------
-- colours (the game's own bar colour is copied; here: stock-HUD thresholds)
-- ---------------------------------------------------------------------------

local COLOUR_GOOD = { 236, 240, 235 }
local COLOUR_WARN = { 255, 199, 84 }
local COLOUR_BAD = { 255, 86, 80 }
local COLOUR_TRACK = { 0, 0, 0, 150 }
local COLOUR_STATUS = { 168, 176, 180 }

local function health_colour(ratio)
  if ratio == nil then return COLOUR_GOOD end
  if ratio > 0.55 then return COLOUR_GOOD end
  if ratio > 0.28 then return COLOUR_WARN end
  return COLOUR_BAD
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local S = {
  clock = 0,
  ratio = nil,
  hp = nil,
  max = nil,
  src = nil,
  at = -1e9,
  -- channels that are drawn but not wired yet (track-only until they are)
  stamina = nil,
  stamina_at = -1e9,
  mag = nil,
  mag_cap = nil,
  mag_at = -1e9,
  session = nil,
  peer = nil,
  player = nil,
  avatar = nil,
  owned = nil,
  owned_raw = nil,
  owned_at = -1e9,
  scan_cursor = 0,
  next_poll = 0,
  next_probe = 0,
  field_ok = nil,
  field_miss = 0,
  channel = "none",
  avatar_pick = nil,
  units_done = false,
  units_found = 0,
  units_at = 0,
  anim_found = 0,
  health_index = nil,
  health_index_missing = nil,
  avatar_field_count = nil,
  dumped = nil,
  batched_missing = nil,
  hash_logged = nil,
  hash_ok = nil,
  unit_at = nil,
  body = nil,
  units_logged2 = nil,
  anim_logged = nil,
  weapon = nil,
  throw_charge = nil,
  exertion = nil,
  logged = nil,
  reported = nil,
}

local Fix = {}
function Fix.finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
function Fix.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, value in pairs(v) do out[k] = Fix.copy(value) end
  return out
end
function Fix.hex(value, digits)
  if type(value) ~= "string" then return nil end
  local v = value:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^0x", "")
  if not v:match("^%x+$") or #v > digits then return nil end
  return "0x" .. string.rep("0", digits - #v) .. v
end
