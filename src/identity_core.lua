-- Engine identity layer: resolves declarations, object fields and resource keys.
local IdentityCore = (function()
  local Core = { VERSION = "identity-v3" }
  local call = EngineCall.call
  local call_many = EngineCall.call_many
  local callable = EngineCall.callable

  local sr = rawget(_G, "stingray")
  local GS = sr and rawget(sr, "GameSession") or nil
  local World = sr and rawget(sr, "World") or nil
  local Unit = sr and rawget(sr, "Unit") or nil
  local Net = sr and rawget(sr, "Network") or nil
  local Vector3 = sr and rawget(sr, "Vector3") or nil
  local IdString64 = sr and rawget(sr, "IdString64") or nil

  local UNRESOLVED = "unknown"
  local AVATAR_LIVING, AVATAR_DEAD = 0, 2

  local ABSENT = "absent"


  local NO_AVATAR_NOW = "no-avatar-right-now"

  local PENDING = {}




  local function surface_missing()
    if sr == nil then return "stingray" end
    local names = {
      { GS, "GameSession", { "objects_owned_by", "game_object_exists",
                             "game_object_is_type", "game_object_field" } },
      { World, "World", { "units_by_resource" } },
      { Unit, "Unit", { "alive", "node", "world_position",
                        "animation_has_variable", "animation_find_variable",
                        "animation_get_variable",
                        "has_animation_state_machine" } },
      { Net, "Network", { "object_info" } },
      { Vector3, "Vector3", { "distance" } },
    }
    for index = 1, #names do
      local namespace, label, members = names[index][1], names[index][2],
                                        names[index][3]
      if type(namespace) ~= "table" then return label end
      for member_index = 1, #members do
        if not callable(namespace, members[member_index]) then
          return label .. "." .. members[member_index]
        end
      end
    end
    return nil
  end

  local NO_OBJECT = 32767

  local Identity = {}
  Identity.__index = Identity

  function Core.new(authored)
    local self = setmetatable({}, Identity)
    self.authored = authored or {}
    self.avatar = self.authored.avatar or {}
    self.player = self.authored.player or {}
    self.carry = self.authored.carry_field or {}
    self.equipment = self.authored.equipment or {}
    self.equipment_defaults = self.authored.equipment_defaults or {}
    self.left_hand_grips = {}
    for _, grip in ipairs(self.authored.left_hand_grips or {}) do
      self.left_hand_grips[grip] = true
    end
    self.backpacks = self.authored.backpacks or {}
    self.underbarrels = self.authored.underbarrels or {}
    self.seats = self.authored.seats or 0
    self.scope = nil
    self.generation = 0
    self.base = nil          
    self.buckets = nil       
    self.counters = {
      calls = 0, errors = 0, resolves = 0, unknowns = 0, absents = 0,
      invalidations = 0,
      exists_misses = 0, type_calls = 0,
      type_field_reads = 0, mask_reads = 0,
      mask_undeclared = 0, mask_unreadable = 0,
      node_cached = 0, body_cached = 0, grip_cached = 0, player_cached = 0,
      squad_cached = 0, squad_scans = 0,
      squad_pending = 0,
      type_recycled = 0, type_skipped = 0,
      under_cached = 0, link_cached = 0,
      body_scans = 0, scans = 0, body_acquired = 0,
      world_kept = 0,
      action_reads = 0, bind_reads = 0,
      fast_hand = 0, fast_break = 0, carried = 0,
      mode_took_the_underbarrel = 0,
      action_no_row = 0, action_no_rig = 0, action_no_span = 0,
      action_cut_seat = 0, action_cut_clip = 0, action_cut_rewind = 0,
      action_carried = 0, action_still = 0, action_span_done = 0,
      action_stage_unread = 0, action_unit_gone = 0, action_gate_open = 0,
      action_gate_reads = 0, action_gate_stage = 0,
      kinds_one = 0, kinds_many = 0, bound_elsewhere = 0,
      aboard = 0,
      left_hand_buckets = 0,
      owned_seen = 0,
      wield_no_match = 0, mask_broke_the_tie = 0, gate_open_seated = 0,
      hand_gate_bound = 0, hand_gate_off_body = 0,
    }
    self:reset()
    return self
  end

  function Identity:reset()
    self.generation = self.generation + 1
    self.avatar_goid = nil
    self.object_type = {}
    self.type_missed = {}
    self.type_fields = {}
    self.carried_weapon = nil
    self.local_body = nil
    self.body_binding = { status = "unbound" }
    self.avatar_state, self.avatar_state_read = nil, false
    self.owned_set, self.owned_count = nil, nil
    self.base_short = nil
    self.pack_memo = nil
    self.under_memo, self.link_memo = nil, nil
    self.action_span = nil
    self.ship_memo = nil
    self.node_index = {}
    self.grip_index = {}
    self.player_goid = nil
    self.squad_memo = nil
    self.controlled_once = false
    self.counters.invalidations = self.counters.invalidations + 1
  end

  function Identity:sync(session, world, peer)
    local scope = self.scope
    local reborn = scope == nil or scope.session ~= session or
                   scope.peer ~= peer
    if reborn or scope.world ~= world then
      self.scope = { session = session, world = world, peer = peer }
      if not reborn then
        self:release_body("world-changed")
        self.node_index, self.grip_index = {}, {}
        self.counters.world_kept = self.counters.world_kept + 1
      end
    end
    if reborn then self:reset() end
  end

  function Identity:live(session, goid)
    local alive = call(self.counters, GS.game_object_exists, session, goid)
    if alive ~= true then
      self.counters.exists_misses = self.counters.exists_misses + 1
      return false
    end
    return true
  end

  function Core.node_position(counters, unit, index)
    if index == nil then return nil end
    return call(counters, Unit.world_position, unit, index)
  end

  function Core.node_of(counters, indices, unit, node_name)
    local per_unit = indices[unit] or {}
    indices[unit] = per_unit
    local known = per_unit[node_name]
    if known ~= nil then
      counters.node_cached = counters.node_cached + 1
      return known
    end
    local index = call(counters, Unit.node, unit, node_name)
    per_unit[node_name] = index
    return index
  end

  function Identity:release_body(status)
    self.local_body = nil
    self.body_binding = { status = status }
    self.carried_weapon = nil
    self.hand_unit = nil
  end

  function Identity:bind_body(session, world, avatar, in_control)
    local state = self:avatar_value(session, avatar, self.avatar.state_field)
    self.avatar_state, self.avatar_state_read = state, true
    if state == AVATAR_DEAD then
      self:release_body("dead")
      return nil
    end
    if self.local_body ~= nil then
      if call(self.counters, Unit.alive, self.local_body) == true then
        self.counters.body_cached = self.counters.body_cached + 1
        return self.local_body
      end
      self:release_body("unit-unavailable")
    end
    if in_control ~= true then
      self.body_binding = { status = "waiting-for-control" }
      return nil
    end
    if state ~= AVATAR_LIVING then
      self.body_binding = { status = "state-unconfirmed" }
      return nil
    end
    self.body_binding = { status = "unreadable" }
    local resource = self.avatar.third_person
    if resource == nil or not callable(Unit, "num_scene_graph_items") then return nil end
    local position = self:avatar_value(session, avatar, self.avatar.position_field)
    if type(position) ~= "userdata" or
       not string.match(tostring(position), "^Vector3%(") then return nil end
    local key = Core.resource_key(self.counters, resource)
    if key == nil then return nil end
    self.counters.body_scans = self.counters.body_scans + 1
    local units = call(self.counters, World.units_by_resource, world, key)
    if type(units) ~= "table" then return nil end
    local winner, nearest, tied, count = nil, math.huge, false, 0
    local seen = {}
    for _, unit in pairs(units) do
      if not seen[unit] then
        seen[unit] = true
        local alive = call(self.counters, Unit.alive, unit)
        if alive ~= true and alive ~= false then return nil end
        if alive == true then
          local last = call(self.counters, Unit.num_scene_graph_items, unit)
          if type(last) ~= "number" or last < 1 or last == math.huge or
             last ~= math.floor(last) then return nil end
          local root = Core.node_position(self.counters, unit, 1)
          if type(root) ~= "userdata" or
             not string.match(tostring(root), "^Vector3%(") then return nil end
          local distance = call(self.counters, Vector3.distance, position, root)
          if type(distance) ~= "number" or distance ~= distance or
             distance < 0 or distance == math.huge then return nil end
          count = count + 1
          if distance < nearest then
            nearest, winner, tied = distance, unit, false
          elseif distance == nearest then
            tied = true
          end
        end
      end
    end
    self.body_binding = { status = "ambiguous", candidates = count,
      distance = winner ~= nil and nearest or nil }
    if winner == nil or tied then return nil end
    self.local_body = winner
    self.body_binding.status = "bound"
    self.counters.body_acquired = self.counters.body_acquired + 1
    return winner
  end

  function Identity:at_wield_node(unit, anchor, row)
    local position = Core.node_position(self.counters, unit, 1)
    if position == nil then return false end
    local offset = row.wield_offset or self.equipment_defaults.wield_offset or 0
    local span = call(self.counters, Vector3.distance, anchor, position)
    return type(span) == "number" and math.abs(span - offset) == 0
  end

  function Identity:match_attachment(world, row, anchor, matched)
    local units = Core.units_of(self.counters, world, row.resource)
    local hit, ambiguous = false, false
    for index = 1, #units do
      if self:at_wield_node(units[index], anchor, row) then
        hit = true
        if matched ~= nil and matched ~= units[index] then ambiguous = true end
        matched = units[index]
      end
    end
    return hit, matched, ambiguous, #units
  end

  function Identity:narrow_by_wield(world, candidates)
    self.hand_unit = nil
    local body = self.local_body
    if body == nil then
      return {}, "no-local-body"
    end
    local nodes = {}
    local held = {}
    local matched, ambiguous = nil, false
    local saw_unit = false
    for index = 1, #candidates do
      local kind = candidates[index].type
      local row = self.equipment[kind]
      local node = row ~= nil and
        (row.wield_node or self.equipment_defaults.wield_node) or nil
      if held[kind] == nil and row ~= nil and row.resource ~= nil and node ~= nil then
        held[kind] = false
        local anchor = nodes[node]
        if anchor == nil then
          local index = Core.node_of(self.counters, self.node_index, body, node)
          anchor = Core.node_position(self.counters, body, index)
          nodes[node] = anchor or false
        end
        if anchor then
          local conflict, count
          held[kind], matched, conflict, count = self:match_attachment(world, row, anchor, matched)
          ambiguous = ambiguous or conflict
          saw_unit = saw_unit or count > 0
        end
      end
    end
    local kept = {}
    if ambiguous then return kept, "multiple-wield-units" end
    for index = 1, #candidates do
      if held[candidates[index].type] then kept[#kept + 1] = candidates[index] end
    end
    self.hand_unit = matched
    if #kept > 0 then return kept, "narrowed" end
    return kept, saw_unit and "nothing-at-the-wield-node" or "no-candidate-unit"
  end

  function Identity:carried_hand(candidates)
    local saved = self.carried_weapon
    if saved == nil then return {} end
    if call(self.counters, Unit.alive, saved.unit) == true then
      for index = 1, #candidates do
        local row = candidates[index]
        if row.goid == saved.goid and row.type == saved.type then
          self.counters.carried = self.counters.carried + 1
          self.hand_unit = saved.unit
          return { row }
        end
      end
    end
    self.carried_weapon = nil
    return {}
  end

  function Identity:base_candidates()
    local known = type(self.pack_memo) == "table"
    local slot = known and "base_short" or "base"
    if self[slot] ~= nil then return self[slot], slot end
    local rows = {}
    if self.avatar.type ~= nil then
      rows[#rows + 1] = self.avatar.type
    end
    if self.player.type ~= nil then
      rows[#rows + 1] = self.player.type
    end
    if not known then
      for hash in pairs(self.backpacks) do
        rows[#rows + 1] = hash
      end
    end
    table.sort(rows)
    self[slot] = rows
    return rows, slot
  end

  function Identity:grip_bucket(grip)
    if grip == nil then return nil end
    if self.buckets == nil then self.buckets = {} end
    local bucket = self.buckets[grip]
    if bucket ~= nil then return bucket.rows, bucket.set end
    local left = self.left_hand_grips[grip] == true
    if left then
      self.counters.left_hand_buckets = self.counters.left_hand_buckets + 1
    end
    local rows = {}
    for hash, row in pairs(self.equipment) do
      if (left and row.one_handed == true) or (not left and row.grip == grip) then
        rows[#rows + 1] = hash
      end
    end
    table.sort(rows)
    local set = {}
    for index = 1, #rows do set[rows[index]] = true end
    self.buckets[grip] = { rows = rows, set = set }
    return rows, set
  end

  function Identity:in_grip(hash, grip)
    local _, set = self:grip_bucket(grip)
    return set ~= nil and set[hash] == true
  end

  function Core.call_of(authored, hash)
    local row = (authored.equipment or {})[hash] or (authored.backpacks or {})[hash]
      or (authored.underbarrels or {})[hash] or (authored.pack_links or {})[hash]
    if row ~= nil then return row.call end
    if hash == (authored.avatar or {}).type then return (authored.avatar or {}).call end
    if hash == (authored.player or {}).type then return (authored.player or {}).call end
    return nil
  end

  function Core.type_rows(authored)
    local rows = {}
    for hash in pairs(authored.equipment or {}) do
      rows[#rows + 1] = hash
    end
    for hash in pairs(authored.backpacks or {}) do
      rows[#rows + 1] = hash
    end
    for hash in pairs(authored.underbarrels or {}) do
      rows[#rows + 1] = hash
    end
    for hash in pairs(authored.pack_links or {}) do
      rows[#rows + 1] = hash
    end
    table.sort(rows)
    return rows
  end

  function Identity:all_rows()
    if self.all == nil then self.all = Core.type_rows(self.authored) end
    return self.all
  end

  function Identity:scan_types(session, goid, missed, scope, rows)
    if rows == nil or missed[scope] then return nil end
    for index = 1, #rows do
      local hash = rows[index]
      local name = Core.call_of(self.authored, hash)
      if type(name) == "string" then
        self.counters.type_calls = self.counters.type_calls + 1
        local is_type = call(self.counters, GS.game_object_is_type,
                             session, goid, name)
        if is_type == true then
          self.object_type[goid] = hash
          return hash
        end
      end
    end
    missed[scope] = true
    return nil
  end

  function Identity:used_this_window(hash, grip)
    if hash == self.avatar.type or hash == self.player.type then return true end
    if self.backpacks[hash] ~= nil then return true end
    if self.underbarrels[hash] ~= nil then return true end
    return self:in_grip(hash, grip)
  end

  function Identity:type_of(session, goid, grip)
    local known = self.object_type[goid]
    if known ~= nil and not self:used_this_window(known, grip) then
      self.counters.type_skipped = self.counters.type_skipped + 1
      return nil
    end
    if known ~= nil then
      local name = Core.call_of(self.authored, known)
      local still = nil
      if type(name) == "string" then
        self.counters.type_calls = self.counters.type_calls + 1
        still = call(self.counters, GS.game_object_is_type, session, goid, name)
      end
      if still == true then return known end
      self.object_type[goid] = nil
      self.type_missed[goid] = nil
      self.counters.type_recycled = self.counters.type_recycled + 1
    end
    local missed = self.type_missed[goid]
    if missed == nil then
      missed = {}
      self.type_missed[goid] = missed
    end
    local base_rows, base_scope = self:base_candidates()
    local hash = self:scan_types(session, goid, missed, base_scope, base_rows)
    if hash ~= nil then return hash end
    return self:scan_types(session, goid, missed, grip,
                           (self:grip_bucket(grip)))
  end

  function Identity:owned_objects(session, my_peer, grip, owned)
    if owned == nil then
      owned = call(self.counters, GS.objects_owned_by, session, my_peer)
    end
    if type(owned) ~= "table" then return nil end
    local rows = {}
    self.counters.scans = self.counters.scans + 1
    local seen = 0
    for _, goid in pairs(owned) do
      seen = seen + 1
      local hash = self:type_of(session, goid, grip)
      if hash ~= nil then
        rows[#rows + 1] = { goid = goid, type = hash }
      end
    end
    self.counters.owned_seen = seen
    return rows
  end

  function Core.resource_key(counters, resource)
    if type(resource) ~= "string" then return nil end
    local hex = string.match(resource, "^0[xX](%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)$")
    if hex == nil then return resource end
    if not callable(IdString64, "from_hex") then return nil end
    return call(counters, IdString64.from_hex, hex)
  end

  function Core.units_of(counters, world, resource)
    local key = Core.resource_key(counters, resource)
    if key == nil then return {} end
    local found = call(counters, World.units_by_resource, world, key)
    if type(found) ~= "table" then return {} end
    local units = {}
    for _, unit in pairs(found) do
      if call(counters, Unit.alive, unit) == true then
        units[#units + 1] = unit
      end
    end
    return units
  end

  function Identity:current_grip(body)
    if body == nil then return nil, "no-local-body" end
    return self:grip_variable_of(body)
  end

  function Identity:grip_variable_of(unit)
    local name = self.avatar.grip_variable or "weapon_selected"
    local index = self.grip_index[unit]
    if index ~= nil then
      self.counters.grip_cached = self.counters.grip_cached + 1
      local cached = call(self.counters, Unit.animation_get_variable, unit, index)
      if type(cached) ~= "number" then return nil, "variable-unreadable" end
      return cached, nil
    end
    if call(self.counters, Unit.has_animation_state_machine, unit) ~= true then
      return nil, "no-animation-state-machine"
    end
    if call(self.counters, Unit.animation_has_variable, unit, name) ~= true then
      return nil, "no-variable:" .. name
    end
    index = call(self.counters, Unit.animation_find_variable, unit, name)
    if type(index) ~= "number" or index <= 0 then
      return nil, "variable-index-missing"
    end
    self.grip_index[unit] = index
    local value = call(self.counters, Unit.animation_get_variable, unit, index)
    if type(value) ~= "number" then return nil, "variable-unreadable" end
    return value, nil
  end

  local ACTION_INFINITE = 1e30
  local function read_action_layer(counters, unit, layer)
    if call(counters, Unit.has_animation_state_machine, unit) ~= true then
      return nil
    end
    local packed = call_many(counters, Unit.animation_get_state, unit)
    if packed == nil or layer < 1 or layer > packed.n - 1 then return nil end
    local state = packed[layer + 1]
    if state == nil then return nil end
    local info = call_many(counters, Unit.animation_layer_info, unit, layer)
    if info == nil or info.n < 2 then return nil end
    local elapsed, length = info[1], info[2]
    if type(elapsed) ~= "number" or type(length) ~= "number" then return nil end
    if length <= 0 or length >= ACTION_INFINITE then return nil end
    counters.action_reads = counters.action_reads + 1
    return { elapsed = elapsed, length = length, state = state,
             running = true }
  end

  Core.action_layer = read_action_layer

  function Identity:reload_stage_of(hand, window)
    local spot = (self.authored.action or {}).stage
    if type(spot) ~= "table" or window == nil then return nil end
    local read = (window.reads or {})[spot.relation]
    local value = read ~= nil and read[spot.hash] or nil
    if type(value) ~= "number" then
      self.counters.action_stage_unread =
        self.counters.action_stage_unread + 1
      return nil
    end
    if value == 0 then return nil end
    self.counters.action_gate_stage =
      self.counters.action_gate_stage + 1
    return {}, nil, true
  end

  function Identity:reload_clip_of(hand, window)
    local row = self.equipment[hand.type]
    if row == nil then
      self.counters.action_no_row = self.counters.action_no_row + 1
      return self:reload_stage_of(hand, window)
    end
    local rig = row.reload
    if rig == nil then
      self.counters.action_no_rig = self.counters.action_no_rig + 1
      return nil
    end
    local unit = self.hand_unit
    if unit == nil then return nil end
    if call(self.counters, Unit.alive, unit) ~= true then
      self.counters.action_unit_gone =
        self.counters.action_unit_gone + 1
      return nil
    end
    if call(self.counters, Unit.has_animation_state_machine, unit) ~= true then
      return nil
    end
    local packed = call_many(self.counters, Unit.animation_get_state, unit)
    if packed == nil then return nil end
    self.counters.action_gate_reads =
      self.counters.action_gate_reads + 1
    for layer = 0, packed.n - 1 do
      local seats = rig[layer]
      if seats ~= nil then
        local state = packed[layer + 1]
        local span
        if state ~= nil then span = seats[state] end
        if span ~= nil then
          self.counters.action_gate_open =
            self.counters.action_gate_open + 1
          return span, layer, state
        end
      end
    end
    return nil
  end

  function Identity:action_of(hand, rig, window)
    local spec = self.authored.action
    if type(spec) ~= "table" or type(spec.layer) ~= "number" then return nil end
    if type(hand) ~= "table" or hand.goid == nil then
      self.action_span = nil
      return nil
    end
    local span = self.action_span
    if span ~= nil and span.goid ~= hand.goid then span = nil end
    local seat, layer, index = self:reload_clip_of(hand, window)
    if seat == nil then
      self.action_span = nil
      return nil
    end
    if span ~= nil and (span.layer ~= layer or span.index ~= index) then
      self.counters.action_cut_seat = self.counters.action_cut_seat + 1
      span = nil
      self.action_span = nil
    end
    if span ~= nil then
      self.counters.action_carried = self.counters.action_carried + 1
    end
    local reading
    if rig ~= nil and call(self.counters, Unit.alive, rig) == true then
      reading = read_action_layer(self.counters, rig, spec.layer)
    end
    if reading == nil then
      self.action_span = nil
      return nil
    end
    local clip, tail = seat.clip or reading.length, seat.tail
    if span ~= nil then
      if reading.length ~= span.length then
        self.counters.action_cut_clip =
          self.counters.action_cut_clip + 1
        self.action_span = nil
        return nil
      end
      if reading.elapsed < span.elapsed then
        self.counters.action_cut_rewind =
          self.counters.action_cut_rewind + 1
        self.action_span = nil
        return nil
      end
      if reading.elapsed == span.elapsed then
        self.counters.action_still = self.counters.action_still + 1
      end
    end
    local base = span ~= nil and span.base or reading.elapsed
    local length = clip - (tail or 0) - base
    if length <= 0 then
      self.counters.action_no_span = self.counters.action_no_span + 1
      self.action_span = nil
      return nil
    end
    if reading.elapsed - base >= length then
      self.counters.action_span_done =
        self.counters.action_span_done + 1
      self.action_span = nil
    else
      if span == nil then
        span = { goid = hand.goid, length = reading.length, base = base,
                 layer = layer, index = index }
        self.action_span = span
      end
      span.elapsed = reading.elapsed
    end
    reading.elapsed = reading.elapsed - base
    reading.length = length
    return reading
  end

  function Core.declaration(counters, call_string)
    if type(call_string) ~= "string" then return nil, nil end
    local info = call(counters, Net.object_info, call_string)
    if type(info) ~= "table" then return nil, nil end
    local set, order = {}, {}
    local ok, complete = pcall(function()
      local fields = info.fields
      if type(fields) ~= "table" then return false end
      for index = 1, #fields do
        local id = fields[index].id
        if id ~= nil then
          local hex = string.lower(tostring(id))
          if string.sub(hex, 1, 2) == "0x" then hex = string.sub(hex, 3) end
          while string.len(hex) < 8 do hex = "0" .. hex end
          set["0x" .. hex] = true
          order[index] = "0x" .. hex
        end
      end
      return true
    end)
    if not ok or not complete then return nil, nil end
    return set, order
  end

  function Identity:declared_fields(type_hash, call_string)
    local known = self.type_fields[type_hash]
    if known ~= nil then return known end
    local set = Core.declaration(self.counters, call_string) or {}
    self.type_fields[type_hash] = set
    self.counters.type_field_reads = self.counters.type_field_reads + 1
    return set
  end

  function Identity:read_field(session, object_type, goid, field_row, call_string)
    if type(field_row) ~= "table" or type(field_row.call) ~= "string" then
      return nil, "no-authored-field"
    end
    if call_string == nil then
      call_string = Core.call_of(self.authored, object_type)
    end
    if type(call_string) ~= "string" then return nil, "no-call-for-type" end
    if self:declared_fields(object_type, call_string)[field_row.hash or ""]
       ~= true then
      return nil, "type-declares-no-field"
    end
    return call(self.counters, GS.game_object_field, session, goid,
                field_row.call), nil
  end

  function Identity:bound_elsewhere(session, row, call_string)
    local value, why = self:read_field(session, row.type, row.goid,
                                       self.authored.bind_field, call_string)
    if why ~= nil or type(value) ~= "number" then return false end
    self.counters.bind_reads = self.counters.bind_reads + 1
    if value == NO_OBJECT then return false end
    self.counters.bound_elsewhere = self.counters.bound_elsewhere + 1
    return true, value
  end

  function Identity:carry_value(session, row, call_string)
    local value, why = self:read_field(session, row.type, row.goid, self.carry,
                                       call_string)
    if why == "no-authored-field" then return nil, "no-authored-carry-field" end
    if why == "type-declares-no-field" then
      self.counters.mask_undeclared = self.counters.mask_undeclared + 1
      return nil, "type-does-not-declare-it"
    end
    if why ~= nil then return nil, why end
    if type(value) ~= "number" then
      self.counters.mask_unreadable = self.counters.mask_unreadable + 1
      return nil, "unreadable"
    end
    self.counters.mask_reads = self.counters.mask_reads + 1
    return value
  end

  function Identity:hand_on_body(session, row, call_string)
    local bound, target = self:bound_elsewhere(session, row, call_string)
    if bound then
      self.counters.hand_gate_bound =
        self.counters.hand_gate_bound + 1
      return false, "bound-to:" .. tostring(target)
    end
    local value = self:carry_value(session, row, call_string)
    if value == nil then return true, "no-carry-value" end
    if value % 2 == 1 then
      self.counters.hand_gate_off_body =
        self.counters.hand_gate_off_body + 1
      return false, "not-on-my-body:" .. tostring(value), value
    end
    return true, "on-body", value
  end

  function Identity:on_my_body(session, row, call_string)
    local bound, target = self:bound_elsewhere(session, row, call_string)
    if bound then return false, "bound-to:" .. tostring(target) end
    local value, why = self:carry_value(session, row, call_string)
    if value == nil then
      if why == "unreadable" then return false, why end
      return true, why
    end
    if value % 4 == 0 then return true, "on-body", value end
    return false, "carry=" .. tostring(value), value
  end


  function Identity:player_object(session, rows)
    local known = self.player_goid
    if known ~= nil then
      local still = call(self.counters, GS.game_object_is_type,
                         session, known, self.player.call)
      if still == true then
        self.counters.player_cached = self.counters.player_cached + 1
        return { goid = known, type = self.player.type }, 1
      end
      self.player_goid = nil
    end
    local player, count = nil, 0
    for index = 1, #(rows or {}) do
      if rows[index].type == self.player.type then
        player = rows[index]
        count = count + 1
      end
    end
    if count == 1 then self.player_goid = player.goid end
    return player, count
  end

  function Identity:squad(session, my_peer)
    if self.seats == 0 then return nil end
    if session == nil or not callable(GS, "peers") then return nil end
    if self.player.type == nil then return nil end
    local peers = call(self.counters, GS.peers, session)
    if type(peers) ~= "table" then return nil end
    local parts = {}
    for index = 1, #peers do parts[index] = tostring(peers[index]) end
    local mark = table.concat(parts, ",")
    local memo = self.squad_memo
    if memo == nil or memo.mark ~= mark then
      memo = { mark = mark, mine = my_peer, who = {}, found = {}, rows = {} }
      for index = 1, #peers do
        if peers[index] ~= my_peer then
          memo.who[#memo.who + 1] = peers[index]
        end
      end
      self.squad_memo = memo
      self.counters.squad_scans = self.counters.squad_scans + 1
    else
      self.counters.squad_cached = self.counters.squad_cached + 1
    end
    for at = 1, #memo.who do
      if memo.found[at] == nil then
        local owned = self:owned_objects(session, memo.who[at], nil)
        local seen = nil
        for row = 1, #(owned or {}) do
          if owned[row].type == self.player.type then
            seen = { goid = owned[row].goid, type = self.player.type,
                     peer = memo.who[at] }
          end
        end
        if seen ~= nil then
          memo.found[at] = seen
        else
          self.counters.squad_pending = self.counters.squad_pending + 1
        end
      end
    end
    for seat = 1, self.seats do
      if memo.found[seat] ~= nil then
        memo.rows[seat] = memo.found[seat]
      elseif seat <= #memo.who then
        memo.rows[seat] = PENDING
      else
        memo.rows[seat] = false
      end
    end
    return memo.rows
  end

  function Identity:avatar_from(session, player)
    local goid, why = self:read_field(session, player.type, player.goid,
                                      self.player.avatar_field, self.player.call)
    if why == "no-authored-field" then
      return nil, "no-authored-player-field"
    end
    if why == "type-declares-no-field" then
      return nil, "player-does-not-declare-the-field"
    end
    if why ~= nil then return nil, why end
    if type(goid) ~= "number" then return nil, "player-field-unreadable" end
    if self.avatar_goid ~= goid then
      self:reset()
      self.avatar_goid = goid
      self.player_goid = player.goid
    end
    if goid == NO_OBJECT then return nil, NO_AVATAR_NOW end
    return goid, nil
  end

  function Identity:in_control(session, avatar)
    return self:avatar_value(session, avatar, self.avatar.motion_field)
  end

  function Identity:avatar_value(session, avatar, spot)
    local value, why = self:read_field(session, avatar.type, avatar.goid, spot,
                                       self.avatar.call)
    if why ~= nil then return nil end
    return value
  end

  function Identity:on_ship(session, avatar)
    local spot = self.avatar.ship_field
    if spot == nil then return false end
    local memo = self.ship_memo
    if memo ~= nil and memo.goid == avatar.goid then return memo.aboard end
    local value = self:avatar_value(session, avatar, spot)
    if value == nil then return false end
    local aboard = value == spot.value
    self.ship_memo = { goid = avatar.goid, aboard = aboard }
    return aboard
  end

  function Identity:rotation_free(session, avatar)
    return self:avatar_value(session, avatar, self.avatar.rotation_field)
  end

  local function marks(list)
    local out = {}
    for index = 1, #list do
      if index > 6 then
        out[#out + 1] = "+" .. tostring(#list - 6) .. "-more"
        break
      end
      out[#out + 1] = tostring(list[index].type) .. ":" ..
                      tostring(list[index].goid) ..
                      ":mask=" .. tostring(list[index].mask)
    end
    return table.concat(out, ",")
  end

  function Identity:on_body_split(session, rows, pick, test)
    local kept, dropped, all = {}, {}, {}
    for index = 1, #rows do
      local candidate, call_string = pick(rows[index])
      if candidate ~= nil then
        all[#all + 1] = candidate
        local keep, _why, mask = test(self, session, candidate, call_string)
        candidate.mask = mask
        local into = keep and kept or dropped
        into[#into + 1] = candidate
      end
    end
    return kept, dropped, all
  end

  function Identity:find_backpack(session, rows)
    local kept, _dropped, owned = self:on_body_split(session, rows,
      function(row)
        local pack = self.backpacks[row.type]
        if pack == nil then return nil end
        return { goid = row.goid, type = row.type, call = pack.call }, pack.call
      end, Identity.on_my_body)
    if #owned == 0 then return nil, "no-owned-backpack" end
    if #kept == 1 then
      return kept[1], ((#owned == 1) and "sole-owned-backpack-on-my-body"
                        or "carry-bit-broke-the-tie") ..
                      " owned=" .. marks(owned)
    end
    if #kept == 0 then
      return nil, "owned-backpacks=" .. tostring(#owned) ..
                  " none-on-my-body tied=" .. marks(owned)
    end
    local pool = (#kept > 1) and kept or owned
    return nil, "owned-backpacks=" .. tostring(#owned) ..
                " on-body=" .. tostring(#kept) ..
                " tied=" .. marks(pool)
  end

  local function reason_head(reason)
    return type(reason) == "string" and reason:match("^[%a%-]+") or nil
  end


  local function seat_rows(into, rows)
    for seat = 1, #(rows or {}) do
      into["squad_" .. tostring(seat)] = rows[seat]
    end
    return into
  end

  local function empty_hand(status, reason, found)
    found = found or {}
    local hand = nil
    if status == ABSENT then hand = false end
    return seat_rows({
      status = status, avatar = found.avatar, hand_weapon = hand,
      backpack = found.backpack, player = found.player, reason = reason,
      grip = found.grip,
      backpack_reason = found.backpack_reason or "not-resolved",
    }, found.squad)
  end

  local function tally(self, prefix, reason)
    local head = reason_head(reason)
    if head == nil then return end
    local key = prefix .. head:gsub("%-", "_")
    self.counters[key] = (self.counters[key] or 0) + 1
  end

  local function unknown(self, reason, found)
    self.counters.unknowns = self.counters.unknowns + 1
    tally(self, "unknown_", reason)
    return empty_hand(UNRESOLVED, reason, found)
  end

  local function absent(self, reason, found)
    self.counters.absents = self.counters.absents + 1
    tally(self, "absent_", reason)
    return empty_hand(ABSENT, reason, found)
  end

  function Identity:authored_read(session, object, row)
    if object == nil or object.goid == nil then return nil, "no-object" end
    local value, why = self:read_field(session, object.type, object.goid, row)
    if why ~= nil then return nil, why end
    if type(value) ~= "number" then return nil, "unreadable" end
    return value
  end

  function Identity:mode_is_underbarrel(session, hand)
    local value = self:authored_read(session, hand, self.authored.mode_field)
    return value ~= nil and math.floor(value / 8) % 2 == 1
  end

  local FOLLOW_WORDS = {
    underbarrel = {
      parent = "no-object", empty = "no-authored-field",
      none = "no-underbarrel", gone = "underbarrel-gone",
      silent = "weapon-declares-no-link",
      named = "weapon-points-at-it",
      unnamed = "weapon-points-at-an-unnamed-object",
    },
    pack_link = {
      parent = "no-backpack", empty = "no-authored-link-field",
      none = "no-link", gone = "link-gone",
      silent = "backpack-declares-no-link",
      named = "backpack-points-at-it",
      unnamed = "backpack-points-at-an-unnamed-object",
    },
  }

  function Identity:linked_read(session, object, row)
    if object == nil or object.goid == nil then return nil, "no-object" end
    local value, why = self:read_field(session, object.type, object.goid, row)
    if why ~= nil then return nil, why end
    if type(value) == "table" then
      if value[2] ~= nil then return nil, "link-array-has-many" end
      value = value[1]
    end
    if type(value) ~= "number" then return nil, "unreadable" end
    return value
  end

  function Identity:reach(session, parent, fields, words, from)
    if parent == nil or parent.goid == nil then return nil, words.parent end
    if fields == nil or #fields == 0 then return nil, words.empty end
    local why = words.silent
    for index = from or 1, #fields do
      local goid, reason = self:linked_read(session, parent, fields[index])
      if goid == nil then
        if reason ~= nil and why == words.silent then why = reason end
      elseif goid == NO_OBJECT then
        return nil, words.none, true
      elseif not self:live(session, goid) then
        return nil, words.gone
      else
        local type_hash = self:type_of(session, goid, nil)
        if type_hash == nil then
          type_hash = self:scan_types(
            session, goid, self.type_missed[goid] or {}, "all", self:all_rows())
        end
        local row = { goid = goid, type = type_hash }
        local deeper, deep_said =
          self:reach(session, row, fields, words, index + 1)
        if deeper ~= nil then return deeper, deep_said, true end
        return row,
               type_hash ~= nil and words.named or words.unnamed, true
      end
    end
    return nil, why
  end

  function Identity:find_underbarrel(session, hand)
    return self:reach(session, hand, { self.authored.underbarrel_field },
                      FOLLOW_WORDS.underbarrel)
  end

  function Identity:find_pack_link(session, pack)
    return self:reach(session, pack, self.authored.pack_link_fields,
                      FOLLOW_WORDS.pack_link)
  end

  function Identity:follow(slot, cached, session, parent, find)
    local key = parent ~= nil and parent.goid or nil
    local memo = self[slot]
    if key ~= nil and memo ~= nil and memo.parent == key then
      self.counters[cached] = self.counters[cached] + 1
      return memo.row, memo.reason
    end
    local row, reason, settled = find(self, session, parent)
    if key ~= nil and settled == true then
      self[slot] = { parent = key, row = row, reason = reason }
    else
      self[slot] = nil
    end
    return row, reason
  end

  function Identity:owned_unchanged(session, my_peer)
    local owned = call(self.counters, GS.objects_owned_by, session, my_peer)
    if type(owned) ~= "table" then return nil, false end
    local known = self.owned_set
    local seen, same = 0, known ~= nil
    for _, goid in pairs(owned) do
      seen = seen + 1
      if same and known[goid] ~= true then same = false end
    end
    if same and seen ~= self.owned_count then same = false end
    return owned, same
  end

  function Identity:remember_owned(owned)
    local set, seen = {}, 0
    for _, goid in pairs(owned) do
      set[goid] = true
      seen = seen + 1
    end
    self.owned_set, self.owned_count = set, seen
  end

  function Identity:still_in_hand(session, grip)
    local saved = self.carried_weapon
    if saved == nil or saved.grip ~= grip or saved.unit == nil then return nil end
    local body = self.local_body
    if body == nil then return nil end
    local row = self.equipment[saved.type]
    if row == nil then return nil end
    local node = row.wield_node or self.equipment_defaults.wield_node
    if node == nil then return nil end
    if call(self.counters, Unit.alive, saved.unit) ~= true then return nil end
    if not self:live(session, saved.goid) then return nil end
    local index = Core.node_of(self.counters, self.node_index, body, node)
    local anchor = Core.node_position(self.counters, body, index)
    if anchor == nil then return nil end
    if not self:at_wield_node(saved.unit, anchor, row) then return nil end
    return saved
  end

  function Identity:still_on_back(session)
    local memo = self.pack_memo
    if memo == nil then return nil, false end
    if memo == false then return nil, true end
    local pack = self.backpacks[memo.type]
    if pack == nil then return nil, false end
    if not self:live(session, memo.goid) then return nil, false end
    if self:on_my_body(session, memo, pack.call) ~= true then return nil, false end
    return memo, true
  end

  function Identity:seal(session, chosen, found, grip, rig, reason)
    local saved = self.carried_weapon or {}
    saved.goid, saved.type, saved.grip = chosen.goid, chosen.type, chosen.grip
    saved.unit = self.hand_unit
    self.carried_weapon = saved
    self.counters.resolves = self.counters.resolves + 1
    local hand = { goid = chosen.goid, type = chosen.type, grip = chosen.grip }
    local underbarrel, underbarrel_reason =
      self:follow("under_memo", "under_cached", session, hand,
                  self.find_underbarrel)
    if underbarrel ~= nil and underbarrel.goid ~= nil and
       self:mode_is_underbarrel(session, hand) then
      self.counters.mode_took_the_underbarrel =
        self.counters.mode_took_the_underbarrel + 1
      hand = { goid = underbarrel.goid, type = underbarrel.type,
               grip = hand.grip, mask = hand.mask, was = chosen.type }
    end
    local pack_link, pack_link_reason =
      self:follow("link_memo", "link_cached", session, found.backpack,
                  self.find_pack_link)
    local sealed = {
      status = "resolved",
      player = found.player,
      pack_link = pack_link,
      pack_link_reason = pack_link_reason,
      grip = grip,
      avatar = found.avatar,
      underbarrel = underbarrel,
      underbarrel_reason = underbarrel_reason,
      hand_weapon = hand,
      backpack = found.backpack,
      reason = reason,
      backpack_reason = found.backpack_reason,
    }
    return seat_rows(sealed, found.squad), nil, rig
  end

  function Identity:resolve(session, world, my_peer)
    self.hand_unit = nil
    self.last_candidates = nil
    self.avatar_state, self.avatar_state_read = nil, false
    self:sync(session, world, my_peer)
    if session == nil or world == nil or my_peer == nil then
      return unknown(self, "no-session-world-or-peer")
    end
    local missing = surface_missing()
    if missing ~= nil then
      return unknown(self, "surface-missing:" .. missing)
    end

    local player, players = self:player_object(session, nil)
    if player == nil then
      local rows = self:owned_objects(session, my_peer, nil)
      if rows == nil then return unknown(self, "owned-objects-unreadable") end
      player, players = self:player_object(session, rows)
    end
    if players ~= 1 then
      return unknown(self, "owned-players=" .. tostring(players))
    end

    local avatar_goid, avatar_reason = self:avatar_from(session, player)
    local found = {
      player = { goid = player.goid, type = self.player.type },
      avatar = avatar_goid ~= nil
        and { goid = avatar_goid, type = self.avatar.type } or nil,
      squad = self:squad(session, my_peer),
    }
    if found.avatar == nil then
      local hand = (avatar_reason == NO_AVATAR_NOW) and absent or unknown
      return hand(self, "no-avatar:" .. tostring(avatar_reason), found)
    end

    if self:on_ship(session, found.avatar) then
      self.counters.aboard = self.counters.aboard + 1
      return { status = "aboard", reason = "the-avatar-is-the-ship-avatar" }
    end

    local in_control = self:in_control(session, found.avatar)
    if in_control ~= false then self.controlled_once = true end
    self:bind_body(session, world, found.avatar, in_control)

    local rig = self.local_body
    local grip, grip_reason = self:current_grip(rig)
    found.grip = grip
    if grip ~= nil and self.carried_weapon ~= nil and
       grip ~= self.carried_weapon.grip then self.carried_weapon = nil end

    local steering = self:rotation_free(session, found.avatar)
    if in_control == false then
      if steering ~= false then
        return absent(self, "avatar-not-in-control", found), found
      end
      self.counters.gate_open_seated =
        self.counters.gate_open_seated + 1
    elseif steering == false then
      return absent(self, "rotation-locked", found), found
    end

    if grip == nil then
      if self.avatar_state == AVATAR_DEAD then
        return absent(self, "avatar-dead", found)
      end
      return unknown(self, "no-grip:" .. tostring(grip_reason), found)
    end
    if grip == 0 then
      return absent(self, "grip=0-nothing-held", found)
    end

    local owned, unchanged = self:owned_unchanged(session, my_peer)
    if owned == nil then
      return unknown(self, "owned-objects-unreadable", found)
    end
    local kept = unchanged and self:still_in_hand(session, grip) or nil
    if kept ~= nil then
      local packed, standing = self:still_on_back(session)
      if standing then
        self.counters.fast_hand = self.counters.fast_hand + 1
        self.hand_unit = kept.unit
        self.last_candidates = { { goid = kept.goid, type = kept.type } }
        found.backpack = packed
        found.backpack_reason = (packed ~= nil) and "carried-backpack"
                                or "carried-no-backpack"
        return self:seal(session, kept, found, grip, rig,
                         "hand-still-at-the-wield-node")
      end
    end
    self.counters.fast_break = self.counters.fast_break + 1
    self:remember_owned(owned)

    local rows = self:owned_objects(session, my_peer, grip, owned)
    if rows == nil then
      return unknown(self, "owned-objects-unreadable", found)
    end

    local backpack, backpack_reason = self:find_backpack(session, rows)
    found.backpack, found.backpack_reason = backpack, backpack_reason
    self.pack_memo = backpack or false

    local candidates, dropped, of_grip = self:on_body_split(session, rows,
      function(row)
        local equipment = self.equipment[row.type]
        if equipment == nil or not self:in_grip(row.type, grip)
           or equipment.no_hand then return nil end
        return { goid = row.goid, type = row.type, grip = grip },
               equipment.call
      end, Identity.hand_on_body)
    if #candidates == 0 then
      self.carried_weapon = nil
      return absent(self, "no-on-body-object-of-grip=" .. tostring(grip) ..
                          " owned=" .. tostring(#rows) ..
                          " of_grip=" .. tostring(#of_grip) ..
                          " dropped=" .. marks(dropped), found)
    end
    self.last_candidates = candidates
    local kinds, seen_kind, names = 0, {}, {}
    for index = 1, #candidates do
      local kind = candidates[index].type
      if seen_kind[kind] == nil then
        seen_kind[kind] = true
        kinds = kinds + 1
        names[#names + 1] = tostring(kind)
      end
    end
    table.sort(names)
    local kept_kinds = table.concat(names, ",")
    if kinds == 1 then
      self.counters.kinds_one = self.counters.kinds_one + 1
    else
      self.counters.kinds_many = self.counters.kinds_many + 1
    end
    local wield, held
    held, wield = self:narrow_by_wield(world, candidates)
    if #held == 0 then
      held = self:carried_hand(candidates)
      wield = (#held > 0) and "carried" or wield
    end
    if #held == 0 then
      if wield == "nothing-at-the-wield-node" then
        self.counters.wield_no_match =
          self.counters.wield_no_match + 1
        if self.left_hand_grips[grip] == true then
          return absent(self, "carry-empties-the-hand grip=" .. tostring(grip),
                        found)
        end
      end
      return unknown(self, "hand-empty:" .. tostring(wield) ..
                           " kinds=" .. tostring(kinds) .. ":" .. kept_kinds ..
                           " objs=" .. tostring(#candidates) ..
                           " grip=" .. tostring(grip) ..
                           " dropped=" .. marks(dropped), found)
    end
    candidates = held
    if #candidates > 1 then
      local on_body = {}
      for index = 1, #candidates do
        local mask = candidates[index].mask
        if type(mask) == "number" and mask % 4 == 0 then
          on_body[#on_body + 1] = candidates[index]
        end
      end
      if #on_body == 1 then
        self.counters.mask_broke_the_tie =
          self.counters.mask_broke_the_tie + 1
        candidates = on_body
      end
    end
    if #candidates > 1 then
      return unknown(self, "on-body-objects=" .. tostring(#candidates) ..
                           " kinds=" .. tostring(kinds) .. ":" .. kept_kinds ..
                           " grip=" .. tostring(grip) ..
                           " wield=" .. tostring(wield) ..
                           " tied=" .. marks(candidates), found)
    end

    return self:seal(session, candidates[1], found, grip, rig,
                     "wield-node-named-the-hand:" .. tostring(wield) ..
                     " kinds=" .. tostring(kinds) .. ":" .. kept_kinds ..
                     " mask=" .. tostring(candidates[1].mask) ..
                     ((#dropped > 0) and (" dropped=" .. marks(dropped)) or ""))
  end


  function Identity:observation()
    local types, candidates, seats = {}, {}, {}
    for goid, hash in pairs(self.object_type) do types[goid] = hash end
    for index, row in ipairs(self.last_candidates or {}) do
      candidates[index] = { goid = row.goid, type = row.type }
    end
    local memo = self.squad_memo
    local rows = memo ~= nil and memo.rows or {}
    for seat = 1, #rows do
      local row = rows[seat]
      if type(row) ~= "table" then
        seats[seat] = { index = seat, state = "no-seat" }
      elseif row.goid == nil then
        seats[seat] = { index = seat, state = "pending",
                        peer = (memo.who or {})[seat] }
      else
        seats[seat] = { goid = row.goid, type = row.type, state = "seated",
                        peer = row.peer }
      end
    end
    return {
      object_type = types, last_candidates = candidates, squad = seats,
      squad_mine = memo ~= nil and memo.mine or nil,
      hand_unit = self.hand_unit, player_goid = self.player_goid,
      carried_goid = self.carried_weapon and self.carried_weapon.goid,
      local_body = self.local_body,
      avatar_state = self.avatar_state, avatar_state_read = self.avatar_state_read,
      body_binding = { status = self.body_binding.status,
        distance = self.body_binding.distance,
        candidates = self.body_binding.candidates },
      owned_seen = self.counters.owned_seen,
    }
  end

  function Identity:report()
    local out = EngineCall.counters_of(self.counters)
    out.cached_types = 0
    for _ in pairs(self.type_fields) do
      out.cached_types = out.cached_types + 1
    end
    return out
  end

  return Core
end)()
