# Changelog

## 0.1.42 — first public prerelease preparation

- Replace the development diary README with installation, setup, supported-storage, operation,
  diagnostics, recovery, and contributor guidance for ATM10 on Minecraft 1.21.1.
- Make the normal release build produce an installer and source archive without an updater asset;
  retain explicit updater generation for compatibility tests and later public releases.
- Record completed development-world acceptance results and verify the pinned Basalt2 revision,
  license, and bundled-file hashes.
- Add repository ignore rules for generated packages, local settings, diagnostics, and Python caches.
- Expand abbreviated presentation, companion, display, demo, packaging, adapter, and test-fixture
  names; format compressed multi-statement code so each operation is readable without changing behavior.
- Keep the demo implementation in the source archive while omitting it from installed computers.
- Keep reactor/turbine regulation, saved settings, networking, and UI behavior unchanged.

## 0.1.41 — Draconic Evolution Energy Core support

- Recognize the ATM10 `draconic_rf_storage` peripheral as native FE energy storage.
- Read its Energy Core totals through `getEnergyStored` and `getMaxEnergyStored`, and identify it
  clearly in storage telemetry.

## 0.1.40 — Integrated Dynamics storage label

- Identify the in-game-tested `integrateddynamics:energy_battery` by name in storage telemetry
  instead of displaying `generic FE`.
- Continue using its standard CC:Tweaked `energy_storage` methods; control behavior is unchanged.

## 0.1.39 — Extreme Reactors Energizer support

- Recognize the ATM10 `BigReactors-Energizer` computer port and its modern alternate type as
  native FE energy storage.
- Read stored energy and capacity through `getEnergyStored` and `getEnergyCapacity`.
- Report an unassembled Energizer as unavailable instead of accepting invalid readings.

## 0.1.38 — Mekanism Induction Matrix support

- Recognize Mekanism `inductionPort` peripherals as energy storage.
- Read formed Induction Matrix energy and capacity through `getEnergy` and `getMaxEnergy`, converting
  Mekanism Joules to FE with the same runtime conversion helper used by Energy Cubes.
- Report an unformed Matrix as unavailable instead of accepting misleading zero-capacity readings.

## 0.1.37 — readability and maintenance

- Separate saved-setting migration, validation, restart-state handling and display migration into
  named helpers while preserving the existing file format and compatibility defaults.
- Split peripheral adaptation into focused storage, generator, reactor and turbine readers; give
  device types, measurements and command values descriptive names without changing supported APIs.
- Expand controller/peer startup and installer/updater flows into named parsing, validation, disk
  reporting and update helpers so failures can be followed without decoding compressed statements.
- Preserve automatic control formulas, command ordering, UI behavior and all existing settings.

## 0.1.36 — quieter turbine dashboard

- Remove persistent **Automatic control enabled** and completed-calibration messages from normal
  operation while retaining calibration progress, required state, failures and safety warnings.
- Omit the redundant **Selected storage** source line from the turbine overview; retain it on the
  passive-reactor overview and retain the actual stored amount and capacity everywhere.
- Keep completed calibration and combined-capacity results available under **Setup > Tuning**.

## 0.1.35 — stalled reactor warning

- Warn when a reactor has sustained demand but produces no power or steam for 30 seconds, regardless
  of whether the underlying cause is fuel, waste, coolant, transfer blockage or another condition.
- Identify the affected passive reactor; for a cooled reactor, show measured output versus requested
  steam. Clear the warning after three seconds of recovered production or when demand ends.
- Avoid warnings during standby, ordinary startup and intentionally near-closed rod operation.
- Reduce packaging storage simulations while retaining the real 1 MB installed-footprint guard.

## 0.1.34 — explicit turbine calibration

- Add **Setup > Tuning > Calibrate turbines** as the only way to start turbine calibration.
- Remove automatic commissioning, continuous point verification, performance-change detection and
  automatic capacity invalidation from normal control.
- Measure turbines sequentially into a temporary session, run the combined reactor-capacity check,
  and replace saved calibration only after the complete routine finishes.
- Preserve the previous calibration if Manual, Stop, a disconnect, restart or final command failure
  interrupts the routine; completed results still save automatically with bounded retry.
- Show missing or mismatched tuning as **Calibration required** without starting it automatically.

## 0.1.33 — persistent calibration status

