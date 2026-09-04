# In-game release checks — 0.1.36

Status: **not run in Minecraft for this build**. Host regressions are separate evidence.
Use the existing test world or a recoverable copy. Devices retain their last settings while
controllers/peers are offline; a Stop request cannot reach a disconnected device.

## Record the environment

- Minecraft: 1.21.1
- Pack name/version: __________
- CC:Tweaked version: __________
- Extreme Reactors version: __________
- Controller and peer IDs: __________
- Storage mods/tiers used: __________
- Monitor dimensions and text scale: __________
- Test date and tester: __________

Update the controller first, then peers. Exit before updating, and rerun an interrupted updater
before starting the program. Verify every tested screen reports 0.1.36. The updater preserves
configuration, saved selections, aliases, role/startup choices, display preferences and Basalt.

## Suggested order

| Check | Action | Expected result | Result |
| --- | --- | --- | --- |
| Existing install | Update a controller and one peer | Settings/role retained; all runtime dependencies available | Not run |
| Fresh install | Install on a spare Advanced Computer, choose controller; repeat as peer | Setup and controls work on the first launch; managed startup also works after reboot | Not run |
| Idle Manual | Start in saved Manual and observe rod/flow/active settings | No automatic changes | Not run |
| Peer recovery | In Auto, restart a connected reactor or storage peer | Short peer status and WAIT; same plant resumes after two healthy polls | Not run |
| Repeated outage | Interrupt contact again before recovery completes | Readiness count resets; no premature Auto | Not run |
| Cancel recovery | During an outage choose Manual; repeat with Stop | Automatic recovery stays cancelled; Stop reaches available devices only | Not run |
| Changed plant | Replace/remove a selected device, or edit peer/storage selections | No silent substitution or automatic approval of changed plant | Not run |
| Passive control | Run the two-passive-reactor setup with steady load, then add/remove load | Regulation returns toward the configured charge target; record min/max and settling time | Not run |
| Turbine control | Run one cooled reactor with two turbines and a selected bank | Existing RPM regulation, coil behavior and storage standby thresholds unchanged | Not run |
| Explicit calibration | With storage already high, enable Auto and choose Setup > Tuning > Calibrate turbines | Turbines calibrate one at a time with clear do-not-adjust status; no sustained external load is required | Not run |
| Combined capacity | Let the explicit routine measure every turbine | All turbines run together; ten stable seconds report verified combined demand, or a fully-open shortage reports failure | Not run |
| Calibration status | After completion, cycle between generation and standby | Saved count remains fixed; normal operation never starts calibration or rewrites tuning | Not run |
| Calibration persistence | Reboot after completion; observe ordinary stable operation | Saved points restore without a calibration or capacity check | Not run |
| Coil upgrade | Modify coils, return to Auto, then explicitly run Calibrate turbines | Normal control does not infer the change; the requested routine replaces tuning after it completes | Not run |
| Reactor steam limit | After generating calibration, reduce reactor capacity or add sufficient turbine demand; repeat during initial spin-up | Sustained full-output shortage warns with measured output/demand while Auto continues; ordinary spin-up does not warn | Not run |
| Reactor stalled | While output is required, prevent one passive reactor from producing; repeat with the cooled reactor | After 30 seconds, identify the passive reactor or show measured zero steam; clear after three seconds of recovery | Not run |
| Turbine mechanical limit | With adequate reactor steam, use a turbine whose RPM falls at maximum flow with coils engaged | Per-turbine maximum-flow/RPM-falling warning appears after ten seconds and clears after recovery | Not run |
| Steam-limit recovery | Restore adequate reactor output, enter standby, then repeat with no fuel | Warning clears after recovery/standby; empty reactor warns without rods being withdrawn | Not run |
| Calibration save error | On a spare computer, reproduce a settings-write failure at completion, then restore writable space | Unsaved warning; Auto continues; periodic retry or Tuning > Retry save clears the warning | Not run |
| Storage selection | Check the Mekanism cube, RFTools powercell and EnderIO bank individually | Readings plausible; selection saved; missing selections removable | Not run |
| Transport | Exercise adjacent peripherals, wired devices and wireless peers | Same supported device readings and controls | Not run |
| Manual UI | Edit rods using presets/fine steps/Apply; rename a device | Drafts responsive; correct device changed; names persist | Not run |
| Setup UI | Add/remove a peer, type while polling, switch display preference | Input survives refresh; saves apply; Stop remains accessible | Not run |
| Launch cleanup | Try removed controller flags; use `--terminal`, then Setup to restore Auto display | Removed flags reject without settings changes; display recovery preserves saved control mode | Not run |
| Displays | Resize/remove/replace monitors, including compact peers | Layout/buttons remain usable; controller falls back to computer | Not run |
| Peer tab labels | Compare 3x3 and four-monitor-wide peers; attach/remove reactor, turbine and storage categories | Reactor/Turbine fit at four wide; at 3x3 only all three categories require React/Turb; all tabs remain clickable | Not run |
| Peer tab spacing | Repeat with zero, one, two and three device categories; resize smaller/larger | One-cell gaps and outer margins remain; sparse tabs do not stretch; gaps do not activate tabs | Not run |
| Restart order | Restart controller and peers in different orders; later do a server restart | Saved Auto waits for the saved plant; saved Manual remains Manual | Not run |

Selecting multiple ports of one physical battery/network can double-count capacity unless their
identity mapping deduplicates them. Use one selected port per physical store during these checks.

## Report a failure

Record the test row, computer ID, mode, device IDs, exact message and steps needed to reproduce it.
For long peripheral details use `reactor-control/diagnostics probe --output probe.txt`; for discovered
devices use `reactor-control/diagnostics scan --output scan.txt`. Run diagnostics after exiting the UI.
Exported files can be copied from that computer's CC directory. Do not delete live CC files from
the host while the world is running; use in-game file operations.

Do not mark this build release-ready until the relevant rows pass and remaining licensing/release
decisions in RELEASE.md are resolved. Past development-world results do not certify this refactor.
