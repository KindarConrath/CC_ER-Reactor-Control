dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local UI=require('lib.companion_ui')
local state={id=4,owner=2,devices={},lastContact=nil}
local reactor={name='back',label='back',kind='reactor',online=true,active=true,rods=62.5,
 fuel=2000,waste=20,temperature=450,output=5000,energy=200,capacity=1000}
local turbine={name='turbine_0',label='turbine_0',kind='turbine',online=true,active=true,
 rpm=1796,coils=false,flow=500,flowLimit=510,flowMax=2000,output=12000,energy=600,capacity=1000}
local storage={name='bottom',label='bottom',kind='storage',online=true,energy=70,capacity=100}
local function contains(text)
 for _,row in ipairs(screen) do if row.text:find(text,1,true) then return true end end;return false
end
local function exercise(display,touch)
 local env=setmetatable({},{__index=_ENV});env._G=env
 local basalt=assert(loadfile('vendor/basalt.lua','t',env))()
 basalt.getErrorManager().error=function(e) error(e) end
 state.devices={reactor};state.lastContact=nil
 local ui=UI.new(basalt,state,display)
 local function render() fakeTime=fakeTime+1;ui.refresh();basalt.update('timer',999) end
 local function click(label)
  local b=assert(ui.buttons[label]);
  if touch then basalt.update('monitor_touch','monitor_0',b.x+1,b.y)
  else basalt.update('mouse_click',1,b.x+1,b.y);basalt.update('mouse_up',1,b.x+1,b.y) end
  render()
 end
 render();assert(not ui.buttons.Turbines and not ui.buttons.Storage and ui.buttons.Overview)
 assert(ui.tab=='Reactors' and contains('Rods: 62.5%') and not contains('Controller #'))
 fakeTime=fakeTime+9;render()
 assert(contains('Controller #2') and contains('Waiting for controller'))
 state.devices={reactor,turbine,storage};state.lastContact=fakeTime;render()
 assert(not contains('Controller #') and not contains('Controller contact:'))
 fakeTime=state.lastContact+9;render();assert(not contains('Controller #'))
 render();assert(contains('Controller #2') and contains('Controller contact: 11s ago'))
 state.lastContact=fakeTime;render();assert(not contains('Controller #'))
 click('Turbines');assert(contains('RPM: 1796') and contains('Coils: disengaged') and contains('510.0 mB/t'))
 click('Storage');assert(contains('Stored charge: 70.0%'))
 click('Overview');assert(contains('Reactors: 1') and contains('Turbines: 1') and contains('Local storage: 70.0%'))
 for key in pairs(ui.buttons) do assert(key=='Overview' or key=='Reactors' or key=='Turbines' or key=='Storage') end
 reactor.cooled=true;reactor.steam=1000;reactor.hot=1500;reactor.hotCapacity=5000
 click('Reactors');assert(contains('Steam:') and contains('Steam tank:'))
 state.devices={};render();assert(contains('No local devices') and not contains('Rods:') and ui.tab=='Overview')
 state.devices={storage};local single=UI.new(basalt,state,display);single.refresh();assert(single.tab=='Storage' and not single.buttons.Reactors and not single.buttons.Turbines)
 state.devices={reactor,turbine,storage};local mixed=UI.new(basalt,state,display);mixed.refresh();assert(mixed.tab=='Overview')
