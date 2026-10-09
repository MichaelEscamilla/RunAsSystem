# RunAsSystem
Run MSI, EXE and script installers as **NT AUTHORITY\SYSTEM** to test an installation the same way ConfigMgr and Intune run it, without downloading PsExec or remembering its switches.<br>

Select or drag and drop an installer, set the arguments and click **Run as SYSTEM**. The exit code and what it means are shown when the installer finishes.

## Quick Access
Run the script directly from GitHub:

### Invoke-Expression
```powershell
iex (irm runassystem.michaeltheadmin.com)
```

The app needs administrator rights. If it isn't started elevated, it relaunches itself and shows a UAC prompt.

## Run Modes
### Session 0 (default)
The installer runs as SYSTEM in **session 0**, which has no desktop. This is how the ConfigMgr client and the Intune Management Extension run installers, so it's the most accurate test. Problems this mode catches:
- Installers that stop at a prompt or dialog nobody can see. In ConfigMgr and Intune these hang until they time out.
- Installers that depend on the logged-on user's profile, environment variables or mapped drives.

No PsExec is needed. A one-time Scheduled Task, similar to the approach used by the [Patch My PC Connectivity tool](https://github.com/PatchMyPCTeam/CustomerTroubleshooting/tree/Release/PowerShell/Connectivity), runs the installer directly:
- The task is registered in the root of the Task Scheduler Library as `RunAsSystem_<timestamp>`.
- It runs as `S-1-5-18` with highest privileges at normal priority. Scheduled tasks default to below-normal priority, which would make installs run slower than they do in ConfigMgr or Intune.
- It has no active trigger, so it only runs when the tool starts it. It has no time limit, and its working directory is the installer's own folder.
- The installer's exit code becomes the task's *Last Run Result*, which is how the tool reads it.
- The task is deleted as soon as the run finishes. If the app is closed mid-run, the task expires and deletes itself after 24 hours, and the next launch of the app removes it anyway.

### Interactive (PsExec)
The installer runs as SYSTEM **on your desktop**, so any installer UI is visible. This is useful for working out why a silent install hangs.

The tool looks for `PsExec64.exe` (or `PsExec.exe`) in the installer's folder first, then on the `PATH`. If it isn't found, the tool offers to download it from [live.sysinternals.com](https://live.sysinternals.com) into the installer's folder.

## Supported File Types
| Type | Runs as |
| --- | --- |
| `.msi` | `msiexec.exe /i` (or `/x`, `/fvomus`) `"file.msi"` + UI level, `/l*v` log and properties |
| `.msp` | `msiexec.exe /p "file.msp"` + the same options |
| `.exe` | The file itself, with your arguments |
| `.ps1` | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "file.ps1"` + arguments |
| `.cmd` / `.bat` | `cmd.exe /c ""file.cmd" arguments"` |
| `.vbs` | `cscript.exe //NoLogo "file.vbs"` + arguments |

The installer's own folder is always used as the working directory, the same as ConfigMgr and Intune.

## MSI Options
- **Action**: Install (`/i`), Uninstall (`/x`) or Repair (`/fvomus`).
- **UI**: Silent (`/qn`), Basic (`/qb`), Basic with no cancel (`/qb!`), Passive (`/passive`) or Full UI.
- **Log**: a verbose log (`/l*v`) is on by default. It's written next to the installer with `.log` added to the installer's file name (for example `Setup.msi` → `Setup.msi.log`). You can change the path.
- **ArgumentList**: anything else to pass to msiexec, such as `ALLUSERS=1 TRANSFORMS="app.mst"` or `/norestart`.

The **Command Line** box shows exactly what will run, and you can copy it with the copy button.

## Stopping a Run
While a run is in progress, a **Stop** button appears next to Run. It works the same way for every file type and in both Session 0 and PsExec modes. It ends the running process and anything it started, and records the run as **Stopped** in history. Stopping a process partway through can leave the software partly installed.

**MSI installs can't be stopped this way**, and neither can an MSI started by an EXE. The install runs in the Windows Installer service, not in the `msiexec.exe` process the tool starts. Windows Installer finishes the install in the background and keeps writing the log, and RunAsSystem just stops waiting. Starting another MSI before it finishes returns `1618`. Uninstall afterwards if you need to undo it.

## Exit Codes
When the run finishes, the exit code is shown in colour:
- **Green**: success (`0`, `1707`).
- **Orange**: success with a restart required or started (`3010`, `1641`).
- **Red**: failure.

Common Windows Installer codes (`1603`, `1618`, `1619`, `1638`, and others) have plain-English descriptions. Any other code falls back to the description Windows has for that number. The hex value is shown under the code (for example `0x80070002`), which is handy for EXE installers that document their codes in hex.

## History
Every run is saved to `%LOCALAPPDATA%\RunAsSystem\History.json`. It keeps the last 50 runs, including runs launched with `iex`.
- Each entry shows the file, exit code, time, run mode and arguments.
- **Load** (or double-click a run, or the load icon that appears when you hover over a run) puts the file, options, arguments and run mode back into the form, ready to run again.
- **Copy** (or the copy icon on hover) copies the run's command line.
- **Clear** empties the history.

Arguments can contain passwords or license keys, so the arguments and command line are encrypted with Windows DPAPI. Only your Windows account on that device can read them. If you copy `History.json` to another device, the runs still appear, but their arguments can't be loaded. Those entries show a warning icon.

## Keyboard Shortcuts
| Shortcut | Action |
| --- | --- |
| `Ctrl+Enter` or `F5` | Run as SYSTEM |
| `Ctrl+O` | Browse for an installer |
| `Ctrl+L` | Load the selected history entry |

## Drag and Drop While Elevated
Windows normally blocks drag and drop from Explorer into an elevated window, which is why GetMSIInformation asks you not to run it as administrator. RunAsSystem lets the older `WM_DROPFILES` message through the window's message filter, so drag and drop still works while elevated. You can also paste a path or use **Browse**.

## Right-Click Context Menu Option
Install a **Run as SYSTEM...** option for `.msi`, `.msp`, `.exe`, `.ps1`, `.cmd`, `.bat` and `.vbs` files from the **Right Click Menu** menu. The option shows the UAC shield and opens the app with the file already loaded.

- **Install**: copies the script and icon to `%LOCALAPPDATA%\RunAsSystem\ContextMenu` and registers the menu under `HKCU\Software\Classes\SystemFileAssociations`.
- **Uninstall**: removes the menu and its files. Your run history is kept.
- **Open Right Click Menu Folder**: opens the folder used by the menu.

## Command Line Parameters
```powershell
.\RunAsSystem.ps1 -FilePath "C:\Installers\Setup.msi" -Arguments "ALLUSERS=1"
```
| Parameter | Description |
| --- | --- |
| `-FilePath` | Installer to load when the app opens |
| `-Arguments` | Text to pre-fill in the ArgumentList box |

## Things to Know About SYSTEM
- **Network paths**: SYSTEM connects to shares as the computer account (`DOMAIN\COMPUTER$`). The share needs to allow read access for it, and write access too if the MSI log is written there. The app warns you when the installer is on a network path.
- **Mapped drives**: drive letters you mapped in your normal session aren't available to elevated apps or to SYSTEM. Use the UNC path instead.
- **Session 0 has no UI**: if an installer waits for input in Session 0, it waits forever. Switch to **Interactive (PsExec)** to see what it's waiting for.

## Requirements
- Windows PowerShell 5.1 (it also runs in PowerShell 7, but doesn't need it)
- Administrator rights
- Internet access only for the update check and the optional PsExec download

## Credit
- SYSTEM execution through a one-time Scheduled Task, based on the [Patch My PC Connectivity tool](https://github.com/PatchMyPCTeam/CustomerTroubleshooting/tree/Release/PowerShell/Connectivity).
- [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec) by Sysinternals, for Interactive mode.
