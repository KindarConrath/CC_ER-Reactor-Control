# Release checklist

## Public prerelease 0.1.42

This is the first public prerelease. Earlier 0.1.x builds were development-world packages and are
not treated as supported public releases.

### Release contents

- `reactor-control-install-0.1.42.lua`: self-contained CC:Tweaked installer, including Basalt2.
- `reactor-control-0.1.42.zip`: source, documentation, tests, tools, and the installer.
- No updater asset. The updater remains maintained in source and can be built with
  `python tools/package.py --with-updater` for compatibility testing or a later release.

### Completed

- [x] Controller and peer startup installation.
- [x] Direct, wired-modem, and wireless-peer discovery.
- [x] Passive multi-reactor regulation under steady and changing loads.
- [x] One cooled reactor with multiple independently calibrated turbines.
- [x] Explicit calibration and combined steam-capacity verification.
- [x] WAIT/reconnect behavior and saved Manual/Auto restoration.
- [x] Automatic controller and peer monitor handling, including compact peer screens.
- [x] Tested storage adapters documented in the README.
- [x] Controller, peer, setup, device-adapter, restart, UI, and packaging host checks.
- [x] User-facing README separated from development history.
- [x] Basalt2 pinned revision and license verified; hashes recorded.
- [x] Git ignore rules exclude generated builds, state, diagnostics, and Python caches.
- [x] One-letter identifiers removed from first-party runtime, tools, and test fixtures except
  intentional ignored values and coordinate fields.

### Required before publishing

- [x] Add the MIT project license with KindarConrath copyright wording.
- [x] Insert the public repository URL and versioned in-game `wget` command.
- [x] Run the complete host suite on the final version and license bytes.
- [x] Inspect the final ZIP contents and installer disk footprint.
- [ ] Create a GitHub prerelease, attach only the versioned installer and source archive, and use the
  0.1.42 changelog entry as release notes.

## Maintainer workflow

Use two-space Lua indentation, descriptive names, one statement per line, and small functions with
one responsibility. Keep control logic independent from Basalt presentation code. Vendor code stays
pinned and unmodified. Saved-settings migrations are compatibility code, not dead code.

Before packaging:

```text
python tests/run.py
python tools/package.py
python tools/package.py --with-updater
python tests/packaging.py
```

The first package command creates public artifacts. The second explicitly creates the development
updater so its path remains tested. Documentation and tests belong in the source archive, not on the
CC computer. Packages must not contain saved state, credentials, diagnostic exports, or unrelated
workspace files.

## Later work

- Optional richer graphical UI using the same telemetry and command queue.
- Per-reactor automatic/manual selection for baseline and surge generation.
- Additional storage adapters when current ATM10 peripherals can be inspected and tested.
- A public updater once there is a supported public version to update.
