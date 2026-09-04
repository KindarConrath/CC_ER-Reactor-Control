local arguments = {...}
local controllerId = tonumber(arguments[1])
assert(controllerId and controllerId >= 0 and controllerId % 1 == 0,
  "Usage: agent CONTROLLER_COMPUTER_ID")
assert(controllerId ~= os.getComputerID(), "Controller must be a different computer")

local root = fs.getDir(shell.getRunningProgram())
package.path = fs.combine(root, "?.lua") .. ";" .. package.path

local Settings = require("lib.settings")
local config = Settings.load(root)

local function applyDisplayArguments()
  local changed = false
  local index = 2
  while index <= #arguments do
    local argument = arguments[index]
    if argument == "--monitor" then
      index = index + 1
      local name = arguments[index]
      assert(name and name ~= "" and not name:match("^%-%-"),
        "--monitor needs a peripheral name")
      -- Accept the old invocation, but discover the current monitor instead
      -- of pinning its peripheral name.
      config.companionDisplay = {mode = "auto"}
      changed = true
    elseif argument == "--auto-display" then
      config.companionDisplay = {mode = "auto"}
      changed = true
    elseif argument == "--terminal" then
      config.companionDisplay = {mode = "terminal"}
      changed = true
    elseif argument == "--no-display" then
      config.companionDisplay = {mode = "off"}
      changed = true
    else
      error("Usage: agent CONTROLLER_ID [--auto-display | --terminal | --no-display]")
    end
    index = index + 1
  end
  return changed
end

if applyDisplayArguments() then
  Settings.save(root, config)
end

local Companion = require("lib.companion")
local peer = Companion.new(controllerId, config, require("lib.devices"))
print("Reactor companion #" .. os.getComputerID() .. " paired to controller #" .. controllerId)
print("Devices must be adjacent or connected by wired modems.")
print("On connection loss, devices retain their last settings.")
local displayName = config.companionDisplay.name
local displaySuffix = displayName and (" " .. displayName) or ""
print("Local display: " .. config.companionDisplay.mode .. displaySuffix)

Companion.run(config, peer, function(currentConfig, service)
  require("lib.companion_ui").run(root, currentConfig, service)
end)
