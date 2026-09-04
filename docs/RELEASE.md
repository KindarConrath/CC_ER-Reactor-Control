# Release preparation

0.1.36 removes persistent success/status messages from the turbine operating dashboard;
it is not yet a public-release sign-off.
Regulation formulas and saved settings remain compatible.

## Completed cleanup work

- Named regulation helpers separate storage trends, turbine flow, reactor demand and rod rates.
- Networking/backend code uses descriptive locals and explicit request/response handling.
- Removed the unused poll-token cache. Fresh, one-use command leases remain required.
- Runtime headers and packaging use `lib/version.lua` as their single version source.
- Updaters include every first-party runtime module. Older manifests omitted the network module.
- User instructions and development history are separate.
- `main.lua` separates argument parsing, backend creation and display startup.
- `diagnostics.lua` owns scan, probe and report export without starting the UI or control loop.
- Controller peer/display setup uses the UI, and the demo has a source-only development launcher.
- `main.lua` accepts only Manual recovery, terminal recovery and managed-boot flags.
- The coordinator separates polling, requests, mode/selection changes, Stop and recovery.
- Explicit calibration is isolated from normal RPM regulation, uses a temporary session until every
  turbine and the capacity check finish, and has bounded save retries and progress displays.
- Steam-capacity monitoring reports sustained full-output shortages without changing commands or
  treating ordinary spin-up as a capacity failure.
- Setup starts sequential turbine calibration without depending on external load, followed by a
  combined reactor-demand verification; normal operation never relearns saved points automatically.
- Controller/peer pages and Setup use named renderers; common widgets/selectors live in `lib/ui_widgets.lua`.
- [Licensing review](LICENSING.md) records the bundled notices and remaining provenance/license decisions.
- [In-game acceptance sheet](ACCEPTANCE.md) gives steps and expected results for the existing two setups.
- Host regression and packaging checks cover complete updates, startup, settings preservation,
  reconnection, manual cancellation, existing UI behavior and the 1 MB disk budget.

## Remaining before public release

- [x] Apply the readability pass to the coordinator, main entry point and controller/peer/Setup UI modules.
- [x] Split the coordinator's long command-processing function into focused handlers without
  changing command order, Stop precedence or mode persistence.
- [x] Consolidate shared UI layout helpers without coupling the coordinator/control logic to Basalt.
- [ ] Continue readability review of adapters, settings, remaining launchers and presentation helpers.
- [x] Remove the six legacy/development controller flags; retain saved-settings migrations.
- [ ] Review companion/installer launch options separately before public release.
- [ ] Agree on the project's license and attribution. Basalt's MIT notice remains bundled;
  that does not choose a license for this project's own code.
- [ ] Resolve the pinned-revision provenance verification gap recorded in LICENSING.md.
- [ ] Confirm the public project name, repository/distribution location and release version.
- [ ] Review the user guide for stale behavior and label the tested mod/version/storage matrix.
- [ ] Run the in-game acceptance checks below on the cleanup builds.

Keep regulation formulas and RPM targets unchanged during cleanup. The requested 0.1.28 feature
extends calibration lifecycle and persistence, not the regulator or peak-band selection. Host tests
cannot establish behavior under every modpack's physics, thermal lag or server/network timing.

## In-game acceptance checks

The executable test sequence and result sheet are in [ACCEPTANCE.md](ACCEPTANCE.md).
All in-game results remain unverified for this build until the user runs them.

Update the controller first; 0.1.22 supplies dependencies missed by the 0.1.21 updater.
Exit the application before updating. Rerun an interrupted updater before starting the program.

- [ ] Fresh controller and peer installs create working startup launchers.
- [ ] An existing installation retains its role, peer IDs, storage selections and display choices.
- [ ] Two passive reactors regulate the selected storage under steady and changing load.
- [ ] A cooled reactor and two turbines hold the accepted speed target and standby behavior.
- [ ] Direct peripherals, wired modem devices and wireless peers remain usable.
- [ ] Reboot a peer in Auto: readable status, no writes while waiting, then recovery after two
  healthy matching polls. Repeat with Manual/Stop during the outage and confirm no auto-resume.
- [ ] Replacing a device or changing selections requires review rather than silently changing Auto.
- [ ] Attach/remove/resize controller and peer monitors; verify fallback, tabs and device selectors.
- [ ] Restart the server with peers starting at different times; verify saved Auto recovery.

## Next phase: optional graphical UI

Keep the compact interface available. Add a separate Basalt2 presentation using the same telemetry,
command queue and configuration; it must not introduce another control loop or alter regulation.
Choose the interface through Setup, with a usable fallback for small or missing monitors.

Visual references requested by the user:

- [Kasra-G/ReactorController](https://github.com/Kasra-G/ReactorController): its README describes
  a graphical UI with configurable information modules.
- [hexxone/cc-fusionmon](https://github.com/hexxone/cc-fusionmon): its README describes monitoring
  Mekanism fusion-related devices. Treat it as a presentation reference, not an Extreme Reactors API.

Before implementation, review screenshots and choose the useful elements: compact status panels,
storage/fuel gauges, turbine speed displays and bounded history charts are candidates, not commitments.
Verify attribution/license requirements before reusing any code or assets. Keep optional graphics
and history bounded by the CC disk/memory budget, and omit irrelevant device categories as today.

## Maintainer workflow

Use two-space indentation, descriptive locals, one statement per line and small functions with one
responsibility. Comments should explain units, ordering constraints or non-obvious control decisions.
Keep plain Lua modules; do not introduce class hierarchies merely to organize functions.
Vendor code stays pinned and unmodified. Compatibility migrations are not dead code merely because
the current UI no longer exposes the old option.

Change `lib/version.lua`, update the current download examples and changelog, then run:

```text
python tests/run.py
python tools/package.py
python tests/packaging.py
```

Ship both installer and updater, plus the source archive. Documentation/tests stay in the archive,
not on the CC disk. Packages exclude saved state, credentials and other unrelated workspace files.
