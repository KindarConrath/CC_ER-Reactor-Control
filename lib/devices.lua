-- Extreme Reactors 1.21.1 adapter. No Basalt or networking dependencies.
local Util = require("lib.util")
local Devices = {}

local DEVICE_TYPES = {
  reactor = {"BigReactors-Reactor", "extremereactor-reactorComputerPort"},
  turbine = {"BigReactors-Turbine", "extremereactor-turbineComputerPort"},
}

local ENERGIZER_TYPES = {
  "BigReactors-Energizer",
  "extremereactor-energizerComputerPort",
}

local MEKANISM_CUBE_TYPES = {
  "basicEnergyCube",
  "advancedEnergyCube",
  "eliteEnergyCube",
  "ultimateEnergyCube",
  "creativeEnergyCube",
}

local MEKANISM_INDUCTION_PORT_TYPE = "inductionPort"
local INTEGRATED_DYNAMICS_BATTERY_TYPE = "integrateddynamics:energy_battery"
local DRACONIC_ENERGY_STORAGE_TYPE = "draconic_rf_storage"

local function hasAnyType(name, peripheralTypes)
  for _, peripheralType in ipairs(peripheralTypes) do
    if peripheral.hasType(name, peripheralType) then
      return true
    end
  end
  return false
end

local function isEnergyCube(name)
  return hasAnyType(name, MEKANISM_CUBE_TYPES)
end

local function isInductionPort(name)
  return peripheral.hasType(name, MEKANISM_INDUCTION_PORT_TYPE)
end

local function isEnergizer(name)
  return hasAnyType(name, ENERGIZER_TYPES)
end

local function isIntegratedDynamicsBattery(name)
  return peripheral.hasType(name, INTEGRATED_DYNAMICS_BATTERY_TYPE)
end

local function isDraconicEnergyStorage(name)
  return peripheral.hasType(name, DRACONIC_ENERGY_STORAGE_TYPE)
end

local function classify(name, config)
  for kind, aliases in pairs(DEVICE_TYPES) do
    if hasAnyType(name, aliases) then
      return kind
    end
  end
  if config.storageMappings[name]
      or isEnergyCube(name)
      or isInductionPort(name)
      or isEnergizer(name)
      or isDraconicEnergyStorage(name)
      or peripheral.hasType(name, "energy_storage") then
    return "storage"
  end
end

local function numberMethod(peripheralDevice, method, ...)
  local call = assert(peripheralDevice[method], "Missing " .. method)
  return Util.number(call(...))
end

local function readStorage(device, peripheralDevice, config)
  local mapping = config.storageMappings[device.name]
  local energyCube = isEnergyCube(device.name)
  local inductionPort = isInductionPort(device.name)
  local energizer = isEnergizer(device.name)
  if not mapping and (energyCube or inductionPort) then
    assert(type(mekanismEnergyHelper) == "table"
        and type(mekanismEnergyHelper.joulesToFE) == "function",
      "Mekanism energy helper unavailable; configure an explicit storage mapping")
    if inductionPort then
      assert(peripheralDevice.isFormed(), "Induction matrix is not formed")
    end
    -- Native Mekanism methods report Joules, independent of its GUI display unit.
    -- Use the installed mod's conversion helper; never assume the default ratio.
    device.energy = Util.number(mekanismEnergyHelper.joulesToFE(
      numberMethod(peripheralDevice, "getEnergy")))
    device.capacity = Util.number(mekanismEnergyHelper.joulesToFE(
      numberMethod(peripheralDevice, "getMaxEnergy")))
    device.identity = device.name
    device.adapter = inductionPort and "Mekanism induction matrix" or "Mekanism energy cube"
    return
  end


  if not mapping and energizer then
    assert(peripheralDevice.mbIsAssembled(), "Energizer is not assembled")
    device.energy = numberMethod(peripheralDevice, "getEnergyStored")
    device.capacity = numberMethod(peripheralDevice, "getEnergyCapacity")
    device.identity = device.name
    device.adapter = "Extreme Reactors energizer"
    return
  end

  if not mapping and isDraconicEnergyStorage(device.name) then
    device.energy = numberMethod(peripheralDevice, "getEnergyStored")
    device.capacity = numberMethod(peripheralDevice, "getMaxEnergyStored")
    device.identity = device.name
    device.adapter = "Draconic Evolution energy core"
    return
  end

  mapping = mapping or {
    stored = "getEnergy",
    capacity = "getEnergyCapacity",
    scale = 1,
  }
  assert(type(mapping.scale) == "number" and mapping.scale > 0,
    "Storage mapping needs positive scale")
  device.energy = numberMethod(peripheralDevice, mapping.stored) * mapping.scale
  device.capacity = numberMethod(peripheralDevice, mapping.capacity) * mapping.scale
  device.identity = mapping.identity or device.name
  device.label = mapping.label or device.name
  if config.storageMappings[device.name] then
    device.adapter = "mapped"
  elseif isIntegratedDynamicsBattery(device.name) then
    device.adapter = "Integrated Dynamics energy battery"
  else
    device.adapter = "generic FE"
  end
end

