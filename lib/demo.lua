-- Deliberately approximate dynamics for UI/regression tests, not a physics model.
local U=require("lib.util")
local M={}
function M.new(direct)
  local list={}; local writes={}
  local function reactor(n)
    return {id="demo/reactor"..n,name="reactor"..n,label="Demo reactor "..n,kind="reactor",online=true,
      active=false,cooled=not direct,rods=80,fuel=5000,waste=100,temperature=400,
      energy=5000000,capacity=10000000,output=0,steam=0,hot=10000,hotCapacity=20000}
  end
  list[1]=reactor(1)
  if direct then list[2]=reactor(2)
  else
    for i=1,2 do list[#list+1]={id="demo/turbine"..i,name="turbine"..i,label="Demo turbine "..i,
      kind="turbine",online=true,active=false,energy=5000000,capacity=10000000,output=0,
      rpm=0,flow=0,flowLimit=0,flowMax=2000,coils=false} end
  end
  list[#list+1]={id="demo/battery",name="battery",label="Demo battery",kind="storage",online=true,
    identity="demo-battery",adapter="simulated FE",energy=650000000,capacity=1000000000}
  local b={devices=list,writes=writes,time=0}
  function b.poll() return U.copy(list),{} end
  function b.write(commands)
    for _,cmd in ipairs(commands) do
      writes[#writes+1]=U.copy(cmd)
      for _,d in ipairs(list) do if d.name==cmd.name then
        local field=({rods="rods",active="active",flow="flowLimit",coils="coils"})[cmd.op]
        assert(field,"Bad demo command"); d[field]=cmd.value
      end end
    end
  end
  function b.advance(dt)
    dt=math.min(dt,3); b.time=b.time+dt
    local steam,output=0,0
    for _,d in ipairs(list) do if d.kind=="reactor" then
      local supply=d.active and (100-d.rods)/100 or 0
      d.steam=d.steam+(supply*4000-d.steam)*math.min(dt/4,1)
      d.output=direct and supply*80000 or 0; steam=steam+d.steam; output=output+d.output
    end end
    local wanted=0
    for _,d in ipairs(list) do if d.kind=="turbine" and d.active then wanted=wanted+d.flowLimit end end
    for _,d in ipairs(list) do if d.kind=="turbine" then
      d.flow=d.active and d.flowLimit*math.min(1,steam/math.max(1,wanted)) or 0
      d.rpm=math.max(0,d.rpm+(d.flow*1.2-d.rpm*(d.coils and 0.7 or 0.03))*dt/12)
      d.output=d.coils and d.rpm*25 or 0; output=output+d.output
    end end
    local battery=list[#list]; local load=45000+20000*math.sin(b.time/80)
    battery.energy=U.clamp(battery.energy+(output-load)*20*dt,0,battery.capacity)
    for _,d in ipairs(list) do if d.kind~="storage" then d.energy=battery.energy/battery.capacity*d.capacity end end
    list[1].hot=U.clamp(list[1].hot+(steam-wanted)*20*dt,0,list[1].hotCapacity)
  end
  return b
end
return M
