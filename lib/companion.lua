-- Companion transport and optional local telemetry. No control policy lives here.
local U=require("lib.util")
local Network=require("lib.network")
local M={}
function M.new(owner,c,devices)
  local state={owner=owner,id=os.getComputerID(),devices={},lastContact=nil,startedAt=U.now()}
  local handle=Network.serverHandler(owner,c,devices)
  local peer={state=state}
  function peer.receive(sender,msg)
    local reply=handle(sender,msg)
    if reply then state.lastContact=U.now() end
    return reply
  end
  function peer.refresh()
    local ok,list=pcall(devices.poll,c)
    state.devices=ok and list or {}
    state.error=not ok and tostring(list) or nil
    state.updatedAt=ok and U.now() or nil
  end
  function peer.serve()
    while true do
      Network.open()
      local sender,msg=rednet.receive(Network.protocol,1)
      if sender then
        local reply=peer.receive(sender,msg)
        if reply then rednet.send(sender,reply,Network.protocol) end
      end
    end
  end
  return peer
end
function M.display(c,peer,runUI)
  local previousError
  while true do
    local ok,err=pcall(runUI,c,peer)
    if not ok and tostring(err)=="Terminated" then error(err,0) end
    if not ok and tostring(err)~=previousError then
      print("Companion display waiting: "..tostring(err));previousError=tostring(err)
    end
    sleep(2)
  end
end
function M.run(c,peer,runUI)
  if c.companionDisplay.mode=="off" then peer.serve()
  else
    parallel.waitForAll(peer.serve,function() M.display(c,peer,runUI) end)
  end
end
return M
