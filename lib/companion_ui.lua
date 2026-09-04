local Util = require("lib.util")
local Presentation = require("lib.presentation")
local Display = require("lib.display")
local Widgets = require("lib.ui_widgets")
local version = require("lib.version")
local CompanionUI = {}
local MIN_WIDTH, MIN_HEIGHT = 23, 17
local COMPACT_TABS = {Overview = "All", Reactors = "Reactor", Turbines = "Turbine", Storage = "Power"}
local SHORT_TABS = {Reactors = "React", Turbines = "Turb"}

local function charge(device)
  return device.capacity > 0 and device.energy / device.capacity * 100 or 0
end

function CompanionUI.new(basalt, state, display, config)
  local startedAt = state.startedAt or Util.now()
  local ui = {
    tab = "Overview", index = {Reactors = 1, Turbines = 1, Storage = 1},
    chosen = false, buttons = {},
  }
  local frame = basalt.createFrame():setTerm(display):setBackground(colors.black):setForeground(colors.white)
  local width, height = display.getSize()
  local widgets = Widgets.new(frame, ui, function() return width end)
  local label, button = widgets.label, widgets.button

  local function chooseInitialTab(groups)
    if not ui.chosen then
      local onlyCategory, count = nil, 0
      for name, devices in pairs(groups) do
        if #devices > 0 then
          onlyCategory = name
          count = count + 1
        end
      end
      if count > 0 then
        ui.tab = count == 1 and onlyCategory or "Overview"
        ui.chosen = true
      end
    end
    if ui.tab ~= "Overview" and #groups[ui.tab] == 0 then
      ui.tab = "Overview"
    end
  end

  local function drawHeader()
    label(1, "REACTOR PEER #" .. state.id .. "  " .. version, colors.cyan)
    local contactAge = math.max(0, Util.now() - (state.lastContact or startedAt))
    if contactAge > 10 then
      label(2, "Controller #" .. state.owner, colors.orange)
      local prefix = width < 35 and "No contact: " or "Controller contact: "
      local message = state.lastContact and (prefix .. math.floor(contactAge) .. "s ago")
        or "Waiting for controller contact"
      label(3, message, colors.orange)
    end
  end

  local function drawTabs(groups)
    local tabs = Presentation.tabs(groups)
    local labels, textWidth = {}, 0
    for index, name in ipairs(tabs) do
      labels[index] = width >= 45 and name or COMPACT_TABS[name]
      textWidth = textWidth + #labels[index]
    end

    -- Reserve both outer margins and a one-cell gap between every pair of tabs.
    local availableWidth = width - 2 - (#tabs - 1)
    if textWidth > availableWidth then
      for index, name in ipairs(tabs) do
        local shorter = SHORT_TABS[name]
        if shorter then
          textWidth = textWidth - #labels[index] + #shorter
          labels[index] = shorter
        end
      end
    end
    -- Compact buttons follow their labels instead of filling unused screen space.
    local padding = math.min(2, math.floor((availableWidth - textWidth) / #tabs))
    local column = 2
    for index, name in ipairs(tabs) do
      local text = labels[index]
      local tabWidth = width >= 45 and 10 or #text + padding
      button(column, 5, tabWidth, text, function()
        ui.tab = name
        ui.chosen = true
        ui.refresh()
      end, ui.tab == name and colors.blue or colors.gray)
      if text ~= name then
        ui.buttons[name] = ui.buttons[text]
      end
      column = column + tabWidth + 1
    end
  end

  local function drawReactor(reactor)
    label(10, string.format("%s  Rods: %.1f%%", reactor.active and "ON" or "OFF", reactor.rods))
    label(11, "Fuel: " .. Util.format(reactor.fuel) .. "  Waste: " .. Util.format(reactor.waste) .. " mB")
    label(12, "Fuel temp: " .. Util.format(reactor.temperature) .. " C")
    label(13, reactor.cooled and ("Steam: " .. Util.format(reactor.steam) .. " mB/t")
      or ("Output: " .. Util.format(reactor.output) .. " FE/t"))
    label(15, string.format("Energy: %.1f%%", charge(reactor)))
    label(16, Util.format(reactor.energy) .. " / " .. Util.format(reactor.capacity) .. " FE")
    if reactor.cooled then
      label(17, "Steam tank: " .. Util.format(reactor.hot) .. " / " .. Util.format(reactor.hotCapacity) .. " mB")
    end
  end

  local function drawTurbine(turbine)
    label(10, string.format("%s  RPM: %.0f", turbine.active and "ON" or "OFF", turbine.rpm))
    label(11, "Coils: " .. (turbine.coils and "engaged" or "disengaged"))
    label(12, "Steam: " .. Util.format(turbine.flow) .. " / " .. Util.format(turbine.flowLimit) .. " mB/t")
    label(13, "Intake: " .. Util.format(turbine.flowMax) .. " mB/t")
    label(14, "Output: " .. Util.format(turbine.output) .. " FE/t")
    label(16, string.format("Energy: %.1f%%", charge(turbine)))
    label(17, Util.format(turbine.energy) .. " / " .. Util.format(turbine.capacity) .. " FE")
  end

  local function drawStorage(storage)
    label(11, string.format("Stored charge: %.1f%%", charge(storage)), colors.lime)
    label(13, "Stored: " .. Util.format(storage.energy) .. " FE")
    label(14, "Capacity: " .. Util.format(storage.capacity) .. " FE")
  end

  function ui.refresh()
    local nextWidth, nextHeight = display.getSize()
    if nextWidth ~= width or nextHeight ~= height then
      frame:term_resize()
    end
    width, height = nextWidth, nextHeight
    widgets.clear()
    if width < MIN_WIDTH or height < MIN_HEIGHT then
      label(2, "Display needs 23 x 17 cells", colors.orange)
      label(4, "Companion service continues running")
      return
    end

    local groups = Presentation.groups(state.devices)
    chooseInitialTab(groups)
    drawHeader()
    drawTabs(groups)
    if ui.tab == "Overview" then
      for index, text in ipairs(Presentation.overview(groups)) do
        label(6 + index, text)
      end
    else
      local device = widgets.selector(groups[ui.tab], config, "No local devices")
      if device then
        if not device.online then
          label(11, "Unavailable: " .. tostring(device.error), colors.orange)
        elseif device.kind == "reactor" then
          drawReactor(device)
        elseif device.kind == "turbine" then
          drawTurbine(device)
        else
          drawStorage(device)
        end
      end
    end
    if state.error then
      label(height - 1, state.error, colors.orange)
    end
  end

  basalt.onEvent("monitor_resize", function(name)
    local ok, monitorName = pcall(peripheral.getName, display)
    if ok and monitorName == name then
      ui.refresh()
    end
  end)
  basalt.onEvent("term_resize", function() ui.refresh() end)
  return ui
end

function CompanionUI.findMonitor()
  return Display.findMonitor(MIN_WIDTH, MIN_HEIGHT)
end

function CompanionUI.run(root, config, peer)
  local display, monitorName
  if config.companionDisplay.mode == "auto" then
    display, monitorName = CompanionUI.findMonitor()
    if not display then
      return -- Keep serving without a screen; the companion retries later.
    end
  else
    display = term.current()
  end
  assert(display.isColor(), "Use a colour monitor or Advanced Computer display")
  local width, height = display.getSize()
  assert(width >= MIN_WIDTH and height >= MIN_HEIGHT, "Display needs at least 23 x 17 cells; reduce its text scale")

  local environment = setmetatable({}, {__index = _ENV})
  environment._G = environment
  local basalt = assert(loadfile(fs.combine(root, "vendor/basalt.lua"), "t", environment))()
  basalt.getErrorManager().error = function(err) error(tostring(err), 0) end
  peer.refresh()
  local ui = CompanionUI.new(basalt, peer.state, display, config)
  ui.refresh()
  basalt.schedule(function()
    while true do
      sleep(config.interval)
      if monitorName then
        if not peripheral.hasType(monitorName, "monitor") then
          error("Monitor disconnected; waiting for display", 0)
        end
        local currentWidth, currentHeight = display.getSize()
        if currentWidth < MIN_WIDTH or currentHeight < MIN_HEIGHT then
          error("Monitor too small; waiting for suitable display", 0)
        end
      end
      peer.refresh()
      ui.refresh()
    end
  end)
  basalt.run()
end

return CompanionUI
