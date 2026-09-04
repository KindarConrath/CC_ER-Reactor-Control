# Reactor Control

Reactor Control is a Basalt2 dashboard and automatic controller for Extreme Reactors on
Minecraft 1.21.1. It was built and acceptance-tested in ATM10 with CC:Tweaked.

It supports:

- One or more passively cooled reactors generating FE directly.
- One actively cooled reactor feeding one or more turbines.
- Manual control or whole-plant automatic control.
- Direct peripherals, wired modem networks, and wireless companion computers.
- Automatic monitor discovery and compact read-only displays on companions.
- Multiple selected energy stores, combined by stored energy and capacity.
- Explicit per-turbine calibration and a combined reactor steam-capacity check.

Basalt2 is bundled in the installer, so the Minecraft computer does not need internet access
after the installer has been transferred.

> Reactor Control sends commands to real multiblocks. First launch is always Manual. Confirm the
> detected devices and selected storage before enabling Auto, and keep a way to shut the plant down.

## Requirements

- Minecraft 1.21.1
- CC:Tweaked
- Extreme Reactors
- An Advanced Computer for the controller
- Extreme Reactors computer ports on every controlled reactor and turbine
- A colour monitor at least 45 x 19 cells for an external controller display (optional)

The controller falls back to the Advanced Computer screen if no suitable monitor is attached.
A companion display needs at least 23 x 17 cells, which fits a 3x3 monitor at normal text scale.

## Installation

Download `reactor-control-install-0.1.42.lua` from the GitHub release and transfer it to an
Advanced Computer. CC:Tweaked supports dragging a file onto an open computer terminal; a disk
drive also works.

Once the repository and `v0.1.42` prerelease are public, a server computer with HTTP enabled can
install directly from the release asset:

```text
wget run https://github.com/KindarConrath/CC_ER-Reactor-Control/releases/download/v0.1.42/reactor-control-install-0.1.42.lua
```

The URL will not work while the repository or release remains private.

Run the installer without arguments:

```text
reactor-control-install-0.1.42
```

Choose the startup role when prompted:

```text
Role:
1) controller
2) peer
Default (1):
```

The installer creates `/reactor-control`, installs the bundled Basalt2 copy, and adds its own
startup launcher. It does not overwrite an existing installation. Run the program immediately
with:

```text
reactor-control/startup run
```

or reboot the computer to test startup. You can then delete the standalone installer from the
Minecraft computer to reclaim disk space.

Non-interactive installation is also available:

```text
reactor-control-install-0.1.42 --controller
reactor-control-install-0.1.42 --companion 0
reactor-control-install-0.1.42 custom-directory --companion 0
```

Replace `0` with the main controller's computer ID. A custom directory must not already exist.

This first public prerelease intentionally has no updater package. Test installations should be
replaced with a fresh install. Preserve `config.lua` and `settings.dat` separately only if you
intend to carry their settings forward. Future releases can publish the maintained updater when
there is a public version to update.

## Connecting a plant

### Adjacent and wired peripherals

A reactor, turbine, storage block, or monitor can be directly adjacent to its computer. For a
wired network, connect wired modems with networking cable and right-click the modem attached to
each machine to expose its peripheral. One controller can use all supported devices visible on
that network.

### Wireless peers

Wireless modems carry messages between computers; they do not expose remote peripherals by
themselves. Install a peer computer beside a device or its wired network and pair it with the
main controller's computer ID. Then, on the controller:

1. Open **Setup > Peers**.
2. Enter the peer computer ID.
3. Select **Add peer**.

A peer may expose one device or several devices. Its optional monitor shows only locally visible
reactor, turbine, and storage data. The main controller remains responsible for all commands.

The saved peer list survives restarts. If a peer is unavailable, Auto enters **WAIT** and does not
issue new commands. Once the saved plant returns unchanged, two healthy polls are required before
automatic control resumes. A removed peer remains configured until it is removed in **Setup > Peers**.

Both computers and their machinery must remain loaded. Normal wireless range and dimension limits
apply; use ender modems when the installation requires them.

## First-time setup

1. Start the controller and leave it in Manual.
2. Open **Setup** and add any wireless peers.
3. Use **Rescan** if necessary.
4. Review the Reactors, Turbines, and Storage pages.
5. Select every independent storage device that should control generation.
6. Enable Auto only after the displayed plant is correct.
7. For a turbine plant, run **Setup > Tuning > Calibrate turbines**.

The selected mode, devices, display preference, names, and calibration are saved. After a normal
server restart, saved Auto waits for the same plant to return before resuming. Saved Manual remains
Manual.

## Operating modes

- **Manual** leaves automatic regulation disabled and exposes device controls.
- **Auto** controls all selected generators as one plant.
- **WAIT** means saved Auto is waiting for the previously accepted plant or a peer connection.
- **Stop all** inserts reactor rods fully, deactivates reactors, stops turbine steam flow, engages
  turbine coils, and deactivates turbines.
- **Exit / Ctrl+T** closes the program while leaving the current device settings in place.

Manual reactor rod targets can be changed with presets or 1%/5% steps, then sent with **Apply**.
Editing is immediate; the physical command and its confirmation still follow the normal polling
and peer protocol.

## Automatic passive-reactor control

The default charge target is 70%. The controller adjusts control rods continuously using the
storage error and recent charge trend. It withdraws rods more aggressively when storage is far
below target and inserts them faster when storage is filling quickly, reducing overshoot after a
load disappears. Above the default 90% standby threshold it closes and deactivates the reactors;
generation resumes below 75%.

All passive reactors currently share the same policy. Per-reactor baseline/surge modes are a
possible later feature, but are not part of this release.

