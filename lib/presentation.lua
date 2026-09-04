-- Display names and summaries only: never change transport IDs or control policy.
local Util = require("lib.util")
local Presentation = {}

local categories = {
  reactor = "Reactors",
  turbine = "Turbines",
  storage = "Storage",
}

function Presentation.groups(devices)
  local groups = {Reactors = {}, Turbines = {}, Storage = {}}
  for _, device in ipairs(devices) do
    local category = categories[device.kind]
    if category then
      groups[category][#groups[category] + 1] = device
    end
  end
  return groups
end

function Presentation.tabs(groups)
  local tabs = {"Overview"}
  for _, category in ipairs({"Reactors", "Turbines", "Storage"}) do
    if #groups[category] > 0 then
      tabs[#tabs + 1] = category
    end
  end
  return tabs
end

function Presentation.baseName(device)
  if device.label and device.label ~= device.name and device.label ~= device.id then
    return device.label
  end
  if device.kind == "reactor" then
    if device.cooled == nil then
      return "Reactor"
    end
    return device.cooled and "Cooled reactor" or "Passive reactor"
  elseif device.kind == "turbine" then
    return "Turbine"
  end

  local types = table.concat(device.peripheralTypes or {}, " ") .. " " .. (device.name or "")
  for _, tier in ipairs({"basic", "advanced", "elite", "ultimate", "creative"}) do
    if types:find(tier .. "EnergyCube", 1, true) then
      return tier:sub(1, 1):upper() .. tier:sub(2) .. " energy cube"
    end
  end
  if types:find("capacitor_bank", 1, true) then
    return "Capacitor bank"
  end
  if types:find("rftoolspower:", 1, true) then
    return "RFTools powercell"
  end
  return "Energy storage"
end

function Presentation.deviceHeading(device, config)
  local deviceId = device.id or ("local/" .. device.name)
  local alias = config and config.deviceNames and config.deviceNames[deviceId]
  local peripheralName = device.name or deviceId
  if peripheralName == deviceId then
    peripheralName = deviceId:match("[^/]+$") or peripheralName
  end

  local peripheralSides = {
    back = true,
    front = true,
    left = true,
    right = true,
    top = true,
    bottom = true,
  }
  local location
  if peripheralSides[peripheralName] then
    location = peripheralName:sub(1, 1):upper() .. peripheralName:sub(2)
  else
    location = "Port " .. (peripheralName:match("_(%d+)$") or peripheralName)
  end

  local peerId = device.peer or tostring(deviceId):match("^peer:(%d+)/")
  local owner = peerId and ("Peer " .. peerId) or "Local"
  return owner .. " / " .. location, alias or Presentation.baseName(device)
end

function Presentation.title(device, config)
  local location, name = Presentation.deviceHeading(device, config)
  return location .. " - " .. name
end

function Presentation.fitName(name, width)
  if #name <= width then
    return name
  end

  local lowerName = name:lower()
  local energyCubeTier
  for _, candidate in ipairs({"basic", "advanced", "elite", "ultimate", "creative"}) do
    if lowerName == candidate .. " energy cube" then
      energyCubeTier = candidate
      break
    end
  end

  local alternatives = {}
  if energyCubeTier then
    local properTier = energyCubeTier:sub(1, 1):upper() .. energyCubeTier:sub(2)
    alternatives = {
      properTier .. " Cube",
      properTier:sub(1, math.min(3, #properTier)) .. ". Cube",
    }
  elseif lowerName:find("capacitor bank", 1, true) then
    alternatives = {"Capacitor Bank", "Cap. Bank"}
  elseif lowerName:find("powercell", 1, true) then
    alternatives = {"Powercell"}
  end

  for _, candidate in ipairs(alternatives) do
    if #candidate <= width then
      return candidate
    end
  end
  if width <= 3 then
    return name:sub(1, width)
  end
  return name:sub(1, width - 3) .. "..."
end

function Presentation.validName(value)
  assert(type(value) == "string", "Name must be text")
  value = value:match("^%s*(.-)%s*$")
  assert(#value <= 32 and not value:find("%c"),
    "Use at most 32 characters without control characters")
  return value ~= "" and value or nil
end

function Presentation.overview(groups)
  local lines = {}
  local unavailableCount = 0

  local function addLine(line)
    lines[#lines + 1] = line
  end

  if #groups.Reactors > 0 then
    addLine("Reactors: " .. #groups.Reactors)
    local passiveCount = 0
    local cooledCount = 0
    local totalPower = 0
    local totalSteam = 0
    for _, reactor in ipairs(groups.Reactors) do
      if not reactor.online then
        unavailableCount = unavailableCount + 1
      elseif reactor.cooled then
        cooledCount = cooledCount + 1
        totalSteam = totalSteam + (reactor.steam or 0)
      else
        passiveCount = passiveCount + 1
        totalPower = totalPower + (reactor.output or 0)
      end
    end
    if passiveCount > 0 then
      addLine("Reactor output: " .. Util.format(totalPower) .. " FE/t")
    end
    if cooledCount > 0 then
      addLine("Reactor steam: " .. Util.format(totalSteam) .. " mB/t")
    end
    if passiveCount + cooledCount == 0 then
      addLine("Reactor readings unavailable")
    end
  end

  if #groups.Turbines > 0 then
    addLine("Turbines: " .. #groups.Turbines)
    local totalPower = 0
    local onlineCount = 0
    for _, turbine in ipairs(groups.Turbines) do
      if turbine.online then
        onlineCount = onlineCount + 1
        totalPower = totalPower + (turbine.output or 0)
      else
        unavailableCount = unavailableCount + 1
      end
    end
    if onlineCount > 0 then
      addLine("Turbine output: " .. Util.format(totalPower) .. " FE/t")
    else
      addLine("Turbine readings unavailable")
    end
  end

  if #groups.Storage > 0 then
    addLine("Storage devices: " .. #groups.Storage)
    local totalEnergy = 0
    local totalCapacity = 0
    local seenIdentities = {}
    for _, storage in ipairs(groups.Storage) do
      if not storage.online then
        unavailableCount = unavailableCount + 1
      else
        local identity = storage.identity or storage.id or storage.name
        if not seenIdentities[identity] then
          seenIdentities[identity] = true
          totalEnergy = totalEnergy + storage.energy
          totalCapacity = totalCapacity + storage.capacity
        end
      end
    end
    if totalCapacity > 0 then
      addLine(string.format("Local storage: %.1f%%", totalEnergy / totalCapacity * 100))
      addLine(Util.format(totalEnergy) .. " / " .. Util.format(totalCapacity) .. " FE")
    else
      addLine("Storage readings unavailable")
    end
  end

  if #lines == 0 then
    addLine("No local devices connected")
  end
  if unavailableCount > 0 then
    addLine("Unavailable devices: " .. unavailableCount)
  end
  return lines
end

return Presentation
