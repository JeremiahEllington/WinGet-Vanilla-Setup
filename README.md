# WinGet-Vanilla-Setup

PowerShell-only bootstrap to install WinGet (Microsoft App Installer) on a vanilla Windows host. Handles common prerequisites, prefers online install, and supports an optional offline mode if you stage packages.

## What this does
- Enables TLS 1.2 for downloads
- Ensures Microsoft.VCLibs and Microsoft.UI.Xaml frameworks
- Installs App Installer (winget) via MSIX bundle
- Verifies winget is available and prints version
- Optionally installs packages from a simple text file

## Requirements
- Run PowerShell as Administrator
- Windows 10 1809+ or Windows 11
- Internet access, unless using offline artifacts

## Quick start (online)
Run this in an elevated PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
irm https://raw.githubusercontent.com/JeremiahEllington/WinGet-Vanilla-Setup/main/Install-WinGet.ps1 | iex
```

## Offline mode
If your host has restricted internet, you can pre-stage the following files into an `offline` folder beside the script:

- `Microsoft.VCLibs.x64.14.00.Desktop.appx`
- `Microsoft.UI.Xaml.2.8.appx` (or the version you have)
- `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle`

Then run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Install-WinGet.ps1 -UseOffline
```

## Installing apps with winget
Add package IDs (one per line) to `packages-example.txt`, e.g.:

```
Microsoft.PowerToys
Microsoft.VisualStudioCode
Git.Git
7zip.7zip
```

Then run the script again. It will detect the file and run `winget install` for each ID.

## Troubleshooting
- Ensure you're in an elevated session.
- If MSIX install fails online, try `-UseOffline` with pre-downloaded artifacts.
- Some environments block Microsoft Store. The script tries direct MSIX first, then a fallback.

## License
MIT
