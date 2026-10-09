# Snapmaker U1 Bridge for Bambu Studio

Version **5.48.0-u1.1** adds advance heating and flexible filament mapping to the upstream 5.48.0 compatibility package. This is a community revision, not an official Snapmaker or Bambu Lab release.

Based on [VitasGuo/BambuStudio-SnapmakerU1-Compat](https://github.com/VitasGuo/BambuStudio-SnapmakerU1-Compat), commit a96942e35ca6d30d0231f926f3b05eb8ae7eb816. Original author attribution and the GPL-3.0 license are retained. The original documentation remains in README.md.

## Windows installation

1. Finish any active print and close Bambu Studio.
2. Extract the Windows release ZIP to a folder.
3. Right-click install.bat and choose Run as administrator. The upstream installer installs the profiles and bridge. Node.js is required and may be installed by that installer.
4. Reopen Bambu Studio and confirm the Device page reports **5.48.0-u1.1**.

Existing testers can instead use their separately supplied Windows-Update ZIP. Extract it and run INSTALL.cmd; RESTORE.cmd restores the previous bridge. That update archive is specific to its recorded installation baseline.

## Recommended print workflow

Select the Snapmaker U1 profile, slice, and choose Print. In the Device tab, map each used project filament to the physical head containing its filament, then start printing. The bridge prepares advance heating after the head mapping is confirmed. The default lead is 30 seconds; existing saved preferences are retained. Temperature waits remain as a fallback.

Only filaments used on the plate appear. Multiple project filaments can share a head. Shared assignments are called out; more than four used filaments without a pause produces a warning. Sliced temperatures and flow settings are retained, so shared assignments must suit the loaded material. Existing pauses are preserved; filament replacement is manual.

## Print versus Upload

- Print prepares the file automatically and opens the bridge filament confirmation workflow.
- Upload prepares a touchscreen-compatible file and stores it without starting a print. Starting that file later through the bridge prepares heating for the confirmed mapping.
- Starting an uploaded file on the printer touchscreen uses the touchscreen mapping, but this revision does not add mapping-aware advance heating for that path. Heating waits may occur.
- The manual Convert page remains available as an upstream utility. It is not needed for automatic Print/Upload and does not receive all automatic-path metadata fixes.

## Known limitations

Five-plus-color touchscreen starts are unresolved. A native Snapmaker Orca five-color test also raised system anomaly **0003-0522-0000-0000** after tool checks. This revision does not claim to fix that anomaly. The bridge workflow has been tested by the user with shared assignments; arbitrary models and mappings are not guaranteed.

Windows is the tested platform. Upstream Linux installation is retained but this revision has not been physically validated on Linux.

See RELEASE-NOTES.md for validation details.
