package.path = "./?.lua;" .. package.path
local Calibration = require("lib.calibration")
local App = require("lib.app")
local Settings = require("lib.settings")
local MemoryFS = require("tests.memory_fs")
local clock = 100
os.epoch = function() return clock * 1000 end
os.getComputerID = function() return 42 end

local count = 0
local function test(name, run)
  local ok, err = pcall(run)
  assert(ok, name .. ": " .. tostring(err))
  count = count + 1
  print("PASS " .. name)
end

local function learningFixture()
  local config = dofile("config.lua")
  local control = {flow = 1000}
  local turbine = {id = "test/turbine", active = true, coils = true,
    rpm = config.rpmTarget, flow = 1000, output = 40000}
  local points = {}
  local function step(phase, acceleration, elapsed)
    return Calibration.update(control, config, turbine, phase or "generating",
      acceleration or 0, elapsed or 1, points)
  end
  return step, control, turbine, points, config
end

test("calibration needs ten stable seconds, then emits only one learned result", function()
  local step, control, turbine, points = learningFixture()
  for second = 1, 9 do
    assert(not step() and control.calibration.stable == second)
    assert(not points[turbine.id])
  end
  assert(step())
  assert(control.calibration.status == "complete")
  local point = points[turbine.id].generating
  assert(point.flow == 1000 and point.output == 40000)
  for _ = 1, 100 do assert(not step()) end
  assert(points[turbine.id].generating == point)
end)

test("fractional update intervals count elapsed seconds rather than samples", function()
  local step, control = learningFixture()
  for _ = 1, 39 do assert(not step(nil, nil, 0.25)) end
  assert(control.calibration.stable == 9.75)
  assert(step(nil, nil, 0.25))
end)

test("coil confirmation and activation are required before counting", function()
  local step, control, turbine, points = learningFixture()
  turbine.coils = false
  for _ = 1, 12 do assert(not step()) end
  assert(control.calibration.stable == 0 and not points[turbine.id])
  turbine.coils = true
  turbine.active = false
  for _ = 1, 12 do assert(not step()) end
  turbine.active = true
  for _ = 1, 9 do assert(not step()) end
  assert(step())
  for _ = 1, 12 do assert(not step("standby")) end
  assert(control.calibration.stable == 0 and not points[turbine.id].standby)
  turbine.coils = false
  for _ = 1, 9 do assert(not step("standby")) end
  assert(step("standby") and points[turbine.id].generating and points[turbine.id].standby)
end)

test("RPM, acceleration, steam shortage and spin-up reset the stability window", function()
  for _, reason in ipairs({"rpm", "acceleration", "flow", "spinup"}) do
    local step, control, turbine = learningFixture()
    for _ = 1, 9 do assert(not step()) end
    if reason == "rpm" then turbine.rpm = turbine.rpm + 20 end
    if reason == "flow" then turbine.flow = 0 end
    assert(not step(reason == "spinup" and "spinup" or nil, reason == "acceleration" and 3 or 0))
    assert(control.calibration.stable == 0)
    turbine.rpm = 1796
    turbine.flow = 1000
    for _ = 1, 9 do assert(not step()) end
    assert(step())
  end
end)

test("phase and RPM changes do not carry stability time or overwrite another phase", function()
  local step, control, turbine, points, config = learningFixture()
  for _ = 1, 9 do assert(not step()) end
  turbine.coils = false
  for _ = 1, 9 do assert(not step("standby")) end
  assert(step("standby") and not points[turbine.id].generating)
  turbine.coils = true
  for _ = 1, 10 do step() end
  assert(points[turbine.id].generating and points[turbine.id].standby)
  config.rpmTarget = 898
  turbine.rpm = 898
  for _ = 1, 9 do assert(not step()) end
  assert(points[turbine.id].rpm == 1796)
  assert(step() and points[turbine.id].rpm == 898 and not points[turbine.id].standby)
end)

test("explicit calibration measures a changed simulated coil resistance", function()
  local Control = require("lib.control")
  local config = dofile("config.lua")
  local turbine = require("lib.demo").new(false).devices[2]
  turbine.active, turbine.coils = true, true
  turbine.rpm, turbine.flowLimit, turbine.flow = 1600, 950, 950
  local control, points = Control.new(), {}
  local function run(resistance, outputFactor)
    Control.beginCalibration(control, {turbine})
    for _ = 1, 600 do
      local commands = Control.step(control, config, {}, {turbine},
        {energy = 50, capacity = 100, charge = 0.5}, 1, points)
      for _, command in ipairs(commands) do
        if command.op == "flow" then turbine.flowLimit = command.value end
      end
      turbine.flow = turbine.flowLimit
      turbine.rpm = turbine.rpm + (turbine.flow * 1.2 - turbine.rpm * resistance) / 12
      turbine.output = turbine.rpm * outputFactor
      local point = control.calibrationSession.points[turbine.id]
      if point and point.generating then
        assert(math.abs(turbine.rpm - config.rpmTarget) < config.rpmTolerance)
        return point.generating
      end
    end
    error("Explicit calibration did not learn the turbine")
  end
  local oldPoint = run(0.7, 25)
  local newPoint = run(0.9, 32)
  assert(newPoint.flow > oldPoint.flow * 1.1 and newPoint.output > oldPoint.output * 1.1)
end)

