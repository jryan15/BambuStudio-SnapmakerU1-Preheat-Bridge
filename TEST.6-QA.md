# Snapmaker U1 Bridge u1.4-test.6

Private Windows test build based on the exact u1.4-test.5 ZIP. The original ZIP and installed bridge were not changed. AUDIT-REPORT.md is the historical test.5 report.

## What changed
- The Fluidd WebSocket proxy preserves text and binary frame types in both directions, including browser messages queued while the connection opens. Fluidd can now read Moonraker's JSON responses as text.
- The Device page keeps the jog controls alongside the panel on desktop and moves them below it at narrower widths. Temperature readings and inputs no longer overlap at the tested narrow width.
- No changes to nozzle profile files, build-plate handling, or conversion and printing logic.

## Tested without a physical printer
- Retested Device, Console, Debug, AI Lab, G-code Convert, and About in Edge at 1280px and 520px against the packaged bridge and a simulated Moonraker. Fluidd reached Ready at both widths. No JavaScript exceptions or HTTP errors were observed. The narrow controls no longer overlap; wide controls stay side by side.
- Debug auto-refresh starts and stops on tab change. AI Lab's missing-provider notice, Convert's missing-file notice, About's version, and the language toggle were checked.
- A loopback proxy test confirmed text and binary frames retained their types and payloads in both directions, before and after the upstream handshake.
- All 95 bridge tests passed. All 45 installer engine checks passed, including registration of all four nozzle sizes and recognition of test.5 as an upgrade candidate. Installer transaction tests passed on temporary files with Windows services mocked: fresh install, profile-only update, failed-upgrade rollback, successful upgrade, profile removal, and uninstall.

## Still to verify
- Fluidd Console command round-trip was not verified in the browser.
- Four registered nozzle profiles are not proof that native Bambu Studio displays them. Verify 0.2, 0.4, 0.6, and 0.8 mm in Printer Selection and confirm the selected diameter matches the installed heads before a small supervised test print.
- Real printer controls, camera, AI provider/persistence, and browser end-to-end conversion were not verified. This is not a public release or a recommendation to replace a working install mid-print.
