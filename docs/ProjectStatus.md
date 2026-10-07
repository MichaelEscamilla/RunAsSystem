# Project Status

Where the project stands, the decisions behind it, and what's left to do. Update this file when one of these changes.

_Last updated: 2026-10-06 (initial build, version 2026.10.6.0)_

## Goal

Make it easy to run MSI and EXE installers (and scripts) as SYSTEM to test installs the way ConfigMgr and Intune run them, without downloading PsExec and running it from the right folder. Pick an installer, type the arguments, click Run.

## Decisions Made (and Why)

| Topic | Decision | Reason |
| --- | --- | --- |
| Look and structure | Match [GetMSIInformation](https://github.com/MichaelEscamilla/GetMSIInformation) and [CodeSigningTool](https://github.com/MichaelEscamilla/CodeSigningTool): one `.ps1` file with WPF, the same palette, update check, right-click menu and `iex (irm …)` launch | Keeps the tool family consistent |
| PowerShell version | Windows PowerShell **5.1**, with no relaunch into pwsh | Testing often happens on devices that don't have PowerShell 7 |
| How it runs as SYSTEM | A one-time Scheduled Task (Session 0) by default, based on the [Patch My PC Connectivity tool](https://github.com/PatchMyPCTeam/CustomerTroubleshooting/tree/Release/PowerShell/Connectivity) | Avoids PsExec, and Session 0 is how ConfigMgr and Intune really run installers |
| Interactive mode | Optional PsExec mode (`-s -i`) | Lets you see the installer's UI. If PsExec isn't found, the tool offers to download it from live.sysinternals.com **into the installer's folder** (the owner's choice) |
| File types | `.msi`, `.msp`, `.exe`, `.ps1`, `.cmd`, `.bat`, `.vbs` | MSI and EXE are the main use; scripts were requested too |
| MSI options | An action choice (Install `/i`, Uninstall `/x`, Repair `/fvomus`), a UI level, `/norestart`, and `/l*v` | Requested |
| MSI log name | `<installer file name>.log` next to the installer, e.g. `Setup.msi.log` | The request said "match the installer but add .log", which was taken literally. If `Setup.log` is preferred, change `Get-DefaultLogPath` |
| Working directory | The installer's own folder | Matches ConfigMgr and Intune |
| Copy to a local cache first | **Not done** | The owner said it wasn't needed |
| Timeout or kill button | **Not done** | The owner said it wasn't needed |
| 32-bit (Intune-style) launch | **Not done** | The owner said it wasn't needed |
| Detection-rule help (new Uninstall registry entries) | **Not now** | Possible later |
| History | `%LOCALAPPDATA%\RunAsSystem\History.json`, last 50 runs, with Load, Copy and Clear | It saves locally even when the script is launched with `iex` |
| Drag and drop while elevated | Uses `WM_DROPFILES` with a message filter, plus Browse, paste and the right-click menu | The app has to run elevated, which normally blocks drag and drop from Explorer |
| Parameters | `-FilePath` and `-Arguments` | Needed by the right-click menu and handy for scripting |
| Name | RunAsSystem | The repo folder already used this name |

## Verified

These were tested in Windows PowerShell 5.1, but **not elevated**:

- The script parses in 5.1 and contains only ASCII characters.
- The XAML loads and the window renders (checked with an offscreen screenshot).
- The command line is built correctly for all seven file types and for PsExec mode.
- The MSI options panel shows and hides as expected, and the default log path is filled in.
- Exit codes get the right meaning and colour category.
- History saves, reloads, loads back into the form and clears.
- The elevated drag-and-drop hook compiles and attaches.

## Not Yet Tested (Needs an Elevated Session)

- [ ] A Session 0 run end to end. A `test.cmd` containing `exit /b 3010` should show **3010** in orange.
- [ ] The `RunAsSystem_*` task is deleted after the run, and leftover tasks are cleaned up when the app starts.
- [ ] Closing the app during a run: the warning appears, and the task cleans up later.
- [ ] A real MSI install, uninstall and repair, with the log written next to the installer.
- [ ] PsExec mode, both when PsExec is found and through the download prompt. Check that the exit code is passed back.
- [ ] Drag and drop from Explorer into the elevated window.
- [ ] Right-click menu install and uninstall: the menu shows the UAC shield and opens the app with the file loaded.
- [ ] The relaunch-as-admin step, both when the script is run from a file and when it's launched with `iex`.
- [ ] The update check (it needs a published GitHub release first).

## Known Limitations

- With no timeout or kill button, an installer that waits for input in Session 0 runs until it's stopped in Task Scheduler or Task Manager.
- PsExec rebuilds the argument list it passes on, so MSI properties with quoted values containing spaces may not reach msiexec exactly as typed. Session 0 mode passes them unchanged.
- `-Arguments` isn't passed on when the script relaunches itself as admin. Only `-FilePath` is.
- Mapped drive letters aren't visible to elevated apps or to SYSTEM. The app tells the user to use the UNC path instead.

## To Do

- [ ] `git init`, create the GitHub repo `MichaelEscamilla/RunAsSystem` and push. The update check and the `iex` URL both depend on it.
- [ ] Run the elevated tests above.
- [ ] Add screenshots to `Images/` and the README.
- [ ] Optionally add a short URL on michaeltheadmin.com (like `msiapp.michaeltheadmin.com`) and update the README.
- [ ] Publish the first release with the Release workflow. Optionally publish to the PowerShell Gallery too.

## Ideas for Later

- Detection-rule helper: show the Uninstall registry entries an install adds, with the product code and uninstall string.
- A live view of the MSI log while it's being written.
- An optional timeout and kill button.
- An option to copy the installer to a local cache first, like ccmcache or the IME content folder.
