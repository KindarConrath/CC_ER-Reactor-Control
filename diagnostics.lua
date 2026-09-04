local args = {...}
local root = fs.getDir(shell.getRunningProgram())
package.path = fs.combine(root, "?.lua") .. ";" .. fs.combine(root, "?/init.lua") .. ";" .. package.path

local usage = "Usage: diagnostics scan|probe [--output FILE]"
local mode = args[1]
if not mode or mode == "--help" then
  print(usage)
  print("scan: supported local/peer devices; probe: local peripheral types and methods")
  return
end
assert(mode == "scan" or mode == "probe", usage)

local outputPath
local index = 2
while index <= #args do
  assert(args[index] == "--output" and not outputPath, usage)
  index = index + 1
  outputPath = args[index]
  assert(outputPath and outputPath ~= "" and not outputPath:match("^%-%-"), "--output needs a file name")
  index = index + 1
end

local config = require("lib.settings").load(root)
local version = require("lib.version")
local report = {}

local function reportLine(text, isError)
  text = tostring(text)
  report[#report + 1] = (isError and "ERROR: " or "") .. text
  if not outputPath then
    if isError then
      printError(text)
    else
      print(text)
    end
  end
end

local function probePeripherals()
  reportLine("Reactor Control " .. version .. " - peripheral probe")
  reportLine("Computer ID: " .. os.getComputerID())
  reportLine("Locally visible peripheral types and methods (read-only):")
  for _, device in ipairs(require("lib.devices").inspect(config)) do
    reportLine(device.name .. " (" .. table.concat(device.types, ", ") .. ") -> " .. device.kind)
    reportLine("  " .. table.concat(device.methods, ", "))
  end
  local hasConversionHelper = type(mekanismEnergyHelper) == "table"
    and type(mekanismEnergyHelper.joulesToFE) == "function"
  reportLine("Mekanism conversion helper: " .. tostring(hasConversionHelper))
end

local function scanDevices()
  local backend = require("lib.backend").new(config)
  local devices, errors = backend.poll()
  reportLine("Reactor Control " .. version .. " - device scan")
  reportLine("Computer ID: " .. os.getComputerID())
  local peers = #config.remotePeers > 0 and table.concat(config.remotePeers, ", ") or "none"
  reportLine("Configured peers (" .. #config.remotePeers .. "): " .. peers)
  for _, device in ipairs(devices) do
    reportLine(device.id .. "  " .. device.kind .. "  " .. (device.online and "online" or tostring(device.error)))
  end
  if #devices == 0 then
    reportLine("No supported devices detected. Run diagnostics probe to inspect visible peripherals.")
  end
  for _, err in ipairs(errors) do
    reportLine(err, true)
  end
end

if mode == "probe" then
  probePeripherals()
else
  scanDevices()
end

if outputPath then
  local path = shell.resolve(outputPath)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then
    fs.makeDir(parent)
  end
  local file = assert(fs.open(path, "w"), "Cannot write report: " .. path)
  file.write(table.concat(report, "\n") .. "\n")
  file.close()
  print("Saved diagnostic report to /" .. path:gsub("^/+", ""))
end