end
exercise(term,false)
local monitor={};for k,v in pairs(term) do monitor[k]=v end
exercise(monitor,true)
term.getSize=function() return 23,17 end
monitor.getSize=term.getSize
local compactEnv=setmetatable({},{__index=_ENV});compactEnv._G=compactEnv
local compactBasalt=assert(loadfile('vendor/basalt.lua','t',compactEnv))()
compactBasalt.getErrorManager().error=function(e) error(e) end
state.devices={reactor,turbine,storage};state.lastContact=fakeTime
local compact=UI.new(compactBasalt,state,monitor);compact.refresh();compactBasalt.update('timer',999)
assert(compact.buttons.All and compact.buttons.React and compact.buttons.Turb and compact.buttons.Power)
compact.tab='Reactors';compact.refresh();compactBasalt.update('timer',999)
assert(compact.buttons['<'].y==7 and compact.buttons['<'].height==3 and compact.buttons['>'].height==3)
assert(contains('1/1') and contains('Local / Back') and screen[9].text:sub(7,17)=='Cooled r...')
assert(require('lib.presentation').fitName('Ultimate Energy Cube',11)=='Ult. Cube')
-- Resizing an existing dashboard must resize its drawing area as well as its layout.
for _,columns in ipairs({31,39,45,51,23}) do
 monitor.getSize=function() return columns,19 end
 compactBasalt.update('monitor_resize','monitor_0')
 local text=columns>=45 and 'Storage' or 'Power'
 local tab=compact.buttons.Storage
 assert(screen[5].text:sub(tab.x,tab.x+tab.width-1):find(text,1,true),
   'Clipped storage tab after resize to '..columns)
