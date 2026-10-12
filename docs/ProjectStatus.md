# Project Status

Where the project stands, the decisions behind it, and what's left to do. Update this file when one of these changes.

_Last updated: 2026-10-10 (version 2026.10.10.0: Update Available installs the update, relaunches stay in the same PowerShell, and the update check waits until the window has opened. Also Open Log during a run, and the result clears when a different file is loaded)_

## Goal

Make it easy to run MSI and EXE installers (and scripts) as SYSTEM to test installs the way ConfigMgr and Intune run them, without downloading PsExec and running it from the right folder. Pick an installer, type the arguments, click Run.

## Decisions Made (and Why)

| Topic | Decision | Reason |
| --- | --- | --- |
| Look and structure | Match [GetMSIInformation](https://github.com/MichaelEscamilla/GetMSIInformation) and [CodeSigningTool](https://github.com/MichaelEscamilla/CodeSigningTool): one `.ps1` file with WPF, the same palette, update check, right-click menu and `iex (irm …)` launch | Keeps the tool family consistent |
| PowerShell version | Works in Windows PowerShell **5.1** (the baseline) and PowerShell 7, with no step that switches to pwsh when it's installed. The elevation and update relaunches use the PowerShell the script is already running in (`$Script:CurrentPowerShellPath`, from `$PSHOME`), so starting it from pwsh stays in pwsh (2026-10-10). `.ps1` installers always use 5.1. The right-click menu uses pwsh 7.4+ if it's installed when the menu is installed, otherwise 5.1 (2026-10-10, matching GetMSIInformation) | Testing often happens on devices that don't have PowerShell 7. GetMSIInformation prefers pwsh 7.4+ wherever it's installed. RunAsSystem only stays in the PowerShell it was given, so 5.1 users are never moved to pwsh and pwsh users are never dropped to 5.1 |
| How it runs as SYSTEM | A one-time Scheduled Task (Session 0) by default, based on the [Patch My PC Connectivity tool](https://github.com/PatchMyPCTeam/CustomerTroubleshooting/tree/Release/PowerShell/Connectivity) | Avoids PsExec, and Session 0 is how ConfigMgr and Intune really run installers |
| Interactive mode | Optional PsExec mode (`-s -i`) | Lets you see the installer's UI. If PsExec isn't found, the tool offers to download it from live.sysinternals.com **into the installer's folder** (the owner's choice) |
| File types | `.msi`, `.msp`, `.exe`, `.ps1`, `.cmd`, `.bat`, `.vbs` | MSI and EXE are the main use; scripts were requested too |
| MSI options | An action choice (Install `/i`, Uninstall `/x`, Repair `/fvomus`), a UI level, and `/l*v` | Requested |
| `/norestart` checkbox | **Removed** (2026-10-09) | The owner doesn't use it. Type `/norestart` in ArgumentList when it's needed. Older history entries still contain a `NoRestart` field, which is now ignored |
| MSI log name | `<installer file name>.<Action>.log` next to the installer: `Setup.msi.Install.log`, `.Uninstall.log`, `.Repair.log`, or `Update.msp.Patch.log` for an MSP (changed 2026-10-09, it was `Setup.msi.log`). Changing the action updates the name only if the box still holds the automatic name (`$Script:DefaultLogPath`). A typed path is kept, and a new file always gets a new default. History entries keep the log path they were run with | Owner's request, so the logs from install, uninstall and repair of one MSI don't overwrite each other |
| Working directory | The installer's own folder | Matches ConfigMgr and Intune |
| Copy to a local cache first | **Not done** | The owner said it wasn't needed |
| Current user mode | Added 2026-10-09 as a third run mode (`CurrentUser`). It runs as **the account running the script**, with the script's elevation (in practice elevated), on that user's desktop. It uses the same `Register-SystemTask` with principal parameters: the script account's SID, `LogonType` 3 (interactive token) and `RunLevel` 1 or 0. The option shows the account and its elevation, and the Run button reads "Run as Current User" | Owner's choice to start simple and test before deciding further. Using the scheduled task (instead of `Start-Process`) keeps the exit code, cleanup, Stop and history shared, so later variations only change the principal |
| Current user variations considered | **Not done yet**, to be decided after lab testing: (1) running as the user signed in to the window's session instead of the script account (`WTSQuerySessionInformation`), which handles an admin elevating with a different account; (2) forcing no elevation (`RunLevel` 0) to match Intune and ConfigMgr user context; (3) warning when that user has more than one session, because Task Scheduler picks the user, not the session, so UI could appear in the other session | Discussed 2026-10-09. Each one only changes the task principal or adds a check before the run |
| Stop button | Added 2026-10-09. A red **Stop** button (`btn_Stop`) appears next to Run during a run. It uses the same label and the same confirmation prompt for every file type, and the prompt explains the MSI behaviour. `Get-RunProcessId` finds the process by the installer path in its command line, started after the run began, skipping this app and the local PsExec client. `taskkill /T /F` then ends that process and its whole tree. After that it stops the scheduled task or the PsExec client, in case the search missed something. The run is recorded as **Stopped** (category `Stopped`, grey). Only the text underneath differs for MSI and MSP ("Stopped waiting - Windows Installer is still running the install..."). Pre-release builds wrote `Cancelled` and `StoppedWaiting`, and those still display as Stopped | Stopping the task only ends the process it launched directly, and killing PsExec only ends the local client, so bootstrapper and PSADT children kept running. One label and one prompt was the owner's preference: the action is the same whatever the file type. Stop is a separate button so that double-clicking Run can't stop anything. The Windows Installer service is never matched, because its command line doesn't contain the installer path |
| Really stopping an MSI | **Not done** (2026-10-09). Lab testing showed the install carried on after it was stopped. The `msiexec.exe /i` client exits, but the Windows Installer service (`msiexec /V`) keeps running the install. The options considered were: stopping the service, rejected because it affects every MSI install on the device and can leave a half-applied install; and a clean cancel through the MSI API's UI callback (rolls back, exit `1602`), rejected because it needs a SYSTEM-side host process instead of running `msiexec.exe` directly | The owner is fine with a warning: stopping an MSI partway through is part of testing, and you can uninstall afterwards |
| Timeout | **Not done** | The owner said it wasn't needed. Use Stop instead |
| 32-bit (Intune-style) launch | **Not done** | The owner said it wasn't needed |
| Detection-rule help (new Uninstall registry entries) | **Not now** | Possible later |
| History | `%LOCALAPPDATA%\RunAsSystem\History.json`, last 50 runs, with Load, Copy and Clear | It saves locally even when the script is launched with `iex` |
| ArgumentList label | The arguments box is labelled **ArgumentList** for every file type. It used to switch between "Properties" and "Arguments". Internal names (`txt_Arguments`, `-Arguments`, the history `Arguments` field) are unchanged | Owner's preference. Leaving the internal names alone keeps old history files and `-Arguments` callers working |
| Changing the file | If the new file is the same type, all options are kept. If the type is different, everything except the path goes back to the defaults: Install, Silent, log on, ArgumentList empty, Session 0. Only known types are compared, so a half-typed path doesn't clear anything | Settings for one type rarely suit another, for example MSI properties passed to an EXE |
| Remembering choices between launches | **Not done** | History already restores a whole run, and remembered choices would conflict with resetting to the defaults when the file type changes |
| Section cards and colours | Each section (Installer and options, Run As, Command Line, Result, History) is a `Card` border with its header inside (`CardHeader`), 10px/6px padding and a `BorderMuted` outline. File and options share one card with a thin divider, which leaves the command line about 97px; separate cards left only about 68px. The window background is a new token, `Window` (`#231915`): the darkest stone mixed with a little of the site's darkest orange. Cards are `Bg`, inputs `Surface`, buttons `Surface2` | The owner wanted clearer sections. Card fills of `Surface` with inputs in `Bg` made the inputs look like holes to the window, and an orange outline was too loud. Giving each layer its own shade fixed it. The palette matches michaeltheadmin.com (Blowfish stone and orange). **`Window` isn't in GetMSIInformation or CodeSigningTool yet**, so add it there to keep the family consistent |
| Main form layout | The ArgumentList box wraps and grows from one line up to about three (76px), then scrolls. Enter still doesn't add a line break. The result panel is a fixed 118px, and the command line takes whatever height is left (scrolling if needed). The copy button stretches to the same height as the command line box | The command line is the part that changes length, so it gets the leftover space. The result panel always holds the same content |
| Open Log during a run | Open Log and Open Folder are pointed at the new run when it starts, so they never open the previous run's files. Open Log is disabled until the log file exists, then enabled while the install is still running (`Watch-SystemRun` checks on its 500 ms tick, one `Test-Path` per tick until the file appears). It opens with the default app for `.log` files. The logging switch stays `/l*v` | The owner wanted to watch an MSI install while it runs. A specific viewer such as CMTrace isn't installed in a known place, and someone using Notepad can close and reopen the file. Before this, Open Log kept pointing at the previous run's log during a new run. A log panel inside the app was considered and turned down |
| Result when the file changes | The result, Open Log and Open Folder belong to the file that was run (`$Script:ResultFilePath`). Loading a different file clears them (`Clear-RunResult`, also used by Reset). Loading the same file again keeps them | The owner noticed that a stopped run's result stayed on screen after a new file was loaded, which made it look like the result of the new file |
| Exit code display | The decimal code is shown large, with its hex value always shown in small text underneath. The console log includes both | EXE installers often document their codes in hex, and HRESULTs are easier to look up that way |
| Copying the exit code | Click the decimal code or the hex value to copy just that value (`Copy-ExitCode`). The hand cursor and "Click to copy" tooltip only appear when a real code is shown, not for `--`, `...`, `Stopped` or `Error`. Both text blocks are left-aligned so only the text itself is clickable | The owner wanted the code easy to look up. No extra button, so the result panel keeps its fixed height |
| Status bar messages | `Set-StatusBar` shows a message, then one reused `DispatcherTimer` (`$Script:StatusTimer`) puts back `$Script:DefaultStatusBarText` after 4 seconds. A new message restarts the countdown. The restore state is kept on the timer's `Tag`. `-Persist` keeps a message until the next one or Reset; only the "Loaded run WITHOUT its arguments" warning uses it | Matches CodeSigningTool's `Set-StatusMessage`. The owner wanted resetting as the default, with a way to keep messages that ask you to do something |
| Reset | A ✕ icon inside the right end of the File box (`btn_Reset`), or `Ctrl+R`, runs `Reset-Form`. It puts the window back to how it opens: no file, default options, an empty log path, the result showing "Not run yet", Open Log and Open Folder disabled, no history selection, and the default status bar text. History is kept. It's disabled during a run | The owner wanted a clean start without reopening the tool. Putting it inside the File box avoids adding a row under Browse |
| Keyboard shortcuts | `Ctrl+Enter` and `F5` run, `Ctrl+O` browses, `Ctrl+L` loads the selected history entry, `Ctrl+R` resets. They're handled in `PreviewKeyDown` on the window and only act when the matching button is enabled. The button tooltips list the shortcuts | Requested. Checking whether the button is enabled stops a shortcut from starting a second run or loading history during a run |
| Updating | Ported from GetMSIInformation `main` (2026-10-10). Clicking **Update Available** acts on how the script was launched (`Get-UpdateChannel`, worked out once at startup). The startup check is queued with `Dispatcher.InvokeAsync` at `ApplicationIdle`, so the window draws first (the same as GetMSIInformation). A PowerShell Gallery install is recognised by the `InstalledScriptInfosRunAsSystem_InstalledScriptInfo.xml` file next to the script, not by `Get-InstalledScript`, which held up the window by 4-6 s while it loaded PowerShellGet. **Web** (`iex`): opens the release page. **RightClick** or **LooseFile**: downloads `RunAsSystem.ps1` from the release tag to `%TEMP%`, checks that it parses, copies it over the running script, then relaunches it with the loaded file. **PSGallery**: runs `Update-Script`, then relaunches. When an update can't be applied (offline, locked, read-only or a parse error), it opens the release page instead. Updating is blocked during a run. The relaunch has no `-Verb RunAs` (the app is already elevated, so there's no UAC prompt) and carries `-FilePath` but not `-Arguments`. The right-click registry entry isn't rewritten | Matches GetMSIInformation. The parse check stops a truncated download or an error page from replacing a working script. The registry entry only points at the script path, so it doesn't change between versions |
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
- [x] The `RunAsSystem_*` task is deleted after the run, and leftover tasks are cleaned up when the app starts (the owner confirmed it on 2026-10-10).
- [ ] Closing the app during a run: the warning appears, and the task cleans up later.
- [ ] A real MSI install, uninstall and repair, with the log written next to the installer.
- [x] Open Log during a run: it's disabled at the start, then enabled when the MSI log appears (the status bar says so), and it opens the current run's log, not the previous one. The owner confirmed it works on 2026-10-10.
- [x] Open Log after Stop on an MSI, while Windows Installer is still writing the log (the owner confirmed it on 2026-10-10).
- [x] Loading a different file after a run (by Browse, drag and drop, typing or a history entry) clears the result to "Not run yet" and disables Open Log and Open Folder. Loading the same file again keeps the result (the owner confirmed it on 2026-10-10).
- [x] PsExec mode with MSI, EXE and PS1 files.
- [ ] The PsExec download prompt.
- [x] Drag and drop from Explorer into the elevated window (the owner confirmed it on 2026-10-10).
- [ ] Right-click menu install and uninstall: the menu shows the UAC shield and opens the app with the file loaded. Still to check: the registry command points at powershell.exe on a device without pwsh 7.4+.
- [x] Right-click menu uses pwsh 7.4+ when it's installed. The owner confirmed it works (2026-10-10).
- [ ] The relaunch-as-admin step, both when the script is run from a file and when it's launched with `iex`.
- [x] Current user mode elevated. The owner tested it in the lab on 2026-10-09 and it works. It was also tested non-elevated while building: Medium integrity, 3010 returned, task removed.
- [ ] Current user mode when RunAsSystem is elevated with a different admin account than the one signed in. Does the interactive task start, and as which account?
- [ ] The whole app in pwsh 7, elevated. Checked outside the app on 2026-10-10 in 7.6: the script parses, the drag-and-drop class compiles, the XAML loads and `Schedule.Service` connects. Still to test by hand: a run in each mode, history, drag and drop, and the relaunch for elevation started from pwsh.
- [x] The update check finds a newer release and shows the menu item (the owner confirmed it on 2026-10-10).
- [ ] Update in place (2026.10.10.0). The owner confirmed the update works (2026-10-10), but not yet in every launch channel. Tested outside the app in 5.1: the download from the release tag, the parse check and the replace work, and a 404 or a locked file returns `$false`. Still to test by hand: the LooseFile and RightClick channels end to end (the window reopens elevated with the file loaded), the PSGallery channel, and the warning when updating during a run. The first time the in-place update can be tried is going from 2026.10.10.0 to a newer release, because older versions only open the release page.

