-- Deliberately approximate dynamics for UI/regression tests, not a physics model.
local Util = require("lib.util")
local Demo = {}

function Demo.new(directPower)
  local devices = {}
  local writes = {}

  local function makeReactor(reactorNumber)
    return {
      id = "demo/reactor" .. reactorNumber,
      name = "reactor" .. reactorNumber,
      label = "Demo reactor " .. reactorNumber,
      kind = "reactor",
      online = true,
      active = false,
      cooled = not directPower,
      rods = 80,
      fuel = 5000,
      waste = 100,
      temperature = 400,
      energy = 5000000,
      capacity = 10000000,
      output = 0,
      steam = 0,
      hot = 10000,
      hotCapacity = 20000,
    }
  end

  devices[1] = makeReactor(1)
  if directPower then
    devices[2] = makeReactor(2)
  else
    for turbineNumber = 1, 2 do
      devices[#devices + 1] = {
        id = "demo/turbine" .. turbineNumber,
        name = "turbine" .. turbineNumber,
        label = "Demo turbine " .. turbineNumber,
        kind = "turbine",
        online = true,
        active = false,
        energy = 5000000,
        capacity = 10000000,
        output = 0,
        rpm = 0,
        flow = 0,
        flowLimit = 0,
        flowMax = 2000,
        coils = false,
      }
    end
  end

  devices[#devices + 1] = {
    id = "demo/battery",
    name = "battery",
    label = "Demo battery",
    kind = "storage",
    online = true,
    identity = "demo-battery",
    adapter = "simulated FE",
    energy = 650000000,
    capacity = 1000000000,
  }

  local backend = {devices = devices, writes = writes, time = 0}

  function backend.poll()
    return Util.copy(devices), {}
  end

  function backend.write(commands)
    for _, command in ipairs(commands) do
      writes[#writes + 1] = Util.copy(command)
      for _, device in ipairs(devices) do
        if device.name == command.name then
          local field = ({
            rods = "rods",
            active = "active",
            flow = "flowLimit",
            coils = "coils",
          })[command.op]
          assert(field, "Bad demo command")
          device[field] = command.value
        end
      end
    end
  end

  function backend.advance(elapsed)
    elapsed = math.min(elapsed, 3)
    backend.time = backend.time + elapsed

    local totalSteam = 0
    local totalOutput = 0
    for _, reactor in ipairs(devices) do
      if reactor.kind == "reactor" then
        local outputFraction = reactor.active and (100 - reactor.rods) / 100 or 0
        reactor.steam = reactor.steam
          + (outputFraction * 4000 - reactor.steam) * math.min(elapsed / 4, 1)
        reactor.output = directPower and outputFraction * 80000 or 0
        totalSteam = totalSteam + reactor.steam
        totalOutput = totalOutput + reactor.output
      end
    end

    local requestedSteam = 0
    for _, turbine in ipairs(devices) do
      if turbine.kind == "turbine" and turbine.active then
        requestedSteam = requestedSteam + turbine.flowLimit
      end
    end

    for _, turbine in ipairs(devices) do
      if turbine.kind == "turbine" then
        turbine.flow = turbine.active
          and turbine.flowLimit * math.min(1, totalSteam / math.max(1, requestedSteam)) or 0
        local inductionDrag = turbine.coils and 0.7 or 0.03
        turbine.rpm = math.max(0,
          turbine.rpm + (turbine.flow * 1.2 - turbine.rpm * inductionDrag) * elapsed / 12)
        turbine.output = turbine.coils and turbine.rpm * 25 or 0
        totalOutput = totalOutput + turbine.output
      end
    end

    local battery = devices[#devices]
    local load = 45000 + 20000 * math.sin(backend.time / 80)
    battery.energy = Util.clamp(
      battery.energy + (totalOutput - load) * 20 * elapsed, 0, battery.capacity)
    for _, generator in ipairs(devices) do
      if generator.kind ~= "storage" then
        generator.energy = battery.energy / battery.capacity * generator.capacity
      end
    end
    devices[1].hot = Util.clamp(
      devices[1].hot + (totalSteam - requestedSteam) * 20 * elapsed,
      0,
      devices[1].hotCapacity)
  end

  return backend
end

return Demo
