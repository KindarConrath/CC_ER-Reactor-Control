local arguments = {...}

local function parseArguments()
  local destination, role, controllerId
  local index = 1
  while index <= #arguments do
    local argument = arguments[index]
    if argument == "--controller" or argument == "--companion" then
      assert(not role, "Choose only one installation role")
      role = argument == "--controller" and "controller" or "companion"
      if role == "companion" then
        index = index + 1
        controllerId = tonumber(arguments[index])
        assert(controllerId, "--companion requires the main controller computer ID")
      end
    elseif argument == "--help" then
      print("Usage: installer [DIRECTORY] [--controller | --companion CONTROLLER_ID]")
      print("Without a role flag, the installer asks which role to start at boot.")
      return nil, nil, nil, true
    else
      assert(argument:sub(1, 2) ~= "--" and not destination,
        "Unknown or extra argument: " .. argument)
      destination = argument
    end
    index = index + 1
  end
  return shell.resolve(destination or "reactor-control"), role, controllerId, false
end

local function packageSize()
  local required = 0
  for _, item in pairs(files) do
    required = required + math.max(item[1], 1024) + 2048
  end
  return required
end

local destination, role, controllerId, helpOnly = parseArguments()
if helpOnly then
  return
end

assert(not fs.exists(destination),
  "Destination exists. Use a release updater when provided, or preserve your settings and remove the old installation first.")
local stage = destination .. "-install-@VERSION@.tmp"
assert(not fs.exists(stage),
  "Previous staging directory exists: " .. stage .. ". Inspect it before retrying.")
checkSpace(destination, packageSize())

-- Use the bundled setup module without importing another installation's modules.
local startupSource = unpackFile(files["lib/startup.lua"])
local Startup = assert(load(startupSource, "startup setup", "t", _ENV))()
local selected = role and Startup.check(destination, role, controllerId)
  or Startup.choose(destination)

local installed, installError = pcall(function()
  fs.makeDir(stage)
  for name, item in pairs(files) do
    writeFile(fs.combine(stage, name), unpackFile(item))
  end
  fs.move(stage, destination)
end)
if not installed then
  -- This directory was created by this attempt and contains only package data.
  if fs.exists(stage) then
    fs.delete(stage)
  end
  error("Installation failed; destination was not created: " .. tostring(installError), 0)
end

print("Installed Reactor Control @VERSION@ in " .. destination)
local configured, setupError = pcall(
  Startup.enable, destination, selected.role, selected.owner)
if not configured then
  error("Program installed, but startup setup failed: " .. tostring(setupError)
    .. "\nAfter fixing the error, run " .. destination
    .. "/startup setup. Do not reinstall.", 0)
end

local pairing = selected.owner and (" for controller #" .. selected.owner) or ""
print("Startup enabled: " .. selected.role .. pairing)
if selected.role == "companion" then
  print("On the main controller: Setup > Peers > add ID " .. os.getComputerID())
else
  print("First launch is Manual. Choose storage and enable Auto when ready.")
end
print("Run " .. destination .. "/startup run now, or reboot to test startup.")
print("You may now remove this installer download to reclaim disk space.")