- Count saved generating operating points in the overview instead of transient ten-second
  verification windows, so normal generation/standby transitions no longer appear to erase tuning.
- Distinguish passive monitoring from a confirmed performance change and remove the misleading
  instruction to hold the external load steady while an existing point is being checked.

## 0.1.32 — capacity-check persistence fix

- Restart the combined stability window if a turbine refines its learned generating flow during
  verification, so the result always covers the final combined demand.
- Save the final turbine-demand signature instead of the signature captured when verification began;
  this prevents a successful capacity check from repeating after reboot.

## 0.1.31 — turbine commissioning and capacity verification

- Commission turbines with missing generating points sequentially in Auto, temporarily overriding
  storage standby so initial calibration no longer depends on maintaining an external load.
- After all turbines learn generating points, run them together for ten stable seconds and report
  whether the reactor sustained their combined calibrated steam requirement.
- Warn per turbine after ten seconds at maximum requested and actual steam flow while RPM continues
  falling; clear after recovery or leaving generation.
- Restore the previously tested Basalt controller scheduling path; retain immediate peer/display
  Setup saves without treating the non-reproduced first-session observation as a confirmed defect.
- Show clean peer monitor-disconnection status without Lua filenames or line numbers.
- Use compact names and ellipses between navigation buttons on narrow peer displays.

## 0.1.30 — reliable first-session Setup

- Apply peer and display Setup changes immediately instead of waiting for the next control tick.
- Run controller polling independently of Basalt's internal scheduled-task list, fixing a fresh-install
  session that could accept button presses while leaving queued actions on `Saving...` until reboot.
- Preserve Stop priority and discard stale queued device or mode requests when the peer list changes.

## 0.1.29 — insufficient reactor steam warning

- Warn without stopping Auto when a fully opened reactor remains more than 5% or 100 mB/t below combined turbine demand for ten seconds.
- Begin this check immediately when all connected turbines have current generating calibration points.
- For a new underpowered plant that cannot complete calibration, apply a 30-second generating grace before the same ten-second check.
- Treat an empty reactor as capacity-limited without withdrawing its rods; preserve the existing no-fuel safety behavior.
- Clear the warning after three seconds of recovered supply, immediately in standby, Manual, or a changed topology.
- Show measured reactor steam/demand on every controller page and a concise warning in Setup.
- Add control and actual Basalt UI coverage for thresholds, delays, recovery, standby and empty fuel.

## 0.1.28 — visible, automatically saved turbine calibration

- Show per-turbine calibration/checking/recalibration progress and saved status on the controller, with an Overview summary.
- Require confirmed active/coil state and ten continuous qualifying seconds; keep generation/standby points separate.
- Save new or meaningfully changed stable operating points automatically, without rewriting unchanged tuning every update.
- Detect sustained flow or generating-power changes above 10%; show recalibration after three seconds and relearn after ten total.
- Keep RPM feedback and rod regulation formulas unchanged; coil materials are not explicitly identified.
- Keep regulating if calibration autosave fails, display the unsaved warning, and retry every 30 seconds or through Save tuning.
- Retain old calibration data and verify it on reuse; include the new calibration module in installer and updater.
- Add lifecycle, persistence, simulated coil-upgrade and actual Basalt UI regression tests.

## 0.1.27 — compact peer tab spacing

- Keep a one-cell gap between peer tabs and a margin at both screen edges.
- Size compact tabs to their labels with up to two padding cells, rather than stretching across the screen.
- Preserve full Reactor/Turbine labels on 3x3 peers with up to two device categories and four-wide peers with all categories.
- Keep existing wide-screen tab sizes and all control behavior unchanged.
- Test rendered gaps, margins, bounded widths and non-clickable gaps with mouse/touch, including empty and single-category peers.

## 0.1.26 — readable compact peer tabs

- Use Reactor and Turbine on compact peers whenever their tab widths allow it.
- At 3x3, shorten to React/Turb only when reactor, turbine and power categories are all present.
- Four-monitor-wide peers show Reactor/Turbine even with all categories connected.
- Preserve wide-screen labels, device selection, navigation and control behavior.
- Test every device-category combination at 23, 31, 39, 45 and 51 columns with real Basalt rendering.

## 0.1.25 — controller launch cleanup

