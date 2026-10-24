<#
.SYNOPSIS
    Installs the app in this folder silently.

.DESCRIPTION
    Runs the app's .msi or .exe from this script's folder with no prompts, and
    exits with the installer's exit code. Intune reads the exit code to tell
    whether the install worked: 0 is success and 3010 is success that needs a
    restart.

    Intune install command:
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1

    The log is saved as <installer name>-install.log in
    C:\ProgramData\Microsoft\IntuneManagementExtension\Logs, which Intune's
    Collect diagnostics includes. An .msi also writes its own detailed
    <installer name>-msi-install.log there.

    Build-IntuneWin.ps1 copies this file from input\ into each app folder that
    has no install script of its own. Edit the copy in an app folder to change
    that app only, or this file in input\ to change the starting point for apps
    packaged from now on.
#>

# ---- Settings ----

# The installer to run, relative to this folder. Leave it empty to use the only
# .msi in this folder, or if there isn't exactly one, the only .exe.
$Installer = ''

# Switches that make an .exe install silently. They depend on the tool the
# installer was made with, so check the app's documentation if /S doesn't work:
#   NSIS: /S          Inno Setup: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
#   InstallShield: /s /v"/qn"          WiX bundles and many others: /quiet /norestart
$ExeArguments = '/S'

# Extra arguments for an .msi, such as public properties: 'ALLUSERS=1 ADDLOCAL=ALL'
# It always runs with /qn /norestart and a log.
$MsiArguments = ''

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
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
Start-Transcript -Path (Join-Path $logFolder "$logName-install.log") -Append | Out-Null

try {
    if (-not $installerFile) {
        if ($Installer) { throw "Installer not found: $(Join-Path $PSScriptRoot $Installer)" }
        throw "Couldn't tell which file in $PSScriptRoot is the installer. Set `$Installer at the top of $PSCommandPath."
    }
    if ($installerFile.Extension -eq '.msi') {
        $msiLog = Join-Path $logFolder "$logName-msi-install.log"
        $exitCode = Invoke-Program 'msiexec.exe' "/i `"$($installerFile.FullName)`" /qn /norestart /l*v `"$msiLog`" $MsiArguments".Trim()
    } else {
        $exitCode = Invoke-Program $installerFile.FullName $ExeArguments
    }
} catch {
    Write-Host "FAILED: $($_.Exception.Message)"
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
