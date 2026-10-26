-- Signal provider: maps layout slots onto sampled engine values.
local Provider = (function()
  local Core = { VERSION = "provider-v1" }
  local callable = EngineCall.callable

  local sr = rawget(_G, "stingray")
  local GS = sr and rawget(sr, "GameSession") or nil
  local Net = sr and rawget(sr, "Network") or nil

  local function slot_of(relation)
    if relation == nil then return nil end
    return (string.gsub(relation, "%-", "_"))
  end


  local function pad16(value, width)
    local text = string.lower(tostring(value))
    if string.sub(text, 1, 2) == "0x" then text = string.sub(text, 3) end
    if #text < width then text = string.rep("0", width - #text) .. text end
    return text
  end

  local Instance = {}
  Instance.__index = Instance

  local KINDS = { "authored", "table", "equipment", "underbarrel", "pack" }

  function Core.new(generated)
    local self = setmetatable({}, Instance)
    self.generated = generated or {}
    self.columns = self.generated.snapshot or {}
    self.fields = self.generated.network_fields or {}
    self.identity = self.generated.identity or {}
    self.signals = self.generated.signals or {}
    self.types_seen = {}
    self.role_tables = self.generated.role_tables or {}
    self.authored_base = self.generated.authored_base or {}
    self.authored_delta = self.generated.authored_delta or {}
    self.equipment = self.identity.equipment or {}
    self.packs = self.identity.backpacks or {}
    self.foreign_calls = self.generated.foreign_calls or {}
    self.foreign_steady = self.generated.foreign_steady or {}
    self.underbarrels = self.identity.underbarrels or {}
    self:reset_objects()
    self.declared_note = {}
    self.counters = {
      windows = 0, batched_calls = 0, batched_errors = 0,
      columns_filled = 0, columns_missing = 0, columns_pinned = 0,
      relations_read = 0, relations_skipped = 0,
      foreign_reads = 0, foreign_calls = 0, seats_vacant = 0,
      steady_kept = 0, steady_read = 0,
      declaration_calls = 0, declaration_errors = 0,
      declaration_types = 0, declaration_fields = 0,
      no_call_string = 0, hash_not_declared = 0,
      nested_reads = 0,
      delta_lookups = 0, delta_hits = 0, delta_misses = 0,
      delta_ambiguous = 0, signals_filled = 0,
      exists_misses = 0,
      action_filled = 0,
    }
    self.hashes = {}
    self.source_kind = {}
    for _, signal in pairs(self.signals) do
      for _, entry in ipairs(signal.sources or {}) do
        for at = 1, #KINDS do
          if type(entry) == "table" and entry[KINDS[at]] ~= nil then
            self.source_kind[entry] = KINDS[at]
            break
          end
        end
      end
    end
    self.delta_gate = {}
    for _, signal in pairs(self.signals) do
      for _, entry in ipairs(signal.sources or {}) do
        if type(entry) == "table" and entry.needs_delta ~= nil then
          self.delta_gate[entry] = { authored = entry.needs_delta,
                                     delta_from = entry.delta_from,
                                     relation = entry.relation }
        end
      end
    end
    return self
  end

  function Instance:field(signal, role)
    local row = self.signals[signal]
    if row == nil then return nil end
    return (self.role_tables[row.roles] or {})[role]
  end

  function Instance:cell_of(reads, signal, role)
    local spec = self:field(signal, role)
    local relation = (self.signals[signal] or {}).relation
    local hash = spec
    if type(spec) == "table" then
      hash = spec.field
      relation = spec.relation or relation
    end
    local read = reads[relation]
    if read == nil then return nil, false end
    if hash == nil then return nil, true end
    return read[hash], true
  end

  function Instance:raised(identity_result, column, relation)
    local hand = identity_result and identity_result.hand_weapon or nil
    local row = hand ~= nil and hand.type ~= nil
      and self.equipment[hand.type] or nil
    local want = row ~= nil and row[column] or nil
    if relation ~= "backpack" then
      return want ~= nil                          
    end
    local pack = identity_result and identity_result.backpack or nil
    return not (want ~= nil and pack ~= nil and pack.type ~= nil and
                want[pack.type] == true)          
  end

  function Instance:group(name, reads, identity_result, entry)
    local row = self.signals[name] or {}
    local kind = self:seated(identity_result,
                            slot_of(entry.relation or row.relation))
    local equipment = kind ~= nil and self.equipment[kind] or nil
    local groups = equipment ~= nil and equipment[entry.group] or nil
    local at = self:cell_of(reads, name, entry.from)
    if type(groups) ~= "table" then return nil, false end
    if type(at) ~= "number" then return nil, true end
    return groups[at + 1], true
  end

  function Instance:overridden(name, reads, identity_result, entry)
    local row = self.signals[name] or {}
    local kind = self:seated(identity_result,
                             slot_of(entry.relation or row.relation))
    if kind == nil then return nil end
    local value = ((self.authored_base[entry.authored] or {})[kind])
    if type(value) == "table" then
      local group, grouped = nil, false
      if entry.group ~= nil then
        group, grouped = self:group(name, reads, identity_result, entry)
      end
      if grouped then
        if group == nil or #group == 0 then return nil end
        local total = 0
        for _, at in ipairs(group) do
          if type(value[at]) ~= "number" then return nil end
          total = total + value[at]
        end
        value = total
      else
        local at = entry.from ~= nil and
          self:cell_of(reads, name, entry.from) or nil
        if type(at) ~= "number" then return nil end
        value = value[at + 1]
      end
    end
    if entry.delta_from ~= nil then
      local array = self:cell_of(reads, name, entry.delta_from)
      local written = self.authored_delta[entry.authored] or {}
      if type(array) == "table" then
        local found, hits = nil, 0
        for _, raw in pairs(array) do
          local hit = written["0x" .. pad16(raw, 16)]
          if hit ~= nil then
            hits = hits + 1
            found = hit
          end
        end
        self.counters.delta_lookups = self.counters.delta_lookups + 1
        if hits == 1 then
          self.counters.delta_hits = self.counters.delta_hits + 1
          value = found
        elseif hits == 0 then
          self.counters.delta_misses = self.counters.delta_misses + 1
        else
          self.counters.delta_ambiguous = self.counters.delta_ambiguous + 1
          return nil
        end
      end
    end
    if type(value) ~= "number" or value <= 0 then return nil end
    return value
  end

  local function labelled(names, at, slot, fallback, bits)
    if type(names) ~= "table" then return nil end
    if slot ~= nil and type(at) == "number" then
      at = math.floor(at / (4 ^ slot)) % 4
    end
    if bits ~= nil and type(at) == "number" then
      local key = 0
      for index = 1, #bits do
        key = key * 2 + math.floor(at / (2 ^ bits[index])) % 2
      end
      at = key
    end
    if at == nil then
      if not fallback then return nil end
      at = 0
    end
    return names[tostring(at)]
  end

  function Instance:seated(identity_result, slot)
    local named = slot ~= nil and (identity_result or {})[slot] or nil
    return named ~= nil and named.type or nil
  end

  local BOOK_OF = {
    ["equipment"]   = { book = "equipment",    of = "hand_weapon",
                        named = true },
    ["underbarrel"] = { book = "underbarrels", of = "hand_weapon" },
    ["pack"]        = { book = "packs",        of = "backpack" },
  }

  function Instance:from_book(kind, name, reads, identity_result, entry)
    local seat = BOOK_OF[kind]
    if seat == nil then
      return labelled((self.identity or {})[entry.table],
                      self:cell_of(reads, name, entry.from),
                      entry.slot, false, entry.bits)
    end
    local type_hash = self:seated(identity_result, seat.of)
    local row = type_hash ~= nil and self[seat.book][type_hash] or nil
    if not seat.named then
      return row ~= nil and row[entry[kind]] or nil
    end
    local at, was_read = self:cell_of(reads, name, entry.from)
    return labelled(row ~= nil and row[entry[kind]] or nil,
                    at, entry.slot, was_read)
  end

  function Instance:from_sources(name, reads, identity_result)
    local sources = (self.signals[name] or {}).sources
    if sources == nil then return nil, false, nil, "no-sources" end
    local shut = false
    for index = 1, #sources do
      local entry = sources[index]
      local cell = entry
      local kind = self.source_kind[entry]
      local gated = type(entry) == "table" and entry.unless_authored ~= nil
        and self:raised(identity_result, entry.unless_authored,
                        (self.signals[name] or {}).relation)
      if not gated and type(entry) == "table" and entry.needs ~= nil then
        gated = not self:raised(identity_result, entry.needs,
                                (self.signals[name] or {}).relation)
      end
      if not gated and type(entry) == "table" and entry.needs_delta ~= nil then
        gated = self:overridden(name, reads, identity_result,
                                self.delta_gate[entry]) == nil
      end
      if gated then
        shut = true
        cell = nil
      elseif kind == "authored" then
        local value = self:overridden(name, reads, identity_result, entry)
        if value ~= nil then return value, true, nil, nil, entry.still end
        cell = nil
      elseif kind ~= nil then
        local value = self:from_book(kind, name, reads, identity_result, entry)
        if value ~= nil then return value, true, nil, nil, entry.still end
        cell = nil
      elseif type(entry) == "table" then
        cell = entry.from
        if entry.group ~= nil then
          local group, grouped = self:group(name, reads, identity_result, entry)
          cell = nil
          if grouped then
            if group == nil or #group == 0 then
              return nil, true, false, "incomplete"
            end
            local total = 0
            for _, at in ipairs(group) do
              local value = self:cell_of(reads, name, entry.by[at])
              if type(value) ~= "number" then
                return nil, true, false, "incomplete"
              end
              total = total + value
            end
            return total, true
          end
        elseif entry.by_any ~= nil then
          local at = self:cell_of(reads, name, entry.from)
          cell = nil
          if at ~= nil and at ~= entry.unless_value then
            cell = entry.by_any
          end
        elseif entry.by ~= nil then
          local at = self:cell_of(reads, name, entry.from)
          cell = nil
          if type(at) == "number" then cell = entry.by[at + 1] end
          if cell == nil and at ~= nil then
            cell = entry.by[tostring(at)]
          end
        end
      end
      local value = nil
      if type(cell) == "number" then
        value = cell
      elseif cell ~= nil then
        if cell ~= name and self.signals[cell] ~= nil then
          value = self:signal(cell, reads, identity_result)
        else
          value = self:cell_of(reads, name, cell)
        end
      end
      if value ~= nil then
        return value, true, nil, nil, type(entry) == "table" and entry.still
      end
    end
    if shut then return nil, true, nil, "gated" end
    local row = self.signals[name] or {}
    for index = 1, #sources do
      local entry = sources[index]
      local relation = (type(entry) == "table" and entry.relation) or row.relation
      if reads[relation] ~= nil then return nil, true, nil, "no-answer" end
    end
    return nil, true, nil, "unread"
  end

  function Instance:plus(name, reads, base, identity_result)
    local row = (self.signals[name] or {}).plus
    if row == nil then return base end
    local value = self:cell_of(reads, name, row.from)
    if value == nil then return base end
    local add = (value == false) and (row.when_false or 0) or 0
    if base == nil then return add > 0 and add or nil end
    return base + add
  end

  function Instance:signal(name, reads, identity_result)
    local listed, handled, complete, why, still =
      self:from_sources(name, reads, identity_result)
    if complete == false then return nil, why or "incomplete" end
    if handled then
      local value = self:plus(name, reads, listed, identity_result)
      if value ~= nil then return value, nil, still end
      return nil, why or "no-answer"
    end
    return nil, why or "no-sources"
  end

  function Instance:hashes_of(relation)
    local cached = self.hashes[relation]
    if cached ~= nil then return cached end
    local seen, rows = {}, {}
    local declared = self.fields[relation]
    if type(declared) == "table" then
      for index = 1, #declared do
        if seen[declared[index]] == nil then
          seen[declared[index]] = true
          rows[#rows + 1] = declared[index]
        end
      end
    end
    for _, source in pairs(self.columns) do
      if source.relation == relation and type(source.from) == "string" and
         string.sub(source.from, 1, 2) == "0x" and seen[source.from] == nil then
        seen[source.from] = true
        rows[#rows + 1] = source.from
      end
    end
    self.hashes[relation] = rows
    return rows
  end

  local CALL_TABLES = { "equipment", "backpacks", "underbarrels", "pack_links" }
  local CALL_SINGLES = { "avatar", "player" }

  function Instance:call_of(type_hash)
    for index = 1, #CALL_TABLES do
      local row = (self.identity[CALL_TABLES[index]] or {})[type_hash]
      if row ~= nil and type(row.call) == "string" then return row.call end
    end
    for index = 1, #CALL_SINGLES do
      local one = self.identity[CALL_SINGLES[index]] or {}
      if one.type == type_hash and type(one.call) == "string" then
        return one.call
      end
    end
    return nil
  end

  function Instance:slots_of(type_hash)
    if type_hash == nil then return nil end
    local known = self.slots[type_hash]
    if known ~= nil then
      if known == false then return nil end
      return known
    end
    local call = self:call_of(type_hash)
    if call == nil then
      self.counters.no_call_string = self.counters.no_call_string + 1
      self.slots[type_hash] = false
      return nil
    end
    if not callable(Net, "object_info") then
      self.slots[type_hash] = false
      return nil
    end
    self.counters.declaration_calls = self.counters.declaration_calls + 1
    local ok, info = pcall(Net.object_info, call)
    if not ok or type(info) ~= "table" or type(info.fields) ~= "table" then
      self.counters.declaration_errors = self.counters.declaration_errors + 1
      self.slots[type_hash] = false
      return nil
    end
    local at, counted, shape = {}, 0, {}
    for index, descriptor in pairs(info.fields) do
      if type(index) == "number" and index == math.floor(index) and
         type(descriptor) == "table" and type(descriptor.id) == "string" then
        local hash = "0x" .. pad16(descriptor.id, 8)
        at[hash] = index
        counted = counted + 1
        shape[#shape + 1] = hash .. ":" .. tostring(descriptor.type) ..
                            ":" .. tostring(descriptor.bits) ..
                            ":" .. tostring(descriptor.min) ..
                            ":" .. tostring(descriptor.max)
      end
    end
    if counted == 0 then
      self.counters.declaration_errors = self.counters.declaration_errors + 1
      self.slots[type_hash] = false
      return nil
    end
    table.sort(shape)
    self.declared_note[type_hash] = table.concat(shape, ",")
    self.counters.declaration_types = self.counters.declaration_types + 1
    self.counters.declaration_fields = self.counters.declaration_fields +
      counted
    self.slots[type_hash] = at
    return at
  end

  local function seated(value, seat, counters)
    if value[seat] ~= nil then return value[seat] end
    for _, one in pairs(value) do
      if type(one) == "table" and one[seat] ~= nil then
        counters.nested_reads = counters.nested_reads + 1
        return one[seat]
      end
    end
  end

  function Instance:reset_objects()
    self.out = {}
    self.slots = {}
    self.steady = {}
  end

  function Instance:one_by_one(session, goid, relation)
    if not callable(GS, "game_object_field") then return nil end
    local calls = self.foreign_calls[relation]
    if calls == nil then return nil end
    local steady = self.foreign_steady[relation] or {}
    local held = self.steady[relation]
    if held == nil or held.goid ~= goid then
      held = { goid = goid, values = {} }
      self.steady[relation] = held
    end
    local taken, asked = {}, 0
    for hash, call in pairs(calls) do
      local kept = nil
      if steady[hash] == true then kept = held.values[hash] end
      if kept ~= nil then
        taken[hash] = kept
        self.counters.steady_kept = self.counters.steady_kept + 1
      else
        asked = asked + 1
        local ok, value = pcall(GS.game_object_field, session, goid, call)
        if ok and value ~= nil then
          taken[hash] = value
          if steady[hash] == true then
            held.values[hash] = value
            self.counters.steady_read = self.counters.steady_read + 1
          end
        end
      end
    end
    self.counters.foreign_calls = self.counters.foreign_calls + asked
    self.counters.foreign_reads = self.counters.foreign_reads + 1
    return taken
  end

  function Instance:batched(session, goid, relation, type_hash)
    if not callable(GS, "game_object_field_batched") then return nil end
    for key in pairs(self.out) do self.out[key] = nil end
    self.counters.batched_calls = self.counters.batched_calls + 1
    local ok, value = pcall(GS.game_object_field_batched, session, goid,
                            self.out)
    if not ok then
      self.counters.batched_errors = self.counters.batched_errors + 1
      return nil
    end
    if type(value) ~= "table" then return nil end
    local at = self:slots_of(type_hash)
    if at == nil then
      return nil
    end
    self.types_seen[type_hash] = true
    local wanted, taken = self:hashes_of(relation), {}
    for index = 1, #wanted do
      local hash = wanted[index]
      local seat = at[hash]
      if seat == nil then
        self.counters.hash_not_declared = self.counters.hash_not_declared + 1
      else
        local cell_value = seated(value, seat, self.counters)
        if cell_value ~= nil then taken[hash] = cell_value end
      end
    end
    return taken
  end

  function Instance:live(session, goid)
    if not callable(GS, "game_object_exists") then return false end
    local ok, alive = pcall(GS.game_object_exists, session, goid)
    if not ok or alive ~= true then
      self.counters.exists_misses = self.counters.exists_misses + 1
      return false
    end
    return true
  end

  function Instance:read_relations(session, identity_result, window)
    local reads = {}
    for relation in pairs(self.fields) do
      local named = identity_result[slot_of(relation)]
      if named == false then
        self.counters.seats_vacant = self.counters.seats_vacant + 1
        window.relations[relation] = "no-seat"
        window.bearers[relation] = false
      elseif named == nil or named.goid == nil then
        self.counters.relations_skipped = self.counters.relations_skipped + 1
        window.relations[relation] = "no-object"
      elseif not self:live(session, named.goid) then
        self.counters.relations_skipped = self.counters.relations_skipped + 1
        window.relations[relation] = "object-gone"
      else
        local read
        if self.foreign_calls[relation] ~= nil then
          read = self:one_by_one(session, named.goid, relation)
        else
          read = self:batched(session, named.goid, relation, named.type)
        end
        if read == nil then
          self.counters.relations_skipped = self.counters.relations_skipped + 1
          window.relations[relation] = "batched-failed"
        else
          self.counters.relations_read = self.counters.relations_read + 1
          window.relations[relation] = "read"
          reads[relation] = read
          window.bearers[relation] = named.goid
        end
      end
    end
    return reads
  end

  local function cell(read, source)
    if read == nil then return nil end
    local value = read[source.from]
    if value == nil then return nil end
    if source.slot == nil then return value end
    if type(value) ~= "number" then return nil end
    local divisor = 4 ^ source.slot
    return math.floor(value / divisor) % 4
  end

  function Instance:read(identity_result, session)
    self.counters.windows = self.counters.windows + 1
    local window = { cells = {}, relations = {}, bearers = {}, absent = {},
                     pinned = {} }
    identity_result = identity_result or {}

    window.reads = self:read_relations(session, identity_result, window)
    return window
  end

  function Instance:fill(identity_result, window)
    identity_result = identity_result or {}
    local reads = window.reads
    for column, source in pairs(self.columns) do
      local value, why, still = nil, nil, nil
      if source.const ~= nil then
        value = source.const
      elseif type(source.from) == "string" and
             string.sub(source.from, 1, 7) == "signal:" then
        value, why, still = self:signal(string.sub(source.from, 8), reads,
                                        identity_result)
        if value ~= nil then
          self.counters.signals_filled = self.counters.signals_filled + 1
        end
      elseif type(source.from) == "string" and
             string.sub(source.from, 1, 7) == "action:" then
        local action = identity_result.action
        if type(action) == "table" then
          value = action[string.sub(source.from, 8)]
          if value ~= nil then
            self.counters.action_filled =
              self.counters.action_filled + 1
          end
          why = "no-action-value"
        else
          why = "no-action"
        end
      elseif source.from ~= nil then
        value = cell(reads[source.relation], source)
        why = reads[source.relation] == nil and "unread" or "no-cell"
      end
      if value ~= nil then
        window.cells[column] = value
        if still == true then
          window.pinned[column] = true
          self.counters.columns_pinned = self.counters.columns_pinned + 1
        end
        self.counters.columns_filled = self.counters.columns_filled + 1
      else
        self.counters.columns_missing = self.counters.columns_missing + 1
        window.absent[column] = why or "no-source"
      end
    end
    return window
  end

  function Instance:declared_of(type_hash)
    if type_hash == nil then return nil end
    return self.declared_note[type_hash]
  end

  local POPULATIONS = { "equipment", "backpacks", "underbarrels", "pack_links" }

  function Instance:coverage()
    local out, known = {}, {}
    local avatar = (self.identity.avatar or {}).type
    if avatar ~= nil then
      known[avatar] = true
      out[#out + 1] = "avatar=" ..
        (self.types_seen[avatar] and "1" or "0") .. "/1"
    end
    for index = 1, #POPULATIONS do
      local name = POPULATIONS[index]
      local rows = self.identity[name]
      if type(rows) == "table" then
        local total, seen = 0, {}
        for type_hash in pairs(rows) do
          total = total + 1
          known[type_hash] = true
          if self.types_seen[type_hash] then seen[#seen + 1] = type_hash end
        end
        if total > 0 then
          table.sort(seen)
          local named = {}
          for index = 1, #seen do
            if index > 12 then break end
            named[#named + 1] = seen[index]
          end
          out[#out + 1] = name .. "=" .. #seen .. "/" .. total ..
            (#named > 0 and ("=" .. table.concat(named, ",")) or "")
        end
      end
    end
    local stray = {}
    for type_hash in pairs(self.types_seen) do
      if not known[type_hash] then stray[#stray + 1] = type_hash end
    end
    if #stray > 0 then
      table.sort(stray)
      local named = {}
      for index = 1, #stray do
        if index > 5 then break end
        named[#named + 1] = stray[index]
      end
      out[#out + 1] = "stray=" .. #stray .. "=" ..
                      table.concat(named, ",")
    end
    return table.concat(out, " ")
  end

  function Instance:report()
    return EngineCall.counters_of(self.counters)
  end

  return Core
end)()
