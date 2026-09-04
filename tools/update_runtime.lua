local arguments = {...}

local function parseArguments()
  local destination = "reactor-control"
  local diskOnly = false
  local outputPath
  local index = 1
  while index <= #arguments do
    local argument = arguments[index]
    if argument == "--disk" then
      diskOnly = true
    elseif argument == "--output" then
      index = index + 1
      outputPath = assert(arguments[index], "--output needs a file name")
    elseif argument:sub(1, 2) == "--" then
      error("Usage: updater [DIRECTORY] [--disk [--output FILE]]")
    else
      destination = argument
    end
    index = index + 1
  end
  assert(not outputPath or diskOnly, "--output requires --disk")
  return destination, diskOnly, outputPath
end

local destination, diskOnly, outputPath = parseArguments()
assert(fs.isDir(destination), "No installation directory: " .. destination)

local drive = fs.getDrive(destination)

local function isOnInstallDrive(path)
  return fs.getDrive(path) == drive
end

local function fileTreeSize(path)
  if not isOnInstallDrive(path) then
    return 0
  end
  if not fs.isDir(path) then
    return fs.getSize(path)
  end

  local total = 0
  for _, name in ipairs(fs.list(path)) do
    total = total + fileTreeSize(fs.combine(path, name))
  end
  return total
end

local function appendDirectoryEntries(lines, parent, heading)
  if not isOnInstallDrive(parent) then
    return
  end

  local entries = {}
  for _, name in ipairs(fs.list(parent)) do
    local path = fs.combine(parent, name)
    if isOnInstallDrive(path) then
      entries[#entries + 1] = {name = path, bytes = fileTreeSize(path)}
    end
  end
  table.sort(entries, function(a, b)
    if a.bytes == b.bytes then
      return a.name < b.name
    end
    return a.bytes > b.bytes
  end)

  lines[#lines + 1] = heading .. " (file bytes; excludes allocation overhead):"
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = string.format("%d  %s", entry.bytes, entry.name)
  end
end

local function diskReport()
  local lines = {}
  local available = fs.getFreeSpace(destination)
  local capacity = fs.getCapacity(destination)
  lines[#lines + 1] = "Disk for " .. destination .. " (" .. tostring(drive) .. ")"
  lines[#lines + 1] = "Capacity: " .. tostring(capacity) .. " bytes"
  lines[#lines + 1] = "Free: " .. tostring(available) .. " bytes"
  if type(capacity) == "number" and type(available) == "number" then
    lines[#lines + 1] = "Used: " .. (capacity - available) .. " bytes"
  end
  appendDirectoryEntries(lines, "/", "Top-level usage")
  appendDirectoryEntries(lines, destination, "Installation contents")
  return table.concat(lines, "\n")
end

if diskOnly then
  local report = diskReport()
  if outputPath then
    local path = shell.resolve(outputPath)
    writeFile(path, report .. "\n")
    print("Saved disk report to /" .. path:gsub("^/+", ""))
  else
    print(report)
  end
  return
end

local function readExistingFile(path)
  if not fs.exists(path) then
    return nil
  end
  assert(isOnInstallDrive(path), "Update target is on another drive: " .. path)
  local file = assert(fs.open(path, "r"), "Cannot read " .. path)
  local contents = file.readAll()
  file.close()
  return contents
end

local function collectChanges()
  -- Decode and checksum the complete package before replacing anything. Keep
  -- replacements in memory instead of consuming space with a staging tree.
  local changes = {}
  for name, item in pairs(files) do
    local contents = unpackFile(item)
    if name:sub(-4) == ".lua" then
      assert(load(contents, "@" .. name, "t", {}), "Invalid packaged Lua: " .. name)
    end

    local path = fs.combine(destination, name)
    assert(not fs.isDir(path), "Expected a file: " .. path)
    local previous = readExistingFile(path)
    if previous ~= contents then
      changes[#changes + 1] = {
        name = name,
        data = contents,
        oldSize = previous and #previous or 0,
      }
    end
  end
  return changes
end

local function recognizedBackup(path, relativePath)
  if not isOnInstallDrive(path) then
    return false
  end
  if not fs.isDir(path) then
    return files[relativePath] ~= nil or relativePath == "README.md"
  end
  for _, name in ipairs(fs.list(path)) do
    local childRelative = relativePath == "" and name or relativePath .. "/" .. name
    if not recognizedBackup(fs.combine(path, name), childRelative) then
      return false
    end
  end
  return true
end

local function removeLegacyBackups()
  -- Discard only recognized versioned code backups. Unknown contents,
  -- settings, mounted drives, and unrelated backups are preserved.
  local before = fs.getFreeSpace(destination)
  local removed = 0
  for _, name in ipairs(fs.list(destination)) do
    if name:match("^backup%-%d+%.%d+%.%d+$") then
      local path = fs.combine(destination, name)
      if fs.isDir(path) and recognizedBackup(path, "") then
        fs.delete(path)
        removed = removed + 1
      else
        print("Kept unrecognized backup: " .. path)
      end
    end
  end

  local available = fs.getFreeSpace(destination)
  if removed > 0 then
    print("Removed " .. removed .. " legacy code backup(s).")
    if type(before) == "number" and type(available) == "number" then
      print("Reclaimed " .. (available - before) .. " bytes.")
    end
  end
  return available
end

local function requiredGrowth(changes)
  local growth = 0
  for _, entry in ipairs(changes) do
    growth = growth + #entry.data - entry.oldSize
    if entry.oldSize == 0 then
      growth = growth + 1024
    end
  end
  return math.max(0, growth + 4096)
end

local changes = collectChanges()
local available = removeLegacyBackups()
if #changes == 0 then
  print("Already updated to @VERSION@. No code files changed.")
  return
end

-- Shrinking files go first. Replacing in place requires only net growth plus
-- a small allocation/settings margin, not enough room for a second full copy.
table.sort(changes, function(a, b)
  local changeA = #a.data - a.oldSize
  local changeB = #b.data - b.oldSize
  if changeA == changeB then
    return a.name < b.name
  end
  return changeA < changeB
end)

local required = requiredGrowth(changes)
if type(available) == "number" and available < required then
  print(diskReport())
  error(string.format(
    "Need about %d additional bytes free; have %d. Installed code and settings unchanged. "
      .. "Move old downloads or unneeded files off this disk. Use --disk --output FILE for a "
      .. "report after freeing space.",
    required, available), 0)
end

local currentFile
local updated, updateError = pcall(function()
  for _, entry in ipairs(changes) do
    currentFile = entry.name
    writeFile(fs.combine(destination, entry.name), entry.data)
  end
end)
if not updated then
  error("Update incomplete at " .. tostring(currentFile) .. ": " .. tostring(updateError)
    .. ". Config and saved settings preserved. Free space if needed and rerun this updater "
    .. "before starting the controller. No rollback backup was created.", 0)
end

print("Updated to @VERSION@. " .. #changes .. " changed files; no rollback backup or staging copy.")
print("Config, saved settings and Basalt preserved. Restart your controller or companion.")
print("To enable or change startup, run " .. destination .. "/startup setup.")
print("You may now remove this updater download to reclaim disk space.")
