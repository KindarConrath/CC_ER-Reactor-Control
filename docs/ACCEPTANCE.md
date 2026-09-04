# In-game acceptance record — development builds through 0.1.41

Environment: Minecraft 1.21.1, ATM10, CC:Tweaked, Extreme Reactors, and bundled Basalt2.
Exact modpack/mod build numbers were not recorded. The 0.1.42 public-preparation changes affect
documentation and packaging; its runtime remains subject to the final host regression suite.

## Completed in the development world

| Area | Observed result |
| --- | --- |
| Passive plant | Two passive reactors regulated a 102.4M FE store around the 70% target under multiple cable loads and recovered after sudden load removal. |
| Turbine plant | One cooled reactor and two turbines reached and held the selected peak band; spinning standby and generating transitions behaved as expected. |
| Calibration | Each turbine calibrated independently with coils engaged, followed by a successful combined reactor-capacity check. |
| Capacity warnings | Reactor steam-limit and turbine maximum-flow/falling-RPM warnings appeared under induced shortages and cleared after recovery. |
| Stalled output | Passive and cooled reactor stalled-output warnings appeared and recovered as expected. |
| Startup | Fresh roles created startup launchers; controllers and peers restored after computer/world restarts. |
| Peer recovery | Rebooted peers caused WAIT and reconnected; saved Auto resumed only after the plant returned. |
| Networking | Adjacent peripherals, wired modem networks, and wireless peers worked in the test layouts. |
| Displays | Controller switched between its terminal and a monitor; peers recovered when monitors returned and remained usable down to 3x3. |
| Storage control | Mekanism Energy Cube, Ender IO Capacitor Bank, and RFTools Powercell readings/control were exercised. |
| Additional adapters | Integrated Dynamics battery and Draconic Energy Core reported correctly; Induction Matrix and Extreme Reactors Energizer APIs were probed and adapted. |

## Known limits and cautions

- Flux Networks blocks in the tested pack could not be exposed as CC:Tweaked peripherals.
- A monitor text field still uses the attached computer's keyboard; this is normal CC:Tweaked input behavior.
- Select one port per physical energy store to avoid double-counting capacity.
- Turbine calibration needs a mechanically viable turbine and enough reactor steam for the combined check.
- Host tests cannot reproduce server tick rate, chunk loading, reactor thermal lag, or every modpack configuration.

## Final prerelease smoke test

Run these checks on the exact published installer:

1. Fresh-install one controller and one peer; reboot both and confirm their roles start automatically.
2. Confirm the controller starts in Manual and lists the expected plant once.
3. Select storage, enable Auto, and verify passive or turbine regulation begins.
4. Restart a peer during Auto; confirm WAIT, readable status, and reconnection.
5. For a turbine plant, run explicit calibration and confirm automatic saving.
6. Remove and restore the controller monitor; confirm terminal fallback and return.
7. Run `diagnostics scan` and `diagnostics probe --output probe.txt`.
8. Confirm the installed program plus the downloaded installer remain below the 1 MB computer quota.

Record any failure with computer IDs, mode, device IDs, exact message, and reproduction steps. Do not
delete live computer files from the host while the world is running; use in-game file operations.
