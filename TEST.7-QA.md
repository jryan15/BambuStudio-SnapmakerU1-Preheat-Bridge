# u1.4-test.7 — private review package

Built from the supplied 6,452,892-byte test.6 ZIP. The original ZIP is unchanged. Nothing has been pushed or published. TEST.6-QA.md and AUDIT-REPORT.md are historical reports.

## Changes

- Manual Convert counts actual standalone layer markers in the print body, not mentions inside saved configuration comments.
- Both manual and automatic conversion preserve the original startup Z_OFFSET commands for Z homing and bed mesh calibration.
- Setup offers a normal close of Bambu Studio before modifying files. It allows up to 60 seconds for unsaved-work dialogs. If Bambu stays open, setup stops without forcing it closed.
- Setup displays failures in a message box, with backup details still available in Details.
- After successful installation/update, setup offers to open the selected Bambu executable through the Windows desktop shell.
- Setup title reads the package version instead of a stale hardcoded test number.
- The 0.4 mm model is labeled Snapmaker U1 - 0.4 mm. Existing machine/process/filament preset names and inheritance names are retained. The installer migrates the standard model identity and removes the duplicate legacy model tile from the vendor registry. Custom settings in the base preset are preserved.
- LM Studio's provider label is English.
- Fluidd text/binary proxy and responsive layout fixes from test.6 are retained.

## Checks completed for this build

- 97 bridge tests passed, including new regression cases for both conversion paths.
- The user's original 0_PLA_27m56s.gcode converts to 15 layers, preserves both -0.07 mm offsets, and retains all 30,551 motion commands identically in manual and automatic conversion. The user's source/output files are not included in this distributable.
- 49 installer file-engine checks passed, including the 0.4 mm model migration, custom-setting preservation, unique model registration, and uninstall.
- Installer transaction scenarios passed: fresh install, current bridge retained, injected upgrade failure/rollback, older upgrade, selected removal and uninstall. Windows services/process operations are mocked.
- PowerShell syntax parsed successfully. Package payload hashes verified.

## Actual user hardware results on test.6 (not repeated on test.7)

- Update completed after Bambu was closed.
- Native Bambu Printer Selection displayed all four nozzle entries; 0.4 still had its old unsuffixed label.
- About showed test.6.
- Embedded Fluidd received a reply to read-only M115 from Klipper.
- Camera video and physical light on/off worked.
- Debug auto-refresh/tab-switch reset and log export worked.
- AI Config reported connection refused for the unavailable local LM Studio endpoint. No AI optimization was tested.
- Manual conversion/download produced the file that exposed the two corrected discrepancies.

## Not claimed as tested

The new Windows close/reopen prompts, 0.4 label in actual Bambu, and printing with test.7 have not been tested on hardware. No additional print was requested from the user. AI optimization remains unverified. This package is suitable for review toward a prerelease, not a claim of complete hardware validation.

## Install

Wait for the printer to be idle. Extract into a new folder and run SETUP.bat. Check program/settings folders, then apply Update. If Bambu is open, accept the normal-close prompt and handle any unsaved-work dialog. After success, accept the offer to open Bambu. Enable the renamed 0.4 mm model in Printer Selection if needed; custom printer presets keep their existing names. All four heads must match the selected nozzle diameter.
