package.path = "./?.lua;" .. package.path
local Control = require("lib.control")
local Demo = require("lib.demo")

local function fixture()
  local config = dofile("config.lua")
  local devices = Demo.new(false).devices
  local reactor = devices[1]
  local turbines = {devices[2], devices[3]}
  reactor.active, reactor.rods = true, 20
  for _, turbine in ipairs(turbines) do
    turbine.active = true
    turbine.coils = false
    turbine.rpm = config.rpmTarget
    turbine.flow = 1000
    turbine.flowLimit = 1000
    turbine.output = 0
  end
  return config, reactor, turbines
end

local function apply(commands, turbines, reactor)
  for _, command in ipairs(commands) do
    if command.id == reactor.id and command.op == "rods" then
      reactor.rods = command.value
    end
    for _, turbine in ipairs(turbines) do
      if command.id == turbine.id then
        if command.op == "flow" then turbine.flowLimit = command.value end
        if command.op == "coils" then turbine.coils = command.value end
        if command.op == "active" then turbine.active = command.value end
      end
    end
  end
  for _, turbine in ipairs(turbines) do
    turbine.flow = turbine.flowLimit
    turbine.output = turbine.coils and 40000 or 0
  end
end

local function tick(state, config, reactor, turbines, points, steam)
  reactor.steam = steam or (turbines[1].flow + turbines[2].flow)
  local commands, learned = Control.step(state, config, {reactor}, turbines,
    {energy = 95, capacity = 100, charge = 0.95}, 1, points)
  apply(commands, turbines, reactor)
  return learned
end

do
  local config, reactor, turbines = fixture()
  local state, points = Control.new(), {_capacity = {status = "passed", signature = "old"}}
  local first, second = turbines[1].id, turbines[2].id
  points[first] = {rpm = config.rpmTarget, generating = {flow = 800, output = 30000}}
  points[second] = {rpm = config.rpmTarget, generating = {flow = 800, output = 30000}}
  Control.beginCalibration(state, turbines)
  tick(state, config, reactor, turbines, points)
  assert(state.calibrationTarget.id == first and turbines[1].coils and not turbines[2].coils)
  assert(points[first].generating.flow == 800, "Incomplete calibration must preserve saved settings")
  for _ = 1, 10 do tick(state, config, reactor, turbines, points) end
  assert(state.calibrationSession.points[first].generating and points[first].generating.flow == 800)
  tick(state, config, reactor, turbines, points)
  assert(state.calibrationTarget.id == second and not turbines[1].coils and turbines[2].coils)
  for _ = 1, 10 do tick(state, config, reactor, turbines, points) end
  assert(state.calibrationSession.points[second].generating and points[second].generating.flow == 800)
  tick(state, config, reactor, turbines, points)
  assert(not state.calibrationTarget and state.capacityCheck.active)
  for _ = 1, 10 do tick(state, config, reactor, turbines, points, 2000) end
  assert(state.capacityCheck.status == "passed" and not state.capacityCheck.active)
  assert(not state.calibrationSession.active and state.calibrationSession.status == "passed")
  assert(points._capacity and points._capacity.status == "passed")
  assert(points[first].generating.flow == 1000 and points[second].generating.flow == 1000)
  tick(state, config, reactor, turbines, points)
  assert(not turbines[1].coils and not turbines[2].coils,
    "Normal storage-driven standby must resume after explicit calibration")
  print("PASS explicit calibration is transactional, sequential, capacity-checked and finite")
end

do
  local config, reactor, turbines = fixture()
  local points = {}
  local working = {}
  for _, turbine in ipairs(turbines) do
    turbine.coils = true
    working[turbine.id] = {rpm = config.rpmTarget, generating = {flow = 1000, output = 40000}}
  end
  reactor.rods = 0
  local state = Control.new()
  state.calibrationSession = {active = true, points = working}
  for _ = 1, 11 do tick(state, config, reactor, turbines, points, 1500) end
  assert(state.capacityCheck.status == "failed" and not state.capacityCheck.active)
  assert(state.capacityCheck.required == 2000 and state.capacityCheck.output == 1500)
  assert(points._capacity and points._capacity.status == "failed")
  assert(not state.calibrationSession.active)
  print("PASS explicit calibration saves a completed insufficient-capacity result")
end

do
  local config, reactor, turbines = fixture()
  local points = {}
  local signatureParts = {}
  for _, turbine in ipairs(turbines) do
    points[turbine.id] = {
      rpm = config.rpmTarget,
      generating = {flow = 1000, output = 40000},
    }
    signatureParts[#signatureParts + 1] = turbine.id .. "=1000.000"
  end
  table.sort(signatureParts)
  points._capacity = {
    signature = config.rpmTarget .. "|" .. table.concat(signatureParts, "|"),
    status = "passed",
    required = 2000,
    output = 2000,
  }

  local restored = Control.new()
  tick(restored, config, reactor, turbines, points, 2000)
  assert(not restored.capacityCheck,
    "Normal control must not start a capacity check")
  assert(not turbines[1].coils and not turbines[2].coils,
    "Saved calibration must obey normal storage standby")

  turbines[1].output = 90000
  turbines[1].flow = 1400
  turbines[1].flowLimit = 1400
  for _ = 1, 30 do
    tick(restored, config, reactor, turbines, points, 2400)
  end
  assert(points[turbines[1].id].generating.flow == 1000)
  assert(points[turbines[1].id].generating.output == 40000)
  assert(not restored.capacityCheck and not restored.calibrationSession)
  print("PASS normal control never relearns or invalidates saved calibration")
end

do
  local config, reactor, turbines = fixture()
  local turbine = turbines[1]
  turbine.coils = true
  turbine.flow = turbine.flowMax
  turbine.flowLimit = turbine.flowMax
  turbine.rpm = config.rpmTarget - 20
  local points = {
    [turbine.id] = {rpm = config.rpmTarget, generating = {flow = turbine.flowMax, output = 40000}},
  }
  local state = Control.new()
  for _ = 1, 11 do
    turbine.rpm = turbine.rpm - 1
    Control.step(state, config, {reactor}, {turbine},
      {energy = 50, capacity = 100, charge = 0.5}, 1, points)
  end
  assert(state.turbineLimits[1] and state.turbineLimits[1].id == turbine.id)
  turbine.rpm = config.rpmTarget
  for _ = 1, 3 do
    Control.step(state, config, {reactor}, {turbine},
      {energy = 50, capacity = 100, charge = 0.5}, 1, points)
  end
  assert(#state.turbineLimits == 0)
  print("PASS maximum-flow falling-RPM warning confirms and clears per turbine")
end
