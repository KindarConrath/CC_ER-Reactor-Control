local Util = require("lib.util")
local Calibration = require("lib.calibration")
local Control = {}
local STEAM_SHORTAGE_SECONDS = 10
local UNCALIBRATED_GRACE_SECONDS = 30
local STEAM_RECOVERY_SECONDS = 3
local TURBINE_LIMIT_SECONDS = 10
local TURBINE_RECOVERY_SECONDS = 3
local CAPACITY_STABLE_SECONDS = 10
local REACTOR_STALL_SECONDS = 30
local REACTOR_STALL_RECOVERY_SECONDS = 3

function Control.new()
  return {reactors = {}, turbines = {}, standby = false}
end

local function addCommand(commands, device, operation, value)
  commands[#commands + 1] = {
    id = device.id,
    name = device.name,
    peer = device.peer,
    op = operation,
    value = value,
  }
end

local function setRods(commands, reactor, state, insertion)
  state.rods = Util.clamp(insertion, 0, 100)
  local rounded = math.floor(state.rods + 0.5)
  if rounded ~= math.floor(reactor.rods + 0.5) then
    addCommand(commands, reactor, "rods", rounded)
  end
end

function Control.topology(reactors, turbines)
  if #reactors == 0 then
    return nil, "No reactors selected"
  end
  for _, reactor in ipairs(reactors) do
    if not reactor.online then
      return nil, reactor.label .. ": " .. tostring(reactor.error)
    end
  end
  for _, turbine in ipairs(turbines) do
    if not turbine.online then
      return nil, turbine.label .. ": " .. tostring(turbine.error)
    end
  end
  if #turbines > 0 then
    if #reactors ~= 1 or not reactors[1].cooled then
      return nil, "Turbine mode requires exactly one actively cooled reactor"
    end
    return "turbine"
  end
  for _, reactor in ipairs(reactors) do
    if reactor.cooled then
      return nil, "Actively cooled reactor needs at least one turbine"
    end
  end
  return "direct"
end

