[CmdletBinding()]
param(
    [switch]$NoLaunch,
    [switch]$NoShortcuts,
    [switch]$SkipPrerequisites,
    [string]$SourceDirectory,
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repository = 'https://github.com/adilzubair/codex-subscription-router-windows.git'
$defaultSource = Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Source'
$defaultInstall = Join-Path $env:LOCALAPPDATA 'Programs\Codex Subscription Router'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $defaultSource } else { [System.IO.Path]::GetFullPath($SourceDirectory) }
$installRoot = if ([string]::IsNullOrWhiteSpace($InstallDirectory)) { $defaultInstall } else { [System.IO.Path]::GetFullPath($InstallDirectory) }

function Resolve-CommandPath {
    param([string]$Name, [string[]]$Fallbacks)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    foreach ($fallback in $Fallbacks) {
        if (Test-Path -LiteralPath $fallback) {
            return $fallback
        }
    }
    return $null
}

function Install-WingetPackage {
    param([string]$Id, [string]$Source = 'winget')

    $winget = Resolve-CommandPath -Name 'winget.exe' -Fallbacks @()
    if ($null -eq $winget) {
        throw "Windows Package Manager (winget) is required to install $Id."
    }
    Write-Host "Installing prerequisite: $Id"
    & $winget install --id $Id --exact --source $Source --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install $Id (exit code $LASTEXITCODE)."
    }
}

