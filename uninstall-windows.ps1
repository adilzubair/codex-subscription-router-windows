[CmdletBinding()]
param(
    [switch]$PurgeAccountState,
    [switch]$KeepRuntime,
    [switch]$KeepSource,
    [string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$installRoot = if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    Join-Path $env:LOCALAPPDATA 'Programs\Codex Subscription Router'
} else {
    [System.IO.Path]::GetFullPath($InstallDirectory)
}
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Runtime'
$sourceRoot = Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Source'
$muxPath = [System.IO.Path]::GetFullPath((Join-Path $installRoot 'codex-mux.exe'))
$runtimePrefix = [System.IO.Path]::GetFullPath($runtimeRoot).TrimEnd('\') + '\'

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    $executable = $_.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($executable)) { return }
    $full = [System.IO.Path]::GetFullPath($executable)
    if ($full.Equals($muxPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Subscription Router.lnk'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Subscription Router'
Remove-Item -Force -LiteralPath $desktopShortcut -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -LiteralPath $startMenu -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -LiteralPath $installRoot -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -LiteralPath "$installRoot.previous" -ErrorAction SilentlyContinue

if (-not $KeepRuntime) {
    Remove-Item -Recurse -Force -LiteralPath $runtimeRoot -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath (Join-Path $env:LOCALAPPDATA 'Codex Subscription Router') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath (Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Native') -ErrorAction SilentlyContinue
}
if ($PurgeAccountState) {
    Remove-Item -Recurse -Force -LiteralPath (Join-Path $env:USERPROFILE '.codex-mux') -ErrorAction SilentlyContinue
}
if (-not $KeepSource) {
    Set-Location $env:TEMP
    Remove-Item -Recurse -Force -LiteralPath $sourceRoot -ErrorAction SilentlyContinue
}

Write-Host 'Codex Subscription Router was removed.'
if (-not $PurgeAccountState) {
    Write-Host 'Connected subscription data was preserved in %USERPROFILE%\.codex-mux.'
}
