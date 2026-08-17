$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scripts = @(
    (Join-Path $projectRoot 'install-windows.ps1'),
    (Join-Path $projectRoot 'uninstall-windows.ps1'),
    (Join-Path $PSScriptRoot 'build-windows.ps1'),
    (Join-Path $PSScriptRoot 'launch-router.ps1')
)

$failed = $false
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $failed = $true
        foreach ($errorRecord in $errors) {
            Write-Error "${script}:$($errorRecord.Extent.StartLineNumber): $($errorRecord.Message)" -ErrorAction Continue
        }
    }
}
if ($failed) { exit 1 }
Write-Host "PowerShell syntax OK ($($scripts.Count) scripts)."
