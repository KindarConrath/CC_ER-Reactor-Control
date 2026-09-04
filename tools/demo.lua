-- Source-only UI development launcher. Never opens a network or loads saved settings.
local args = {...}
local mode = args[1] or "turbine"
assert(#args <= 1 and (mode == "passive" or mode == "turbine"),
  "Usage: tools/demo [passive|turbine]")

local root = fs.getDir(fs.getDir(shell.getRunningProgram()))
package.path = fs.combine(root, "?.lua") .. ";" .. fs.combine(root, "?/init.lua") .. ";" .. package.path

local config = dofile(fs.combine(root, "config.lua"))
config.remotePeers = {}
config.reactors = {}
config.turbines = {}
config.storage = {"demo/battery"}
config.calibration = {}
config.lastMode = "manual"
config.autoSnapshot = nil
config.autoStandby = false

local display = term.current()
local width, height = display.getSize()
assert(display.isColor() and width >= 45 and height >= 19,
  "Demo needs a colour terminal of at least 45 x 19 cells")
local backend = require("lib.demo").new(mode == "passive")
local app = require("lib.app").new(config, backend, root, true)

local environment = setmetatable({}, {__index = _ENV})
environment._G = environment
local basalt = assert(loadfile(fs.combine(root, "vendor/basalt.lua"), "t", environment))()
require("lib.ui").new(basalt, app, display, function() return display end).run()
