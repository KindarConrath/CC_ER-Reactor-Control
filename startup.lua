local arguments = {...}
local root = fs.getDir(shell.getRunningProgram())
package.path = fs.combine(root, "?.lua") .. ";" .. package.path

local Startup = require("lib.startup")
local action = arguments[1]

local function printEnabled(config)
  local pairing = config.owner and (" for controller #" .. config.owner) or ""
  print("Startup enabled: " .. config.role .. pairing)
  print("Controller startup restores the last chosen Manual/Auto mode.")
  print("Use 'reboot' to test, or launch the program normally now.")
end

local function configureStartup()
  local maximumArguments = action == "companion" and 2 or 1
  assert(#arguments <= maximumArguments, "Too many startup arguments")
  if action == "setup" then
    return Startup.setup(root)
  end
  return Startup.enable(root, action, arguments[2])
end

if action == "setup" or action == "controller" or action == "companion" then
  printEnabled(configureStartup())
elseif action == "disable" then
  Startup.disable(root)
  print("Reactor Control startup disabled; saved settings retained.")
elseif action == "status" then
  local config, enabled = Startup.status(root)
  print("Startup: " .. (enabled and "enabled" or "disabled"))
  if config then
    local pairing = config.owner and ("; controller #" .. config.owner) or ""
    print("Role: " .. config.role .. pairing)
  end
elseif action == "run" then
  assert(Startup.run(root), "Startup program stopped with an error")
else
  print("Usage: reactor-control/startup setup")
  print("       reactor-control/startup controller")
  print("       reactor-control/startup companion CONTROLLER_ID")
  print("       reactor-control/startup status | disable")
end
