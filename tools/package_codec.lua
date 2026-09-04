-- Embedded payloads use fixed-width 12-bit LZW, encoded as base64. No downloads
-- or external decompressor are needed. Validate size and Adler-32 before use.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits = {}
for index = 1, #alphabet do
  digits[alphabet:sub(index, index)] = index - 1
end

local function unpackFile(item)
  local bytes = {}
  local bitCount = 0
  local bitValue = 0
  for character in item[3]:gmatch(".") do
    if character ~= "=" then
      local digit = assert(digits[character], "Damaged package encoding")
      bitValue = bitValue * 64 + digit
      bitCount = bitCount + 6
      if bitCount >= 8 then
        bitCount = bitCount - 8
        bytes[#bytes + 1] = string.char(math.floor(bitValue / 2 ^ bitCount))
        bitValue = bitValue % 2 ^ bitCount
      end
    end
  end

  local packed = table.concat(bytes)
  local dictionary = {}
  local function resetDictionary()
    dictionary = {}
    for code = 0, 255 do
      dictionary[code] = string.char(code)
    end
  end

  resetDictionary()
  local nextCode = 256
  local offset = 1
  local secondCode = false
  local previous
  local output = {}
  while offset + 1 <= #packed do
    local code
    if not secondCode then
      code = packed:byte(offset) * 16 + math.floor(packed:byte(offset + 1) / 16)
      secondCode = true
    else
      if offset + 2 > #packed then
        break
      end
      code = (packed:byte(offset + 1) % 16) * 256 + packed:byte(offset + 2)
      offset = offset + 3
      secondCode = false
    end

    local entry = dictionary[code]
    if not entry and previous and code == nextCode then
      entry = previous .. previous:sub(1, 1)
    end
    assert(entry, "Damaged package dictionary")
    output[#output + 1] = entry

    if previous then
      if nextCode < 4096 then
        dictionary[nextCode] = previous .. entry:sub(1, 1)
        nextCode = nextCode + 1
      else
        resetDictionary()
        nextCode = 256
      end
    end
    previous = entry
  end

  local data = table.concat(output)
  assert(#data == item[1], "Damaged package length")
  local sum1 = 1
  local sum2 = 0
  for index = 1, #data do
    sum1 = (sum1 + data:byte(index)) % 65521
    sum2 = (sum2 + sum1) % 65521
  end
  assert(sum2 * 65536 + sum1 == item[2], "Damaged package checksum")
  return data
end

local function writeFile(path, data)
  local parent = fs.getDir(path)
  if not fs.exists(parent) then
    fs.makeDir(parent)
  end
  local file = assert(fs.open(path, "w"), "Cannot write " .. path)
  local writeSucceeded, writeError = pcall(file.write, data)
  local closeSucceeded, closeError = pcall(file.close)
  assert(writeSucceeded, writeError)
  assert(closeSucceeded, closeError)
end

local function checkSpace(path, required)
  -- Allow allocation overhead and room for subsequent saved settings.
  required = required + 16384
  local existing = path
  while not fs.exists(existing) do
    local parent = fs.getDir(existing)
    assert(parent ~= existing, "Cannot locate installation drive")
    existing = parent
  end
  local available = fs.getFreeSpace(existing)
  if type(available) == "number" and available < required then
    error(string.format(
      "Not enough disk space: need about %d KB free; have %d KB. "
        .. "No installation files changed. Move old installer/update downloads out of this "
        .. "computer, then retry.",
      math.ceil(required / 1024),
      math.floor(available / 1024)), 0)
  end
end