function Assert-SafeInstallPath {
    param([string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -eq $root -or $full.Length -lt ($root.Length + 8)) {
        throw "Refusing to use an unsafe install path: $full"
    }
}

function Stop-RouterProcesses {
    param([string]$InstalledPath)

    $runtimePrefix = ([System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Runtime'))).TrimEnd('\') + '\'
    $muxPath = [System.IO.Path]::GetFullPath((Join-Path $InstalledPath 'codex-mux.exe'))
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $executable = $_.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($executable)) { return }
        $full = [System.IO.Path]::GetFullPath($executable)
        if ($full.Equals($muxPath, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-Shortcut {
    param(
        [string]$Path,
        [string]$Target,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$Icon
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    if (-not [string]::IsNullOrWhiteSpace($Icon) -and (Test-Path -LiteralPath $Icon)) {
        $shortcut.IconLocation = "$Icon,0"
    }
    $shortcut.Save()
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This installer only supports Windows.'
}
Assert-SafeInstallPath -Path $installRoot

Write-Host 'Codex Subscription Router for Windows'
Write-Host '-------------------------------------'

if (-not $SkipPrerequisites) {
    if ($null -eq (Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue)) {
        Install-WingetPackage -Id '9PLM9XGG6VKS' -Source 'msstore'
    }
    if ($null -eq (Resolve-CommandPath -Name 'git.exe' -Fallbacks @('C:\Program Files\Git\cmd\git.exe'))) {
        Install-WingetPackage -Id 'Git.Git'
    }
    if ($null -eq (Resolve-CommandPath -Name 'go.exe' -Fallbacks @('C:\Program Files\Go\bin\go.exe'))) {
        Install-WingetPackage -Id 'GoLang.Go'
    }
    if ($null -eq (Resolve-CommandPath -Name 'npm.cmd' -Fallbacks @('C:\Program Files\nodejs\npm.cmd'))) {
        Install-WingetPackage -Id 'OpenJS.NodeJS.LTS'
    }
}

$git = Resolve-CommandPath -Name 'git.exe' -Fallbacks @('C:\Program Files\Git\cmd\git.exe')
$npm = Resolve-CommandPath -Name 'npm.cmd' -Fallbacks @('C:\Program Files\nodejs\npm.cmd')
$go = Resolve-CommandPath -Name 'go.exe' -Fallbacks @('C:\Program Files\Go\bin\go.exe')
if ($null -eq $git -or $null -eq $npm -or $null -eq $go) {
    throw 'Git, Go, and Node.js/npm are required. Re-run without -SkipPrerequisites to install them.'
}

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    if (Test-Path -LiteralPath (Join-Path $sourceRoot '.git')) {
        $changes = & $git -C $sourceRoot status --porcelain
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the local source checkout.' }
        if (@($changes).Count -gt 0) {
            throw "The source checkout has local changes. Preserve or remove them before updating: $sourceRoot"
        }
        Write-Host 'Updating source...'
        & $git -C $sourceRoot pull --ff-only origin main
        if ($LASTEXITCODE -ne 0) { throw 'The source update failed.' }
    } elseif (Test-Path -LiteralPath $sourceRoot) {
        throw "The source directory exists but is not a Git checkout: $sourceRoot"
    } else {
        Write-Host 'Downloading source...'
        & $git clone --depth 1 --branch main $repository $sourceRoot
        if ($LASTEXITCODE -ne 0) { throw 'The source download failed.' }
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'scripts\windows\build-windows.ps1'))) {
    throw "The selected source directory is incomplete: $sourceRoot"
}

Write-Host 'Installing pinned build dependency...'
Push-Location $sourceRoot
try {
    & $npm ci --ignore-scripts
    if ($LASTEXITCODE -ne 0) { throw 'npm dependency installation failed.' }

    $env:PATH = "$(Split-Path -Parent $go);$env:PATH"
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sourceRoot 'scripts\windows\build-windows.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'The Windows build failed.' }
} finally {
    Pop-Location
}

$buildRoot = Join-Path $sourceRoot 'dist\windows'
foreach ($required in @('codex-mux.exe', 'launch-native-menu.cmd', 'launch-router.ps1', 'renderer-patcher\patch-windows-runtime.mjs')) {
    if (-not (Test-Path -LiteralPath (Join-Path $buildRoot $required))) {
        throw "The build output is incomplete: $required"
    }
}

Stop-RouterProcesses -InstalledPath $installRoot
$staging = "$installRoot.staging-$PID"
$previous = "$installRoot.previous"
foreach ($temporary in @($staging, $previous)) {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -Recurse -Force -LiteralPath $temporary
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $installRoot) | Out-Null
Copy-Item -Recurse -Force -LiteralPath $buildRoot -Destination $staging

try {
    if (Test-Path -LiteralPath $installRoot) {
        Move-Item -LiteralPath $installRoot -Destination $previous
    }
    Move-Item -LiteralPath $staging -Destination $installRoot
} catch {
    if (-not (Test-Path -LiteralPath $installRoot) -and (Test-Path -LiteralPath $previous)) {
        Move-Item -LiteralPath $previous -Destination $installRoot
    }
    throw
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
    Sort-Object -Property Version -Descending | Select-Object -First 1
$icon = $null
if ($null -ne $package) {
    $packageIcon = Join-Path $package.InstallLocation 'app\resources\icon-chatgpt.ico'
    if (Test-Path -LiteralPath $packageIcon) {
        $icon = Join-Path $installRoot 'codex-router.ico'
        Copy-Item -Force -LiteralPath $packageIcon -Destination $icon
    }
}

if (-not $NoShortcuts) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Subscription Router'
    $powershell = Resolve-CommandPath -Name 'powershell.exe' -Fallbacks @((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    New-Shortcut -Path (Join-Path $desktop 'Codex Subscription Router.lnk') -Target (Join-Path $installRoot 'launch-native-menu.cmd') -Arguments '' -WorkingDirectory $installRoot -Icon $icon
    New-Shortcut -Path (Join-Path $startMenu 'Codex Subscription Router.lnk') -Target (Join-Path $installRoot 'launch-native-menu.cmd') -Arguments '' -WorkingDirectory $installRoot -Icon $icon
    New-Shortcut -Path (Join-Path $startMenu 'Subscription Manager.lnk') -Target (Join-Path $installRoot 'open-manager.cmd') -Arguments '' -WorkingDirectory $installRoot -Icon $icon
    New-Shortcut -Path (Join-Path $startMenu 'Update Router.lnk') -Target $powershell -Arguments "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $sourceRoot 'install-windows.ps1')`" -NoLaunch" -WorkingDirectory $sourceRoot -Icon $icon
    New-Shortcut -Path (Join-Path $startMenu 'Uninstall Router.lnk') -Target $powershell -Arguments "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $sourceRoot 'uninstall-windows.ps1')`"" -WorkingDirectory $sourceRoot -Icon $icon
}

Write-Host ''
Write-Host "Installed successfully: $installRoot"
Write-Host 'Your connected subscription data remains under %USERPROFILE%\.codex-mux.'
if (-not $NoLaunch) {
    Start-Process -FilePath (Join-Path $installRoot 'launch-native-menu.cmd') -WorkingDirectory $installRoot
}
