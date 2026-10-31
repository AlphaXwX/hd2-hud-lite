-- Chef keeps its own skip/suspect records for this resource and refuses a call
-- that crashed before it reaches the engine. It also refuses a mod that opens
-- its own state file ("the loader's own files are off limits"), so this module
-- keeps no second copy of that guard: it stays as the single hook the native
-- layer asks, and blocks nothing itself. A duplicated guard made the mod block
-- every batched read for the whole session, which hid values the batch carries.
local IdentitySafety={}
function IdentitySafety.blocked(path, kind)
  return false
end
