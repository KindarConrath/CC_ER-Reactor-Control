package.path='./?.lua;'..package.path
local Settings=require('lib.settings')
local App=require('lib.app')
local memory=require('tests.memory_fs')
os.getComputerID=function() return 42 end
os.epoch=function() return 100000 end
local function fixture()
  fs,textutils=memory.new()
  local c=dofile('config.lua');c.calibration={};c.storage={'demo/battery'}
  local b=require('lib.demo').new(true);b.advance=nil
  local a=App.new(c,b,'.',false)
  a.enqueue('mode',nil,'auto');a.tick();assert(a.mode=='auto')
  return a,b,c
end
local a,b,c=fixture();local writes=#b.writes
local add=a.enqueue('peer','0',true);a.tick()
assert(a.setupResult.request==add and a.setupResult.ok)
assert(c.remotePeers[1]==0 and a.mode=='manual' and not a.pendingResume)
assert(#b.writes==writes and c.storage[1]=='demo/battery')
local saved=Settings.load('.');assert(saved.remotePeers[1]==0 and saved.lastMode=='manual' and not saved.autoSnapshot)
a.tick();a.enqueue('mode',nil,'auto');a.tick();assert(a.mode=='auto')
local snapshot=c.autoSnapshot
local duplicate=a.enqueue('peer','0',true);a.tick()
assert(a.setupResult.request==duplicate and a.setupResult.ok and #c.remotePeers==1)
assert(a.mode=='auto' and c.autoSnapshot==snapshot)
for _,id in ipairs({'bad','-1','1.5','42','1e999'}) do
  a.enqueue('peer',id,true);a.tick()
  assert(not a.setupResult.ok and a.mode=='auto' and #c.remotePeers==1 and c.autoSnapshot==snapshot)
end
local before=c.controllerDisplay
a.enqueue('display',nil,'terminal');a.tick()
assert(c.controllerDisplay.mode=='terminal' and a.mode=='auto' and c.autoSnapshot==snapshot)
assert(Settings.load('.').controllerDisplay.mode=='terminal')
print('PASS peer zero, persistence, duplicate/invalid IDs and display changes preserve the intended mode')

-- A failed save must not change live peers or erase saved Auto.
local open=fs.open
fs.open=function(path,mode) if mode=='w' then return nil end;return open(path,mode) end
a.enqueue('peer',7,true);a.tick()
assert(not a.setupResult.ok and #c.remotePeers==1 and a.mode=='auto' and c.autoSnapshot==snapshot)
fs.open=open
assert(Settings.load('.').lastMode=='auto')
-- Removed peers need not answer; the backend consumes the changed list on its next poll.
local queried={}
b.poll=function()
  queried[#queried+1]=table.concat(c.remotePeers,',')
  return b.devices,#c.remotePeers>0 and {'Peer unavailable'} or {}
end
a.enqueue('peer',0,false);a.tick();assert(a.setupResult.ok and #c.remotePeers==0)
a.tick();assert(queried[#queried]=='' and c.lastMode=='manual')
assert(Settings.load('.').storage[1]=='demo/battery')
print('PASS failed saves retain previous settings and unreachable peers can be removed')

-- An Auto click queued with an edit cannot accept the pre-edit plant.
a,b,c=fixture();writes=#b.writes
a.enqueue('peer',7,true);a.enqueue('mode',nil,'auto');a.tick()
assert(a.mode=='manual' and #b.writes==writes and not c.autoSnapshot)
-- Stop applies even when a settings operation is pending; its UI receives a result.
a,b,c=fixture();a.enqueue('stop');local pending=a.enqueue('peer',7,true);a.tick()
assert(not b.devices[1].active and a.mode=='manual')
assert(a.setupResult.request==pending and not a.setupResult.ok and #c.remotePeers==0)
a,b,c=fixture();a.enqueue('peer',7,true);a.enqueue('stop');a.tick()
assert(not b.devices[1].active and a.mode=='manual' and c.remotePeers[1]==7)
print('PASS peer edits reject same-batch Auto and pending setup cannot prevent Stop')
