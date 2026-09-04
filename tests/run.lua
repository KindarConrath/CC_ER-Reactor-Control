package.path="./?.lua;"..package.path
local Util=require("lib.util")
local Control=require("lib.control")
local Demo=require("lib.demo")
local clock=100
os.epoch=function() return clock*1000 end
os.getComputerID=function() return 42 end
local App=require("lib.app")
local count=0
local function test(name, callback)
  local succeeded, testError = pcall(callback)
  assert(succeeded, name .. ": " .. tostring(testError))
  count = count + 1
  print("PASS " .. name)
end
local function config()
  local value = dofile("config.lua")
  return value
end
local function fixture(direct)
  local testConfig=config(); testConfig.storage={"demo/battery"}; testConfig.calibration={}
  local backend=Demo.new(direct); return App.new(testConfig,backend,".",true),backend,testConfig
end
test("manual startup and idle issue no writes",function()
  local app,backend=fixture(true); app.tick(); clock=clock+1; app.tick()
  assert(app.mode=="manual" and #backend.writes==0)
end)
test("direct Auto regulates rods and activates reactors",function()
  local app,backend=fixture(true); backend.devices[#backend.devices].energy=1000000
  app.enqueue("mode",nil,"auto"); app.tick()
  assert(app.mode=="auto" and backend.devices[1].active and backend.devices[1].rods<80)
end)
local function rodMovement(charge,trend,cooled,elapsed,testConfig)
  testConfig=testConfig or config();elapsed=elapsed or 1;trend=trend or 0
  local controlState=Control.new();controlState.net=trend;controlState.previousCapacity=100;controlState.previousEnergy=charge*100-trend*100*elapsed
  local device={id="r",name="r",rods=80,fuel=100,active=true,cooled=cooled or false,
    steam=0,hot=0,hotCapacity=100}
  Control.step(controlState,testConfig,{device},{},{energy=charge*100,capacity=100,charge=charge},elapsed,{})
  return 80-controlState.reactors.r.rods
end
test("passive withdrawal accelerates at low charge and tapers near target",function()
  local empty,low,middle,near=rodMovement(0),rodMovement(.1),rodMovement(.4),rodMovement(.6)
  assert(math.abs(empty-8)<1e-9)
  assert(low>middle and middle>2 and near<1)
  assert(math.abs(low-6.4081632653)<1e-8)
  assert(math.abs(middle-3.1020408163)<1e-8)
  assert(math.abs(rodMovement(.7))<1e-9)
end)
test("charge trend slows withdrawal and accelerates insertion",function()
  assert(rodMovement(.1,.015)>0 and rodMovement(.1,.015)<rodMovement(.1))
  assert(rodMovement(.1,.025)<0)
  assert(math.abs(rodMovement(.8)+2.8)<1e-9)
  assert(math.abs(rodMovement(.8,.01)+8)<1e-9)
  assert(rodMovement(.69,.005)<0,"Should reduce output before a projected overshoot")
  assert(math.abs(rodMovement(.71))<.3,"Small steady excess should taper")
end)
test("new passive rates preserve steam regulation and allow previous tuning",function()
  assert(math.abs(rodMovement(.1,0,true)-2)<1e-9)
  assert(math.abs(rodMovement(.6,0,true)-2)<1e-9)
  local testConfig=config();testConfig.passiveMaxRodWithdrawalRate=testConfig.rodRate;testConfig.passiveMaxRodInsertionRate=testConfig.rodRate
  assert(math.abs(rodMovement(.1,0,false,1,testConfig)-2)<1e-9)
  assert(math.abs(rodMovement(.8,0,false,1,testConfig)+.8)<1e-9)
end)
test("adaptive rates scale with elapsed time",function()
  local testConfig=config();testConfig.passiveMaxRodWithdrawalRate=4;testConfig.passiveMaxRodInsertionRate=4
  assert(math.abs(rodMovement(0,0,false,.5,testConfig)-2)<1e-9)
  assert(math.abs(rodMovement(.8,.01,false,.5,testConfig)+2)<1e-9)
end)
test("old configuration receives rate defaults without needing file edits",function()
  local testConfig=config();testConfig.passiveMaxRodWithdrawalRate=nil;testConfig.passiveMaxRodInsertionRate=nil
  testConfig.passiveBrakingSeconds=nil
  local previousDofile,previousFs=dofile,fs
  dofile=function() return testConfig end
  fs = {
    combine = function(leftPath, rightPath)
      return leftPath .. "/" .. rightPath
    end,
    exists = function()
      return false
    end,
  }
  local ok,result=pcall(require("lib.settings").load,".")
  dofile=previousDofile;fs=previousFs
  assert(ok and result.passiveMaxRodWithdrawalRate==8 and result.passiveMaxRodInsertionRate==8)
  assert(result.passiveBrakingSeconds==90)
end)
test("load-drop braking responds before the slow charge filter catches up",function()
  local function movement(seconds)
    local testConfig=config();testConfig.passiveBrakingSeconds=seconds
    local controlState=Control.new();controlState.net=0;controlState.brakingNet=0;controlState.previousEnergy=69.9;controlState.previousCapacity=100
    local device={id="r",name="r",rods=50,fuel=100,active=true,cooled=false}
    Control.step(controlState,testConfig,{device},{},{energy=70,capacity=100,charge=.7},1,{})
    return controlState.reactors.r.rods-50
  end
  assert(movement(90)>movement(30)*3)
  assert(movement(90)<=config().passiveMaxRodInsertionRate)
end)
test("braking preserves falling-charge response and steady balance",function()
  local old=config();old.passiveBrakingSeconds=30
  for _,charge in ipairs({.1,.4,.6,.7,.8}) do
    assert(math.abs(rodMovement(charge,-.001)-rodMovement(charge,-.001,false,1,old))<1e-9)
    assert(math.abs(rodMovement(charge,0)-rodMovement(charge,0,false,1,old))<1e-9)
  end
end)
-- A deliberately simple two-reactor plant with lag and integer rod commands.
-- This exercises storage/load feedback; it is not Extreme Reactors physics.
local function passiveTrial(brakingSeconds,lag,dropLoad)
  local testConfig=config();testConfig.passiveBrakingSeconds=brakingSeconds
  local controlState=Control.new();local reactors={};local learned={}
  for index=1,2 do reactors[index]={id="r"..index,name="r"..index,rods=100*(1-3200/24000),
    fuel=100,active=true,cooled=false,output=1600} end
  local capacity=102400000;local energy=capacity*.7
  local result={minimum=1,peak=.7,finalMin=1,finalMax=0}
  for tick=0,3600 do
    local load=tick<600 and 3200 or 9600
    if result.removedAt then load=0 end
    local output=0
    for _,device in ipairs(reactors) do
      local wanted=device.active and 12000*(1-device.rods/100) or 0
      device.output=device.output+(wanted-device.output)*(1-math.exp(-1/lag))
      output=output+device.output
    end
    energy=Util.clamp(energy+(output-load)*20,0,capacity)
    local charge=energy/capacity
    if tick>=600 and not result.removedAt then
      result.minimum=math.min(result.minimum,charge)
      -- 69.95% is displayed as 70.0%; remove at the first recovery to that point.
      if dropLoad and tick>610 and charge>=.6995 then result.removedAt=tick end
    end
    if result.removedAt then result.peak=math.max(result.peak,charge) end
    if tick>=3540 then
      result.finalMin=math.min(result.finalMin,charge)
      result.finalMax=math.max(result.finalMax,charge)
    end
    local commands=Control.step(controlState,testConfig,reactors,{},{energy=energy,capacity=capacity,charge=charge},1,learned)
    for _,cmd in ipairs(commands) do
      for _,device in ipairs(reactors) do if cmd.id==device.id then
        if cmd.op=="rods" then
          assert(cmd.value>=0 and cmd.value<=100 and cmd.value%1==0)
          device.rods=cmd.value
        elseif cmd.op=="active" then device.active=cmd.value end
      end end
    end
    if result.removedAt and not result.closedAfter and reactors[1].rods==100
        and reactors[2].rods==100 then result.closedAfter=tick-result.removedAt end
    if result.removedAt and tick-result.removedAt>600 then break end
  end
  return result
end
test("load removal during recovery produces less overshoot and earlier full insertion",function()
  for _,lag in ipairs({3,8,20}) do
    local previous=passiveTrial(30,lag,true)
    local updated=passiveTrial(90,lag,true)
    assert(previous.removedAt and updated.removedAt,"Plant did not recover to target")
    assert(updated.peak<previous.peak-.01,"Braking should reduce overshoot by at least one point in this model")
    assert(updated.closedAfter<previous.closedAfter,"Rods should reach full insertion sooner")
    assert(math.abs(updated.minimum-previous.minimum)<.001,"Initial load response should be preserved")
    print(string.format("  lag %ds: peak %.2f%% -> %.2f%%, full insertion %ds -> %ds",
      lag,previous.peak*100,updated.peak*100,previous.closedAfter,updated.closedAfter))
  end
end)
test("stronger braking still settles near target under sustained load",function()
  for _,lag in ipairs({3,8,20}) do
    local result=passiveTrial(90,lag,false)
    assert(result.finalMin>.695 and result.finalMax<.705)
    assert(result.finalMax-result.finalMin<.002,"Steady load should not sustain large swings")
  end
end)
test("returning to Manual preserves all controls",function()
  local app,backend=fixture(true); app.enqueue("mode",nil,"auto"); app.tick()
  local writeCount = #backend.writes
  app.enqueue("mode",nil,"manual")
  clock = clock + 1
  app.tick()
  assert(#backend.writes == writeCount and app.mode == "manual")
end)
test("manual rod commands cannot override Auto",function()
  local app,backend=fixture(true); app.enqueue("mode",nil,"auto"); app.tick()
  app.enqueue("rods",backend.devices[1].id,0); clock=clock+1; app.tick()
  assert(backend.devices[1].rods>0)
end)
test("storage aggregates by capacity and deduplicates identities",function()
  local storageDevices={{id="a",kind="storage",online=true,identity="one",energy=50,capacity=100},
    {id="b",kind="storage",online=true,identity="two",energy=0,capacity=900},
    {id="c",kind="storage",online=true,identity="one",energy=50,capacity=100}}
  local storageSummary=Control.storage(storageDevices,{"a","b","c"},{},{})
  assert(storageSummary.energy==50 and storageSummary.capacity==1000 and storageSummary.charge==0.05)
end)
test("configured missing storage never falls back to internal buffers",function()
  local app,backend,testConfig=fixture(true); testConfig.storage={"missing"}; app.enqueue("mode",nil,"auto"); app.tick()
  assert(app.mode=="manual" and #backend.writes==0 and app.problem:find("Storage unavailable"))
end)
test("disconnected selection stays removable then disappears completely",function()
  local app,backend,testConfig=fixture(true);testConfig.storage={"removed-bank","demo/battery"};app.tick()
  local listed=app.storageDevices();assert(#listed==2)
  assert(listed[2].id=="removed-bank" and not listed[2].online)
  local saved
  app.save=function() saved=Util.copy(testConfig.storage) end
  local writeCount=#backend.writes;app.enqueue("storage","removed-bank");app.tick()
  assert(#testConfig.storage==1 and testConfig.storage[1]=="demo/battery")
  assert(#saved==1 and saved[1]=="demo/battery")
  assert(#app.storageDevices()==1 and app.storageDevices()[1].id=="demo/battery")
  assert(not app.problem and app.mode=="manual" and #backend.writes==writeCount)
  local reboot=App.new(testConfig,backend,".",true);reboot.tick()
  assert(#reboot.storageDevices()==1,"Removed ID should not return after restart")
end)
test("replacement bank receives no automatic selection from an old ID",function()
  local app,backend,testConfig=fixture(true);testConfig.storage={"old-bank"};app.tick()
  assert(app.problem and #app.storageDevices()==2)
  app.enqueue("storage","old-bank");app.tick()
  assert(#testConfig.storage==0 and not app.problem and app.storage.source=="Generator buffers")
  assert(#app.storageDevices()==1 and app.storageDevices()[1].id=="demo/battery")
  app.enqueue("storage","demo/battery");app.tick()
  assert(#testConfig.storage==1 and app.storage.source=="Selected storage" and app.mode=="manual")
end)
test("connected selected storage is listed exactly once",function()
  local app=fixture(true);app.tick();assert(#app.storageDevices()==1)
end)
test("Auto suspends on a disappearing reactor",function()
  local app,backend=fixture(true); app.enqueue("mode",nil,"auto"); app.tick()
  table.remove(backend.devices,2); local writeCount=#backend.writes; clock=clock+1; app.tick()
  assert(app.mode=="manual" and #backend.writes==writeCount)
end)
test("unsupported topology blocks Auto",function()
  local app,backend=fixture(false); table.insert(backend.devices,1,Util.copy(backend.devices[1]))
  app.enqueue("mode",nil,"auto"); app.tick(); assert(app.mode=="manual" and #backend.writes==0)
end)
test("standby disengages coils and reduces intake",function()
  local testConfig=config(); local backend=Demo.new(false); local all=backend.poll()
  local reactor={all[1]}; local turbines={all[2],all[3]}
  for _,turbine in ipairs(turbines) do turbine.rpm=1796; turbine.coils=true; turbine.flow=1000; turbine.flowLimit=1000; turbine.active=true end
  local controlState=Control.new(); local commands=Control.step(controlState,testConfig,reactor,turbines,{energy=95,capacity=100,charge=.95},1,{})
  local coils,flow=0,0
  for _,command in ipairs(commands) do
    if command.op=="coils" then assert(command.value==false); coils=coils+1 end
    if command.op=="flow" then assert(command.value<1000); flow=flow+1 end
  end
  assert(controlState.standby and coils==2 and flow==2)
end)
test("standby hysteresis avoids threshold chatter",function()
  local testConfig=config(); local controlState=Control.new()
  Control.step(controlState,testConfig,{}, {},{energy=95,capacity=100,charge=.95},1,{})
  Control.step(controlState,testConfig,{}, {},{energy=85,capacity=100,charge=.85},1,{})
  assert(controlState.standby)
  Control.step(controlState,testConfig,{}, {},{energy=70,capacity=100,charge=.70},1,{})
  assert(not controlState.standby)
end)
test("generation resumes with coil engagement near target RPM",function()
  local testConfig=config(); local backend=Demo.new(false); local all=backend.poll(); local turbine=all[2]
  turbine.rpm=1796; turbine.coils=false; turbine.active=true; turbine.flowLimit=100
  local commands=Control.step(Control.new(),testConfig,{all[1]},{turbine},{energy=50,capacity=100,charge=.5},1,{})
  local engaged=false
  for _,cmd in ipairs(commands) do if cmd.op=="coils" and cmd.value then engaged=true end end
  assert(engaged)
end)
test("normal storage cycling does not change saved turbine calibration",function()
  local testConfig=config(); local backend=Demo.new(false); local all=backend.poll(); local turbine=all[2]
  turbine.rpm=1796;turbine.coils=true;turbine.active=true;turbine.flowLimit=1000;turbine.flow=1000
  local controlState=Control.new(); local learned={}
  learned[turbine.id]={rpm=1796,generating={flow=1000,output=40000}}
  for index=1,12 do Control.step(controlState,testConfig,{all[1]},{turbine},{energy=50,capacity=100,charge=.5},1,learned) end
  turbine.coils=false;turbine.flowLimit=100;turbine.flow=100
  for index=1,12 do Control.step(controlState,testConfig,{all[1]},{turbine},{energy=95,capacity=100,charge=.95},1,learned) end
  assert(not learned[turbine.id].standby and learned[turbine.id].generating.flow==1000)
end)
test("sustained calibrated turbine demand warns when the reactor is fully open and short on steam",function()
  local testConfig=config();local backend=Demo.new(false);local all=backend.poll();local reactor=all[1]
  local turbines={all[2],all[3]};local points={}
  reactor.rods=0;reactor.steam=1500;reactor.active=true
  for _,turbine in ipairs(turbines) do
    turbine.active=true;turbine.coils=true;turbine.rpm=1796;turbine.flowLimit=1000;turbine.flow=1000;turbine.output=40000
    points[turbine.id]={rpm=1796,generating={flow=1000,output=40000}}
  end
  local controlState=Control.new()
  for _=1,9 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,points) end
  assert(not controlState.steamShortage)
  Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,points)
  assert(controlState.steamShortage and controlState.steamShortage.demand==2000)
  assert(controlState.steamShortage.output==1500 and controlState.steamShortage.deficit==500)
  assert(controlState.steamShortage.calibrated)
end)
test("capacity warning ignores warmup and margin, then clears after recovery or standby",function()
  local testConfig=config();local backend=Demo.new(false);local all=backend.poll();local reactor=all[1]
  local turbines={all[2],all[3]}
  reactor.rods=0;reactor.steam=1500;reactor.active=true
  for _,turbine in ipairs(turbines) do
    turbine.active=true;turbine.coils=true;turbine.rpm=1796;turbine.flowLimit=1000;turbine.flow=1000;turbine.output=40000
  end
  local controlState=Control.new()
  for _=1,38 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(not controlState.steamShortage,"Uncalibrated turbines need the startup grace plus shortage delay")
  Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{})
  assert(controlState.steamShortage and not controlState.steamShortage.calibrated)
  reactor.steam=1900
  for _=1,2 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(controlState.steamShortage,"Recovery needs confirmation")
  Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{})
  assert(not controlState.steamShortage,"A shortage at exactly the 5%/100 mB margin is ignored")
  reactor.steam=1500;reactor.rods=2;controlState=Control.new()
  for _=1,60 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(not controlState.steamShortage,"Do not warn before rods reach fully open")
  reactor.rods=0
  for _=1,39 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(controlState.steamShortage)
  Control.step(controlState,testConfig,{reactor},turbines,{energy=95,capacity=100,charge=.95},1,{})
  assert(controlState.standby and not controlState.steamShortage,"Standby clears a generating-capacity warning")
end)
test("an exhausted calibrated reactor reports the steam shortage without opening its rods",function()
  local testConfig=config();local backend=Demo.new(false);local all=backend.poll();local reactor=all[1]
  local turbines={all[2],all[3]};local points={}
  reactor.rods=80;reactor.fuel=0;reactor.steam=0;reactor.active=false
  for _,turbine in ipairs(turbines) do
    turbine.active=true;turbine.coils=true;turbine.rpm=1796;turbine.flowLimit=1000;turbine.flow=1000;turbine.output=40000
    points[turbine.id]={rpm=1796,generating={flow=1000,output=40000}}
  end
  local controlState=Control.new()
  for _=1,10 do Control.step(controlState,testConfig,{reactor},turbines,{energy=50,capacity=100,charge=.5},1,points) end
  assert(controlState.steamShortage and controlState.steamShortage.deficit==2000)
  assert(controlState.reactors[reactor.id].rods==80,"Fuel starvation must not withdraw rods")
end)
test("Stop all changes global mode and stops steam/fission",function()
  local app,backend=fixture(false); app.enqueue("mode",nil,"auto"); app.tick()
  app.enqueue("stop"); clock=clock+1; app.tick()
  assert(app.mode=="manual" and not backend.devices[1].active and backend.devices[1].rods==100)
  assert(not backend.devices[2].active and backend.devices[2].flowLimit==0)
end)
test("RPM feedback converges without changing calibration",function()
  local testConfig=config(); local backend=Demo.new(false); local device=backend.devices[2]
  device.active=true;device.coils=true;device.rpm=1600;device.flowLimit=950;device.flow=950
  local state=Control.new();local learned={}
  for index=1,300 do
    local commands=Control.step(state,testConfig,{}, {device},{energy=50,capacity=100,charge=.5},1,learned)
    for _,cmd in ipairs(commands) do if cmd.op=="flow" then device.flowLimit=cmd.value end end
    device.flow=device.flowLimit
    device.rpm=device.rpm+(device.flow*1.2-device.rpm*.7)/12
  end
  assert(math.abs(device.rpm-testConfig.rpmTarget)<testConfig.rpmTolerance)
  assert(next(learned)==nil)
end)
test("failed writes suspend automatic control",function()
  local app,backend=fixture(true); backend.write=function() error("link lost") end
  app.enqueue("mode",nil,"auto"); app.tick()
  assert(app.mode=="manual" and app.message:find("link lost"))
end)
test("fuel starvation does not drive rods fully open",function()
  local app,backend=fixture(true); backend.devices[1].fuel=0
  app.enqueue("mode",nil,"auto"); app.tick(); assert(backend.devices[1].rods==80)
end)
test("a demanded passive reactor with no output reports and clears a stall",function()
  local testConfig=config();local backend=Demo.new(true);local reactor=backend.devices[1]
  reactor.active=true;reactor.rods=50;reactor.output=0;reactor.fuel=5000
  local controlState=Control.new()
  for _=1,29 do Control.step(controlState,testConfig,{reactor},{},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(#controlState.reactorStalls==0)
  Control.step(controlState,testConfig,{reactor},{},{energy=50,capacity=100,charge=.5},1,{})
  assert(controlState.reactorStalls[1] and not controlState.reactorStalls[1].cooled)
  reactor.output=100
  for _=1,3 do Control.step(controlState,testConfig,{reactor},{},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(#controlState.reactorStalls==0)
end)
test("a demanded cooled reactor with no steam reports a measured stall",function()
  local testConfig=config();local backend=Demo.new(false);local reactor,turbine=backend.devices[1],backend.devices[2]
  reactor.active=true;reactor.rods=50;reactor.steam=0;reactor.fuel=5000
  turbine.active=true;turbine.coils=true;turbine.rpm=testConfig.rpmTarget;turbine.flow=1000;turbine.flowLimit=1000
  local controlState=Control.new()
  for _=1,30 do Control.step(controlState,testConfig,{reactor},{turbine},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(controlState.reactorStalls[1] and controlState.reactorStalls[1].cooled)
  assert(controlState.reactorStalls[1].output==0 and controlState.reactorStalls[1].demand>0)
end)
test("long demo runs keep commands within device limits",function()
  for _,direct in ipairs({true,false}) do
    local app,backend=fixture(direct); app.enqueue("mode",nil,"auto")
    for index=1,600 do clock=clock+1; app.tick(); assert(app.mode=="auto",app.message) end
    for _,cmd in ipairs(backend.writes) do
      if cmd.op=="rods" then assert(cmd.value>=0 and cmd.value<=100) end
      if cmd.op=="flow" then assert(cmd.value>=0 and cmd.value<=2000) end
    end
  end
end)
-- Contract tests using the real adapter, with mocked CC:Tweaked peripherals.
test("local adapter reads zero-indexed rods and clamps commands",function()
  local rods={10,30}; local active=false
  local peripheralDevice={getActive=function() return active end,getEnergyStored=function() return 50 end,
    getEnergyCapacity=function() return 100 end,getEnergyProducedLastTick=function() return 7 end,
    isActivelyCooled=function() return false end,getNumberOfControlRods=function() return 2 end,
    getControlRodLevel=function(index) return rods[index+1] end,getFuelAmount=function() return 5 end,
    getWasteAmount=function() return 1 end,getFuelTemperature=function() return 300 end,
    setAllControlRodLevels=function(insertion) rods={insertion,insertion} end,
    setActive=function(value) active=value end}
  peripheral={wrap=function() return peripheralDevice end,getNames=function() return {"reactor_0"} end,
    hasType=function(_, peripheralType)
      return peripheralType=="extremereactor-reactorComputerPort"
    end}
  local Devices=require("lib.devices"); local testConfig=config(); local device=Devices.poll(testConfig)[1]
  assert(device.rods==20 and device.output==7)
  Devices.write({name="reactor_0",op="rods",value=105},testConfig); assert(rods[1]==100)
end)
test("mapped storage applies configured conversion",function()
  local testConfig=config(); testConfig.storageMappings.cell={stored="stored",capacity="maximum",scale=.4,identity="bank"}
  peripheral={wrap=function() return {stored=function() return "250" end,maximum=function() return 1000 end} end,
    getNames=function() return {"cell"} end,hasType=function() return false end}
  local device=require("lib.devices").poll(testConfig)[1]
  assert(device.energy==100 and device.capacity==400 and device.identity=="bank")
end)
test("Integrated Dynamics energy battery uses the generic API with a descriptive label",function()
  local battery={getEnergy=function() return 250 end,getEnergyCapacity=function() return 1000 end}
  peripheral={getNames=function() return {"back"} end,
    hasType=function(_,kind) return kind=="integrateddynamics:energy_battery" or kind=="energy_storage" end,
    wrap=function() return battery end}
  local device=require("lib.devices").poll(config())[1]
  assert(device.kind=="storage" and device.online)
  assert(device.energy==250 and device.capacity==1000)
  assert(device.adapter=="Integrated Dynamics energy battery")
end)
test("reported wired setup discovers both BigReactors reactors and ultimate cube",function()
  local names={"right","BigReactors-Reactor_0","BigReactors-Reactor_1","ultimateEnergyCube_0","left"}
  local kinds={right="modem",[names[2]]="BigReactors-Reactor",[names[3]]="BigReactors-Reactor",
    [names[4]]="ultimateEnergyCube",left="monitor"}
  local reactor={getActive=function() return false end,getEnergyStored=function() return 50 end,
    getEnergyCapacity=function() return 100 end,getEnergyProducedLastTick=function() return 7 end,
    isActivelyCooled=function() return false end,getNumberOfControlRods=function() return 1 end,
    getControlRodLevel=function() return 30 end,getFuelAmount=function() return 5 end,
    getWasteAmount=function() return 1 end,getFuelTemperature=function() return 300 end,
    setAllControlRodLevels=function(insertion) assert(insertion==40) end}
  local cube={getEnergy=function() return 4000 end,getMaxEnergy=function() return 8000 end}
  peripheral={getNames=function() return names end,
    hasType=function(peripheralName, peripheralType) return kinds[peripheralName]==peripheralType end,
    wrap=function(peripheralName)
      return kinds[peripheralName]=="BigReactors-Reactor" and reactor or cube
    end,
    getType=function(peripheralName) return kinds[peripheralName] end,
    getMethods=function() return {"getEnergy"} end}
  -- A non-default conversion catches accidental hardcoding of the usual J/FE ratio.
  mekanismEnergyHelper={joulesToFE=function(joules) return joules/4 end}
  local Devices=require("lib.devices");local testConfig=config();local result=Devices.poll(testConfig)
  assert(#result==3)
  assert(result[1].kind=="reactor" and result[1].online)
  assert(result[2].kind=="reactor" and result[2].online)
  assert(result[3].kind=="storage" and result[3].online)
  assert(result[3].energy==1000 and result[3].capacity==2000)
  Devices.write({name=names[2],op="rods",value=40},testConfig)
  local inspected=Devices.inspect(testConfig);assert(#inspected==5)
  mekanismEnergyHelper=nil
end)
test("Mekanism helper absence is reported without mislabelling Joules as FE",function()
  peripheral={getNames=function() return {"ultimateEnergyCube_0"} end,
    hasType=function(_, peripheralType) return peripheralType=="ultimateEnergyCube" end,
    wrap=function() return {getEnergy=function() return 1 end,getMaxEnergy=function() return 2 end} end}
  mekanismEnergyHelper=nil
  local device=require("lib.devices").poll(config())[1]
  assert(device.kind=="storage" and not device.online and device.error:find("helper unavailable"))
end)
test("reported Mekanism induction port is recognized as matrix storage",function()
  local formed=true
  local port={
    isFormed=function() return formed end,
    getEnergy=function() return 4000000 end,
    getMaxEnergy=function() return 16000000 end,
  }
  peripheral={
    getNames=function() return {"inductionPort_0"} end,
    hasType=function(_,kind) return kind=="inductionPort" end,
    wrap=function() return port end,
  }
  mekanismEnergyHelper={joulesToFE=function(joules) return joules/4 end}
  local device=require("lib.devices").poll(config())[1]
  assert(device.kind=="storage" and device.online)
  assert(device.energy==1000000 and device.capacity==4000000)
  assert(device.adapter=="Mekanism induction matrix")
  formed=false
  device=require("lib.devices").poll(config())[1]
  assert(not device.online and device.error:find("not formed"))
  mekanismEnergyHelper=nil
end)
test("reported Extreme Reactors Energizer computer port is recognized as storage",function()
  local assembled=true
  local energizer={
    mbIsAssembled=function() return assembled end,
    getEnergyStored=function() return 2500000 end,
    getEnergyCapacity=function() return 10000000 end,
  }
  peripheral={
    getNames=function() return {"BigReactors-Energizer_0"} end,
    hasType=function(_,kind) return kind=="BigReactors-Energizer" end,
    wrap=function() return energizer end,
  }
  local device=require("lib.devices").poll(config())[1]
  assert(device.kind=="storage" and device.online)
  assert(device.energy==2500000 and device.capacity==10000000)
  assert(device.adapter=="Extreme Reactors energizer")
  assembled=false
  device=require("lib.devices").poll(config())[1]
  assert(not device.online and device.error:find("not assembled"))
end)
test("reported Draconic Evolution energy interface is recognized as storage",function()
  local pylon={
    getEnergyStored=function() return 3e12 end,
    getMaxEnergyStored=function() return 8e12 end,
  }
  peripheral={
    getNames=function() return {"back"} end,
    hasType=function(_,kind) return kind=="draconic_rf_storage" end,
    wrap=function() return pylon end,
  }
  local device=require("lib.devices").poll(config())[1]
  assert(device.kind=="storage" and device.online)
  assert(device.energy==3e12 and device.capacity==8e12)
  assert(device.adapter=="Draconic Evolution energy core")
end)
test("explicit cube mapping overrides native conversion",function()
  local testConfig=config();testConfig.storageMappings.ultimateEnergyCube_0={stored="getEnergy",capacity="getMaxEnergy",scale=.25}
  peripheral={getNames=function() return {"ultimateEnergyCube_0"} end,
    hasType=function(_, peripheralType) return peripheralType=="ultimateEnergyCube" end,
    wrap=function() return {getEnergy=function() return 1 end,getMaxEnergy=function() return 2 end} end}
  local device=require("lib.devices").poll(testConfig)[1]
  assert(device.online and device.energy==.25 and device.capacity==.5 and device.adapter=="mapped")
end)
test("companion rejects wrong owner, expired leases, and replay",function()
  local Network=require("lib.network"); local applied=0
  local handler=Network.serverHandler(7,config(),{poll=function() return {} end,write=function() applied=applied+1 end})
  assert(handler(8,{id="a",op="poll"})==nil)
  local pollResponse=handler(7,{id="a",op="poll"}); assert(pollResponse.ok)
  local writeRequest={id="b",op="write",data={token=pollResponse.data.token,commands={{op="active",value=true}}}}
  assert(handler(7,writeRequest).ok and applied==1)
  assert(not handler(7,writeRequest).ok and applied==1)
  pollResponse=handler(7,{id="c",op="poll"})
  writeRequest.data.token=pollResponse.data.token
  clock=clock+6
  assert(not handler(7,writeRequest).ok and applied==1)
end)
test("client matches acknowledgements and reports timeout",function()
  local Network=require("lib.network"); local sent; local reads=0
  rednet={send=function(peer,msg) sent=msg; return true end,receive=function()
    reads=reads+1
    if reads==1 then return 999,{id=sent.id,reply=true,ok=true,data="wrong peer"} end
    return 7,{id=sent.id,reply=true,ok=true,data="right peer"}
  end}
  assert(Network.request(7,"poll",nil,2)=="right peer")
  rednet.receive=function() clock=clock+2; return nil end
  local ok,err=pcall(Network.request,7,"poll",nil,2)
  assert(not ok and Network.isConnectionError(err) and tostring(err)=="Peer #7: no response")
  local testConfig=config();testConfig.remotePeers={7};peripheral={getNames=function() return {} end}
  local _,errors,retry=require("lib.backend").new(testConfig).poll()
  assert(retry and errors[1]=="Peer #7: no response")
  rednet.receive=function() return 7,{id=sent.id,reply=true,ok=false,error="lib/devices.lua:55: invalid rods"} end
  _,errors,retry=require("lib.backend").new(testConfig).poll()
  assert(not retry and errors[1]=="Peer #7: invalid rods")
  rednet.send=function() return false end
  ok,err=pcall(Network.request,7,"poll",nil,2)
  assert(not ok and Network.isConnectionError(err) and tostring(err)=="Peer #7: no open modem")
end)
test("backend normalizes remote IDs and sends acknowledged batches",function()
  peripheral={getNames=function() return {} end}
  local Network=require("lib.network"); local old=Network.request; local sent
  Network.request=function(peer,op,data)
    if op=="poll" then return {token="lease",devices={{name="r",kind="reactor",online=true}}} end
    sent=data; return true
  end
  local testConfig=config(); testConfig.remotePeers={7}; local backend=require("lib.backend").new(testConfig)
  local list,errors=backend.poll(); assert(#errors==0 and list[1].id=="peer:7/r" and list[1].peer==7)
  backend.write({{name="r",peer=7,op="active",value=true}})
  assert(sent.token=="lease" and sent.commands[1].op=="active")
  Network.request=old
end)
print(string.format("%d tests passed",count))
