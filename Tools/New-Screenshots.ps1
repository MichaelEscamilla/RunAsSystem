<#
.SYNOPSIS
    Takes the README and docs screenshots of RunAsSystem from the scenarios in Screenshots.psd1.

.DESCRIPTION
    For each scenario, launches RunAsSystem.ps1 with a demo file loaded, drives the window with UI Automation
    (controls are found by their XAML Name), and saves the window as a PNG with transparent rounded corners.

    - Fixtures (demo .cmd/.ps1 files) and Downloads (real installers, checked by SHA256) go to FixtureFolder,
      so screenshots show short, clean paths.
    - Your run history is set aside and every screenshot starts with an empty history. It's put back at the end,
      even if the script fails. If a previous run was interrupted, the next run restores it first.
    - Captures are scaled to the window's 100% size (1100x760), so images match whatever the display scale is.

    Must run elevated: the app is elevated, and Windows blocks UI Automation into an elevated window from a
    normal one. Works in Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER Name
    Only take the screenshots whose Name matches (wildcards allowed). Defaults to all.

.PARAMETER List
    Show the scenarios and their output files, without taking anything.

.PARAMETER AllowInstall
    Run scenarios that really install software (they have an Installs ProductCode). The product is
    uninstalled after the capture. Without this switch they're skipped.

.PARAMETER Refresh
    Download the installers again, even if they're already in FixtureFolder.

.PARAMETER NativeScale
    Keep the captured pixels at the display's scale instead of scaling them to 100%.

.PARAMETER PowerShellPath
    The PowerShell that runs RunAsSystem.ps1. Defaults to Windows PowerShell 5.1, the baseline.

.EXAMPLE
    .\Tools\New-Screenshots.ps1 -List

.EXAMPLE
    .\Tools\New-Screenshots.ps1 -Name results-*

.EXAMPLE
    .\Tools\New-Screenshots.ps1 -AllowInstall
    Take every screenshot, including the main image, which installs and then uninstalls 7-Zip.
#>
[CmdletBinding()]
param(
    [string[]]$Name = '*',
    [switch]$List,
    [switch]$AllowInstall,
    [switch]$Refresh,
    [switch]$NativeScale,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Screenshots.psd1'),
    [string]$PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppScriptPath = Join-Path $RepoRoot 'RunAsSystem.ps1'
$Config = Import-PowerShellDataFile -Path $ConfigPath
$Scenarios = @($Config.Screenshots | Where-Object { $Scenario = $_; @($Name | Where-Object { $Scenario.Name -like $_ }).Count -gt 0 })

if ($List) {
    $Scenarios | ForEach-Object {
        [PSCustomObject]@{
            Name     = $_.Name
            File     = $_.File
            Installs = [bool]$_.Installs
            Output   = $_.Output
        }
    } | Format-Table -AutoSize
    return
}

if ($Scenarios.Count -eq 0) { throw "No screenshots match: $($Name -join ', ')" }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell. RunAsSystem is elevated, and Windows blocks UI Automation into it from a normal window.'
}

#region Native helpers
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing

