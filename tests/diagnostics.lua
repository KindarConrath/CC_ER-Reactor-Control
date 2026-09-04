package.path="./?.lua;"..package.path
local memory=require("tests.memory_fs")
local Settings=require("lib.settings")
local files
local count=0
os.getComputerID=function() return 42 end
os.epoch=function() return 100000 end
local function test(name, callback)
  fs,textutils,files=memory.new()
  local config = dofile("config.lua")
  config.remotePeers = {4, 5, 6}
  config.lastMode = "auto"
  config.autoSnapshot = {
    topology = "direct",
    generators = "old-plant",
    storage = "",
    peers = "4|5|6",
  }
  Settings.save(".", config)
  local succeeded, testError = pcall(callback)
  assert(succeeded, name .. ": " .. tostring(testError))
  count = count + 1
  print("PASS " .. name)
end
local methods={}
for index = 1, 500 do
  methods[#methods + 1] = string.format("method%03d", index)
end
peripheral={getNames=function() return {"left"} end,
  getType=function() return "BigReactors-Reactor","test_type" end,
  hasType=function(_,kind) return kind=="BigReactors-Reactor" end,
  getMethods=function() return methods end,
  wrap=function() error("Metadata probe must not read or write device controls") end}
local function command(...)
  local output={}
  local env=setmetatable({},{__index=_G});env._G=env
  env.shell={getRunningProgram=function() return "diagnostics.lua" end,resolve=function(path)
    return fs.combine(path:sub(1,1)=="/" and "" or "reports",path)
  end}
  env.print=function(text) output[#output+1]=tostring(text) end
  env.printError=function(text) output[#output+1]="ERROR: "..tostring(text) end
  env.require=function(name)
    if name=="lib.network" then return {open=function() end} end
    if name=="lib.backend" then return {new=function() return {poll=function()
      return {{id="peer:4/left",kind="reactor",online=true}}, {"Computer 6 did not respond"}
    end} end} end
    if name=="lib.app" or name=="lib.ui" or name=="lib.startup" then
      error("Diagnostics must not start the controller, UI or startup")
    end
    return require(name)
  end
  assert(loadfile("diagnostics.lua","t",env))(...)
  return output
end
test("probe file preserves all long lines and leaves saved Auto untouched",function()
  local original=files["settings.dat"]
  local screen=command("probe")
  local output=command("probe","--output","/probe.txt")
  assert(files["probe.txt"]==table.concat(screen,"\n").."\n")
  assert(files["probe.txt"]:find("method500",1,true) and #files["probe.txt"]>5000)
  assert(files["probe.txt"]:find("left (BigReactors-Reactor, test_type) -> reactor",1,true))
  assert(#output==1 and output[1]=="Saved diagnostic report to /probe.txt")
  assert(files["settings.dat"]==original)
end)
test("scan file includes remote errors and respects relative output paths",function()
  local original=files["settings.dat"]
  command("scan","--output","scan.txt")
  local text=assert(files["reports/scan.txt"])
  assert(text:find("Configured peers (3): 4, 5, 6",1,true))
  assert(text:find("peer:4/left  reactor  online",1,true))
  assert(text:find("ERROR: Computer 6 did not respond",1,true))
  assert(files["settings.dat"]==original)
end)
test("repeated output replaces the previous report completely",function()
  command("probe","--output","/probe.txt")
  local previous=methods;methods={"oneMethod"}
  command("probe","--output","/probe.txt")
  assert(files["probe.txt"]:find("oneMethod",1,true) and not files["probe.txt"]:find("method500",1,true))
  methods=previous
end)
test("output requires a filename and a diagnostic mode",function()
  for _,args in ipairs({{"probe","--output"},{"--output","/probe.txt"},{"--output","scan"},
      {"scan","probe"},{"scan","--peer","4"},{"scan","--output","--manual"}}) do
    assert(not pcall(command,table.unpack(args)))
  end
  assert(not files["probe.txt"])
end)
test("help does not require configured devices or alter saved settings",function()
  local original=files["settings.dat"]
  local output=command()
  assert(output[1]:find("diagnostics scan|probe",1,true))
  assert(table.concat(command("--help"),"\n")==table.concat(output,"\n"))
  assert(files["settings.dat"]==original)
end)
test("main directs obsolete report flags to the diagnostics command",function()
  local original=files["settings.dat"]
  local env=setmetatable({},{__index=_G});env._G=env
  env.shell={getRunningProgram=function() return "main.lua" end}
  for _,flag in ipairs({"--scan","--probe","--output"}) do
    local ok,err=pcall(assert(loadfile("main.lua","t",env)),flag)
    assert(not ok and tostring(err):find("diagnostics scan|probe",1,true))
  end
  assert(files["settings.dat"]==original)
end)
print(string.format("%d diagnostic export tests passed",count))