end
-- Choose labels from the available tab width, including device changes on an
-- existing screen. At 23 columns only all three device categories need shortening.
local function verifyTabLabels(display, touch)
local environment=setmetatable({},{__index=_ENV});environment._G=environment
local compactBasalt=assert(loadfile('vendor/basalt.lua','t',environment))()
compactBasalt.getErrorManager().error=function(e) error(e) end
local compact=UI.new(compactBasalt,state,display)
for _, columns in ipairs({23, 24, 26, 27, 30, 31, 39, 44, 45, 51, 23}) do
 display.getSize=function() return columns,19 end
 for mask=0,7 do
  state.devices={}
  for index,device in ipairs({reactor,turbine,storage}) do
   if math.floor(mask / 2^(index-1)) % 2 == 1 then
    state.devices[#state.devices+1]=device
   end
  end
  compact.refresh();compactBasalt.update('timer',999)
  local labels=columns>=45 and {Overview='Overview',Reactors='Reactors',Turbines='Turbines',Storage='Storage'}
    or {Overview='All',Reactors='Reactor',Turbines='Turbine',Storage='Power'}
  if columns<27 and mask==7 then labels.Reactors='React';labels.Turbines='Turb' end
  local previousEnd=0
  local tabs=require('lib.presentation').tabs(require('lib.presentation').groups(state.devices))
  for _,name in ipairs(tabs) do
   local tab=assert(compact.buttons[name])
   local expected=labels[name]
   assert(compact.buttons[expected]==tab, 'Wrong label for '..name..' at '..columns..' columns, mask '..mask)
   local rendered=screen[5].text:sub(tab.x,tab.x+tab.width-1):match('^%s*(.-)%s*$')
   assert(rendered==expected, 'Clipped tab: '..tostring(rendered)..' instead of '..expected)
   assert(tab.x==previousEnd+2, 'Tabs need a one-cell gap')
   assert(tab.x+tab.width-1<columns, 'Tabs need a right margin')
   assert(tab.width<=10, 'Sparse tabs must not stretch across the screen')
   assert(screen[5].bg:sub(tab.x-1,tab.x-1)=='f', 'Gap must use the background colour')
   previousEnd=tab.x+tab.width-1
   if not touch then
    compactBasalt.update('mouse_click',1,tab.x,tab.y)
    compactBasalt.update('mouse_up',1,tab.x,tab.y)
   else
    compactBasalt.update('monitor_touch','monitor_0',tab.x,tab.y)
   end
   assert(compact.tab==name, 'Tab navigation failed: '..name)
   if touch then
    compactBasalt.update('monitor_touch','monitor_0',tab.x-1,tab.y)
   else
    compactBasalt.update('mouse_click',1,tab.x-1,tab.y)
    compactBasalt.update('mouse_up',1,tab.x-1,tab.y)
   end
   assert(compact.tab==name, 'Tab gap must not be clickable')
  end
  assert(screen[5].bg:sub(previousEnd+1,columns)==string.rep('f',columns-previousEnd),
    'Unused space after tabs must remain background')
 end
end
end
verifyTabLabels(term,false)
verifyTabLabels(monitor,true)
monitor.getSize=function() return 23,19 end
local secondReactor=require('lib.util').copy(reactor);secondReactor.name='front'
state.devices={reactor,secondReactor};compact.tab='Reactors'
compact.refresh();compactBasalt.update('timer',999)
assert(screen[7].text:sub(3,3)==' ' and screen[8].text:sub(3,3)=='<' and screen[9].text:sub(3,3)==' ')
local nextButton=compact.buttons['>'];local arrowColumn=nextButton.x+1
assert(screen[7].text:sub(arrowColumn,arrowColumn)==' ' and screen[8].text:sub(arrowColumn,arrowColumn)=='>' and screen[9].text:sub(arrowColumn,arrowColumn)==' ')
compactBasalt.update('monitor_touch','monitor_0',arrowColumn,9)
assert(compact.index.Reactors==2 and screen[8].text:sub(7,18)=='Local / Fron')
compactBasalt.update('monitor_touch','monitor_0',3,7)
assert(compact.index.Reactors==1 and contains('Local / Back'))
term.getSize=function() return 51,19 end
monitor.getSize=term.getSize
print('PASS 23 x 17 compact peer tabs and three-line device selector')
print('PASS peer tabs resize without clipping and three-row centered arrows navigate')
print('PASS full peer tab labels whenever they fit, all device combinations, mouse and touch')
local c={companionDisplay={mode='auto'},interval=1}
assert(pcall(UI.run,'.',c,{}),'No monitor is normal headless operation')
print('PASS actual Basalt companion telemetry, category selection, mouse and monitor navigation')

-- Discovery accepts direct and wired monitors; stale names, small, monochrome,
-- and disconnected-during-probe candidates must not hide a usable screen.
local attached={}
local small={isColor=function() return true end,getSize=function() return 20,10 end}
local mono={isColor=function() return false end}
local compactMonitor={isColor=function() return true end,getSize=function() return 23,17 end}
peripheral.getNames=function() local names={};for n in pairs(attached) do names[#names+1]=n end;return names end
peripheral.hasType=function(n,kind) return attached[n]~=nil and kind=='monitor' end
peripheral.wrap=function(n) if attached[n]=='broken' then error('detached') end;return attached[n] end
attached={left=monitor};local found,name=UI.findMonitor();assert(found==monitor and name=='left')
attached={monitor_9=monitor};found,name=UI.findMonitor();assert(name=='monitor_9')
attached={a_small=small,b_mono=mono,c_broken='broken',monitor_9=monitor}
found,name=UI.findMonitor();assert(found==monitor and name=='monitor_9')
attached={monitor_9=monitor,left=monitor};found,name=UI.findMonitor();assert(name=='left')
attached={};assert(UI.findMonitor()==nil)
attached={compact=compactMonitor};found,name=UI.findMonitor();assert(found==compactMonitor and name=='compact')
attached={}
print('PASS direct/wired automatic monitor selection, replacement IDs and unsuitable displays')

-- Run the actual Basalt display through startup without a monitor, attachment,
-- detachment and replacement. The outer retry worker must rebuild the display.
local polls=0
local peer={state=state,refresh=function() polls=polls+1 end}
os.pullEventRaw=function() return coroutine.yield() end
local worker=coroutine.create(function() require('lib.companion').display(c,peer,function() UI.run('.',c,peer) end) end)
local function resume(...)
 fakeTime=fakeTime+1
 local ok,err=coroutine.resume(worker,...);assert(ok,err)
end
resume();assert(polls==0)
attached={left=monitor};resume('timer',999);assert(polls==1)
resume('timer',999);assert(polls>=2)
attached={};resume('timer',999)
local previous=polls
attached={monitor_10=monitor};resume('timer',999);assert(polls>previous)
print('PASS actual Basalt automatic display starts after attachment and recovers on replacement')
