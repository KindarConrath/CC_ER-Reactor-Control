dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local Display=require('lib.display')
local attached={}
local function monitor()
  local m={};for k,v in pairs(term) do m[k]=v end
  local original=m.blit
  m.blit=function(...)
    local present=false;for _,v in pairs(attached) do if v==m then present=true end end
    assert(present,'rendered to detached monitor');return original(...)
  end
  return m
end
peripheral.getNames=function() local names={};for n in pairs(attached) do names[#names+1]=n end;return names end
peripheral.hasType=function(n,kind) return attached[n]~=nil and kind=='monitor' end
peripheral.wrap=function(n) return attached[n] end
peripheral.getName=function(m) for n,v in pairs(attached) do if v==m then return n end end;error('not a monitor') end
peripheral.getType=function(m) peripheral.getName(m);return 'monitor' end
local c=dofile('config.lua');c.calibration={};c.storage={'demo/battery'}
local backend=require('lib.demo').new(true)
local app=require('lib.app').new(c,backend,'.',true)
app.enqueue('mode',nil,'auto');app.tick();assert(app.mode=='auto')
local control=app.control
local selectDisplay=Display.controller(c,term)
assert(selectDisplay()==term)
local env=setmetatable({},{__index=_ENV});env._G=env
local basalt=assert(loadfile('vendor/basalt.lua','t',env))()
basalt.getErrorManager().error=function(e) error(e) end
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
c.controllerDisplay.mode='terminal';ui.refresh();assert(basalt.getActiveFrame(term))
c.controllerDisplay.mode='auto';ui.refresh();assert(basalt.getActiveFrame(replacement))
print('PASS controller live display fallback, replacement, resize, input and uninterrupted Auto state')
