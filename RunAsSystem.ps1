<#PSScriptInfo

.VERSION 2026.10.6.0

.GUID 8f2d6c1e-4b7a-4e3f-9a5d-2c8b1e7f6a40

.AUTHOR Michael Escamilla

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI https://github.com/MichaelEscamilla/RunAsSystem

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
2026.10.6.0   - Initial release

.PRIVATEDATA

#>

<#
.SYNOPSIS
A graphical tool for running MSI, EXE and script installers as NT AUTHORITY\SYSTEM.

.DESCRIPTION
Select (or drag and drop) an installer, set the arguments, and run it as SYSTEM - the same way ConfigMgr and Intune do.

Two run modes are available:
  - Session 0 (default): A one-time Scheduled Task runs the installer as SYSTEM in session 0 with no desktop,
    exactly like the ConfigMgr client and the Intune Management Extension. No PsExec required.
  - Interactive (PsExec): Runs the installer as SYSTEM on your desktop, so any installer UI is visible.
    PsExec is downloaded from live.sysinternals.com into the installer's folder if it isn't already available.

The exit code is reported when the installer finishes, and every run is saved to a history list so it can be re-run.

.PARAMETER FilePath
Optional path of the installer to load when the application opens.

.PARAMETER Arguments
Optional arguments to pre-fill in the Arguments box.

.NOTES
Requires administrator rights. The script relaunches itself elevated when needed.
Written for Windows PowerShell 5.1 so it can be used on devices where PowerShell 7 isn't installed.
#>

param (
  [Parameter(Mandatory = $false)]
  [string]$FilePath,
  [Parameter(Mandatory = $false)]
  [string]$Arguments
)

#############################################
################# Variables #################
#############################################
# Script Name
$Script:ScriptName = "RunAsSystem.ps1"
# Script Version
[System.Version]$Script:ScriptVersion = "2026.10.6.0"
# App Data folder (history and right-click menu files)
$Script:AppDataPath = "$env:LOCALAPPDATA\RunAsSystem"
$Script:HistoryPath = "$Script:AppDataPath\History.json"
$Script:HistoryMaxEntries = 50
# Right Click Menu
$Script:RightClickMenuName = "Run as SYSTEM"
$Script:RightClickMenuKeyName = "RunAsSystem"
$Script:RightClickMenuFolderPath = "$Script:AppDataPath\ContextMenu"
# Supported file types
$Script:SupportedExtensions = @('.msi', '.msp', '.exe', '.ps1', '.cmd', '.bat', '.vbs')
# Scheduled Task (Session 0 mode)
$Script:TaskNamePrefix = "RunAsSystem_"
$Script:TaskMarker = "[RunAsSystem-Temporary-Task]"
# GitHub Repository (used for the update check)
$Script:GitHubRepo = "MichaelEscamilla/RunAsSystem"
$Script:ScriptUrl = "https://raw.githubusercontent.com/$Script:GitHubRepo/main/RunAsSystem.ps1"
$Script:ReleasesApiUrl = "https://api.github.com/repos/$Script:GitHubRepo/releases/latest"
$Script:ReleasesPageUrl = "https://github.com/$Script:GitHubRepo/releases"
# Headers required by the GitHub REST API (a User-Agent is mandatory)
$Script:UpdateCheckHeaders = @{
  'User-Agent' = 'RunAsSystem-UpdateCheck'
  'Accept'     = 'application/vnd.github+json'
}
# Get the Security Principal
$Script:currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
# Windows PowerShell 5.1 path (used for the right-click menu and relaunching)
$Script:WindowsPowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
# Current run state
$Script:CurrentRun = $null
# Type of the last file loaded, so the options can be reset when the type changes
$Script:LastInstallerType = $null
# The log path last filled in automatically, so a path that was typed in isn't overwritten
$Script:DefaultLogPath = $null
# michaeltheadmin.com Icon
$Script:WindowIconBase64 = "AAABAAEAIBwAAAEAIACYDgAAFgAAACgAAAAgAAAAOAAAAAEAIAAAAAAAcA4AAMQOAADEDgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABaSFoNRkZGEUtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEEtLSxBLS0sQS0tLEFRGRhFaSEgNAAAAAAAAAABUVFQLUkxPrFNOUOlRTE7tUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7FFMTuxRTE7sUUxO7VROUOhSTU+qTExMCU5KTH5lYWP/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bm1t/25tbf9ubW3/bmxt/2RfYf9OSkx6TkhLtWtoaf94eHj/dnZ2/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3V1df91dXX/dXV1/3Z2dv94eHj/aWZn/05IS69OSUuxamdo/3h4eP9mZGX/Uk1P/05JS/9OSUv/VVFT/1VRUv9OSUv/T0pM/09KTP9PSkz/T0pM/09KTP9PSkz/T0pM/09KTP9PSkz/T0pM/09KTP9PSkz/TklL/1VRU/9VUVP/TklL/05JS/9STlD/ZmRl/3h4eP9oZWb/T0lMqk9JTLBqZ2j/eHl4/1dUVf90cHH/rqys/62rrP9rZ2j/b2tt/66srP+npaX/p6Wl/6elpf+npaX/p6Wl/6elpf+npaX/p6Wl/6elpf+npaX/p6Wl/6elpf+tq6z/a2do/29rbP+urKz/rays/3Bsbv9YVVb/eHl5/2hlZv9PSUyqT0lMsGpnaP94eXj/U1BR/5GPkP/09PT/8/Pz/399ff+Hg4X/9PT0/+jo6P/o6Oj/6Ojo/+jo6P/o6Oj/6Ojo/+jo6P/o6Oj/6Ojo/+jo6P/o6Oj/6Ojo//Pz8/9/fX3/hoOE//T09P/z9PP/i4iJ/1VRUv94eXn/aGVm/09JTKpPSUywamdo/3h5eP9VUlP/hIGC/9PS0v/S0dH/dXJz/3t3ef/T0tL/ycjI/8rJyv/Kycr/ycjI/8nIyP/Kycr/ysnK/8nIyP/JyMj/ysnK/8vKyf/Lycj/1NLR/3dzc/98eHj/1dPS/9TT0f9/fHz/V1NU/3h5ef9oZWb/T0lMqk9JTLBqZ2j/eHl4/19cXv9TTU//V1JU/1dSVP9TTlD/VE9R/1dSVP9XUlT/V1NV/1dTVf9XUlT/V1JU/1dTVf9XU1X/V1JU/1dSVP9XU1X/WFNU/1hSVP9ZU1T/VU9Q/1VPUP9ZU1T/WVNU/1JNTv9gXV7/eHl5/2hlZv9PSUyqT0lMsGpnaP94eXj/V1NV/3x4ef/Hx8j/v76//8HAwf/BwMD/v76//8jHx/9ybnD/dnN0/8jIyP/Ix8f/cm9w/3Vxc//Ix8j/yMfI/4B2cP85VYL/LXrf/y933P8xed7/MXne/y933P8tet7/Q1p//2NaU/94eXn/aGVm/09JTKpPSUywamdo/3h5eP9UUFL/jImK//L09P/n6Oj/5+jo/+fo6P/n6Oj/8/Pz/4B9f/+Gg4T/9PT0//L08/+Afn//hICC//L09P/y9PT/k4h//zRblv8jjf//J4n//yeJ//8nif//J4n//yON//9AYJL/Y1lQ/3h5ef9oZWb/T0lMqk9JTLBqZ2j/eHl4/1hUVv95dHP/v7u3/7izr/+3tLP/tLO0/7GwsP+5t7j/cGxu/3Rwcf+5uLj/ubi4/3Bsbv9ybnD/ubi4/7m4uP98c27/PVV9/y5zzf8xcMr/NHTO/zR0zv8xcMr/LnPN/0RXef9jWlX/eHl5/2hlZv9PSUyqT0lMsGpnaP94eXj/YFxd/01LUv9ITVz/SE5d/0pJUP9TTU7/XFdZ/1tXWf9VUVL/VlFT/1tXWf9bV1n/VVFT/1ZRU/9cV1n/XFdZ/1VQU/9ZU1L/ZFtY/2RbV/9ZUEz/WlFN/2RbWP9kW1j/VlBQ/19cXv94eXn/aGVm/09JTKpPSUywamdo/3h5eP9jWFH/QF+Q/ymE+f8phPn/OFiJ/4yCe//e3t7/3d3d/3p2eP9/fH3/3t7e/93e3f96d3j/fXl7/93e3v/d3t7/fXp7/4B9fv/f3t7/3t3d/3p2d/9/fH3/397e/97e3f+DgIH/VlJT/3h5ef9oZWb/T0lMqk9JTLBqZ2j/eHl4/2NYT/8+Ypr/JI3//ySN//81WpL/lYuC//Pz8//y8vL/gHx+/4aDhP/z8/P/8vPy/4B9fv+DgIL/8vPz//Lz8/+DgYL/h4SF//Pz8//y8vL/f3x9/4aDhP/z8/P/8vPy/4qIiP9VUVL/eHl5/2hlZv9PSUyqT0lMsGpnaP94eXj/YFhV/0ZTbv87aaj/O2mo/0NRbP9waGX/m5iZ/5uYmf9mYWP/aGRm/5uYmf+bmJn/ZmJj/2djZf+bmJn/m5iZ/2djZf9pZWb/m5iZ/5uYmf9lYWL/amZo/6Cdnv+fnZ7/a2Zo/1lVV/94eXn/aGVm/09JTKpOSUuxamdo/3d4eP9nZmj/XFVT/2BUTP9gVEz/X1hV/1dUVv9QTE7/UExO/1lVV/9ZVVb/UExO/1BMTv9ZVVf/WVVW/1BMTv9QTE7/WVVW/1hVVv9QTE7/UExO/1lVV/9ZVVb/UE1O/1FNTv9WUlT/aWdo/3d4eP9oZWb/TkhLq09JTLNraGn/eHl5/3d3d/93eHj/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4d/93eHf/d3h3/3d4eP93d3f/eHl4/2hmZ/9OSEuuUUpMbWRfYf9ta2z/bWts/21rbP9ta2z/bWts/21rbP9ta2z/bWts/21rbP9ta2z/bWts/21rbP9ta2z/amhp/2poaf9ta2z/bWts/21rbP9ta2z/bWts/21rbP9ta2z/bWts/21rbP9ta2z/bWts/21rbP9samv/Yl1f/1BLS2hRUVECUUtNjFNNT89QS0zTUEpM01BKTNNQSkzTUEpM01BKTNNQSkzTUEpM01BKTNNQSkzTUEpM01BLTdFQS03yUEtN8FBLTdFQSkzTUEpM01BKTNNQSkzTUEpM01BKTNNQSkzTUEpM01BKTNNQSkzTUEtM01NNT89RTE6IfHx8AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFNMT7lTTVCmAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAU01Qs1JNT7gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABTTU1RWFNV/1NOUIhUTE9pVFBSaExMTBYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABRTE9mVlFS11NOUOJWUVLdUEtQNQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//////////wAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD//n////5////+B////wf///////////8="

# Windows PowerShell 5.1 does not enable TLS 1.2 by default (needed for GitHub and live.sysinternals.com)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

#############################################
################# Functions #################
#############################################
#region Functions
function Test-IsAdmin {
  return $Script:currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-RelaunchElevated {
  # Registering a task as SYSTEM and running PsExec -s both require administrator rights,
  # so relaunch elevated, carrying the FilePath over.
  Write-Host "Relaunching as Administrator..."
  if ($PSCommandPath) {
    $ArgumentList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$PSCommandPath`""
    if ($FilePath) { $ArgumentList += " -FilePath `"$FilePath`"" }
  }
  else {
    # Invoked from the internet (iex), so download the script again in the elevated session
    $Command = "& ([scriptblock]::Create((Invoke-RestMethod '$($Script:ScriptUrl)')))"
    if ($FilePath) { $Command += " -FilePath '$($FilePath -replace "'", "''")'" }
    $ArgumentList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -Command `"$Command`""
  }

  try {
    Start-Process -FilePath $Script:WindowsPowerShellPath -ArgumentList $ArgumentList -Verb RunAs -ErrorAction Stop
  }
  catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Run As SYSTEM needs to run as Administrator.`n`n$($_.Exception.Message)", "Run As SYSTEM", "OK", "Warning") | Out-Null
  }
}

function Get-InstallerType {
  param (
    [Parameter(Mandatory = $false)]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

  switch ([System.IO.Path]::GetExtension($Path).ToLower()) {
    '.msi' { return 'MSI' }
    '.msp' { return 'MSP' }
    '.exe' { return 'EXE' }
    '.ps1' { return 'PS1' }
    '.cmd' { return 'CMD' }
    '.bat' { return 'CMD' }
    '.vbs' { return 'VBS' }
  }
  return $null
}

function Get-DefaultLogPath {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $false)]
    [string]$MsiAction
  )

  # The installer's name plus the action, in the same folder (Setup.msi -> Setup.msi.Uninstall.log),
  # so the install, uninstall and repair logs of one MSI don't overwrite each other
  $ActionName = if ([System.IO.Path]::GetExtension($Path) -eq '.msp') {
    'Patch'
  }
  else {
    switch ($MsiAction) {
      '/x' { 'Uninstall' }
      '/fvomus' { 'Repair' }
      default { 'Install' }
    }
  }
  return "$Path.$ActionName.log"
}

