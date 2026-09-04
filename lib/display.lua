-- Shared monitor discovery for controller and companion dashboards.
local Display = {}

function Display.usable(display, minimumWidth, minimumHeight)
  local succeeded, usable = pcall(function()
    if not display or not display.isColor() then
      return false
    end
    local width, height = display.getSize()
    return width >= (minimumWidth or 45) and height >= (minimumHeight or 19)
  end)
  return succeeded and usable
end

function Display.findMonitor(minimumWidth, minimumHeight)
  local peripheralNames = peripheral.getNames()
  table.sort(peripheralNames)
  for _, peripheralName in ipairs(peripheralNames) do
    local succeeded, monitor = pcall(function()
      if peripheral.hasType(peripheralName, "monitor") then
        return peripheral.wrap(peripheralName)
      end
    end)
    if succeeded and Display.usable(monitor, minimumWidth, minimumHeight) then
      return monitor, peripheralName
    end
  end
end

function Display.controller(config, computerDisplay)
  local selectedMonitor
  local selectedName
  return function()
    if config.controllerDisplay.mode == "auto" then
      -- Keep a working monitor instead of switching whenever another is attached.
      local succeeded, present = pcall(peripheral.hasType, selectedName or "", "monitor")
      if selectedName and succeeded and present and Display.usable(selectedMonitor) then
        return selectedMonitor
      end
      selectedMonitor, selectedName = Display.findMonitor()
      if selectedMonitor then
        return selectedMonitor
      end
    end
    return computerDisplay
  end
end

return Display
