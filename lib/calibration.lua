-- Learn operating points without changing the RPM controller's decisions.
local Calibration = {}
Calibration.STABLE_SECONDS = 10
local STABILITY_FRACTION = 0.10

local function differs(value, baseline, minimum)
  return math.abs(value - baseline) > math.max(minimum, math.abs(baseline) * STABILITY_FRACTION)
end

local function resetWindow(state)
  state.stable = 0
  state.flowTotal = 0
  state.outputTotal = 0
  state.anchorFlow = nil
  state.anchorOutput = nil
end

function Calibration.update(control, config, turbine, phase, acceleration, elapsed, points)
  local state = control.calibration
  if not state or state.phase ~= phase or state.rpm ~= config.rpmTarget then
    state = {phase = phase, rpm = config.rpmTarget}
    resetWindow(state)
    control.calibration = state
  end
  if state.complete then
    return false
  end
  local eligible = phase ~= "spinup" and turbine.active
    and turbine.coils == (phase == "generating")
    and math.abs(turbine.rpm - state.rpm) <= config.rpmTolerance
    and math.abs(acceleration) < 2
    and math.abs(turbine.flow - control.flow) <= math.max(5, control.flow * 0.05)

  if not eligible then
    resetWindow(state)
    state.status = phase == "spinup" and "spinup" or "calibrating"
    return false
  end

  if state.anchorFlow and (differs(control.flow, state.anchorFlow, 5)
      or (phase == "generating" and differs(turbine.output, state.anchorOutput, 1))) then
    resetWindow(state)
  end
  state.anchorFlow = state.anchorFlow or control.flow
  state.anchorOutput = state.anchorOutput or turbine.output

  local sampleSeconds = math.min(elapsed, Calibration.STABLE_SECONDS - state.stable)
  state.stable = state.stable + sampleSeconds
  state.flowTotal = state.flowTotal + control.flow * sampleSeconds
  state.outputTotal = state.outputTotal + turbine.output * sampleSeconds
  state.status = "calibrating"
  if state.stable < Calibration.STABLE_SECONDS then
    return false
  end

  state.status = "complete"
  state.complete = true
  local entry = points[turbine.id]
  if not entry or entry.rpm ~= state.rpm then
    entry = {rpm = state.rpm}
    points[turbine.id] = entry
  end
  entry[phase] = {
    flow = state.flowTotal / state.stable,
    output = state.outputTotal / state.stable,
  }
  return true
end

return Calibration
