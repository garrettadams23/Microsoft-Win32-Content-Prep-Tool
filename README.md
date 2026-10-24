# Microsoft Win32 Content Prep Tool

Manage Windows Apps (.intunewin) with Intune

[Version 1.8.7](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/tag/v1.8.7)

[See release notes for more information.](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool/releases)

Use the Microsoft Win32 Content Prep Tool to pre-process Windows Classic apps. The packaging tool converts application installation files into the .intunewin format. The packaging tool also detects the parameters required by Intune to determine the application installation state. After you use this tool on your apps, you will be able to upload and assign the apps in the Microsoft Intune console.

## Packaging apps with Build-IntuneWin

`Build-IntuneWin.ps1` packages every app in the [`input`](input) folder into a .intunewin file in the [`output`](output) folder.

1. Put each app's setup files in its own folder under `input`, for example `input\7-Zip\7z2408-x64.msi`. Everything in an app's folder goes into its package, so keep only that app's files there.
2. Double-click `Start-Packaging.bat`. When every app is packaged, it opens the `output` folder.
3. Upload `output\<app folder name>.intunewin` to Intune.

The script picks each app's setup file from the files directly in its folder: a PSAppDeployToolkit launcher (`Invoke-AppDeployToolkit.exe` or `Deploy-Application.exe`), then `install.ps1`, `install.cmd` or `install.bat`, then the only `.msi`, then the only `.exe`. If it can't pick one, `Start-Packaging.bat` asks you which file to use.

You can also run `.\Build-IntuneWin.ps1` from PowerShell. It skips any app whose setup file it can't pick, unless you name the file with `-SetupFile` or add `-PromptForSetupFile`:

```powershell
.\Build-IntuneWin.ps1 -App 7-Zip -SetupFile 7z2408-x64.msi
```

`-App` on its own packages only the apps you name. Run `Get-Help .\Build-IntuneWin.ps1 -Detailed` for all options.

Only the README in `input` and `output` and the two scripts in `input` are committed to git (see `.gitignore`), so installers and packages stay out of the repo.

### Install and uninstall scripts

[`input\install.ps1`](input/install.ps1) and [`input\uninstall.ps1`](input/uninstall.ps1) install and uninstall an app's `.msi` or `.exe` silently. When an app folder has no install script or PSAppDeployToolkit launcher of its own, packaging copies both into it, so `install.ps1` becomes the setup file. They're only copied when the app's installer is the only `.msi` or the only `.exe` in its folder, scripts already in an app folder are never replaced, and nothing is copied when you use `-SetupFile`. Delete them from `input` if you don't want them added.

In Intune, use these commands for the app:

- Install command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1`
- Uninstall command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1`

Each script exits with the installer's exit code, so Intune's default return codes apply (3010 means a restart is needed), and logs to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<installer name>-install.log` or `-uninstall.log`, which Intune's **Collect diagnostics** includes. `uninstall.ps1` treats an app that isn't installed as uninstalled.

The settings at the top of each script cover most apps:

- `$Installer`: the file to run. By default, the only `.msi` in the folder, or the only `.exe`.
- `$ExeArguments` in `install.ps1`: the switches that make an `.exe` install silently, `/S` by default. They depend on the tool the installer was made with, so check them for each `.exe`. The script lists the common ones.
- `$MsiArguments` in `install.ps1`: extra `msiexec` arguments, such as public properties.
- `$DisplayName` in `uninstall.ps1`: the app's name in **Settings > Apps**. By default, an `.msi` is uninstalled with `msiexec /x` and the `.msi` itself, and an `.exe` with the uninstall command of the app whose name starts with the product name in the `.exe`'s file properties. If more than one app matches, nothing is uninstalled.
- `$ExeArguments` in `uninstall.ps1`: the switches added to an `.exe` app's uninstall command, unless it registered a silent one of its own.

Edit the copy in an app folder to change one app, then package it again. Edit the ones in `input` to change what new app folders get.

Because the setup file is `install.ps1` rather than the `.msi`, Intune doesn't fill in the MSI's product code, so add a detection rule yourself, for example **MSI** with the product code, or a file or registry rule.

**Prerequisites**

.NET Framework 4.7.2

Before you install and use the Microsoft Win32 Content Prep Tool, you **must**:

- Review the [Microsoft License Terms for Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool/blob/master/Microsoft%20License%20Terms%20For%20Win32%20Content%20Prep%20Tool.pdf). Print and retain a copy of the license terms for your records. By downloading and using Microsoft Win32 Content Prep Tool, you agree to such license terms. If you do not accept them, do not use the software.
- Review the [Privacy and personal data in Intune](https://learn.microsoft.com/mem/intune/protect/privacy-personal-data) for information on the privacy policy of the Microsoft Win32 Content Prep Tool.

Sample commands to use for the Microsoft Win32 Content Prep Tool:

- IntuneWinAppUtil -v
  - This will show the tool version (Only available starting version 1.8.2).
- IntuneWinAppUtil -h
  - This will show usage information for the tool.
- IntuneWinAppUtil -c <setup_folder> -s <source_setup_file> -o <output_folder> <-q>
  - This will generate the .intunewin file from the specified source folder and setup file.
  - For MSI setup file, this tool will retrieve required information for Intune.
  - If -a is specified, all catalog files in that folder will be bundled into the .intunewin file.
  - If -q is specified, it will be in quiet mode. If the output file already exists, it will be overwritten.
  - Also, if the output folder does not exist, it will be created automatically.
- IntuneWinAppUtil
  - If no parameter is specified, this tool will guide you to input the required parameters step by step.

Command-line parameters available

- -h Help
- -v Tool version (Only available starting version 1.8.2).
- -c <setup_folder> Setup folder for all setup files. All files in this folder will be compressed into .intunewin file.
  - Only the setup files for this app should be in this folder.
- -s <setup_file> Setup file (e.g. setup.exe or setup.msi).
- -o <output_file> Output folder for the generated .intunewin file.
- -a <catalog_folder> Catalog folder for all catalog files. All files in this folder will be treated as catalog file for Win10 S mode.
- -q If specified, it will be in quiet mode. In quiet mode, there are no interactive prompts and existing content in the output folder (-o) will be overwritten if it exists. Also, if the output folder does not exist, it will be created automatically.
- -qq If specified, all conditions of -q will be applied and there will be no console output. If both -q and -qq are specified, the conditions of -qq will be enforced.

**Note: The generated .intunewin file contains all compressed and encrypted source setup files and the encryption information to decrypt it. Please keep it in the safe place as your source setup files.**
