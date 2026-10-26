<#
Start the Smart Attendance Kiosk automatically when this user signs in to Windows (kiosk PC).
Adds a shortcut to run.bat in the Startup folder; -Remove takes it away again.

    powershell -ExecutionPolicy Bypass -File scripts\install_autostart.ps1
    powershell -ExecutionPolicy Bypass -File scripts\install_autostart.ps1 -Remove
#>
param([switch]$Remove)

$startup  = [Environment]::GetFolderPath('Startup')
$shortcut = Join-Path $startup 'Smart Attendance Kiosk.lnk'

if ($Remove) {
    if (Test-Path $shortcut) { Remove-Item $shortcut; 'Removed: the kiosk will no longer start at sign-in.' }
    else { 'Nothing to remove.' }
    return
}

$root = Split-Path -Parent $PSScriptRoot
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcut)
$lnk.TargetPath = Join-Path $root 'run.bat'
$lnk.WorkingDirectory = $root
$lnk.WindowStyle = 7   # start minimised
$lnk.Description = 'Start the Smart Attendance Kiosk'
$lnk.Save()
"Added: the kiosk starts when you sign in ($shortcut)."
