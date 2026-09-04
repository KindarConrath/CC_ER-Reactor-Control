-- Companion transport and optional local telemetry. No control policy lives here.
local Util = require("lib.util")
local Network = require("lib.network")
local Companion = {}

function Companion.new(ownerId, config, devices)
  local state = {
    owner = ownerId,
    id = os.getComputerID(),
    devices = {},
    lastContact = nil,
    startedAt = Util.now(),
  }
  local handleRequest = Network.serverHandler(ownerId, config, devices)
  local peer = {state = state}

  function peer.receive(senderId, message)
    local reply = handleRequest(senderId, message)
    if reply then
      state.lastContact = Util.now()
    end
    return reply
  end

  function peer.refresh()
    local succeeded, deviceList = pcall(devices.poll, config)
    state.devices = succeeded and deviceList or {}
    state.error = not succeeded and tostring(deviceList) or nil
    state.updatedAt = succeeded and Util.now() or nil
  end

  function peer.serve()
    while true do
      Network.open()
      local senderId, message = rednet.receive(Network.protocol, 1)
      if senderId then
        local reply = peer.receive(senderId, message)
        if reply then
          rednet.send(senderId, reply, Network.protocol)
        end
      end
    end
  end

  return peer
end

function Companion.display(config, peer, runUI)
  local previousError
  while true do
    local succeeded, displayError = pcall(runUI, config, peer)
    if not succeeded and tostring(displayError) == "Terminated" then
      error(displayError, 0)
    end
    if not succeeded and tostring(displayError) ~= previousError then
      previousError = tostring(displayError)
      print("Companion display waiting: " .. previousError)
    end
    sleep(2)
  end
end

function Companion.run(config, peer, runUI)
  if config.companionDisplay.mode == "off" then
    peer.serve()
  else
    parallel.waitForAll(peer.serve, function()
      Companion.display(config, peer, runUI)
    end)
  end
end

return Companion
