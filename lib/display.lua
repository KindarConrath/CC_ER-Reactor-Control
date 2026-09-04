-- Shared monitor discovery for controller and companion dashboards.
local M={}
function M.usable(display,minWidth,minHeight)
  local ok,usable=pcall(function()
    if not display or not display.isColor() then return false end
    local width,height=display.getSize()
    return width>=(minWidth or 45) and height>=(minHeight or 19)
  end)
  return ok and usable
end
function M.findMonitor(minWidth,minHeight)
  local names=peripheral.getNames();table.sort(names)
  for _,name in ipairs(names) do
    local ok,display=pcall(function()
      if peripheral.hasType(name,"monitor") then return peripheral.wrap(name) end
    end)
    if ok and M.usable(display,minWidth,minHeight) then return display,name end
  end
end
function M.controller(config,computer)
  local selected,name
  return function()
    if config.controllerDisplay.mode=="auto" then
      -- Keep a working monitor instead of switching whenever another is attached.
      local ok,present=pcall(peripheral.hasType,name or "","monitor")
      if name and ok and present and M.usable(selected) then return selected end
      selected,name=M.findMonitor()
      if selected then return selected end
    end
    return computer
  end
end
return M
