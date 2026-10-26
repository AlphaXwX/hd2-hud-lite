-- Per-frame sample snapshot container.
local Snapshot = (function()
  local Core = { VERSION = "snapshot-v1" }

  Core.OWNER_UNKNOWN = "owner-unknown"
  Core.OWNER_VACANT = "owner-vacant"

  local Instance = {}
  Instance.__index = Instance

  function Core.new(generated)
    local self = setmetatable({}, Instance)
    self.generated = generated or {}
    self.slots = {}
    for side, rows in pairs(self.generated.slots or {}) do
      local by_key, groups = {}, {}
      for index = 1, #rows do
        local row = rows[index]
        if by_key[row.key] == nil then
          by_key[row.key] = {}
          groups[#groups + 1] = by_key[row.key]
        end
        local bucket = by_key[row.key]
        bucket[#bucket + 1] = row
      end
      table.sort(groups, function(a, b) return a[1].key < b[1].key end)
      self.slots[side] = groups
    end
    local slot_keys = self.generated.slot_keys or {}
    local slot_owners = self.generated.slot_owners or {}
    local guest_order = self.generated.guest_order or {}
    self.owner_by_key = {}
    for name, relation in pairs(slot_owners) do
      local key = slot_keys[name]
      if key ~= nil then self.owner_by_key[key] = relation end
    end
    self.rank = {}
    for index = 1, #guest_order do
      self.rank[guest_order[index]] = index
    end
    self.counters = {
      windows = 0, drawn = 0, empty_slots = 0,
      owner_wins = 0, guest_wins = 0, undecided = 0, owner_unknown = 0,
      owner_vacant = 0,
    }
    return self
  end

  function Instance:pick(key, rows, prepared, taken)
    local owner = self.owner_by_key[key]
    if owner ~= nil then
      local bearer = prepared.bearers[owner]
      if bearer == false then
        self.counters.owner_vacant = self.counters.owner_vacant + 1
        return nil, Core.OWNER_VACANT
      end
      if bearer == nil then
        self.counters.owner_unknown = self.counters.owner_unknown + 1
        return nil, Core.OWNER_UNKNOWN
      end
    end
    local best, best_rank, tied, missing = nil, nil, false, nil
    for index = 1, #rows do
      local row = rows[index]
      local entry = prepared.candidates[row]
      if entry == nil then
        missing = prepared.rejected[row] or missing
      elseif taken[entry.column] then
        missing = "drawn-elsewhere"
      else
        local rank = self.rank[entry.relation] or math.huge
        if owner ~= nil and entry.relation == owner and row.owner == true then
          rank = -1
        end
        if best_rank == nil or rank < best_rank then
          best, best_rank, tied = row, rank, false
        elseif rank == best_rank and row.value ~= best.value then
          tied = true
        end
      end
    end
    if best == nil then return nil, missing end
    if tied then
      self.counters.undecided = self.counters.undecided + 1
      return nil, "undecided"
    end
    local how = best_rank == -1 and "owner" or "guest"
    self.counters[how .. "_wins"] = self.counters[how .. "_wins"] + 1
    return prepared.candidates[best], how
  end

  function Instance:assemble(prepared)
    self.counters.windows = self.counters.windows + 1
    local out = {
      at = prepared.at,
      diagnostics = { empty = {}, taken_by = {} },
    }
    local diagnostics = out.diagnostics
    for side, groups in pairs(self.slots) do
      local drawn, taken = {}, {}
      for index = 1, #groups do
        local rows = groups[index]
        local key, kind = rows[1].key, rows[1].kind
        if taken[kind] == nil then taken[kind] = {} end
        local entry, how = self:pick(key, rows, prepared, taken[kind])
        if entry == nil then
          self.counters.empty_slots = self.counters.empty_slots + 1
          diagnostics.empty[key] = how
        else
          taken[kind][entry.column] = true
          drawn[#drawn + 1] = {
            key = key, kind = entry.kind, column = entry.column,
            relation = entry.relation, values = { entry.values[1] },
            max = entry.max, display = entry.display, taken_by = how,
            unit = entry.unit, fraction = entry.fraction, locked = entry.locked,
            warned = entry.warned, full = entry.full,
            pinned = entry.pinned, phase = entry.phase, rate = entry.rate,
            raw = entry.raw,
          }
          diagnostics.taken_by[key] = how .. ":" .. entry.column
          self.counters.drawn = self.counters.drawn + 1
        end
      end
      out[side] = drawn
    end
    return out
  end

  function Instance:report()
    return EngineCall.counters_of(self.counters)
  end

  return Core
end)()

-- Sampled model: prepares and shapes draw commands for the renderer.
local HudModel = (function()
  local Core = { VERSION = "hud-model-v1" }


  local Instance = {}
  Instance.__index = Instance

  function Core.new(generated)
    local self = setmetatable({}, Instance)
    self:reset_objects()
    self.sides = (generated or {}).sides or {}
    self.primitives = (((generated or {}).layout or {}).primitives) or {}
    local columns = (generated or {}).snapshot or {}
    self.entries = {}
    for _, rows in pairs((generated or {}).slots or {}) do
      for _, row in ipairs(rows) do
        local entry = { row = row, key = row.key, kind = row.kind, column = row.value,
          relation = (columns[row.value] or {}).relation,
          values = {}, display = row.display, reads = {} }
        self.entries[#self.entries + 1] = entry
        local function bind(target, key, name)
          if name ~= nil then
            entry.reads[#entry.reads + 1] = { target = target, key = key, name = name }
          end
        end
        entry.state = {}
        for key, name in pairs(row.display or {}) do
          if string.sub(key, -5) == "_when" then
            bind(entry.state, string.sub(key, 1, -6), name)
          end
        end
        if row.charge ~= nil then
          entry.charge = {}
          for part, name in pairs(row.charge) do
            bind(entry.charge, part, name)
          end
        end
        if row.rise_rate ~= nil or row.fall_rate ~= nil then
          entry.motion = {}
          bind(entry.motion, "rise", row.rise_rate)
          bind(entry.motion, "fall", row.fall_rate)
          bind(entry.motion, "discharge", row.discharge_rate)
        end
        bind(entry, "warn_level", row.warn_above)
        if row.charge ~= nil or row.rise_rate ~= nil or row.fall_rate ~= nil then
          local parts = { tostring((columns[row.value] or {}).relation),
            row.value, tostring(row.max), tostring(row.charge ~= nil),
            tostring(row.rise_rate), tostring(row.fall_rate),
            tostring(row.discharge_rate),
            tostring((row.display or {}).rise_when) }
          local named = {}
          for part in pairs(row.charge or {}) do
            named[#named + 1] = part
          end
          table.sort(named)
          for _, part in ipairs(named) do
            parts[#parts + 1] = part .. "=" .. tostring(row.charge[part])
          end
          entry.time_source = table.concat(parts, "\1")
        end
      end
    end
    self.idle_fade_seconds =
      ((generated or {}).layout or {}).style ~= nil and
      generated.layout.style.idle_fade_seconds or nil
    self.counters = {
      windows = 0, shapes = 0, active = 0, idle = 0, awake = 0,
      changes = 0, clock_rewinds = 0, no_value = 0, no_fraction = 0,
      no_denominator = 0, over_max = 0,
      locked = 0,
      charge_starts = 0, charge_reads = 0,
      charge_dry = 0, charge_safe_clamps = 0,
      hidden_zero = 0,
    }
    return self
  end

  function Instance:reset_objects()
    self.said = {}
    self.thermal = {}
    self.thermal_active = {}
    self.charge = {}
  end


  function Instance:says(shape, now, awake)
    local mark = self:mark_of(shape)
    local state = self.said[shape.key]
    if state == nil then
      state = { signature = nil, at = now }
      self.said[shape.key] = state
    end
    if state.signature ~= mark then
      if state.signature ~= nil then
        self.counters.changes = self.counters.changes + 1
      end
      state.signature, state.at = mark, now
      return true
    end
    if now < state.at then
      self.counters.clock_rewinds = self.counters.clock_rewinds + 1
      state.at = now
      return true
    end
    if awake then
      state.at = now
      return true
    end
    return (now - state.at) <= self.idle_fade_seconds
  end

  function Instance:mark_of(shape)
    local values = shape.values
    local mark = tostring(shape.max)
    if type(values) == "table" then
      for index = 1, #values do
        mark = mark .. "" .. tostring(values[index])
      end
    end
    return mark
  end


  local function thermal_phase(entry, row, now)
    if entry.pinned then return "still" end
    local motion = entry.motion or {}
    local rising = (entry.state or {}).rise
    if entry.locked then rising = false end
    if rising == true then
      if type(motion.rise) == "number" and motion.rise > 0 then
        return "rise"
      end
      return "still"
    end
    if rising == false and type(motion.fall) == "number" and
       motion.fall > 0 then
      return "fall"
    end
    return "still"
  end

  local function thermal_speed(row, phase)
    local authored = row.motion[phase]
    if type(authored) ~= "number" or authored <= 0 then return 0 end
    local rate = row.live[phase]
    if type(rate) ~= "number" or rate <= 0 then rate = authored end
    if phase ~= "rise" then return -rate end
    return rate
  end

  local function thermal_limit(row, maximum)
    if row.phase == "discharge" then return row.raw end
    local step = row.step[row.phase]
    if type(step) ~= "number" then return nil end
    local speed = thermal_speed(row, row.phase)
    if speed > 0 then
      return math.min(maximum, math.max(row.shown, row.raw + step))
    elseif speed < 0 then
      return math.max(0, math.min(row.shown, row.raw - step))
    end
    return nil
  end

  local function thermal_prediction(row, now, maximum)
    local elapsed = now - row.at
    local correction_elapsed =
      math.max(0, math.min(now, row.correction_until) - row.at)
    local speed = thermal_speed(row, row.phase)
    local predicted = row.shown + speed * elapsed +
                      row.correction * correction_elapsed
    local limit = thermal_limit(row, maximum)
    if limit ~= nil then
      if speed > 0 then
        predicted = math.min(predicted, limit)
      elseif speed < 0 then
        predicted = math.max(predicted, limit)
      end
    end
    return math.max(0, math.min(predicted, maximum))
  end


  local function start_thermal_motion(row, shown, now)
    row.shown, row.at = shown, now
  end

  local function hide_thermal(row, now)
    local shown = thermal_prediction(row, math.max(now, row.at), row.maximum)
    row.shown, row.at = shown, now
    row.phase, row.phase_at = "fall", now
  end

  function Instance:charge_value(entry, value, now)
    if type(entry.charge) ~= "table" then return value end
    local key = entry.time_key
    local ammo = entry.charge.ammo
    local dry = type(ammo) == "number" and ammo <= 0
    local held = value == true
    if not held or dry then
      self.charge[key] = nil
      if dry then
        self.counters.charge_dry = self.counters.charge_dry + 1
      end
      return nil
    end
    local row = self.charge[key]
    if row == nil or row.maximum ~= entry.max or now < row.at then
      if row ~= nil and now < row.at then
        self.counters.clock_rewinds = self.counters.clock_rewinds + 1
      end
      self.charge[key] = { maximum = entry.max, at = now }
      self.counters.charge_starts = self.counters.charge_starts + 1
      return 0
    end
    self.counters.charge_reads = self.counters.charge_reads + 1
    local elapsed = now - row.at
    local safe = entry.charge.safe
    if type(safe) == "number" and entry.charge.mode == entry.charge.safe_mode
       and elapsed > safe then
      self.counters.charge_safe_clamps = self.counters.charge_safe_clamps + 1
      return safe
    end
    if elapsed > entry.max then return entry.max end
    return elapsed
  end

  function Instance:thermal_value(entry, value, now)
    if type(entry.motion) ~= "table" then return value end
    local key = entry.time_key
    if entry.pinned then
      self.thermal[key], self.thermal_active[key] = nil, nil
      return value
    end
    local row = self.thermal[key]
    local phase = thermal_phase(entry, row, now)
    if row == nil or row.maximum ~= entry.max or now < row.at then
      row = {
        raw = value, raw_at = now, phase = phase, phase_at = now,
        live = {}, step = {},
        correction = 0,
        correction_until = now, maximum = entry.max,
        motion = entry.motion,
      }
      start_thermal_motion(row, value, now)
      self.thermal[key] = row
      self.thermal_active[key] = row
      return value
    end

    self.thermal_active[key] = row
    row.motion = entry.motion
    local shown = thermal_prediction(row, now, entry.max)
    local raw_changed = value ~= row.raw

    if raw_changed and
       (phase == "still" or row.phase == "still" or
        value <= 0 or value >= entry.max) then
      row.phase, row.phase_at = phase, now
      row.raw, row.raw_at = value, now
      row.correction, row.correction_until = 0, now
      start_thermal_motion(row, value, now)
      return value
    end

    if row.phase == "discharge" then
      if not (raw_changed or phase ~= "fall" or shown <= row.raw) then
        phase = "discharge"
      end
    end

    if phase ~= row.phase then
      if row.phase == "rise" and row.raw_at <= row.phase_at and
         phase == "fall" and
         type(row.motion.discharge) == "number" then
        phase = "discharge"
        row.correction, row.correction_until = 0, now
      end
      row.phase, row.phase_at = phase, now
      if phase == "still" then
        row.correction, row.correction_until = 0, now
      end
      start_thermal_motion(row, shown, now)
    end

    if raw_changed then
      local elapsed = now - row.raw_at
      local delta = value - row.raw
      local same_span = row.raw_at >= row.phase_at
      row.raw, row.raw_at = value, now
      if elapsed > 0 then
        if same_span and
           ((phase == "rise" and delta > 0) or
            (phase == "fall" and delta < 0)) then
          row.live[phase] = math.abs(delta) / elapsed
          row.step[phase] = math.abs(delta)
        end
        start_thermal_motion(row, shown, now)
        if same_span then row.sample_span = elapsed end
        local span = row.sample_span or elapsed
        row.correction = (value - shown) / span
        row.correction_until = now + span
      else
        row.correction, row.correction_until = 0, now
        start_thermal_motion(row, shown, now)
      end
    end

    return shown
  end

  function Instance:prepare_value(entry, now, computed)
    if (self.primitives[entry.kind] or {}).fraction then
      if entry.max == nil then
        entry.unit = true
      else
        local show = entry.display or {}
        entry.raw = entry.values[1]
        local value = entry.values[1]
        if type(entry.max) == "number" and entry.max > 0 then
          local cached = computed[entry.time_key]
          if cached ~= nil then
            value = cached
          else
            value = self:charge_value(entry, value, now)
            if type(value) == "number" then
              value = self:thermal_value(entry, value, now)
            end
            local thermal = self.thermal[entry.time_key]
            if thermal ~= nil then
              entry.phase, entry.rate = thermal.phase, thermal.speed
            else
              entry.phase, entry.rate = nil, nil
            end
            if entry.time_key ~= nil then
              computed[entry.time_key] = value or false
            end
          end
        else
          value = nil
        end
        if type(value) == "number" then
          entry.values[1] = value
          if type(entry.charge) == "table" and
             type(entry.charge.full) == "number" and
             value >= entry.charge.full then
            entry.full = true
          end
          local fraction = value / entry.max
          if fraction < 0 then fraction = 0 end
          if fraction > 1 then
            self.counters.over_max = self.counters.over_max + 1
            fraction = 1
          end
          if show.direction == "fill" then fraction = 1 - fraction end
          entry.fraction = fraction
          if type(entry.warn_level) == "number" then
            entry.warned = entry.locked == true or value >= entry.warn_level
          end
        else
          self.counters.no_fraction = self.counters.no_fraction + 1
          return nil, "no-fraction"
        end
      end
    end
    return entry
  end

  function Instance:candidate(entry, window, now, computed)
    local row = entry.row
    local cells, bearers = window.cells or {}, window.bearers or {}
    local value = cells[row.value]
    if value == nil then
      self.counters.no_value = self.counters.no_value + 1
      return nil, "no-value"
    end
    if row.max ~= nil and cells[row.max] == nil then
      self.counters.no_denominator = self.counters.no_denominator + 1
      return nil, "no-denominator"
    end
    entry.values[1], entry.max = value, cells[row.max]
    entry.pinned = (window.pinned or {})[row.value] == true
    entry.unit, entry.fraction, entry.locked, entry.raw = nil, nil, nil, nil
    entry.warned, entry.full = nil, nil
    for _, read in ipairs(entry.reads) do
      read.target[read.key] = cells[read.name]
    end
    local dim = entry.pinned or (entry.state or {}).dim
    entry.locked = (dim ~= nil and dim ~= false) or nil
    if entry.time_source ~= nil then
      entry.time_key = entry.time_source .. "\1" .. tostring(bearers[entry.relation])
    end
    return self:prepare_value(entry, now, computed)
  end

  function Instance:prepare(window, now)
    window = window or {}
    if type(now) ~= "number" then now = 0 end
    local out = { candidates = {}, rejected = {}, bearers = window.bearers or {},
      at = now }
    local computed = {}
    for _, entry in ipairs(self.entries) do
      out.candidates[entry.row], out.rejected[entry.row] =
        self:candidate(entry, window, now, computed)
    end
    for key, row in pairs(self.thermal_active) do
      if type(computed[key]) ~= "number" then
        hide_thermal(row, now)
        self.thermal_active[key] = nil
      end
    end
    for key in pairs(self.charge) do
      if type(computed[key]) ~= "number" then self.charge[key] = nil end
    end
    return out
  end

  local function all_zero(shape)
    if (shape.display or {}).hide_zero ~= true then return false end
    local values = shape.values
    if type(values) ~= "table" or #values == 0 then return false end
    for index = 1, #values do
      if values[index] ~= 0 then return false end
    end
    return true
  end

  function Instance:shapes(assembled)
    self.counters.windows = self.counters.windows + 1
    local now = assembled.at
    local out = { diagnostics = { faded = {} } }
    for _, side in ipairs(self.sides) do
      local rows, shapes = assembled[side] or {}, {}
      for index = 1, #rows do
        local entry = rows[index]
        if all_zero(entry) then
          out.diagnostics.faded[entry.key] = "zero"
          self.counters.hidden_zero = self.counters.hidden_zero + 1
        else
          local shape = { key = entry.key, kind = entry.kind, values = entry.values,
            display = entry.display, unit = entry.unit, fraction = entry.fraction,
            locked = entry.locked, warned = entry.warned, full = entry.full,
            pinned = entry.pinned, phase = entry.phase, rate = entry.rate,
            raw = entry.raw,
            max = (self.primitives[entry.kind] or {}).fraction
                  and entry.max or nil }
          shapes[#shapes + 1] = shape
          if shape.locked then self.counters.locked = self.counters.locked + 1 end
          self.counters.shapes = self.counters.shapes + 1
          local awake = shape.locked == true or
                        (shape.display or {}).keeps_awake == true
          shape.say = self:says(shape, now, awake)
          local name = shape.say and "active" or "idle"
          self.counters[name] = self.counters[name] + 1
          if awake then self.counters.awake = self.counters.awake + 1 end
        end
      end
      out[side] = shapes
    end
    return out
  end

  function Instance:report()
    local out = EngineCall.counters_of(self.counters)
    out.idle_fade_seconds = self.idle_fade_seconds
    return out
  end

  return Core
end)()

-- Command renderer: turns model shapes into drawing calls.
local Renderer = (function()
  local Core = { VERSION = "renderer-v1" }


  local STATE = {
    [false] = {
      [false] = { [false] = { level = "active", tone = "normal" },
                  [true] = { level = "locked", tone = "normal" } },
      [true]  = { [false] = { level = "active", tone = "warn" },
                  [true] = { level = "locked", tone = "warn" } },
    },
    [true] = {
      [false] = { [false] = { level = "idle", tone = "normal" } },
      [true]  = { [false] = { level = "idle", tone = "warn" } },
    },
  }

  local FULL_STATE = {
    [false] = {
      [false] = { level = "active", tone = "full" },
      [true] = { level = "locked", tone = "full" },
    },
    [true] = {
      [false] = { level = "idle", tone = "full" },
    },
  }

  local Instance = {}
  Instance.__index = Instance

  function Core.new(generated)
    local self = setmetatable({}, Instance)
    self.generated = generated or {}
    local layout = self.generated.layout or {}
    self.style = {}
    for name, source in pairs(layout.slots or {}) do
      local style = {}
      for key, value in pairs(source) do style[key] = value end
      local place = (layout.places or {})[style.place] or {}
      if style.alpha == nil then style.alpha = place.alpha end
      if style.alpha == nil then style.alpha = (layout.style or {}).alpha end
      style.join = place.join
      self.style[name] = style
    end
    self.slot_name = {}
    self.commands, self.texts = {}, {}
    self.stacks, self.stacked, self.stack_group = {}, {}, {}
    self.says = {}
    for name, key in pairs(self.generated.slot_keys or {}) do
      self.slot_name[key] = name
      local style = self.style[name]
      if style ~= nil then
        self.commands[key] = { slot = name, key = key,
          kind = string.match(name, "^[^/]+/([^.]+)%."),
          place = style.place, alpha = style.alpha }
        self.texts[key] = {}
      end
    end
    self.sides = self.generated.sides or {}
    self.primitives = (layout.primitives) or {}
    local carried = {}
    for _, row in pairs(self.primitives) do
      for _, key in ipairs(row.style or {}) do carried[key] = true end
    end
    for _, key in ipairs({ "unit", "fraction", "text", "name",
                           "stack", "stack_of" }) do
      carried[key] = true
    end
    self.carried = {}
    for key in pairs(carried) do self.carried[#self.carried + 1] = key end
    table.sort(self.carried)
    self.counters = {
      frames = 0, drawn = 0, unstyled = 0, warned = 0,
    }
    for kind in pairs(self.primitives) do self.counters[kind] = 0 end
    for _, side in ipairs(self.sides) do self.counters[side] = 0 end
    return self
  end

  function Instance:style_for(key)
    local name = self.slot_name[key]
    if name == nil then return nil, nil end
    return self.style[name], name
  end

  local function text_of(cached, values, prefix)
    local previous = cached.values
    local same = previous ~= nil and #previous == #values
                 and cached.prefix == prefix
    if same then
      for index = 1, #values do
        if previous[index] ~= values[index] then same = false; break end
      end
    end
    if same then return cached.text end
    local parts, copied = {}, {}
    for index = 1, #values do
      parts[#parts + 1] = tostring(values[index])
      copied[index] = values[index]
    end
    local text = table.concat(parts, "/")
    if prefix ~= nil then text = prefix .. text end
    cached.values, cached.prefix, cached.text = copied, prefix, text
    return cached.text
  end

  function Instance:draw_shape(side, shape, host, warn, says, counts, ranks)
    local style, bare = self:style_for(shape.key)
    if style == nil then
      self.counters.unstyled = self.counters.unstyled + 1
      return
    end
    local idle = says[style.group or bare] ~= true
    local locked = shape.locked == true
    local warned = warn == true and style.warns == true
    local primitive = self.primitives[shape.kind]
    local draw = primitive ~= nil and host[shape.kind] or nil
    if draw == nil then
      self.counters.unstyled = self.counters.unstyled + 1
      return
    end
    local common = self.commands[shape.key]
    common.side = side
    if shape.full == true then
      common.state = FULL_STATE[idle][locked]
    else
      common.state = STATE[idle][warned][locked]
    end
    for _, key in ipairs(self.carried) do common[key] = nil end
    for _, key in ipairs(primitive.style or {}) do common[key] = style[key] end
    if primitive.fraction then
      common.unit = shape.unit
      common.fraction = shape.fraction
    end
    if shape.kind == "number" then
      local join = nil
      if style.join ~= nil and ranks ~= nil and bare ~= nil
          and (ranks[bare] or 1) > 1 then
        join = style.join
      end
      common.text = text_of(self.texts[shape.key], shape.values, join)
    elseif shape.kind == "icon" then
      common.name = shape.values[1]
    end
    if primitive.stacks then
      local count, position = 1, 1
      if counts ~= nil and bare ~= nil then
        local group = self.stack_group[bare]
        if group ~= nil and counts[group] ~= nil then count = counts[group] end
        if ranks[bare] ~= nil then position = ranks[bare] end
      end
      common.stack, common.stack_of = position, count
    end
    self.counters[shape.kind] = (self.counters[shape.kind] or 0) + 1
    draw(host, common)
    self.counters.drawn = self.counters.drawn + 1
  end

  function Instance:warned(side, rows, says)
    local warn = false
    for index = 1, #rows do
      local shape = rows[index]
      local style, name = self:style_for(shape.key)
      local said = shape.warned
      if said == nil then
        local floor = style ~= nil and style.warn_below or nil
        said = type(floor) == "number" and type(shape.fraction) == "number"
               and shape.fraction <= floor
      end
      if said then
        warn = true
        if says ~= nil and name ~= nil then
          says[style ~= nil and style.group or name] = true
        end
      end
    end
    return warn
  end

  function Instance:stack_counts(rows)
    local counts, ranks = self.stacks, self.stacked
    for key in pairs(counts) do counts[key] = nil end
    for key in pairs(ranks) do ranks[key] = nil end
    for key in pairs(self.stack_group) do self.stack_group[key] = nil end
    for index = 1, #rows do
      local shape = rows[index]
      if (self.primitives[shape.kind] or {}).stacks then
        local style, name = self:style_for(shape.key)
        if style ~= nil and style.place ~= nil and name ~= nil then
          local group = style.place .. "\1" .. shape.kind
          counts[group] = (counts[group] or 0) + 1
          self.stack_group[name] = group
          ranks[name] = 1
          for other, rank in pairs(ranks) do
            if other ~= name and self.stack_group[other] == group then
              if other < name then ranks[name] = ranks[name] + 1
              else ranks[other] = rank + 1 end
            end
          end
        end
      end
    end
    return counts, ranks
  end

  function Instance:group_says(shapes)
    local says = self.says
    for key in pairs(says) do says[key] = nil end
    for _, side in ipairs(self.sides) do
      local rows = shapes[side] or {}
      for index = 1, #rows do
        local shape = rows[index]
        local style, name = self:style_for(shape.key)
        if style ~= nil and name ~= nil then
          local group = style.group or name
          if shape.say == true then says[group] = true
          elseif says[group] == nil then says[group] = false end
        end
      end
    end
    return says
  end

  function Instance:draw(shapes, host)
    self.counters.frames = self.counters.frames + 1
    shapes = shapes or {}
    local says = self:group_says(shapes)
    for _, side in ipairs(self.sides) do
      local rows = shapes[side] or {}
      self.counters[side] = self.counters[side] + #rows
      local warn = self:warned(side, rows, says)
      if warn then self.counters.warned = self.counters.warned + 1 end
      local counts, ranks = self:stack_counts(rows)
      for index = 1, #rows do
        self:draw_shape(side, rows[index], host, warn, says, counts, ranks)
      end
    end
  end

  function Instance:report()
    return EngineCall.counters_of(self.counters)
  end

  return Core
end)()
