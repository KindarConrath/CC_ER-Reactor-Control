local Util = require("lib.util")
local Control = require("lib.control")
local Settings = require("lib.settings")
local App = {}

local function sortedIds(ids)
  local copy = {}
  for _, id in ipairs(ids) do
    copy[#copy + 1] = tostring(id)
  end
  table.sort(copy)
  return table.concat(copy, "|")
end

local function snapshot(config, topology, signature)
  return {
    topology = topology,
    generators = signature,
    storage = sortedIds(config.storage),
    peers = sortedIds(config.remotePeers),
  }
end

local function sameSnapshot(saved, current)
  if type(saved) ~= "table" then
    return false
  end
  for _, key in ipairs({"topology", "generators", "storage", "peers"}) do
    if saved[key] ~= current[key] then
      return false
    end
  end
  return true
end

local function selectDevices(devices, kind, selectedIds)
  local selected, byId = {}, {}
  for _, device in ipairs(devices) do
    byId[device.id] = device
    if #selectedIds == 0 and device.kind == kind then
      selected[#selected + 1] = device
    end
  end
  for _, id in ipairs(selectedIds) do
    selected[#selected + 1] = byId[id] or {
      id = id, name = id, label = id, kind = kind,
      online = false, error = "Disconnected",
    }
  end
  return selected
end

local function generatorSignature(reactors, turbines)
  local ids = {}
  for _, reactor in ipairs(reactors) do
    ids[#ids + 1] = reactor.id
  end
  for _, turbine in ipairs(turbines) do
    ids[#ids + 1] = turbine.id
  end
  table.sort(ids)
  return table.concat(ids, "|")
end

function App.new(config, backend, root, demo)
  local Network = require("lib.network")
  local app = {
    config = config, backend = backend, root = root, demo = demo,
    mode = "manual", queue = {}, devices = {}, reactors = {}, turbines = {},
    message = "", control = Control.new(), running = true,
    pendingResume = not demo and config.lastMode == "auto" and config.autoSnapshot ~= nil,
    readyPolls = 0,
  }
  if app.pendingResume then
    app.message = "Waiting to restore Auto; Mode cancels"
  elseif not demo and config.lastMode == "auto" then
    app.message = "Enable Auto once to save its device list"
  end

  function app.enqueue(operation, id, value)
    -- Only coalesce adjacent rod targets; never cross a mode or Stop request.
    local last = app.queue[#app.queue]
    if operation == "rods" and last and last.op == operation and last.id == id then
      last.value = value
    else
      app.queue[#app.queue + 1] = {op = operation, id = id, value = value}
    end
    return app.queue[#app.queue]
  end

  local function calibrationSaved()
    if app.calibrationDirty then
      app.message = ""
    end
    app.calibrationDirty = false
    app.calibrationSaveError = nil
    app.calibrationRetryAt = nil
  end

  function app.save()
    if not demo then
      Settings.save(root, config)
    end
    calibrationSaved()
  end

  local function saveCalibration(now, force)
    if not app.calibrationDirty or (not force and now < (app.calibrationRetryAt or 0)) then
      return
    end
    local ok, err = pcall(app.save)
    if not ok then
      app.calibrationSaveError = tostring(err)
      app.calibrationRetryAt = now + 30
      app.message = "Calibration NOT saved; retrying"
    end
  end

  function app.rename(id, value)
    local name = require("lib.presentation").validName(value)
    config.deviceNames = config.deviceNames or {}
    local previous = config.deviceNames[id]
    config.deviceNames[id] = name
    local ok, err = pcall(app.save)
    if not ok then
      config.deviceNames[id] = previous
      error(err, 0)
    end
    app.message = name and "Device name saved" or "Automatic device name restored"
  end

  function app.storageDevices()
    -- Missing selections remain removable even after a block gets a new modem ID.
    local devices, seen = {}, {}
    for _, device in ipairs(app.devices) do
      if device.kind == "storage" then
        devices[#devices + 1] = device
        seen[device.id] = true
      end
    end
    for _, id in ipairs(config.storage) do
      if not seen[id] then
        devices[#devices + 1] = {
          id = id, name = id, label = "Disconnected storage", kind = "storage",
          online = false, error = "Peripheral is no longer connected",
        }
        seen[id] = true
      end
    end
    return devices
  end

  function app.suspend(reason, reconnect)
    -- Runtime faults preserve restart intent; only connection failures can retry here.
    app.reconnecting = reconnect and config.lastMode == "auto" and config.autoSnapshot ~= nil or false
    app.mode = "manual"
    app.pendingResume = app.reconnecting
    app.readyPolls = 0
    app.control = Control.new()
    app.message = tostring(reason)
    app.fault = true
  end

  local function holdManual(reason)
    app.mode = "manual"
    app.pendingResume = false
    app.reconnecting = false
    app.readyPolls = 0
    app.control = Control.new()
    config.lastMode = "manual"
    config.autoSnapshot = nil
    config.autoStandby = false
    app.message = reason
    app.fault = false
  end

  function app.manual(reason)
    holdManual(reason)
    -- Stop must still reach devices when saving the restart setting fails.
    local ok, err = pcall(app.save)
    if not ok then
      app.message = "Manual; restart setting NOT saved: " .. tostring(err)
      app.fault = true
    end
  end

  local function configure(request)
    local nextConfig = Util.copy(config)
    if request.op == "peer" then
      local peerId = tonumber(request.id)
      if not (peerId and peerId >= 0 and peerId < math.huge and peerId % 1 == 0) then
        error("Enter a whole, non-negative peer ID", 0)
      end
      if peerId == os.getComputerID() then
        error("Peer ID must differ from controller ID", 0)
      end
      assert(type(request.value) == "boolean", "Choose add or remove")
      local found
      for index, id in ipairs(nextConfig.remotePeers) do
        if id == peerId then
          found = index
          break
        end
      end
      if request.value and found then
        return false, "Peer #" .. peerId .. " is already added"
      elseif not request.value and not found then
        return false, "Peer #" .. peerId .. " is already removed"
      end
      if request.value then
        table.insert(nextConfig.remotePeers, peerId)
      else
        table.remove(nextConfig.remotePeers, found)
      end
      nextConfig.lastMode = "manual"
      nextConfig.autoSnapshot = nil
      nextConfig.autoStandby = false
      -- Save before exposing the changed peer list to the polling backend.
      if not demo then
        Settings.save(root, nextConfig)
      end
      calibrationSaved()
      config.remotePeers = nextConfig.remotePeers
      holdManual("Peers changed; review devices before Auto")
      return true, "Peer #" .. peerId .. (request.value and " added" or " removed") .. "; mode is Manual"
    end

    assert(request.value == "auto" or request.value == "terminal", "Choose automatic or computer display")
    nextConfig.controllerDisplay = {mode = request.value}
    if not demo then
      Settings.save(root, nextConfig)
    end
    calibrationSaved()
    config.controllerDisplay = nextConfig.controllerDisplay
    return false, "Display preference saved"
  end

  function app.configureSetup(operation, id, value)
    local request = {op = operation, id = id, value = value}
    local ok, changed, message = pcall(configure, request)
    app.setupResult = {request = request, ok = ok, message = ok and message or tostring(changed)}
    if ok and changed then
      -- Setup runs between control ticks. Discard stale device/mode requests, but
      -- retain an explicit Stop so it still takes priority on the next tick.
      local retained = {}
      for _, queued in ipairs(app.queue) do
        if queued.op == "stop" then
          retained[#retained + 1] = queued
        end
      end
      app.queue = retained
      app.problem = "Refreshing peer connections"
    end
    return request
  end

  local function pollDevices()
    local devices, errors, connectionLost = backend.poll()
    app.devices = devices
    app.errors = errors
    app.reactors = selectDevices(devices, "reactor", config.reactors)
    app.turbines = selectDevices(devices, "turbine", config.turbines)
    local topology, topologyProblem = Control.topology(app.reactors, app.turbines)
    local storage, storageProblem = Control.storage(devices, config.storage, app.reactors, app.turbines)
    local networkProblem = #errors > 0 and table.concat(errors, "; ") or nil
    app.topology = topology
    app.storage = storage
    app.problem = networkProblem or topologyProblem or storageProblem
    return {
      topology = topology,
      topologyProblem = topologyProblem,
      networkProblem = networkProblem,
      connectionLost = connectionLost,
      signature = generatorSignature(app.reactors, app.turbines),
    }
  end

  local function requestMode(mode, readings, peersChanged)
    if mode ~= "auto" then
      app.manual("")
    elseif peersChanged then
      app.message = "Refresh peers before enabling Auto"
    elseif app.problem then
      app.suspend(app.problem)
    else
      config.lastMode = "auto"
      config.autoSnapshot = snapshot(config, readings.topology, readings.signature)
      config.autoStandby = false
      app.save() -- Persist the accepted plant before any automatic write.
      app.mode = "auto"
      app.pendingResume = false
      app.reconnecting = false
      app.control = Control.new()
      app.signature = readings.signature
      app.fault = false
      app.message = ""
    end
  end

  local function toggleStorage(deviceId)
    app.manual("Storage selection changed; review before Auto")
    local found = false
    for index, id in ipairs(config.storage) do
      if id == deviceId then
        table.remove(config.storage, index)
        found = true
        break
      end
    end
    if not found then
      config.storage[#config.storage + 1] = deviceId
    end
    app.save()
  end

  local function stopCommands()
    app.manual("Stop requested: inspect device status")
    local commands = {}
    for _, reactor in ipairs(app.reactors) do
      if reactor.online then
        commands[#commands + 1] = {name = reactor.name, peer = reactor.peer, op = "rods", value = 100}
        commands[#commands + 1] = {name = reactor.name, peer = reactor.peer, op = "active", value = false}
      end
    end
    for _, turbine in ipairs(app.turbines) do
      if turbine.online then
        commands[#commands + 1] = {name = turbine.name, peer = turbine.peer, op = "flow", value = 0}
        commands[#commands + 1] = {name = turbine.name, peer = turbine.peer, op = "coils", value = true}
        commands[#commands + 1] = {name = turbine.name, peer = turbine.peer, op = "active", value = false}
      end
    end
    return commands
  end

  local function processRequests(readings)
    local pending = app.queue
    app.queue = {}
    local commands, handledSetup, byId = {}, {}, {}
    local peersChanged = false
    for _, device in ipairs(app.devices) do
      byId[device.id] = device
    end

    for _, request in ipairs(pending) do
      local operation = request.op
      if operation == "peer" or operation == "display" then
        handledSetup[request] = true
        local ok, changed, message = pcall(configure, request)
        app.setupResult = {request = request, ok = ok, message = ok and message or tostring(changed)}
        if ok and changed then
          peersChanged = true
          commands = {}
        end
      elseif operation == "mode" then
        requestMode(request.value, readings, peersChanged)
      elseif operation == "rpm" then
        config.rpmTarget = Util.clamp(Util.number(request.value), 500, 2000)
        app.control = Control.new()
        app.save()
      elseif operation == "storage" then
        toggleStorage(request.id)
      elseif operation == "calibrate" then
        if app.mode ~= "auto" then
          app.message = "Enable Auto before calibrating turbines"
        elseif readings.topology ~= "turbine" then
          app.message = "Turbine calibration requires one cooled reactor and turbines"
        elseif app.calibrationDirty then
          app.message = "Save the completed calibration before starting again"
        else
          Control.beginCalibration(app.control, app.turbines)
          app.message = "Turbine calibration started; do not adjust devices"
        end
      elseif operation == "save" then
        if app.calibrationDirty then
          saveCalibration(Util.now(), true)
        else
          app.save()
          app.message = demo and "Demo settings are temporary" or "Settings and learned flow points saved"
        end
      elseif operation == "stop" then
        commands = stopCommands()
        break
      elseif operation == "quit" then
        app.running = false
      elseif operation == "rescan" then
        app.message = "Discovery refreshed"
      elseif peersChanged then
        app.message = "Refresh peers before changing device controls"
      elseif app.mode == "manual" then
        if app.pendingResume or config.lastMode == "auto" then
          app.manual("")
        end
        local device = byId[request.id]
        if device and device.online then
          commands[#commands + 1] = {
            name = device.name, peer = device.peer, op = operation, value = request.value,
          }
        else
          app.message = "Device unavailable"
        end
      else
        app.message = "Switch to Manual to change device controls"
      end
    end

    for _, request in ipairs(pending) do
      if (request.op == "peer" or request.op == "display") and not handledSetup[request] then
        app.setupResult = {request = request, ok = false, message = "Setup change cancelled by Stop"}
      end
    end
    return commands, peersChanged
  end

  local function restoreAuto(readings)
    if not app.pendingResume then
      return
    end
    local matches = sameSnapshot(config.autoSnapshot, snapshot(config, readings.topology, readings.signature))
    local ready = not app.problem and matches
    app.readyPolls = ready and app.readyPolls + 1 or 0
    if app.reconnecting and not readings.connectionLost and not ready then
      app.suspend(app.problem or "Devices changed; review before Auto")
    elseif app.reconnecting and readings.connectionLost then
      app.problem = readings.networkProblem .. "; retrying"
      app.message = app.problem
    elseif not ready then
      app.message = app.problem and "Waiting for devices to restore Auto" or "Waiting for saved plant; Mode cancels"
    elseif app.readyPolls >= 2 then
      app.mode = "auto"
      app.pendingResume = false
      app.signature = readings.signature
      app.control = Control.new()
      app.control.standby = config.autoStandby or false
      app.fault = false
      app.message = app.reconnecting and "Connection restored; Auto resumed" or "Saved Auto mode restored"
      app.reconnecting = false
    else
      app.message = "Plant ready; confirming before Auto"
    end
  end

  function app.step()
    local now = Util.now()
    local elapsed = app.lastTime and now - app.lastTime or config.interval
    app.lastTime = now
    if backend.advance then
      backend.advance(elapsed)
    end

    local readings = pollDevices()
    if app.mode == "auto" and (app.problem or readings.signature ~= app.signature) then
      app.suspend(app.problem or "Devices changed; review before Auto", readings.connectionLost)
    end

    local commands, peersChanged = processRequests(readings)
    if not app.running then
      return -- Exit preserves device settings without sending a final batch.
    end
    if peersChanged then
      app.problem = "Refreshing peer connections"
      if #commands > 0 then
        backend.write(commands) -- A queued Stop still takes priority.
      end
      return
    end

    -- A queued storage choice can invalidate the earlier reading in this same tick.
    local storage, storageProblem = Control.storage(app.devices, config.storage, app.reactors, app.turbines)
    app.storage = storage
    app.problem = readings.networkProblem or readings.topologyProblem or storageProblem
    if app.mode == "auto" and storageProblem then
      app.suspend(storageProblem)
    end
    restoreAuto(readings)

    local calibrationCompleted, previousCalibration, previousDirty
    if #commands == 0 and app.mode == "auto" then
      previousCalibration = Util.copy(config.calibration)
      previousDirty = app.calibrationDirty
      commands, calibrationCompleted = Control.step(app.control, config, app.reactors, app.turbines,
        assert(storage), elapsed, config.calibration)
      app.calibrationDirty = app.calibrationDirty or calibrationCompleted
      if config.autoStandby ~= app.control.standby then
        config.autoStandby = app.control.standby
        app.save()
      end
    end
    if #commands > 0 then
      local written, writeError = pcall(backend.write, commands)
      if not written then
        if calibrationCompleted then
          config.calibration = previousCalibration
          app.calibrationDirty = previousDirty
        end
        error(writeError, 0)
      end
    end
    saveCalibration(now, false)
  end

  function app.tick()
    local ok, err = pcall(app.step)
    if ok then
      return
    end
    if Network.isConnectionError(err) and (app.mode == "auto" or app.reconnecting) then
      app.suspend(tostring(err) .. "; retrying", true)
      app.problem = app.message
    elseif app.pendingResume and not app.reconnecting then
      app.readyPolls = 0
      app.message = "Waiting to restore Auto: " .. tostring(err)
      app.fault = true
    else
      app.suspend("Control paused: " .. tostring(err))
    end
  end

  return app
end

return App
