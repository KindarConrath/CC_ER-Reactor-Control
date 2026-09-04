-- Minimal terminal/peripheral API for rendering the actual Basalt bundle.
colors={}; for index,name in ipairs({"white","orange","magenta","lightBlue","yellow","lime","pink","gray",
  "lightGray","cyan","purple","blue","brown","green","red","black"}) do colors[name]=2^(index-1) end
colours=colors
keys={}; for index,name in ipairs({"backspace","delete","down","enter","escape","home","left","pageDown","pageUp","right","tab","up"}) do keys[name]=index end
local cursorX,cursorY,foreground,background=1,1,"0","f"
screen={}; for row=1,19 do screen[row]={text=string.rep(" ",51),fg=string.rep("0",51),bg=string.rep("f",51)} end
local function hex(color) return string.format("%x",math.floor(math.log(color)/math.log(2)+.5)) end
term={}
function term.current() return term end
term.native=term.current
function term.redirect(target) return term end
function term.getSize() return 51,19 end
function term.isColor() return true end
term.isColour=term.isColor
function term.getCursorPos() return cursorX,cursorY end
function term.setCursorPos(column, row) cursorX=column;cursorY=row end
function term.setCursorBlink() end
function term.getCursorBlink() return false end
function term.setTextColor(color) foreground=hex(color) end
term.setTextColour=term.setTextColor
function term.setBackgroundColor(color) background=hex(color) end
term.setBackgroundColour=term.setBackgroundColor
function term.getTextColor() return colors.white end
function term.getBackgroundColor() return colors.black end
function term.getPaletteColor() return 0,0,0 end
term.getPaletteColour=term.getPaletteColor
function term.blit(text, foregroundMask, backgroundMask)
  assert(#text==#foregroundMask and #text==#backgroundMask,"Invalid terminal blit")
  if screen[cursorY] then
    for key,value in pairs({text=text,fg=foregroundMask,bg=backgroundMask}) do
      screen[cursorY][key]=(screen[cursorY][key]:sub(1,cursorX-1)..value..screen[cursorY][key]:sub(cursorX+#text)):sub(1,51)
    end
  end
  cursorX=cursorX+#text
end
function term.write(text) term.blit(text,foreground:rep(#text),background:rep(#text)) end
function term.clear() for row=1,19 do screen[row]={text=(" "):rep(51),fg=foreground:rep(51),bg=background:rep(51)} end end
function term.clearLine() end
function term.scroll() end
fs={}
function fs.combine(leftPath, rightPath)
  return leftPath=="" and rightPath or leftPath.."/"..rightPath
end
function fs.getDir(path) return path:match("^(.*)/") or "" end
function fs.exists(path)
  local file=io.open(path,"r")
  if file then file:close();return true end
  return false
end
function fs.list() return {} end
function fs.delete(path) os.remove(path) end
function fs.open(path,mode)
  local file=io.open(path,mode); if not file then return nil end
  return {readAll=function() return file:read("*a") end,
    write=function(contents) file:write(contents) end,
    close=function() file:close() end}
end
peripheral={getNames=function() return {} end,hasType=function() return false end}
function peripheral.getType(value) if value==term then error("not a peripheral") end; return "monitor" end
function peripheral.getName(value) if value==term then error("not a peripheral") end; return "monitor_0" end
shell={getRunningProgram=function() return "main.lua" end}
textutils={unserializeJSON=function() return {} end}
local timer=0; fakeTime=100
os.startTimer=function() timer=timer+1; return timer end
os.cancelTimer=function() end
os.queueEvent=function() end
os.epoch=function() return fakeTime*1000 end
os.clock=function() return fakeTime end
os.getComputerID=function() return 42 end
function sleep() coroutine.yield("timer") end
