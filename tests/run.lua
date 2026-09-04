package.path="./?.lua;"..package.path
local U=require("lib.util")
local C=require("lib.control")
local Demo=require("lib.demo")
local clock=100
os.epoch=function() return clock*1000 end
os.getComputerID=function() return 42 end
local App=require("lib.app")
local count=0
local function test(name,f)
  local ok,e=pcall(f); assert(ok,name..": "..tostring(e)); count=count+1; print("PASS "..name)
end
local function config()
  local value = dofile("config.lua")
  return value
end
local function fixture(direct)
  local c=config(); c.storage={"demo/battery"}; c.calibration={}
  local b=Demo.new(direct); return App.new(c,b,".",true),b,c
end
test("manual startup and idle issue no writes",function()
  local a,b=fixture(true); a.tick(); clock=clock+1; a.tick()
  assert(a.mode=="manual" and #b.writes==0)
end)
test("direct Auto regulates rods and activates reactors",function()
  local a,b=fixture(true); b.devices[#b.devices].energy=1000000
  a.enqueue("mode",nil,"auto"); a.tick()
  assert(a.mode=="auto" and b.devices[1].active and b.devices[1].rods<80)
end)
local function rodMovement(charge,trend,cooled,dt,c)
  c=c or config();dt=dt or 1;trend=trend or 0
  local s=C.new();s.net=trend;s.previousCapacity=100;s.previousEnergy=charge*100-trend*100*dt
  local d={id="r",name="r",rods=80,fuel=100,active=true,cooled=cooled or false,
    steam=0,hot=0,hotCapacity=100}
  C.step(s,c,{d},{},{energy=charge*100,capacity=100,charge=charge},dt,{})
  return 80-s.reactors.r.rods
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
  local c=config();c.passiveMaxRodWithdrawalRate=c.rodRate;c.passiveMaxRodInsertionRate=c.rodRate
  assert(math.abs(rodMovement(.1,0,false,1,c)-2)<1e-9)
  assert(math.abs(rodMovement(.8,0,false,1,c)+.8)<1e-9)
end)
test("adaptive rates scale with elapsed time",function()
  local c=config();c.passiveMaxRodWithdrawalRate=4;c.passiveMaxRodInsertionRate=4
  assert(math.abs(rodMovement(0,0,false,.5,c)-2)<1e-9)
  assert(math.abs(rodMovement(.8,.01,false,.5,c)+2)<1e-9)
end)
test("old configuration receives rate defaults without needing file edits",function()
  local c=config();c.passiveMaxRodWithdrawalRate=nil;c.passiveMaxRodInsertionRate=nil
  c.passiveBrakingSeconds=nil
  local previousDofile,previousFs=dofile,fs
  dofile=function() return c end
  fs={combine=function(a,b) return a.."/"..b end,exists=function() return false end}
  local ok,result=pcall(require("lib.settings").load,".")
  dofile=previousDofile;fs=previousFs
  assert(ok and result.passiveMaxRodWithdrawalRate==8 and result.passiveMaxRodInsertionRate==8)
  assert(result.passiveBrakingSeconds==90)
end)
test("load-drop braking responds before the slow charge filter catches up",function()
  local function movement(seconds)
    local c=config();c.passiveBrakingSeconds=seconds
    local s=C.new();s.net=0;s.brakingNet=0;s.previousEnergy=69.9;s.previousCapacity=100
    local d={id="r",name="r",rods=50,fuel=100,active=true,cooled=false}
    C.step(s,c,{d},{},{energy=70,capacity=100,charge=.7},1,{})
    return s.reactors.r.rods-50
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
  local c=config();c.passiveBrakingSeconds=brakingSeconds
  local s=C.new();local reactors={};local learned={}
  for i=1,2 do reactors[i]={id="r"..i,name="r"..i,rods=100*(1-3200/24000),
    fuel=100,active=true,cooled=false,output=1600} end
  local capacity=102400000;local energy=capacity*.7
  local result={minimum=1,peak=.7,finalMin=1,finalMax=0}
  for tick=0,3600 do
    local load=tick<600 and 3200 or 9600
    if result.removedAt then load=0 end
    local output=0
    for _,d in ipairs(reactors) do
      local wanted=d.active and 12000*(1-d.rods/100) or 0
      d.output=d.output+(wanted-d.output)*(1-math.exp(-1/lag))
      output=output+d.output
    end
    energy=U.clamp(energy+(output-load)*20,0,capacity)
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
    local commands=C.step(s,c,reactors,{},{energy=energy,capacity=capacity,charge=charge},1,learned)
    for _,cmd in ipairs(commands) do
      for _,d in ipairs(reactors) do if cmd.id==d.id then
        if cmd.op=="rods" then
          assert(cmd.value>=0 and cmd.value<=100 and cmd.value%1==0)
          d.rods=cmd.value
        elseif cmd.op=="active" then d.active=cmd.value end
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
  local a,b=fixture(true); a.enqueue("mode",nil,"auto"); a.tick()
  local n=#b.writes; a.enqueue("mode",nil,"manual"); clock=clock+1; a.tick()
  assert(#b.writes==n and a.mode=="manual")
end)
test("manual rod commands cannot override Auto",function()
  local a,b=fixture(true); a.enqueue("mode",nil,"auto"); a.tick()
  a.enqueue("rods",b.devices[1].id,0); clock=clock+1; a.tick()
  assert(b.devices[1].rods>0)
end)
test("storage aggregates by capacity and deduplicates identities",function()
  local ds={{id="a",kind="storage",online=true,identity="one",energy=50,capacity=100},
    {id="b",kind="storage",online=true,identity="two",energy=0,capacity=900},
    {id="c",kind="storage",online=true,identity="one",energy=50,capacity=100}}
  local s=C.storage(ds,{"a","b","c"},{},{})
  assert(s.energy==50 and s.capacity==1000 and s.charge==0.05)
end)
test("configured missing storage never falls back to internal buffers",function()
  local a,b,c=fixture(true); c.storage={"missing"}; a.enqueue("mode",nil,"auto"); a.tick()
  assert(a.mode=="manual" and #b.writes==0 and a.problem:find("Storage unavailable"))
end)
test("disconnected selection stays removable then disappears completely",function()
  local a,b,c=fixture(true);c.storage={"removed-bank","demo/battery"};a.tick()
  local listed=a.storageDevices();assert(#listed==2)
  assert(listed[2].id=="removed-bank" and not listed[2].online)
  local saved
  a.save=function() saved=U.copy(c.storage) end
  local n=#b.writes;a.enqueue("storage","removed-bank");a.tick()
  assert(#c.storage==1 and c.storage[1]=="demo/battery")
  assert(#saved==1 and saved[1]=="demo/battery")
  assert(#a.storageDevices()==1 and a.storageDevices()[1].id=="demo/battery")
  assert(not a.problem and a.mode=="manual" and #b.writes==n)
  local reboot=App.new(c,b,".",true);reboot.tick()
  assert(#reboot.storageDevices()==1,"Removed ID should not return after restart")
end)
test("replacement bank receives no automatic selection from an old ID",function()
  local a,b,c=fixture(true);c.storage={"old-bank"};a.tick()
  assert(a.problem and #a.storageDevices()==2)
  a.enqueue("storage","old-bank");a.tick()
  assert(#c.storage==0 and not a.problem and a.storage.source=="Generator buffers")
  assert(#a.storageDevices()==1 and a.storageDevices()[1].id=="demo/battery")
  a.enqueue("storage","demo/battery");a.tick()
  assert(#c.storage==1 and a.storage.source=="Selected storage" and a.mode=="manual")
end)
test("connected selected storage is listed exactly once",function()
  local a=fixture(true);a.tick();assert(#a.storageDevices()==1)
end)
test("Auto suspends on a disappearing reactor",function()
  local a,b=fixture(true); a.enqueue("mode",nil,"auto"); a.tick()
  table.remove(b.devices,2); local n=#b.writes; clock=clock+1; a.tick()
  assert(a.mode=="manual" and #b.writes==n)
end)
test("unsupported topology blocks Auto",function()
  local a,b=fixture(false); table.insert(b.devices,1,U.copy(b.devices[1]))
  a.enqueue("mode",nil,"auto"); a.tick(); assert(a.mode=="manual" and #b.writes==0)
end)
test("standby disengages coils and reduces intake",function()
  local c=config(); local b=Demo.new(false); local all=b.poll()
  local r={all[1]}; local turbines={all[2],all[3]}
  for _,t in ipairs(turbines) do t.rpm=1796; t.coils=true; t.flow=1000; t.flowLimit=1000; t.active=true end
  local s=C.new(); local cmds=C.step(s,c,r,turbines,{energy=95,capacity=100,charge=.95},1,{})
  local coils,flow=0,0
  for _,x in ipairs(cmds) do
    if x.op=="coils" then assert(x.value==false); coils=coils+1 end
    if x.op=="flow" then assert(x.value<1000); flow=flow+1 end
  end
  assert(s.standby and coils==2 and flow==2)
end)
test("standby hysteresis avoids threshold chatter",function()
  local c=config(); local s=C.new()
  C.step(s,c,{}, {},{energy=95,capacity=100,charge=.95},1,{})
  C.step(s,c,{}, {},{energy=85,capacity=100,charge=.85},1,{})
  assert(s.standby)
  C.step(s,c,{}, {},{energy=70,capacity=100,charge=.70},1,{})
  assert(not s.standby)
end)
test("generation resumes with coil engagement near target RPM",function()
  local c=config(); local b=Demo.new(false); local all=b.poll(); local t=all[2]
  t.rpm=1796; t.coils=false; t.active=true; t.flowLimit=100
  local commands=C.step(C.new(),c,{all[1]},{t},{energy=50,capacity=100,charge=.5},1,{})
  local engaged=false
  for _,cmd in ipairs(commands) do if cmd.op=="coils" and cmd.value then engaged=true end end
  assert(engaged)
end)
test("normal storage cycling does not change saved turbine calibration",function()
  local c=config(); local b=Demo.new(false); local all=b.poll(); local t=all[2]
  t.rpm=1796;t.coils=true;t.active=true;t.flowLimit=1000;t.flow=1000
  local s=C.new(); local learned={}
  learned[t.id]={rpm=1796,generating={flow=1000,output=40000}}
  for i=1,12 do C.step(s,c,{all[1]},{t},{energy=50,capacity=100,charge=.5},1,learned) end
  t.coils=false;t.flowLimit=100;t.flow=100
  for i=1,12 do C.step(s,c,{all[1]},{t},{energy=95,capacity=100,charge=.95},1,learned) end
  assert(not learned[t.id].standby and learned[t.id].generating.flow==1000)
end)
test("sustained calibrated turbine demand warns when the reactor is fully open and short on steam",function()
  local c=config();local b=Demo.new(false);local all=b.poll();local r=all[1]
  local turbines={all[2],all[3]};local points={}
  r.rods=0;r.steam=1500;r.active=true
  for _,t in ipairs(turbines) do
    t.active=true;t.coils=true;t.rpm=1796;t.flowLimit=1000;t.flow=1000;t.output=40000
    points[t.id]={rpm=1796,generating={flow=1000,output=40000}}
  end
  local s=C.new()
  for _=1,9 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,points) end
  assert(not s.steamShortage)
  C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,points)
  assert(s.steamShortage and s.steamShortage.demand==2000)
  assert(s.steamShortage.output==1500 and s.steamShortage.deficit==500)
  assert(s.steamShortage.calibrated)
end)
test("capacity warning ignores warmup and margin, then clears after recovery or standby",function()
  local c=config();local b=Demo.new(false);local all=b.poll();local r=all[1]
  local turbines={all[2],all[3]}
  r.rods=0;r.steam=1500;r.active=true
  for _,t in ipairs(turbines) do
    t.active=true;t.coils=true;t.rpm=1796;t.flowLimit=1000;t.flow=1000;t.output=40000
  end
  local s=C.new()
  for _=1,38 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(not s.steamShortage,"Uncalibrated turbines need the startup grace plus shortage delay")
  C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{})
  assert(s.steamShortage and not s.steamShortage.calibrated)
  r.steam=1900
  for _=1,2 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(s.steamShortage,"Recovery needs confirmation")
  C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{})
  assert(not s.steamShortage,"A shortage at exactly the 5%/100 mB margin is ignored")
  r.steam=1500;r.rods=2;s=C.new()
  for _=1,60 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(not s.steamShortage,"Do not warn before rods reach fully open")
  r.rods=0
  for _=1,39 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,{}) end
  assert(s.steamShortage)
  C.step(s,c,{r},turbines,{energy=95,capacity=100,charge=.95},1,{})
  assert(s.standby and not s.steamShortage,"Standby clears a generating-capacity warning")
end)
test("an exhausted calibrated reactor reports the steam shortage without opening its rods",function()
  local c=config();local b=Demo.new(false);local all=b.poll();local r=all[1]
  local turbines={all[2],all[3]};local points={}
  r.rods=80;r.fuel=0;r.steam=0;r.active=false
  for _,t in ipairs(turbines) do
    t.active=true;t.coils=true;t.rpm=1796;t.flowLimit=1000;t.flow=1000;t.output=40000
    points[t.id]={rpm=1796,generating={flow=1000,output=40000}}
  end
  local s=C.new()
  for _=1,10 do C.step(s,c,{r},turbines,{energy=50,capacity=100,charge=.5},1,points) end
  assert(s.steamShortage and s.steamShortage.deficit==2000)
  assert(s.reactors[r.id].rods==80,"Fuel starvation must not withdraw rods")
end)
test("Stop all changes global mode and stops steam/fission",function()
  local a,b=fixture(false); a.enqueue("mode",nil,"auto"); a.tick()
  a.enqueue("stop"); clock=clock+1; a.tick()
  assert(a.mode=="manual" and not b.devices[1].active and b.devices[1].rods==100)
  assert(not b.devices[2].active and b.devices[2].flowLimit==0)
end)
test("RPM feedback converges without changing calibration",function()
  local c=config(); local b=Demo.new(false); local d=b.devices[2]
  d.active=true;d.coils=true;d.rpm=1600;d.flowLimit=950;d.flow=950
  local state=C.new();local learned={}
  for i=1,300 do
    local commands=C.step(state,c,{}, {d},{energy=50,capacity=100,charge=.5},1,learned)
    for _,cmd in ipairs(commands) do if cmd.op=="flow" then d.flowLimit=cmd.value end end
    d.flow=d.flowLimit
    d.rpm=d.rpm+(d.flow*1.2-d.rpm*.7)/12
  end
  assert(math.abs(d.rpm-c.rpmTarget)<c.rpmTolerance)
  assert(next(learned)==nil)
end)
test("failed writes suspend automatic control",function()
  local a,b=fixture(true); b.write=function() error("link lost") end
  a.enqueue("mode",nil,"auto"); a.tick()
  assert(a.mode=="manual" and a.message:find("link lost"))
end)
test("fuel starvation does not drive rods fully open",function()
  local a,b=fixture(true); b.devices[1].fuel=0
  a.enqueue("mode",nil,"auto"); a.tick(); assert(b.devices[1].rods==80)
end)
test("a demanded passive reactor with no output reports and clears a stall",function()
  local c=config();local b=Demo.new(true);local r=b.devices[1]
  r.active=true;r.rods=50;r.output=0;r.fuel=5000
  local s=C.new()
  for _=1,29 do C.step(s,c,{r},{},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(#s.reactorStalls==0)
  C.step(s,c,{r},{},{energy=50,capacity=100,charge=.5},1,{})
  assert(s.reactorStalls[1] and not s.reactorStalls[1].cooled)
  r.output=100
  for _=1,3 do C.step(s,c,{r},{},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(#s.reactorStalls==0)
end)
test("a demanded cooled reactor with no steam reports a measured stall",function()
  local c=config();local b=Demo.new(false);local r,t=b.devices[1],b.devices[2]
  r.active=true;r.rods=50;r.steam=0;r.fuel=5000
  t.active=true;t.coils=true;t.rpm=c.rpmTarget;t.flow=1000;t.flowLimit=1000
  local s=C.new()
  for _=1,30 do C.step(s,c,{r},{t},{energy=50,capacity=100,charge=.5},1,{}) end
  assert(s.reactorStalls[1] and s.reactorStalls[1].cooled)
  assert(s.reactorStalls[1].output==0 and s.reactorStalls[1].demand>0)
end)
test("long demo runs keep commands within device limits",function()
  for _,direct in ipairs({true,false}) do
    local a,b=fixture(direct); a.enqueue("mode",nil,"auto")
    for i=1,600 do clock=clock+1; a.tick(); assert(a.mode=="auto",a.message) end
    for _,cmd in ipairs(b.writes) do
      if cmd.op=="rods" then assert(cmd.value>=0 and cmd.value<=100) end
      if cmd.op=="flow" then assert(cmd.value>=0 and cmd.value<=2000) end
    end
  end
end)
-- Contract tests using the real adapter, with mocked CC:Tweaked peripherals.
test("local adapter reads zero-indexed rods and clamps commands",function()
  local rods={10,30}; local active=false
  local p={getActive=function() return active end,getEnergyStored=function() return 50 end,
    getEnergyCapacity=function() return 100 end,getEnergyProducedLastTick=function() return 7 end,
    isActivelyCooled=function() return false end,getNumberOfControlRods=function() return 2 end,
    getControlRodLevel=function(i) return rods[i+1] end,getFuelAmount=function() return 5 end,
    getWasteAmount=function() return 1 end,getFuelTemperature=function() return 300 end,
    setAllControlRodLevels=function(n) rods={n,n} end,setActive=function(v) active=v end}
  peripheral={wrap=function() return p end,getNames=function() return {"reactor_0"} end,
    hasType=function(_,t) return t=="extremereactor-reactorComputerPort" end}
  local D=require("lib.devices"); local c=config(); local d=D.poll(c)[1]
  assert(d.rods==20 and d.output==7)
  D.write({name="reactor_0",op="rods",value=105},c); assert(rods[1]==100)
end)
test("mapped storage applies configured conversion",function()
  local c=config(); c.storageMappings.cell={stored="stored",capacity="maximum",scale=.4,identity="bank"}
  peripheral={wrap=function() return {stored=function() return "250" end,maximum=function() return 1000 end} end,
    getNames=function() return {"cell"} end,hasType=function() return false end}
  local d=require("lib.devices").poll(c)[1]
  assert(d.energy==100 and d.capacity==400 and d.identity=="bank")
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
    setAllControlRodLevels=function(n) assert(n==40) end}
  local cube={getEnergy=function() return 4000 end,getMaxEnergy=function() return 8000 end}
  peripheral={getNames=function() return names end,hasType=function(n,t) return kinds[n]==t end,
    wrap=function(n) return kinds[n]=="BigReactors-Reactor" and reactor or cube end,
    getType=function(n) return kinds[n] end,getMethods=function() return {"getEnergy"} end}
  -- A non-default conversion catches accidental hardcoding of the usual J/FE ratio.
  mekanismEnergyHelper={joulesToFE=function(n) return n/4 end}
  local D=require("lib.devices");local c=config();local result=D.poll(c)
  assert(#result==3)
  assert(result[1].kind=="reactor" and result[1].online)
  assert(result[2].kind=="reactor" and result[2].online)
  assert(result[3].kind=="storage" and result[3].online)
  assert(result[3].energy==1000 and result[3].capacity==2000)
  D.write({name=names[2],op="rods",value=40},c)
  local inspected=D.inspect(c);assert(#inspected==5)
  mekanismEnergyHelper=nil
end)
test("Mekanism helper absence is reported without mislabelling Joules as FE",function()
  peripheral={getNames=function() return {"ultimateEnergyCube_0"} end,
    hasType=function(_,t) return t=="ultimateEnergyCube" end,
    wrap=function() return {getEnergy=function() return 1 end,getMaxEnergy=function() return 2 end} end}
  mekanismEnergyHelper=nil
  local d=require("lib.devices").poll(config())[1]
  assert(d.kind=="storage" and not d.online and d.error:find("helper unavailable"))
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
  local c=config();c.storageMappings.ultimateEnergyCube_0={stored="getEnergy",capacity="getMaxEnergy",scale=.25}
  peripheral={getNames=function() return {"ultimateEnergyCube_0"} end,
    hasType=function(_,t) return t=="ultimateEnergyCube" end,
    wrap=function() return {getEnergy=function() return 1 end,getMaxEnergy=function() return 2 end} end}
  local d=require("lib.devices").poll(c)[1]
  assert(d.online and d.energy==.25 and d.capacity==.5 and d.adapter=="mapped")
end)
test("companion rejects wrong owner, expired leases, and replay",function()
  local N=require("lib.network"); local applied=0
  local handler=N.serverHandler(7,config(),{poll=function() return {} end,write=function() applied=applied+1 end})
  assert(handler(8,{id="a",op="poll"})==nil)
  local p=handler(7,{id="a",op="poll"}); assert(p.ok)
  local w={id="b",op="write",data={token=p.data.token,commands={{op="active",value=true}}}}
  assert(handler(7,w).ok and applied==1)
  assert(not handler(7,w).ok and applied==1)
  p=handler(7,{id="c",op="poll"}); w.data.token=p.data.token; clock=clock+6
  assert(not handler(7,w).ok and applied==1)
end)
test("client matches acknowledgements and reports timeout",function()
  local N=require("lib.network"); local sent; local reads=0
  rednet={send=function(peer,msg) sent=msg; return true end,receive=function()
    reads=reads+1
    if reads==1 then return 999,{id=sent.id,reply=true,ok=true,data="wrong peer"} end
    return 7,{id=sent.id,reply=true,ok=true,data="right peer"}
  end}
  assert(N.request(7,"poll",nil,2)=="right peer")
  rednet.receive=function() clock=clock+2; return nil end
  local ok,err=pcall(N.request,7,"poll",nil,2)
  assert(not ok and N.isConnectionError(err) and tostring(err)=="Peer #7: no response")
  local c=config();c.remotePeers={7};peripheral={getNames=function() return {} end}
  local _,errors,retry=require("lib.backend").new(c).poll()
  assert(retry and errors[1]=="Peer #7: no response")
  rednet.receive=function() return 7,{id=sent.id,reply=true,ok=false,error="lib/devices.lua:55: invalid rods"} end
  _,errors,retry=require("lib.backend").new(c).poll()
  assert(not retry and errors[1]=="Peer #7: invalid rods")
  rednet.send=function() return false end
  ok,err=pcall(N.request,7,"poll",nil,2)
  assert(not ok and N.isConnectionError(err) and tostring(err)=="Peer #7: no open modem")
end)
test("backend normalizes remote IDs and sends acknowledged batches",function()
  peripheral={getNames=function() return {} end}
  local N=require("lib.network"); local old=N.request; local sent
  N.request=function(peer,op,data)
    if op=="poll" then return {token="lease",devices={{name="r",kind="reactor",online=true}}} end
    sent=data; return true
  end
  local c=config(); c.remotePeers={7}; local b=require("lib.backend").new(c)
  local list,errors=b.poll(); assert(#errors==0 and list[1].id=="peer:7/r" and list[1].peer==7)
  b.write({{name="r",peer=7,op="active",value=true}})
  assert(sent.token=="lease" and sent.commands[1].op=="active")
  N.request=old
end)
print(string.format("%d tests passed",count))
