# Right-Click Menu

[RunAsSystem](../README.md) > Right-Click Menu

Install a **Run as SYSTEM...** option for `.msi`, `.msp`, `.exe`, `.ps1`, `.cmd`, `.bat` and `.vbs` files from the **Right Click Menu** menu. The option shows the UAC shield and opens the app with the file already loaded.

- **Install**: copies the script and icon to `%LOCALAPPDATA%\RunAsSystem\ContextMenu` and registers the menu under `HKCU\Software\Classes\SystemFileAssociations`.
- **Uninstall**: removes the menu and its files. Your run history is kept.
- **Open Right Click Menu Folder**: opens the folder used by the menu.

The menu opens the app in PowerShell 7.4 or later when that's installed, and in Windows PowerShell 5.1 otherwise. That's decided when you install the menu, so if you install PowerShell 7 later, reinstall the menu to switch to it.

The menu's copy of the script is updated in place when you click **Update Available**. See [Updates](updates.md).
