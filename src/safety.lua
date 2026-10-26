-- Read-only native-call safety state: reads Chef's own skip/suspect records
-- for this resource and fails closed when that record file is unreadable.
local IdentitySafety={denied={},uncertain=false}
do
  local directory=chef.log_directory
  if type(directory)=="string" and directory~="" then
    local separator=directory:match("[\\/]$") and "" or "/"
    local function read_file(name)
      if type(io)~="table" or type(io.open)~="function" then return nil end
      local ok,body=pcall(function()
        local f=io.open(directory..separator..name,"r")
        if not f then return nil end
        local text=f:read(1048577);f:close()
        if type(text)~="string" or #text>1048576 then return nil end
        return text
      end)
      return ok and body or nil
    end
    local state=read_file("chef_loader_state.txt")
    if state==nil then
      -- Cannot establish protection state: do not retry high-risk batch and
      -- animation reads by accident.
      IdentitySafety.uncertain=true
    else
      for line in state:gmatch("[^\r\n]+") do
        local record=line:match("^skip: (.+)$") or line:match("^suspect: (.+)$")
        if record then
          local owner,call=record:match("^([^|]+)|(.+)$")
          if owner==IDENTITY_CURRENT then IdentitySafety.denied[call]=true end
        end
      end
    end
  end
end
function IdentitySafety.blocked(path,kind)
  if IdentitySafety.denied[path] or (kind and IdentitySafety.denied[path..":"..tostring(kind)]) then return true end
  if IdentitySafety.uncertain then
    return path=="GameSession.game_object_field_batched" or path=="Unit.animation_get_state" or path=="Unit.animation_layer_info"
  end
  return false
end
