# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

RunAsSystem is a **single-file PowerShell + WPF app** (`RunAsSystem.ps1`) for running MSI, MSP, EXE, PS1, CMD/BAT and VBS installers as `NT AUTHORITY\SYSTEM`. Admins use it to test installs the way ConfigMgr and Intune run them. It belongs to a family of tools that share one look and structure:

- [GetMSIInformation](https://github.com/MichaelEscamilla/GetMSIInformation) (the style reference)
- [CodeSigningTool](https://github.com/MichaelEscamilla/CodeSigningTool)

Keep changes consistent with those repos.

**Read [docs/ProjectStatus.md](docs/ProjectStatus.md) first.** It holds the decisions already made, what has and hasn't been tested, the known limitations and the to-do list. Update it when you finish work.

## Hard Constraints

- **Windows PowerShell 5.1 compatible.** The tool is used on devices that only have 5.1, so don't use `??`, `?:`, `?.`, `-Parallel`, `&&`/`||`, `Join-String`, `ConvertFrom-Json -AsHashtable` or other 7-only syntax. Don't add a "relaunch in pwsh" step.
- **ASCII only in `RunAsSystem.ps1`.** Windows PowerShell 5.1 reads a `.ps1` without a BOM as ANSI, so any non-ASCII character gets mangled. In XAML use entities (`&#xE8C8;`). In PowerShell strings use `[char]0x....`. Check with: `[regex]::Matches((Get-Content RunAsSystem.ps1 -Raw), '[^\x00-\x7F]').Count` (it must be 0).
- **Single file.** No modules, no extra script files and no external dependencies. The script must keep working when run with `iex (irm <raw url>)`, where `$PSCommandPath` is empty. Every code path that uses the script's own path needs a fallback that downloads it from `$Script:ScriptUrl`.
- **It must run elevated.** The script relaunches itself with `-Verb RunAs` when it isn't elevated. It passes `-FilePath` through but not `-Arguments`.

## Structure of `RunAsSystem.ps1`

Sections appear in this order. Keep the banner comments and `#region` markers.

1. `<#PSScriptInfo#>`: `.VERSION` and `.RELEASENOTES`. The release workflow reads both.
2. Comment-based help and `param()` (`-FilePath`, `-Arguments`).
3. **Variables**: `$Script:`-scoped settings, including `$Script:ScriptVersion` and the base64 window icon.
4. **Functions** (`#region Functions`), grouped by concern:
   - form state and command building
   - PsExec
   - exit codes
   - Scheduled Task (Session 0)
   - running
   - history
   - elevated drag and drop
   - update check
   - right-click menu
5. **Main Script**: the elevation check, then the XAML here-string (`@'...'@`, a literal string so `$` in the XAML is never expanded). Every `Name="..."` element becomes a `$Script:` variable of the same name.
6. **Event Handlers** (`#region Event Handlers`), then `ShowDialog()`.

## Conventions

- Control name prefixes: `txt_`, `btn_`, `cmb_`, `chk_`, `rad_`, `lbl_`, `txtblk_`, `lsbox_`, `panel_`, `MenuItem_`.
- Use only the colour tokens in `Window.Resources`: `Bg`, `Surface`, `Surface2`, `Border`, `BorderMuted`, `Text`, `TextMuted`, `Accent`, `AccentHover`, `AccentText`, `Danger`, `Success`. In code, get brushes with `$formRunAsSystem.FindResource('Name')` and never hard-code colours.
- Log what the app does to the console with `Write-Host "Action: [$value]"`, matching the sibling tools.
- Comment the *why*, not the *what*.
- `ConvertFrom-Json` in 5.1 returns a JSON array as a single object, so unroll it with `| ForEach-Object { $_ }`.
- Use `ConvertTo-Json -InputObject @($list)` so that a one-item list is still saved as an array.

## How SYSTEM Execution Works

- **Session 0 mode**: `Register-SystemTask` uses the `Schedule.Service` COM object, not the ScheduledTasks module. The task's action is the installer itself (msiexec.exe, the exe, powershell.exe, cmd.exe or cscript.exe), so the installer's exit code becomes `LastTaskResult`. Don't add a wrapper script.
  - Task settings: principal `S-1-5-18`, `LogonType` 5, `RunLevel` 1, `Priority` 4, `ExecutionTimeLimit` `PT0S`.
  - It has a disabled trigger that expires after 24 hours, plus `DeleteExpiredTaskAfter` `PT0S`, so a task left behind by a crash deletes itself.
  - Every task description contains `$Script:TaskMarker`. Only ever delete tasks that have the marker.
- `Watch-SystemRun` runs on a 500 ms `DispatcherTimer`. Task states 2 (queued) and 4 (running) mean the installer is still running. `LastTaskResult` 267009 or 267011 means the task hasn't finished or hasn't started yet.
- **PsExec mode** runs `PsExec64.exe -accepteula -nobanner -s -i <current session> -w "<dir>" "<exe>" <args>` with `Start-Process -PassThru`.
- **Elevated drag and drop**: `Enable-ElevatedDragDrop` compiles a small C# class (`RunAsSystem.ElevatedDropTarget`) that:
  - calls `RevokeDragDrop` on the window
  - lets `WM_DROPFILES`, `WM_COPYDATA` and `0x0049` through `ChangeWindowMessageFilterEx`
  - calls `DragAcceptFiles`
  - handles `WM_DROPFILES` in an `HwndSource` hook

  Don't replace it with WPF `AllowDrop` events: those use OLE drag and drop, which Windows (UIPI) blocks into an elevated window.

## Releasing

- To release, bump **both** `.VERSION` in `PSScriptInfo` and `$Script:ScriptVersion`. The format is `yyyy.M.d.n`, for example `2026.10.6.0`.
- Add a `.RELEASENOTES` line in the format `<version>   - <note>`, with continuation lines indented.
- `.github/workflows/release.yml` (manual dispatch) builds the GitHub release from those notes. The in-app update check compares against the latest release tag.
- `.github/workflows/publish-module.yaml` publishes the script to the PowerShell Gallery.

## Testing

There's no automated test suite. Before you finish:

1. Check that the script parses in **Windows PowerShell 5.1**:
   ```powershell
   powershell.exe -NoProfile -Command "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('RunAsSystem.ps1',[ref]$null,[ref]$e); $e"
   ```

2. Run the ASCII check above.
3. Run the app elevated in 5.1 and test the change by hand:
   - For Session 0, a `test.cmd` that contains `exit /b 3010` is a quick way to check exit code handling.
   - Confirm in Task Scheduler that the `RunAsSystem_*` task is removed afterwards.
