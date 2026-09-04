local Presentation = require("lib.presentation")
local Widgets = {}

function Widgets.new(frame, ui, getWidth)
  local widgets = {}

  function widgets.clear()
    frame:clear()
    ui.buttons = {}
  end

  function widgets.label(row, text, color, column)
    column = column or 2
    return frame:addLabel({
      x = column, y = row,
      text = tostring(text):sub(1, getWidth() - column),
      foreground = color or colors.white,
    })
  end

  function widgets.button(column, row, width, text, action, color, height)
    height = height or 1
    local button = frame:addButton({
      x = column, y = row, width = width, height = height, text = text,
      background = color or colors.gray, foreground = colors.white,
    })
    button:onClick(action)
    ui.buttons[text] = {x = column, y = row, width = width, height = height, action = action}
    return button
  end

  function widgets.selector(devices, config, emptyText)
    local count = #devices
    local index = math.max(1, math.min(count, ui.index[ui.tab] or 1))
    ui.index[ui.tab] = index
    widgets.button(2, 7, 3, "<", function()
      ui.index[ui.tab] = math.max(1, index - 1)
      ui.refresh()
    end, nil, 3)
    widgets.button(getWidth() - 4, 7, 3, ">", function()
      ui.index[ui.tab] = math.min(count, index + 1)
      ui.refresh()
    end, nil, 3)
    local countText = count > 0 and string.format("%d/%d", index, count) or "0/0"
    widgets.label(7, countText, colors.lightGray, 7)
    if count > 0 then
      local location, name = Presentation.deviceHeading(devices[index], config)
      widgets.label(8, location, colors.cyan, 7)
      -- Keep the heading clear of the three-row right navigation button.
      widgets.label(9, Presentation.fitName(name, math.max(1, getWidth() - 12)), colors.white, 7)
    else
      widgets.label(8, emptyText, colors.lightGray, 7)
    end
    return devices[index]
  end

  return widgets
end

return Widgets
