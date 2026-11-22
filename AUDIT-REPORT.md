# Snapmaker U1 test.5 audit

This is a test build, not a fully validated public release. No physical printer was controlled during this audit. GitHub has not been updated.

## Device-page coverage

| Tab | Verified | Still needs real-system testing |
|---|---|---|
| Device | Page scripts, connection modal, temperature/light/speed requests sent to a loopback simulated printer | Camera, actual hardware controls, real status updates |
| Console | Fluidd HTML, JavaScript asset and generated endpoint configuration served successfully | Visual Fluidd rendering and firmware connection |
| Debug | Page scripts, export endpoint, refresh stops when leaving tab; vertical layout corrected | Windows browser appearance and large real logs |
| AI Lab | Page scripts, missing-provider guard, workspace edits preserved through initialization | Real provider requests and generated suggestions |
| Convert | Empty-input guard; synthetic Bambu upload, conversion and download; original retained; first tool 2 retained | Real files and physical prints on each nozzle size |
| About | Fork links, English default/language toggle, U1 revision and prerelease comparison | Live release availability on user's network |

All six tab scripts ran under jsdom with no script/resource errors. This is a DOM/API test, not a visual browser test. Browser execution was blocked by this environment. Fluidd was HTTP-tested separately rather than executed under jsdom.

## Installer coverage

- 27 file-engine assertions using actual temporary files: install, preservation, repeated runs, removal, classification and rollback.
- Transaction scenarios exercise fresh install, retained current bridge, older bridge upgrade, injected failure rollback, removal and uninstall. Windows process/task operations are mocked.
- Nozzle profile validator checks inheritance, model registration, compatibility and diameter configuration.
- PowerShell parsing checks syntax; this is not Windows GUI execution.
- Bridge unit suite: 95 passing tests, including workspace preservation.

The earlier test.4 distinct printer-model fix remains included. Original 0.4 mm stays `Snapmaker U1`; additional models are `Snapmaker U1 - 0.2 mm`, `0.6 mm`, and `0.8 mm`. Existing grouped optional profiles are migrated without replacing their other settings.

## Fixes from this audit

- Default to English while respecting a saved language choice.
- About and release checking refer to this fork, with upstream attribution retained.
- Compare U1 revisions and test revisions correctly.
- Fix Debug vertical layout and stop its refresh timer when leaving.
- Preserve edited AI workspace documents instead of overwriting them at startup.
- Return a usable connection-settings response if network-interface enumeration is unavailable.
- Show `Needs repair` for old grouped nozzle profiles and show both versions for bridge updates.
- Translate remaining conversion error messages and folder tooltip.

## Remaining acceptance test

Wait until the printer is idle. Close Bambu Studio, extract into a new folder and run `SETUP.bat`. Confirm the correct program/settings folders, install, then reopen Bambu and enable the new U1 models in Printer Selection. Confirm the bridge version is `5.48.0-u1.4-test.5` and the selected nozzle matches all four installed heads.

Windows UAC, scheduled tasks, Node download/bootstrap, real process restart, Bambu profile loading/slicing and physical prints still require testing on Windows and the printer. Do not publish this as fully tested based on the automated audit alone.

## Reproduction

Run `npm test` in `bridge-node`; run `setup/Test-Engine.ps1` and `setup/Test-Transaction.ps1` with PowerShell; run `python3 tools/nozzle-profiles/validate.py`. DOM audit requires jsdom 26 and the bridge dependencies: set `AUDIT_DOM=1` and `JSDOM_PATH` to the installed jsdom directory, then run `node tools/audit/device-ui.cjs`. It launches only a temporary loopback bridge and simulated printer.
