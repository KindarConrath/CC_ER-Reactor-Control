dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local P=require('lib.presentation')
local c=dofile('config.lua');c.calibration={};c.storage={'demo/battery'}
local b=require('lib.demo').new(true);b.advance=nil;b.devices[1].rods=90
local app=require('lib.app').new(c,b,'.',true);app.tick()
local env=setmetatable({},{__index=_ENV});env._G=env
local basalt=assert(loadfile('vendor/basalt.lua','t',env))()
basalt.getErrorManager().error=function(err) error(err) end
local ui=require('lib.ui').new(basalt,app,term)
local function render() fakeTime=fakeTime+1;ui.refresh();basalt.update('timer',999) end
local function click(name)
 local p=assert(ui.buttons[name],name)
 basalt.update('mouse_click',1,p.x+1,p.y);basalt.update('mouse_up',1,p.x+1,p.y)
end
local function contains(text)
 for _,row in ipairs(screen) do if row.text:find(text,1,true) then return true end end;return false
end
render();assert(not ui.buttons.Turbines and not contains('Turbines:'))
click('Reactors')
assert(contains('1/2') and contains('Local / Port reactor1') and contains('Demo reactor 1'))
assert(ui.buttons['<'].y==7 and ui.buttons['<'].height==3 and ui.buttons['>'].height==3)
assert(screen[7].text:sub(3,3)==' ' and screen[8].text:sub(3,3)=='<' and screen[9].text:sub(3,3)==' ')
local arrowColumn=ui.buttons['>'].x+1
assert(screen[7].text:sub(arrowColumn,arrowColumn)==' ' and screen[8].text:sub(arrowColumn,arrowColumn)=='>' and screen[9].text:sub(arrowColumn,arrowColumn)==' ')
assert(ui.buttons.Rename.x+ui.buttons.Rename.width<=ui.buttons['>'].x)
click('0%');assert(#app.queue==0 and contains('Rod target: 0%'))
click('Apply');assert(#app.queue==1 and app.queue[1].value==0 and #b.writes==0)
app.tick();app.tick();render();assert(b.devices[1].rods==0 and not ui.rodDrafts[b.devices[1].id].requested)
click('100%');for _=1,4 do click('-5') end;click('-1')
assert(contains('Rod target: 79%') and b.devices[1].rods==0)
render();assert(contains('Rod target: 79%'))
click('Apply');click('+1');click('Apply');assert(#app.queue==1 and app.queue[1].value==80)
click('>');click('25%');click('Apply')
assert(#app.queue==2 and app.queue[2].id==b.devices[2].id and app.queue[2].value==25)
app.tick();assert(b.devices[1].rods==80 and b.devices[2].rods==25)
app.tick();render()
click('0%');click('-5');assert(ui.rodDrafts[b.devices[2].id].value==0)
click('100%');click('+5');assert(ui.rodDrafts[b.devices[2].id].value==100)
click('Actual');assert(ui.rodDrafts[b.devices[2].id].value==25)
print('PASS passive tabs and immediate, independent rod targets with presets, fine steps and Apply')

-- Renaming uses actual input events and keeps the field across background refreshes.
app.enqueue('mode',nil,'auto');app.tick();render();assert(not ui.buttons.Apply)
local id=app.reactors[2].id;local oldSnapshot=c.autoSnapshot
click('Rename')
basalt.update('mouse_click',1,3,8);basalt.update('mouse_up',1,3,8)
for char in ('Surge reactor'):gmatch('.') do basalt.update('char',char) end
assert(ui.nameInput:getText()=='Surge reactor')
local input=ui.nameInput;app.tick();render();assert(ui.nameInput==input and input:getText()=='Surge reactor')
click('Save name');assert(c.deviceNames[id]=='Surge reactor' and app.mode=='auto' and c.autoSnapshot==oldSnapshot)
assert(contains('Surge reactor') and app.reactors[2].id==id)
click('Rename');click('Automatic');assert(not c.deviceNames[id])
click('Rename');basalt.update('char','X');click('Cancel');assert(not c.deviceNames[id])
app.enqueue('mode',nil,'manual');app.tick();render();assert(ui.buttons.Apply)
print('PASS name input survives polling; rename/reset/cancel preserve IDs and Auto mode')

-- Minimum supported display width keeps every control within the screen.
term.getSize=function() return 45,19 end
basalt.update('term_resize');render()
for _,button in pairs(ui.buttons) do assert(button.x+button.width-1<=45) end
print('PASS rod and naming controls fit the minimum 45-column display')

-- Companion overview contains only present device categories and sums storage by capacity.
local storages={{name='bottom',kind='storage',online=true,energy=50,capacity=100},
 {name='bank_2',kind='storage',online=true,energy=150,capacity=300}}
local lines=table.concat(P.overview(P.groups(storages)),'\n')
assert(lines:find('Local storage: 50.0%%') and not lines:find('Reactor') and not lines:find('Turbine'))
local onlyReactor={{name='back',kind='reactor',online=true,cooled=false,output=500}}
lines=table.concat(P.overview(P.groups(onlyReactor)),'\n')
assert(lines:find('Reactor output') and not lines:find('storage') and not lines:find('steam') and not lines:find('Turbine'))
local onlyTurbine={{name='back',kind='turbine',online=true,output=500}}
lines=table.concat(P.overview(P.groups(onlyTurbine)),'\n')
assert(lines:find('Turbine output') and not lines:find('Reactor') and not lines:find('storage'))
local unavailable={{name='back',kind='reactor',online=false}}
lines=table.concat(P.overview(P.groups(unavailable)),'\n');assert(lines:find('unavailable') and not lines:find('0.0 FE'))
assert(#P.tabs(P.groups({}))==1)
local first={id='peer:4/back',peer=4,name='back',kind='reactor',cooled=false}
local second={id='peer:5/back',peer=5,name='back',kind='reactor',cooled=false}
assert(P.title(first,c)~=P.title(second,c) and P.title(first,c):find('Peer 4 / Back',1,true))
local location,name=P.deviceHeading(first,c)
assert(location=='Peer 4 / Back' and name=='Passive reactor')
local cube={name='bottom',kind='storage',peripheralTypes={'ultimateEnergyCube','energy_storage'}}
assert(P.title(cube,c):find('Ultimate energy cube',1,true))
print('PASS relevant peer summaries, capacity-weighted storage and distinct descriptive device names')
-- Monitor navigation uses the same target editing and keyboard naming controls.
local monitor={};for k,v in pairs(term) do monitor[k]=v end
local monitorEnv=setmetatable({},{__index=_ENV});monitorEnv._G=monitorEnv
local monitorBasalt=assert(loadfile('vendor/basalt.lua','t',monitorEnv))()
monitorBasalt.getErrorManager().error=function(err) error(err) end
local monitorUI=require('lib.ui').new(monitorBasalt,app,monitor)
monitorUI.refresh()
local function touch(name)
 local button=assert(monitorUI.buttons[name],name)
 monitorBasalt.update('monitor_touch','monitor_0',button.x+1,button.y)
end
touch('Reactors');touch('50%');touch('-1');touch('-1');touch('Apply')
assert(app.queue[#app.queue].value==48)
touch('Rename');monitorBasalt.update('monitor_touch','monitor_0',3,8)
for char in ('Monitor name'):gmatch('.') do monitorBasalt.update('char',char) end
assert(monitorUI.nameInput:getText()=='Monitor name')
monitorUI.refresh();touch('Save name');assert(c.deviceNames[b.devices[1].id]=='Monitor name')
print('PASS monitor touch rod editing and keyboard naming')
