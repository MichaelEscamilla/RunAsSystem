# Screenshots for the README and docs/, taken by New-Screenshots.ps1.
#
# Each entry in Screenshots launches RunAsSystem.ps1 with File loaded, runs its Steps, and saves the
# window to Output (relative to the repo root). History starts empty for every screenshot.
#
# Step actions (one per step, controls are named by their XAML Name):
#   @{ Click = 'btn_Run' }                                  Press a button, menu item, radio button or checkbox
#   @{ Select = 'cmb_Ps1Host'; Item = 'PowerShell 7' }      Pick a combo box item by its text (wildcards allowed)
#   @{ Check = 'chk_Log'; Value = $false }                  Set a checkbox (Value defaults to $true) or select a radio button
#   @{ SetText = 'txt_Arguments'; Value = '/S' }            Replace a text box's text
#   @{ Expand = 'MenuItem_Tools' }                          Open a menu or combo box; the capture then includes its popup
#   @{ Hover = 'lsbox_History'; Item = 0 }                  Move the mouse over a control, or over item N of a list
#   @{ WaitForResult = 60 }                                 Wait up to N seconds for a run to finish (an exit code, Stopped or Error)
#   @{ WaitFor = 'btn_Stop'; Visible = $true }              Wait for a control to appear (Visible) or its text to match a regex (Match)
#   @{ Dialog = 'Yes' }                                     Press a button in the app's message box
#   @{ Wait = 1.5 }                                         Pause for N seconds
#
# Other keys:
#   Arguments      Pre-fills ArgumentList (the app's -Arguments parameter)
#   Installs       The MSI ProductCode the run installs. The screenshot is skipped unless -AllowInstall is used or
#                  if the product is already installed, and the product is uninstalled after the capture.
#   AfterCapture   Steps run after the capture, e.g. to stop a run that's still going
#   ScriptVersion  Launch a temp copy of the script with this version, so Update Available appears
#
# Manual screenshots (not automated): the Explorer right-click menu (docs/right-click-menu.md).
@{
    # Downloads and Fixtures are written here, so the screenshots show short, clean paths
    FixtureFolder = 'C:\RunAsSystem\Files'

    # Real installers, downloaded once and checked against the hash. To update one, change the URL and the hash:
    #   (Get-FileHash <file>).Hash
    Downloads     = @(
        @{
            File   = '7z2604-x64.msi'
            Url    = 'https://github.com/ip7z/7zip/releases/download/26.04/7z2604-x64.msi'
            Sha256 = '0B01334A418654293513449F61D6BFC99E5196CA371E3C3DC961EDA57CD535C6'
        }
        # A WiX Burn bundle, which takes a log path with /log. The versioned URL, not aka.ms, which always points at the latest.
        @{
            File   = 'VC_redist.x64.exe'
            Url    = 'https://download.visualstudio.microsoft.com/download/pr/990c720a-46ce-4dc7-87b9-c2eb615d34b9/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe'
            Sha256 = 'CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B'
        }
    )

    # Demo files, written fresh on every run. They only echo text and exit with a chosen code.
    Fixtures      = @(
        @{
            File    = 'Install-ContosoApp.cmd'
            Content = @'
@echo off
echo Installing Contoso App 4.2
echo Copying files... done
echo Registering services... done
echo A restart is required to finish the install.
exit /b 3010
'@
        }
        @{
            File    = 'Install-ContosoAgent.cmd'
            Content = @'
@echo off
echo Installing Contoso Agent 2.1
echo ERROR: The Contoso Agent service could not be registered.
exit /b 1603
'@
        }
        @{
            File    = 'Install-ContosoSuite.cmd'
            Content = @'
@echo off
echo Installing Contoso Suite 7.0
for /l %%i in (1,1,120) do (
  echo Installing component %%i of 120...
  ping -n 2 127.0.0.1 >nul
)
exit /b 0
'@
        }
        @{
            File    = 'Install-ContosoApp.ps1'
            Content = @'
param (
    [string]$Mode = 'Install',
    [string[]]$Features = @('Core')
)

Write-Output "Contoso App 4.2: $Mode ($($Features -join ', '))"
Start-Sleep -Seconds 1
Write-Output 'Contoso App installed.'
exit 0
'@
        }
    )

    Screenshots   = @(
        # README: a finished MSI install
        @{
            Name     = 'main'
            Output   = 'Images/main.png'
            File     = '7z2604-x64.msi'
            Installs = '{23170F69-40C1-2702-2604-000001000000}'
            Steps    = @(
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 180 }
            )
        }

        # docs/file-types.md
        @{
            Name      = 'file-types-msi'
            Output    = 'Images/file-types-msi.png'
            File      = '7z2604-x64.msi'
            Arguments = 'ALLUSERS=1 /norestart'
        }
        @{
            Name      = 'file-types-ps1'
            Output    = 'Images/file-types-ps1.png'
            File      = 'Install-ContosoApp.ps1'
            Arguments = "-Mode Install -Features 'Core','Reports'"
            Steps     = @(
                @{ Select = 'cmb_Ps1Invoke'; Item = '-Command' }
            )
        }
        @{
            Name   = 'file-types-tools-menu'
            Output = 'Images/file-types-tools-menu.png'
            Steps  = @(
                @{ Expand = 'MenuItem_Tools' }
            )
        }
        @{
            Name      = 'file-types-variables'
            Output    = 'Images/file-types-variables.png'
            File      = 'VC_redist.x64.exe'
            Arguments = '/install /quiet /norestart /log "{LogFile}"'
        }

        # docs/run-modes.md
        @{
            Name   = 'run-modes-current-user'
            Output = 'Images/run-modes-current-user.png'
            File   = 'Install-ContosoApp.cmd'
            Steps  = @(
                @{ Click = 'rad_CurrentUser' }
            )
        }

        # docs/results.md
        @{
            Name   = 'results-3010'
            Output = 'Images/results-3010.png'
            File   = 'Install-ContosoApp.cmd'
            Steps  = @(
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 60 }
            )
        }
        @{
            Name   = 'results-failure'
            Output = 'Images/results-failure.png'
            File   = 'Install-ContosoAgent.cmd'
            Steps  = @(
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 60 }
            )
        }
        @{
            Name         = 'results-running'
            Output       = 'Images/results-running.png'
            File         = 'Install-ContosoSuite.cmd'
            Steps        = @(
                @{ Click = 'btn_Run' }
                @{ WaitFor = 'txtblk_Stdout'; Match = 'component [3-9]'; Timeout = 60 }
            )
            AfterCapture = @(
                @{ Click = 'btn_Stop' }
                @{ Dialog = 'Yes' }
                @{ WaitForResult = 60 }
            )
        }

        # docs/history.md: three runs, then hover over the newest entry
        @{
            Name   = 'history'
            Output = 'Images/history.png'
            File   = 'Install-ContosoAgent.cmd'
            Steps  = @(
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 60 }
                @{ SetText = 'txt_FilePath'; Value = 'C:\RunAsSystem\Files\Install-ContosoApp.ps1' }
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 60 }
                @{ SetText = 'txt_FilePath'; Value = 'C:\RunAsSystem\Files\Install-ContosoApp.cmd' }
                @{ Click = 'btn_Run' }
                @{ WaitForResult = 60 }
                @{ Hover = 'lsbox_History'; Item = 0 }
            )
        }

        # docs/updates.md
        @{
            Name          = 'updates'
            Output        = 'Images/updates.png'
            ScriptVersion = '2026.10.9.0'
            Steps         = @(
                @{ WaitFor = 'MenuItem_UpdateAvailable'; Visible = $true; Timeout = 30 }
            )
        }
    )
}
