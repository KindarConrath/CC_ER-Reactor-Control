-- Initial settings. UI choices are saved in settings.dat and override this file.
return {
  interval = 1,                 -- seconds between control updates
  targetCharge = 0.70,
  standbyAbove = 0.90,
  generateBelow = 0.75,
  rodRate = 2,                  -- normal rod rate, percentage points per second
  passiveMaxRodWithdrawalRate = 8, -- faster passive ramp when storage is low
  passiveMaxRodInsertionRate = 8,  -- faster reduction when over target or filling quickly
  passiveBrakingSeconds = 90,   -- rising-charge look-ahead near target; 30 restores old response
  rpmTarget = 1796,             -- efficiency band; adjustable in UI
  rpmTolerance = 12,
  flowRate = 150,               -- maximum flow-limit change (mB/t) per second
  remotePeers = {},             -- companion computer IDs, e.g. {12, 13}
  remoteTimeout = 2,
  controllerDisplay = {mode="auto"}, -- discover a monitor, otherwise use this computer
  reactors = {},               -- empty: discover all; otherwise full IDs from Scan
  turbines = {},               -- empty: discover all
  storage = {},                -- selected full IDs; empty uses generator buffers
  -- One entry per physical battery/network, even if it has multiple ports.
  -- Key is the local peripheral name ON THE COMPUTER THAT CAN SEE IT.
  -- Configure remote mappings in the companion computer's config.lua.
  deviceNames = {},            -- optional display aliases by full ID; UI names override these
  storageMappings = {
    -- ["some_battery_0"] = {
    --   stored = "getEnergyStored", capacity = "getMaxEnergyStored",
    --   scale = 1, identity = "main-battery", label = "Main battery"
    -- },
  },
}
