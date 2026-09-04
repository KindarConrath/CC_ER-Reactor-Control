dofile("tests/cc_stub.lua")
package.path = "./?.lua;" .. package.path
local App = require("lib.app")
local Settings = require("lib.settings")
local UI = require("lib.ui")

local function exercise(display, width, touch)
  display.getSize = function() return width, 19 end
  fs, textutils = require("tests.memory_fs").new()
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
  local app = App.new(config, backend, ".", false)
  app.tick()
  local environment = setmetatable({}, {__index = _ENV})
  environment._G = environment
  local basalt = assert(loadfile("vendor/basalt.lua", "t", environment))()
  basalt.getErrorManager().error = function(err) error(err) end
  local ui = UI.new(basalt, app, display)
  local function render()
    ui.refresh()
    basalt.update("timer", 999)
  end
  local function tick()
    fakeTime = fakeTime + 1
    app.tick()
    render()
  end
  local function click(name)
    local button = assert(ui.buttons[name])
    if touch then
      basalt.update("monitor_touch", "monitor_0", button.x, button.y)
    else
      basalt.update("mouse_click", 1, button.x, button.y)
      basalt.update("mouse_up", 1, button.x, button.y)
    end
    render()
  end
  local function row(number, expected)
    local actual = screen[number].text:sub(2, width - 1):match("^%s*(.-)%s*$")
    assert(actual == expected, "Row " .. number .. ": " .. actual .. " instead of " .. expected)
  end
  local function finishCalibration()
    for _ = 1, 60 do
      if app.control.calibrationSession and not app.control.calibrationSession.active then return end
      tick()
    end
    error("Calibration did not finish")
  end

  render()
  click("Turbines")
  row(13, "Calibration required")
  row(17, "Setup > Tuning > Calibrate turbines")
  click("Mode: MANUAL")
  tick()
  row(13, "Calibration required")
  click("Setup")
  click("Tuning")
  row(7, "Turbine calibration: 0/2 saved")
  click("Calibrate turbines")
  tick()
  click("Back")
  click("Turbines")
  row(13, "Gen: calibrating 1/10s")
  row(17, "Calibration routine; do not adjust")
  finishCalibration()
  row(13, "")
  row(17, "")
  click("Overview")
  row(17, "")

  backend.devices[4].energy = backend.devices[4].capacity * 0.95
  tick()
  row(17, "")
  backend.devices[4].energy = backend.devices[4].capacity * 0.50
  tick()
  row(17, "")

  app.control.calibrationSession = {active = true, points = {}}
  app.control.calibrationTarget = {id = backend.devices[2].id, index = 1, count = 2}
  render()
  row(17, "Calibrating turbine 1/2; do not adjust")
  app.control.calibrationTarget = nil
  app.control.capacityCheck = {active = true, status = "verifying", output = 1800, required = 2000}
  render()
  row(17, "Capacity check: 1.8k/2.0k mB/t")
  app.control.capacityCheck.active = false
  app.control.capacityCheck.status = "passed"
  render()
  row(17, "Capacity verified: >=2.0k mB/t")
  app.control.capacityCheck = nil
  app.control.calibrationSession.active = false

  click("Turbines")
  local selectedControl = app.control.turbines[backend.devices[2].id]
  selectedControl.limitWarning = {id = backend.devices[2].id, rpm = 1700, flow = 2000}
  app.control.turbineLimits = {selectedControl.limitWarning}
  render()
  row(13, "TURBINE LIMIT: max flow; RPM falling")
  row(17, "Add blades or reduce coil drag")
  selectedControl.limitWarning = nil
  app.control.turbineLimits = {}
  click("Overview")

  app.control.reactorStalls = {{
    id = backend.devices[1].id, cooled = true, output = 0, demand = 2000,
  }}
  render()
  row(18, "REACTOR STALLED: 0.0/2.0k mB/t steam")
  app.control.reactorStalls = {}

  backend.devices[1].rods = 0
  backend.devices[1].steam = 1500
  app.control.reactors[backend.devices[1].id].rods = 0
  for _ = 1, 10 do tick() end
  row(18, "REACTOR LIMIT: 1.5k/2.0k mB/t steam")
  backend.devices[1].steam = 2000
  for _ = 1, 3 do tick() end
  assert(not screen[18].text:find("REACTOR LIMIT", 1, true))

  local savedOutput = Settings.load(".").calibration[backend.devices[2].id].generating.output
  backend.devices[2].output = 52000
  for _ = 1, 20 do tick() end
  row(17, "")
  assert(Settings.load(".").calibration[backend.devices[2].id].generating.output == savedOutput)

  local originalSave = Settings.save
  click("Setup")
  click("Tuning")
  click("Calibrate turbines")
  Settings.save = function() error("out of space") end
  tick()
  finishCalibration()
  assert(app.mode == "auto" and app.calibrationDirty)
  row(19, "Calibration NOT saved; retry from Tuning")
  click("Retry save")
  tick()
  assert(app.calibrationSaveError)
  Settings.save = originalSave
  click("Retry save")
  tick()
  assert(not app.calibrationSaveError and not app.calibrationDirty)

  app.suspend("Peer #4: no response; retrying", true)
  render()
  click("Back")
  click("Turbines")
  row(13, "")
  click("Mode: WAIT")
  tick()
  row(13, "")
end

exercise(term, 45, false)
local monitor = {}
for key, value in pairs(term) do monitor[key] = value end
exercise(monitor, 51, true)
print("PASS explicit calibration progress, saved state, retry and cancellation UI at 45/51 columns")
