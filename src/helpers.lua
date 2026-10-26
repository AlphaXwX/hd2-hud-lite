-- Small helpers shared by the frame loop.
local function in_mission()
  if type(chef.in_mission) == "function" then
    local ok, v = pcall(chef.in_mission)
    if ok and type(v) == "boolean" then return v end
  end
  return true
end
