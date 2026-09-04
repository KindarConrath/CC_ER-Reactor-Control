local SetupUI = {}
local PEERS_PER_PAGE = 5

function SetupUI.new(frame, app, widgets, close)
  local panel = {page = "Peers", pageNumber = 1, draft = ""}
  local label, button = widgets.label, widgets.button
  local input, statusLabel, faultLabel

  local function submit(operation, id, value)
    if panel.pending then
      return
    end
    panel.pending = app.configureSetup(operation, id, value)
    panel.message = "Saving..."
    panel.failed = false
    panel.refresh(panel.width, panel.height)
  end

  local function acceptResult()
    local result = app.setupResult
    if not (panel.pending and result and result.request == panel.pending) then
      return
    end
    if result.ok and panel.pending.op == "peer" and panel.pending.value then
      panel.draft = ""
      if input then
        input:setText("")
      end
    end
    panel.pending = nil
    panel.message = result.message
    panel.failed = not result.ok
  end

  local function drawPeers(width, peers, pages)
    label(6, "Configured peers: " .. #peers, colors.lightGray)
    local first = (panel.pageNumber - 1) * PEERS_PER_PAGE + 1
    for row = 0, PEERS_PER_PAGE - 1 do
      local peerId = peers[first + row]
      if peerId then
        label(7 + row, "Peer #" .. peerId)
        button(width - 9, 7 + row, 8, "Remove", function() submit("peer", peerId, false) end)
      end
    end
    if #peers == 0 then
      label(8, "No peers added", colors.lightGray)
    end
    if pages > 1 then
      button(2, 12, 8, "Previous", function()
        panel.pageNumber = panel.pageNumber - 1
        panel.refresh(panel.width, panel.height)
      end)
      label(12, panel.pageNumber .. " / " .. pages, colors.lightGray, 16)
      button(width - 9, 12, 8, "Next", function()
        panel.pageNumber = panel.pageNumber + 1
        panel.refresh(panel.width, panel.height)
      end)
    end
    label(14, "Peer ID:")
    input = frame:addInput({
      x = 11, y = 14, width = width - 25, height = 1, maxLength = 10,
      text = panel.draft, background = colors.white, foreground = colors.black,
    })
    panel.input = input
    button(width - 12, 14, 11, "Add peer", function() submit("peer", input:getText(), true) end, colors.green)
  end

  local function drawDisplay()
    label(7, "Controller display", colors.lightGray)
    button(2, 9, 20, "Automatic monitor", function() submit("display", nil, "auto") end)
    button(24, 9, 19, "Computer screen", function() submit("display", nil, "terminal") end)
    panel.displayLabel = label(11, "")
  end

  local function drawTuning(width)
    local saved = 0
    for _, turbine in ipairs(app.turbines) do
      local entry = app.config.calibration[turbine.id]
      if entry and entry.rpm == app.config.rpmTarget and entry.generating then
        saved = saved + 1
      end
    end
    label(7, string.format("Turbine calibration: %d/%d saved", saved, #app.turbines),
      saved == #app.turbines and colors.lime or colors.orange)
    local session = app.control.calibrationSession
    local active = session and session.active
    if active then
      label(8, "Calibration is controlling the plant", colors.orange)
    elseif app.mode ~= "auto" then
      label(8, "Enable Auto before calibration", colors.lightGray)
    else
      label(8, "Runs each turbine, then checks reactor capacity", colors.lightGray)
    end
    button(2, 10, 21, active and "Restart calibration" or "Calibrate turbines", function()
      panel.message = nil
      panel.failed = false
      app.enqueue("calibrate")
    end, colors.orange)
    if app.calibrationSaveError then
      button(25, 10, 12, "Retry save", function()
        panel.message = nil
        panel.failed = false
        app.enqueue("save")
      end)
    end
    local capacity = app.config.calibration._capacity
    if capacity and saved == #app.turbines then
      label(12, capacity.status == "passed" and "Combined reactor capacity verified"
        or "Combined reactor capacity insufficient",
        capacity.status == "passed" and colors.lime or colors.orange)
    end
    label(14, "Manual or Stop cancels calibration", colors.lightGray)
  end

  local function rebuild(width, height, peers, pages, key)
    if input then
      panel.draft = input:getText()
    end
    input = nil
    panel.input = nil
    widgets.clear()
    panel.key = key
    label(1, "SETUP", colors.cyan)
    label(3, "Controller #" .. os.getComputerID())
    button(width - 19, 3, 8, "Stop all", function() app.enqueue("stop") end, colors.red)
    button(width - 9, 3, 8, "Back", close)
    local tabNames = {"Peers", "Display"}
    if app.topology == "turbine" then
      tabNames[#tabNames + 1] = "Tuning"
    end
    for index, name in ipairs(tabNames) do
      button(2 + (index - 1) * 12, 5, 11, name, function()
        panel.page = name
        panel.refresh(panel.width, panel.height)
      end, panel.page == name and colors.blue or colors.gray)
    end
    if panel.page == "Peers" then
      drawPeers(width, peers, pages)
    elseif panel.page == "Display" then
      drawDisplay()
    else
      drawTuning(width)
    end
    button(2, 16, 10, "Rescan", function()
      panel.message = nil
      panel.failed = false
      app.enqueue("rescan")
    end)
    statusLabel = label(height - 1, "")
    faultLabel = label(height, "", colors.orange)
  end

  function panel.refresh(width, height)
    panel.width, panel.height = width, height
    acceptResult()
    local peers = app.config.remotePeers
    local pages = math.max(1, math.ceil(#peers / PEERS_PER_PAGE))
    if panel.page == "Tuning" and app.topology ~= "turbine" then
      panel.page = "Peers"
    end
    panel.pageNumber = math.max(1, math.min(pages, panel.pageNumber))
    local session = app.control.calibrationSession
    local capacity = app.config.calibration._capacity
    local key = table.concat({panel.page, width, height, panel.pageNumber, table.concat(peers, ","),
      app.topology or "", app.mode, session and tostring(session.active) or "",
      capacity and capacity.status or "", tostring(app.calibrationDirty or false)}, "|")
    -- Rebuild only when layout or membership changes, preserving the live input otherwise.
    if panel.key ~= key then
      rebuild(width, height, peers, pages, key)
    end
    if panel.page == "Display" then
      local selected = app.config.controllerDisplay.mode == "auto" and "Automatic monitor" or "Computer screen"
      panel.displayLabel:setText("Selected: " .. selected)
    end
    statusLabel:setText((panel.message or app.message or ""):sub(1, width - 2))
    statusLabel:setForeground(panel.failed and colors.orange or colors.lightGray)
    local shortage = app.control.steamShortage
    local shortageMessage = shortage and "REACTOR LIMIT: insufficient steam capacity"
    local turbineLimit = app.control.turbineLimits and app.control.turbineLimits[1]
    local turbineMessage = turbineLimit and "TURBINE LIMIT: max flow; RPM falling"
    local reactorStall = app.control.reactorStalls and app.control.reactorStalls[1]
    local stallMessage = reactorStall and "REACTOR STALLED: no power or steam output"
    faultLabel:setText((app.problem or (app.fault and app.message) or stallMessage
      or shortageMessage or turbineMessage
      or (app.calibrationSaveError and "Calibration NOT saved; retry from Tuning") or ""):sub(1, width - 2))
  end

  return panel
end

return SetupUI
