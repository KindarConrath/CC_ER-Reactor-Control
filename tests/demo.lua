package.path = "./?.lua;" .. package.path
local memory = require("tests.memory_fs")
fs, textutils = memory.new()
os.epoch = function() return 100000 end
os.getComputerID = function() return 42 end

local function runDemo(...)
  local launched = false
  local env = setmetatable({}, {__index = _G})
  env._G = env
  env.shell = {getRunningProgram = function() return "tools/demo.lua" end}
  env.term = {current = function()
    return {getSize = function() return 51, 19 end, isColor = function() return true end}
  end}
  env.loadfile = function(path)
    assert(path == "vendor/basalt.lua")
    return function() return {} end
  end
  local observed
  env.require = function(name)
    if name == "lib.ui" then
      return {new = function(_, app)
        observed = app
        return {run = function()
          launched = true
          assert(app.demo and app.mode == "manual" and not app.pendingResume)
          assert(#app.config.remotePeers == 0)
          app.tick()
          app.enqueue("mode", nil, "auto")
          app.tick()
          assert(app.mode == "auto", app.message)
          app.enqueue("save")
          app.tick()
        end}
      end}
    end
    return require(name)
  end
  local ok, err = pcall(assert(loadfile("tools/demo.lua", "t", env)), ...)
  return ok, err, launched, observed
end

-- Any settings access or real peripheral/network activity must fail this test.
fs.open = function() error("Demo must not access saved settings") end
peripheral = setmetatable({}, {__index = function() error("Demo must not access peripherals") end})
rednet = setmetatable({}, {__index = function() error("Demo must not access rednet") end})
for _, mode in ipairs({"passive", "turbine"}) do
  local ok, err, launched, app = runDemo(mode)
  assert(ok, err)
  assert(launched and #app.reactors == (mode == "passive" and 2 or 1))
  assert(#app.turbines == (mode == "passive" and 0 or 2))
end
local ok, err, launched, app = runDemo()
assert(ok, err)
assert(launched and #app.turbines == 2)
for _, arguments in ipairs({{"--direct"}, {"other"}, {"passive", "turbine"}}) do
  ok, err, launched = runDemo(table.unpack(arguments))
  assert(not ok and not launched and tostring(err):find("Usage:", 1, true))
end
print("PASS source-only demo modes, default, validation and isolation from saved settings/hardware")
