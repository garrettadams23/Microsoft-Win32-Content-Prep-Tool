<#
.SYNOPSIS
    Uninstalls the app in this folder silently.

.DESCRIPTION
    For an .msi, runs msiexec /x on the .msi in this folder. For an .exe, finds
    the app in the list in Settings > Apps and runs its uninstaller with no
    prompts. Exits with the uninstaller's exit code, which Intune reads to tell
    whether the uninstall worked. An app that isn't installed counts as
    uninstalled (exit code 0).

    Intune uninstall command:
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1

    The log is saved as <installer name>-uninstall.log in
    C:\ProgramData\Microsoft\IntuneManagementExtension\Logs, which Intune's
    Collect diagnostics includes. An .msi also writes its own detailed
    <installer name>-msi-uninstall.log there.

    Build-IntuneWin.ps1 copies this file from input\ into each app folder that
    has no install script of its own. Edit the copy in an app folder to change
    that app only, or this file in input\ to change the starting point for apps
    packaged from now on.
#>

# ---- Settings ----

# The installer the app was installed with, relative to this folder. Leave it
# empty to use the only .msi in this folder, or if there isn't exactly one, the
# only .exe.
$Installer = ''

# The app's name as shown in Settings > Apps, where * matches anything, for
# example '7-Zip*'. Leave it empty to uninstall with the .msi in this folder, or
# for an .exe, to use the product name in the .exe's file properties followed by
# *. If more than one app matches, nothing is uninstalled.
$DisplayName = ''

# Switches that make an .exe uninstaller silent, added to the app's uninstall
# command. They're not used when the app registered a silent uninstall command
# of its own, or was installed from an .msi.
#   NSIS: /S          Inno Setup: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
$ExeArguments = '/S'

# ---- End of settings ----

$ErrorActionPreference = 'Stop'

# 32-bit PowerShell on 64-bit Windows sees the 32-bit Program Files and registry,
# so start again in 64-bit PowerShell.
$powerShell64 = Join-Path $env:windir 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and (Test-Path -LiteralPath $powerShell64)) {
    & $powerShell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

# Returns the installer file, or $null if it can't be found.
function Find-Installer {
    if ($Installer) {
        $path = Join-Path $PSScriptRoot $Installer
        if (Test-Path -LiteralPath $path -PathType Leaf) { return Get-Item -LiteralPath $path }
        return $null
    }
    $files = @(Get-ChildItem -LiteralPath $PSScriptRoot -File)
    foreach ($extension in '.msi', '.exe') {
        $match = @($files | Where-Object { $_.Extension -eq $extension })
        if ($match.Count -eq 1) { return $match[0] }
    }
    return $null
}

# Returns the apps in Settings > Apps whose name matches a wildcard pattern.
function Find-InstalledApp([string] $Pattern) {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    return @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like $Pattern })
}

# Splits a command line such as "C:\Program Files\App\uninst.exe" /x into the
# program and its arguments.
function Split-CommandLine([string] $CommandLine) {
    if ($CommandLine -match '^\s*"([^"]+)"\s*(.*)$') { return $Matches[1], $Matches[2] }
    if ($CommandLine -match '^\s*(.+?\.exe)\s*(.*)$') { return $Matches[1], $Matches[2] }
    return $CommandLine.Trim(), ''
}

# Runs a program, waits for it and any programs it starts to finish, and returns
# its exit code.
function Invoke-Program([string] $FilePath, [string] $Arguments) {
    Write-Host "Running: `"$FilePath`" $Arguments"
    $startArgs = @{ FilePath = $FilePath; Wait = $true; PassThru = $true }
    if ($Arguments) { $startArgs.ArgumentList = $Arguments }
    $process = Start-Process @startArgs
    Write-Host "Exit code: $($process.ExitCode)"
    return $process.ExitCode
}

$installerFile = Find-Installer
$logName = if ($installerFile) { $installerFile.BaseName } else { 'app' }
$logFolder = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$msiLog = Join-Path $logFolder "$logName-msi-uninstall.log"
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
Start-Transcript -Path (Join-Path $logFolder "$logName-uninstall.log") -Append | Out-Null

try {
    if (-not $DisplayName -and $installerFile -and $installerFile.Extension -eq '.msi') {
        $exitCode = Invoke-Program 'msiexec.exe' "/x `"$($installerFile.FullName)`" /qn /norestart /l*v `"$msiLog`""
    } else {
        $pattern = $DisplayName
        if (-not $pattern -and $installerFile -and $installerFile.VersionInfo.ProductName) {
            $pattern = [System.Management.Automation.WildcardPattern]::Escape($installerFile.VersionInfo.ProductName.Trim()) + '*'
        }
        if (-not $pattern) {
            throw "Couldn't tell which app to uninstall. Set `$DisplayName at the top of $PSCommandPath."
        }

        $apps = Find-InstalledApp $pattern
        if ($apps.Count -gt 1) {
            throw "More than one app matches '$pattern': $(($apps | ForEach-Object { $_.DisplayName }) -join ', '). Set `$DisplayName at the top of $PSCommandPath to just one of them."
        }
        if ($apps.Count -eq 0) {
            Write-Host "No app matching '$pattern' is installed, so there's nothing to uninstall."
            $exitCode = 0
        } else {
            $app = $apps[0]
            Write-Host "Uninstalling $($app.DisplayName) $($app.DisplayVersion)"
            if ($app.WindowsInstaller -eq 1 -and $app.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $exitCode = Invoke-Program 'msiexec.exe' "/x $($app.PSChildName) /qn /norestart /l*v `"$msiLog`""
            } elseif ($app.QuietUninstallString) {
                $program, $arguments = Split-CommandLine $app.QuietUninstallString
                $exitCode = Invoke-Program $program $arguments
            } elseif ($app.UninstallString) {
                $program, $arguments = Split-CommandLine $app.UninstallString
                $exitCode = Invoke-Program $program "$arguments $ExeArguments".Trim()
            } else {
                throw "$($app.DisplayName) has no uninstall command in $($app.PSPath)."
            }
        }
    }
    # msiexec returns 1605 when the app isn't installed.
    if ($exitCode -eq 1605) {
        Write-Host "The app isn't installed, so there's nothing to uninstall."
        $exitCode = 0
    }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)"
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