if (-not ('RunAsSystemScreenshots.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace RunAsSystemScreenshots {
    public static class Native {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
        [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
        [DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
        [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT rect, int size);

        // The visible frame in physical pixels, whatever this process's DPI awareness
        public static RECT GetFrame(IntPtr hwnd) {
            RECT rect;
            DwmGetWindowAttribute(hwnd, 9, out rect, Marshal.SizeOf(typeof(RECT)));
            return rect;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder name, int max);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, System.Text.StringBuilder text, int max);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc proc, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

        static string ClassOf(IntPtr hwnd) { System.Text.StringBuilder s = new System.Text.StringBuilder(256); GetClassName(hwnd, s, 256); return s.ToString(); }
        static string TextOf(IntPtr hwnd) { System.Text.StringBuilder s = new System.Text.StringBuilder(256); GetWindowText(hwnd, s, 256); return s.ToString().Replace("&", ""); }

        // Presses a button in a message box (a #32770 dialog) of the process. Posted, so a modal handler can't block this.
        public static bool ClickDialogButton(uint processId, string text) {
            foreach (IntPtr dialog in GetVisibleWindows(processId)) {
                if (ClassOf(dialog) != "#32770") { continue; }
                IntPtr found = IntPtr.Zero;
                EnumChildWindows(dialog, delegate (IntPtr child, IntPtr lParam) {
                    if (ClassOf(child) == "Button" && string.Equals(TextOf(child), text, StringComparison.OrdinalIgnoreCase)) { found = child; return false; }
                    return true;
                }, IntPtr.Zero);
                if (found != IntPtr.Zero) { PostMessage(found, 0x00F5, IntPtr.Zero, IntPtr.Zero); return true; } // BM_CLICK
            }
            return false;
        }

        // Every visible top-level window of a process: the main window plus any open popups (menus, dropdowns, tooltips)
        public static IntPtr[] GetVisibleWindows(uint processId) {
            List<IntPtr> windows = new List<IntPtr>();
            EnumWindows(delegate (IntPtr hwnd, IntPtr lParam) {
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid == processId && IsWindowVisible(hwnd)) { windows.Add(hwnd); }
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }
    }
}
'@
}

# Per-monitor aware, so UI Automation, the cursor and screen captures all use physical pixels.
# It fails when the host already set an awareness, which is fine if that's per-monitor too.
$null = [RunAsSystemScreenshots.Native]::SetProcessDpiAwarenessContext([IntPtr]-4)
if ([RunAsSystemScreenshots.Native]::GetAwarenessFromDpiAwarenessContext([RunAsSystemScreenshots.Native]::GetThreadDpiAwarenessContext()) -ne 2) {
    Write-Warning "This PowerShell isn't per-monitor DPI aware, so Hover and popup captures may be off at display scales other than 100%."
}

$UIA = [System.Windows.Automation.AutomationElement]
$TreeScope = [System.Windows.Automation.TreeScope]
#endregion

#region UI Automation
function Find-Element {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][string]$Id,
        [double]$Timeout = 10,
        [switch]$Optional
    )

    $Condition = New-Object System.Windows.Automation.PropertyCondition($UIA::AutomationIdProperty, $Id)
    $Deadline = (Get-Date).AddSeconds($Timeout)
    do {
        $Element = $Window.FindFirst($TreeScope::Descendants, $Condition)
        if ($Element) { return $Element }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $Deadline)

    if ($Optional) { return $null }
    throw "Control '$Id' not found. Was it renamed in RunAsSystem.ps1?"
}

function Get-Pattern {
    param($Element, $Pattern)
    $Out = $null
    if ($Element.TryGetCurrentPattern($Pattern, [ref]$Out)) { return $Out }
    return $null
}

function Get-ElementText {
    param($Element)
    $Value = Get-Pattern $Element ([System.Windows.Automation.ValuePattern]::Pattern)
    if ($Value) { return $Value.Current.Value }
    return $Element.Current.Name
}

function Get-ElementCenter {
    param($Element)
    $Rect = $Element.Current.BoundingRectangle
    if ($Rect.IsEmpty) { throw "Control '$($Element.Current.AutomationId)' has no position on screen." }
    return @([int]($Rect.X + $Rect.Width / 2), [int]($Rect.Y + $Rect.Height / 2))
}

function Invoke-MouseClick {
    param($Element)
    $X, $Y = Get-ElementCenter $Element
    [RunAsSystemScreenshots.Native]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 100
    [RunAsSystemScreenshots.Native]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) # left down
    [RunAsSystemScreenshots.Native]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) # left up
}

