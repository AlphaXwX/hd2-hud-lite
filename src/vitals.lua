-- Vitals sampling: health, stamina, avatar declaration and body units.
local HP_FIELDS, MAX_FIELDS = {"health"}, {"max_health"}
local AVATAR_TYPE = "gl7xl2w"
local function field_number(goid, name)
  if goid == nil then return nil end
  local v = Native.field(S.session, goid, name)
  if Fix.finite(v) then return v end
  return nil
end

local function sane_ratio(v)
  if type(v) ~= "number" or v ~= v then return nil end
  if v == math.huge or v == -math.huge or v < 0 then return nil end
  if v <= 1.0001 then return v end
  return nil
end

local function read_max(goid)
  for _, name in ipairs(MAX_FIELDS) do
    local v = field_number(goid, name)
    if v ~= nil and v > 1 and v < 100000 then return v end
  end
  return nil
end

-- 8-char hex form of a declaration row's field id
local function hash_of_field(row)
  local hash=type(row)=="table" and Model.hash(row.id)
  return hash and hash:sub(3) or nil
end

local HEALTH_HASH = "cb0453ea"

local function avatar_health_index()
  if S.health_index ~= nil then return S.health_index end
  if S.health_index_retry and S.clock<S.health_index_retry then return nil end
  S.health_index_retry=S.clock+1
  if object_info == nil then return nil end
  local info = Native.info(AVATAR_TYPE)
  local fields = type(info) == "table" and info.fields or nil
  if type(fields) ~= "table" then
    S.health_index_missing = true
    return nil
  end
  S.avatar_field_count = #fields
  for i = 1, #fields do
    if hash_of_field(fields[i]) == HEALTH_HASH then
      S.health_index = i

      return i
    end
  end
  S.health_index_missing = true
  return nil
end

local function avatar_batched()
  if S.avatar == nil then return nil end
  return Native.batch(S.session, S.avatar)
end

local function accept_health(value, source)
  if not Fix.finite(value) then return false end
  local ratio = sane_ratio(value)
  local hp, max = nil, nil
  if ratio == nil then
    max = read_max(S.avatar) or 100
    hp = value
    ratio = value / max
  else
    local reported = read_max(S.avatar)
    if reported ~= nil then max = reported; hp = value * reported end
  end
  if not Fix.finite(ratio) then return false end
  if ratio < 0 then ratio = 0 end
  if ratio > 1 then ratio = 1 end
  S.ratio, S.hp, S.max = ratio, hp, max
  S.src, S.at = source, S.clock
  return true
end

local function sample_health()
  if S.session == nil or S.avatar == nil then return false end

  -- preferred: declaration position of 0xcb0453ea + batched snapshot
  local index = avatar_health_index()
  local vals = avatar_batched()
  if vals ~= nil then
    if index ~= nil then
      local v = vals[index]
      if Fix.finite(v) then
        if accept_health(v, "batched#" .. index) then return true end
      end
    end
  end

  -- fallback: the by-name getters, still only on the typed avatar object
  for _, name in ipairs(HP_FIELDS) do
    local v = field_number(S.avatar, name)
    if v ~= nil and accept_health(v, name) then return true end
  end
  return false
end

local STAMINA_FIELD = "stamina"

local function sample_stamina()
  if S.avatar == nil then return end
  if S.stamina_next and S.clock < S.stamina_next then return end
  S.stamina_next = S.clock + 0.05

  local v = field_number(S.avatar, STAMINA_FIELD)
  if v == nil then
    if not S.stamina_missing then
      S.stamina_missing = true
      logf("stamina: '" .. STAMINA_FIELD .. "' returned no number")
    end
    return
  end
  -- 0..1 as documented, but tolerate a 0..100 reading
  local norm = v
  if norm > 1.5 then norm = norm / 100 end
  S.stamina = math.max(0, math.min(1, norm))
  S.stamina_at = S.clock
  S.stamina_src = STAMINA_FIELD
  if not S.stamina_logged then
    S.stamina_logged = true
    logf(string.format("stamina: raw=%s normalised=%.3f", tostring(v), S.stamina))
  end
end
