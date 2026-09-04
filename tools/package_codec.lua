-- Embedded payloads use fixed-width 12-bit LZW, encoded as base64. No downloads
-- or external decompressor are needed. Validate size and Adler-32 before use.
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
local function unpackFile(item)
  local bytes,bits,value={},0,0
  for char in item[3]:gmatch('.') do
    if char~='=' then
      local digit=assert(digits[char],'Damaged package encoding')
      value=value*64+digit;bits=bits+6
      if bits>=8 then bits=bits-8;bytes[#bytes+1]=string.char(math.floor(value/2^bits));value=value%2^bits end
    end
  end
  local packed=table.concat(bytes);local dictionary={}
  local function reset() dictionary={};for i=0,255 do dictionary[i]=string.char(i) end end
  reset()
  local nextCode,offset,half,previous=256,1,false,nil
  local output={}
  while offset+1<=#packed do
    local code
    if not half then code=packed:byte(offset)*16+math.floor(packed:byte(offset+1)/16);half=true
    else
      if offset+2>#packed then break end
      code=(packed:byte(offset+1)%16)*256+packed:byte(offset+2);offset=offset+3;half=false
    end
    local entry=dictionary[code]
    if not entry and previous and code==nextCode then entry=previous..previous:sub(1,1) end
    assert(entry,'Damaged package dictionary')
    output[#output+1]=entry
    if previous then
      if nextCode<4096 then dictionary[nextCode]=previous..entry:sub(1,1);nextCode=nextCode+1
      else reset();nextCode=256 end
    end
    previous=entry
  end
  local data=table.concat(output);assert(#data==item[1],'Damaged package length')
  local a,b=1,0
  for i=1,#data do a=(a+data:byte(i))%65521;b=(b+a)%65521 end
  assert(b*65536+a==item[2],'Damaged package checksum')
  return data
end
local function writeFile(path,data)
  local parent=fs.getDir(path)
  if not fs.exists(parent) then fs.makeDir(parent) end
  local f=assert(fs.open(path,'w'),'Cannot write '..path)
  local ok,err=pcall(f.write,data)
  local closed,closeError=pcall(f.close)
  assert(ok,err);assert(closed,closeError)
end
local function checkSpace(path,required)
  -- Allow allocation overhead and room for subsequent saved settings.
  required=required+16384
  local existing=path
  while not fs.exists(existing) do
    local parent=fs.getDir(existing)
    assert(parent~=existing,'Cannot locate installation drive')
    existing=parent
  end
  local available=fs.getFreeSpace(existing)
  if type(available)=='number' and available<required then
    error(string.format('Not enough disk space: need about %d KB free; have %d KB. No installation files changed. Move old installer/update downloads out of this computer, then retry.',math.ceil(required/1024),math.floor(available/1024)),0)
  end
end
