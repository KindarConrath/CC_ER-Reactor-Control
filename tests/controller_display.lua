dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local Display=require('lib.display')
local attached={}
local function monitor()
  local monitor={};for key,value in pairs(term) do monitor[key]=value end
  local original=monitor.blit
  monitor.blit=function(...)
    local present=false;for _,value in pairs(attached) do if value==monitor then present=true end end
    assert(present,'rendered to detached monitor');return original(...)
  end
  return monitor
end
peripheral.getNames=function() local names={};for peripheralName in pairs(attached) do names[#names+1]=peripheralName end;return names end
peripheral.hasType=function(peripheralName,kind) return attached[peripheralName]~=nil and kind=='monitor' end
peripheral.wrap=function(peripheralName) return attached[peripheralName] end
peripheral.getName=function(monitor) for peripheralName,value in pairs(attached) do if value==monitor then return peripheralName end end;error('not a monitor') end
peripheral.getType=function(monitor) peripheral.getName(monitor);return 'monitor' end
local testConfig=dofile('config.lua');testConfig.calibration={};testConfig.storage={'demo/battery'}
local backend=require('lib.demo').new(true)
local app=require('lib.app').new(testConfig,backend,'.',true)
app.enqueue('mode',nil,'auto');app.tick();assert(app.mode=='auto')
local control=app.control
local selectDisplay=Display.controller(testConfig,term)
assert(selectDisplay()==term)
local env=setmetatable({},{__index=_ENV});env._G=env
local basalt=assert(loadfile('vendor/basalt.lua','t',env))()
basalt.getErrorManager().error=function(displayError) error(displayError) end
local ui=require('lib.ui').new(basalt,app,selectDisplay(),selectDisplay)
ui.refresh();basalt.update('timer',999)
local function event(name,...)
  fakeTime=fakeTime+1;basalt.update(name,...)
  app.tick();ui.refresh();basalt.update('timer',999)
  assert(app.mode=='auto' and app.control==control)
end
local first=monitor();attached.left=first;event('peripheral','left')
assert(basalt.getActiveFrame(first) and not basalt.getActiveFrame(term))
local other=monitor();attached.back=other;event('peripheral','back')
assert(basalt.getActiveFrame(first),'Keep current monitor when another attaches')
attached.left=nil;event('peripheral_detach','left')
assert(basalt.getActiveFrame(other) and not basalt.getActiveFrame(first))
other.getSize=function() return 20,10 end;event('monitor_resize','back')
assert(basalt.getActiveFrame(term))
other.getSize=function() return 51,19 end;event('monitor_resize','back')
assert(basalt.getActiveFrame(other))
attached={};event('peripheral_detach','back');assert(basalt.getActiveFrame(term))
-- Terminal clicks and replacement monitor touches still reach the same app.
basalt.update('mouse_click',1,4,3);basalt.update('mouse_up',1,4,3)
assert(app.queue[1].op=='mode');app.queue={}
local replacement=monitor();attached.monitor_10=replacement;event('peripheral','monitor_10')
basalt.update('monitor_touch','monitor_10',4,3)
assert(app.queue[1].op=='mode');app.queue={}
testConfig.controllerDisplay.mode='terminal';ui.refresh();assert(basalt.getActiveFrame(term))
testConfig.controllerDisplay.mode='auto';ui.refresh();assert(basalt.getActiveFrame(replacement))
print('PASS controller live display fallback, replacement, resize, input and uninterrupted Auto state')
