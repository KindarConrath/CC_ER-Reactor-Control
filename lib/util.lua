local Util = {}
local SI_SUFFIXES = {"", "k", "M", "G", "T", "P"}

function Util.clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function Util.number(value)
  value = tonumber(value)
  assert(value and value == value and math.abs(value) < math.huge, "Invalid numeric reading")
  return value
end

function Util.copy(source)
  local copy = {}
  for key, value in pairs(source) do
    copy[key] = type(value) == "table" and Util.copy(value) or value
  end
  return copy
end

function Util.format(value)
  if not value then
    return "--"
  end
  local suffix = 1
  while math.abs(value) >= 1000 and suffix < #SI_SUFFIXES do
    value = value / 1000
    suffix = suffix + 1
  end
  return string.format("%.1f%s", value, SI_SUFFIXES[suffix])
end

function Util.now()
  return os.epoch("utc") / 1000
end

return Util
