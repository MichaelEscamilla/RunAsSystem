# Reference

[RunAsSystem](../README.md) > Reference

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+Enter` or `F5` | Run |
| `Ctrl+O` | Browse for an installer |
| `Ctrl+L` | Load the selected history entry |
| `Ctrl+R` | Reset: clear the file, options and result, as if the tool had just opened (same as the ✕ in the File box) |

## Command Line Parameters

```powershell
.\RunAsSystem.ps1 -FilePath "C:\Installers\Setup.msi" -Arguments "ALLUSERS=1"
```

| Parameter | Description |
| --- | --- |
| `-FilePath` | Installer to load when the app opens |
| `-Arguments` | Text to pre-fill in the ArgumentList box |

## Menus

| Menu | Item | Does |
| --- | --- | --- |
| File | Open History Folder | Opens `%LOCALAPPDATA%\RunAsSystem`, which holds the history, captured output, PsExec and the right-click menu files |
| File | Open Task Scheduler | Opens Task Scheduler, to look at a `RunAsSystem_*` task during a Session 0 or Current User run |
| Right Click Menu | Install, Uninstall, Open Right Click Menu Folder | See [Right-Click Menu](right-click-menu.md) |
| About | GitHub - RunAsSystem, michaeltheadmin.com | Open the project page or the website |
| About | Check for Updates | See [Updates](updates.md). The version you're running is shown under it |
| Update Available | | Appears when a newer release exists. See [Updates](updates.md) |

The arrow beside **Browse** is the [Tools menu](file-types.md#tools-menu).

## Drag and Drop While Elevated

Windows normally blocks drag and drop from Explorer into an elevated window, which is why GetMSIInformation asks you not to run it as administrator. RunAsSystem lets the older `WM_DROPFILES` message through the window's message filter, so drag and drop still works while elevated. You can also paste a path or use **Browse**.
