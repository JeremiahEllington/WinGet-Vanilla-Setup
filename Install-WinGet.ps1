#requires -Version 5.1
<#!
.SYNOPSIS
  Installs WinGet (App Installer) on a vanilla Windows host using PowerShell only.

.DESCRIPTION
  Handles common pre-reqs: TLS 1.2, winget-cli dependencies, Microsoft.VCLibs, UI.Xaml, and App Installer via MSIX/Appx.
  Prefers online acquisition from Microsoft endpoints. Includes offline-fallback hooks if you stage MSIX/Appx files.

.NOTES
  - Run in an elevated PowerShell session.
  - Supported: Windows 10 1809+ (build 17763+) and Windows 11. Older versions may require servicing packs.
  - Requires internet access unless you provide offline artifacts in the ./offline folder.

.PARAMETER UseOffline
  Use previously-downloaded packages from ./offline when available.

.PARAMETER Quiet
  Suppress most output.

.LINK
  https://github.com/JeremiahEllington/WinGet-Vanilla-Setup
#>
param(
  [switch]$UseOffline,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg) { if (-not $Quiet) { Write-Host "[INFO] $msg" -ForegroundColor Cyan } }
function Write-Warn($msg) { Write-Warning $msg }
function Write-Err($msg)  { Write-Error $msg }

# Ensure TLS 1.2 for web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Elevation check
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Write-Err "This script must be run as Administrator."
  exit 1
}

# Paths
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$OfflineDir = Join-Path $ScriptRoot 'offline'

function Test-WindowsVersion {
  $os = Get-CimInstance Win32_OperatingSystem
  $build = [int]$os.BuildNumber
  $isWin11 = [Environment]::OSVersion.Version.Major -ge 10 -and $build -ge 22000
  [pscustomobject]@{ Build=$build; IsWin11=$isWin11 }
}

function Get-WinGetPath {
  $paths = @(
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
    "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
  )
  foreach ($p in $paths) { if (Test-Path $p) { return $p } }
  $cmd = Get-Command winget -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  return $null
}

function Ensure-DeveloperMode {
  try {
    $reg = 'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    if (-not (Test-Path $reg)) { New-Item -Path $reg | Out-Null }
    Set-ItemProperty -Path $reg -Name 'AllowAllTrustedApps' -Type DWord -Value 1 -Force | Out-Null
    Write-Info 'Developer Mode (AllowAllTrustedApps) ensured.'
  } catch {
    Write-Warn "Could not set Developer Mode registry flag: $($_.Exception.Message)"
  }
}

function Add-AppxPackageSafe {
  param(
    [Parameter(Mandatory)] [string]$Path
  )
  Write-Info "Installing package: $([IO.Path]::GetFileName($Path))"
  Add-AppxPackage -Path $Path -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
}

function Install-Dependency-Packages {
  # Microsoft.VCLibs and UI.Xaml often required for App Installer
  $vcLibs = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00' -AllUsers -ErrorAction SilentlyContinue
  $uiXaml = Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.8' -AllUsers -ErrorAction SilentlyContinue

  if (-not $vcLibs) {
    if ($UseOffline -and (Test-Path (Join-Path $OfflineDir 'Microsoft.VCLibs.x64.14.00.Desktop.appx'))) {
      Add-AppxPackageSafe -Path (Join-Path $OfflineDir 'Microsoft.VCLibs.x64.14.00.Desktop.appx')
    } else {
      Write-Info 'Fetching Microsoft VCLibs from CDN...'
      $vcUrl = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
      $tmp = New-TemporaryFile
      Invoke-WebRequest -Uri $vcUrl -OutFile $tmp -UseBasicParsing
      Add-AppxPackageSafe -Path $tmp
    }
  } else { Write-Info 'Microsoft VCLibs already present.' }

  if (-not $uiXaml) {
    if ($UseOffline -and (Test-Path (Join-Path $OfflineDir 'Microsoft.UI.Xaml.2.8.appx'))) {
      Add-AppxPackageSafe -Path (Join-Path $OfflineDir 'Microsoft.UI.Xaml.2.8.appx')
    } else {
      Write-Info 'Fetching Microsoft.UI.Xaml 2.8 framework...'
      # Note: version may change. Using well-known aka.ms link
      $xamlUrl = 'https://aka.ms/Microsoft.UI.Xaml.2.8'
      $tmp = New-TemporaryFile
      Invoke-WebRequest -Uri $xamlUrl -OutFile $tmp -UseBasicParsing
      Add-AppxPackageSafe -Path $tmp
    }
  } else { Write-Info 'Microsoft.UI.Xaml already present.' }
}

function Install-AppInstaller {
  $winget = Get-WinGetPath
  if ($winget) {
    Write-Info "WinGet already installed at: $winget"
    return
  }

  Ensure-DeveloperMode

  if ($UseOffline -and (Test-Path (Join-Path $OfflineDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'))) {
    Add-AppxPackageSafe -Path (Join-Path $OfflineDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle')
    return
  }

  Write-Info 'Installing App Installer (winget) from Microsoft Store/aka.ms...'
  # Try direct msixbundle via aka.ms first
  try {
    $appInstallerUrl = 'https://aka.ms/getwinget'
    $tmp = New-TemporaryFile
    Invoke-WebRequest -Uri $appInstallerUrl -OutFile $tmp -UseBasicParsing
    Add-AppxPackageSafe -Path $tmp
    return
  } catch {
    Write-Warn "Direct MSIX install failed: $($_.Exception.Message)"
  }

  # Fallback: use App Installer package id via Store install (requires Store availability)
  try {
    Write-Info 'Attempting store-based install via Add-AppxPackage with Store link...'
    $storeUrl = 'https://aka.ms/Microsoft.AppInstaller'
    $tmp = New-TemporaryFile
    Invoke-WebRequest -Uri $storeUrl -OutFile $tmp -UseBasicParsing
    Add-AppxPackageSafe -Path $tmp
  } catch {
    throw "Failed to install App Installer (winget). Consider offline mode with pre-downloaded packages in ./offline. Error: $($_.Exception.Message)"
  }
}

function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}

function Test-WinGetWorking {
  Refresh-Path
  $wg = Get-WinGetPath
  if (-not $wg) { throw 'winget.exe not found after installation.' }
  Write-Info "winget found: $wg"
  & $wg --version
}

function Install-FromPackagesList {
  param(
    [string]$PackagesFile = (Join-Path $ScriptRoot 'packages-example.txt')
  )
  if (-not (Test-Path $PackagesFile)) { return }
  $wg = Get-WinGetPath
  if (-not $wg) { return }
  Write-Info "Installing packages from: $PackagesFile"
  Get-Content $PackagesFile |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object {
      $pkg = $_.Trim()
      if (-not $pkg) { return }
      Write-Info "winget install $pkg"
      & $wg install --id $pkg --silent --accept-source-agreements --accept-package-agreements
      if ($LASTEXITCODE -ne 0) { Write-Warn "Failed to install $pkg" }
    }
}

# Main
$ver = Test-WindowsVersion
Write-Info "Windows Build: $($ver.Build) | Windows 11: $($ver.IsWin11)"
Install-Dependency-Packages
Install-AppInstaller
Test-WinGetWorking
Install-FromPackagesList

Write-Info 'WinGet setup completed.'