local originalSave = Settings.save
local writes, failSave
Settings.save = function(...)
  writes = writes + 1
  if failSave then error("out of space") end
  return originalSave(...)
end

local function tick(app)
  clock = clock + 1
  app.tick()
end

local function appFixture(demo)
  fs, textutils = MemoryFS.new()
  writes, failSave = 0, false
  local config = dofile("config.lua")
  config.calibration = {}
  config.storage = {"demo/battery"}
  config.autoStandby = false
  local backend = require("lib.demo").new(false)
  backend.advance = nil
  for _, turbine in ipairs({backend.devices[2], backend.devices[3]}) do
    turbine.active, turbine.coils = true, true
    turbine.rpm, turbine.flowLimit, turbine.flow, turbine.output = 1796, 1000, 1000, 40000
  end
  backend.devices[1].steam = 2000
  local app = App.new(config, backend, ".", demo or false)
  app.enqueue("mode", nil, "auto")
  tick(app)
  assert(app.mode == "auto", app.message)
  return app, backend, config
end

local function startCalibration(app)
  app.enqueue("calibrate")
  tick(app)
  assert(app.control.calibrationSession and app.control.calibrationSession.active, app.message)
end

local function finishCalibration(app)
  for _ = 1, 60 do
    if app.control.calibrationSession and not app.control.calibrationSession.active then return end
    tick(app)
  end
  error("Calibration did not finish")
end

test("explicit turbine calibration commits once and normal control never resaves", function()
  local app, backend, config = appFixture()
  local initialWrites = writes
  startCalibration(app)
  finishCalibration(app)
  assert(writes == initialWrites + 1 and not app.calibrationDirty)
  assert(app.message == "")
  local saved = Settings.load(".")
  for _, turbine in ipairs({backend.devices[2], backend.devices[3]}) do
    assert(saved.calibration[turbine.id].generating.flow == 1000)
  end
  app = App.new(saved, backend, ".", false)
  for _ = 1, 40 do tick(app) end
  assert(app.mode == "auto" and writes == initialWrites + 1)
  assert(not app.control.calibrationSession and not app.control.capacityCheck)
end)

test("calibration autosave failure retains Auto, retries slowly, and reports recovery", function()
  local app, backend = appFixture()
  local initialWrites = writes
  startCalibration(app)
  failSave = true
  finishCalibration(app)
  assert(app.mode == "auto" and app.calibrationDirty and app.calibrationSaveError)
  assert(app.message == "Calibration NOT saved; retrying" and writes == initialWrites + 1)
  local controlWrites = #backend.writes
  for _ = 1, 29 do tick(app) end
  assert(writes == initialWrites + 1 and #backend.writes > controlWrites)
  failSave = false
  tick(app)
  assert(writes == initialWrites + 2 and not app.calibrationDirty and not app.calibrationSaveError)
  assert(app.message == "" and app.mode == "auto")
end)

test("Retry save works immediately and Manual cancels unfinished calibration", function()
  local app = appFixture()
  startCalibration(app)
  failSave = true
  finishCalibration(app)
  assert(app.calibrationSaveError)
  local initialWrites = writes
  app.enqueue("save")
  tick(app)
  assert(writes == initialWrites + 1 and app.mode == "auto" and app.calibrationDirty)
  failSave = false
  app.enqueue("save")
  tick(app)
  assert(writes == initialWrites + 2 and not app.calibrationSaveError and not app.calibrationDirty)
  app = appFixture()
  startCalibration(app)
  for _ = 1, 4 do tick(app) end
  app.enqueue("mode", nil, "manual")
  tick(app)
  for _ = 1, 20 do tick(app) end
  assert(app.mode == "manual" and next(app.config.calibration) == nil)
end)

test("a failed final control write discards the unfinished calibration result", function()
  local app, backend = appFixture()
  startCalibration(app)
  while not (app.control.capacityCheck and app.control.capacityCheck.stable >= 9) do tick(app) end
  local initialWrites = writes
  backend.write = function() error("write failed") end
  tick(app)
  assert(app.mode == "manual" and writes == initialWrites and not app.calibrationDirty)
  assert(next(app.config.calibration) == nil)
  assert(next(Settings.load(".").calibration) == nil)
end)

test("a peer outage cancels calibration without replacing saved settings", function()
  local app, backend = appFixture()
  startCalibration(app)
  for _ = 1, 4 do tick(app) end
  local poll = backend.poll
  backend.poll = function() return {}, {"Peer #4: no response"}, true end
  for _ = 1, 15 do tick(app) end
  assert(app.pendingResume and next(app.config.calibration) == nil)
  backend.poll = poll
  tick(app)
  assert(app.pendingResume)
  tick(app)
  assert(app.mode == "auto" and next(app.config.calibration) == nil)
  for _ = 1, 20 do tick(app) end
  assert(next(app.config.calibration) == nil and not app.control.calibrationSession)
  assert(next(Settings.load(".").calibration) == nil)
end)

test("demo calibration completes without disk writes", function()
  local app = appFixture(true)
  startCalibration(app)
  finishCalibration(app)
  assert(writes == 0 and not app.calibrationDirty)
  assert(app.message == "")
end)

Settings.save = originalSave
print(count .. " calibration lifecycle and persistence tests passed")
