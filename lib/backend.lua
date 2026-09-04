local Devices = require("lib.devices")
local Network = require("lib.network")
local Backend = {}

local function appendDevices(destination, devices, prefix, peerId)
  for _, device in ipairs(devices) do
    device.id = prefix .. device.name
    device.peer = peerId
    -- Explicit identities can join multiple ports of the same storage network.
    device.identity = device.identity or device.id
    if device.identity == device.name then
      device.identity = device.id
    end
    destination[#destination + 1] = device
  end
end

function Backend.new(config)
  local backend = {config = config}

  function backend.poll()
    Network.open() -- Discover modems attached since the previous poll.
    local devices, errors = {}, {}
    local connectionErrorsOnly = true
    appendDevices(devices, Devices.poll(config), "local/", nil)

    for _, peerId in ipairs(config.remotePeers) do
      local ok, response = pcall(Network.request, peerId, "poll", nil, config.remoteTimeout)
      if ok then
        appendDevices(devices, response.devices, "peer:" .. peerId .. "/", peerId)
      else
        errors[#errors + 1] = tostring(response)
        if not Network.isConnectionError(response) then
          connectionErrorsOnly = false
        end
      end
    end

    return devices, errors, #errors > 0 and connectionErrorsOnly
  end

  function backend.write(commands)
    local peerBatches = {}
    for _, command in ipairs(commands) do
      if command.peer then
        local batch = peerBatches[command.peer] or {}
        peerBatches[command.peer] = batch
        batch[#batch + 1] = command
      else
        Devices.write(command, config)
      end
    end

    for peerId, batch in pairs(peerBatches) do
      -- Acquire the lease immediately before writing; polling other peers can be slow.
      local response = Network.request(peerId, "poll", nil, config.remoteTimeout)
      Network.request(peerId, "write", {
        token = response.token,
        commands = batch,
      }, config.remoteTimeout)
    end
  end

  return backend
end

return Backend
