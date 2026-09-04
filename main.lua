local args = {...}
local root = fs.getDir(shell.getRunningProgram())
package.path = fs.combine(root, "?.lua") .. ";" .. fs.combine(root, "?/init.lua") .. ";" .. package.path

local options = {boot = false, manual = false, terminal = false}

local function parseArguments()
  for _, argument in ipairs(args) do
    if argument == "--boot" then
      options.boot = true
    elseif argument == "--manual" then
      options.manual = true
    elseif argument == "--terminal" then
      options.terminal = true
    else
      error("Unknown option: " .. argument .. "\nUsage: main [--manual] [--terminal] [--boot]. "
        .. "Use Setup for peers and displays. For reports, use diagnostics scan|probe [--output FILE]", 0)
    end
  end
end

parseArguments()
local Settings = require("lib.settings")
local config = Settings.load(root)

local function resetSavedMode()
  config.lastMode = "manual"
  config.autoSnapshot = nil
  config.autoStandby = false
end

local function openDisplay(selectDisplay)
  local function getDisplay()
    local display = selectDisplay()
    local width, height = display.getSize()
    assert(display.isColor(), "Use an Advanced Computer/colour monitor")
    assert(width >= 45 and height >= 19, "Display must be at least 45 x 19 cells; reduce monitor text scale")
    return display
  end

  local ok, display = pcall(getDisplay)
  if options.boot then
    local previousError
    while not ok do
      if display ~= previousError then
        print("Waiting for control display: " .. tostring(display))
        previousError = display
      end
      sleep(1)
      ok, display = pcall(getDisplay)
    end
  end
  assert(ok, display)
  return display
end

if options.manual then
  resetSavedMode()
end
if options.terminal then
  config.controllerDisplay = {mode = "terminal"}
end
if options.manual or options.terminal then
  Settings.save(root, config)
end

require("lib.network").open()
local backend = require("lib.backend").new(config)
local selectDisplay = require("lib.display").controller(config, term.current())
local display = openDisplay(selectDisplay)
local app = require("lib.app").new(config, backend, root, false)

-- The pinned Basalt bundle has an internal module loader; keep it isolated.
local environment = setmetatable({}, {__index = _ENV})
environment._G = environment
local basalt = assert(loadfile(fs.combine(root, "vendor/basalt.lua"), "t", environment))()
local ui = require("lib.ui").new(basalt, app, display, selectDisplay)
ui.run()
print("Controller closed. Device settings were preserved.")
