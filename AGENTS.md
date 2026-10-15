# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

RunAsSystem is a **single-file PowerShell + WPF app** (`RunAsSystem.ps1`) for running MSI, MSP, EXE, PS1, CMD/BAT and VBS installers as `NT AUTHORITY\SYSTEM`. Admins use it to test installs the way ConfigMgr and Intune run them. It belongs to a family of tools that share one look and structure:

- [GetMSIInformation](https://github.com/MichaelEscamilla/GetMSIInformation) (the style reference)
- [CodeSigningTool](https://github.com/MichaelEscamilla/CodeSigningTool)

Keep changes consistent with those repos.

**Read [docs/ProjectStatus.md](docs/ProjectStatus.md) first.** It holds the decisions already made, what has and hasn't been tested, the known limitations and the to-do list. Update it when you finish work.

## Hard Constraints

- **Works in both Windows PowerShell 5.1 and PowerShell 7.** 5.1 is the baseline: the tool is used on devices that only have 5.1, so don't use `??`, `?:`, `?.`, `-Parallel`, `&&`/`||`, `Join-String`, `ConvertFrom-Json -AsHashtable` or other 7-only syntax. Everything must also work when it's started from pwsh. Watch for 5.1/7 differences: `Add-Type` compiles with a different compiler and needs WPF assemblies passed by `.Location`, `Invoke-WebRequest` behaves differently, and the default file encodings differ.
- **Relaunch in the PowerShell it was started in.** Use `$Script:CurrentPowerShellPath` (built from `$PSHOME`) to relaunch for elevation or after an update, so 5.1 stays 5.1 and pwsh stays pwsh. Don't add a step that switches to pwsh when it's installed (unlike GetMSIInformation). `.ps1` installers use `$Script:WindowsPowerShellPath` and `-File` by default, because that's what Intune and ConfigMgr use. The PS1 options can switch to 32-bit 5.1 (`$Script:WindowsPowerShell32Path`) or PowerShell 7 (`$Script:PwshPath`, machine-wide installs only), to `-Command` or `-EncodedCommand`, change `-ExecutionPolicy`, and add extra PowerShell parameters. The right-click menu is the one exception: `Install-RightClickMenu` registers pwsh 7.4+ when it's installed (like GetMSIInformation) and falls back to 5.1. The choice is made when the menu is installed, so reinstalling the menu picks up a newly installed pwsh.
- **ASCII only in `RunAsSystem.ps1`.** Windows PowerShell 5.1 reads a `.ps1` without a BOM as ANSI, so any non-ASCII character gets mangled. In XAML use entities (`&#xE8C8;`). In PowerShell strings use `[char]0x....`. Check with: `[regex]::Matches((Get-Content RunAsSystem.ps1 -Raw), '[^\x00-\x7F]').Count` (it must be 0).
- **Single file.** No modules, no extra script files and no external dependencies. The script must keep working when run with `iex (irm <raw url>)`, where `$PSCommandPath` is empty. Every code path that uses the script's own path needs a fallback that downloads it from `$Script:ScriptUrl`.
- **It must run elevated.** The script relaunches itself with `-Verb RunAs` when it isn't elevated. It passes `-FilePath` through but not `-Arguments`. The update relaunch (`Restart-Script`) also passes only `-FilePath`. It doesn't need `-Verb RunAs`, because the app is already elevated.

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
   - output capture
   - running
   - history
   - elevated drag and drop
   - update check
   - right-click menu
5. **Main Script**: the elevation check, then the XAML here-string (`@'...'@`, a literal string so `$` in the XAML is never expanded). Every `Name="..."` element becomes a `$Script:` variable of the same name.
6. **Event Handlers** (`#region Event Handlers`), then `ShowDialog()`.

## Conventions

- Control name prefixes: `txt_`, `btn_`, `cmb_`, `cmbitem_`, `chk_`, `rad_`, `lbl_`, `txtblk_`, `lsbox_`, `panel_`, `MenuItem_`.
- **Layers:** `Window` (the window background, a dark stone with a hint of the site's orange) sits behind the section cards. Cards are `Bg`, inputs and the History list are `Surface`, and buttons are `Surface2`, so neighbouring layers never share a shade. Each section is a `Border` with `Style="{StaticResource Card}"` and its header inside, using `CardHeader`. The palette comes from michaeltheadmin.com (the Blowfish theme's stone and orange scales).
- Use only the colour tokens in `Window.Resources`: `Window`, `Bg`, `Surface`, `Surface2`, `Border`, `BorderMuted`, `Text`, `TextMuted`, `Accent`, `AccentHover`, `AccentText`, `Danger`, `Success`. In code, get brushes with `$formRunAsSystem.FindResource('Name')` and never hard-code colours.
- Log what the app does to the console with `Write-Host "Action: [$value]"`, matching the sibling tools.
- Comment the *why*, not the *what*.
- `ConvertFrom-Json` in 5.1 returns a JSON array as a single object, so unroll it with `| ForEach-Object { $_ }`.
- Use `ConvertTo-Json -InputObject @($list)` so that a one-item list is still saved as an array.

## How SYSTEM Execution Works

- **Session 0 mode**: `Register-SystemTask` uses the `Schedule.Service` COM object, not the ScheduledTasks module. The task's action is the installer itself (msiexec.exe, the exe, powershell.exe, cmd.exe or cscript.exe), so the installer's exit code becomes `LastTaskResult`. Don't add a wrapper script.
  - **The one exception is output capture.** For Session 0 runs of anything except MSI and MSP (`Test-CaptureOutput`), the action is a Windows PowerShell `-EncodedCommand` launcher (`Get-OutputCaptureCommand`). It starts the installer with `System.Diagnostics.Process` (arguments passed through unchanged), copies stdout and stderr into `%LOCALAPPDATA%\RunAsSystem\Output\<task name>.txt`, and exits with the installer's exit code. Keep it inline and encoded: there's no script file, and the installer path stays out of the launcher's command line so Stop finds the installer. Don't use `Start-Process` in it, because it treats `[` `]` in paths as wildcards.
  - Task settings: principal `S-1-5-18`, `LogonType` 5, `RunLevel` 1, `Priority` 4, `ExecutionTimeLimit` `PT0S`.
  - **Current user mode** uses the same task with different principal parameters (`-UserId`, `-LogonType`, `-RunLevel`): the script account's SID, `LogonType` 3 (interactive token, so no password), and `RunLevel` 1 if the script is elevated, otherwise 0. Future user-context variations, such as the session user or forcing no elevation, should change only these parameters.
  - It has a disabled trigger that expires after 24 hours, plus `DeleteExpiredTaskAfter` `PT0S`, so a task left behind by a crash deletes itself.
  - Every task description contains `$Script:TaskMarker`. Only ever delete tasks that have the marker.
- `Watch-SystemRun` runs on a 500 ms `DispatcherTimer`. Task states 2 (queued) and 4 (running) mean the installer is still running. `LastTaskResult` 267009 or 267011 means the task hasn't finished or hasn't started yet.
- **Tools** (`Test-IsTool`: an EXE in System32, SysWOW64 or a PowerShell folder) run from `$Script:ToolWorkingDirectory`, and Stop only matches their processes that descend from the Task Scheduler service or `PSEXESVC.exe`, because their path isn't unique to a run.
- **PsExec mode** runs `PsExec64.exe -accepteula -nobanner -s -i <current session> -w "<dir>" "<exe>" <args>` with `Start-Process -PassThru`.
- **Elevated drag and drop**: `Enable-ElevatedDragDrop` compiles a small C# class (`RunAsSystem.ElevatedDropTarget`) that:
  - calls `RevokeDragDrop` on the window
  - lets `WM_DROPFILES`, `WM_COPYDATA` and `0x0049` through `ChangeWindowMessageFilterEx`
  - calls `DragAcceptFiles`
  - handles `WM_DROPFILES` in an `HwndSource` hook

  Don't replace it with WPF `AllowDrop` events: those use OLE drag and drop, which Windows (UIPI) blocks into an elevated window.

## How Updating Works

- **Check:** `$Script:TestForUpdate` reads the latest GitHub release and compares its tag with `$Script:ScriptVersion`.
  - At startup it runs in a runspace (`Start-BackgroundUpdateCheck`). The `Loaded` handler queues it with `Dispatcher.InvokeAsync` at `ApplicationIdle`, so the window draws first. This is the same as GetMSIInformation.
  - **Check for Updates** runs it straight away, without the runspace.
- **Launch channel:** `Get-UpdateChannel` works out how the script was launched, once, in `$Script:UpdateChannel`. The result is `Web` (empty `$PSCommandPath`), `RightClick` (running from `$Script:RightClickMenuFolderPath`), `PSGallery` or `LooseFile`.
  - Recognise a Gallery install by `InstalledScriptInfos\RunAsSystem_InstalledScriptInfo.xml` next to the script. **Don't call `Get-InstalledScript` at startup.** It loads PowerShellGet and freezes the UI for 4-6 seconds.
- **Update Available** click:
  - `RightClick` and `LooseFile`: `Update-ScriptFile` downloads `https://raw.githubusercontent.com/<repo>/<tag>/RunAsSystem.ps1` to `%TEMP%`, checks that it parses, then copies it over `$PSCommandPath`.
  - `PSGallery`: runs `Update-Script`.
  - Either way, `Restart-Script` then starts the new copy with `-FilePath` and closes the window.
  - Every failure, and the `Web` channel, falls back to `Open-ReleasePage`.
  - Updating is refused while `$Script:CurrentRun` is set.
- Release tags must have `RunAsSystem.ps1` at the repo root, because the download URL is built from the tag.

## Releasing

- To release, bump **both** `.VERSION` in `PSScriptInfo` and `$Script:ScriptVersion`. The format is `yyyy.M.d.n`, for example `2026.10.6.0`.
- Add a `.RELEASENOTES` line in the format `<version>   - <note>`, with continuation lines indented. Pad after the version so that every ` - ` lines up at the same column. The workflow turns each line into a bullet, so put one change on each line.
- Don't leave `$Script:ScriptVersion` lowered after testing the update. Check that both version fields match before releasing.
- `.github/workflows/release.yml` (manual dispatch) builds the GitHub release from those notes. The in-app update check compares against the latest release tag.
- `.github/workflows/publish-module.yaml` publishes the script to the PowerShell Gallery.

## Testing

There's no automated test suite. Before you finish:

1. Check that the script parses in **Windows PowerShell 5.1** and in **pwsh** (swap `powershell.exe` for `pwsh`):

   ```powershell
   powershell.exe -NoProfile -Command "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('RunAsSystem.ps1',[ref]$null,[ref]$e); $e"
   ```

2. Run the ASCII check above.
3. Run the app elevated in 5.1 and test the change by hand. If the change touches anything that behaves differently in 7 (`Add-Type`, web requests, JSON, file encoding or relaunching), test it in pwsh too.
   - For Session 0, a `test.cmd` that contains `exit /b 3010` is a quick way to check exit code handling.
   - Confirm in Task Scheduler that the `RunAsSystem_*` task is removed afterwards.
   - To test updating, copy the script to a temp folder and lower `$Script:ScriptVersion` in the copy. Don't do it in the repo file. Clicking **Update Available** overwrites that copy with the latest release.