- Remove `--demo`, `--direct`, `--peer`, `--remove-peer`, `--monitor` and `--auto-display` from `main.lua`.
- Manage peers and display preferences through Setup; keep `--manual`, recovery `--terminal` and internal `--boot`.
- Reject unsupported options before saving settings or starting networking/UI.
- Move the demo to the source-only `tools/demo.lua [passive|turbine]` development launcher.
- Preserve saved settings migrations, restart recovery, regulation and companion launch options.
- Cover removed flags, Setup peer edits, recovery options and demo isolation in host tests.

## 0.1.24 — standalone troubleshooting

- Move scan, local peripheral probe and report export to `diagnostics.lua`.
- Use `diagnostics scan|probe [--output FILE]`; omit arguments for help.
- Remove report modes from `main.lua`. The old flags direct users to the new command.
- Include diagnostics in both installer and updater; preserve saved modes and selections.
- Other development/legacy launch options remain pending their separate release cleanup.

## 0.1.23 — coordinator and compact UI readability

- Separate main entry-point parsing, diagnostics, backend setup and display startup.
- Split coordinator polling, command requests, mode changes, Stop and recovery into named functions.
- Split controller/peer pages and Setup rendering; share common widgets and the three-row selector.
- Preserve regulation formulas, command ordering, modes, device naming and compact UI layout.
- Include third-party attribution, a scoped licensing review and an unrun in-game acceptance sheet.
- Preserve Basalt's full notice in both installs and updates; project-wide licensing remains undecided.

## 0.1.22 — first release-cleanup pass

- Generate the updater manifest from runtime files; fix omitted network/util modules in earlier updates.
- Use one version source for the runtime and package builder.
- Split regulation into named helpers without changing formulas or command ordering.
- Expand networking and backend code; remove an unused poll-token cache. Writes still acquire fresh leases.
- Separate historical notes from the guide and track remaining release/UI work.
- Host regression, full-module update and disk-budget checks pass. A 5,000-step comparison against
  0.1.21 produced identical control commands, internal state and learned calibration.

## Earlier development builds

These notes describe each version when introduced; later entries supersede earlier behavior.
Important: the 0.1.21 fresh installer included its new network module, but its updater omitted it.
Use 0.1.22 or later to refresh existing installations completely.

Version 0.1.21 resumes Auto after temporary peer connection loss once two consecutive healthy
polls match the saved plant. Connection messages identify the peer first, for example
`Peer #4: no response; retrying`, without Lua filenames or line numbers. Changed devices and
actual control errors still pause for review. Update the controller to enable this behavior;
the companion protocol is unchanged.

Version 0.1.20 gives peer selectors the same spacing after the left arrow as the controller.

Version 0.1.19 uses centered `<` and `>` in three-row selector buttons spanning the count,
location and name rows. The controller's Rename button sits beside the right arrow without overlap.