function Control.storage(devices, selectedIds, reactors, turbines)
  local sources, byId = {}, {}
  for _, device in ipairs(devices) do
    byId[device.id] = device
  end
  if #selectedIds > 0 then
    for _, id in ipairs(selectedIds) do
      local device = byId[id]
      if not device or not device.online then
        return nil, "Storage unavailable: " .. id
      end
      if device.kind ~= "storage" then
        return nil, "Selected device is not storage: " .. id
      end
      sources[#sources + 1] = device
    end
  else
    sources = #turbines > 0 and turbines or reactors
  end

  local energy, capacity, seen = 0, 0, {}
  for _, device in ipairs(sources) do
    if not device.online then
      return nil, "Buffer unavailable: " .. device.id
    end
    local identity = device.identity or device.id
    if not seen[identity] then
      seen[identity] = true
      energy = energy + device.energy
      capacity = capacity + device.capacity
    end
  end
  if capacity <= 0 then
    return nil, "No readable energy capacity"
  end
  return {
    energy = energy,
    capacity = capacity,
    charge = Util.clamp(energy / capacity, 0, 1),
    source = #selectedIds > 0 and "Selected storage" or "Generator buffers",
  }
end

local function updateStorageTrend(state, config, storage, elapsed)
  if storage.charge >= config.standbyAbove then
    state.standby = true
  elseif storage.charge <= config.generateBelow then
    state.standby = false
  end

  local net = 0
  if state.previousEnergy and state.previousCapacity == storage.capacity then
    net = (storage.energy - state.previousEnergy) / elapsed / storage.capacity
  end
  state.net = (state.net or net) * 0.7 + net * 0.3

  -- The faster signal catches surplus generation after a sudden load drop.
  local fastWeight = 0.3 ^ elapsed
  if state.previousCapacity ~= storage.capacity then
    state.brakingNet = net
  end
  state.brakingNet = (state.brakingNet or net) * fastWeight + net * (1 - fastWeight)
  state.previousEnergy = storage.energy
  state.previousCapacity = storage.capacity
end

local function calibrationPoint(calibration, turbine, target, phase)
  local entry = calibration[turbine.id]
  return entry and entry.rpm == target and entry[phase] or nil
end

local function capacitySignature(config, turbines, calibration)
  local values = {}
  for _, turbine in ipairs(turbines) do
    local point = calibrationPoint(calibration, turbine, config.rpmTarget, "generating")
    if not point then return nil end
    values[#values + 1] = turbine.id .. "=" .. string.format("%.3f", point.flow)
  end
  table.sort(values)
  return config.rpmTarget .. "|" .. table.concat(values, "|")
end

local function nextCalibrationTarget(plant, config, turbines, calibration)
  for index, turbine in ipairs(turbines) do
    if not calibrationPoint(calibration, turbine, config.rpmTarget, "generating") then
      plant.calibrationTarget = {id = turbine.id, index = index, count = #turbines}
      return turbine.id
    end
  end
  plant.calibrationTarget = nil
  local signature = capacitySignature(config, turbines, calibration)
  if not plant.capacityCheck then
    plant.capacityCheck = {
      active = true, stable = 0, shortage = 0, status = "starting", signature = signature,
    }
  end
  return nil
end

function Control.beginCalibration(state, turbines)
  assert(#turbines > 0, "No turbines available to calibrate")
  state.calibrationSession = {active = true, points = {}}
  state.calibrationTarget = nil
  state.capacityCheck = nil
  state.turbines = {}
end

local function regulateTurbine(commands, plant, config, turbine, elapsed, calibration,
    generatingWanted, learn)
  local state = plant.turbines[turbine.id] or {
    flow = turbine.flowLimit,
    previousRPM = turbine.rpm,
  }
  plant.turbines[turbine.id] = state
  local target = config.rpmTarget
  local coils = generatingWanted and (turbine.coils or turbine.rpm >= target * 0.95)
  local phase = not generatingWanted and "standby" or (coils and "generating" or "spinup")
  local saved = calibration[turbine.id]
  if state.state ~= phase then
    local learned = saved and saved.rpm == target and saved[phase]
    if learned then
      state.flow = learned.flow
    elseif phase == "standby" then
      state.flow = math.min(state.flow, turbine.flowMax * 0.05)
    elseif phase == "generating" then
      state.flow = math.max(state.flow, turbine.flowMax * 0.5)
    end
    state.state = phase
  end

  local rpmError = target - turbine.rpm
  local acceleration = (turbine.rpm - state.previousRPM) / elapsed
  state.previousRPM = turbine.rpm
  local adjustment = (rpmError * 0.5 - acceleration * 5) * elapsed
  if math.abs(rpmError) < config.rpmTolerance and math.abs(acceleration) < 1 then
    adjustment = 0
  end
  state.flow = Util.clamp(
    state.flow + Util.clamp(adjustment, -config.flowRate * elapsed, config.flowRate * elapsed),
    0, turbine.flowMax
  )
  if turbine.rpm > target + math.max(100, target * 0.08) then
    state.flow = 0
  end
  if not turbine.active then
    addCommand(commands, turbine, "active", true)
  end
  -- Reduce steam before removing the generating load.
  addCommand(commands, turbine, "flow", math.floor(state.flow + 0.5))
  if turbine.coils ~= coils then
    addCommand(commands, turbine, "coils", coils)
  end
  state.status = phase
  state.acceleration = acceleration

  local learned = false
  if learn and phase == "generating" then
    learned = Calibration.update(state, config, turbine, phase, acceleration, elapsed, calibration)
  else
    state.calibration = nil
  end
  return state.flow, learned
end

local function updateTurbineLimits(plant, config, turbines, elapsed)
  plant.turbineLimits = {}
  for _, turbine in ipairs(turbines) do
    local state = plant.turbines[turbine.id]
    local nearMaximum = state and state.flow >= turbine.flowMax - math.max(5, turbine.flowMax * 0.01)
      and turbine.flow >= turbine.flowMax - math.max(5, turbine.flowMax * 0.05)
    local limited = state and state.status == "generating" and turbine.coils and nearMaximum
      and turbine.rpm < config.rpmTarget - config.rpmTolerance and state.acceleration < -0.5
    if limited then
      state.limitRecovery = 0
      state.limitSeconds = (state.limitSeconds or 0) + elapsed
      if state.limitSeconds >= TURBINE_LIMIT_SECONDS then
        state.limitWarning = {id = turbine.id, rpm = turbine.rpm, flow = turbine.flow}
      end
    else
      state.limitSeconds = 0
      if state and state.limitWarning then
        state.limitRecovery = (state.limitRecovery or 0) + elapsed
        if state.status ~= "generating" or state.limitRecovery >= TURBINE_RECOVERY_SECONDS then
          state.limitWarning = nil
          state.limitRecovery = 0
        end
      end
    end
    if state and state.limitWarning then
      plant.turbineLimits[#plant.turbineLimits + 1] = state.limitWarning
    end
  end
end

local function passiveDemand(plant, config, charge)
  local demand = (config.targetCharge - charge) - plant.net * 30
  local brakingSeconds = config.passiveBrakingSeconds or 90
  if brakingSeconds > 30 then
    -- Blend in extra anticipation over the final percentage point below target.
    local proximity = Util.clamp((charge - config.targetCharge + 0.01) / 0.01, 0, 1)
    local rising = math.max(plant.net, plant.brakingNet)
    if proximity > 0 and rising > 0 then
      local horizon = 30 + (brakingSeconds - 30) * proximity
      demand = math.min(demand, (config.targetCharge - charge) - rising * horizon)
    end
  end
  return demand
end

local function rodRate(config, reactor, demand, charge)
  local rate = Util.clamp(demand * 8, -config.rodRate, config.rodRate)
  if not reactor.cooled and demand > 0 then
    local deficit = math.max(0, config.targetCharge - charge)
    local urgency = Util.clamp(math.min(deficit, demand) / config.targetCharge, 0, 1)
    local maximum = config.passiveMaxRodWithdrawalRate or math.max(config.rodRate, 8)
    local limit = config.rodRate + (maximum - config.rodRate) * urgency ^ 2
    rate = math.min(demand * 8 * (limit / config.rodRate), limit)
  elseif not reactor.cooled and demand < 0 then
    local maximum = config.passiveMaxRodInsertionRate or math.max(config.rodRate, 8)
    local gain = 8 + (maximum - config.rodRate) / (1 - config.targetCharge)
    rate = -math.min(-demand * gain, maximum)
  end
  return rate
end

local function regulateReactor(commands, plant, config, reactor, storage, totalSteam, elapsed)
  local state = plant.reactors[reactor.id] or {rods = reactor.rods}
  plant.reactors[reactor.id] = state
  local demand
  if reactor.cooled then
    local fill = reactor.hotCapacity > 0 and reactor.hot / reactor.hotCapacity or 0
    demand = (totalSteam - reactor.steam) / math.max(totalSteam, reactor.steam, 100)
      + (0.5 - fill) * 0.6
  else
    demand = passiveDemand(plant, config, storage.charge)
  end
  state.demand = demand

  if not reactor.cooled and plant.standby then
    setRods(commands, reactor, state, 100)
    if reactor.active then
      addCommand(commands, reactor, "active", false)
    end
  elseif reactor.fuel <= 0 then
    state.status = "No fuel"
  else
    state.status = "Regulating"
    local rate = rodRate(config, reactor, demand, storage.charge)
    setRods(commands, reactor, state, state.rods - rate * elapsed)
    if not reactor.active then
      addCommand(commands, reactor, "active", true)
    end
  end
end

local function updateReactorStalls(plant, reactors, totalSteam, elapsed)
  plant.reactorStalls = {}
  for _, reactor in ipairs(reactors) do
    local state = plant.reactors[reactor.id]
    local output = (reactor.cooled and reactor.steam or reactor.output) or 0
    local demandExists = reactor.cooled and totalSteam > 100
      or (not reactor.cooled and not plant.standby and state and state.demand > 0.01)
    local askedToRun = reactor.fuel <= 0 or (reactor.active and reactor.rods <= 90
      and state and state.rods <= 90)
    local stalled = demandExists and askedToRun and output <= 1
    if stalled then
      state.stallRecovery = 0
      state.stallSeconds = (state.stallSeconds or 0) + elapsed
      if state.stallSeconds >= REACTOR_STALL_SECONDS then
        state.stallWarning = {
          id = reactor.id,
          output = output,
          demand = reactor.cooled and totalSteam or nil,
          cooled = reactor.cooled,
        }
      end
    else
      state.stallSeconds = 0
      if state and state.stallWarning then
        state.stallRecovery = (state.stallRecovery or 0) + elapsed
        if not demandExists or state.stallRecovery >= REACTOR_STALL_RECOVERY_SECONDS then
          state.stallWarning = nil
          state.stallRecovery = 0
        end
      end
    end
    if state and state.stallWarning then
      plant.reactorStalls[#plant.reactorStalls + 1] = state.stallWarning
    end
  end
end

local function clearSteamShortage(plant)
  plant.steamShortageSeconds = 0
  plant.steamRecoverySeconds = 0
  plant.steamShortage = nil
end

local function updateSteamCapacity(plant, config, reactors, turbines, totalSteam, elapsed, calibration)
  if plant.standby or #reactors ~= 1 or #turbines == 0 then
    plant.generatingSeconds = 0
    clearSteamShortage(plant)
    return
  end

  local allGenerating, allCalibrated = true, true
  for _, turbine in ipairs(turbines) do
    local control = plant.turbines[turbine.id]
    allGenerating = allGenerating and control and control.status == "generating" or false
    local entry = calibration[turbine.id]
    allCalibrated = allCalibrated and entry and entry.rpm == config.rpmTarget
      and entry.generating ~= nil or false
  end
  if allGenerating then
    plant.generatingSeconds = (plant.generatingSeconds or 0) + elapsed
  else
    plant.generatingSeconds = 0
    clearSteamShortage(plant)
    return
  end

  local reactor = reactors[1]
  local control = plant.reactors[reactor.id]
  local deficit = totalSteam - reactor.steam
  local tolerance = math.max(100, totalSteam * 0.05)
  local fullyOpen = control and control.rods <= 1 and reactor.rods <= 1
  local atCapacity = fullyOpen or reactor.fuel <= 0
  local graceComplete = allCalibrated or plant.generatingSeconds >= UNCALIBRATED_GRACE_SECONDS
  local insufficient = atCapacity and deficit > tolerance and graceComplete
  if insufficient then
    plant.steamRecoverySeconds = 0
    plant.steamShortageSeconds = (plant.steamShortageSeconds or 0) + elapsed
    if plant.steamShortageSeconds >= STEAM_SHORTAGE_SECONDS then
      plant.steamShortage = {
        demand = totalSteam,
        output = reactor.steam,
        deficit = deficit,
        calibrated = allCalibrated,
      }
    end
  else
    plant.steamShortageSeconds = 0
    if plant.steamShortage then
      plant.steamRecoverySeconds = (plant.steamRecoverySeconds or 0) + elapsed
      if plant.steamRecoverySeconds >= STEAM_RECOVERY_SECONDS then
        plant.steamShortage = nil
        plant.steamRecoverySeconds = 0
      end
    end
  end
end

local function updateCapacityCheck(plant, config, reactors, turbines, calibration, elapsed)
  local check = plant.capacityCheck
  if not (check and check.active) then
    return false
  end
  if #reactors ~= 1 then
    check.active = false
    check.status = "unavailable"
    return false
  end

  local required = 0
  local stable = true
  for _, turbine in ipairs(turbines) do
    local point = calibrationPoint(calibration, turbine, config.rpmTarget, "generating")
    local control = plant.turbines[turbine.id]
    if not point then
      return false
    end
    required = required + point.flow
    stable = stable and control and control.status == "generating" and turbine.coils
      and math.abs(turbine.rpm - config.rpmTarget) <= config.rpmTolerance
      and math.abs(control.acceleration or math.huge) < 2
      and math.abs(turbine.flow - control.flow) <= math.max(5, control.flow * 0.05)
  end

  local reactor = reactors[1]
  local reactorControl = plant.reactors[reactor.id]
  local tolerance = math.max(100, required * 0.05)
  local enoughSteam = reactor.steam >= required - tolerance
  check.required = required
  check.output = reactor.steam
  if stable and enoughSteam then
    check.shortage = 0
    check.stable = check.stable + elapsed
    check.status = "verifying"
    if check.stable >= CAPACITY_STABLE_SECONDS then
      check.active = false
      check.status = "passed"
      calibration._capacity = {
        signature = capacitySignature(config, turbines, calibration) or check.signature,
        status = check.status,
        required = check.required, output = check.output,
      }
      return true
    end
  else
    check.stable = 0
    check.status = "waiting"
    local fullyOpen = reactorControl and reactorControl.rods <= 1 and reactor.rods <= 1
    if fullyOpen and reactor.steam < required - tolerance then
      check.shortage = check.shortage + elapsed
      if check.shortage >= STEAM_SHORTAGE_SECONDS then
        check.active = false
        check.status = "failed"
        calibration._capacity = {
          signature = capacitySignature(config, turbines, calibration) or check.signature,
          status = check.status,
          required = check.required, output = check.output,
        }
        return true
      end
    else
      check.shortage = 0
    end
  end
  return false
end

function Control.step(state, config, reactors, turbines, storage, elapsed, calibration)
  local commands = {}
  elapsed = Util.clamp(elapsed, 0.1, 3)
  updateStorageTrend(state, config, storage, elapsed)

  local session = state.calibrationSession
  local calibrating = session and session.active and #turbines > 0
  local workingCalibration = calibrating and session.points or calibration
  local calibrationId
  if calibrating then
    calibrationId = nextCalibrationTarget(state, config, turbines, workingCalibration)
  end
  local checkingCapacity = state.capacityCheck and state.capacityCheck.active

  local totalSteam = 0
  for _, turbine in ipairs(turbines) do
    local generatingWanted
    if calibrationId then
      generatingWanted = turbine.id == calibrationId
    elseif checkingCapacity then
      generatingWanted = true
    else
      generatingWanted = not state.standby
    end
    local learn = calibrating and calibrationId == turbine.id
    local flow = regulateTurbine(commands, state, config, turbine, elapsed,
      workingCalibration, generatingWanted, learn)
    totalSteam = totalSteam + flow
  end
  for _, reactor in ipairs(reactors) do
    regulateReactor(commands, state, config, reactor, storage, totalSteam, elapsed)
  end
  updateReactorStalls(state, reactors, totalSteam, elapsed)
  updateSteamCapacity(state, config, reactors, turbines, totalSteam, elapsed, calibration)
  updateTurbineLimits(state, config, turbines, elapsed)
  local capacityChanged = updateCapacityCheck(state, config, reactors, turbines,
    workingCalibration, elapsed)
  if calibrating and capacityChanged and state.capacityCheck and not state.capacityCheck.active then
    for _, turbine in ipairs(turbines) do
      calibration[turbine.id] = workingCalibration[turbine.id]
    end
    calibration._capacity = workingCalibration._capacity
    session.active = false
    session.status = state.capacityCheck.status
    state.calibrationTarget = nil
    return commands, true
  end
  return commands, false
end

return Control