function Set-Foreground {
    param([IntPtr]$Hwnd)
    # Only when needed: an Alt press in the app itself would highlight its menu bar in the screenshot
    if ([RunAsSystemScreenshots.Native]::GetForegroundWindow() -eq $Hwnd) { return }
    # Windows only lets the foreground process hand focus over; a simulated Alt press counts as input and unlocks it
    [RunAsSystemScreenshots.Native]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [RunAsSystemScreenshots.Native]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [RunAsSystemScreenshots.Native]::SetForegroundWindow($Hwnd) | Out-Null
}

function Wait-RunResult {
    param($Window, [double]$Timeout)
    $ExitCode = Find-Element -Window $Window -Id 'txtblk_ExitCode'
    $History = Find-Element -Window $Window -Id 'lsbox_History'
    $ListItem = New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)
    $HistoryCount = $History.FindAll($TreeScope::Children, $ListItem).Count
    $Deadline = (Get-Date).AddSeconds($Timeout)
    # Give the click a moment to start the run, so a result from before it isn't taken as the answer
    Start-Sleep -Milliseconds 500
    while ((Get-Date) -lt $Deadline) {
        $Text = Get-ElementText $ExitCode
        if ($Text -notin '--', '...') {
            # The result shows before the history entry is added, so wait for that too
            $HistoryDeadline = (Get-Date).AddSeconds(10)
            while ($History.FindAll($TreeScope::Children, $ListItem).Count -le $HistoryCount -and (Get-Date) -lt $HistoryDeadline) { Start-Sleep -Milliseconds 200 }
            return $Text
        }
        Start-Sleep -Milliseconds 250
    }
    throw "The run didn't finish within $Timeout seconds."
}

function Invoke-Dialog {
    # A MessageBox is a plain Win32 dialog, so its button is pressed directly rather than through UI Automation
    param([int]$ProcessId, [string]$Button, [double]$Timeout = 10)
    $Deadline = (Get-Date).AddSeconds($Timeout)
    do {
        if ([RunAsSystemScreenshots.Native]::ClickDialogButton([uint32]$ProcessId, $Button)) { return }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $Deadline)
    throw "No message box with a '$Button' button appeared."
}

