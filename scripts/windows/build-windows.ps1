[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'dist\windows'
}
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$goCommand = Get-Command go.exe -ErrorAction SilentlyContinue
$goPath = if ($null -ne $goCommand) { $goCommand.Source } else { $null }
if ($null -eq $goPath) {
    $defaultGo = 'C:\Program Files\Go\bin\go.exe'
    if (Test-Path -LiteralPath $defaultGo) {
        $goPath = $defaultGo
    }
}
if ($null -eq $goPath) {
    throw 'Go 1.26 or newer is required. Install it with: winget install --id GoLang.Go --exact'
}

$goVersion = & $goPath version
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to run the Go toolchain.'
}

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$muxPath = Join-Path $outputPath 'codex-mux.exe'

Push-Location $projectRoot
try {
    & $goPath build -trimpath -ldflags '-s -w' -o $muxPath '.\cmd\codex-mux'
    if ($LASTEXITCODE -ne 0) {
        throw 'The Windows multiplexer build failed.'
    }
} finally {
    Pop-Location
}

Copy-Item -Force -LiteralPath (Join-Path $PSScriptRoot 'launch-router.ps1') -Destination (Join-Path $outputPath 'launch-router.ps1')
Copy-Item -Force -LiteralPath (Join-Path $PSScriptRoot 'launch-router.cmd') -Destination (Join-Path $outputPath 'launch-router.cmd')
Copy-Item -Force -LiteralPath (Join-Path $PSScriptRoot 'launch-native-menu.cmd') -Destination (Join-Path $outputPath 'launch-native-menu.cmd')
Copy-Item -Force -LiteralPath (Join-Path $PSScriptRoot 'open-manager.cmd') -Destination (Join-Path $outputPath 'open-manager.cmd')

$patcherPath = Join-Path $outputPath 'renderer-patcher'
New-Item -ItemType Directory -Force -Path $patcherPath | Out-Null
Copy-Item -Force -LiteralPath (Join-Path $PSScriptRoot 'patch-windows-runtime.mjs') -Destination (Join-Path $patcherPath 'patch-windows-runtime.mjs')
Copy-Item -Force -LiteralPath (Join-Path $projectRoot 'ui\windows-account-menu.js') -Destination (Join-Path $patcherPath 'windows-account-menu.js')
Copy-Item -Recurse -Force -LiteralPath (Join-Path $projectRoot 'node_modules') -Destination $patcherPath

Write-Host "Built Codex Subscription Router for Windows"
Write-Host "  Go:     $goVersion"
Write-Host "  Output: $outputPath"
Write-Host ""
Write-Host 'Launch it with dist\windows\launch-router.cmd'
Write-Host 'Or use dist\windows\launch-native-menu.cmd for the experimental native profile menu.'
