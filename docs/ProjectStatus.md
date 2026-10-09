# Project Status

Where the project stands, the decisions behind it, and what's left to do. Update this file when one of these changes.

_Last updated: 2026-10-09 (history arguments encrypted with DPAPI, lab testing of Session 0 and PsExec)_

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
| MSI options | An action choice (Install `/i`, Uninstall `/x`, Repair `/fvomus`), a UI level, and `/l*v` | Requested |
| `/norestart` checkbox | **Removed** (2026-10-09) | The owner doesn't use it. Type `/norestart` in ArgumentList when it's needed. Older history entries still contain a `NoRestart` field, which is now ignored |
| MSI log name | `<installer file name>.log` next to the installer, e.g. `Setup.msi.log` | The request said "match the installer but add .log", which was taken literally. If `Setup.log` is preferred, change `Get-DefaultLogPath` |
| Working directory | The installer's own folder | Matches ConfigMgr and Intune |
| Copy to a local cache first | **Not done** | The owner said it wasn't needed |
| Timeout or kill button | **Not done** | The owner said it wasn't needed |
| 32-bit (Intune-style) launch | **Not done** | The owner said it wasn't needed |
| Detection-rule help (new Uninstall registry entries) | **Not now** | Possible later |
| History | `%LOCALAPPDATA%\RunAsSystem\History.json`, last 50 runs, with Load, Copy and Clear | It saves locally even when the script is launched with `iex` |
| ArgumentList label | The arguments box is labelled **ArgumentList** for every file type. It used to switch between "Properties" and "Arguments". Internal names (`txt_Arguments`, `-Arguments`, the history `Arguments` field) are unchanged | Owner's preference. Leaving the internal names alone keeps old history files and `-Arguments` callers working |
| Changing the file | If the new file is the same type, all options are kept. If the type is different, everything except the path goes back to the defaults: Install, Silent, log on, ArgumentList empty, Session 0. Only known types are compared, so a half-typed path doesn't clear anything | Settings for one type rarely suit another, for example MSI properties passed to an EXE |
| Remembering choices between launches | **Not done** | History already restores a whole run, and remembered choices would conflict with resetting to the defaults when the file type changes |
| Main form layout | The ArgumentList box wraps and grows from one line up to about three (76px), then scrolls. Enter still doesn't add a line break. The result panel is a fixed 118px, and the command line takes whatever height is left (scrolling if needed). The copy button stays 56px tall | The command line is the part that changes length, so it gets the leftover space. The result panel always holds the same content |
| Exit code display | The decimal code is shown large, with its hex value always shown in small text underneath. The console log includes both | EXE installers often document their codes in hex, and HRESULTs are easier to look up that way |
| Keyboard shortcuts | `Ctrl+Enter` and `F5` run, `Ctrl+O` browses, `Ctrl+L` loads the selected history entry. They're handled in `PreviewKeyDown` on the window and only act when the matching button is enabled. The button tooltips list the shortcuts | Requested. Checking whether the button is enabled stops a shortcut from starting a second run or loading history during a run |
| History entries | Each entry shows the file name and exit code, then the time, MSI action and mode, then the arguments on a third line (Consolas, cut off when too long). Load and Copy icon buttons appear beside the exit code only while the mouse is over the entry | Runs of the same installer with different arguments can be told apart, and loading a run takes one click. There's deliberately no "Run Again" button: you should load a run and review it before running it |
| History encryption | `Arguments` and `CommandLine` are saved encrypted with DPAPI (CurrentUser) as `ArgumentsProtected` and `CommandLineProtected`. Older plain-text files are encrypted the first time they're read. An entry that can't be decrypted (another account or device, or a password reset) is kept, and its arguments are left blank when it's loaded. The entry shows a red warning icon (the tooltip explains it), Copy is disabled, and loading it shows a red status bar message | Arguments can contain passwords and license keys, and they have to be saved so runs can be repeated quickly |
| Masking secrets on screen or in the console | **Not done** | The owner said it wasn't needed: typing a secret into the tool and sharing your screen are risks the user already understands. Copy uses the real command line |
| Drag and drop while elevated | Uses `WM_DROPFILES` with a message filter, plus Browse, paste and the right-click menu | The app has to run elevated, which normally blocks drag and drop from Explorer |
| Parameters | `-FilePath` and `-Arguments` | Needed by the right-click menu and handy for scripting |
| Name | RunAsSystem | The repo folder already used this name |

## Verified

Tested by the owner on 2026-10-09, elevated, in their lab on the devices the tool is meant for:

- Session 0 and PsExec modes with MSI, EXE and PS1 files. Arguments are passed through correctly.
- The app also works in PowerShell 7, although 5.1 is still the target.

Tested in Windows PowerShell 5.1 while building the tool (not elevated):

- The script parses in 5.1 and contains only ASCII characters.
- The XAML loads and the window renders (checked with an offscreen screenshot).
- The command line is built correctly for all seven file types and for PsExec mode.
- The MSI options panel shows and hides as expected, and the default log path is filled in.
- Exit codes get the right meaning and colour category.
- History saves, reloads, loads back into the form and clears.
- History encryption: values round-trip, a plain-text file is migrated, an entry that can't be decrypted keeps its encrypted value, and an empty history saves as `[]`.
- The elevated drag-and-drop hook compiles and attaches.

## Not Yet Tested (Needs an Elevated Session)

- [x] Session 0 runs with MSI, EXE and PS1 files.
- [ ] CMD/BAT and VBS files. A `test.cmd` containing `exit /b 3010` should show **3010** in orange.
- [ ] The `RunAsSystem_*` task is deleted after the run, and leftover tasks are cleaned up when the app starts.
- [ ] Closing the app during a run: the warning appears, and the task cleans up later.
- [ ] A real MSI install, uninstall and repair, with the log written next to the installer.
- [x] PsExec mode with MSI, EXE and PS1 files.
- [ ] The PsExec download prompt.
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

- [x] `git init`, create the GitHub repo `MichaelEscamilla/RunAsSystem` and push.
- [x] Test the history encryption in the app. The owner confirmed it works, and that a copied `History.json` doesn't decrypt on another device.
- [x] UI improvements:
  - an arguments line and hover Load/Copy buttons on history entries
  - the ArgumentList label, and resetting options when the file type changes
  - a wrapping ArgumentList box
  - a fixed-height result panel, with the command line taking the leftover height
  - keyboard shortcuts
  - the hex exit code
- [ ] Test the keyboard shortcuts in the app (only F5 could be tested offscreen).
- [ ] Run the elevated tests above.
- [ ] Add screenshots to `Images/` and the README.
- [ ] Optionally add a short URL on michaeltheadmin.com (like `msiapp.michaeltheadmin.com`) and update the README.
- [ ] Publish the first release with the Release workflow. Optionally publish to the PowerShell Gallery too.

## Future Improvements

- A resizable window (currently 1100x760 with resizing turned off) that remembers its size and position.

- A filter box above the history list, to find a run by file name or argument.
- Pinned history entries that the 50-entry limit doesn't push out.

- A **"Don't save this run to history"** checkbox next to Run, plus a setting to turn history off completely, for arguments you'd rather not store even encrypted.
- Detection-rule helper: show the Uninstall registry entries an install adds, with the product code and uninstall string.
- A live view of the MSI log while it's being written.
- An optional timeout and kill button.
- An option to copy the installer to a local cache first, like ccmcache or the IME content folder.