function Invoke-Step {
    param($App, [hashtable]$Step)

    $Window = $App.Element
    $Timeout = if ($Step.Timeout) { [double]$Step.Timeout } else { 10 }

    if ($Step.ContainsKey('Click')) {
        Write-Host "    Click $($Step.Click)"
        $Element = Find-Element -Window $Window -Id $Step.Click -Timeout $Timeout
        $Invoke = Get-Pattern $Element ([System.Windows.Automation.InvokePattern]::Pattern)
        $SelectionItem = Get-Pattern $Element ([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $Toggle = Get-Pattern $Element ([System.Windows.Automation.TogglePattern]::Pattern)
        if ($Invoke) { $Invoke.Invoke() }
        elseif ($SelectionItem) { $SelectionItem.Select() }
        elseif ($Toggle) { $Toggle.Toggle() }
        else { Invoke-MouseClick $Element } # e.g. a TextBlock with a click handler
    }
    elseif ($Step.ContainsKey('Select')) {
        Write-Host "    Select $($Step.Select) = $($Step.Item)"
        $Combo = Find-Element -Window $Window -Id $Step.Select -Timeout $Timeout
        $ExpandCollapse = Get-Pattern $Combo ([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        # A WPF combo box only creates its items once it has been opened
        $ExpandCollapse.Expand()
        Start-Sleep -Milliseconds 300
        $Items = $Combo.FindAll($TreeScope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
        $Item = @($Items) | Where-Object { $_.Current.Name -like $Step.Item } | Select-Object -First 1
        if (-not $Item) {
            $ExpandCollapse.Collapse()
            throw "'$($Step.Select)' has no item like '$($Step.Item)'. Items: $((@($Items) | ForEach-Object { $_.Current.Name }) -join ', ')"
        }
        (Get-Pattern $Item ([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
        $ExpandCollapse.Collapse()
    }
    elseif ($Step.ContainsKey('Check')) {
        $Value = if ($Step.ContainsKey('Value')) { [bool]$Step.Value } else { $true }
        Write-Host "    Check $($Step.Check) = $Value"
        $Element = Find-Element -Window $Window -Id $Step.Check -Timeout $Timeout
        $SelectionItem = Get-Pattern $Element ([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $Toggle = Get-Pattern $Element ([System.Windows.Automation.TogglePattern]::Pattern)
        if ($SelectionItem) { $SelectionItem.Select() }
        elseif ($Toggle) {
            $Want = if ($Value) { 'On' } else { 'Off' }
            while ("$($Toggle.Current.ToggleState)" -ne $Want) { $Toggle.Toggle() }
        }
        else { throw "'$($Step.Check)' isn't a checkbox or radio button." }
    }
    elseif ($Step.ContainsKey('SetText')) {
        Write-Host "    SetText $($Step.SetText) = $($Step.Value)"
        $Element = Find-Element -Window $Window -Id $Step.SetText -Timeout $Timeout
        (Get-Pattern $Element ([System.Windows.Automation.ValuePattern]::Pattern)).SetValue([string]$Step.Value)
    }
    elseif ($Step.ContainsKey('Expand')) {
        Write-Host "    Expand $($Step.Expand)"
        $Element = Find-Element -Window $Window -Id $Step.Expand -Timeout $Timeout
        $ExpandCollapse = Get-Pattern $Element ([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($ExpandCollapse) { $ExpandCollapse.Expand(); $App.Expanded.Add($ExpandCollapse) } else { Invoke-MouseClick $Element }
        # Popups are separate windows that PrintWindow doesn't include, so this capture comes from the screen
        $App.CaptureScreen = $true
    }
    elseif ($Step.ContainsKey('Hover')) {
        Write-Host "    Hover $($Step.Hover)$(if ($Step.ContainsKey('Item')) { " item $($Step.Item)" })"
        $Element = Find-Element -Window $Window -Id $Step.Hover -Timeout $Timeout
        if ($Step.ContainsKey('Item')) {
            $Items = @($Element.FindAll($TreeScope::Children, (New-Object System.Windows.Automation.PropertyCondition($UIA::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem))))
            if ($Items.Count -le $Step.Item) { throw "'$($Step.Hover)' has $($Items.Count) items, so there's no item $($Step.Item)." }
            $Element = $Items[$Step.Item]
        }
        $X, $Y = Get-ElementCenter $Element
        [RunAsSystemScreenshots.Native]::SetCursorPos($X, $Y) | Out-Null
        $App.Hovering = $true
    }
    elseif ($Step.ContainsKey('WaitForResult')) {
        Write-Host "    WaitForResult (up to $($Step.WaitForResult)s)"
        $Result = Wait-RunResult -Window $Window -Timeout ([double]$Step.WaitForResult)
        Write-Host "      Exit code: $Result"
    }
    elseif ($Step.ContainsKey('WaitFor')) {
        Write-Host "    WaitFor $($Step.WaitFor)"
        $Deadline = (Get-Date).AddSeconds($Timeout)
        while ($true) {
            # Collapsed WPF controls aren't in the automation tree, so finding the control means it's visible
            $Element = Find-Element -Window $Window -Id $Step.WaitFor -Timeout 0.5 -Optional
            $Done = $Element -and -not $Element.Current.IsOffscreen
            if ($Done -and $Step.Match) { $Done = (Get-ElementText $Element) -match $Step.Match }
            if ($Done) { break }
            if ((Get-Date) -gt $Deadline) { throw "Timed out waiting for '$($Step.WaitFor)'$(if ($Step.Match) { " to match '$($Step.Match)'" })." }
            Start-Sleep -Milliseconds 250
        }
    }
    elseif ($Step.ContainsKey('Dialog')) {
        Write-Host "    Dialog $($Step.Dialog)"
        Invoke-Dialog -ProcessId $App.Process.Id -Button $Step.Dialog -Timeout $Timeout
    }
    elseif ($Step.ContainsKey('Wait')) {
        Write-Host "    Wait $($Step.Wait)s"
        Start-Sleep -Milliseconds ([int]([double]$Step.Wait * 1000))
    }
    else {
        throw "Unknown step: $(($Step.Keys) -join ', ')"
    }
}
#endregion

#region Capture
function New-RoundedImage {
    # PrintWindow drops the alpha channel of a layered window, so the corners come back black; cut them out again
    param([System.Drawing.Bitmap]$Bitmap, [int]$Radius)

    $Width = $Bitmap.Width; $Height = $Bitmap.Height; $D = $Radius * 2
    $Out = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $Graphics = [System.Drawing.Graphics]::FromImage($Out)
    $Graphics.SmoothingMode = 'AntiAlias'
    $Path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $Path.AddArc(0, 0, $D, $D, 180, 90)
    $Path.AddArc($Width - $D, 0, $D, $D, 270, 90)
    $Path.AddArc($Width - $D, $Height - $D, $D, $D, 0, 90)
    $Path.AddArc(0, $Height - $D, $D, $D, 90, 90)
    $Path.CloseFigure()
    $Brush = New-Object System.Drawing.TextureBrush($Bitmap)
    $Graphics.FillPath($Brush, $Path)
    $Brush.Dispose(); $Path.Dispose(); $Graphics.Dispose()
    return $Out
}

function Resize-Image {
    param([System.Drawing.Bitmap]$Bitmap, [int]$Width, [int]$Height)

    $Out = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $Graphics = [System.Drawing.Graphics]::FromImage($Out)
    $Graphics.InterpolationMode = 'HighQualityBicubic'
    $Graphics.PixelOffsetMode = 'HighQuality'
    $Graphics.CompositingQuality = 'HighQuality'
    # TileFlipXY stops the bicubic filter from pulling transparent pixels in along the edges
    $Attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $Attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $Graphics.DrawImage($Bitmap, (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)), 0, 0, $Bitmap.Width, $Bitmap.Height, [System.Drawing.GraphicsUnit]::Pixel, $Attributes)
    $Attributes.Dispose(); $Graphics.Dispose()
    return $Out
}

function Save-WindowImage {
    param($App, [string]$Path)

    $Hwnd = $App.Hwnd
    $Scale = [RunAsSystemScreenshots.Native]::GetDpiForWindow($Hwnd) / 96
    $Frame = [RunAsSystemScreenshots.Native]::GetFrame($Hwnd)
    $Width = $Frame.Right - $Frame.Left; $Height = $Frame.Bottom - $Frame.Top

    # The window itself, drawn by Windows even where other windows cover it
    $Raw = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    $Graphics = [System.Drawing.Graphics]::FromImage($Raw)
    $Hdc = $Graphics.GetHdc()
    $null = [RunAsSystemScreenshots.Native]::PrintWindow($Hwnd, $Hdc, 2) # PW_RENDERFULLCONTENT, needed for WPF
    $Graphics.ReleaseHdc($Hdc); $Graphics.Dispose()
    $Image = New-RoundedImage -Bitmap $Raw -Radius ([int][Math]::Round(12 * $Scale)) # the window's outer CornerRadius
    $Raw.Dispose()

    if ($App.CaptureScreen) {
        # Lay the open popups over the window, copied from the screen, on a canvas big enough for both
        $Popups = @([RunAsSystemScreenshots.Native]::GetVisibleWindows($App.Process.Id) | Where-Object { $_ -ne $Hwnd } | ForEach-Object { [RunAsSystemScreenshots.Native]::GetFrame($_) } | Where-Object { ($_.Right - $_.Left) -gt 1 -and ($_.Bottom - $_.Top) -gt 1 })
        $Left = (@($Frame.Left) + @($Popups | ForEach-Object { $_.Left }) | Measure-Object -Minimum).Minimum
        $Top = (@($Frame.Top) + @($Popups | ForEach-Object { $_.Top }) | Measure-Object -Minimum).Minimum
        $Right = (@($Frame.Right) + @($Popups | ForEach-Object { $_.Right }) | Measure-Object -Maximum).Maximum
        $Bottom = (@($Frame.Bottom) + @($Popups | ForEach-Object { $_.Bottom }) | Measure-Object -Maximum).Maximum
        $Canvas = New-Object System.Drawing.Bitmap(($Right - $Left), ($Bottom - $Top), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $Graphics = [System.Drawing.Graphics]::FromImage($Canvas)
        $Graphics.DrawImageUnscaled($Image, $Frame.Left - $Left, $Frame.Top - $Top)
        foreach ($Popup in $Popups) {
            $Size = New-Object System.Drawing.Size(($Popup.Right - $Popup.Left), ($Popup.Bottom - $Popup.Top))
            $Graphics.CopyFromScreen($Popup.Left, $Popup.Top, $Popup.Left - $Left, $Popup.Top - $Top, $Size)
        }
        $Graphics.Dispose(); $Image.Dispose()
        $Image = $Canvas
    }

    if (-not $NativeScale -and $Scale -ne 1) {
        $Scaled = Resize-Image -Bitmap $Image -Width ([int][Math]::Round($Image.Width / $Scale)) -Height ([int][Math]::Round($Image.Height / $Scale))
        $Image.Dispose()
        $Image = $Scaled
    }

    $Folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Folder)) { $null = New-Item -ItemType Directory -Path $Folder -Force }
    $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $Size = "$($Image.Width)x$($Image.Height)"
    $Image.Dispose()
    return $Size
}
#endregion

#region App
function Start-App {
    param([hashtable]$Scenario, [string]$ScriptPath)

    $Arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$ScriptPath`"")
    if ($Scenario.File) {
        $FilePath = if ([System.IO.Path]::IsPathRooted($Scenario.File)) { $Scenario.File } else { Join-Path $Config.FixtureFolder $Scenario.File }
        $Arguments += '-FilePath', "`"$FilePath`""
    }
    if ($Scenario.Arguments) {
        # Windows command line rules: a quote inside the value is \"
        # -Arguments:"..." so a value starting with - (like -Mode Install) isn't read as a parameter name
        $Arguments += "-Arguments:`"$($Scenario.Arguments.Replace('"', '\"'))`""
    }
    $Process = Start-Process -FilePath $PowerShellPath -ArgumentList $Arguments -PassThru

    # Find the WPF window by its XAML Name; the hidden console window belongs to the same process
    $Condition = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $Process.Id)),
        (New-Object System.Windows.Automation.PropertyCondition($UIA::AutomationIdProperty, 'form1')))
    $Deadline = (Get-Date).AddSeconds(60)
    do {
        if ($Process.HasExited) { throw "RunAsSystem exited before its window opened (exit code $($Process.ExitCode))." }
        $Window = $UIA::RootElement.FindFirst($TreeScope::Children, $Condition)
        if (-not $Window) { Start-Sleep -Milliseconds 250 }
    } while (-not $Window -and (Get-Date) -lt $Deadline)
    if (-not $Window) { throw "RunAsSystem's window didn't open within 60 seconds." }

    $Hwnd = [IntPtr]$Window.Current.NativeWindowHandle
    # Same place every time, on the primary monitor, so popups are on screen for the capture
    $null = [RunAsSystemScreenshots.Native]::SetWindowPos($Hwnd, [IntPtr]::Zero, 80, 80, 0, 0, 0x0001 -bor 0x0004) # NOSIZE, NOZORDER
    Set-Foreground $Hwnd
    $null = Find-Element -Window $Window -Id 'btn_Run' -Timeout 30
    # Let the window finish loading: the file info, the command line and the update check at idle
    Start-Sleep -Seconds 2

    [PSCustomObject]@{
        Process       = $Process
        Element       = $Window
        Hwnd          = $Hwnd
        CaptureScreen = $false
        Hovering      = $false
        Expanded      = New-Object System.Collections.Generic.List[object]
    }
}

function Stop-App {
    param($App)

    if ($App.Process.HasExited) { return }
    # An open menu keeps the window from closing
    foreach ($ExpandCollapse in $App.Expanded) { try { $ExpandCollapse.Collapse() } catch {} }
    if ($App.Expanded.Count -gt 0) {
        # Collapse alone leaves a WPF menu in menu mode, which still refuses the close; Escape ends it
        Set-Foreground $App.Hwnd
        foreach ($i in 1..2) {
            [RunAsSystemScreenshots.Native]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero)
            [RunAsSystemScreenshots.Native]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 150
        }
    }
    try {
        (Get-Pattern $App.Element ([System.Windows.Automation.WindowPattern]::Pattern)).Close()
    }
    catch {}
    if (-not $App.Process.WaitForExit(15000)) {
        Write-Warning "RunAsSystem didn't close; ending it. A run still in progress leaves its task behind until the next launch."
        Stop-Process -Id $App.Process.Id -Force
    }
}

function Test-ProductInstalled {
    # Asks Windows Installer rather than the Uninstall key, which some MSIs (7-Zip) don't create
    param([string]$ProductCode)
    $Installer = New-Object -ComObject WindowsInstaller.Installer
    $State = $Installer.GetType().InvokeMember('ProductState', 'GetProperty', $null, $Installer, @($ProductCode))
    return ($State -eq 5) # INSTALLSTATE_DEFAULT
}
#endregion

#region Prepare files
if (-not (Test-Path -LiteralPath $Config.FixtureFolder)) { $null = New-Item -ItemType Directory -Path $Config.FixtureFolder -Force }

foreach ($Fixture in $Config.Fixtures) {
    # Here-strings take the .psd1 file's line endings; cmd wants CRLF
    $Content = ($Fixture.Content -replace '\r?\n', "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $Config.FixtureFolder $Fixture.File), $Content, (New-Object System.Text.UTF8Encoding($false)))
}

foreach ($Download in $Config.Downloads) {
    $Path = Join-Path $Config.FixtureFolder $Download.File
    if ($Refresh -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host "Downloading: [$($Download.Url)]"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Download.Url -OutFile $Path -UseBasicParsing
    }
    $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Hash -ne $Download.Sha256) {
        Remove-Item -LiteralPath $Path -Force
        throw "$($Download.File) doesn't match its Sha256 in $(Split-Path -Leaf $ConfigPath). Expected $($Download.Sha256), got $Hash. If the URL changed on purpose, update the hash."
    }
}
#endregion

#region Run
$HistoryPath = Join-Path $env:LOCALAPPDATA 'RunAsSystem\History.json'
$HistoryBackup = "$HistoryPath.screenshots-backup"
$HadHistory = $false
$TempFolder = Join-Path ([System.IO.Path]::GetTempPath()) "RunAsSystem-Screenshots-$PID"
$Results = New-Object System.Collections.Generic.List[object]

# A backup left by an interrupted run holds the real history, so put it back before taking a new one
if (Test-Path -LiteralPath $HistoryBackup) {
    Write-Warning "Restoring the history set aside by an interrupted run."
    Move-Item -LiteralPath $HistoryBackup -Destination $HistoryPath -Force
}
if (Test-Path -LiteralPath $HistoryPath) {
    Move-Item -LiteralPath $HistoryPath -Destination $HistoryBackup
    $HadHistory = $true
}

try {
    foreach ($Scenario in $Scenarios) {
        Write-Host "[$($Scenario.Name)] -> $($Scenario.Output)" -ForegroundColor Cyan
        if ($Scenario.Installs) {
            if (-not $AllowInstall) {
                Write-Host "  Skipped: installs software. Use -AllowInstall." -ForegroundColor Yellow
                $Results.Add([PSCustomObject]@{ Name = $Scenario.Name; Result = 'Skipped (needs -AllowInstall)'; Output = $Scenario.Output })
                continue
            }
            if (Test-ProductInstalled $Scenario.Installs) {
                Write-Host "  Skipped: $($Scenario.Installs) is already installed, so the result wouldn't be a clean install." -ForegroundColor Yellow
                $Results.Add([PSCustomObject]@{ Name = $Scenario.Name; Result = 'Skipped (already installed)'; Output = $Scenario.Output })
                continue
            }
        }

        if (Test-Path -LiteralPath $HistoryPath) { Remove-Item -LiteralPath $HistoryPath -Force }

        $ScriptPath = $AppScriptPath
        if ($Scenario.ScriptVersion) {
            # A temp copy with a lower version, so the update check offers the latest release. Never the repo file.
            if (-not (Test-Path -LiteralPath $TempFolder)) { $null = New-Item -ItemType Directory -Path $TempFolder }
            $ScriptPath = Join-Path $TempFolder 'RunAsSystem.ps1'
            $Text = [System.IO.File]::ReadAllText($AppScriptPath) -replace '(\$Script:ScriptVersion = ")[^"]+"', "`${1}$($Scenario.ScriptVersion)`""
            [System.IO.File]::WriteAllText($ScriptPath, $Text, (New-Object System.Text.UTF8Encoding($false)))
        }

        $App = $null
        try {
            $App = Start-App -Scenario $Scenario -ScriptPath $ScriptPath
            foreach ($Step in @($Scenario.Steps)) { if ($Step) { Invoke-Step -App $App -Step $Step } }
            # Park the mouse off the window, unless a step put it somewhere on purpose
            if (-not $App.Hovering) { [RunAsSystemScreenshots.Native]::SetCursorPos(0, 0) | Out-Null }
            Start-Sleep -Milliseconds 700
            $OutputPath = Join-Path $RepoRoot $Scenario.Output
            $Size = Save-WindowImage -App $App -Path $OutputPath
            Write-Host "  Saved $Size" -ForegroundColor Green
            $Results.Add([PSCustomObject]@{ Name = $Scenario.Name; Result = "Saved $Size"; Output = $Scenario.Output })
            # The image is already saved, so a failure here only matters for tidying up
            try { foreach ($Step in @($Scenario.AfterCapture)) { if ($Step) { Invoke-Step -App $App -Step $Step } } }
            catch { Write-Warning "AfterCapture: $($_.Exception.Message)" }
        }
        catch {
            Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
            $Results.Add([PSCustomObject]@{ Name = $Scenario.Name; Result = "Failed: $($_.Exception.Message)"; Output = $Scenario.Output })
        }
        finally {
            if ($App) { Stop-App $App }
            if ($Scenario.Installs -and (Test-ProductInstalled $Scenario.Installs)) {
                Write-Host "  Uninstalling $($Scenario.Installs)"
                $Uninstall = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $($Scenario.Installs) /qn /norestart" -Wait -PassThru
                if ($Uninstall.ExitCode -notin 0, 3010) { Write-Warning "Uninstall returned $($Uninstall.ExitCode). Remove it by hand." }
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $HistoryPath) { Remove-Item -LiteralPath $HistoryPath -Force }
    if ($HadHistory) { Move-Item -LiteralPath $HistoryBackup -Destination $HistoryPath -Force }
    if (Test-Path -LiteralPath $TempFolder) { Remove-Item -LiteralPath $TempFolder -Recurse -Force }
}

$Results | Format-Table -AutoSize -Wrap
#endregion
