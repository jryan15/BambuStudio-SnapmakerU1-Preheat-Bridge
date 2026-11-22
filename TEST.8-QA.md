# Setup test.8 — correct settings target

Installer-only revision of test.7. Included bridge and nozzle profiles remain byte-for-byte unchanged. About will still show bridge test.7; setup shows test.8. Nothing published.

## Fix
The previous startup rule selected BambuStudioBeta whenever an old Beta Snapmaker registry existed. That targeted the wrong user settings for regular Bambu. Removed that rule.

Setup now selects BambuStudio for the regular application and BambuStudioBeta for a Beta-named application folder or Beta executable ProductVersion. Unknown/custom locations default to regular; manual selection remains available. Changing the program folder refreshes the suggested settings folder. An edition mismatch requires explicit confirmation before applying changes. This is heuristic edition detection, not a claim that every custom executable/data-directory override can be identified.

## Validation
55 file-engine checks passed, including stale Beta profiles alongside regular Bambu, Beta directory, Beta executable metadata, regular executable metadata, trailing separator and custom directory cases. PowerShell syntax parsed. Bridge and nozzle payload hashes match test.7. Native Windows dialog behavior has not been tested here.

## User hardware result carried forward
The user reports all four nozzle choices now work after targeting regular BambuStudio settings with test.7. The earlier absent-printer symptom was resolved without changing model registration. This confirms test.7 registration worked for that installation; the installer target selection was wrong. All other test.6/test.7 validation limits remain documented in their reports.

## Use
Extract into a new folder; run SETUP.bat. Review the visible program/settings paths. A current intact test.7 bridge stays running and is not replaced. If all selected profiles already match, Already installed is expected. A reinstall is unnecessary for a user who already corrected the target with test.7.
