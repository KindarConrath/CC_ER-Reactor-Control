-- Display names and summaries only: never change transport IDs or control policy.
local U=require('lib.util')
local M={}
local categories={reactor='Reactors',turbine='Turbines',storage='Storage'}
function M.groups(devices)
  local groups={Reactors={},Turbines={},Storage={}}
  for _,d in ipairs(devices) do
    local category=categories[d.kind]
    if category then groups[category][#groups[category]+1]=d end
  end
  return groups
end
function M.tabs(groups)
  local tabs={'Overview'}
  for _,category in ipairs({'Reactors','Turbines','Storage'}) do
    if #groups[category]>0 then tabs[#tabs+1]=category end
  end
  return tabs
end
function M.baseName(d)
  if d.label and d.label~=d.name and d.label~=d.id then return d.label end
  if d.kind=='reactor' then
    if d.cooled==nil then return 'Reactor' end
    return d.cooled and 'Cooled reactor' or 'Passive reactor'
  elseif d.kind=='turbine' then return 'Turbine' end
  local types=table.concat(d.peripheralTypes or {},' ')..' '..(d.name or '')
  for _,tier in ipairs({'basic','advanced','elite','ultimate','creative'}) do
    if types:find(tier..'EnergyCube',1,true) then
      return tier:sub(1,1):upper()..tier:sub(2)..' energy cube'
    end
  end
  if types:find('capacitor_bank',1,true) then return 'Capacitor bank' end
  if types:find('rftoolspower:',1,true) then return 'RFTools powercell' end
  return 'Energy storage'
end
function M.deviceHeading(d,c)
  local id=d.id or ('local/'..d.name)
  local alias=c and c.deviceNames and c.deviceNames[id]
  local name=d.name or id
  if name==id then name=id:match('[^/]+$') or name end
  local sides={back=true,front=true,left=true,right=true,top=true,bottom=true}
  local location=sides[name] and (name:sub(1,1):upper()..name:sub(2)) or ('Port '..(name:match('_(%d+)$') or name))
  local peer=d.peer or tostring(id):match('^peer:(%d+)/')
  local owner=peer and ('Peer '..peer) or 'Local'
  return owner..' / '..location,alias or M.baseName(d)
end
function M.title(d,c)
  local location,name=M.deviceHeading(d,c)
  return location..' - '..name
end
function M.fitName(name,width)
  if #name<=width then return name end
  local lower=name:lower()
  local tier
  for _,candidate in ipairs({'basic','advanced','elite','ultimate','creative'}) do
    if lower==candidate..' energy cube' then tier=candidate break end
  end
  local alternatives={}
  if tier then
    local proper=tier:sub(1,1):upper()..tier:sub(2)
    alternatives={proper..' Cube',proper:sub(1,math.min(3,#proper))..'. Cube'}
  elseif lower:find('capacitor bank',1,true) then
    alternatives={'Capacitor Bank','Cap. Bank'}
  elseif lower:find('powercell',1,true) then
    alternatives={'Powercell'}
  end
  for _,candidate in ipairs(alternatives) do
    if #candidate<=width then return candidate end
  end
  if width<=3 then return name:sub(1,width) end
  return name:sub(1,width-3)..'...'
end
function M.validName(value)
  assert(type(value)=='string','Name must be text')
  value=value:match('^%s*(.-)%s*$')
  assert(#value<=32 and not value:find('%c'),'Use at most 32 characters without control characters')
  return value~='' and value or nil
end
function M.overview(groups)
  local lines={}
  local function add(s) lines[#lines+1]=s end
  local offline=0
  if #groups.Reactors>0 then
    add('Reactors: '..#groups.Reactors)
    local passive,cooled,power,steam=0,0,0,0
    for _,d in ipairs(groups.Reactors) do
      if not d.online then offline=offline+1
      elseif d.cooled then cooled=cooled+1;steam=steam+(d.steam or 0)
      else passive=passive+1;power=power+(d.output or 0) end
    end
    if passive>0 then add('Reactor output: '..U.format(power)..' FE/t') end
    if cooled>0 then add('Reactor steam: '..U.format(steam)..' mB/t') end
    if passive+cooled==0 then add('Reactor readings unavailable') end
  end
  if #groups.Turbines>0 then
    add('Turbines: '..#groups.Turbines)
    local power,online=0,0
    for _,d in ipairs(groups.Turbines) do
      if d.online then online=online+1;power=power+(d.output or 0) else offline=offline+1 end
    end
    add(online>0 and ('Turbine output: '..U.format(power)..' FE/t') or 'Turbine readings unavailable')
  end
  if #groups.Storage>0 then
    add('Storage devices: '..#groups.Storage)
    local energy,capacity,seen=0,0,{}
    for _,d in ipairs(groups.Storage) do
      if not d.online then offline=offline+1
      else
        local id=d.identity or d.id or d.name
        if not seen[id] then seen[id]=true;energy=energy+d.energy;capacity=capacity+d.capacity end
      end
    end
    if capacity>0 then
      add(string.format('Local storage: %.1f%%',energy/capacity*100))
      add(U.format(energy)..' / '..U.format(capacity)..' FE')
    else add('Storage readings unavailable') end
  end
  if #lines==0 then add('No local devices connected') end
  if offline>0 then add('Unavailable devices: '..offline) end
  return lines
end
return M
