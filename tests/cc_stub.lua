-- Minimal terminal/peripheral API for rendering the actual Basalt bundle.
colors={}; for i,n in ipairs({"white","orange","magenta","lightBlue","yellow","lime","pink","gray",
  "lightGray","cyan","purple","blue","brown","green","red","black"}) do colors[n]=2^(i-1) end
colours=colors
keys={}; for i,n in ipairs({"backspace","delete","down","enter","escape","home","left","pageDown","pageUp","right","tab","up"}) do keys[n]=i end
local x,y,fg,bg=1,1,"0","f"
screen={}; for row=1,19 do screen[row]={text=string.rep(" ",51),fg=string.rep("0",51),bg=string.rep("f",51)} end
local function hex(c) return string.format("%x",math.floor(math.log(c)/math.log(2)+.5)) end
term={}
function term.current() return term end
term.native=term.current
function term.redirect(t) return term end
function term.getSize() return 51,19 end
function term.isColor() return true end
term.isColour=term.isColor
function term.getCursorPos() return x,y end
function term.setCursorPos(a,b) x=a;y=b end
function term.setCursorBlink() end
function term.getCursorBlink() return false end
function term.setTextColor(c) fg=hex(c) end
term.setTextColour=term.setTextColor
function term.setBackgroundColor(c) bg=hex(c) end
term.setBackgroundColour=term.setBackgroundColor
function term.getTextColor() return colors.white end
function term.getBackgroundColor() return colors.black end
function term.getPaletteColor() return 0,0,0 end
term.getPaletteColour=term.getPaletteColor
function term.blit(text,f,b)
  assert(#text==#f and #text==#b,"Invalid terminal blit")
  if screen[y] then
    for key,value in pairs({text=text,fg=f,bg=b}) do
      screen[y][key]=(screen[y][key]:sub(1,x-1)..value..screen[y][key]:sub(x+#text)):sub(1,51)
    end
  end
  x=x+#text
end
function term.write(text) term.blit(text,fg:rep(#text),bg:rep(#text)) end
function term.clear() for row=1,19 do screen[row]={text=(" "):rep(51),fg=fg:rep(51),bg=bg:rep(51)} end end
function term.clearLine() end
function term.scroll() end
fs={}
function fs.combine(a,b) return a=="" and b or a.."/"..b end
function fs.getDir(path) return path:match("^(.*)/") or "" end
function fs.exists(path) local f=io.open(path,"r"); if f then f:close();return true end; return false end
function fs.list() return {} end
function fs.delete(path) os.remove(path) end
function fs.open(path,mode)
  local f=io.open(path,mode); if not f then return nil end
  return {readAll=function() return f:read("*a") end,write=function(s) f:write(s) end,close=function() f:close() end}
end
peripheral={getNames=function() return {} end,hasType=function() return false end}
function peripheral.getType(v) if v==term then error("not a peripheral") end; return "monitor" end
function peripheral.getName(v) if v==term then error("not a peripheral") end; return "monitor_0" end
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
