dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local c=dofile('config.lua');c.calibration={};c.storage={'demo/battery'}
local backend=require('lib.demo').new(true)
local app=require('lib.app').new(c,backend,'.',true);app.tick()
local env=setmetatable({},{__index=_ENV});env._G=env
local basalt=assert(loadfile('vendor/basalt.lua','t',env))()
basalt.getErrorManager().error=function(e) error(e) end
local ui=require('lib.ui').new(basalt,app,term)
local function render() fakeTime=fakeTime+1;ui.refresh();basalt.update('timer',999) end
local function click(text)
  local p=assert(ui.buttons[text],text)
  basalt.update('mouse_click',1,p.x+1,p.y);basalt.update('mouse_up',1,p.x+1,p.y)
  render()
end
local function settle() app.tick();render() end
render();click('Setup')
assert(ui.buttons.Back and ui.buttons.Peers and ui.buttons.Display and not ui.buttons.Reactors)
basalt.update('mouse_click',1,12,14);basalt.update('mouse_up',1,12,14)
basalt.update('char','0')
local field=ui.setup.input;settle();assert(ui.setup.input==field and field:getText()=='0')
click('Add peer');assert(c.remotePeers[1]==0 and ui.setup.input:getText()=='' and not ui.setup.pending)
click('Add peer');assert(#c.remotePeers==1 and ui.setup.failed)
click('Remove');assert(#c.remotePeers==0)
ui.setup.input:setText('42');click('Add peer')
assert(#c.remotePeers==0 and ui.setup.failed and ui.setup.input:getText()=='42')
ui.setup.input:setText('17');click('Display');click('Peers');assert(ui.setup.input:getText()=='17')
for i=1,7 do app.configureSetup('peer',i,true);render() end
assert(ui.buttons.Next);click('Next');click('Remove');assert(#c.remotePeers==6)
term.getSize=function() return 45,19 end;basalt.update('term_resize');render()
for _,p in pairs(ui.buttons) do assert(p.x+p.width-1<=45 and p.y<=19) end
click('Display');click('Computer screen');assert(c.controllerDisplay.mode=='terminal')
click('Automatic monitor');assert(c.controllerDisplay.mode=='auto')
click('Back');assert(not ui.setup and ui.buttons.Setup)
print('PASS actual Basalt Setup input, immediate feedback, validation, removal, pagination and display choices')

local monitor={};for k,v in pairs(term) do monitor[k]=v end
local secondEnv=setmetatable({},{__index=_ENV});secondEnv._G=secondEnv
local second=assert(loadfile('vendor/basalt.lua','t',secondEnv))()
second.getErrorManager().error=function(e) error(e) end
local view=require('lib.ui').new(second,app,monitor);view.refresh()
local function touch(text)
  local p=assert(view.buttons[text]);second.update('monitor_touch','monitor_0',p.x+1,p.y)
end
touch('Setup');second.update('monitor_touch','monitor_0',12,14)
second.update('char','8');touch('Add peer');view.refresh()
assert(c.remotePeers[#c.remotePeers]==8)
print('PASS monitor touch and computer keyboard add a peer through Setup')
