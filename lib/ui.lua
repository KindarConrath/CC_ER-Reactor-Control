local Util = require("lib.util")
local Presentation = require("lib.presentation")
local Setup = require("lib.setup_ui")
local Widgets = require("lib.ui_widgets")
local Calibration = require("lib.calibration")
local version = require("lib.version")
local UI = {}
local SETUP_NAMES = {direct = "Passive Reactors", turbine = "Reactor + Turbines"}

function UI.new(basalt, app, display, selectDisplay)
  local ui = {
    tab = "Overview", index = {Reactors = 1, Turbines = 1, Storage = 1},
    buttons = {}, rodDrafts = {},
  }
  local frame = basalt.createFrame():setTerm(display):setBackground(colors.black):setForeground(colors.white)
  local width, height = display.getSize()
  local widgets = Widgets.new(frame, ui, function() return width end)
  local label, button = widgets.label, widgets.button

  local function manual(device, operation, value)
    app.enqueue(operation, device.id, value)
  end

  local function identify(device)
    button(width - 13, 7, 8, "Rename", function()
      ui.editor = {id = device.id, title = Presentation.title(device, app.config)}
      ui.refresh()
    end)
  end

  local function editName()
    local editor = ui.editor
    if editor.built then
      return -- Keep keyboard focus and unsaved text through background polling.
    end
    widgets.clear()
    label(1, "NAME DEVICE", colors.cyan)
    label(3, editor.title)
    label(4, editor.id, colors.lightGray)
    label(6, "Name (up to 32 characters):")
    ui.nameInput = frame:addInput({
      x = 2, y = 8, width = width - 3, height = 1, maxLength = 32,
      text = editor.value or (app.config.deviceNames or {})[editor.id] or "",
      background = colors.white, foreground = colors.black,
    })
    label(10, "Click the field, then type on this computer", colors.lightGray)
    label(11, "Blank restores the automatic name", colors.lightGray)
    local function commit(value)
      local ok, err = pcall(app.rename, editor.id, value)
      if ok then
        ui.editor = nil
        ui.refresh()
      elseif ui.nameError then
        ui.nameError:setText(tostring(err):sub(1, width - 3))
      else
        ui.nameError = label(15, tostring(err), colors.orange)
      end
    end
    button(2, 13, 9, "Save name", function() commit(ui.nameInput:getText()) end, colors.green)
    button(13, 13, 9, "Automatic", function() commit("") end)
    button(24, 13, 8, "Cancel", function()
      ui.editor = nil
      ui.refresh()
    end)
    label(height, "Naming does not change device IDs or controls", colors.gray)
    ui.nameError = nil
    editor.built = true
  end

  local function refreshDisplay()
    local nextDisplay = selectDisplay and selectDisplay() or display
    local nextWidth, nextHeight = nextDisplay.getSize()
    if nextDisplay ~= display or nextWidth ~= width or nextHeight ~= height then
      if ui.editor then
        ui.editor.value = ui.nameInput and ui.nameInput:getText() or ui.editor.value
        ui.editor.built = false
      end
      if nextDisplay ~= display then
        pcall(display.clear)
        display = nextDisplay
        frame:setTerm(display)
      else
        frame:term_resize()
      end
    end
    width, height = nextWidth, nextHeight
  end

  local function refreshRodDrafts()
    if ui.lastMode ~= app.mode then
      ui.rodDrafts = {}
      ui.lastMode = app.mode
    end
    local present = {}
    for _, reactor in ipairs(app.reactors) do
      if reactor.online then
        present[reactor.id] = true
      end
    end
    for id in pairs(ui.rodDrafts) do
      if not present[id] then
        ui.rodDrafts[id] = nil
      end
    end
  end

  local function drawNavigation()
    label(1, "REACTOR CONTROL  " .. version .. (app.demo and "  [DEMO]" or ""), colors.cyan)
    local modeText = app.pendingResume and "Mode: WAIT" or (app.mode == "auto" and "Mode: AUTO" or "Mode: MANUAL")
    button(2, 3, 12, modeText, function()
      app.enqueue("mode", nil, (app.mode == "auto" or app.pendingResume) and "manual" or "auto")
    end, app.mode == "auto" and colors.green or colors.blue)
    button(15, 3, 8, "Stop all", function() app.enqueue("stop") end, colors.red)
    button(24, 3, 8, "Setup", function()
      ui.setup = Setup.new(frame, app, widgets, function()
        ui.setup = nil
        ui.refresh()
      end)
      ui.refresh()
    end)
    button(38, 3, 6, "Exit", function() app.enqueue("quit") end)

    local groups = {Reactors = app.reactors, Turbines = app.turbines, Storage = app.storageDevices()}
    if ui.tab ~= "Overview" and #groups[ui.tab] == 0 then
      ui.tab = "Overview"
    end
    for index, name in ipairs(Presentation.tabs(groups)) do
      button(2 + (index - 1) * 11, 5, 10, name, function()
        ui.tab = name
        ui.refresh()
      end, ui.tab == name and colors.blue or colors.gray)
    end
  end

  local function calibrationText(turbine)
    if app.calibrationSaveError then
      return "Calibration NOT saved; retrying", "Setup > Tuning can retry saving", colors.orange
    end
    local session = app.control.calibrationSession
    local sessionActive = session and session.active
    local control = app.control.turbines[turbine.id]
    if control and control.limitWarning then
      return "TURBINE LIMIT: max flow; RPM falling", "Add blades or reduce coil drag", colors.orange
    end
    local savedEntry = app.config.calibration[turbine.id]
    local savedPoint = savedEntry and savedEntry.rpm == app.config.rpmTarget
      and savedEntry.generating
    if not sessionActive then
      if savedPoint then
        return "", "", colors.lightGray
      end
      return "Calibration required", "Setup > Tuning > Calibrate turbines", colors.orange
    end
    local calibrationTarget = app.control.calibrationTarget
    if calibrationTarget and calibrationTarget.id ~= turbine.id then
      return string.format("Waiting for turbine %d/%d", calibrationTarget.index, calibrationTarget.count),
        "Calibration runs one turbine at a time", colors.lightGray
    end
    local capacityCheck = app.control.capacityCheck
    if capacityCheck and capacityCheck.active then
      return "Verifying combined reactor capacity",
        "All turbines are generating; Manual cancels", colors.orange
    end
    local state = control and control.calibration
    if not state then
      return "Calibration waiting for readings", "", colors.lightGray
    elseif state.status == "spinup" then
      return "Calibration waiting for spin-up",
        "Calibration is controlling the plant; do not adjust", colors.orange
    end
    local phase = state.phase == "generating" and "Gen" or "Standby"
    if state.status == "complete" then
      return phase .. ": measurement complete", "Continuing calibration routine", colors.lime
    end
    return string.format("%s: calibrating %d/%ds", phase, math.floor(state.stable), Calibration.STABLE_SECONDS),
      "Calibration routine; do not adjust", colors.orange
  end

  local function steamCapacityWarning()
    local shortage = app.control.steamShortage
    if shortage then
      return "REACTOR LIMIT: " .. Util.format(shortage.output) .. "/"
        .. Util.format(shortage.demand) .. " mB/t steam"
    end
  end

  local function reactorStallWarning()
    local warning = app.control.reactorStalls and app.control.reactorStalls[1]
    if not warning then
      return
    end
    local reactorNumber = 1
    for index, reactor in ipairs(app.reactors) do
      if reactor.id == warning.id then reactorNumber = index break end
    end
    if warning.cooled then
      return "REACTOR STALLED: " .. Util.format(warning.output) .. "/"
        .. Util.format(warning.demand) .. " mB/t steam"
    end
    return string.format("REACTOR STALLED: Reactor %d/%d; no output",
      reactorNumber, #app.reactors)
  end

  local function turbineCapacityWarning()
    local warning = app.control.turbineLimits and app.control.turbineLimits[1]
    if warning then
      local turbineNumber = 1
      for index, candidate in ipairs(app.turbines) do
        if candidate.id == warning.id then turbineNumber = index break end
      end
      return string.format("TURBINE LIMIT: Turbine %d/%d; RPM falling",
        turbineNumber, #app.turbines)
    end
  end

  local function drawCalibrationSummary()
    if app.topology ~= "turbine" then
      return
    end
    if app.calibrationSaveError then
      label(17, "Calibration NOT saved; retrying", colors.orange)
    else
      local session = app.control.calibrationSession
      local sessionActive = session and session.active
      local calibrationTarget = sessionActive and app.control.calibrationTarget
      local capacityCheck = sessionActive and app.control.capacityCheck
      if calibrationTarget then
        label(17, string.format("Calibrating turbine %d/%d; do not adjust",
          calibrationTarget.index, calibrationTarget.count), colors.orange)
        return
      elseif capacityCheck then
        local required = Util.format(capacityCheck.required or 0)
        local output = Util.format(capacityCheck.output or 0)
        if capacityCheck.active then
          label(17, "Capacity check: " .. output .. "/" .. required .. " mB/t", colors.orange)
        elseif capacityCheck.status == "passed" then
          label(17, "Capacity verified: >=" .. required .. " mB/t", colors.lime)
        elseif capacityCheck.status == "failed" then
          label(17, "Capacity FAILED: " .. output .. "/" .. required .. " mB/t", colors.orange)
        end
        return
      end
      local saved = 0
      for _, turbine in ipairs(app.turbines) do
        local entry = app.config.calibration[turbine.id]
        if entry and entry.rpm == app.config.rpmTarget and entry.generating then
          saved = saved + 1
        end
      end
      if app.calibrationDirty then
        label(17, "Calibration complete; saving", colors.orange)
      elseif saved < #app.turbines then
        label(17, string.format("Calibration required: %d/%d; Setup > Tuning",
          saved, #app.turbines), colors.orange)
      end
    end
  end

  local function drawOverview()
    label(7, "Setup: " .. (SETUP_NAMES[app.topology] or "Not ready"))
    local counts = {}
    if #app.reactors > 0 then
      counts[#counts + 1] = "Reactors: " .. #app.reactors
    end
    if #app.turbines > 0 then
      counts[#counts + 1] = "Turbines: " .. #app.turbines
    end
    label(8, table.concat(counts, "   "))
    local storage = app.storage
    if storage then
      local chargeText = string.format("Stored: %.1f%%", storage.charge * 100)
      if app.topology == "direct" then
        chargeText = chargeText .. string.format("   Target: %.1f%%", app.config.targetCharge * 100)
      end
      label(10, chargeText, colors.lime)
      label(11, Util.format(storage.energy) .. " / " .. Util.format(storage.capacity) .. " FE")
      if app.topology ~= "turbine" then
        label(12, storage.source, colors.lightGray)
      end
    else
      label(10, "Energy storage unavailable", colors.orange)
    end
    if app.topology == "turbine" then
      label(13, string.format("Auto: Generate <=%.1f%%  Standby >=%.1f%%",
        app.config.generateBelow * 100, app.config.standbyAbove * 100), colors.lightGray)
    end
    local output = 0
    for _, device in ipairs(app.devices) do
      if device.kind ~= "storage" and device.online then
        output = output + (device.output or 0)
      end
    end
    label(14, "Generation: " .. Util.format(output) .. " FE/t")
    local standby = app.topology == "turbine" and "Spinning standby" or "Standby"
    local state = app.pendingResume and "Waiting to restore Auto"
      or (app.mode == "manual" and "Manual"
        or (app.control.calibrationSession and app.control.calibrationSession.active
          and app.control.calibrationTarget and "Calibrating"
          or (app.control.calibrationSession and app.control.calibrationSession.active
            and app.control.capacityCheck and app.control.capacityCheck.active and "Capacity check"
            or (app.control.standby and standby or "Generating"))))
    label(15, "State: " .. state)
    label(16, "Computer ID: " .. os.getComputerID() .. "  Remote peers: " .. #app.config.remotePeers, colors.lightGray)
    drawCalibrationSummary()
  end

  local function drawRodControls(reactor)
    local draft = ui.rodDrafts[reactor.id]
    if not draft then
      draft = {value = reactor.rods}
      ui.rodDrafts[reactor.id] = draft
    end
    if not draft.dirty or (draft.requested and math.abs(reactor.rods - draft.value) < 0.01) then
      draft.value = reactor.rods
      draft.dirty = false
      draft.requested = false
    end
    local status = draft.requested and "(requested)" or (draft.dirty and "(not applied)" or "")
    label(13, string.format("Rod target: %.0f%%  %s", draft.value, status), colors.cyan)
    local function setTarget(value)
      if app.mode ~= "manual" then
        return
      end
      draft.value = math.floor(Util.clamp(value, 0, 100) + 0.5)
      draft.dirty = true
      draft.requested = false
      ui.refresh()
    end
    button(2, 14, 12, reactor.active and "Deactivate" or "Activate", function()
      manual(reactor, "active", not reactor.active)
    end)
    for index, value in ipairs({0, 25, 50, 75, 100}) do
      button(15 + (index - 1) * 6, 14, 5, value .. "%", function() setTarget(value) end)
    end
    for index, delta in ipairs({-5, -1, 1, 5}) do
      button(2 + (index - 1) * 6, 15, 5, (delta > 0 and "+" or "") .. delta, function()
        setTarget(draft.value + delta)
      end)
    end
    button(26, 15, 8, "Apply", function()
      if app.mode ~= "manual" then
        return
      end
      draft.value = math.floor(Util.clamp(draft.value, 0, 100) + 0.5)
      manual(reactor, "rods", draft.value)
      draft.dirty = true
      draft.requested = true
      ui.refresh()
    end, colors.green)
    button(35, 15, 8, "Actual", function()
      draft.value = reactor.rods
      draft.dirty = false
      draft.requested = false
      ui.refresh()
    end)
    label(16, "Choose a target, then Apply", colors.lightGray)
  end

  local function drawReactors()
    local reactor = widgets.selector(app.reactors, app.config, "No devices")
    if not reactor then
      return
    end
    identify(reactor)
    if not reactor.online then
      label(11, "Unavailable: " .. tostring(reactor.error), colors.orange)
      return
    end
    label(10, string.format("%s  Rods: %.0f%%  Fuel: %s",
      reactor.active and "ON" or "OFF", reactor.rods, Util.format(reactor.fuel)))
    label(11, "Waste: " .. Util.format(reactor.waste) .. "   Temp: " .. Util.format(reactor.temperature) .. " C")
    label(12, reactor.cooled and ("Steam: " .. Util.format(reactor.steam) .. " mB/t")
      or ("Output: " .. Util.format(reactor.output) .. " FE/t"))
    if app.mode == "manual" then
      drawRodControls(reactor)
    else
      ui.rodDrafts[reactor.id] = nil
      label(14, "Switch to Manual to edit rod insertion", colors.lightGray)
    end
    label(17, "Higher rod insertion reduces output", colors.lightGray)
  end

  local function drawTurbines()
    local turbine = widgets.selector(app.turbines, app.config, "No devices")
    if not turbine then
      return
    end
    identify(turbine)
    if not turbine.online then
      label(11, "Unavailable: " .. tostring(turbine.error), colors.orange)
      return
    end
    label(10, string.format("RPM: %.0f / %.0f  %s",
      turbine.rpm, app.config.rpmTarget, turbine.coils and "Coils ON" or "Coils OFF"))
    label(11, "Steam: " .. Util.format(turbine.flow) .. " / " .. Util.format(turbine.flowLimit) .. " mB/t")
    label(12, "Output: " .. Util.format(turbine.output) .. " FE/t")
    local calibrationStatus, calibrationHint, calibrationColor = calibrationText(turbine)
    label(13, calibrationStatus, calibrationColor)
    button(2, 14, 10, turbine.active and "Deactivate" or "Activate", function()
      manual(turbine, "active", not turbine.active)
    end)
    button(13, 14, 9, "Coils", function() manual(turbine, "coils", not turbine.coils) end)
    button(23, 14, 9, "Flow -50", function() manual(turbine, "flow", turbine.flowLimit - 50) end)
    button(33, 14, 9, "Flow +50", function() manual(turbine, "flow", turbine.flowLimit + 50) end)
    label(16, "Auto RPM band:", colors.lightGray)
    button(17, 16, 10, "898 RPM", function() app.enqueue("rpm", nil, 898) end)
    button(28, 16, 11, "1796 RPM", function() app.enqueue("rpm", nil, 1796) end)
    label(17, calibrationHint, colors.lightGray)
  end

  local function drawStorage()
    local storage = widgets.selector(app.storageDevices(), app.config, "No devices")
    if storage then
      identify(storage)
      local selected = false
      for _, id in ipairs(app.config.storage) do
        if id == storage.id then
          selected = true
        end
      end
      if storage.online then
        label(11, Util.format(storage.energy) .. " / " .. Util.format(storage.capacity) .. " FE")
        label(12, string.format("Charge: %.1f%%   %s", storage.energy / storage.capacity * 100, storage.adapter or "storage"))
      else
        label(11, "Unavailable: " .. tostring(storage.error), colors.orange)
      end
      button(2, 14, 24, selected and "Remove from control" or "Use for control", function()
        app.enqueue("storage", storage.id)
      end)
    end
    label(16, "Choose ONE port per physical battery", colors.lightGray)
    label(17, "None selected = generator internal buffers", colors.lightGray)
  end

  function ui.refresh()
    refreshDisplay()
    refreshRodDrafts()
    if ui.editor then
      editName()
      return
    elseif ui.setup then
      ui.setup.refresh(width, height)
      return
    end
    widgets.clear()
    if width < 45 or height < 19 then
      label(2, "Display needs at least 45 x 19 cells", colors.orange)
      label(4, "Use a larger monitor or smaller text scale")
      return
    end

    drawNavigation()
    if ui.tab == "Overview" then
      drawOverview()
    elseif ui.tab == "Reactors" then
      drawReactors()
    elseif ui.tab == "Turbines" then
      drawTurbines()
    else
      drawStorage()
    end
    local warning = reactorStallWarning() or steamCapacityWarning() or turbineCapacityWarning()
    local message = app.problem or (app.calibrationSaveError and "Calibration NOT saved; retrying")
      or warning or app.message
    if message and message ~= "" then
      label(height - 1, message, (app.problem or app.fault or warning) and colors.orange or colors.lightGray)
    end
  end

  if selectDisplay then
    for _, event in ipairs({"peripheral", "peripheral_detach", "monitor_resize", "term_resize"}) do
      basalt.onEvent(event, function() ui.refresh() end)
    end
  end

  function ui.run()
    ui.refresh()
    basalt.schedule(function()
      while app.running do
        app.tick()
        ui.refresh()
        sleep(app.config.interval)
      end
      basalt.stop()
    end)
    basalt.run()
  end

  return ui
end

return UI
