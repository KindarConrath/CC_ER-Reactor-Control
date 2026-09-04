# Reactor Control 0.1.36

## Updating from 0.1.0 through 0.1.35

Drop `reactor-control-update-0.1.36.lua` into the computer and run `reactor-control-update-0.1.36` after exiting
the controller or companion. This development updater validates its payload in memory, removes
recognized legacy code backups, then overwrites only changed files in place. It creates no rollback
backup or update staging copy. `config.lua`, saved settings, Basalt and startup configuration are preserved.
For a custom installation directory, pass it as the updater's first argument.
Relaunch the controller or companion afterwards. Existing saved mode and startup settings are retained.

Development cleanup build for **Minecraft 1.21.1, Extreme Reactors, CC:Tweaked, and Basalt2**.
Release history is in [CHANGELOG.md](CHANGELOG.md). See [the release checklist](docs/RELEASE.md)
for completed checks and work remaining before a public release.

**0.1.22 update correction:** earlier updaters did not include every runtime module. In particular,
the 0.1.21 updater omitted the network module needed by its reconnect changes. This updater refreshes
all first-party runtime modules while preserving configuration and Basalt. Update the controller first.

The Basalt2 dependency is included and pinned. No downloads are needed in Minecraft.

## Quick start

1. Drop `reactor-control-install-0.1.36.lua` into an Advanced Computer's terminal window.
   CC:Tweaked's file-transfer support copies it into the computer when you accept the transfer.
   If drag-and-drop is unavailable, copy it into that computer's world save directory or use a disk.
2. Run `reactor-control-install-0.1.36` in the ComputerCraft shell. Choose **1) controller** or
   **2) peer**; for a peer, enter the main controller's computer ID. The installer creates startup
   automatically. Enter accepts the displayed default. Ctrl+T at these prompts cancels before installation.
   The remaining steps below apply to the main controller. On a peer, run
   `reactor-control/startup run` or reboot, then add its ID on the main controller under **Setup > Peers**.
3. Attach the devices and optionally run `reactor-control/diagnostics scan` to check discovery.
4. Run `reactor-control/main`. The first launch opens in **Manual** without changing any devices.
5. Inspect the devices, choose the storage to use, then click **Mode: MANUAL** to enable Auto.

If using the source ZIP instead, put its `reactor-control` directory in the computer's root.
The main program can be launched from any working directory.
The installer refuses an existing destination; use the updater for later versions so settings
are retained. A fresh custom destination can be supplied as the first argument. Relative paths
use the shell's current directory, and the generated launcher uses an absolute path.
To skip the role prompts, use one of:

```text
reactor-control-install-0.1.36 --controller
reactor-control-install-0.1.36 --companion 0
reactor-control-install-0.1.36 custom-directory --companion 0
```

Replace `0` with the main controller ID. Setup rejects this computer's own ID and conflicting
startup launchers before creating the installation. It does not launch the controller or change
device settings. A new main controller starts in Manual; after selecting Auto, future starts
restore that choice once the saved plant is ready. A peer's pairing is saved for future starts;
its ID must also be added to the main controller under **Setup > Peers**.
If startup creation fails after the program was copied, the installer reports that distinction.
Fix the reported error and run `reactor-control/startup setup` instead of reinstalling.

## Controller Setup screen

Select **Setup** on the controller's top row. **Back** returns to the dashboard; control and
polling continue while Setup is open. **Stop all** remains available on the Setup screen.

* **Peers:** click/touch the Peer ID field, type the companion's computer ID using the computer's
  keyboard, then select **Add peer**. Use **Remove** on the matching row to delete an old ID.
  IDs must be non-negative whole numbers and cannot equal this controller's ID. Duplicate additions
  leave the existing list unchanged. Each accepted change saves automatically and switches to Manual.
* **Display:** choose **Automatic monitor** or **Computer screen**. The preference saves and applies
  without a restart, while retaining the current control mode. Automatic mode falls back to the
  computer when no suitable monitor is available.
* **Tuning:** with Auto enabled, choose **Calibrate turbines** to run the explicit turbine-calibration
  routine. If saving its completed result fails, **Retry save** appears on this page.
* **Rescan:** request refreshed discovery.

The input field survives background polling and switching Setup tabs. Setup reports pending,
successful and failed changes; failed saves do not replace the live configuration. After a peer
change, return to the dashboard, review the resulting devices/storage selection, then enable Auto.
The peer itself must be installed with the **peer** role and paired to this controller ID; adding
it to this list does not remotely reconfigure its pairing.

## Diagnostic reports

