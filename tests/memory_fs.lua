-- In-memory CraftOS file API and table serialization for restart tests.
local MemoryFS={}
function MemoryFS.new()
  local files,dirs={}, {[""]=true}
  local function path(inputPath)
    local parts={}
    for part in inputPath:gmatch("[^/]+") do
      if part==".." then table.remove(parts) elseif part~="." then parts[#parts+1]=part end
    end
    return table.concat(parts,"/")
  end
  local fs={}
  function fs.combine(sourcePath,targetPath) return path(sourcePath.."/"..targetPath) end
  function fs.exists(inputPath) inputPath=path(inputPath);return files[inputPath]~=nil or dirs[inputPath]~=nil end
  function fs.isDir(inputPath) return dirs[path(inputPath)]==true end
  function fs.getDir(inputPath) return path(inputPath):match("^(.*)/") or "" end
  function fs.makeDir(inputPath)
    inputPath=path(inputPath);assert(files[inputPath]==nil);dirs[inputPath]=true
    if inputPath~="" then fs.makeDir(fs.getDir(inputPath)) end
  end
  function fs.delete(inputPath) inputPath=path(inputPath);files[inputPath]=nil;dirs[inputPath]=nil end
  function fs.move(sourcePath,targetPath)
    sourcePath=path(sourcePath);targetPath=path(targetPath);assert(files[sourcePath] and not fs.exists(targetPath));files[targetPath]=files[sourcePath];files[sourcePath]=nil
  end
  function fs.open(inputPath,mode)
    inputPath=path(inputPath)
    if mode=="r" then
      if not files[inputPath] then return nil end
      return {readAll=function() return files[inputPath] end,close=function() end}
    end
    assert(mode=="w" and dirs[fs.getDir(inputPath)] and not dirs[inputPath],"Bad write path "..inputPath)
    files[inputPath]=""
    return {write=function(contents) files[inputPath]=files[inputPath]..contents end,close=function() end}
  end
  local function serialize(value)
    if type(value)=="string" then return string.format("%q",value) end
    if type(value)~="table" then return tostring(value) end
    local entries={}
    for key,item in pairs(value) do entries[#entries+1]="["..serialize(key).."]="..serialize(item) end
    return "{"..table.concat(entries,",").."}"
  end
  local textutils={serialize=serialize,unserialize=function(contents)
    local chunk=load("return "..contents,"settings","t",{})
    if not chunk then return nil end
    local ok,value=pcall(chunk);return ok and value or nil
  end}
  return fs,textutils,files
end
return MemoryFS
