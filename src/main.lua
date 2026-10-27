
local function poll(now)
  Model.sample()
  if not S.avatar or not Model.ready then return end
  if identity.avatar_state==2 then return end
  sample_health()
  sample_stamina()
  sample_consumables()
end
local function update(dt)
  if S.stopped then return end
  local step=Fix.finite(dt) and dt or 1/60
  step=math.max(0,math.min(0.25,step))
  S.dt,S.clock=step,S.clock+step
  if S.options_dirty or S.clock>=(S.option_at or 0) then
    refresh_options();S.options_dirty=false;S.option_at=S.clock+0.5
  end
  local mission=in_mission()
  local world=type(chef.world)=="function" and chef.world() or nil
  local world_id=type(chef.world_id)=="function" and chef.world_id() or world
  if not mission or world==nil then
    if S.mission~=false then Model.reset();Native.reset() end
    S.mission=false;return
  end
  if S.world~=world or S.world_id~=world_id or S.mission~=true then
    Model.reset();Native.reset()
    S.world,S.world_id,S.mission=world,world_id,true
    S.next_poll=0
  end
  if S.clock+1e-8>=S.next_poll then
    S.next_poll=S.clock+0.05
    local session,peer=gcall(get_session),gcall(get_peer)
    if session~=S.session or peer~=S.peer then
      Model.reset();Native.reset();S.session,S.peer=session,peer
    end
    if session==nil or peer==nil then Model.reset();return end
    local ok,err=pcall(poll,S.clock)
    if not ok then
      Model.reset()
      if S.poll_error_logged~=tostring(err) then S.poll_error_logged=tostring(err);logf("poll error: "..tostring(err)) end
      return
    end
  end
  -- No native calls here: original thermal/charge/idle model uses cached inputs
  -- between polls, making the rings frame-smooth without repeating discovery.
  if Model.ready and S.clock-(Model.sample_at or -1e9)<=0.3 then
    local ok,err=pcall(Model.build)
    if not ok then
      Model.window=nil;Native.clear(Model.commands)
      if S.model_error~=tostring(err) then S.model_error=tostring(err);logf("model error: "..tostring(err)) end
    end
  else Model.window=nil;Native.clear(Model.commands) end
end
local function shutdown()
  if S.stopped then return end
  S.stopped=true
  -- Chef owns every GUI. Never destroy a handle after a world is gone.
  Model.reset();Native.reset()
end
logf("HUD Lite "..VERSION.." by Alpha F. Bloodfallen; bounded 20Hz discovery")
logf("reload: weapon rig or declared stage gates BODY animation layer 11; full state returns; Chef skips retained")
return {version=VERSION,installed=true,update=update,render=render,shutdown=shutdown}
