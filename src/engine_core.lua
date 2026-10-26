-- Guarded engine call layer: counting, pcall wrapping and liveness checks.
local EngineCall = (function()
  local Core = { VERSION = "engine-call-v1" }

  function Core.callable(namespace, name)
    return type(namespace) == "table" and
           type(rawget(namespace, name)) == "function"
  end

  function Core.attempt(fn, ...)
    if fn == nil then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
  end

  function Core.call(counters, fn, ...)
    local result = { pcall(fn, ...) }
    if result[1] ~= true then
      counters.errors = counters.errors + 1
      return nil
    end
    counters.calls = counters.calls + 1
    return result[2]
  end

  function Core.call_many(counters, fn, ...)
    local function collect(ok, ...)
      if ok ~= true then
        counters.errors = counters.errors + 1
        return nil
      end
      counters.calls = counters.calls + 1
      return { n = select("#", ...), ... }
    end
    return collect(pcall(fn, ...))
  end

  function Core.world_is_live(worlds, wanted)
    if type(worlds) ~= "table" or wanted == nil then return false end
    for index = 1, #worlds do
      if worlds[index] == wanted then return true end
    end
    return false
  end

  function Core.counters_of(counters)
    local out = {}
    for key, value in pairs(counters or {}) do out[key] = value end
    return out
  end

  return Core
end)()
-- Engine identity layer: resolves declarations, object fields and resource keys.

-- Fragment merge: folds the feature fragments into the shared layout graph.
local Fragments = (function()
  local Core = { VERSION = "fragments-v1" }

  local COMMON_SECTIONS = { "slot_keys", "slot_owners", "identity" }
  local TABLE_SECTIONS = { "snapshot", "signals", "role_tables",
                           "authored_base", "authored_delta" }
  local LAYOUT_SECTIONS = { "places", "slots" }

  local function common_layout(layout)
    local carried = {}
    for _, name in ipairs(LAYOUT_SECTIONS) do carried[name] = true end
    local names = {}
    for name in pairs(layout) do
      if not carried[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
  end
  local function sides_of(common)
    local named = (common or {}).sides
    if type(named) == "table" and #named > 0 then return named end
    return { "right", "left" }
  end

  local function absorb(into, from)
    for key, value in pairs(from or {}) do into[key] = value end
  end

  -- Chef Shared Loader port: the option fragments arrive as HD2-Options tables in chef.options
  -- (require of other resources is off limits to loader mods).
  function Core.load(name)
    local helper = rawget(_G, "chef")
    local options = type(helper) == "table" and helper.options or nil
    if type(options) ~= "table" then return nil, "no-require" end
    local part = options[name]
    if part == nil then return nil, "not-found" end
    if type(part) ~= "table" then return nil, "not-a-table" end
    return part
  end

  function Core.merge(common, load)
    load = load or Core.load
    common = common or {}
    local layout = common.layout or {}

    local out, counts = {}, { axes = 0, loaded = 0, absent = 0, rows = 0,
                              no_require = 0, not_found = 0,
                              not_a_table = 0, styled = 0 }
    for _, name in ipairs(COMMON_SECTIONS) do out[name] = common[name] end
    local carried = common_layout(layout)
    out.layout = {}
    for _, name in ipairs(carried) do out.layout[name] = layout[name] end
    for _, name in ipairs(LAYOUT_SECTIONS) do out.layout[name] = {} end
    for _, name in ipairs(TABLE_SECTIONS) do out[name] = {} end
    out.network_fields = {}
    out.foreign_calls = {}
    out.foreign_steady = {}

    local present, rows = {}, {}
    local sides = sides_of(common)
    out.sides = sides
    for _, side in ipairs(sides) do rows[side] = {} end

    for _, axis in ipairs(common.axes or {}) do
      counts.axes = counts.axes + 1
      local part, why = load(axis.resource)
      if part == nil then
        counts.absent = counts.absent + 1
        if why == "no-require" then
          counts.no_require = counts.no_require + 1
        elseif why == "not-a-table" then
          counts.not_a_table = counts.not_a_table + 1
        else
          counts.not_found = counts.not_found + 1
        end
      else
        counts.loaded = counts.loaded + 1
        for _, relation in ipairs(part.relations or {}) do
          present[relation] = true
        end
        for relation, list in pairs(part.network_fields or {}) do
          local bucket = out.network_fields[relation]
          if bucket == nil then
            bucket = {}
            out.network_fields[relation] = bucket
          end
          for _, hash in ipairs(list) do
            local seen = false
            for index = 1, #bucket do
              if bucket[index] == hash then
                seen = true
                break
              end
            end
            if not seen then bucket[#bucket + 1] = hash end
          end
        end
        for relation, calls in pairs(part.foreign_calls or {}) do
          local bucket = out.foreign_calls[relation]
          if bucket == nil then
            bucket = {}
            out.foreign_calls[relation] = bucket
          end
          for hash, call in pairs(calls) do bucket[hash] = call end
        end
        for relation, held in pairs(part.foreign_steady or {}) do
          local bucket = out.foreign_steady[relation]
          if bucket == nil then
            bucket = {}
            out.foreign_steady[relation] = bucket
          end
          for hash, keep in pairs(held) do bucket[hash] = keep end
        end
        for _, name in ipairs(TABLE_SECTIONS) do
          absorb(out[name], part[name])
        end
        for _, name in ipairs(LAYOUT_SECTIONS) do
          absorb(out.layout[name], (part.layout or {})[name])
        end
        for _, name in ipairs(carried) do
          local over = (part.layout or {})[name]
          if over ~= nil then
            local fresh = {}
            absorb(fresh, out.layout[name])
            absorb(fresh, over)
            out.layout[name] = fresh
            counts.styled = counts.styled + 1
          end
        end
        for _, side in ipairs(sides) do
          local into = rows[side]
          for _, row in ipairs((part.slots or {})[side] or {}) do
            into[#into + 1] = row
            counts.rows = counts.rows + 1
          end
        end
      end
    end

    local relations = {}
    for name in pairs(present) do relations[#relations + 1] = name end
    table.sort(relations)
    out.relations = relations

    for _, bucket in pairs(out.network_fields) do table.sort(bucket) end

    out.slots = {}
    for _, side in ipairs(sides) do
      local list = rows[side]
      table.sort(list, function(left, right)
        if left.key ~= right.key then return left.key < right.key end
        return tostring(left.value) < tostring(right.value)
      end)
      out.slots[side] = list
    end

    local order = {}
    for _, name in ipairs(common.guest_precedence or {}) do
      if present[name] then order[#order + 1] = name end
    end
    out.guest_order = order

    return out, counts
  end

  return Core
end)()
-- Signal provider: maps layout slots onto sampled engine values.