## Turbine control and calibration

In Auto, each turbine regulates steam intake around the selected efficient rotor-speed band
(898 or 1796 RPM). Coils remain disengaged during spin-up. In generating mode, coils engage and
steam flow is adjusted to hold speed. When storage is full enough for standby, coils disengage so
the rotor can remain spinning with less steam.

Calibration starts only from **Setup > Tuning > Calibrate turbines**. The controller:

1. Measures each turbine separately with its coils engaged.
2. Requires ten continuous seconds of stable RPM, flow, and output for that turbine.
3. Runs all calibrated turbines together.
4. Verifies that the reactor can sustain their combined steam demand.
5. Saves the complete result automatically.

Do not manually change the plant during calibration. An interrupted run keeps the previous saved
calibration. After changing turbine blades, coils, or the RPM band, explicitly calibrate again.
The controller deliberately does not try to infer hardware changes.

Warnings distinguish a reactor that cannot sustain combined steam demand, a turbine that is losing
RPM at maximum steam with coils engaged, and a reactor that has produced no requested power or steam
for a sustained period. Automatic control continues best-effort unless the plant or connection is
unsafe to accept.

## Energy storage support

The following adapters were exercised in the ATM10 test world:

| Storage | Peripheral/API path |
| --- | --- |
| Mekanism Energy Cube | Native Mekanism energy methods with the installed Joule-to-FE helper |
| Mekanism Induction Matrix | `inductionPort`; formed-multiblock check and native conversion |
| Ender IO Capacitor Bank | CC:Tweaked generic `energy_storage` |
| RFTools Powercell | CC:Tweaked generic `energy_storage` |
| Integrated Dynamics Energy Battery | CC:Tweaked generic `energy_storage` |
| Extreme Reactors Energizer | `BigReactors-Energizer` native energy methods |
| Draconic Evolution Energy Core | `draconic_rf_storage` native energy methods |

Other peripherals exposing `energy_storage`, `getEnergy()`, and `getEnergyCapacity()` may work as
generic FE storage. Flux Networks blocks in the tested ATM10 version could not be exposed to a
CC:Tweaked modem and are therefore not supported.

When multiple storage devices are selected, charge is calculated as total stored FE divided by
total capacity. Select one port per physical store; exposing the same store more than once can
double-count it unless a shared identity is configured.

Custom storage methods can be mapped in `config.lua` on the computer that sees the peripheral:

```lua
storageMappings = {
  ["your_peripheral_name"] = {
    stored = "getEnergyStored",
    capacity = "getMaxEnergyStored",
    scale = 1,
    identity = "main-battery",
    label = "Main battery",
  },
},
```

`scale` converts the returned unit to FE. Do not guess conversion factors; compare the controller's
capacity with the block GUI before allowing that storage to control a plant.

## Displays and device names

The controller automatically selects a suitable attached monitor and falls back to its own screen.
Choose automatic monitor or computer screen under **Setup > Display**. If a saved monitor choice
makes the UI inaccessible, run:

```text
reactor-control/main --terminal
```

Peers automatically discover suitable monitors and recover if a monitor is removed and later
replaced. Their UI remains usable down to 23 x 17 cells and shows only locally available device
categories. Long names are shortened to fit compact displays.

On the controller, open a device and choose **Rename** to save a display alias. Automatic names
include transport and location information while raw device IDs remain visible for diagnostics.

## Diagnostics

Exit the running controller or peer before running diagnostics.

```text
reactor-control/diagnostics scan
reactor-control/diagnostics probe
reactor-control/diagnostics scan --output scan.txt
reactor-control/diagnostics probe --output probe.txt
```

`scan` reports supported local and peer devices. `probe` lists locally visible peripheral types and
methods without sending control commands. Saving to a file avoids terminal-width truncation and lets
server owners retrieve the report from the ComputerCraft computer folder.

## Configuration and recovery

`config.lua` contains defaults for polling, storage thresholds, rod/flow rates, RPM, explicit device
lists, peers, and custom storage mappings. UI choices are stored in `settings.dat` and take precedence.
The previous saved settings file is retained as `settings.dat.bak`.

Useful recovery commands:

```text
reactor-control/main --manual
reactor-control/main --terminal
reactor-control/startup status
reactor-control/startup setup
reactor-control/startup disable
```

`--manual` cancels saved Auto before launch. Startup owns only `/startup/reactor-control.lua` and
refuses to replace a conflicting launcher.

## Development

The source archive contains the Lua modules, tests, documentation, packaging tools, and an isolated
demo launcher. It does not include saved settings or credentials.

Run the host checks from the project directory:

```text
python -m pip install lupa
python tests/run.py
python tools/package.py
python tools/package.py --with-updater
python tests/packaging.py
```

`python tools/package.py` creates the public installer and source archive. `--with-updater` also
builds the maintained development updater so its compatibility path can be tested; it is not part
of the first public release.

The tests use Lua 5.2 through Lupa, mocked CC peripherals, and the bundled Basalt2. They do not
simulate Minecraft reactor physics, server tick rate, or wireless loading behavior. See
[`docs/ACCEPTANCE.md`](docs/ACCEPTANCE.md) for the in-game test matrix and
[`docs/RELEASE.md`](docs/RELEASE.md) for the maintainer checklist.

## License and third-party software

Reactor Control is MIT licensed; see `LICENSE`. Basalt2 is bundled unchanged under its own MIT license;
see `vendor/BASALT-LICENSE.txt` and `THIRD_PARTY_NOTICES.txt`. Earlier reactor-control projects were
used as design references only; their code and assets are not included.