local function readGenerator(device, peripheralDevice)
  if peripheralDevice.getConnected then
    assert(peripheralDevice.getConnected(), "Multiblock not connected")
  end
  device.active = peripheralDevice.getActive()
  assert(type(device.active) == "boolean", "Invalid active state")
  device.energy = numberMethod(peripheralDevice, "getEnergyStored")
  device.capacity = numberMethod(peripheralDevice, "getEnergyCapacity")
  device.output = numberMethod(peripheralDevice, "getEnergyProducedLastTick")
end

local function readReactor(device, peripheralDevice)
  device.cooled = peripheralDevice.isActivelyCooled()
  assert(type(device.cooled) == "boolean", "Invalid cooling mode")

  local rodCount = numberMethod(peripheralDevice, "getNumberOfControlRods")
  assert(rodCount > 0, "No control rods")
  local totalInsertion = 0
  for index = 0, rodCount - 1 do
    totalInsertion = totalInsertion + numberMethod(peripheralDevice, "getControlRodLevel", index)
  end
  device.rods = totalInsertion / rodCount
  device.fuel = numberMethod(peripheralDevice, "getFuelAmount")
  device.waste = numberMethod(peripheralDevice, "getWasteAmount")
  device.temperature = numberMethod(peripheralDevice, "getFuelTemperature")

  if device.cooled then
    device.steam = numberMethod(peripheralDevice, "getHotFluidProducedLastTick")
    device.hot = numberMethod(peripheralDevice, "getHotFluidAmount")
    device.hotCapacity = numberMethod(peripheralDevice, "getHotFluidAmountMax")
  end
end

local function readTurbine(device, peripheralDevice)
  device.rpm = numberMethod(peripheralDevice, "getRotorSpeed")
  device.flow = numberMethod(peripheralDevice, "getFluidFlowRate")
  device.flowLimit = numberMethod(peripheralDevice, "getFluidFlowRateMax")
  device.flowMax = numberMethod(peripheralDevice, "getFluidFlowRateMaxMax")
  device.coils = peripheralDevice.getInductorEngaged()
  assert(type(device.coils) == "boolean", "Invalid coil state")
end

function Devices.read(name, kind, config)
  local peripheralDevice = assert(peripheral.wrap(name), "Disconnected: " .. name)
  local device = {
    name = name,
    kind = kind,
    label = name,
    online = true,
    peripheralTypes = peripheral.getType and {peripheral.getType(name)} or {},
  }

  if kind == "storage" then
    readStorage(device, peripheralDevice, config)
  else
    readGenerator(device, peripheralDevice)
    if kind == "reactor" then
      readReactor(device, peripheralDevice)
    else
      readTurbine(device, peripheralDevice)
    end
  end

  assert(device.energy >= 0 and device.capacity >= 0, "Invalid energy readings")
  if kind == "storage" then
    assert(device.capacity > 0 and device.energy <= device.capacity * 1.001,
      "Invalid storage capacity")
  end
  return device
end

function Devices.poll(config)
  local devices = {}
  for _, name in ipairs(peripheral.getNames()) do
    local kind = classify(name, config)
    if kind then
      local ok, device = pcall(Devices.read, name, kind, config)
      devices[#devices + 1] = ok and device or {
        name = name,
        kind = kind,
        label = name,
        online = false,
        error = tostring(device),
      }
    end
  end
  table.sort(devices, function(leftDevice, rightDevice)
    return leftDevice.name < rightDevice.name
  end)
  return devices
end

function Devices.inspect(config)
  local result = {}
  for _, name in ipairs(peripheral.getNames()) do
    local entry = {
      name = name,
      types = {peripheral.getType(name)},
      kind = classify(name, config) or "unrecognized",
      methods = peripheral.getMethods(name) or {},
    }
    table.sort(entry.methods)
    result[#result + 1] = entry
  end
  table.sort(result, function(leftEntry, rightEntry)
    return leftEntry.name < rightEntry.name
  end)
  return result
end

function Devices.write(command, config)
  assert(type(command) == "table" and type(command.name) == "string", "Invalid command")
  local kind = classify(command.name, config)
  assert(kind == "reactor" or kind == "turbine", "Not a controlled device")
  local peripheralDevice = assert(peripheral.wrap(command.name), "Disconnected")
  local operation, value = command.op, command.value

  if operation == "active" then
    assert(type(value) == "boolean")
    peripheralDevice.setActive(value)
  elseif operation == "rods" and kind == "reactor" then
    local insertion = math.floor(Util.clamp(Util.number(value), 0, 100) + 0.5)
    peripheralDevice.setAllControlRodLevels(insertion)
  elseif operation == "flow" and kind == "turbine" then
    local maximum = peripheralDevice.getFluidFlowRateMaxMax()
    local flow = math.floor(Util.clamp(Util.number(value), 0, maximum) + 0.5)
    peripheralDevice.setFluidFlowRateMax(flow)
  elseif operation == "coils" and kind == "turbine" then
    assert(type(value) == "boolean")
    peripheralDevice.setInductorEngaged(value)
  else
    error("Unsupported device command: " .. tostring(operation))
  end
end

return Devices