Run the probe on the computer directly connected to the devices. Exit its running controller
or companion first, then save a report in that computer's root folder:

```text
reactor-control/diagnostics probe --output /probe.txt
```

Retrieve `probe.txt` from that computer's folder in the world save and attach it when reporting
a discovery problem. Lines are not limited to the terminal width, so every method name is kept.
The report includes the running version, computer ID, local peripheral names/types/methods and
Mekanism helper availability. Probe inspects metadata without issuing control commands.

For the main controller's local and remote device status:

```text
reactor-control/diagnostics scan --output /scan.txt
```

Scan exports the configured peer list, device status and any connection errors. Relative output
paths use the current shell directory; leading `/` selects the computer root. Missing parent
folders are created, and repeating a command with the same output path replaces that report.
Diagnostics preserve saved settings and device controls and do not launch the UI. Omit `--output`
to print the report instead. Run `reactor-control/diagnostics` without arguments for usage.
The former `main --scan`, `main --probe` and `main --output` options have moved to this command.

## Supported arrangements

* One or more **passively cooled** reactors generating FE directly.
* Exactly one **actively cooled** reactor feeding one or more Extreme Reactors turbines.
* One global Manual/Auto mode. Different per-device modes are reserved for a later version.
* Devices directly attached, exposed through wired modems, reached through companion computers,
  or a mixture of these transports.

The computer network does not describe steam plumbing. Connect only the intended plant, or set
the `reactors` and `turbines` lists in `config.lua` to the full device IDs printed by `diagnostics scan`.
Expose **one computer port per reactor/turbine**, and do not expose the same physical device both
locally and through a companion. This initial adapter cannot automatically identify such aliases.
Changes to the automatically selected reactor/turbine set pause Auto for review.

## Wired connections

Connect a wired modem to the computer and to each device's computer port. Join them with
networking cable and right-click each device modem to expose the peripheral.
One controller can read all devices exposed on that wired network.

## Wireless connections

Wireless modems exchange messages between computers; they do **not** expose peripherals directly.
Install the same package on a companion computer near the machinery. That computer needs:

* Access to its reactor, turbine, or batteries through adjacent connections or a wired modem network.
* A wireless or ender modem to reach the main controller. The main controller needs a compatible modem.

Example: main controller computer ID **5**, companion computer ID **12**.

On computer 12:

```text
reactor-control/agent 5
```

On computer 5, open the controller, choose **Setup > Peers**, enter `12` in **Peer ID**,
and select **Add peer**. Repeat for each peer. The Setup screen displays this controller's own
ID so it can be entered during companion installation.

The saved peer list survives restarts. The Scan output will use
IDs such as `peer:12/extremereactor-reactorComputerPort_0`. A companion can serve several devices.
To remove peer 0 and configure peers 4, 5 and 6, open **Setup > Peers**, select **Remove** beside
peer 0, then add 4, 5 and 6. Unreachable peers stay in this list until explicitly removed; they
need not reconnect before removal. The list is paginated when there are more than five peers.
Add and remove peers through **Setup > Peers**; controller peer command-line options have been removed.

Scan displays the saved list and only polls those peers. Peer changes persist across restarts.
On Storage, remove any selected device belonging to the removed peer and select the intended
new storage before enabling Auto. Device selections are retained for explicit review rather
than silently redirected to a different battery. Explicit reactor/turbine ID lists in `config.lua`
also need updating if they reference the removed peer.
The same companion protocol also works over wired rednet links. For a normal wired peripheral
network, the companion is unnecessary.

Both computers and the machines must stay loaded. Normal wireless modem range/dimension limits
still apply; use ender modems where appropriate. Pairing uses the controller computer ID and an
application protocol, with reply matching and one-use, five-second command leases. It is **not
cryptographic authentication**; this first version is intended for your trusted computer network.

On a connection timeout or missing modem, an Auto controller pauses adjustments and displays
**Mode: WAIT**, with a short status such as `Peer #4: no response; retrying`. Once all configured
peers return, two consecutive healthy polls must match the saved generators, storage selection
and peer list before Auto resumes. A further outage resets this count. Rejected commands,
device errors or a changed plant still require review and explicit Auto selection. Manual,
Stop, manual device controls and selection changes cancel pending recovery.
Devices retain their last settings, including if the controller/companion stops or unloads.
Commands already applied before an error are not rolled back; a lost acknowledgement can mean
a command took effect. Recovery reads current device state and sends new commands with fresh leases.
There is no autonomous control loop in a companion yet.
The last chosen mode survives a runtime fault, so a later controller restart can restore saved
Auto after its readiness checks. Explicit Manual, Stop all, a manual device command, or a storage
selection change saves Manual instead. Companions and controllers reopen modems on subsequent
polls, allowing modems to attach after the program starts.

