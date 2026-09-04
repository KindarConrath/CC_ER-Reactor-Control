dofile("tests/cc_stub.lua")
package.path="./?.lua;"..package.path
local testConfig=dofile("config.lua"); testConfig.calibration={}; testConfig.storage={"demo/battery"}
local backend=require("lib.demo").new(false)
local app=require("lib.app").new(testConfig,backend,".",true); app.tick()
local env=setmetatable({},{__index=_ENV});env._G=env
local basalt=assert(loadfile("vendor/basalt.lua","t",env))()
basalt.getErrorManager().error=function(e) error(e) end
local ui=require("lib.ui").new(basalt,app,term)
local function render()
  fakeTime=fakeTime+1;ui.refresh();basalt.update("timer",999)
end
local function contains(text)
  for _,row in ipairs(screen) do if row.text:find(text,1,true) then return true end end
  return false
end
render();assert(contains("REACTOR CONTROL"));assert(contains("Stored:"))
-- Real event dispatch, not calling the click callback directly.
basalt.update("mouse_click",1,4,3);basalt.update("mouse_up",1,4,3)
assert(#app.queue==1 and app.queue[1].op=="mode")
app.tick();render();assert(app.mode=="auto" and contains("Mode: AUTO"))
ui.tab="Reactors";render();assert(contains("Rods") and contains("Fuel"))
ui.tab="Turbines";render();assert(contains("RPM:") and contains("Coils"))
ui.tab="Storage";render();assert(contains("Demo battery") and contains("Remove from control"))
-- A selected missing peripheral must be actionable even with no storage connected.
local oldPoll=backend.poll
backend.poll=function()
  local all=oldPoll();local list={}
  for _,device in ipairs(all) do if device.kind~="storage" then list[#list+1]=device end end
  return list,{}
end
app.tick();render()
assert(app.mode=="manual" and contains("Disconnected storage") and contains("Remove from control"))
basalt.update("mouse_click",1,4,14);basalt.update("mouse_up",1,4,14)
app.tick();render()
assert(#testConfig.storage==0 and not app.problem and ui.tab=="Overview" and not ui.buttons.Storage)
assert(not contains("Disconnected storage") and not contains("Remove from control"))
backend.poll=oldPoll;app.tick();ui.tab="Storage";render()
assert(contains("Demo battery") and contains("Use for control"))
-- Waiting for a saved Auto plant must expose an immediate Manual cancellation.
ui.tab="Overview";app.pendingResume=true;app.config.lastMode="auto";render()
assert(contains("Mode: WAIT") and contains("Waiting to restore Auto"))
basalt.update("mouse_click",1,4,3);basalt.update("mouse_up",1,4,3)
assert(app.queue[1].op=="mode" and app.queue[1].value=="manual")
app.tick();render();assert(not app.pendingResume and app.config.lastMode=="manual")
-- Monitor touch path through the actual Basalt BaseFrame event adapter.
local monitor={};for key,value in pairs(term) do monitor[key]=value end
local second=require("lib.ui").new(basalt,app,monitor);second.refresh()
app.queue={};basalt.update("monitor_touch","monitor_0",4,3)
assert(#app.queue==1 and app.queue[1].op=="mode","Monitor touch did not reach mode button")
ui.tab="Overview";render()
uiTest={basalt=basalt,ui=ui,app=app}
print("PASS real Basalt2 rendering, all tabs, mouse and monitor touch")
