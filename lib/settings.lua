local Settings = {}

local SAVED_KEYS = {
  "rpmTarget",
  "targetCharge",
  "storage",
  "remotePeers",
  "monitor",
  "calibration",
  "lastMode",
  "autoSnapshot",
  "autoStandby",
  "companionDisplay",
  "controllerDisplay",
  "deviceNames",
}

local SNAPSHOT_KEYS = {"topology", "generators", "storage", "peers"}

local function readSavedSettings(path)
  local file = assert(fs.open(path, "r"))
  local saved = textutils.unserialize(file.readAll())
  file.close()
  assert(type(saved) == "table", "settings.dat is invalid; restore or remove it")
  return saved
end

local function applySavedSettings(config, saved)
  -- Old monitor settings require migration, so remember whether one existed
  -- before copying the currently supported fields.
  if saved.controllerDisplay == nil and saved.monitor ~= nil then
    config.controllerDisplay = nil
  end
  for _, key in ipairs(SAVED_KEYS) do
    if saved[key] ~= nil then
      config[key] = saved[key]
    end
  end
end

local function assertFiniteAtLeast(value, minimum, name)
  assert(type(value) == "number" and value < math.huge and value >= minimum,
    name .. " must be finite and at least " .. minimum)
end

local function migrateControlSettings(config)
  -- config.lua is deliberately retained during updates, so supply defaults
  -- introduced by newer runtime versions here.
  config.passiveMaxRodWithdrawalRate = config.passiveMaxRodWithdrawalRate
    or math.max(config.rodRate, 8)
  config.passiveMaxRodInsertionRate = config.passiveMaxRodInsertionRate
    or math.max(config.rodRate, 8)
  config.passiveBrakingSeconds = config.passiveBrakingSeconds or 90
end

local function validateControlSettings(config)
  assert(type(config.interval) == "number" and config.interval >= 0.25,
    "interval must be >= 0.25")
  assert(config.generateBelow > 0 and config.generateBelow < config.standbyAbove
      and config.standbyAbove < 1,
    "Require 0 < generateBelow < standbyAbove < 1")
  assert(config.targetCharge > 0 and config.targetCharge < 1, "Invalid targetCharge")
  assert(config.rpmTarget >= 500 and config.rpmTarget <= 2000,
    "v0.1 RPM target must be 500..2000")
  assert(config.rodRate > 0 and config.flowRate > 0 and config.remoteTimeout > 0,
    "Rates/timeouts must be positive")

  assertFiniteAtLeast(config.passiveMaxRodWithdrawalRate, config.rodRate,
    "passiveMaxRodWithdrawalRate")
  assertFiniteAtLeast(config.passiveMaxRodInsertionRate, config.rodRate,
    "passiveMaxRodInsertionRate")
  assertFiniteAtLeast(config.passiveBrakingSeconds, 30, "passiveBrakingSeconds")
end

local function validateCollections(config)
  for _, key in ipairs({"remotePeers", "reactors", "turbines", "storage", "storageMappings"}) do
    assert(type(config[key]) == "table", key .. " must be a table")
  end

  config.deviceNames = config.deviceNames or {}
  assert(type(config.deviceNames) == "table", "Invalid saved device names")
  for id, name in pairs(config.deviceNames) do
    assert(type(id) == "string" and type(name) == "string", "Invalid saved device name")
  end
  config.calibration = config.calibration or {}
end

local function validateRestartState(config)
  config.lastMode = config.lastMode or "manual"
  assert(config.lastMode == "manual" or config.lastMode == "auto",
    "Invalid saved control mode")

  if config.autoSnapshot ~= nil then
    assert(type(config.autoSnapshot) == "table", "Invalid saved Auto device snapshot")
    for _, key in ipairs(SNAPSHOT_KEYS) do
      assert(type(config.autoSnapshot[key]) == "string", "Invalid saved Auto device snapshot")
    end
  end

  if config.autoStandby == nil then
    config.autoStandby = false
  end
  assert(type(config.autoStandby) == "boolean", "Invalid saved standby state")
end

local function migrateDisplaySettings(config)
  if config.controllerDisplay == nil then
    config.controllerDisplay = {mode = config.monitor == false and "terminal" or "auto"}
  end
  assert(type(config.controllerDisplay) == "table"
      and (config.controllerDisplay.mode == "auto" or config.controllerDisplay.mode == "terminal"),
    "Controller display must be auto or terminal")

  -- Physical monitor names from older versions migrate to discovery.
  config.monitor = nil
  config.companionDisplay = config.companionDisplay or {mode = "auto"}
  assert(type(config.companionDisplay) == "table", "Invalid companion display setting")
  if config.companionDisplay.mode == "monitor" then
    config.companionDisplay = {mode = "auto"}
  end

  local mode = config.companionDisplay.mode
  assert(mode == "off" or mode == "terminal" or mode == "auto",
    "Companion display must be auto, off or terminal")
end

function Settings.load(root)
  local config = dofile(fs.combine(root, "config.lua"))
  local path = fs.combine(root, "settings.dat")
  if fs.exists(path) then
    applySavedSettings(config, readSavedSettings(path))
  end

  migrateControlSettings(config)
  validateControlSettings(config)
  validateCollections(config)
  validateRestartState(config)
  migrateDisplaySettings(config)
  return config
end

function Settings.save(root, config)
  local saved = {}
  for _, key in ipairs(SAVED_KEYS) do
    saved[key] = config[key]
  end

  local path = fs.combine(root, "settings.dat")
  local temporaryPath = path .. ".tmp"
  local backupPath = path .. ".bak"
  local file = assert(fs.open(temporaryPath, "w"))
  file.write(textutils.serialize(saved))
  file.close()

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end
  if fs.exists(path) then
    fs.move(path, backupPath)
  end
  fs.move(temporaryPath, path)
end

return Settings
