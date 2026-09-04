dofile('tests/cc_stub.lua')
package.path='./?.lua;'..package.path
local Companion=require('lib.companion')
local Settings=require('lib.settings')
local c=dofile('config.lua');c.companionDisplay={mode='auto'}
local writes=0
local broken=false
local device={kind='storage',name='bottom',label='bottom',online=true,energy=70,capacity=100}
local devices={poll=function() if broken then error('read failed') end;return {device} end,
  write=function() writes=writes+1 end}
local peer=Companion.new(2,c,devices)
assert(not peer.receive(3,{id='x',op='poll'}) and not peer.state.lastContact)
local reply=peer.receive(2,{id='p',op='poll'});assert(reply.ok)
peer.refresh();peer.refresh();assert(writes==0 and #peer.state.devices==1)
assert(peer.receive(2,{id='w',op='write',data={token=reply.data.token,commands={{}}}}).ok)
assert(writes==1,'Display polling invalidated the controller lease')
broken=true;peer.refresh();assert(#peer.state.devices==0 and peer.state.error:find('read failed'))
broken=false;peer.refresh();assert(not peer.state.error)
print('PASS local telemetry is read-only, clears failed reads and preserves command leases')

-- Exercise the actual service and retry worker together with broadcast event delivery.
-- This small scheduler preserves the CC parallel contract: each waiting coroutine gets the event.
parallel={waitForAll=function(...)
  local workers={};for _,f in ipairs({...}) do workers[#workers+1]={co=coroutine.create(f)} end
  local event={}
  while true do
    local alive=0
    for _,w in ipairs(workers) do
      if coroutine.status(w.co)~='dead' then
        if w.filter==nil or event[1]==w.filter then
          local ok,filter=coroutine.resume(w.co,table.unpack(event));assert(ok,filter);w.filter=filter
        end
        if coroutine.status(w.co)~='dead' then alive=alive+1 end
      end
    end
    if alive==0 then return end
    event={coroutine.yield()}
  end
end}
local sent={}
rednet={receive=function() local _,sender,msg=coroutine.yield('rednet_message');return sender,msg end,
 send=function(sender,msg) sent[#sent+1]=msg end}
local attached=false;local launches=0
local service=coroutine.create(function()
  Companion.run(c,peer,function()
    launches=launches+1
    assert(attached,'monitor absent')
    while true do coroutine.yield('peripheral_detach');assert(attached,'monitor removed') end
  end)
end)
local function event(...) local ok,err=coroutine.resume(service,...);assert(ok,err) end
event();assert(launches==1)
event('rednet_message',2,{id='offline-display',op='poll'});assert(sent[#sent].ok)
attached=true;event('timer');assert(launches==2)
attached=false;event('peripheral_detach')
event('rednet_message',2,{id='detached-display',op='poll'});assert(sent[#sent].ok)
attached=true;event('timer');assert(launches==3)
assert(writes==1)
print('PASS missing, detached and reattached display does not stop companion replies')

-- CLI persistence and startup use the real settings/startup modules, without a blocking service.
local originalRun=Companion.run
local selected
Companion.run=function(config) selected=config.companionDisplay end
fs,textutils,files=require('tests.memory_fs').new()
shell={getRunningProgram=function() return 'agent.lua' end}
c=Settings.load('');assert(c.companionDisplay.mode=='auto')
c.controllerDisplay={mode='terminal'};c.lastMode='auto';Settings.save('',c)
local agent=assert(loadfile('agent.lua'))
agent('2','--monitor','left');assert(selected.mode=='auto' and not selected.name)
local saved=Settings.load('');assert(saved.controllerDisplay.mode=='terminal' and saved.lastMode=='auto')
local Startup=require('lib.startup');Startup.enable('','companion',2)
shell.execute=function(path,owner) assert(owner=='2');agent(owner);return true end
Startup.run('');assert(selected.mode=='auto' and not selected.name)
agent('2','--terminal');agent('2');assert(selected.mode=='terminal')
agent('2','--no-display');agent('2');assert(selected.mode=='off')
assert(not pcall(agent,'2','--monitor'));assert(Settings.load('').companionDisplay.mode=='off')
agent('2','--auto-display');assert(selected.mode=='auto')
c=Settings.load('');c.companionDisplay={mode='monitor',name='removed_monitor_0'};Settings.save('',c)
agent('2');assert(selected.mode=='auto' and not selected.name)
Companion.run=originalRun
local served=false
Companion.run({companionDisplay={mode='off'}},{serve=function() served=true end},function() error('UI loaded') end)
assert(served)
print('PASS companion display choices survive startup, preserve main settings and default to automatic detection')

-- No monitor is a normal return, and must still be checked again later.
local attempts=0
local retry=coroutine.create(function()
 Companion.display({companionDisplay={mode='auto'}},peer,function() attempts=attempts+1 end)
end)
assert(coroutine.resume(retry));assert(attempts==1)
assert(coroutine.resume(retry,'timer'));assert(attempts==2)
print('PASS automatic display retries when no monitor was attached at startup')