Version 0.1.18 draws selector arrows with `/` and `\` across both rows on controllers and peers.
Peer dashboards now resize Basalt's drawing area along with the layout, preventing clipped tab
labels after a monitor changes size. Both rows of each arrow remain clickable.

Version 0.1.17 supports peer dashboards on **23 x 17 character cells**.
Every device selector now puts its count above two separate heading lines:
location (`Local / Bottom` or `Peer 4 / Back`) and the descriptive/custom device name. Its left
and right arrows span both heading rows. Compact peer screens use **All**, **React**, **Turb** and
**Power** tabs as space permits; larger displays retain the full labels. Controller selectors use
the same three-row heading while retaining their 45 x 19 minimum for the interactive controls.

Version 0.1.16 adds **Setup** to the controller dashboard. **Peers** adds/removes saved peer IDs;
**Display** chooses automatic monitor detection or the computer screen. These choices save
automatically. Save tuning and Rescan now live in Setup. Peer edits return the plant to Manual
and require fresh readings before Auto can be enabled; duplicate additions and failed edits
preserve the current configuration and mode. No peer-management command is required.

Version 0.1.15 discovers controller monitors automatically, with computer-screen fallback.
Displays can attach, detach or resize during operation without restarting the app or resetting
Auto. Old monitor names migrate to discovery; an explicit terminal-only choice is retained.
Use `reactor-control/main --auto-display` to return to automatic discovery if needed.
Peers show the main controller ID and contact status only after more than 10 seconds without
contact, and hide both when contact resumes. The same grace period applies from peer startup
when it has not yet received a message.

Version 0.1.14 uses numbered role selection: **1) controller**, **2) peer**. Enter keeps the
displayed default (controller on a fresh install, otherwise the saved role). Controller and peer
dashboards omit the redundant startup/control hints. Overview labels setups **Passive Reactors**
or **Reactor + Turbines**. Device readings, fault messages and control behaviour are retained.

Version 0.1.13 integrates startup setup into new installations. The installer asks whether this
computer is a controller or a peer, asks peers for their main controller ID, and enables startup.
Existing installations keep their role and enabled/disabled startup state when updated. To enable
or reconfigure startup after updating, run `reactor-control/startup setup` once on each computer.
This changes only startup configuration; saved Manual/Auto, device selections and display choices
are retained. Regulation is unchanged.

Version 0.1.12 adopts in-place updates without code rollback backups, adds disk accounting, and leaves documentation
in the source ZIP instead of installing it on CC. New installs still include Basalt (283,779 bytes).
Updates leave that installed dependency alone. A failed/interrupted update may leave mixed or
truncated code; rerun the updater before starting the program. Settings remain separate.

Version 0.1.11 introduced compressed offline payloads and staging with rollback backups. That
update strategy is superseded by 0.1.12 to reduce development-time disk usage.

Version 0.1.10 shows only relevant device tabs and companion summary sections, adds instant local
rod-target editing with presets and fine steps, and adds descriptive and custom device names.
Update both the main controller and companions for the complete UI and device-type metadata.

Version 0.1.9 discovers companion monitors automatically at startup and while running. No monitor
name is saved or required. Previously saved monitor names migrate to automatic detection; explicit
terminal and no-display choices are preserved. See **Optional companion displays** in README.md.

Version 0.1.8 adds read-only Basalt2 displays on companions.

Version 0.1.7 adds `--output FILE` to probe and scan. It saves the full report, including long
method lists and scan errors, and prints just the saved path. Without `--output`, diagnostics
continue to print to the terminal as before.

Version 0.1.6 adds `--remove-peer ID` and lists the configured peers in scan output.
Downloads now have version-specific filenames; scan and probe also print the running version. `--peer ID`
adds to the saved list; it never replaces that list. Removing or adding a peer saves Manual
and clears the previous Auto snapshot, so the changed plant can be reviewed. Adding an already
configured peer or removing an absent one leaves the saved mode intact.

Version 0.1.5 adds controller/companion startup setup and remembers the last chosen Manual/Auto
mode. Enable Auto once after upgrading to save the current plant for future restarts. At launch,
saved Auto waits for two consecutive healthy polls matching its saved generators, storage
selection and peer list, then resumes. It preserves the turbine standby phase too. Initial
connection failures do not discard that request. The UI shows **Mode: WAIT** while restoring Auto; clicking Mode while waiting cancels restoration and saves Manual.

Version 0.1.4 corrects the Overview display: passive systems show their charge target;
turbine systems show their configured automatic generation/standby thresholds (75%/90%
by default). Turbine systems no longer display the unused passive charge target. Passive
standby is labelled **Standby**; turbine standby remains **Spinning standby**.

Version 0.1.3 improves passive-reactor braking when a load disappears during recovery to the
charge target. A faster charging-trend signal detects the growing surplus, and a longer
look-ahead near target requests earlier, stronger rod insertion within the existing rate limit.
The extra look-ahead blends in over the last percentage point below target. Steady-charge
adjustments and turbine control retain their previous policies. Existing configuration files
receive `passiveBrakingSeconds = 90` in memory; no configuration edit is required.

This cumulative update also includes previous fixes. It recognizes the observed
`BigReactors-Reactor` type as well as the previously supported reactor-port name, and adds a
native Mekanism Energy Cube adapter. `--probe` lists all local types/methods when troubleshooting.
Version 0.1.2 keeps removed selected batteries on the Storage page as **Disconnected storage**.
Select the old entry and click **Remove from control**, then select a replacement if desired.
The old peripheral ID does not need to be restored. Remaining selections are preserved, the
removal is saved, and Auto must be re-enabled explicitly after reviewing the revised storage.

It also accelerates passive-reactor rod withdrawal when storage is low and rod insertion when
storage is over target or rising quickly. Adjustments taper as the charge error/trend decreases.
Existing configuration files automatically receive the new defaults in memory.
