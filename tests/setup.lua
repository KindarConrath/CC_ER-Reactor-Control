package.path='./?.lua;'..package.path
local Settings=require('lib.settings')
local App=require('lib.app')
local memory=require('tests.memory_fs')
os.getComputerID=function() return 42 end
os.epoch=function() return 100000 end
local function fixture()
  fs,textutils=memory.new()
  local testConfig=dofile('config.lua');testConfig.calibration={};testConfig.storage={'demo/battery'}
  local backend=require('lib.demo').new(true);backend.advance=nil
  local app=App.new(testConfig,backend,'.',false)
  app.enqueue('mode',nil,'auto');app.tick();assert(app.mode=='auto')
  return app,backend,testConfig
end
local app,backend,testConfig=fixture();local writes=#backend.writes
local add=app.enqueue('peer','0',true);app.tick()
assert(app.setupResult.request==add and app.setupResult.ok)
assert(testConfig.remotePeers[1]==0 and app.mode=='manual' and not app.pendingResume)
assert(#backend.writes==writes and testConfig.storage[1]=='demo/battery')
local saved=Settings.load('.');assert(saved.remotePeers[1]==0 and saved.lastMode=='manual' and not saved.autoSnapshot)
app.tick();app.enqueue('mode',nil,'auto');app.tick();assert(app.mode=='auto')
local snapshot=testConfig.autoSnapshot
local duplicate=app.enqueue('peer','0',true);app.tick()
assert(app.setupResult.request==duplicate and app.setupResult.ok and #testConfig.remotePeers==1)
assert(app.mode=='auto' and testConfig.autoSnapshot==snapshot)
for _,id in ipairs({'bad','-1','1.5','42','1e999'}) do
  app.enqueue('peer',id,true);app.tick()
  assert(not app.setupResult.ok and app.mode=='auto' and #testConfig.remotePeers==1 and testConfig.autoSnapshot==snapshot)
end
local before=testConfig.controllerDisplay
app.enqueue('display',nil,'terminal');app.tick()
assert(testConfig.controllerDisplay.mode=='terminal' and app.mode=='auto' and testConfig.autoSnapshot==snapshot)
assert(Settings.load('.').controllerDisplay.mode=='terminal')
print('PASS peer zero, persistence, duplicate/invalid IDs and display changes preserve the intended mode')

-- A failed save must not change live peers or erase saved Auto.
local open=fs.open
fs.open=function(path,mode) if mode=='w' then return nil end;return open(path,mode) end
app.enqueue('peer',7,true);app.tick()
assert(not app.setupResult.ok and #testConfig.remotePeers==1 and app.mode=='auto' and testConfig.autoSnapshot==snapshot)
fs.open=open
assert(Settings.load('.').lastMode=='auto')
-- Removed peers need not answer; the backend consumes the changed list on its next poll.
local queried={}
backend.poll=function()
  queried[#queried+1]=table.concat(testConfig.remotePeers,',')
  return backend.devices,#testConfig.remotePeers>0 and {'Peer unavailable'} or {}
end
app.enqueue('peer',0,false);app.tick();assert(app.setupResult.ok and #testConfig.remotePeers==0)
app.tick();assert(queried[#queried]=='' and testConfig.lastMode=='manual')
assert(Settings.load('.').storage[1]=='demo/battery')
print('PASS failed saves retain previous settings and unreachable peers can be removed')

-- An Auto click queued with an edit cannot accept the pre-edit plant.
app,backend,testConfig=fixture();writes=#backend.writes
app.enqueue('peer',7,true);app.enqueue('mode',nil,'auto');app.tick()
assert(app.mode=='manual' and #backend.writes==writes and not testConfig.autoSnapshot)
-- Stop applies even when a settings operation is pending; its UI receives a result.
app,backend,testConfig=fixture();app.enqueue('stop');local pending=app.enqueue('peer',7,true);app.tick()
assert(not backend.devices[1].active and app.mode=='manual')
assert(app.setupResult.request==pending and not app.setupResult.ok and #testConfig.remotePeers==0)
app,backend,testConfig=fixture();app.enqueue('peer',7,true);app.enqueue('stop');app.tick()
assert(not backend.devices[1].active and app.mode=='manual' and testConfig.remotePeers[1]==7)
print('PASS peer edits reject same-batch Auto and pending setup cannot prevent Stop')