## Optional companion displays

A companion automatically uses an attached colour monitor for its local reactor, turbine and storage
readings. Attach the monitor, then start the companion normally (replace `2` with the main ID):

```text
reactor-control/agent 2
```

Existing companion startup configuration does the same on reboot. No monitor name needs to be
configured. Directly attached monitors and monitors accessible through wired modems both work.
A suitable peer monitor needs at least **23 columns by 17 rows**, which allows a 3x3 monitor at
its normal text scale; enlarge it or reduce its text scale
if needed. If several suitable monitors are available, the first in alphabetical peripheral-name
order is used. A working display is kept until it becomes unavailable or too small.

Without a suitable monitor, the companion runs without a dashboard and checks again every two
seconds. Attaching a monitor later starts the dashboard automatically. Removing it leaves the
network service running; a replacement with a new peripheral ID is discovered automatically.
Previously saved 0.1.8 monitor names are ignored and migrated to automatic detection when loaded.

Optional overrides remain available:

```text
reactor-control/agent 2 --terminal
reactor-control/agent 2 --no-display
reactor-control/agent 2 --auto-display
```

These select the Advanced Computer terminal, disable the dashboard entirely, or return to automatic
monitor discovery. Explicit choices persist across restarts. The main controller's display setting
is separate. This feature requires updating the companions; the network protocol is unchanged.
The old `--monitor NAME` companion invocation is accepted for compatibility and enables automatic
discovery; the supplied name is not saved or used to restrict the selection.