function Update-DefaultLogPath {
  param (
    [Parameter(Mandatory = $false)]
    [switch]$Force
  )

  $Path = $txt_FilePath.Text.Trim().Trim('"')
  if ((Get-InstallerType -Path $Path) -notin 'MSI', 'MSP') { return }

  # Only replace the default name (or an empty box), so a log path that was typed in is kept
  $Current = $txt_LogPath.Text.Trim().Trim('"')
  if ($Force -or -not $Current -or $Current -eq $Script:DefaultLogPath) {
    $Script:DefaultLogPath = Get-DefaultLogPath -Path $Path -MsiAction (Get-ComboBoxTag -ComboBox $cmb_MsiAction)
    $txt_LogPath.Text = $Script:DefaultLogPath
  }
}

function Get-ComboBoxTag {
  param (
    [Parameter(Mandatory = $true)]
    [System.Windows.Controls.ComboBox]$ComboBox
  )

  if ($ComboBox.SelectedItem) { return [string]$ComboBox.SelectedItem.Tag }
  return ''
}

function Set-ComboBoxTag {
  param (
    [Parameter(Mandatory = $true)]
    [System.Windows.Controls.ComboBox]$ComboBox,
    [Parameter(Mandatory = $false)]
    [string]$Tag
  )

  foreach ($Item in $ComboBox.Items) {
    if ([string]$Item.Tag -eq [string]$Tag) {
      $ComboBox.SelectedItem = $Item
      return
    }
  }
}

function Set-StatusBar {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Text,
    [Parameter(Mandatory = $false)]
    [switch]$Warning
  )

  # Every message sets the colour, so a warning doesn't stay red after the next normal message
  $txtblk_StatusBar.Text = $Text
  $txtblk_StatusBar.Foreground = if ($Warning) { $formRunAsSystem.FindResource('Danger') } else { $formRunAsSystem.FindResource('TextMuted') }
}

function Get-FormState {
  [PSCustomObject]@{
    FilePath   = $txt_FilePath.Text.Trim().Trim('"')
    MsiAction  = Get-ComboBoxTag -ComboBox $cmb_MsiAction
    MsiUI      = Get-ComboBoxTag -ComboBox $cmb_MsiUI
    LogEnabled = [bool]$chk_Log.IsChecked
    LogPath    = $txt_LogPath.Text.Trim().Trim('"')
    Arguments  = $txt_Arguments.Text.Trim()
    Mode       = if ($rad_PsExec.IsChecked) { 'PsExec' } else { 'Session0' }
  }
}

function Set-FormState {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$State
  )

  # Set the file path first, since changing it resets the log path to the default
  $txt_FilePath.Text = $State.FilePath
  Set-ComboBoxTag -ComboBox $cmb_MsiAction -Tag $State.MsiAction
  Set-ComboBoxTag -ComboBox $cmb_MsiUI -Tag $State.MsiUI
  $chk_Log.IsChecked = [bool]$State.LogEnabled
  if ($State.LogPath) { $txt_LogPath.Text = $State.LogPath }
  $txt_Arguments.Text = $State.Arguments
  if ($State.Mode -eq 'PsExec') { $rad_PsExec.IsChecked = $true } else { $rad_Session0.IsChecked = $true }
  $txt_LogPath.IsEnabled = [bool]$chk_Log.IsChecked
  Update-CommandPreview
}

function Reset-FormOptions {
  # Everything except the file path, back to the defaults in the XAML
  Set-ComboBoxTag -ComboBox $cmb_MsiAction -Tag '/i'
  Set-ComboBoxTag -ComboBox $cmb_MsiUI -Tag '/qn'
  $chk_Log.IsChecked = $true
  $txt_LogPath.IsEnabled = $true
  $txt_Arguments.Text = ''
  $rad_Session0.IsChecked = $true
}

