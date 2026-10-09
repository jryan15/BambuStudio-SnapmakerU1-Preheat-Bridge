# 5.48.0-u1.1 — Advance heating and filament mapping

Based on upstream 5.48.0, commit a96942e35ca6d30d0231f926f3b05eb8ae7eb816. Original attribution and GPL-3.0 license retained.

## Changes

- Prepare advance heating automatically after bridge filament mapping; default lead 30 seconds, existing preferences retained.
- Show only plate-used filaments, including sparse project slots above four.
- Allow project filaments to share physical heads; preserve native pauses, temperature checks, and sliced material settings.
- Compact shared-head notices and a warning when more than four filaments are used without a pause.
- Convert Print and Upload files automatically, including native-style identification and indexed filament usage required by the tested touchscreen. Preserve sliced print-body commands and bed offsets.
- Verify prepared file contents and use the printer-returned file path before starting a bridge print.
- Address physical heads 0–3 in startup loading/calibration macros while retaining logical project IDs in tool and temperature commands. This corrects an invalid-index bug; it does not establish a fix for the native five-color anomaly.

## Validation

94 automated tests cover heating, pauses, sparse slots, shared assignments, conversion, upload paths, and start verification. Update installer checks cover busy refusal, payload hashes, repeat installation, rollback, and changed-baseline refusal. Reported successful physical tests cover advance heating, used-filament filtering, shared mapping, bridge prints, and touchscreen recognition.

## Known limitations

Touchscreen-started uploads can wait for heating. Five-plus-color touchscreen startup is unresolved and also failed in a native Snapmaker Orca test. The startup correction requires further physical confirmation; automated checks passed. Manual Convert retains upstream behavior. Linux is unvalidated for this revision.

No printer firmware changes are required.
