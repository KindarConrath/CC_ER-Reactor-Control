local Util = require("lib.util")
local Network = {protocol = "er-control/0.1"}
local COMMAND_LEASE_SECONDS = 5
local MAX_BATCH_COMMANDS = 256
local sequence = 0
local session = tostring(os.getComputerID()) .. ":" .. tostring(Util.now())

local connectionError = {
  __tostring = function(err)
    return err.message
  end,
}

function Network.isConnectionError(err)
  return type(err) == "table" and getmetatable(err) == connectionError
end

local function disconnected(peerId, reason)
  error(setmetatable({
    peer = peerId,
    message = "Peer #" .. peerId .. ": " .. reason,
  }, connectionError), 0)
end

function Network.open()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      rednet.open(name)
    end
  end
end

function Network.request(peerId, operation, data, timeout)
  sequence = sequence + 1
  local requestId = session .. ":" .. sequence
  local request = {id = requestId, op = operation, data = data}
  if not rednet.send(peerId, request, Network.protocol) then
    disconnected(peerId, "no open modem")
  end

  local deadline = Util.now() + timeout
  repeat
    local remaining = math.max(0, deadline - Util.now())
    local sender, response = rednet.receive(Network.protocol, remaining)
    if sender == peerId and type(response) == "table"
        and response.id == requestId and response.reply == true then
      if not response.ok then
        local reason = tostring(response.error):gsub("^.-:%d+: ", "")
        error("Peer #" .. peerId .. ": " .. reason, 0)
      end
      return response.data
    end
  until Util.now() >= deadline
  disconnected(peerId, "no response")
end

function Network.serverHandler(ownerId, config, devices)
  local token, issuedAt, serial = nil, 0, 0

  return function(sender, request)
    if sender ~= ownerId or type(request) ~= "table"
        or type(request.id) ~= "string" or request.reply then
      return
    end

    local ok, result = pcall(function()
      if request.op == "poll" then
        serial = serial + 1
        token = session .. ":" .. serial
        issuedAt = Util.now()
        return {devices = devices.poll(config), token = token}
      elseif request.op == "write" then
        local batch = request.data
        assert(type(batch) == "table" and batch.token == token and token ~= nil
          and Util.now() - issuedAt < COMMAND_LEASE_SECONDS,
          "Expired command batch; poll again")
        token = nil -- Consume before writing so partial failures cannot be replayed.
        assert(type(batch.commands) == "table" and #batch.commands <= MAX_BATCH_COMMANDS,
          "Invalid command batch")
        for _, command in ipairs(batch.commands) do
          devices.write(command, config)
        end
        return true
      end
      error("Unknown operation")
    end)

    return {
      id = request.id,
      reply = true,
      ok = ok,
      data = ok and result or nil,
      error = not ok and tostring(result) or nil,
    }
  end
end

return Network