function Get-CommandSpec {
  # Builds the program and arguments to run from the current form state
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$State
  )

  $Type = Get-InstallerType -Path $State.FilePath
  if (-not $Type) { return $null }

  $InstallerPath = $State.FilePath
  $LogPath = $null

  switch ($Type) {
    { $_ -in 'MSI', 'MSP' } {
      $Execute = "$env:SystemRoot\System32\msiexec.exe"
      $Action = if ($Type -eq 'MSP') { '/p' } else { $State.MsiAction }
      $Parts = @($Action, "`"$InstallerPath`"")
      if ($State.MsiUI) { $Parts += $State.MsiUI }
      if ($State.LogEnabled -and $State.LogPath) {
        $LogPath = $State.LogPath
        $Parts += "/l*v `"$LogPath`""
      }
      if ($State.Arguments) { $Parts += $State.Arguments }
      $CommandArguments = $Parts -join ' '
    }
    'EXE' {
      $Execute = $InstallerPath
      $CommandArguments = $State.Arguments
    }
    'PS1' {
      $Execute = $Script:WindowsPowerShellPath
      $CommandArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" $($State.Arguments)".Trim()
    }
    'CMD' {
      $Execute = "$env:SystemRoot\System32\cmd.exe"
      # cmd /c ""C:\Path\Script.cmd" args" - the outer quotes are stripped by cmd, keeping the inner ones intact
      $CommandArguments = if ($State.Arguments) { "/c `"`"$InstallerPath`" $($State.Arguments)`"" } else { "/c `"`"$InstallerPath`"`"" }
    }
    'VBS' {
      $Execute = "$env:SystemRoot\System32\cscript.exe"
      $CommandArguments = "//NoLogo `"$InstallerPath`" $($State.Arguments)".Trim()
    }
  }

  # The installer's own folder is the working directory, the same as ConfigMgr and Intune
  $WorkingDirectory = Split-Path -Path $InstallerPath -Parent

  [PSCustomObject]@{
    Type             = $Type
    InstallerPath    = $InstallerPath
    Execute          = $Execute
    Arguments        = [string]$CommandArguments
    WorkingDirectory = $WorkingDirectory
    LogPath          = $LogPath
    CommandLine      = "`"$Execute`" $CommandArguments".Trim()
  }
}

function Get-PsExecPath {
  param (
    [Parameter(Mandatory = $false)]
    [string]$Directory
  )

  $Names = if ([Environment]::Is64BitOperatingSystem) { @('PsExec64.exe', 'PsExec.exe') } else { @('PsExec.exe') }

  # Look in the installer's folder first
  if ($Directory -and (Test-Path -LiteralPath $Directory)) {
    foreach ($Name in $Names) {
      $Candidate = Join-Path -Path $Directory -ChildPath $Name
      if (Test-Path -LiteralPath $Candidate) { return $Candidate }
    }
  }

  # Then anywhere on the PATH
  foreach ($Name in $Names) {
    $Command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Command) { return $Command.Source }
  }

  return $null
}

function Save-PsExec {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Directory
  )

  $Name = if ([Environment]::Is64BitOperatingSystem) { 'PsExec64.exe' } else { 'PsExec.exe' }
  $Url = "https://live.sysinternals.com/$Name"
  $Destination = Join-Path -Path $Directory -ChildPath $Name

  Write-Host "Downloading PsExec: [$Url] -> [$Destination]"
  Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
  return $Destination
}

function Get-PsExecArguments {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Spec
  )

  # Run in the current session so the installer UI is visible on this desktop (works over RDP too)
  $SessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

  # A trailing backslash (e.g. "C:\") would escape the closing quote
  $WorkingDirectory = $Spec.WorkingDirectory
  if ($WorkingDirectory.EndsWith('\')) { $WorkingDirectory += '.' }

  return "-accepteula -nobanner -s -i $SessionId -w `"$WorkingDirectory`" `"$($Spec.Execute)`" $($Spec.Arguments)".Trim()
}

function Update-CommandPreview {
  $State = Get-FormState
  $Spec = Get-CommandSpec -State $State

  if (-not $Spec) {
    $txt_CommandLine.Text = ''
    $btn_Run.IsEnabled = $false
    $btn_CommandLine_Copy.IsEnabled = $false
    return
  }

  if ($State.Mode -eq 'PsExec') {
    $PsExec = Get-PsExecPath -Directory $Spec.WorkingDirectory
    if (-not $PsExec) {
      $PsExecName = if ([Environment]::Is64BitOperatingSystem) { 'PsExec64.exe' } else { 'PsExec.exe' }
      $PsExec = Join-Path -Path $Spec.WorkingDirectory -ChildPath $PsExecName
    }
    $txt_CommandLine.Text = "`"$PsExec`" $(Get-PsExecArguments -Spec $Spec)"
  }
  else {
    $txt_CommandLine.Text = $Spec.CommandLine
  }

  $btn_CommandLine_Copy.IsEnabled = $true
  $btn_Run.IsEnabled = ($null -eq $Script:CurrentRun) -and (Test-Path -LiteralPath $Spec.InstallerPath -PathType Leaf)
}

function Update-FileSelection {
  $Path = $txt_FilePath.Text.Trim().Trim('"')
  $Type = Get-InstallerType -Path $Path

  # MSI options only apply to MSI and MSP files
  $IsWindowsInstaller = $Type -in 'MSI', 'MSP'
  $panel_MsiOptions.Visibility = if ($IsWindowsInstaller) { 'Visible' } else { 'Collapsed' }
  $panel_MsiLog.Visibility = if ($IsWindowsInstaller) { 'Visible' } else { 'Collapsed' }
  $cmb_MsiAction.IsEnabled = ($Type -eq 'MSI')

  # Settings for one file type rarely suit another (MSI properties passed to an EXE, for example),
  # so start fresh when the type changes. While a path is being typed the type is briefly unknown,
  # so only compare known types, otherwise typing would clear the arguments.
  if ($Type) {
    if ($Script:LastInstallerType -and $Type -ne $Script:LastInstallerType) {
      Write-Host "File type changed: [$($Script:LastInstallerType)] -> [$Type], resetting options"
      Reset-FormOptions
    }
    $Script:LastInstallerType = $Type
  }

  # A new file always gets a new default log next to it
  Update-DefaultLogPath -Force

  # File information line
  $txtblk_FileInfo.Foreground = $formRunAsSystem.FindResource('TextMuted')
  if ([string]::IsNullOrWhiteSpace($Path)) {
    $txtblk_FileInfo.Text = "Drag and drop a file anywhere on this window, or Browse. Supported: $($Script:SupportedExtensions -join ' ')"
  }
  elseif (-not $Type) {
    $txtblk_FileInfo.Text = "Unsupported file type. Supported: $($Script:SupportedExtensions -join ' ')"
    $txtblk_FileInfo.Foreground = $formRunAsSystem.FindResource('Danger')
  }
  elseif (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $txtblk_FileInfo.Text = "File not found."
    if ($Path -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath ([System.IO.Path]::GetPathRoot($Path)))) {
      $txtblk_FileInfo.Text += " Mapped network drives from your normal session aren't available to elevated apps or SYSTEM. Use the UNC path (\\server\share\...) instead."
    }
    $txtblk_FileInfo.Foreground = $formRunAsSystem.FindResource('Danger')
  }
  else {
    $File = Get-Item -LiteralPath $Path
    $SizeMB = [Math]::Round($File.Length / 1MB, 2)
    $Info = "$Type  |  $SizeMB MB  |  Working directory: $($File.DirectoryName)"

    # SYSTEM reaches network paths as the computer account, which commonly fails
    $IsNetwork = $Path.StartsWith('\\')
    if (-not $IsNetwork) {
      try { $IsNetwork = ([System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($Path))).DriveType -eq 'Network' } catch {}
    }
    if ($IsNetwork) {
      $Info += "`nNetwork path: SYSTEM connects as the computer account (DOMAIN\COMPUTER`$), which needs read access to the share$(if ($IsWindowsInstaller) { ' and write access for the log' })."
      $txtblk_FileInfo.Foreground = $formRunAsSystem.FindResource('Accent')
    }
    $txtblk_FileInfo.Text = $Info
  }

  Update-CommandPreview
}

function ConvertTo-Int32 {
  # Task Scheduler can hand back the result as signed or unsigned depending on the value
  param (
    [Parameter(Mandatory = $true)]
    $Value
  )

  return [BitConverter]::ToInt32([BitConverter]::GetBytes([int64]$Value), 0)
}

function Get-ExitCodeInfo {
  param (
    [Parameter(Mandatory = $true)]
    [int]$ExitCode
  )

  $KnownCodes = @{
    0    = 'Success'
    1641 = 'Success - the installer started a restart'
    3010 = 'Success - a restart is required to complete the install'
    1707 = 'Success - installation completed successfully'
    1602 = 'The user cancelled the installation'
    1603 = 'Fatal error during installation - check the log'
    1605 = 'This product is not installed (nothing to uninstall or repair)'
    1612 = 'The installation source for this product is not available'
    1618 = 'Another installation is already in progress'
    1619 = 'The installation package could not be opened (path or access problem)'
    1620 = 'The installation package could not be opened (invalid package)'
    1622 = 'Error opening the installation log file (check the log path and permissions)'
    1625 = 'The installation is forbidden by system policy'
    1633 = 'This installation package is not supported on this platform'
    1638 = 'Another version of this product is already installed'
    1639 = 'Invalid command line argument'
  }

  $Category = switch ($ExitCode) {
    { $_ -in 0, 1707 } { 'Success'; break }
    { $_ -in 1641, 3010 } { 'Reboot'; break }
    default { 'Failure' }
  }

  if ($KnownCodes.ContainsKey($ExitCode)) {
    $Meaning = $KnownCodes[$ExitCode]
  }
  else {
    # Windows Installer and most HRESULTs are in the system message table
    # EXE installers often use their own codes, so label it as the generic Windows description
    try { $Meaning = ([System.ComponentModel.Win32Exception]::new($ExitCode)).Message } catch { $Meaning = '' }
    if (-not $Meaning -or $Meaning -match '^Unknown error') { $Meaning = 'Unknown exit code - check the installer documentation or log' }
    else { $Meaning = "Windows error text: $Meaning" }
  }

  [PSCustomObject]@{
    ExitCode = $ExitCode
    Hex      = '0x{0:X8}' -f $ExitCode
    Category = $Category
    Meaning  = $Meaning
  }
}

#### Scheduled Task (Session 0) ####
function Connect-TaskService {
  # COM rather than the ScheduledTasks module: it's faster to poll and exposes LastTaskResult directly
  if ($Script:TaskService -and $Script:TaskService.Connected) { return $Script:TaskService }
  $Service = New-Object -ComObject 'Schedule.Service'
  $Service.Connect()
  $Script:TaskService = $Service
  return $Service
}

function Register-SystemTask {
  # Approach based on the Patch My PC Connectivity tool:
  # https://github.com/PatchMyPCTeam/CustomerTroubleshooting/tree/Release/PowerShell/Connectivity
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
    [Parameter(Mandatory = $true)]
    [string]$Execute,
    [Parameter(Mandatory = $false)]
    [string]$TaskArguments,
    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory
  )

  $Service = Connect-TaskService
  $Folder = $Service.GetFolder('\')
  $Definition = $Service.NewTask(0)

  # Registration Info - the marker identifies tasks this tool owns, so nothing else is ever touched
  $Definition.RegistrationInfo.Author = 'RunAsSystem'
  $Definition.RegistrationInfo.Description = "$($Script:TaskMarker)`nTemporary task created by Run As SYSTEM to run an installer as NT AUTHORITY\SYSTEM. It has no active trigger, only runs on demand, and is deleted when the run finishes (or automatically when it expires)."

  # Settings
  $Definition.Settings.Enabled = $true
  $Definition.Settings.Hidden = $false
  $Definition.Settings.AllowDemandStart = $true
  $Definition.Settings.StartWhenAvailable = $false
  $Definition.Settings.DisallowStartIfOnBatteries = $false
  $Definition.Settings.StopIfGoingOnBatteries = $false
  # No time limit - the installer runs until it finishes
  $Definition.Settings.ExecutionTimeLimit = 'PT0S'
  # IgnoreNew
  $Definition.Settings.MultipleInstances = 2
  # Normal priority. Tasks default to 7 (below normal), which would make installers run slower than under ConfigMgr/Intune
  $Definition.Settings.Priority = 4
  # Self-delete after the trigger expires, so nothing is left behind if this tool crashes
  $Definition.Settings.DeleteExpiredTaskAfter = 'PT0S'

  # Disabled, expiring trigger: it can never start the task on its own, it only exists so the task can expire
  $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
  $Now = Get-Date
  $Trigger = $Definition.Triggers.Create(1)
  $Trigger.StartBoundary = $Now.ToString('yyyy-MM-ddTHH:mm:ss', $Invariant)
  $Trigger.EndBoundary = $Now.AddHours(24).ToString('yyyy-MM-ddTHH:mm:ss', $Invariant)
  $Trigger.Enabled = $false

  # Action - run the installer directly so its exit code becomes the task's LastTaskResult
  $Action = $Definition.Actions.Create(0)
  $Action.Path = $Execute
  if ($TaskArguments) { $Action.Arguments = $TaskArguments }
  if ($WorkingDirectory) { $Action.WorkingDirectory = $WorkingDirectory }

  # Principal - SYSTEM, highest privileges
  $Definition.Principal.UserId = 'S-1-5-18'
  $Definition.Principal.LogonType = 5
  $Definition.Principal.RunLevel = 1

  # 6 = CREATE_OR_UPDATE, 5 = TASK_LOGON_SERVICE_ACCOUNT. Two forms - Windows builds differ
  try { $null = $Folder.RegisterTaskDefinition($TaskName, $Definition, 6, $null, $null, 5) }
  catch { $null = $Folder.RegisterTaskDefinition($TaskName, $Definition, 6, 'S-1-5-18', $null, 5) }

  Write-Host "Registered Scheduled Task: [\$TaskName]"
  return $Folder.GetTask($TaskName)
}

function Test-OwnSystemTask {
  param (
    [Parameter(Mandatory = $true)]
    $Task
  )

  try { return ([string]$Task.Definition.RegistrationInfo.Description).Contains($Script:TaskMarker) } catch { return $false }
}

function Get-SystemTaskStatus {
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName
  )

  try { $Task = (Connect-TaskService).GetFolder('\').GetTask($TaskName) } catch { return $null }

  [PSCustomObject]@{
    # 0 Unknown, 1 Disabled, 2 Queued, 3 Ready, 4 Running
    State          = [int]$Task.State
    LastTaskResult = ConvertTo-Int32 -Value $Task.LastTaskResult
  }
}

function Remove-SystemTask {
  param (
    [Parameter(Mandatory = $true)]
    [string]$TaskName
  )

  try {
    $Folder = (Connect-TaskService).GetFolder('\')
    $Task = $Folder.GetTask($TaskName)
    if (Test-OwnSystemTask -Task $Task) {
      $Folder.DeleteTask($TaskName, 0)
      Write-Host "Removed Scheduled Task: [\$TaskName]"
    }
  }
  catch {
    Write-Host "Unable to remove Scheduled Task [\$TaskName]: $($_.Exception.Message)"
  }
}

function Clear-StaleSystemTasks {
  # Removes tasks left behind by a previous session that was closed while an installer was running
  try {
    $Folder = (Connect-TaskService).GetFolder('\')
    foreach ($Task in @($Folder.GetTasks(1))) {
      if ($Task.Name -like "$($Script:TaskNamePrefix)*" -and $Task.State -ne 4 -and (Test-OwnSystemTask -Task $Task)) {
        $Folder.DeleteTask($Task.Name, 0)
        Write-Host "Removed stale Scheduled Task: [\$($Task.Name)]"
      }
    }
  }
  catch {
    Write-Host "Unable to check for stale Scheduled Tasks: $($_.Exception.Message)"
  }
}

#### Running ####
function Set-RunningState {
  param (
    [Parameter(Mandatory = $true)]
    [bool]$Running
  )

  foreach ($Control in @($txt_FilePath, $btn_Browse, $cmb_MsiAction, $cmb_MsiUI, $chk_Log, $txt_LogPath, $txt_Arguments, $rad_Session0, $rad_PsExec, $btn_HistoryLoad, $btn_HistoryClear)) {
    $Control.IsEnabled = -not $Running
  }

  # Stop only exists while something is running
  $btn_Stop.Visibility = if ($Running) { 'Visible' } else { 'Collapsed' }

  if ($Running) {
    $btn_Run.IsEnabled = $false
    $btn_Run.Content = 'Running...'
  }
  else {
    $btn_Run.Content = 'Run as SYSTEM'
    # Restore the per-file-type enabled states
    $cmb_MsiAction.IsEnabled = ((Get-InstallerType -Path $txt_FilePath.Text.Trim().Trim('"')) -eq 'MSI')
    $txt_LogPath.IsEnabled = [bool]$chk_Log.IsChecked
    Update-CommandPreview
  }
}

function Set-ResultDisplay {
  param (
    [Parameter(Mandatory = $true)]
    [string]$ExitCodeText,
    [Parameter(Mandatory = $true)]
    [string]$Meaning,
    [Parameter(Mandatory = $false)]
    [string]$Details,
    [Parameter(Mandatory = $false)]
    [string]$Category,
    [Parameter(Mandatory = $false)]
    [string]$HexText
  )

  $Brush = switch ($Category) {
    'Success' { $formRunAsSystem.FindResource('Success') }
    'Reboot' { $formRunAsSystem.FindResource('Accent') }
    'Failure' { $formRunAsSystem.FindResource('Danger') }
    { $_ -in 'Stopped', 'Cancelled', 'StoppedWaiting' } { $formRunAsSystem.FindResource('TextMuted') }
    default { $formRunAsSystem.FindResource('Text') }
  }

  $txtblk_ExitCode.Text = $ExitCodeText
  $txtblk_ExitCode.Foreground = $Brush
  $txtblk_ExitCodeHex.Text = $HexText
  $txtblk_ExitMeaning.Text = $Meaning
  $txtblk_RunDetails.Text = $Details
}

function Start-SystemRun {
  $State = Get-FormState
  $Spec = Get-CommandSpec -State $State
  if (-not $Spec) { return }

  if (-not (Test-Path -LiteralPath $Spec.InstallerPath -PathType Leaf)) {
    [System.Windows.MessageBox]::Show("File not found:`n$($Spec.InstallerPath)", "Run As SYSTEM", "OK", "Warning") | Out-Null
    return
  }

  # Resolve PsExec before changing any state, since it may need to be downloaded
  $PsExecPath = $null
  if ($State.Mode -eq 'PsExec') {
    $PsExecPath = Get-PsExecPath -Directory $Spec.WorkingDirectory
    if (-not $PsExecPath) {
      $Answer = [System.Windows.MessageBox]::Show("PsExec was not found in the installer's folder or on the PATH.`n`nDownload it from live.sysinternals.com to:`n$($Spec.WorkingDirectory)", "Run As SYSTEM - PsExec", "YesNo", "Question")
      if ($Answer -ne 'Yes') { return }
      try {
        $PsExecPath = Save-PsExec -Directory $Spec.WorkingDirectory
      }
      catch {
        [System.Windows.MessageBox]::Show("Unable to download PsExec:`n$($_.Exception.Message)", "Run As SYSTEM - PsExec", "OK", "Error") | Out-Null
        return
      }
    }
  }

  $Script:CurrentRun = [PSCustomObject]@{
    State      = $State
    Spec       = $Spec
    Mode       = $State.Mode
    Started    = Get-Date
    TaskName   = $null
    Process    = $null
    CommandRun = $txt_CommandLine.Text
  }

  Set-RunningState -Running $true
  $ModeText = if ($State.Mode -eq 'PsExec') { 'Interactive (PsExec)' } else { 'Session 0' }
  Set-ResultDisplay -ExitCodeText '...' -Meaning 'Running as NT AUTHORITY\SYSTEM' -Details "$ModeText  |  Started $($Script:CurrentRun.Started.ToString('T'))"
  Write-Host "Running as SYSTEM [$($State.Mode)]: $($Script:CurrentRun.CommandRun)"

  try {
    if ($State.Mode -eq 'PsExec') {
      $Process = Start-Process -FilePath $PsExecPath -ArgumentList (Get-PsExecArguments -Spec $Spec) -WorkingDirectory $Spec.WorkingDirectory -WindowStyle Hidden -PassThru -ErrorAction Stop
      # Touch the handle so ExitCode is available after the process exits
      $null = $Process.Handle
      $Script:CurrentRun.Process = $Process
    }
    else {
      $TaskName = "$($Script:TaskNamePrefix)$(Get-Date -Format 'yyyyMMdd_HHmmss')"
      $Script:CurrentRun.TaskName = $TaskName
      $Task = Register-SystemTask -TaskName $TaskName -Execute $Spec.Execute -TaskArguments $Spec.Arguments -WorkingDirectory $Spec.WorkingDirectory
      try { $null = $Task.Run($null) }
      catch { $null = $Task.RunEx($null, 0, 0, $null) }
    }
  }
  catch {
    Complete-SystemRun -ErrorMessage $_.Exception.Message
    return
  }

  $Script:RunTimer.Start()
}

function Watch-SystemRun {
  # Called by the DispatcherTimer while a run is in progress
  $Run = $Script:CurrentRun
  if (-not $Run) { $Script:RunTimer.Stop(); return }

  $Elapsed = (Get-Date) - $Run.Started
  $btn_Run.Content = "Running...  $($Elapsed.ToString('hh\:mm\:ss'))"

  if ($Run.Mode -eq 'PsExec') {
    if ($Run.Process.HasExited) {
      Complete-SystemRun -ExitCode $Run.Process.ExitCode
    }
    return
  }

  $Status = Get-SystemTaskStatus -TaskName $Run.TaskName
  if (-not $Status) {
    Complete-SystemRun -ErrorMessage "The Scheduled Task [\$($Run.TaskName)] no longer exists."
    return
  }

  # Queued or Running
  if ($Status.State -in 2, 4) { return }

  # 267009 = currently running, 267011 = has not run yet
  if ($Status.LastTaskResult -in 267009, 267011) {
    if ($Status.LastTaskResult -eq 267011 -and $Elapsed.TotalSeconds -gt 30) {
      Complete-SystemRun -ErrorMessage "The Scheduled Task did not start within 30 seconds."
    }
    return
  }

  Complete-SystemRun -ExitCode $Status.LastTaskResult
}

function Get-RunProcessId {
  # Task Scheduler and PsExec don't hand back the installer's PID, so find it by the installer path in
  # its command line and its start time. Only the top of each matching tree is returned, since stopping
  # that ends its children too. The Windows Installer service (msiexec /V) never has the path in its
  # command line, so it's never matched.
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Run
  )

  $Since = $Run.Started.AddSeconds(-5)
  $InstallerPath = $Run.Spec.InstallerPath
  # The local PsExec client also has the path in its command line, and is stopped separately
  $PsExecClientId = if ($Run.Process) { $Run.Process.Id } else { -1 }

  $Found = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object {
      $_.CommandLine -and
      $_.CommandLine.IndexOf($InstallerPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
      $_.CreationDate -ge $Since -and
      $_.ProcessId -ne $PID -and
      $_.ProcessId -ne $PsExecClientId
    })

  $FoundIds = @($Found | ForEach-Object { $_.ProcessId })
  return @($Found | Where-Object { $FoundIds -notcontains $_.ParentProcessId } | ForEach-Object { $_.ProcessId })
}

function Stop-SystemRun {
  $Run = $Script:CurrentRun
  if (-not $Run) { return }

  # An MSI install runs in the Windows Installer service, not the msiexec.exe process this run started.
  # Ending that process doesn't stop the service, and stopping the service would affect every install
  # on the device, so for MSI and MSP this only stops waiting.
  $IsWindowsInstaller = $Run.Spec.Type -in 'MSI', 'MSP'
  $Answer = [System.Windows.MessageBox]::Show("Stop the running process?`n`nThe process and anything it started are ended immediately, so the software may be left partly installed.`n`nMSI installs (including an MSI started by another process) can't be stopped this way. Windows Installer keeps running them in the background until they finish, and the log keeps being written. Run As SYSTEM only stops waiting, so the exit code won't be recorded. Uninstall afterwards if you need to undo it.", "Run As SYSTEM - Stop", "YesNo", "Warning")
  if ($Answer -ne 'Yes') { return }
  # The timer keeps running while the prompt is open, so the run may have finished in the meantime
  if ($Script:CurrentRun -ne $Run) { return }

  Write-Host "Stopping run: [$($Run.CommandRun)]"
  $Note = $null
  try {
    $ProcessIds = @(Get-RunProcessId -Run $Run)
  }
  catch {
    $ProcessIds = @()
    Write-Host "Unable to list processes: $($_.Exception.Message)"
  }

  foreach ($ProcessId in $ProcessIds) {
    # /T ends the whole tree: bootstrappers and PSADT often start child installers
    Write-Host "Stopping process tree: [$ProcessId]"
    & "$env:SystemRoot\System32\taskkill.exe" /PID $ProcessId /T /F 2>&1 | ForEach-Object { Write-Host "  $_" }
  }
  if ($ProcessIds.Count -eq 0 -and -not $IsWindowsInstaller) {
    $Note = "The process couldn't be found, so only the $(if ($Run.TaskName) { 'Scheduled Task' } else { 'PsExec client' }) was stopped. Check Task Manager for anything still running."
    Write-Host $Note
  }

  # Also stop what launched it, in case the process search missed something
  if ($Run.TaskName) {
    try { (Connect-TaskService).GetFolder('\').GetTask($Run.TaskName).Stop(0) } catch {}
  }
  if ($Run.Process -and -not $Run.Process.HasExited) {
    try { $Run.Process.Kill() } catch {}
  }

  Complete-SystemRun -Stopped -WindowsInstaller:$IsWindowsInstaller -ErrorMessage $Note
}

function Complete-SystemRun {
  param (
    [Parameter(Mandatory = $false)]
    [Nullable[int]]$ExitCode,
    [Parameter(Mandatory = $false)]
    [string]$ErrorMessage,
    [Parameter(Mandatory = $false)]
    [switch]$Stopped,
    [Parameter(Mandatory = $false)]
    [switch]$WindowsInstaller
  )

  $Script:RunTimer.Stop()
  $Run = $Script:CurrentRun
  if (-not $Run) { return }

  if ($Run.TaskName) { Remove-SystemTask -TaskName $Run.TaskName }

  $Duration = (Get-Date) - $Run.Started
  $ModeText = if ($Run.Mode -eq 'PsExec') { 'Interactive (PsExec)' } else { 'Session 0' }
  $Details = "$ModeText  |  Started $($Run.Started.ToString('T'))  |  Duration $($Duration.ToString('hh\:mm\:ss'))"

  if ($Stopped) {
    $Meaning = if ($WindowsInstaller) {
      'Stopped waiting - Windows Installer is still running the install in the background. Check the log for the result.'
    }
    elseif ($ErrorMessage) {
      "Stopped - $ErrorMessage"
    }
    else {
      'Stopped - the process and anything it started were ended'
    }
    $Category = 'Stopped'
    Set-ResultDisplay -ExitCodeText 'Stopped' -Meaning $Meaning -Details $Details -Category $Category
    Write-Host "Run stopped: $Meaning"
  }
  elseif ($null -ne $ExitCode) {
    $Info = Get-ExitCodeInfo -ExitCode $ExitCode
    Set-ResultDisplay -ExitCodeText "$ExitCode" -HexText $Info.Hex -Meaning $Info.Meaning -Details $Details -Category $Info.Category
    Write-Host "Exit Code: [$ExitCode] [$($Info.Hex)] $($Info.Meaning)"
    $Meaning = $Info.Meaning
    $Category = $Info.Category
  }
  else {
    Set-ResultDisplay -ExitCodeText 'Error' -Meaning $ErrorMessage -Details $Details -Category 'Failure'
    Write-Host "Run failed: $ErrorMessage"
    $Meaning = $ErrorMessage
    $Category = 'Failure'
  }

  # Remember the log of this run for the Open Log button
  $Script:LastLogPath = $Run.Spec.LogPath
  $Script:LastWorkingDirectory = $Run.Spec.WorkingDirectory
  $btn_OpenLog.IsEnabled = [bool]$Script:LastLogPath
  $btn_OpenFolder.IsEnabled = [bool]$Script:LastWorkingDirectory

  Add-HistoryEntry -Entry ([PSCustomObject]@{
      Timestamp   = $Run.Started.ToString('yyyy-MM-dd HH:mm:ss')
      FilePath    = $Run.State.FilePath
      MsiAction   = $Run.State.MsiAction
      MsiUI       = $Run.State.MsiUI
      LogEnabled  = $Run.State.LogEnabled
      LogPath     = $Run.State.LogPath
      Arguments   = $Run.State.Arguments
      Mode        = $Run.Mode
      CommandLine = $Run.CommandRun
      ExitCode    = $ExitCode
      Meaning     = $Meaning
      Category    = $Category
      Duration    = $Duration.ToString('hh\:mm\:ss')
    })

  $Script:CurrentRun = $null
  Set-RunningState -Running $false
}

#### History ####
function Protect-HistoryValue {
  # Arguments can hold passwords and license keys. DPAPI (CurrentUser scope) means only this
  # Windows account on this device can decrypt them, so a copied History.json is unreadable.
  param (
    [Parameter(Mandatory = $false)]
    [string]$Value
  )

  if ([string]::IsNullOrEmpty($Value)) { return '' }
  return ConvertTo-SecureString -String $Value -AsPlainText -Force | ConvertFrom-SecureString
}

function Unprotect-HistoryValue {
  param (
    [Parameter(Mandatory = $false)]
    [string]$Value
  )

  if ([string]::IsNullOrEmpty($Value)) { return '' }
  $Secure = ConvertTo-SecureString -String $Value -ErrorAction Stop
  return (New-Object System.Net.NetworkCredential('', $Secure)).Password
}

function Get-History {
  if (-not (Test-Path -LiteralPath $Script:HistoryPath)) { return @() }
  try {
    $Data = Get-Content -LiteralPath $Script:HistoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    # Piping unrolls the array (Windows PowerShell 5.1 returns a JSON array as a single object)
    $Entries = @($Data | ForEach-Object { $_ })
  }
  catch {
    Write-Host "Unable to read history: $($_.Exception.Message)"
    return @()
  }

  $HasPlainText = $false
  foreach ($Entry in $Entries) {
    if (-not $Entry.PSObject.Properties['ArgumentsProtected']) {
      # Saved by a version that stored arguments as plain text
      $HasPlainText = $true
      continue
    }

    try {
      $Arguments = Unprotect-HistoryValue -Value $Entry.ArgumentsProtected
      $CommandLine = Unprotect-HistoryValue -Value $Entry.CommandLineProtected
      $Entry.PSObject.Properties.Remove('ArgumentsProtected')
      $Entry.PSObject.Properties.Remove('CommandLineProtected')
      $Unreadable = $false
    }
    catch {
      # Encrypted by another Windows account or device, or the account's password was reset.
      # Keep the encrypted values so saving the history doesn't destroy them.
      $Arguments = ''
      $CommandLine = ''
      $Unreadable = $true
    }
    $Entry | Add-Member -NotePropertyName 'Arguments' -NotePropertyValue $Arguments -Force
    $Entry | Add-Member -NotePropertyName 'CommandLine' -NotePropertyValue $CommandLine -Force
    $Entry | Add-Member -NotePropertyName 'ArgumentsUnreadable' -NotePropertyValue $Unreadable -Force
  }

  # Re-save straight away so plain-text arguments don't stay on disk until the next run
  if ($HasPlainText) {
    Write-Host "Encrypting the arguments saved in history: [$Script:HistoryPath]"
    Save-History -Entries $Entries
  }

  return $Entries
}

function Save-History {
  param (
    [Parameter(Mandatory = $false)]
    [object[]]$Entries = @()
  )

  try {
    if (-not (Test-Path -LiteralPath $Script:AppDataPath)) {
      New-Item -ItemType Directory -Path $Script:AppDataPath -Force | Out-Null
    }

    $Output = @(foreach ($Entry in $Entries) {
      $Copy = $Entry | Select-Object -Property * -ExcludeProperty 'Arguments', 'CommandLine', 'ArgumentsUnreadable'
      if (-not $Entry.ArgumentsUnreadable) {
        $Copy | Add-Member -NotePropertyName 'ArgumentsProtected' -NotePropertyValue (Protect-HistoryValue -Value $Entry.Arguments) -Force
        $Copy | Add-Member -NotePropertyName 'CommandLineProtected' -NotePropertyValue (Protect-HistoryValue -Value $Entry.CommandLine) -Force
      }
      $Copy
    })
    ConvertTo-Json -InputObject $Output -Depth 3 | Set-Content -LiteralPath $Script:HistoryPath -Encoding UTF8 -ErrorAction Stop
  }
  catch {
    Write-Host "Unable to save history: $($_.Exception.Message)"
  }
}

function Add-HistoryEntry {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Entry
  )

  # Newest first, capped
  $Entries = @($Entry) + @(Get-History) | Select-Object -First $Script:HistoryMaxEntries
  Save-History -Entries $Entries
  Update-HistoryList
}

function Update-HistoryList {
  $lsbox_History.Items.Clear()

  foreach ($Entry in @(Get-History)) {
    $CodeBrush = switch ($Entry.Category) {
      'Success' { $formRunAsSystem.FindResource('Success') }
      'Reboot' { $formRunAsSystem.FindResource('Accent') }
      { $_ -in 'Stopped', 'Cancelled', 'StoppedWaiting' } { $formRunAsSystem.FindResource('TextMuted') }
      default { $formRunAsSystem.FindResource('Danger') }
    }

    # Line 1: File name and exit code
    $Line1 = New-Object System.Windows.Controls.DockPanel
    $Code = New-Object System.Windows.Controls.TextBlock
    # 'Cancelled' and 'StoppedWaiting' were written by pre-release builds before they became 'Stopped'
    $Code.Text = if ($Entry.Category -in 'Stopped', 'Cancelled', 'StoppedWaiting') { 'Stopped' } elseif ($null -ne $Entry.ExitCode) { [string]$Entry.ExitCode } else { 'Error' }
    $Code.Foreground = $CodeBrush
    $Code.FontWeight = 'SemiBold'
    $Code.Margin = '8,0,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($Code, 'Right')
    $Name = New-Object System.Windows.Controls.TextBlock
    $Name.Text = Split-Path -Path $Entry.FilePath -Leaf
    $Name.FontWeight = 'SemiBold'
    $Name.TextTrimming = 'CharacterEllipsis'
    $Line1.Children.Add($Code) | Out-Null
    $Line1.Children.Add($Name) | Out-Null

    # Line 2: When and how
    $Line2 = New-Object System.Windows.Controls.TextBlock
    $ModeText = if ($Entry.Mode -eq 'PsExec') { 'PsExec' } else { 'Session 0' }
    $ActionText = if ($Entry.MsiAction -and (Get-InstallerType -Path $Entry.FilePath) -eq 'MSI') { "$($Entry.MsiAction)  |  " } else { '' }
    $Line2.Text = "$($Entry.Timestamp)  |  $ActionText$ModeText"
    $Line2.FontSize = 11
    $Line2.Foreground = $formRunAsSystem.FindResource('TextMuted')
    $Line2.TextTrimming = 'CharacterEllipsis'
    if ($Entry.ArgumentsUnreadable) {
      # Warning icon (Segoe MDL2 Assets) so the entry stands out before it's loaded
      $Icon = New-Object System.Windows.Documents.Run ([string][char]0xE7BA)
      $Icon.FontFamily = 'Segoe MDL2 Assets'
      $Icon.Foreground = $formRunAsSystem.FindResource('Danger')
      $Line2.Inlines.Add((New-Object System.Windows.Documents.Run '  |  '))
      $Line2.Inlines.Add($Icon)
    }

    $Panel = New-Object System.Windows.Controls.StackPanel
    $Panel.Children.Add($Line1) | Out-Null
    $Panel.Children.Add($Line2) | Out-Null

    # Line 3: Arguments, so runs of the same installer with different arguments can be told apart
    if ($Entry.Arguments) {
      $Line3 = New-Object System.Windows.Controls.TextBlock
      $Line3.Text = $Entry.Arguments
      $Line3.FontFamily = 'Consolas'
      $Line3.FontSize = 11
      $Line3.Foreground = $formRunAsSystem.FindResource('TextMuted')
      $Line3.TextTrimming = 'CharacterEllipsis'
      $Line3.Margin = '0,2,0,0'
      $Panel.Children.Add($Line3) | Out-Null
    }

    # Load and Copy buttons beside the exit code, only while the mouse is over the entry.
    # Collapsed otherwise, so the file name gets the full width.
    $Actions = New-Object System.Windows.Controls.StackPanel
    $Actions.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($Actions, 'Right')
    $HoverBinding = New-Object System.Windows.Data.Binding 'IsMouseOver'
    $HoverBinding.RelativeSource = New-Object System.Windows.Data.RelativeSource ([System.Windows.Data.RelativeSourceMode]::FindAncestor, [System.Windows.Controls.ListBoxItem], 1)
    $HoverBinding.Converter = New-Object System.Windows.Controls.BooleanToVisibilityConverter
    $Actions.SetBinding([System.Windows.UIElement]::VisibilityProperty, $HoverBinding) | Out-Null

    $LoadButton = New-Object System.Windows.Controls.Button
    $LoadButton.Style = $formRunAsSystem.FindResource('HistoryIconButton')
    # Segoe MDL2 Assets: Upload (load into the form)
    $LoadButton.Content = [string][char]0xE898
    $LoadButton.ToolTip = 'Load this run into the form'
    $LoadButton.Tag = $Entry
    $LoadButton.Add_Click({ Import-HistoryEntry -Entry $this.Tag })
    $Actions.Children.Add($LoadButton) | Out-Null

    # Nothing to copy when the command line couldn't be decrypted
    if (-not $Entry.ArgumentsUnreadable) {
      $CopyButton = New-Object System.Windows.Controls.Button
      $CopyButton.Style = $formRunAsSystem.FindResource('HistoryIconButton')
      $CopyButton.Content = [string][char]0xE8C8
      $CopyButton.ToolTip = 'Copy the command line'
      $CopyButton.Tag = $Entry
      $CopyButton.Add_Click({ Copy-HistoryEntry -Entry $this.Tag })
      $Actions.Children.Add($CopyButton) | Out-Null
    }

    # Docked children must come before the name, which fills the rest of the line
    $Line1.Children.Insert(1, $Actions)

    $Item = New-Object System.Windows.Controls.ListBoxItem
    $Item.Content = $Panel
    $Item.Tag = $Entry
    $Item.ToolTip = if ($Entry.ArgumentsUnreadable) { "The arguments of this run were saved by another Windows account or device and can't be decrypted.`n`n$($Entry.Meaning)" } else { "$($Entry.CommandLine)`n`n$($Entry.Meaning)" }
    $lsbox_History.Items.Add($Item) | Out-Null
  }

  $btn_HistoryClear.IsEnabled = ($lsbox_History.Items.Count -gt 0) -and ($null -eq $Script:CurrentRun)
  Update-HistoryButtons
}

function Import-HistoryEntry {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Entry
  )

  if ($Script:CurrentRun) {
    Set-StatusBar -Warning -Text "A run can't be loaded while an installer is running"
    return
  }

  Set-FormState -State $Entry
  if ($Entry.ArgumentsUnreadable) {
    Set-StatusBar -Warning -Text "Loaded run from $($Entry.Timestamp) WITHOUT its arguments - they were saved on another account or device and can't be decrypted here. Re-enter them before running."
  }
  else {
    Set-StatusBar -Text "Loaded run from $($Entry.Timestamp)"
  }
}

function Copy-HistoryEntry {
  param (
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Entry
  )

  if (-not $Entry.CommandLine) { return }
  [System.Windows.Clipboard]::SetText($Entry.CommandLine)
  Write-Host "Copied to Clipboard: [$($Entry.CommandLine)]"
  Set-StatusBar -Text "Command line copied to the clipboard"
}

function Update-HistoryButtons {
  $HasSelection = $null -ne $lsbox_History.SelectedItem
  $btn_HistoryLoad.IsEnabled = $HasSelection -and ($null -eq $Script:CurrentRun)
  # There's nothing to copy when the command line couldn't be decrypted
  $btn_HistoryCopy.IsEnabled = $HasSelection -and -not $lsbox_History.SelectedItem.Tag.ArgumentsUnreadable
}

#### Elevated Drag and Drop ####
function Enable-ElevatedDragDrop {
  # WPF drag and drop uses OLE, which Windows blocks from a non-elevated Explorer into an elevated window (UIPI).
  # The older WM_DROPFILES message can be allowed through the message filter, so use that instead.
  param (
    [Parameter(Mandatory = $true)]
    [System.Windows.Window]$Window
  )

  if (-not ('RunAsSystem.ElevatedDropTarget' -as [type])) {
    $Source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;

namespace RunAsSystem
{
    public class ElevatedDropTarget
    {
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool ChangeWindowMessageFilterEx(IntPtr hWnd, uint msg, uint action, IntPtr pChangeFilterStruct);
        [DllImport("shell32.dll")]
        static extern void DragAcceptFiles(IntPtr hWnd, bool fAccept);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern uint DragQueryFile(IntPtr hDrop, uint iFile, StringBuilder lpszFile, uint cch);
        [DllImport("shell32.dll")]
        static extern void DragFinish(IntPtr hDrop);
        [DllImport("ole32.dll")]
        static extern int RevokeDragDrop(IntPtr hWnd);

        const int WM_DROPFILES = 0x0233;
        const uint WM_COPYDATA = 0x004A;
        const uint WM_COPYGLOBALDATA = 0x0049;
        const uint MSGFLT_ALLOW = 1;

        public event Action<string[]> FilesDropped;

        public void Attach(IntPtr hWnd)
        {
            // Remove WPF's OLE drop target so Explorer falls back to WM_DROPFILES
            RevokeDragDrop(hWnd);
            ChangeWindowMessageFilterEx(hWnd, (uint)WM_DROPFILES, MSGFLT_ALLOW, IntPtr.Zero);
            ChangeWindowMessageFilterEx(hWnd, WM_COPYDATA, MSGFLT_ALLOW, IntPtr.Zero);
            ChangeWindowMessageFilterEx(hWnd, WM_COPYGLOBALDATA, MSGFLT_ALLOW, IntPtr.Zero);
            DragAcceptFiles(hWnd, true);
            HwndSource.FromHwnd(hWnd).AddHook(WndProc);
        }

        IntPtr WndProc(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_DROPFILES)
            {
                uint count = DragQueryFile(wParam, 0xFFFFFFFF, null, 0);
                string[] files = new string[count];
                for (uint i = 0; i < count; i++)
                {
                    uint length = DragQueryFile(wParam, i, null, 0);
                    StringBuilder buffer = new StringBuilder((int)length + 1);
                    DragQueryFile(wParam, i, buffer, length + 1);
                    files[i] = buffer.ToString();
                }
                DragFinish(wParam);
                handled = true;

                Action<string[]> handler = FilesDropped;
                if (handler != null) { handler(files); }
            }
            return IntPtr.Zero;
        }
    }
}
'@
    Add-Type -TypeDefinition $Source -ReferencedAssemblies @(
      [System.Windows.Interop.HwndSource].Assembly.Location,
      [System.Windows.Threading.Dispatcher].Assembly.Location
    )
  }

  $Handle = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
  $Script:DropTarget = New-Object RunAsSystem.ElevatedDropTarget
  $Script:DropTarget.add_FilesDropped({
      param($Files)
      if ($Files -and $Files.Count -gt 0) {
        Write-Host "File Dropped: [$($Files[0])]"
        $txt_FilePath.Text = $Files[0]
      }
    })
  $Script:DropTarget.Attach($Handle)
}

#### Update Check ####
# Fetches the latest published GitHub release and reports whether it is newer than $CurrentVersion.
# Authored as a scriptblock so the exact same logic is used by the manual menu check (invoked directly)
# and by the background check (the same scriptblock is handed to a runspace). Takes only arguments,
# so it carries no dependencies into the runspace.
$Script:TestForUpdate = {
  param(
    [string]$ApiUrl,
    [hashtable]$Headers,
    [System.Version]$CurrentVersion
  )
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $release = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
  $latestVersion = [System.Version]($release.tag_name -replace '^v', '')
  [PSCustomObject]@{
    UpdateAvailable = ($latestVersion -gt $CurrentVersion)
    LatestVersion   = $latestVersion
    HtmlUrl         = $release.html_url
  }
}

function Start-BackgroundUpdateCheck {
  # Runs $Script:TestForUpdate on its own runspace/thread so the network call never blocks the UI,
  # then polls for completion on the UI thread.
  [CmdletBinding()]
  param()

  try {
    $Script:UpdatePowerShell = [powershell]::Create()
    $Script:UpdatePowerShell.AddScript($Script:TestForUpdate).
    AddArgument($Script:ReleasesApiUrl).
    AddArgument($Script:UpdateCheckHeaders).
    AddArgument($Script:ScriptVersion) | Out-Null
    $Script:UpdateHandle = $Script:UpdatePowerShell.BeginInvoke()

    $Script:UpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $Script:UpdateTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $Script:UpdateTimer.Add_Tick({
        if (-not $Script:UpdateHandle.IsCompleted) { return }
        $Script:UpdateTimer.Stop()
        try {
          $result = $Script:UpdatePowerShell.EndInvoke($Script:UpdateHandle) | Select-Object -First 1
          Write-Host "Background update check: UpdateAvailable=$($result.UpdateAvailable) | Installed [$($Script:ScriptVersion)] | Latest [$($result.LatestVersion)]"
          Show-UpdateAvailable -Result $result
        }
        catch {
          Write-Host "Background update check failed: $($_.Exception.Message)"
        }
        finally {
          $Script:UpdatePowerShell.Dispose()
        }
      })
    $Script:UpdateTimer.Start()
  }
  catch {
    Write-Host "Unable to start background update check: $($_.Exception.Message)"
  }
}

function Show-UpdateAvailable {
  # Reveals the 'Update Available' menu item when a newer release exists, so both the background and
  # manual checks surface the result the same way. Remembers the download link for the click handler.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    $Result
  )

  if (-not $Result.UpdateAvailable) { return }

  $Script:LatestReleaseUrl = if ($Result.HtmlUrl) { $Result.HtmlUrl } else { $Script:ReleasesPageUrl }
  $MenuItem_UpdateAvailable.Header = "Update Available: v$($Result.LatestVersion)"
  $MenuItem_UpdateAvailable.Visibility = [System.Windows.Visibility]::Visible
}

#### Right Click Menu ####
function Install-RightClickMenu {
  Write-Host "Installing Right Click Menu"

  # Create the folder that holds the script and icon used by the menu
  Write-Host "Creating Folder:    [$($Script:RightClickMenuFolderPath)]"
  if (-not (Test-Path $Script:RightClickMenuFolderPath)) {
    New-Item -ItemType Directory -Path $Script:RightClickMenuFolderPath -Force | Out-Null
  }
  $ScriptPath = Join-Path -Path $Script:RightClickMenuFolderPath -ChildPath $Script:ScriptName

  # Create an ico file from $Script:WindowIconBase64
  $IconFilePath = Join-Path -Path $Script:RightClickMenuFolderPath -ChildPath "RunAsSystem.ico"
  Write-Host "Creating Icon file: [$IconFilePath]"
  try {
    [System.IO.File]::WriteAllBytes($IconFilePath, [System.Convert]::FromBase64String($Script:WindowIconBase64))
  }
  catch {
    Write-Host "Unable to create the icon file: $($_.Exception.Message)"
    $IconFilePath = $Script:WindowsPowerShellPath
  }

  # Copy the script, or download it when invoked from the internet
  if ($PSCommandPath) {
    Write-Host "Creating Script:    [$ScriptPath]"
    Copy-Item -LiteralPath $PSCommandPath -Destination $ScriptPath -Force -ErrorAction SilentlyContinue
  }
  else {
    Write-Host "Downloading script: [$($Script:ScriptUrl)]"
    try {
      Invoke-WebRequest -Uri $Script:ScriptUrl -OutFile $ScriptPath -UseBasicParsing -ErrorAction Stop
      Write-Host "Script saved:       [$ScriptPath]"
    }
    catch {
      Write-Host "Failed to download the script: $_"
      [System.Windows.MessageBox]::Show("Failed to download the script:`n$($_.Exception.Message)", "Run As SYSTEM", "OK", "Error") | Out-Null
      return
    }
  }

  # Always Windows PowerShell 5.1 - it's on every device
  $Command = "`"$($Script:WindowsPowerShellPath)`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$ScriptPath`" -FilePath `"%1`""

  foreach ($Extension in $Script:SupportedExtensions) {
    $KeyPath = "HKCU:\Software\Classes\SystemFileAssociations\$Extension\shell\$($Script:RightClickMenuKeyName)"
    New-Item -Path "$KeyPath\command" -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $KeyPath -Name '(default)' -Value "$($Script:RightClickMenuName)..." -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath $KeyPath -Name 'Icon' -Value $IconFilePath -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    # Shows the UAC shield next to the menu item
    New-ItemProperty -LiteralPath $KeyPath -Name 'HasLUAShield' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -LiteralPath "$KeyPath\command" -Name '(default)' -Value $Command -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Registry Modified:  [$KeyPath]"
  }
  Write-Host "Installation Complete"
  Set-StatusBar -Text "Right-click menu installed for: $($Script:SupportedExtensions -join ' ')"
}

function Uninstall-RightClickMenu {
  Write-Host "Uninstalling Right Click Menu"

  foreach ($Extension in $Script:SupportedExtensions) {
    $KeyPath = "HKCU:\Software\Classes\SystemFileAssociations\$Extension\shell\$($Script:RightClickMenuKeyName)"
    if (Test-Path -LiteralPath $KeyPath) {
      Remove-Item -LiteralPath $KeyPath -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host "Deleted Registry: [$KeyPath]"
    }
  }

  # Only the menu files - the run history is kept
  Remove-Item -LiteralPath $Script:RightClickMenuFolderPath -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Deleted Folder:   [$($Script:RightClickMenuFolderPath)]"
  Write-Host "Uninstallation Complete"
  Set-StatusBar -Text "Right-click menu uninstalled"
}
#endregion Functions

#############################################
################# Main Script ################
#############################################

# Registering a SYSTEM task and running PsExec both need administrator rights
if (-not (Test-IsAdmin)) {
  Invoke-RelaunchElevated
  return
}

# Load Assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Build the GUI
[xml]$XAMLformRunAsSystem = @'
<Window
  xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
  xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Name="form1"
  Width="1100"
  Height="760"
  ResizeMode="NoResize"
  WindowStyle="None"
  AllowsTransparency="True"
  Background="Transparent"
  AllowDrop="True"
  Title="Run As SYSTEM"
  FontFamily="Segoe UI"
  FontSize="14">

  <Window.Resources>
    <!-- Color tokens (michaeltheadmin.com palette) -->
    <SolidColorBrush x:Key="Bg"
        Color="#292524"/>
    <SolidColorBrush x:Key="Surface"
        Color="#1C1917"/>
    <SolidColorBrush x:Key="Surface2"
        Color="#44403C"/>
    <SolidColorBrush x:Key="Border"
        Color="#3A3633"/>
    <SolidColorBrush x:Key="BorderMuted"
        Color="#57534E"/>
    <SolidColorBrush x:Key="Text"
        Color="#F5F5F4"/>
    <SolidColorBrush x:Key="TextMuted"
        Color="#A8A29E"/>
    <SolidColorBrush x:Key="Accent"
        Color="#FB923C"/>
    <SolidColorBrush x:Key="AccentHover"
        Color="#F97316"/>
    <SolidColorBrush x:Key="AccentText"
        Color="#1C1917"/>
    <SolidColorBrush x:Key="Danger"
        Color="#EF4444"/>
    <SolidColorBrush x:Key="Success"
        Color="#4ADE80"/>

    <!-- Menu item templates -->
    <ControlTemplate x:Key="MenuTopLevelHeader"
        TargetType="MenuItem">
      <Grid>
        <Border x:Name="Bd"
            Background="{TemplateBinding Background}"
            BorderBrush="{StaticResource Accent}"
            BorderThickness="1"
            CornerRadius="6"
            Margin="2,0"
            Padding="10,4">
          <ContentPresenter ContentSource="Header"
              VerticalAlignment="Center"/>
        </Border>
        <Popup x:Name="PART_Popup"
            Placement="Bottom"
            IsOpen="{TemplateBinding IsSubmenuOpen}"
            AllowsTransparency="True"
            Focusable="False"
            PopupAnimation="Fade">
          <Border Background="{StaticResource Surface}"
              BorderBrush="{StaticResource Border}"
              BorderThickness="1"
              CornerRadius="8"
              Padding="4"
              Margin="0,4,10,10">
            <Border.Effect>
              <DropShadowEffect BlurRadius="14"
                  ShadowDepth="2"
                  Opacity="0.5"
                  Color="#000000"/>
            </Border.Effect>
            <StackPanel IsItemsHost="True"
                KeyboardNavigation.DirectionalNavigation="Cycle"/>
          </Border>
        </Popup>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted"
            Value="True">
          <Setter TargetName="Bd"
              Property="Background"
              Value="{StaticResource Accent}"/>
          <Setter Property="Foreground"
              Value="{StaticResource AccentText}"/>
        </Trigger>
        <Trigger Property="IsSubmenuOpen"
            Value="True">
          <Setter TargetName="Bd"
              Property="Background"
              Value="{StaticResource Accent}"/>
          <Setter Property="Foreground"
              Value="{StaticResource AccentText}"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>

    <ControlTemplate x:Key="MenuTopLevelItem"
        TargetType="MenuItem">
      <Border x:Name="Bd"
          Background="{TemplateBinding Background}"
          BorderBrush="{StaticResource Accent}"
          BorderThickness="1"
          CornerRadius="6"
          Margin="2,0"
          Padding="10,4">
        <ContentPresenter ContentSource="Header"
            VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted"
            Value="True">
          <Setter TargetName="Bd"
              Property="Background"
              Value="{StaticResource Accent}"/>
          <Setter Property="Foreground"
              Value="{StaticResource AccentText}"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>

    <ControlTemplate x:Key="MenuSubmenuItem"
        TargetType="MenuItem">
      <Border x:Name="Bd"
          Background="{TemplateBinding Background}"
          CornerRadius="6"
          Padding="12,6"
          Margin="1">
        <ContentPresenter ContentSource="Header"
            VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted"
            Value="True">
          <Setter TargetName="Bd"
              Property="Background"
              Value="{StaticResource Accent}"/>
          <Setter Property="Foreground"
              Value="{StaticResource AccentText}"/>
        </Trigger>
        <Trigger Property="IsEnabled"
            Value="False">
          <Setter Property="Foreground"
              Value="{StaticResource TextMuted}"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>

    <!-- Menu -->
    <Style TargetType="Menu">
      <Setter Property="Background"
          Value="Transparent"/>
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Padding"
          Value="6,2"/>
      <Setter Property="BorderThickness"
          Value="0"/>
    </Style>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Background"
          Value="Transparent"/>
      <Style.Triggers>
        <Trigger Property="Role"
            Value="TopLevelHeader">
          <Setter Property="Template"
              Value="{StaticResource MenuTopLevelHeader}"/>
        </Trigger>
        <Trigger Property="Role"
            Value="TopLevelItem">
          <Setter Property="Template"
              Value="{StaticResource MenuTopLevelItem}"/>
        </Trigger>
        <Trigger Property="Role"
            Value="SubmenuItem">
          <Setter Property="Template"
              Value="{StaticResource MenuSubmenuItem}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="Separator">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Separator">
            <Border Height="1"
                Background="{StaticResource Border}"
                Margin="8,4"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Labels -->
    <Style x:Key="ThemedLabel"
        TargetType="Label">
      <Setter Property="Foreground"
          Value="{StaticResource TextMuted}"/>
      <Setter Property="FontWeight"
          Value="SemiBold"/>
      <Setter Property="Margin"
          Value="2.5"/>
      <Setter Property="Padding"
          Value="4,0,8,0"/>
      <Setter Property="VerticalAlignment"
          Value="Stretch"/>
      <Setter Property="VerticalContentAlignment"
          Value="Center"/>
      <Setter Property="HorizontalContentAlignment"
          Value="Right"/>
    </Style>
    <Style TargetType="Label"
        BasedOn="{StaticResource ThemedLabel}"/>

    <!-- Textboxes -->
    <Style x:Key="ThemedTextBox"
        TargetType="TextBox">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Background"
          Value="{StaticResource Surface}"/>
      <Setter Property="BorderBrush"
          Value="{StaticResource Border}"/>
      <Setter Property="BorderThickness"
          Value="1"/>
      <Setter Property="Margin"
          Value="2.5"/>
      <Setter Property="Padding"
          Value="8,0"/>
      <Setter Property="VerticalContentAlignment"
          Value="Center"/>
      <Setter Property="CaretBrush"
          Value="{StaticResource Accent}"/>
      <Setter Property="SelectionBrush"
          Value="{StaticResource Accent}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd"
                Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="{TemplateBinding BorderThickness}"
                CornerRadius="6">
              <ScrollViewer x:Name="PART_ContentHost"
                  Margin="{TemplateBinding Padding}"
                  VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource BorderMuted}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
              </Trigger>
              <Trigger Property="IsEnabled"
                  Value="False">
                <Setter TargetName="Bd"
                    Property="Opacity"
                    Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox"
        BasedOn="{StaticResource ThemedTextBox}"/>

    <!-- Buttons -->
    <Style x:Key="ThemedButton"
        TargetType="Button">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Background"
          Value="{StaticResource Surface2}"/>
      <Setter Property="BorderBrush"
          Value="{StaticResource BorderMuted}"/>
      <Setter Property="BorderThickness"
          Value="1"/>
      <Setter Property="Margin"
          Value="2.5"/>
      <Setter Property="Padding"
          Value="10,4"/>
      <Setter Property="FontWeight"
          Value="SemiBold"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="HorizontalContentAlignment"
          Value="Center"/>
      <Setter Property="VerticalContentAlignment"
          Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="{TemplateBinding BorderThickness}"
                CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center"
                  VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Accent}"/>
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource AccentText}"/>
              </Trigger>
              <Trigger Property="IsPressed"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource AccentHover}"/>
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource AccentHover}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource AccentText}"/>
              </Trigger>
              <Trigger Property="IsEnabled"
                  Value="False">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Surface}"/>
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource Border}"/>
                <Setter TargetName="Bd"
                    Property="Opacity"
                    Value="0.6"/>
                <Setter Property="Foreground"
                    Value="{StaticResource TextMuted}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button"
        BasedOn="{StaticResource ThemedButton}"/>

    <!-- Primary (Run) button -->
    <Style x:Key="AccentButton"
        TargetType="Button"
        BasedOn="{StaticResource ThemedButton}">
      <Setter Property="Background"
          Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush"
          Value="{StaticResource Accent}"/>
      <Setter Property="Foreground"
          Value="{StaticResource AccentText}"/>
      <Setter Property="FontSize"
          Value="16"/>
    </Style>

    <!-- Icon-only copy button -->
    <Style x:Key="CopyButton"
        TargetType="Button"
        BasedOn="{StaticResource ThemedButton}">
      <Setter Property="FontFamily"
          Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize"
          Value="14"/>
      <Setter Property="HorizontalAlignment"
          Value="Stretch"/>
      <Setter Property="Padding"
          Value="0"/>
    </Style>

    <!-- ComboBox -->
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd"
                Background="Transparent"
                CornerRadius="4"
                Padding="10,6">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Accent}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource AccentText}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Margin"
          Value="2.5"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False"
                  ClickMode="Press"
                  IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd"
                        Background="{StaticResource Surface}"
                        BorderBrush="{StaticResource Border}"
                        BorderThickness="1"
                        CornerRadius="6">
                      <TextBlock Text="&#xE70D;"
                          FontFamily="Segoe MDL2 Assets"
                          FontSize="10"
                          Foreground="{StaticResource TextMuted}"
                          HorizontalAlignment="Right"
                          VerticalAlignment="Center"
                          Margin="0,0,10,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver"
                          Value="True">
                        <Setter TargetName="Bd"
                            Property="BorderBrush"
                            Value="{StaticResource Accent}"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False"
                  Content="{TemplateBinding SelectionBoxItem}"
                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                  Margin="10,0,28,0"
                  VerticalAlignment="Center"
                  HorizontalAlignment="Left"/>
              <Popup x:Name="PART_Popup"
                  IsOpen="{TemplateBinding IsDropDownOpen}"
                  Placement="Bottom"
                  AllowsTransparency="True"
                  Focusable="False"
                  PopupAnimation="Fade">
                <Border Background="{StaticResource Surface}"
                    BorderBrush="{StaticResource Border}"
                    BorderThickness="1"
                    CornerRadius="6"
                    Padding="3"
                    Margin="0,2,0,0"
                    MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <StackPanel IsItemsHost="True"
                      KeyboardNavigation.DirectionalNavigation="Contained"/>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled"
                  Value="False">
                <Setter Property="Opacity"
                    Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- CheckBox -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="VerticalAlignment"
          Value="Center"/>
      <Setter Property="Margin"
          Value="8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal"
                Background="Transparent">
              <Border x:Name="Box"
                  Width="18"
                  Height="18"
                  CornerRadius="4"
                  Background="{StaticResource Surface}"
                  BorderBrush="{StaticResource BorderMuted}"
                  BorderThickness="1"
                  VerticalAlignment="Center">
                <TextBlock x:Name="Mark"
                    Text="&#xE73E;"
                    FontFamily="Segoe MDL2 Assets"
                    FontSize="11"
                    Foreground="{StaticResource AccentText}"
                    HorizontalAlignment="Center"
                    VerticalAlignment="Center"
                    Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0"
                  VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Box"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
              </Trigger>
              <Trigger Property="IsChecked"
                  Value="True">
                <Setter TargetName="Box"
                    Property="Background"
                    Value="{StaticResource Accent}"/>
                <Setter TargetName="Box"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
                <Setter TargetName="Mark"
                    Property="Visibility"
                    Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled"
                  Value="False">
                <Setter Property="Opacity"
                    Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- RadioButton -->
    <Style TargetType="RadioButton">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Margin"
          Value="8,5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <StackPanel Orientation="Horizontal"
                Background="Transparent">
              <Border x:Name="Ring"
                  Width="18"
                  Height="18"
                  CornerRadius="9"
                  Background="{StaticResource Surface}"
                  BorderBrush="{StaticResource BorderMuted}"
                  BorderThickness="1"
                  VerticalAlignment="Center">
                <Ellipse x:Name="Dot"
                    Width="8"
                    Height="8"
                    Fill="{StaticResource Accent}"
                    Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0"
                  VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Ring"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
              </Trigger>
              <Trigger Property="IsChecked"
                  Value="True">
                <Setter TargetName="Ring"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
                <Setter TargetName="Dot"
                    Property="Visibility"
                    Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled"
                  Value="False">
                <Setter Property="Opacity"
                    Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Muted section label -->
    <Style x:Key="SectionHeader"
        TargetType="TextBlock">
      <Setter Property="Foreground"
          Value="{StaticResource Accent}"/>
      <Setter Property="FontSize"
          Value="10"/>
      <Setter Property="FontWeight"
          Value="SemiBold"/>
      <Setter Property="VerticalAlignment"
          Value="Center"/>
      <Setter Property="Margin"
          Value="5,0,0,0"/>
    </Style>

    <!-- Thin scrollbar -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width"
          Value="8"/>
      <Setter Property="MinWidth"
          Value="8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track"
                IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border Background="{StaticResource BorderMuted}"
                          CornerRadius="4"
                          Margin="1,0"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- History list -->
    <Style TargetType="ListBox">
      <Setter Property="Background"
          Value="{StaticResource Surface}"/>
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush"
          Value="{StaticResource Border}"/>
      <Setter Property="BorderThickness"
          Value="1"/>
      <Setter Property="Margin"
          Value="2.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBox">
            <Border Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="{TemplateBinding BorderThickness}"
                CornerRadius="6">
              <ScrollViewer Focusable="False"
                  Padding="3"
                  VerticalScrollBarVisibility="Auto"
                  HorizontalScrollBarVisibility="Disabled">
                <ItemsPresenter/>
              </ScrollViewer>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="HorizontalContentAlignment"
          Value="Stretch"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd"
                Background="Transparent"
                BorderBrush="Transparent"
                BorderThickness="1"
                CornerRadius="4"
                Padding="8,5"
                Margin="0,1">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Bg}"/>
              </Trigger>
              <Trigger Property="IsSelected"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Surface2}"/>
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Small icon buttons shown on a history entry while the mouse is over it -->
    <Style x:Key="HistoryIconButton"
        TargetType="Button">
      <Setter Property="Foreground"
          Value="{StaticResource TextMuted}"/>
      <Setter Property="Background"
          Value="Transparent"/>
      <Setter Property="BorderBrush"
          Value="Transparent"/>
      <Setter Property="FontFamily"
          Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize"
          Value="12"/>
      <Setter Property="Width"
          Value="26"/>
      <Setter Property="Height"
          Value="22"/>
      <!-- Negative vertical margin keeps the line the same height when the buttons appear -->
      <Setter Property="Margin"
          Value="2,-3,0,-3"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="1"
                CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center"
                  VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="BorderBrush"
                    Value="{StaticResource Accent}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource Accent}"/>
              </Trigger>
              <Trigger Property="IsPressed"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Accent}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource AccentText}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Tooltip -->
    <Style TargetType="ToolTip">
      <Setter Property="Background"
          Value="{StaticResource Surface}"/>
      <Setter Property="Foreground"
          Value="{StaticResource Text}"/>
      <Setter Property="BorderBrush"
          Value="{StaticResource Border}"/>
      <Setter Property="BorderThickness"
          Value="1"/>
      <Setter Property="Padding"
          Value="8,4"/>
      <Setter Property="MaxWidth"
          Value="600"/>
      <Setter Property="ContentTemplate">
        <Setter.Value>
          <DataTemplate>
            <TextBlock Text="{Binding}"
                TextWrapping="Wrap"/>
          </DataTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Title bar buttons -->
    <Style x:Key="TitleBarButton"
        TargetType="Button">
      <Setter Property="Foreground"
          Value="{StaticResource TextMuted}"/>
      <Setter Property="Background"
          Value="Transparent"/>
      <Setter Property="BorderThickness"
          Value="0"/>
      <Setter Property="Width"
          Value="46"/>
      <Setter Property="FontFamily"
          Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize"
          Value="10"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center"
                  VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Surface2}"/>
                <Setter Property="Foreground"
                    Value="{StaticResource Text}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TitleBarCloseButton"
        TargetType="Button">
      <Setter Property="Foreground"
          Value="{StaticResource TextMuted}"/>
      <Setter Property="Background"
          Value="Transparent"/>
      <Setter Property="BorderThickness"
          Value="0"/>
      <Setter Property="Width"
          Value="46"/>
      <Setter Property="FontFamily"
          Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize"
          Value="10"/>
      <Setter Property="Cursor"
          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                Background="{TemplateBinding Background}"
                CornerRadius="0,11,0,0">
              <ContentPresenter HorizontalAlignment="Center"
                  VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver"
                  Value="True">
                <Setter TargetName="Bd"
                    Property="Background"
                    Value="{StaticResource Danger}"/>
                <Setter Property="Foreground"
                    Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Bg}"
      CornerRadius="12"
      BorderBrush="{StaticResource BorderMuted}"
      BorderThickness="1"
      Margin="0">
    <DockPanel>
      <Border Name="titlebar"
          DockPanel.Dock="Top"
          Background="{StaticResource Surface}"
          CornerRadius="11,11,0,0"
          Height="42">
        <DockPanel LastChildFill="False">
          <Button Name="titlebar_Close"
              DockPanel.Dock="Right"
              Style="{StaticResource TitleBarCloseButton}"
              Content="&#xE8BB;"/>
          <Button Name="titlebar_Minimize"
              DockPanel.Dock="Right"
              Style="{StaticResource TitleBarButton}"
              Content="&#xE921;"/>
          <Image DockPanel.Dock="Left"
              Margin="14,0,0,0"
              Width="20"
              Height="20"
              VerticalAlignment="Center"
              RenderOptions.BitmapScalingMode="HighQuality"
              Source="{Binding Icon, RelativeSource={RelativeSource AncestorType=Window}}"/>
          <StackPanel DockPanel.Dock="Left"
              Orientation="Horizontal"
              VerticalAlignment="Center"
              Margin="10,0,8,0">
            <TextBlock FontSize="15"
                FontWeight="SemiBold"
                Foreground="{StaticResource Text}"
                Text="Run As SYSTEM"
                VerticalAlignment="Center"/>
            <TextBlock Name="txtblk_TitleVersion"
                FontWeight="Normal"
                Foreground="{StaticResource TextMuted}"
                VerticalAlignment="Center"
                Margin="6,0,0,1"/>
          </StackPanel>
          <Menu DockPanel.Dock="Left"
              VerticalAlignment="Center">
            <MenuItem Header="File">
              <MenuItem Name="MenuItem_OpenAppData"
                  Header="Open History Folder"/>
              <MenuItem Name="MenuItem_TaskScheduler"
                  Header="Open Task Scheduler"/>
            </MenuItem>
            <MenuItem Header="Right Click Menu">
              <MenuItem Name="MenuItem_Install"
                  Header="Install"/>
              <MenuItem Name="MenuItem_Uninstall"
                  Header="Uninstall"/>
              <MenuItem Name="MenuItem_Open_RCM"
                  Header="Open Right Click Menu Folder"/>
            </MenuItem>
            <MenuItem Header="About">
              <MenuItem Name="MenuItem_GitHub"
                  Header="GitHub - RunAsSystem"/>
              <MenuItem Name="MenuItem_About"
                  Header="michaeltheadmin.com"/>
              <MenuItem Name="MenuItem_CheckForUpdates"
                  Header="Check for Updates"/>
              <MenuItem Name="MenuItem_Version"
                  Header="Version 1.0.0"
                  IsEnabled="False"
                  FontWeight="Normal"/>
            </MenuItem>
            <MenuItem Name="MenuItem_UpdateAvailable"
                Header="Update Available"
                Visibility="Collapsed"
                Background="{StaticResource Accent}"
                Foreground="{StaticResource AccentText}"/>
          </Menu>
        </DockPanel>
      </Border>
      <Border DockPanel.Dock="Bottom"
          Background="{StaticResource Surface}"
          Height="24"
          CornerRadius="0,0,11,11">
        <TextBlock Name="txtblk_StatusBar"
            VerticalAlignment="Center"
            Foreground="{StaticResource TextMuted}"
            FontSize="12"
            Margin="12,0"
            Text="Created By Michael Escamilla"/>
      </Border>

      <Grid Margin="8,6,8,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="330"/>
        </Grid.ColumnDefinitions>

        <!-- Left: Installer, options and result -->
        <Grid Grid.Column="0">
          <Grid.RowDefinitions>
            <RowDefinition Height="26"/>
            <RowDefinition Height="40"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="26"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="26"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="26"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="56"/>
            <RowDefinition Height="26"/>
            <RowDefinition Height="118"/>
          </Grid.RowDefinitions>

          <!-- INSTALLER -->
          <TextBlock Grid.Row="0"
              Style="{StaticResource SectionHeader}"
              Text="INSTALLER"/>
          <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="100"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="100"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0"
                Content="File"/>
            <TextBox Grid.Column="1"
                Name="txt_FilePath"
                ToolTip="Path to the installer. Drag and drop a file anywhere on this window, paste a path, or Browse."/>
            <Button Grid.Column="2"
                Name="btn_Browse"
                ToolTip="Browse for an installer (Ctrl+O)"
                Content="Browse"/>
          </Grid>
          <TextBlock Grid.Row="2"
              Name="txtblk_FileInfo"
              Margin="108,2,8,6"
              FontSize="12"
              TextWrapping="Wrap"
              Foreground="{StaticResource TextMuted}"/>

          <!-- OPTIONS -->
          <TextBlock Grid.Row="3"
              Style="{StaticResource SectionHeader}"
              Text="OPTIONS"/>
          <Grid Grid.Row="4"
              Name="panel_MsiOptions"
              Height="40"
              Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="100"/>
              <ColumnDefinition Width="200"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0"
                Content="Action"/>
            <ComboBox Grid.Column="1"
                Name="cmb_MsiAction">
              <ComboBoxItem Content="Install (/i)"
                  Tag="/i"
                  IsSelected="True"/>
              <ComboBoxItem Content="Uninstall (/x)"
                  Tag="/x"/>
              <ComboBoxItem Content="Repair (/fvomus)"
                  Tag="/fvomus"/>
            </ComboBox>
            <Label Grid.Column="2"
                Content="UI"/>
            <ComboBox Grid.Column="3"
                Name="cmb_MsiUI">
              <ComboBoxItem Content="Silent (/qn)"
                  Tag="/qn"
                  IsSelected="True"/>
              <ComboBoxItem Content="Basic UI (/qb)"
                  Tag="/qb"/>
              <ComboBoxItem Content="Basic UI, no cancel (/qb!)"
                  Tag="/qb!"/>
              <ComboBoxItem Content="Passive (/passive)"
                  Tag="/passive"/>
              <ComboBoxItem Content="Full UI"
                  Tag=""/>
            </ComboBox>
          </Grid>
          <Grid Grid.Row="5"
              Name="panel_MsiLog"
              Height="40"
              Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="100"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0"
                Content="Log"/>
            <CheckBox Grid.Column="1"
                Name="chk_Log"
                Content="/l*v"
                IsChecked="True"/>
            <TextBox Grid.Column="2"
                Name="txt_LogPath"
                ToolTip="Verbose log path. Defaults to the installer name plus the action, in the installer's folder (e.g. Setup.msi.Install.log)."/>
          </Grid>
          <Grid Grid.Row="6">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="100"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0"
                Name="lbl_Arguments"
                Padding="0,0,8,0"
                Content="ArgumentList"/>
            <!-- Wraps and grows to about three lines for long property lists, then scrolls. Enter still doesn't add a line break -->
            <TextBox Grid.Column="1"
                Name="txt_Arguments"
                TextWrapping="Wrap"
                AcceptsReturn="False"
                MinHeight="35"
                MaxHeight="76"
                Padding="8,3"
                VerticalScrollBarVisibility="Auto"
                ToolTip="Arguments for the installer. For MSI files, add properties here (e.g. ALLUSERS=1 TRANSFORMS=&quot;app.mst&quot;)."/>
          </Grid>

          <!-- RUN AS -->
          <TextBlock Grid.Row="7"
              Style="{StaticResource SectionHeader}"
              Text="RUN AS NT AUTHORITY\SYSTEM"/>
          <StackPanel Grid.Row="8"
              Margin="100,0,0,4">
            <RadioButton Name="rad_Session0"
                GroupName="RunMode"
                IsChecked="True">
              <TextBlock>
                <Run Text="Session 0"
                    FontWeight="SemiBold"/>
                <Run Text=" - hidden, no desktop. The same as ConfigMgr and Intune."
                    Foreground="{StaticResource TextMuted}"/>
              </TextBlock>
            </RadioButton>
            <RadioButton Name="rad_PsExec"
                GroupName="RunMode">
              <TextBlock>
                <Run Text="Interactive (PsExec)"
                    FontWeight="SemiBold"/>
                <Run Text=" - installer UI is visible on your desktop."
                    Foreground="{StaticResource TextMuted}"/>
              </TextBlock>
            </RadioButton>
          </StackPanel>

          <!-- COMMAND LINE -->
          <TextBlock Grid.Row="9"
              Style="{StaticResource SectionHeader}"
              Text="COMMAND LINE"/>
          <Grid Grid.Row="10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="60"/>
            </Grid.ColumnDefinitions>
            <TextBox Grid.Column="0"
                Name="txt_CommandLine"
                IsReadOnly="True"
                TextWrapping="Wrap"
                MinHeight="56"
                Padding="8,6"
                VerticalContentAlignment="Top"
                VerticalScrollBarVisibility="Auto"
                FontFamily="Consolas"
                FontSize="13"/>
            <!-- The command line takes up the leftover height, so keep the copy button its normal size -->
            <Button Grid.Column="1"
                Name="btn_CommandLine_Copy"
                Style="{StaticResource CopyButton}"
                Height="56"
                VerticalAlignment="Top"
                ToolTip="Copy the command line"
                Content="&#xE8C8;"/>
          </Grid>
          <!-- Stop is a separate button rather than Run changing into Stop, so double-clicking Run can't stop the process -->
          <Grid Grid.Row="11"
              Margin="0,5.5,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button Grid.Column="0"
                Name="btn_Run"
                Style="{StaticResource AccentButton}"
                ToolTip="Ctrl+Enter or F5"
                Content="Run as SYSTEM"/>
            <Button Grid.Column="1"
                Name="btn_Stop"
                Width="140"
                FontSize="16"
                Foreground="{StaticResource Danger}"
                BorderBrush="{StaticResource Danger}"
                Visibility="Collapsed"
                ToolTip="Stop the running process and anything it started. An MSI install keeps running in Windows Installer."
                Content="Stop"/>
          </Grid>

          <!-- RESULT -->
          <TextBlock Grid.Row="12"
              Style="{StaticResource SectionHeader}"
              Text="RESULT"/>
          <Border Grid.Row="13"
              Margin="2.5"
              CornerRadius="8"
              BorderBrush="{StaticResource Border}"
              BorderThickness="1"
              Background="{StaticResource Surface}">
            <Grid Margin="14,8">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"
                    MinWidth="110"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="120"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0"
                  VerticalAlignment="Center">
                <TextBlock Text="EXIT CODE"
                    FontSize="10"
                    FontWeight="SemiBold"
                    Foreground="{StaticResource TextMuted}"/>
                <TextBlock Name="txtblk_ExitCode"
                    Text="--"
                    FontSize="34"
                    FontWeight="Bold"
                    Foreground="{StaticResource Text}"/>
                <!-- Hex as well: EXE installers often document their codes in hex, and HRESULTs are easier to look up that way -->
                <TextBlock Name="txtblk_ExitCodeHex"
                    FontFamily="Consolas"
                    FontSize="12"
                    Margin="0,-4,0,0"
                    Foreground="{StaticResource TextMuted}"/>
              </StackPanel>
              <StackPanel Grid.Column="1"
                  VerticalAlignment="Center"
                  Margin="16,0,8,0">
                <TextBlock Name="txtblk_ExitMeaning"
                    Text="Not run yet"
                    FontWeight="SemiBold"
                    TextWrapping="Wrap"
                    Foreground="{StaticResource Text}"/>
                <TextBlock Name="txtblk_RunDetails"
                    FontSize="12"
                    TextWrapping="Wrap"
                    Margin="0,4,0,0"
                    Foreground="{StaticResource TextMuted}"/>
              </StackPanel>
              <StackPanel Grid.Column="2"
                  VerticalAlignment="Center">
                <Button Name="btn_OpenLog"
                    Content="Open Log"
                    Height="34"
                    IsEnabled="False"/>
                <Button Name="btn_OpenFolder"
                    Content="Open Folder"
                    Height="34"
                    IsEnabled="False"/>
              </StackPanel>
            </Grid>
          </Border>
        </Grid>

        <Line
          Grid.Column="1"
          Margin="8,6,8,6"
          X1="0"
          Y1="0"
          X2="0"
          Y2="1"
          Stroke="{StaticResource Border}"
          StrokeThickness="2"
          Stretch="Fill"/>

        <!-- Right: History -->
        <Grid Grid.Column="2">
          <Grid.RowDefinitions>
            <RowDefinition Height="26"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="40"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0"
              Style="{StaticResource SectionHeader}"
              Text="HISTORY"/>
          <ListBox Grid.Row="1"
              Name="lsbox_History"/>
          <UniformGrid Grid.Row="2"
              Columns="3">
            <Button Name="btn_HistoryLoad"
                Content="Load"
                ToolTip="Load the selected run back into the form (Ctrl+L, or double-click it)"/>
            <Button Name="btn_HistoryCopy"
                Content="Copy"
                ToolTip="Copy the command line of the selected run"/>
            <Button Name="btn_HistoryClear"
                Content="Clear"
                ToolTip="Clear the history"/>
          </UniformGrid>
        </Grid>
      </Grid>
    </DockPanel>
  </Border>
</Window>
'@

# Create a new XML node reader for reading the XAML content
$readerformRunAsSystem = New-Object System.Xml.XmlNodeReader $XAMLformRunAsSystem

# Load the XAML content into a WPF window object using the XAML reader
[System.Windows.Window]$formRunAsSystem = [Windows.Markup.XamlReader]::Load($readerformRunAsSystem)

# Create Variables for all the controls in the XAML form
$XAMLformRunAsSystem.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $formRunAsSystem.FindName($_.Name) -Scope Script }

# Timer that watches a run in progress
$Script:RunTimer = New-Object System.Windows.Threading.DispatcherTimer
$Script:RunTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$Script:RunTimer.Add_Tick({
    try { Watch-SystemRun }
    catch { Complete-SystemRun -ErrorMessage $_.Exception.Message }
  })

#############################################
############## Event Handlers ###############
#############################################
#region Event Handlers

#### Form Load #####
$formRunAsSystem.Add_Loaded({
    try {
      # Covert the AppIcon byte array to an Icon and set as the form icon
      $WindowIconBitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
      $WindowIconBitmap.BeginInit()
      $WindowIconBitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($Script:WindowIconBase64)
      $WindowIconBitmap.EndInit()
      $WindowIconBitmap.Freeze()
      $formRunAsSystem.Icon = $WindowIconBitmap
    }
    catch {
      # Write the error to the host but continue on. It's an icon, who cares.
      Write-Host "Error setting form icon: $_"
    }

    # Drag and drop from Explorer into this elevated window
    try {
      Enable-ElevatedDragDrop -Window $formRunAsSystem
    }
    catch {
      Write-Warning "Unable to enable drag and drop while elevated: $($_.Exception.Message)"
    }

    # Update Version Information
    $formRunAsSystem.Title = "Run As SYSTEM - Version $($Script:ScriptVersion)"
    $MenuItem_Version.Header = "Version $($Script:ScriptVersion)"
    $txtblk_TitleVersion.Text = " $($Script:ScriptVersion)"

    # Remove any tasks left behind by a previous session
    Clear-StaleSystemTasks

    # Load history
    Update-HistoryList

    # Background update check (non-blocking).
    Start-BackgroundUpdateCheck

    # Pre-fill from parameters
    if ($Arguments) { $txt_Arguments.Text = $Arguments }
    if ($FilePath) {
      Write-Host "FilePath passed: [$FilePath]"
      $txt_FilePath.Text = $FilePath
    }
    Update-FileSelection
  })

$formRunAsSystem.Add_Closing({
    if ($Script:CurrentRun) {
      $Answer = [System.Windows.MessageBox]::Show("An installer is still running as SYSTEM.`n`nClosing will not stop it, but its exit code won't be recorded. Close anyway?", "Run As SYSTEM", "YesNo", "Warning")
      if ($Answer -ne 'Yes') {
        $_.Cancel = $true
        return
      }
      # A Session 0 task left behind expires and deletes itself, and is also cleaned up the next time the tool opens
    }
    $Script:RunTimer.Stop()
  })

#### Drag and Drop (fallback when the window is not elevated) ####
$formRunAsSystem.Add_DragOver({
    if ($_.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
      $_.Effects = [System.Windows.DragDropEffects]::Copy
      $_.Handled = $true
    }
  })

$formRunAsSystem.Add_Drop({
    $Files = $_.Data.GetData([System.Windows.DataFormats]::FileDrop)
    if ($Files -and -not $Script:CurrentRun) {
      Write-Host "File Dropped: [$($Files[0])]"
      $txt_FilePath.Text = $Files[0]
    }
  })

#### Installer and Options ####
$txt_FilePath.Add_TextChanged({ Update-FileSelection })
$txt_Arguments.Add_TextChanged({ Update-CommandPreview })
$txt_LogPath.Add_TextChanged({ Update-CommandPreview })
$cmb_MsiAction.Add_SelectionChanged({
    Update-DefaultLogPath
    Update-CommandPreview
  })
$cmb_MsiUI.Add_SelectionChanged({ Update-CommandPreview })
$chk_Log.Add_Click({
    $txt_LogPath.IsEnabled = [bool]$chk_Log.IsChecked
    Update-CommandPreview
  })
$rad_Session0.Add_Checked({ Update-CommandPreview })
$rad_PsExec.Add_Checked({ Update-CommandPreview })

$btn_Browse.Add_Click({
    $OpenFileDialog = New-Object Microsoft.Win32.OpenFileDialog
    $OpenFileDialog.Title = "Select an installer"
    $OpenFileDialog.Filter = "Installers and Scripts (*.msi;*.msp;*.exe;*.ps1;*.cmd;*.bat;*.vbs)|*.msi;*.msp;*.exe;*.ps1;*.cmd;*.bat;*.vbs|All Files (*.*)|*.*"
    $CurrentPath = $txt_FilePath.Text.Trim().Trim('"')
    if ($CurrentPath -and (Test-Path -LiteralPath (Split-Path -Path $CurrentPath -Parent) -ErrorAction SilentlyContinue)) {
      $OpenFileDialog.InitialDirectory = Split-Path -Path $CurrentPath -Parent
    }
    if ($OpenFileDialog.ShowDialog()) {
      $txt_FilePath.Text = $OpenFileDialog.FileName
    }
  })

$btn_CommandLine_Copy.Add_Click({
    if ($txt_CommandLine.Text) {
      [System.Windows.Clipboard]::SetText($txt_CommandLine.Text)
      Write-Host "Copied to Clipboard: [$($txt_CommandLine.Text)]"
      Set-StatusBar -Text "Command line copied to the clipboard"
    }
  })

#### Run ####
$btn_Run.Add_Click({ Start-SystemRun })
$btn_Stop.Add_Click({ Stop-SystemRun })

#### Keyboard Shortcuts ####
# Preview so the shortcuts work whichever control has focus. Each one only acts when its button is enabled,
# so a shortcut can't start a second run or load history while an installer is running.
$formRunAsSystem.Add_PreviewKeyDown({
    $Ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0

    if ($_.Key -eq 'F5' -or ($Ctrl -and $_.Key -eq 'Return')) {
      if ($btn_Run.IsEnabled) { Start-SystemRun }
      $_.Handled = $true
    }
    elseif ($Ctrl -and $_.Key -eq 'O') {
      if ($btn_Browse.IsEnabled) { $btn_Browse.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
      $_.Handled = $true
    }
    elseif ($Ctrl -and $_.Key -eq 'L') {
      if ($btn_HistoryLoad.IsEnabled) { & $Script:HistoryLoadHandler }
      $_.Handled = $true
    }
  })

$btn_OpenLog.Add_Click({
    if ($Script:LastLogPath -and (Test-Path -LiteralPath $Script:LastLogPath)) {
      Invoke-Item -LiteralPath $Script:LastLogPath
    }
    else {
      [System.Windows.MessageBox]::Show("The log file was not found:`n$($Script:LastLogPath)", "Run As SYSTEM", "OK", "Information") | Out-Null
    }
  })

$btn_OpenFolder.Add_Click({
    if ($Script:LastWorkingDirectory -and (Test-Path -LiteralPath $Script:LastWorkingDirectory)) {
      Invoke-Item -LiteralPath $Script:LastWorkingDirectory
    }
  })

#### History ####
$lsbox_History.Add_SelectionChanged({ Update-HistoryButtons })

$Script:HistoryLoadHandler = {
  $Item = $lsbox_History.SelectedItem
  if ($Item) { Import-HistoryEntry -Entry $Item.Tag }
}
$btn_HistoryLoad.Add_Click($Script:HistoryLoadHandler)
$lsbox_History.Add_MouseDoubleClick($Script:HistoryLoadHandler)

$btn_HistoryCopy.Add_Click({
    $Item = $lsbox_History.SelectedItem
    if ($Item) { Copy-HistoryEntry -Entry $Item.Tag }
  })

$btn_HistoryClear.Add_Click({
    $Answer = [System.Windows.MessageBox]::Show("Clear the run history?", "Run As SYSTEM", "YesNo", "Question")
    if ($Answer -eq 'Yes') {
      Save-History -Entries @()
      Update-HistoryList
    }
  })

#### Menu Items ####
$MenuItem_OpenAppData.Add_Click({
    if (-not (Test-Path $Script:AppDataPath)) {
      New-Item -ItemType Directory -Path $Script:AppDataPath -Force | Out-Null
    }
    Invoke-Item -Path $Script:AppDataPath
  })

$MenuItem_TaskScheduler.Add_Click({
    Start-Process -FilePath "$env:SystemRoot\System32\taskschd.msc"
  })

$MenuItem_Install.Add_Click({ Install-RightClickMenu })

$MenuItem_Uninstall.Add_Click({ Uninstall-RightClickMenu })

$MenuItem_Open_RCM.Add_Click({
    if (-not (Test-Path $Script:RightClickMenuFolderPath)) {
      New-Item -ItemType Directory -Path $Script:RightClickMenuFolderPath -Force | Out-Null
    }
    Invoke-Item -Path $Script:RightClickMenuFolderPath
  })

$MenuItem_GitHub.Add_Click({
    # Open Github Project Page
    Start-Process "https://github.com/$($Script:GitHubRepo)"
  })

$MenuItem_About.Add_Click({
    # Open Blog
    Start-Process "https://michaeltheadmin.com"
  })

$MenuItem_CheckForUpdates.Add_Click({
    # Manual check. User-initiated, so running the shared scriptblock synchronously is fine.
    Write-Host "Checking for updates: [$($Script:ReleasesApiUrl)]"
    try {
      $result = & $Script:TestForUpdate $Script:ReleasesApiUrl $Script:UpdateCheckHeaders $Script:ScriptVersion
      Write-Host "Update available: $($result.UpdateAvailable) | Installed [$($Script:ScriptVersion)] | Latest [$($result.LatestVersion)]"
      Show-UpdateAvailable -Result $result
      if (-not $result.UpdateAvailable) { Set-StatusBar -Text "You're running the latest version" }
    }
    catch {
      Write-Host "Update check failed: $($_.Exception.Message)"
      Set-StatusBar -Warning -Text "Update check failed: $($_.Exception.Message)"
    }
  })

$MenuItem_UpdateAvailable.Add_Click({
    # Open the download page for the newer release.
    if ($Script:LatestReleaseUrl) { Start-Process $Script:LatestReleaseUrl }
    else { Start-Process $Script:ReleasesPageUrl }
  })

#### Title Bar Handlers ####
$titlebar.Add_MouseLeftButtonDown({
    try { $formRunAsSystem.DragMove() } catch { }
  })

$titlebar_Minimize.Add_Click({
    $formRunAsSystem.WindowState = [System.Windows.WindowState]::Minimized
  })

$titlebar_Close.Add_Click({
    $formRunAsSystem.Close()
  })

#endregion Event Handlers

# Set the PowerShell Window Title
$Host.UI.RawUI.WindowTitle = "Run As SYSTEM"

#Show the WPF Window
$formRunAsSystem.WindowStartupLocation = "CenterScreen"
$formRunAsSystem.ShowDialog() | Out-Null