## Known Limitations

- There's no timeout. An installer that waits for input in Session 0 runs until you click **Stop**.
- Current user mode runs with RunAsSystem's elevation (normally elevated), unlike Intune and ConfigMgr user context, which isn't elevated. It also runs as the account running the script, which may not be the user signed in to the desktop.
- Stop finds processes by the installer path in their command line. A child process that doesn't have the path in its command line is still stopped, because it's in the tree. A process the installer hands work to outside its tree is not stopped, for example a service it starts or an MSI it passes to the Windows Installer service.
- **An MSI can't be stopped.** Stop leaves Windows Installer finishing the install in the background, confirmed in the lab. The same applies to an EXE that runs an MSI internally. Starting another MSI before it finishes returns **1618** (another installation is in progress).
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
- [x] Test the keyboard shortcuts in the app. The owner confirmed they all work.
- [x] Test Stop in the lab, in both Session 0 and PsExec modes, with (the owner confirmed all of them on 2026-10-10):
  - an EXE bootstrapper that starts a child process
  - a PSADT script
  - an MSI, which should show the "Stopped waiting" text in the result (it was already confirmed that the install itself carries on)
  - a run that finishes while the confirmation prompt is open
- [x] Test click-to-copy on the exit code in the app: decimal and hex each copy on their own, and placeholders (`--`, `Stopped`, `Error`) show no hand cursor and copy nothing (the owner confirmed it on 2026-10-10).
- [x] Test the status bar timer in the app: a message clears after 4 seconds, a second message before then restarts the countdown, and the `-Persist` "WITHOUT its arguments" warning stays (the owner confirmed it on 2026-10-10).
- [ ] Run the elevated tests above.
- [x] Add screenshots to `Images/` and the README (2026-10-12: `Screenshot-Empty.png`, `Screenshot-MSI.png`, `Screenshot-PS1.png`, captured at 100% scale with `PrintWindow` so the rounded corners stay transparent). Retake them when the UI changes.
- [ ] Optionally add a short URL on michaeltheadmin.com (like `msiapp.michaeltheadmin.com`) and update the README.
- [x] Publish the first release with the Release workflow (2026.10.9.0, then 2026.10.9.1).
- [ ] Optionally publish to the PowerShell Gallery. The PSGallery update channel needs it.
- [ ] Release 2026.10.10.0. Versions from 2026.10.10.0 on install updates in place. Anyone on 2026.10.9.x still gets the release page for this one update.
- [ ] Consider bringing two things back to GetMSIInformation: recognising a Gallery install by its `InstalledScriptInfos` file instead of `Get-InstalledScript`, which still freezes its UI for a few seconds after the window opens, and the parse check before the downloaded script replaces the old one.
- [ ] Fill in `.COPYRIGHT`, `.LICENSEURI` and `.ICONURI` in GetMSIInformation's script info too, as RunAsSystem now does (2026-10-10). `.TAGS` is left empty in both on purpose. RunAsSystem's icon is `Images/RunAsSystem.png`, exported from `$Script:WindowIconBase64`, and the `.ICONURI` link only works once it's on `main`.
- [ ] Consider porting GetMSIInformation's `ContentRendered` handler (`Activate()` plus toggling `Topmost`), so the window comes to the front after the UAC prompt or an update relaunch.

## Future Improvements

- A resizable window (currently 1100x760 with resizing turned off) that remembers its size and position.

- A filter box above the history list, to find a run by file name or argument.
- Pinned history entries that the 50-entry limit doesn't push out.

- A **"Don't save this run to history"** checkbox next to Run, plus a setting to turn history off completely, for arguments you'd rather not store even encrypted.
- Detection-rule helper: show the Uninstall registry entries an install adds, with the product code and uninstall string.
- Open Log for EXE installers that write their own log: read a log path out of the arguments (for example `/log "x"`, or `/v"/l*v x"` for an EXE that wraps an MSI) and use the same Open Log flow. Pulling a path out of free-form arguments is guesswork, so it needs care.
- An option to copy the installer to a local cache first, like ccmcache or the IME content folder.
