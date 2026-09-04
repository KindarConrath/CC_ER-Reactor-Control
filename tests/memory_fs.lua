-- In-memory CraftOS file API and table serialization for restart tests.
local M={}
function M.new()
  local files,dirs={}, {[""]=true}
  local function path(p)
    local parts={}
    for part in p:gmatch("[^/]+") do
      if part==".." then table.remove(parts) elseif part~="." then parts[#parts+1]=part end
    end
    return table.concat(parts,"/")
  end
  local fs={}
  function fs.combine(a,b) return path(a.."/"..b) end
  function fs.exists(p) p=path(p);return files[p]~=nil or dirs[p]~=nil end
  function fs.isDir(p) return dirs[path(p)]==true end
  function fs.getDir(p) return path(p):match("^(.*)/") or "" end
  function fs.makeDir(p)
    p=path(p);assert(files[p]==nil);dirs[p]=true
    if p~="" then fs.makeDir(fs.getDir(p)) end
  end
  function fs.delete(p) p=path(p);files[p]=nil;dirs[p]=nil end
  function fs.move(a,b)
    a=path(a);b=path(b);assert(files[a] and not fs.exists(b));files[b]=files[a];files[a]=nil
  end
  function fs.open(p,mode)
    p=path(p)
    if mode=="r" then
      if not files[p] then return nil end
      return {readAll=function() return files[p] end,close=function() end}
    end
    assert(mode=="w" and dirs[fs.getDir(p)] and not dirs[p],"Bad write path "..p)
    files[p]=""
    return {write=function(s) files[p]=files[p]..s end,close=function() end}
  end
  local function serialize(value)
    if type(value)=="string" then return string.format("%q",value) end
    if type(value)~="table" then return tostring(value) end
    local entries={}
    for key,item in pairs(value) do entries[#entries+1]="["..serialize(key).."]="..serialize(item) end
    return "{"..table.concat(entries,",").."}"
  end
  local textutils={serialize=serialize,unserialize=function(s)
    local f=load("return "..s,"settings","t",{})
    if not f then return nil end
    local ok,value=pcall(f);return ok and value or nil
  end}
  return fs,textutils,files
end
return M