The dashboard shows reactor rods, fuel/waste and output; turbine RPM, steam intake, coils and
output; and local storage charge/capacity. Tabs and previous/next buttons navigate local devices.
The selector shows the count above separate location and device-name rows, with three-row buttons
and centered `<` and `>` arrows. Compact screens use **All**, **Reactor**, **Turbine** and **Power**
for the available categories. At 3x3, Reactor/Turbine shorten to **React**/**Turb** only when all
three device categories are present; four-monitor-wide screens have room for both full words.
Displays of 45 columns or more retain Overview, Reactors, Turbines and Storage.
Tabs keep a one-cell gap between buttons and a margin at both screen edges. Compact buttons fit
their labels with padding where space permits; empty or single-category peers no longer stretch
the buttons across the screen.
Peers with just one device category open that detail view; mixed peers open Overview. The header
identifies the peer. The main computer ID and contact status appear only after more than ten
seconds without contact, then disappear when contact resumes. It does
not infer the main computer's operating mode or target from local readings.

Local readings continue even without a controller connection. The main computer retains control;
these screens only display data. Display polling does not consume the controller's command lease.
Ctrl+T stops the entire companion service, including its display.

## Recovering from a full computer disk

The 0.1.11 request for roughly 108 KB free included a second on-disk copy of changed update files.
The 0.1.12 updater validates replacements in memory and writes them in place, starting with files
that shrink. Its free-space estimate is net growth plus allocation/settings allowance, not the
full replacement payload. It reports exact bytes rather than rounding a small amount down to 0 KB.

If the disk is full and cannot accept the new download, remove the old standalone updater file
first, for example `reactor-control-update-0.1.11.lua`. The 0.1.12 updater is smaller than 0.1.11.
Keep the installed `reactor-control/` directory, its settings and startup files. Drop in the new
updater and run it normally.

During a normal update, versioned `backup-X.Y.Z` directories inside the installation are removed
only when they contain recognized former update targets (including legacy README files). Unknown
contents, settings, mounted drives, other backup names and old staging directories are left alone.
The package is decoded and validated before this cleanup. No new backup is made. The updater
download itself is kept so an interrupted write can be repaired by running it again; after success,
you may remove that standalone download.

For an accounting report without changing code or cleaning backups:

```text
reactor-control-update-0.1.36 --disk
```

Once enough space is available for a report file, export it for retrieval from the CC folder:

```text
reactor-control-update-0.1.36 --disk --output disk-usage.txt
```

The report includes the actual configured capacity, exact free/used bytes, top-level file and
folder totals, and the installation's children (including `vendor` and each backup directory).
Totals exclude separate mounts such as ROM/disks and are file-byte totals; allocation overhead
is reflected in the filesystem's used/free values. A normal update prints this report if space
for net growth is still insufficient.

An `out of space` error at line 1798 of **reactor-control-update-0.1.10.lua** occurred in its backup
copy loop, before it modified installed code. Its incomplete `backup-0.1.10` directory can be
removed manually or by the recognized-backup cleanup above. This finding applies to that exact
failure location, not failures during later file replacement.

## Device tabs, manual rods and names

The main controller hides device categories that are absent, so a passive system has no Turbines
tab. Selected disconnected storage remains accessible until removed from control. Companions show
Overview plus only the categories they can currently see; losing the current category returns to
Overview. A connected peripheral with a failed reading stays visible as unavailable.

Companion Overview includes only relevant sections. Storage-only peers show combined storage
charge and capacity, without reactor or turbine statistics. Reactor-only peers omit storage
statistics; steam appears only when a cooled reactor has readable telemetry. Multiple batteries
are combined by total energy divided by total capacity, with configured shared identities counted
once. No devices produces a simple empty state.

In global Manual mode, the Reactors page now has an editable **Rod target**:

* Choose **0%, 25%, 50%, 75% or 100%** for a quick jump.
* Adjust with **-5, -1, +1 or +5** as quickly as needed; edits do not wait for polling.
* Press **Apply** to send that absolute insertion target. For example, 90% to 0% takes **0%**, then **Apply**.
* **Actual** discards an unapplied draft and copies the latest reported insertion. It does not cancel a command already sent or queued.

The actual Rods reading remains separate from the draft/requested target. Drafts survive normal
refreshes and are kept separately for each reactor. Changing global mode or losing the reactor
clears its draft. Commands still travel through the existing controller queue and acknowledged
peer protocol; editing is immediate, while physical changes and confirmation wait for those
operations. Targets remain within 0..100%. Apply does not activate an inactive reactor.

Automatic names include the device type and its location, for example **Peer 4 / Back - Passive
reactor** versus **Peer 5 / Back - Passive reactor**. Storage peripheral types identify energy cubes,
capacitor banks and RFTools powercells when available. The raw address is retained beneath the
heading for troubleshooting and configuration; display names never replace transport IDs.

On the main controller, open any device and select **Rename**. Click/touch the text field, then
use that computer's keyboard to enter up to 32 characters and select **Save name**. **Automatic**
or a blank name restores the generated name. Names are saved by full device ID in `settings.dat`;
renaming preserves control mode, storage selection and the accepted Auto plant. The controller
continues polling while the name field stays open. These custom names belong to that controller;
peer screens retain their own automatic names. Peers remain read-only.

## Startup and server restarts

New installers enable startup as part of installation. On existing installations, update every
controller and companion, then run `reactor-control/startup setup` on each computer that needs
startup enabled. It offers the previously saved role and controller ID as defaults. Existing
launchers and saved modes are preserved by the updater, including deliberately disabled startup.

Explicit commands remain available. On the main computer, run:

```text
reactor-control/startup controller
reactor-control/main
```

Choose Auto once the intended devices and storage are selected. The mode is saved immediately;
pressing Save separately is not required. A newly upgraded installation defaults to Manual
until this first choice because older versions did not save the mode or expected plant.

On each companion, replace `2` with the main controller's computer ID:

```text
reactor-control/startup companion 2
reactor-control/agent 2
```

After a reboot, the saved role launches automatically. The controller waits for configured
peers and the saved plant to return, regardless of their startup order. While waiting it issues
no device commands, and does not silently accept a missing or additional reactor. Missing or
replacement devices can be reviewed by cancelling the wait with Mode, adjusting selections,
and enabling Auto explicitly. Companions keep accepting requests when their controller reboots.
Both computers and devices must be loaded for this to operate. The controller uses its own screen when no suitable monitor is ready, and discovers a monitor
when one becomes available. A missing monitor does not delay Auto restoration on an Advanced Computer.

Normal `main` launches also restore the saved mode. Use `reactor-control/main --manual` to
open in Manual and save that choice, for example when changing the installation. Stop all saves
Manual and stops the plant. Exit/Ctrl+T holds device settings and retains the last chosen mode;
therefore exiting from Auto does not disable its restoration on the next launch.

```text
reactor-control/startup status
reactor-control/startup disable
```

Startup setup records the role/owner in `startup.dat` and creates only its own launcher at
`/startup/reactor-control.lua`, using [CC:Tweaked's startup folder](https://tweaked.cc/guide/startup.html).
It preserves other startup files and refuses to replace a conflicting launcher. If another
startup program runs indefinitely before this one, arrange their startup order or concurrency.
Disable removes this launcher's entry while retaining settings. Enabling startup again updates
the role without creating duplicate launchers. A legacy `/startup` file must be moved to
`/startup.lua` before a directory can occupy `/startup`.

## Controls

* **Mode:** Manual holds current settings; Auto regulates all selected generators. The selected
  mode is saved for the next launch. **WAIT** means saved Auto is awaiting its plant; click to cancel.
* **Stop all:** Insert reactor rods to 100%, deactivate reactors, set turbine flow to zero,
  engage coils to let rotors slow while generating, and deactivate turbines.
* **Exit / Ctrl+T:** Close the program and leave machine settings in place.
* **Setup:** Manage peer IDs and display selection. Turbine calibration and Rescan are available here.
  A completed calibration saves automatically; discovery also runs each update.
* **Reactors:** Select a device, activate/deactivate it, or choose a rod target and Apply in Manual.
* **Turbines:** Select a device, change activation/coils/flow in Manual, or select the global
  automatic RPM band (898 or 1796). Per-turbine automatic targets can be added later.
* **Storage:** Select each storage device that should influence generation.

The layout needs a colour display of at least **45 x 19 character cells**. The main controller
uses an attached suitable monitor automatically, including directly attached and wired monitors.
When several are available, it chooses the first in alphabetical peripheral-name order, then
keeps that monitor while it remains suitable. With no suitable monitor it uses the computer's
screen; use an Advanced Computer for this fallback.

Attaching a monitor switches the dashboard to it. Removing it or reducing its usable size below
the minimum selects another suitable monitor or falls back to the computer. The app, current
mode and control state continue running through these changes. Enlarge a small monitor or reduce
its text scale to make it suitable. Monitor touches and terminal mouse clicks use the same controls.

Choose the display in **Setup > Display**. If you need to recover access on the computer screen:

```text
reactor-control/main --terminal
```

This saves terminal-only mode; restore automatic discovery through **Setup > Display**.
Old saved monitor names still migrate to automatic discovery, without retaining the name.
An explicitly saved terminal-only setting is preserved. These choices are separate from
companion display preferences and preserve saved Manual/Auto and device selections.

The controller's only launch options are `--manual` (cancel saved Auto), `--terminal` (screen recovery),
and internal `--boot` (managed startup). The former `--demo`, `--direct`, `--peer`, `--remove-peer`,
`--monitor` and `--auto-display` controller options are rejected without changing settings.
Companion service options belong to `agent.lua` and are unchanged.

## Automatic behaviour

**Direct power:** Incrementally adjust reactor rods from storage charge error and its smoothed
rate of change. This continually modulates output. Withdrawal accelerates smoothly as storage
falls further below target: the default maximum rises from the normal 2 percentage points/second
to 8 at empty storage. Rising charge reduces the urgency, and changes become small near target.
With a 70% target and steady charge, withdrawal is about 6.4 points/second at 10% charge,
3.1 at 40%, and 0.85 at 60%. Integer rod positions mean small changes accumulate between updates.
Add `passiveMaxRodWithdrawalRate = 8` to an older `config.lua` to customize the maximum;
it must be at least `rodRate`. Omission uses 8, or `rodRate` when that is higher.
Insertion also has a default maximum of 8 points/second, configurable with
`passiveMaxRodInsertionRate` (at least `rodRate`). At 80% steady charge with a 70% target,
the default insertion request is 2.8 points/second, compared with 0.8 in 0.1.1. A positive
charging trend raises the insertion request, including before the target is reached.
Near target, `passiveBrakingSeconds` extends that prediction from 30 to 90 seconds by default.
The extension blends in smoothly from one percentage point below target and reaches full
strength at target. The faster trend filter responds to a growing surplus; the slower filter
helps release braking gradually. Set `passiveBrakingSeconds = 30` to restore the 0.1.2 response,
or choose a finite value of at least 30. A longer look-ahead can make the final approach to
target slower. The prediction is a tuning horizon, not a delay before acting or a shutdown timer.
These are controller rates, not guarantees of final charge: thermal lag still needs in-game testing.
Steam-reactor regulation retains the existing rate policy.
Above the high storage threshold, insert rods
and deactivate reactors; resume below the lower threshold. Each reactor starts regulation from
its existing rod setting. This first version applies the same charge-error policy to all reactors;
it does not yet optimize load sharing for fuel efficiency.

**Turbine power:** Adjust each turbine's intake limit to hold the selected RPM. During startup,
keep coils disengaged until near target speed. Once generating, use coils and steam together to
hold speed. Above the storage high threshold, disengage coils and reduce steam to maintain
spinning standby. Re-engage when charge falls below the lower threshold. The reactor adjusts its
rods to meet combined requested steam flow, with steam-buffer feedback.

Turbine calibration never starts automatically. With Auto enabled, open **Setup > Tuning** and choose
**Calibrate turbines**. The routine measures one turbine at a time with its coils engaged while the
others remain in spinning standby. After all turbines record ten stable seconds, it runs them together
for a combined reactor-capacity check, saves the complete result, and returns to ordinary storage
control. Storage charge does not prevent this explicit routine from generating. Manual, Stop, a
disconnect, or a restart cancels an unfinished run and preserves the previous saved calibration.

**Insufficient steam:** In generating mode, the controller compares the reactor's reported steam
production with the turbines' combined requested flow. Once every connected turbine has a current
generating calibration point, a reactor that is fully open but remains short by more than 5% of
demand (and at least 100 mB/t) for ten seconds shows `REACTOR LIMIT: output/demand mB/t steam`.
An empty reactor is also treated as capacity-limited without changing the existing safety rule
that leaves its rods where they are. Auto continues best-effort regulation; this is a warning,
not a shutdown or proof of the reactor's theoretical maximum.

**Stalled reactor:** When output is required and a reactor has been asked to run with sufficiently
withdrawn rods but reports no power or steam for 30 seconds, the controller shows
`REACTOR STALLED`. Passive systems identify the affected reactor; turbine systems show measured
steam versus requested flow. An empty reactor also qualifies when the plant needs its output, without
changing the existing rule that fuel starvation does not force its rods open. This warning detects
the missing result rather than trying to diagnose fuel, waste, coolant or transfer state. It clears
after three seconds of recovered production or immediately when demand ends.

An underpowered plant may be unable to finish turbine calibration. Supply must recover for three
seconds to clear a warning; standby, Manual, or a topology reset clears it
immediately. The measured warning appears along the bottom of every controller page, while Setup
uses a shorter insufficient-capacity message.

If an individual generating turbine remains below the target band with falling RPM while both its
requested and actual flow stay at maximum for ten seconds, the controller shows
`TURBINE LIMIT: Turbine N/M; RPM falling`. This indicates that available blade torque cannot overcome
the engaged inductor load at maximum flow; add blades or reduce coil drag. The warning clears after
three seconds of recovery or immediately outside generation.

**Calibration:** This is a dedicated Setup action rather than continuous change detection. The
controller shows which turbine is being measured, progress toward ten stable seconds, and the combined
capacity check. Normal generation uses the saved points but never verifies, replaces, or invalidates
them automatically. After changing turbine blades, coils, or the RPM target, run **Calibrate turbines**
again. Adding a turbine or selecting an RPM without a matching point displays **Calibration required**.

Each qualifying sample requires an active turbine, confirmed coils engaged for generation or
disengaged for standby, RPM within the configured tolerance (default +/-12), acceleration below
2 RPM/second, and actual steam flow within 5% of the requested flow (minimum allowance 5 mB/t).
Instability, phase changes, RPM-band changes and interrupted contact reset the stability window.
Flow and generating power must also remain within 10% of the window's first sample, with small
absolute allowances to avoid treating tiny changes near zero as significant.

After ten qualifying seconds, average generating flow and output are recorded in a temporary session.
The saved calibration is replaced only after every turbine and the combined capacity check finish.
The controller does not identify coil or blade changes; recalibration is deliberately a user action.
RPM feedback continues to adjust flow during normal operation without modifying the saved points.

If calibration autosaving fails, the UI shows **Calibration NOT saved; retrying**. The learned
point remains usable in memory and Auto continues. Saves retry every 30 seconds, or immediately
through **Setup > Tuning > Retry save**. A later successful settings save also persists pending points.
Do not assume a failed save will survive a restart. Other control/settings failures retain their
existing pause behavior; the non-fatal retry applies specifically to calibration saving.

This is **flow learning at a selected band**, not a sweep that proves maximum FE/t or maximum
FE per mB. Peak-search optimization remains a next iteration.

## Storage support

The current version provides three adapter paths:

| Adapter | Requirement |
| --- | --- |
| Generic FE | CC:Tweaked `energy_storage` with `getEnergy()` and `getEnergyCapacity()` |
| Mekanism Energy Cube | Native `getEnergy()` / `getMaxEnergy()` converted from Joules by `mekanismEnergyHelper.joulesToFE()` |
| Explicit mapped adapter | Configured stored/capacity methods returning numbers or numeric strings, plus an explicit FE conversion factor |

Generic support can cover several mods through the same CC:Tweaked interface. A block being
visible does not guarantee that it exposes its **entire** multiblock or wireless storage network.
Compare the controller's capacity against the in-game block GUI before using it for control.
Storage with nested return tables needs a dedicated adapter in a future iteration.

For a custom peripheral, configure it **on the computer that can see it**, in `config.lua`:

```lua
storageMappings = {
  ["your_peripheral_name"] = {
    stored = "actualStoredEnergyMethod",
    capacity = "actualCapacityMethod",
    scale = 1, -- source energy units multiplied by this factor = FE
    identity = "main-battery",
    label = "Main battery",
  },
},
```

The method names above are placeholders, not claims about any particular mod's API.
The native cube adapter recognizes basic, advanced, elite, ultimate and creative Energy Cube types.
It uses Mekanism's installed conversion helper so changes to its FE conversion setting are respected.
If that helper is unavailable, it reports an error instead of silently treating Joules as FE.
An explicit `storageMappings` entry takes precedence over native discovery.
Use `reactor-control/diagnostics probe` to inspect types and method names without changing any devices.
Native adapters for Mekanism Induction Matrices, Draconic Evolution, Ender IO, and Extreme Reactors Energizers should be verified against
the installed 1.21.1 mod versions before adding named compatibility claims. Do not copy legacy
energy-unit conversions without checking the current API.

Select multiple different batteries to combine them. Charge is total stored FE divided by total
capacity, not an average of battery percentages. Select only one port per physical store, or
assign identical `identity` values to aliases to count them once. Empty selection uses reactor
buffers for direct power and turbine buffers for turbine power. Missing selected storage pauses
Auto; it is never silently replaced by an internal buffer. Unselected storage is display-only.

## Configuration and project layout

Edit `config.lua` for update interval, thresholds, control rates, device selection, peer IDs and
storage mappings. UI/CLI choices are written to `settings.dat` and override the corresponding
defaults on the next launch; the previous saved file is kept as `settings.dat.bak`. To reset UI
choices, move `settings.dat` aside. The last chosen mode, accepted Auto plant, and standby phase
are saved there as well. Without saved settings, the first launch is Manual.

| File | Responsibility |
| --- | --- |
| `main.lua` | Controller entry point and launch options |
| `diagnostics.lua` | Standalone scan, probe and report export |
| `agent.lua` | Companion service and saved display options |
| `lib/companion.lua` | Companion transport and independent display retry worker |
| `lib/companion_ui.lua` | Read-only Basalt2 local telemetry dashboard |
| `lib/display.lua` | Shared monitor discovery and controller screen selection |
| `lib/setup_ui.lua` | Peer and display settings panel with persistent input widgets |
| `startup.lua`, `lib/startup.lua` | Saved computer roles and managed startup launcher |
| `lib/devices.lua` | Extreme Reactors peripheral calls and storage adapters |
| `lib/network.lua`, `lib/backend.lua` | Acknowledged remote messages and unified device IDs |
| `lib/control.lua` | Rod regulation, turbine regulation and standby |
| `lib/calibration.lua` | Stable-point learning, verification and performance-change detection |
| `lib/app.lua` | Global mode, serialized commands and polling |
| `lib/ui.lua` | Basalt2 interface and manual target/name editing |
| `lib/presentation.lua` | Device names, contextual tabs and local summaries |
| `lib/demo.lua` | Approximate local demo dynamics for development/tests |
| `tools/demo.lua` | Source-only demo launcher, separate from normal controller startup |
| `tests/` | Controller, protocol, adapter and actual Basalt rendering tests |
| `tools/package.py`, `tools/package_codec.lua` | Build and decode compact, checksummed offline packages |
| `tools/install_runtime.lua`, `tools/update_runtime.lua` | Install preflight; development in-place updates, legacy-backup cleanup and disk reports |

The controller modules are plain Lua tables/functions. UI callbacks enqueue intentions; one
control coroutine reads telemetry and performs writes. Per-reactor manual overrides can later be
added at the coordinator boundary without coupling them to the UI.

## Development demo

The source ZIP includes `reactor-control/tools/demo.lua`; normal installs do not include this launcher.
On an Advanced Computer with the source tree, use `reactor-control/tools/demo passive` for two passive
reactors, or `reactor-control/tools/demo turbine` for one cooled reactor and two turbines (the default).
The demo uses the current terminal, simulated devices and temporary settings, without loading
`settings.dat` or controlling real peripherals. Its approximate dynamics are not a Minecraft physics model.

## Validation and limits

Host validation uses Lua 5.2 via Lupa, mocked CC peripherals, and the actual bundled Basalt2.
It covers manual preservation, Auto regulation, storage aggregation, disconnect handling,
standby/hysteresis, startup/coil engagement, flow learning, stop commands, bounded simulation,
adapter calls, paired network requests, lease expiry/replay, UI rendering, mouse and monitor input.
Packaging tests include actual runtime and updater bytes inside a 1,000,000-byte simulated disk,
interactive role selection, invalid pairing and startup conflicts, custom paths, the installed
launcher reaching each role entry, launcher-write recovery, zero-free-space legacy-backup cleanup,
updates with only 5 KB free, repeat updates without disk
growth, payload validation before cleanup, unknown-data preservation and report export.
Interrupted in-place writes are repaired by rerunning the updater; no rollback is retained.
UI cleanup coverage includes rapid draft edits before polling, per-reactor targets, contextual tabs,
relevant peer summaries, input surviving refreshes, saved names, the controller's minimum display
width, and the peer's compact 23 x 17 layout.
Restart coverage uses actual serialized settings and fresh app instances: staggered peers,
changed plants, missing storage, cancellation, Manual/Stop persistence, runtime faults, standby
restoration, save failures, startup ownership, late modems, display-setting migration, and boot
fallback with a missing monitor. Display tests exercise the ten-second peer contact threshold,
recovery, direct/wired monitor discovery, controller attachment/removal/replacement/resizing,
input after display changes, and preservation of running Auto state. Setup tests cover actual
keyboard/touch entry, input retention, pagination, duplicate/invalid IDs, save failure, unreachable
peer removal, persistent settings, same-batch Auto refusal, and Stop with a pending change.
The passive regression model includes two reactors, integer rod commands, a 102.4M FE store,
and a load increase followed by removal at the first recovery to displayed 70.0% charge.
Across illustrative 3/8/20-second output lags, 0.1.3 reduces the modeled peak by about two
percentage points versus 0.1.2 and reaches full rod insertion sooner. Separate sustained-load
runs settle within half a percentage point of target. These figures validate the direction of
the tuning change; they do not predict a particular in-game reactor's overshoot.

Run from a host with Python:

```text
python -m pip install lupa
python tests/run.py
python tools/package.py
python tests/packaging.py
```

These are not tests inside Minecraft. Real reactor thermal lag, turbine inertia, modpack tuning,
server tick rate and wireless latency require in-game tuning. The demo is not a physics simulator.
Current release work and the later optional graphical UI are tracked in [docs/RELEASE.md](docs/RELEASE.md).
Calibration tests cover coil confirmation, uninterrupted timing, phase/RPM separation, simulated
coil-resistance changes, automatic saves, restart verification, failed-save retries and controller
UI status at 45/51 columns. These simulations do not establish Extreme Reactors' actual physics.
Turbine peak-speed regulation remains the accepted policy; no peak-search or autonomous peer loop
is being added as part of cleanup.

## Source references

* [Extreme Reactors 1.21 branch / Minecraft version](https://github.com/ZeroNoRyouki/ExtremeReactors2/blob/1.21/gradle.properties)
* [Reactor peripheral implementation](https://github.com/ZeroNoRyouki/ExtremeReactors2/blob/1.21/src/main/java/it/zerono/mods/extremereactors/gamecontent/multiblock/reactor/computer/ReactorComputerPeripheral.java)
* [Turbine peripheral implementation](https://github.com/ZeroNoRyouki/ExtremeReactors2/blob/1.21/src/main/java/it/zerono/mods/extremereactors/gamecontent/multiblock/turbine/computer/TurbineComputerPeripheral.java)
* [Turbine simulation / induction drag and efficiency curve](https://github.com/ZeroNoRyouki/ExtremeReactors2/blob/1.21/src/main/java/it/zerono/mods/extremereactors/gamecontent/multiblock/turbine/TurbineLogic.java)
* [CC:Tweaked peripherals](https://tweaked.cc/module/peripheral.html), [rednet](https://tweaked.cc/module/rednet.html), [generic FE storage](https://tweaked.cc/generic_peripheral/energy_storage.html)
* [Bundled Basalt2 commit](https://github.com/Pyroxenium/Basalt2/tree/ba6c6911d2a317b452629faf77e55c7929857c73)
* [Mekanism 1.21.1 native energy methods](https://github.com/mekanism/Mekanism/blob/1.21.x/src/main/java/mekanism/common/tile/base/TileEntityMekanism.java)
* [Mekanism energy conversion helper](https://github.com/mekanism/Mekanism/blob/1.21.x/src/main/java/mekanism/common/integration/computer/ComputerEnergyHelper.java)

Basalt2 is redistributed under its MIT license; see `vendor/BASALT-LICENSE.txt`.
