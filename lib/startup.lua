local Startup = {}
local LAUNCHER_PATH = "/startup/reactor-control.lua"

local function programPath(root, name)
  return "/" .. fs.combine(root, name):gsub("^/+", "")
end

local function readFile(path)
  local file = assert(fs.open(path, "r"), "Cannot read " .. path)
  local contents = file.readAll()
  file.close()
  return contents
end

local function writeFile(path, contents)
  local file = assert(fs.open(path, "w"), "Cannot write " .. path)
  local wrote, writeError = pcall(file.write, contents)
  local closed, closeError = pcall(file.close)
  assert(wrote, writeError)
  assert(closed, closeError)
end

local function launcherSource(root)
  return "-- Reactor Control managed startup v1\n"
    .. string.format("shell.execute(%q, %q)\n", programPath(root, "startup.lua"), "run")
end

local function configPath(root)
  return fs.combine(root, "startup.dat")
end

local function temporaryLauncherPath(root)
  return fs.combine(root, "startup-launcher.tmp")
end

local function validControllerId(controllerId)
  return type(controllerId) == "number"
    and controllerId >= 0
    and controllerId < math.huge
    and controllerId % 1 == 0
    and controllerId ~= os.getComputerID()
end

local function readRoleConfig(root)
  local path = configPath(root)
  if not fs.exists(path) then
    return nil
  end

  local config = textutils.unserialize(readFile(path))
  assert(type(config) == "table"
      and (config.role == "controller" or config.role == "companion"),
    "Invalid startup.dat")
  if config.role == "companion" then
    assert(validControllerId(config.owner), "Invalid companion controller ID in startup.dat")
  end
  return config
end

function Startup.check(root, role, controllerId)
  assert(role == "controller" or role == "companion", "Choose controller or companion")
  local config = {role = role}
  if role == "companion" then
    controllerId = tonumber(controllerId)
    assert(validControllerId(controllerId), "Companion needs a different controller computer ID")
    config.owner = controllerId
  end

  assert(not fs.exists("/startup") or fs.isDir("/startup"),
    "An existing /startup file prevents a startup directory; move it to /startup.lua first")

  local expectedLauncher = launcherSource(root)
  assert(not fs.exists(LAUNCHER_PATH)
      or (not fs.isDir(LAUNCHER_PATH) and readFile(LAUNCHER_PATH) == expectedLauncher),
    "Existing /startup/reactor-control.lua belongs to another installation or was edited")
  assert(not fs.exists(temporaryLauncherPath(root)),
    "Inspect and remove unfinished startup file: " .. temporaryLauncherPath(root))
  return config
end

function Startup.choose(root)
  local previous = readRoleConfig(root)
  local defaultChoice = previous and previous.role == "companion" and "2" or "1"
  local roles = { ["1"] = "controller", ["2"] = "companion" }
  local role

  print("This computer is #" .. os.getComputerID())
  repeat
    print("Role:")
    print("1) controller")
    print("2) peer")
    write("Default (" .. defaultChoice .. "): ")
    local answer = read():match("^%s*(.-)%s*$")
    role = roles[answer == "" and defaultChoice or answer]
    if not role then
      print("Enter 1 or 2.")
    end
  until role

  local controllerId
  if role == "companion" then
    local defaultControllerId = previous and previous.owner
    repeat
      local suffix = defaultControllerId and (" [" .. defaultControllerId .. "]") or ""
      print("Main controller computer ID" .. suffix .. ":")
      local answer = read():match("^%s*(.-)%s*$")
      controllerId = answer == "" and defaultControllerId or tonumber(answer)
      if not validControllerId(controllerId) then
        print("Enter a whole computer ID other than this computer.")
      end
    until validControllerId(controllerId)
  end
  return Startup.check(root, role, controllerId)
end

function Startup.setup(root)
  local config = Startup.choose(root)
  return Startup.enable(root, config.role, config.owner)
end

function Startup.enable(root, role, controllerId)
  local config = Startup.check(root, role, controllerId)
  local path = configPath(root)
  local temporaryPath = path .. ".tmp"
  local backupPath = path .. ".bak"

  writeFile(temporaryPath, textutils.serialize(config))
  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end
  if fs.exists(path) then
    fs.move(path, backupPath)
  end
  fs.move(temporaryPath, path)

  if not fs.exists("/startup") then
    fs.makeDir("/startup")
  end
  if not fs.exists(LAUNCHER_PATH) then
    local temporaryLauncher = temporaryLauncherPath(root)
    local ok, err = pcall(function()
      writeFile(temporaryLauncher, launcherSource(root))
      fs.move(temporaryLauncher, LAUNCHER_PATH)
    end)
    if not ok then
      if fs.exists(temporaryLauncher) then
        fs.delete(temporaryLauncher)
      end
      error(err, 0)
    end
  end
  return config
end

function Startup.disable(root)
  if fs.exists(LAUNCHER_PATH) then
    assert(not fs.isDir(LAUNCHER_PATH) and readFile(LAUNCHER_PATH) == launcherSource(root),
      "Startup launcher was edited or belongs to another installation; left unchanged")
    fs.delete(LAUNCHER_PATH)
  end
  -- Retain the role file for inspection; disabling only removes our launcher.
end

function Startup.status(root)
  local config = readRoleConfig(root)
  local enabled = fs.exists(LAUNCHER_PATH)
    and not fs.isDir(LAUNCHER_PATH)
    and readFile(LAUNCHER_PATH) == launcherSource(root)
  return config, enabled
end

function Startup.run(root)
  local config = assert(readRoleConfig(root),
    "Configure startup with: reactor-control/startup controller | companion ID")
  if config.role == "controller" then
    return shell.execute(programPath(root, "main.lua"), "--boot")
  end
  return shell.execute(programPath(root, "agent.lua"), tostring(config.owner))
end

return Startup
