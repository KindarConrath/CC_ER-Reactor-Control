package.path="./?.lua;"..package.path
local Util=require("lib.util")
local Settings=require("lib.settings")
local Startup=require("lib.startup")
local memory=require("tests.memory_fs")
local clock=100
os.epoch=function() return clock*1000 end
os.getComputerID=function() return 42 end
local App=require("lib.app")
write=function() end
local count=0
local files
local function reset() fs,textutils,files=memory.new() end
local function test(name, callback)
  reset()
  local succeeded, testError = pcall(callback)
  assert(succeeded, name .. ": " .. tostring(testError))
  count = count + 1
  print("PASS " .. name)
end
local function fixture(direct)
  local testConfig=dofile("config.lua");testConfig.calibration={};testConfig.storage={"demo/battery"}
  local backend=require("lib.demo").new(direct);backend.advance=nil
  backend.devices[#backend.devices].energy=backend.devices[#backend.devices].capacity*.4
  return App.new(testConfig,backend,".",false),backend,testConfig
end
local function tick(app) clock=clock+1;app.tick() end
local function enable(app) app.enqueue("mode",nil,"auto");tick(app);assert(app.mode=="auto",app.message) end
local function reboot(backend)
  local testConfig=Settings.load(".");return App.new(testConfig,backend,".",false),testConfig
end
test("saved Auto waits for two ready polls before resuming on a new app",function()
  local app,backend=fixture(true);enable(app);local writeCount=#backend.writes
  app=reboot(backend);assert(app.pendingResume and app.mode=="manual")
  tick(app);assert(app.pendingResume and #backend.writes==writeCount)
  tick(app);assert(app.mode=="auto" and not app.pendingResume and #backend.writes>writeCount)
end)
test("three peers can start in any order without losing saved Auto",function()
  local app,backend,testConfig=fixture(true);testConfig.remotePeers={1,2,3};enable(app)
  local all=Util.copy(backend.devices);local available={}
  backend.poll=function()
    local devices,errors={},{}
    for index=1,3 do
      if available[index] then devices[#devices+1]=Util.copy(all[index]) else errors[#errors+1]="Peer "..index.." unavailable" end
    end
    return devices,errors
  end
  app=reboot(backend);local writeCount=#backend.writes
  for _,index in ipairs({3,1}) do available[index]=true;tick(app);assert(app.pendingResume and #backend.writes==writeCount) end
  assert(Settings.load(".").lastMode=="auto")
  available[2]=true;tick(app);assert(app.mode=="manual")
  available[1]=false;tick(app);assert(app.readyPolls==0)
  available[1]=true;tick(app);assert(app.mode=="manual")
  tick(app);assert(app.mode=="auto" and #backend.writes>writeCount)
end)
test("missing or extra reactors cannot silently change the restored plant",function()
  local app,backend=fixture(true);enable(app);local original=Util.copy(backend.devices)
  app=reboot(backend);table.remove(backend.devices,2);local writeCount=#backend.writes
  for index=1,4 do tick(app) end
  assert(app.pendingResume and #backend.writes==writeCount)
  backend.devices[2]=Util.copy(original[2]);backend.devices[3]=Util.copy(original[3])
  local extra=Util.copy(original[1]);extra.id="different-reactor";extra.name="different-reactor"
  backend.devices[4]=extra;tick(app);assert(app.pendingResume and #backend.writes==writeCount)
  backend.devices[4]=nil;tick(app);tick(app);assert(app.mode=="auto")
end)
test("replacement storage waits; selecting it explicitly cancels saved Auto",function()
  local app,backend=fixture(true);enable(app);backend.devices[3].id="replacement-bank"
  app=reboot(backend);tick(app);assert(app.pendingResume and app.problem)
  app.enqueue("storage","demo/battery");tick(app)
  assert(not app.pendingResume and Settings.load(".").lastMode=="manual")
end)
test("runtime connection loss pauses without erasing restart intent",function()
  local app,backend=fixture(true);enable(app);local oldPoll=backend.poll
  backend.poll=function() return {},{"link lost"} end;tick(app)
  assert(app.mode=="manual" and not app.pendingResume and Settings.load(".").lastMode=="auto")
  local writeCount=#backend.writes;backend.poll=oldPoll;tick(app);assert(app.mode=="manual" and #backend.writes==writeCount)
  app=reboot(backend);tick(app);tick(app);assert(app.mode=="auto")
end)
test("peer outage resumes Auto after two matching polls and clears the error",function()
  local app,backend=fixture(true);enable(app);local oldPoll=backend.poll;local writeCount=#backend.writes
  backend.poll=function() return {},{"Peer #4: no response"},true end
  tick(app);assert(app.pendingResume and app.reconnecting and app.mode=="manual")
  assert(app.problem=="Peer #4: no response; retrying" and #backend.writes==writeCount)
  backend.poll=oldPoll;tick(app);assert(app.readyPolls==1 and #backend.writes==writeCount and not app.problem)
  backend.poll=function() return {},{"Peer #4: no response"},true end
  tick(app);assert(app.readyPolls==0 and #backend.writes==writeCount)
  backend.poll=oldPoll;tick(app);assert(app.pendingResume and #backend.writes==writeCount)
  tick(app);assert(app.mode=="auto" and not app.pendingResume and not app.fault and not app.problem)
  assert(app.message=="Connection restored; Auto resumed" and #backend.writes>writeCount)
end)
test("Manual, Stop and manual rod changes cancel peer recovery",function()
  for _,op in ipairs({"mode","stop","rods"}) do
    local app,backend=fixture(true);enable(app);local oldPoll=backend.poll
    backend.poll=function() return {},{"Peer #4: no response"},true end
    tick(app);assert(app.pendingResume)
    backend.poll=oldPoll
    app.enqueue(op,op=="rods" and backend.devices[1].id or nil,op=="mode" and "manual" or 95)
    tick(app);local writeCount=#backend.writes;tick(app);tick(app)
    assert(app.mode=="manual" and not app.pendingResume and #backend.writes==writeCount)
    assert(Settings.load(".").lastMode=="manual")
  end
end)
test("changed devices and actual errors require review after reconnection",function()
  for _,fault in ipairs({"replacement","device error","peer error"}) do
    local app,backend=fixture(true);enable(app);local oldPoll=backend.poll;local writeCount=#backend.writes
    backend.poll=function() return {},{"Peer #4: no response"},true end
    tick(app);backend.poll=oldPoll
    if fault=="replacement" then backend.devices[1].id="new-reactor"
    elseif fault=="device error" then backend.devices[1].online=false;backend.devices[1].error="Read failed"
    else backend.poll=function() return Util.copy(backend.devices),{"Peer #4: invalid command"},false end end
    tick(app);assert(app.mode=="manual" and not app.pendingResume and app.fault and #backend.writes==writeCount)
  end
end)
test("write timeout recovers from fresh readings; other write failures stay paused",function()
  local app,backend=fixture(true);enable(app);local oldWrite=backend.write;local writeCount=#backend.writes
  rednet={send=function() return false end}
  backend.write=function() require("lib.network").request(4,"write",{},1) end
  tick(app);assert(app.pendingResume and app.problem=="Peer #4: no open modem; retrying")
  backend.write=oldWrite;tick(app);assert(app.pendingResume and #backend.writes==writeCount)
  tick(app);assert(app.mode=="auto" and not app.problem)
  backend.write=function() error("Device rejected control") end
  tick(app);assert(app.mode=="manual" and not app.pendingResume and app.fault)
end)
test("startup read exceptions keep waiting and reset the confirmation count",function()
  local app,backend=fixture(true);enable(app);app=reboot(backend);tick(app)
  local oldPoll=backend.poll;backend.poll=function() error("not attached yet") end;tick(app)
  assert(app.pendingResume and app.readyPolls==0)
  backend.poll=oldPoll;tick(app);assert(app.mode=="manual");tick(app);assert(app.mode=="auto")
end)
test("Manual choice survives reboot and sends no startup commands",function()
  local app,backend=fixture(true);enable(app);app.enqueue("mode",nil,"manual");tick(app)
  local writeCount=#backend.writes;app=reboot(backend);tick(app);tick(app)
  assert(app.mode=="manual" and not app.pendingResume and #backend.writes==writeCount)
end)
test("Mode and manual rod controls can cancel waiting Auto persistently",function()
  for _,op in ipairs({"mode","rods"}) do
    local app,backend=fixture(true);enable(app);app=reboot(backend)
    app.enqueue(op,op=="rods" and backend.devices[1].id or nil,op=="mode" and "manual" or 95);tick(app)
    assert(not app.pendingResume and Settings.load(".").lastMode=="manual")
    if op=="rods" then assert(backend.devices[1].rods==95) end
  end
end)
test("Stop all cancels waiting Auto and remains stopped after reboot",function()
  local app,backend=fixture(true);enable(app);app=reboot(backend);app.enqueue("stop");tick(app)
  assert(backend.devices[1].rods==100 and not backend.devices[1].active)
  local writeCount=#backend.writes;app=reboot(backend);tick(app);tick(app)
  assert(app.mode=="manual" and #backend.writes==writeCount)
end)
test("Stop still reaches hardware if saving the Manual mode fails",function()
  local app,backend=fixture(true);enable(app)
  fs.open=function() return nil end;app.enqueue("stop");tick(app)
  assert(app.mode=="manual" and not backend.devices[1].active and backend.devices[1].rods==100)
  assert(app.message:find("NOT saved"))
end)
test("Auto does not write if its restart snapshot cannot be saved",function()
  local app,backend=fixture(true);fs.open=function() return nil end
  app.enqueue("mode",nil,"auto");tick(app)
  assert(app.mode=="manual" and #backend.writes==0)
end)
test("turbine standby phase survives reboot inside its hysteresis band",function()
  local app,backend,testConfig=fixture(false)
  for index=2,3 do
    local turbine=backend.devices[index]
    turbine.rpm=1796;turbine.coils=true;turbine.active=true
    testConfig.calibration[turbine.id]={rpm=1796,generating={flow=1000,output=40000}}
  end
  local ids={backend.devices[2].id,backend.devices[3].id};table.sort(ids)
  testConfig.calibration._capacity={
    signature="1796|"..ids[1].."=1000.000|"..ids[2].."=1000.000",
    status="passed",required=2000,output=2000,
  }
  local bank=backend.devices[4];bank.energy=bank.capacity*.95;enable(app)
  assert(Settings.load(".").autoStandby)
  bank.energy=bank.capacity*.82;app=reboot(backend);tick(app);tick(app)
  assert(app.mode=="auto" and app.control.standby and not backend.devices[2].coils)
  bank.energy=bank.capacity*.70;tick(app);assert(not Settings.load(".").autoStandby)
  bank.energy=bank.capacity*.82;app=reboot(backend);tick(app);tick(app)
  assert(not app.control.standby and backend.devices[2].coils)
end)
test("Exit preserves saved Auto and does not send a final control batch",function()
  local app,backend=fixture(true);enable(app);local writeCount=#backend.writes;app.enqueue("quit");tick(app)
  assert(not app.running and #backend.writes==writeCount and Settings.load(".").lastMode=="auto")
end)
test("startup saves each role and launches absolute paths with literal arguments",function()
  fs.makeDir("custom build")
  shell={execute=function(...) shell.called={...};return true end}
  Startup.enable("custom build","controller")
  local testConfig,on=Startup.status("custom build");assert(on and testConfig.role=="controller")
  assert(load(files["startup/reactor-control.lua"],"launcher"))()
  assert(shell.called[1]=="/custom build/startup.lua" and shell.called[2]=="run")
  Startup.run("custom build");assert(shell.called[1]=="/custom build/main.lua" and shell.called[2]=="--boot")
  Startup.enable("custom build","companion",0);Startup.run("custom build")
  assert(shell.called[1]=="/custom build/agent.lua" and shell.called[2]=="0")
end)
test("startup enable/disable preserves other scripts and saved control settings",function()
  fs.makeDir("reactor-control");fs.makeDir("startup")
  files["startup.lua"]="OTHER STARTUP";files["startup/other.lua"]="OTHER SCRIPT"
  files["reactor-control/settings.dat"]="EXISTING SETTINGS"
  Startup.enable("reactor-control","controller");Startup.enable("reactor-control","controller")
  Startup.disable("reactor-control")
  assert(not fs.exists("startup/reactor-control.lua"))
  assert(files["startup.lua"]=="OTHER STARTUP" and files["startup/other.lua"]=="OTHER SCRIPT")
  assert(files["reactor-control/settings.dat"]=="EXISTING SETTINGS")
end)
test("startup conflicts and invalid pairing do not overwrite files",function()
  fs.makeDir("reactor-control");fs.makeDir("startup")
  files["startup/reactor-control.lua"]="USER SCRIPT"
  assert(not pcall(Startup.enable,"reactor-control","controller"))
  assert(not pcall(Startup.disable,"reactor-control"))
  assert(files["startup/reactor-control.lua"]=="USER SCRIPT")
  fs.delete("startup/reactor-control.lua")
  assert(not pcall(Startup.enable,"reactor-control","companion",42))
  assert(not fs.exists("reactor-control/startup.dat"))
end)
test("interactive startup setup retains pairing, saved Auto and display settings",function()
  fs.makeDir("reactor-control")
  local app,backend,testConfig=fixture(true);testConfig.companionDisplay="terminal";enable(app)
  files["reactor-control/settings.dat"]=files["settings.dat"]
  local before=files["reactor-control/settings.dat"]
  Startup.enable("reactor-control","companion",0)
  local answers={"",""};read=function() return table.remove(answers,1) end
  local selected=Startup.setup("reactor-control")
  assert(selected.role=="companion" and selected.owner==0 and #answers==0)
  assert(files["reactor-control/settings.dat"]==before)
  answers={"1"};Startup.setup("reactor-control")
  selected=Startup.status("reactor-control")
  assert(selected.role=="controller" and not selected.owner)
  assert(files["reactor-control/settings.dat"]==before)
end)
test("cancelling interactive setup leaves existing startup and settings untouched",function()
  fs.makeDir("reactor-control");Startup.enable("reactor-control","controller")
  local role=files["reactor-control/startup.dat"]
  local launcher=files["startup/reactor-control.lua"]
  read=function() error("Terminated") end
  assert(not pcall(Startup.setup,"reactor-control"))
  assert(files["reactor-control/startup.dat"]==role and files["startup/reactor-control.lua"]==launcher)
end)
test("controller discovers modems which attach after its first poll",function()
  local attached=false;local opened=0
  peripheral={getNames=function() return attached and {"left"} or {} end,
    hasType=function(_,kind) return kind=="modem" end}
  rednet={open=function(side) assert(side=="left");opened=opened+1 end}
  local backend=require("lib.backend").new(dofile("config.lua"))
  backend.poll();assert(opened==0)
  attached=true;backend.poll();assert(opened==1)
end)
test("companion starts without a modem and serves requests after one attaches",function()
  local attached=false;local opened=0;local reply
  peripheral={getNames=function() return attached and {"left"} or {} end,
    hasType=function(_,kind) return kind=="modem" end}
  rednet={open=function() opened=opened+1 end,
    receive=function(_,timeout) assert(timeout==1);return coroutine.yield("waiting") end,
    send=function(owner,msg) assert(owner==7);reply=msg;return true end}
  shell={getRunningProgram=function() return "agent.lua" end}
  local agent=coroutine.create(function() assert(loadfile("agent.lua"))("7","--no-display") end)
  local ok,status=coroutine.resume(agent);assert(ok and status=="waiting" and opened==0)
  attached=true;ok,status=coroutine.resume(agent);assert(ok and opened>0)
  ok,status=coroutine.resume(agent,7,{id="startup-poll",op="poll"})
  assert(ok and status=="waiting" and reply.ok and reply.id=="startup-poll")
end)
test("boot falls back to the computer and restores Auto without waiting for a monitor",function()
  local app,backend,testConfig=fixture(true);testConfig.monitor="missing-display";testConfig.controllerDisplay=nil;enable(app);local writeCount=#backend.writes
  local launched=false
  local computer={getSize=function() return 51,19 end,isColor=function() return true end}
  term={current=function() return computer end}
  peripheral={getNames=function() return {} end,hasType=function() return false end}
  local env=setmetatable({},{__index=_G});env._G=env
  env.shell={getRunningProgram=function() return "main.lua" end}
  env.sleep=function() error("Boot must not wait for the old monitor") end
  env.loadfile=function() return function() return {} end end
  env.require=function(name)
    if name=="lib.network" then return {open=function() end} end
    if name=="lib.backend" then return {new=function() return backend end} end
    if name=="lib.ui" then return {new=function(_,app,display)
      assert(display==computer)
      return {run=function()
        tick(app);assert(app.pendingResume and #backend.writes==writeCount)
        tick(app);assert(app.mode=="auto");launched=true
      end}
    end} end
    return require(name)
  end
  assert(loadfile("main.lua","t",env))("--boot")
  assert(launched and #backend.writes>writeCount)
end)
test("legacy display settings migrate while explicit controller display choices persist",function()
  for _,value in ipairs({false,"old-monitor"}) do
    files["settings.dat"]=textutils.serialize({monitor=value})
    local testConfig=Settings.load(".")
    assert(testConfig.controllerDisplay.mode==(value==false and "terminal" or "auto") and testConfig.monitor==nil)
    Settings.save(".",testConfig)
    assert(Settings.load(".").controllerDisplay.mode==testConfig.controllerDisplay.mode)
  end
end)

local function scanPeers()
  local queried={};local output={}
  peripheral={getNames=function() return {} end}
  local network=require("lib.network");local previous=network.request
  network.request=function(id,op)
    assert(op=="poll");queried[#queried+1]=id
    return {token="test",devices={}}
  end
  local env=setmetatable({},{__index=_G});env._G=env
  env.shell={getRunningProgram=function() return "diagnostics.lua" end}
  env.print=function(text) output[#output+1]=tostring(text) end
  env.printError=function(err) error(err) end
  local ok,err=pcall(function()
    assert(loadfile("diagnostics.lua","t",env))("scan")
  end)
  network.request=previous
  assert(ok,err)
  return queried,table.concat(output,"\n")
end
test("removing peer zero persists and scans only the remaining peers",function()
  local app,backend,testConfig=fixture(true);testConfig.remotePeers={0,4,5,6};enable(app)
  app.enqueue("peer",0,false);tick(app)
  local queried,output=scanPeers()
  assert(table.concat(queried,",")=="4,5,6")
  local saved=Settings.load(".")
  assert(table.concat(saved.remotePeers,",")=="4,5,6" and saved.lastMode=="manual" and not saved.autoSnapshot)
  assert(output:find("Configured peers (3): 4, 5, 6",1,true))
  assert(saved.storage[1]==testConfig.storage[1],"Device selections should be available for explicit review")
  queried=scanPeers();assert(table.concat(queried,",")=="4,5,6")
end)
test("adding replacement peers keeps other peers and prevents duplicates",function()
  local app,backend,testConfig=fixture(true);testConfig.remotePeers={0};enable(app)
  app.enqueue("peer",0,false);tick(app)
  for _,id in ipairs({4,5,6,4}) do app.enqueue("peer",id,true);tick(app) end
  local queried=scanPeers()
  assert(table.concat(queried,",")=="4,5,6")
  assert(Settings.load(".").lastMode=="manual")
end)
test("no-op peer changes preserve saved Auto intent",function()
  local app,backend,testConfig=fixture(true);testConfig.remotePeers={4,5,6};enable(app)
  app.enqueue("peer",0,false);app.enqueue("peer",4,true);tick(app)
  local saved=Settings.load(".");assert(saved.lastMode=="auto" and saved.autoSnapshot)
end)
local function runMain(...)
  local started=false
  local env=setmetatable({},{__index=_G});env._G=env
  env.shell={getRunningProgram=function() return "main.lua" end}
  local display={getSize=function() return 51,19 end,isColor=function() return true end}
  env.term={current=function() return display end}
  env.loadfile=function() return function() return {} end end
  env.require=function(name)
    if name=="lib.network" then return {open=function() started=true end} end
    if name=="lib.backend" then return {new=function() return require("lib.demo").new(true) end} end
    if name=="lib.display" then return {controller=function() return function() return display end end} end
    if name=="lib.ui" then return {new=function() return {run=function() end} end} end
    return require(name)
  end
  local ok,err=pcall(assert(loadfile("main.lua","t",env)),...)
  return ok,err,started
end
test("terminal recovery and Setup display changes preserve saved Auto",function()
  local app,backend,testConfig=fixture(true);enable(app)
  assert(runMain("--terminal"))
  local saved=Settings.load(".")
  assert(saved.controllerDisplay.mode=="terminal" and saved.lastMode=="auto" and saved.autoSnapshot)
  app=App.new(saved,backend,".",false)
  app.enqueue("display",nil,"auto");tick(app)
  saved=Settings.load(".")
  assert(saved.controllerDisplay.mode=="auto" and saved.lastMode=="auto" and saved.autoSnapshot)
end)
test("removed controller flags fail before saving settings or opening the network",function()
  local app=fixture(true);enable(app)
  local before=files["settings.dat"]
  for _,flag in ipairs({"--demo","--direct","--peer","--remove-peer","--monitor","--auto-display"}) do
    local ok,err,started=runMain("--terminal","--manual",flag)
    assert(not ok and tostring(err):find("Unknown option: "..flag,1,true))
    assert(not started and files["settings.dat"]==before)
  end
end)
test("normal launch preserves Auto and explicit manual clears its restart intent",function()
  local app=fixture(true);enable(app)
  local before=files["settings.dat"]
  assert(runMain());assert(files["settings.dat"]==before)
  assert(runMain("--boot","--manual","--terminal"))
  local saved=Settings.load(".")
  assert(saved.lastMode=="manual" and not saved.autoSnapshot and not saved.autoStandby)
  assert(saved.controllerDisplay.mode=="terminal")
end)
test("device names persist without changing Auto intent, selections or command IDs",function()
  local app,backend,testConfig=fixture(true);enable(app)
  local id=backend.devices[1].id;local writes=#backend.writes
  app.rename(id,"  Baseline reactor  ")
  local saved=Settings.load(".")
  assert(saved.deviceNames[id]=="Baseline reactor" and saved.lastMode=="auto")
  assert(saved.autoSnapshot.generators==testConfig.autoSnapshot.generators and saved.storage[1]==testConfig.storage[1])
  assert(#backend.writes==writes and backend.devices[1].id==id and app.mode=="auto")
  local restored=App.new(saved,backend,".",false);assert(restored.pendingResume)
  restored.rename(id,"");assert(Settings.load(".").deviceNames[id]==nil)
end)
test("failed or invalid rename preserves the previous name and control mode",function()
  local app,backend,testConfig=fixture(true);enable(app);local id=backend.devices[1].id
  app.rename(id,"Existing name")
  assert(not pcall(app.rename,id,string.rep("x",33)))
  assert(not pcall(app.rename,id,"bad\nname"))
  app.save=function() error("disk full") end
  assert(not pcall(app.rename,id,"Unsaved name"))
  assert(testConfig.deviceNames[id]=="Existing name" and app.mode=="auto")
end)
print(string.format("%d restart/configuration tests passed",count))
