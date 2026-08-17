[CmdletBinding()]
param(
    [switch]$ManagerOnly,
    [switch]$NoManager,
    [switch]$NativeMenu,
    [string]$PackageRoot,
    [string]$MuxPath,
    [ValidateRange(1, 65535)]
    [int]$ControlPort = 48123
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($MuxPath)) {
    $MuxPath = Join-Path $PSScriptRoot 'codex-mux.exe'
}

function Test-RouterHealth {
    param([int]$Port)
    try {
        $response = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$Port/v1/health" -TimeoutSec 1
        return $response.ok -eq $true
    } catch {
        return $false
    }
}

function Resolve-CodexPackageRoot {
    param([string]$ConfiguredRoot)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredRoot)) {
        $resolved = (Resolve-Path -LiteralPath $ConfiguredRoot).Path
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'AppxManifest.xml'))) {
            throw "The configured package root is not a Codex MSIX package: $resolved"
        }
        return $resolved
    }

    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($null -ne $package -and -not [string]::IsNullOrWhiteSpace($package.InstallLocation)) {
        return $package.InstallLocation
    }

    $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
    $candidate = Get-ChildItem -Directory -LiteralPath $windowsApps -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.Name -match '^OpenAI\.Codex_(?<Version>\d+(?:\.\d+){3})_[^_]+__2p2nqsd0c76g0$') {
                [PSCustomObject]@{ Directory = $_; Version = [version]$Matches.Version }
            }
        } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw 'The OpenAI Codex Windows package was not found. Install the ChatGPT desktop app from the Microsoft Store first.'
    }
    return $candidate.Directory.FullName
}

function Open-RouterManager {
    param([int]$Port, [string]$StateRoot)

    $tokenPath = Join-Path $StateRoot 'control-token'
    if (-not (Test-Path -LiteralPath $tokenPath)) {
        throw "The router is online but its control token is missing: $tokenPath"
    }
    $token = (Get-Content -Raw -LiteralPath $tokenPath).Trim()
    if ($token -notmatch '^[0-9a-f]{64}$') {
        throw "The router control token is invalid: $tokenPath"
    }
    $managerUrl = "http://127.0.0.1:$Port/manager#token=$token"
    Start-Process $managerUrl
}

function Protect-RouterPath {
    param([string]$Path, [bool]$Directory)

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $rights = if ($Directory) { '(OI)(CI)F' } else { 'F' }
    $currentGrant = "*$($currentSid):$rights"
    $systemGrant = "*S-1-5-18:$rights"
    & icacls.exe $Path /inheritance:r /grant:r $currentGrant $systemGrant | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to protect the router path with Windows ACLs: $Path"
    }
}

function Ensure-ControlToken {
    param([string]$StateRoot)

    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    Protect-RouterPath -Path $StateRoot -Directory $true
    $tokenPath = Join-Path $StateRoot 'control-token'
    if (Test-Path -LiteralPath $tokenPath) {
        $token = (Get-Content -Raw -LiteralPath $tokenPath).Trim()
        if ($token -notmatch '^[0-9a-f]{64}$') {
            throw "The router control token is invalid: $tokenPath"
        }
        Protect-RouterPath -Path $tokenPath -Directory $false
        return $token
    }

    $bytes = [byte[]]::new(32)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    $token = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    [System.IO.File]::WriteAllText($tokenPath, $token, [System.Text.UTF8Encoding]::new($false))
    Protect-RouterPath -Path $tokenPath -Directory $false
    return $token
}

function Sync-BundledCodex {
    param([string]$SourcePath, [string]$DestinationPath)

    $signature = Get-AuthenticodeSignature -LiteralPath $SourcePath
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'OpenAI') {
        throw "The bundled Codex executable does not have a valid OpenAI signature: $SourcePath"
    }

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash
    if (Test-Path -LiteralPath $DestinationPath) {
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $DestinationPath).Hash
        if ($sourceHash -eq $destinationHash) {
            return
        }
    }

    $temporaryPath = "$DestinationPath.tmp-$PID"
    try {
        Copy-Item -Force -LiteralPath $SourcePath -Destination $temporaryPath
        $copiedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryPath).Hash
        if ($copiedHash -ne $sourceHash) {
            throw 'The private Codex copy failed SHA-256 verification.'
        }
        Move-Item -Force -LiteralPath $temporaryPath -Destination $DestinationPath
    } finally {
        Remove-Item -Force -LiteralPath $temporaryPath -ErrorAction SilentlyContinue
    }
}

function Set-RouterOwlProfile {
    param([string]$RuntimePath, [string]$ProfileName)

    $owlConfigPath = Join-Path $RuntimePath 'resources\owl-app.ini'
    if (-not (Test-Path -LiteralPath $owlConfigPath)) {
        throw "The Owl desktop configuration is missing: $owlConfigPath"
    }
    $owlConfig = [System.IO.File]::ReadAllText($owlConfigPath)
    $escapedProfileName = [regex]::Escape($ProfileName)
    if ($owlConfig -match "(?m)^UserDataDirectoryName=$escapedProfileName`r?$") {
        return
    }
    $patchedConfig = [regex]::Replace(
        $owlConfig,
        '(?m)^UserDataDirectoryName=[^\r\n]+\r?$',
        "UserDataDirectoryName=$ProfileName",
        1
    )
    if ($patchedConfig -eq $owlConfig) {
        throw 'The Owl desktop profile setting did not match the expected Codex build.'
    }
    [System.IO.File]::WriteAllText($owlConfigPath, $patchedConfig, [System.Text.UTF8Encoding]::new($false))
}

function Sync-DesktopRuntime {
    param(
        [string]$PackagePath,
        [bool]$UseNativeMenu,
        [string]$ControlToken,
        [int]$ControlPort,
        [string]$ProfileName
    )

    $sourceApp = Join-Path $PackagePath 'app'
    $sourceAsar = Join-Path $sourceApp 'resources\app.asar'
    if (-not (Test-Path -LiteralPath $sourceAsar)) {
        throw "The packaged desktop runtime is incomplete: $sourceApp"
    }

    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceAsar).Hash.ToLowerInvariant()
    $tokenHash = ''
    if ($UseNativeMenu) {
        $tokenHash = (Get-FileHash -Algorithm SHA256 -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($ControlToken)))).Hash.ToLowerInvariant()
    }
    $packageName = [System.IO.Path]::GetFileName($PackagePath)
    $runtimeBase = Join-Path $env:LOCALAPPDATA 'Codex Subscription Router Runtime'
    $runtimeVariant = if ($UseNativeMenu) { "owl-router-native-v1-$ControlPort-$($tokenHash.Substring(0, 12))" } else { 'owl-router-v1' }
    $runtimePath = Join-Path $runtimeBase "$packageName-$($sourceHash.Substring(0, 12))-$runtimeVariant"
    $runtimeAsar = Join-Path $runtimePath 'resources\app.asar'
    if (Test-Path -LiteralPath $runtimeAsar) {
        $runtimeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeAsar).Hash.ToLowerInvariant()
        if ($UseNativeMenu) {
            $metadataPath = Join-Path $runtimePath 'resources\codex-router-native.json'
            if (Test-Path -LiteralPath $metadataPath) {
                $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json
                if ($metadata.sourceHash -eq $sourceHash -and
                    $metadata.patchedHash -eq $runtimeHash -and
                    $metadata.tokenHash -eq $tokenHash -and
                    [int]$metadata.controlPort -eq $ControlPort) {
                    Set-RouterOwlProfile -RuntimePath $runtimePath -ProfileName $ProfileName
                    return $runtimePath
                }
            }
        } elseif ($runtimeHash -eq $sourceHash) {
            Set-RouterOwlProfile -RuntimePath $runtimePath -ProfileName $ProfileName
            return $runtimePath
        }
        throw "The cached desktop runtime failed verification: $runtimePath"
    }

    New-Item -ItemType Directory -Force -Path $runtimeBase | Out-Null
    $stagingPath = Join-Path $runtimeBase ".staging-$PID-$($sourceHash.Substring(0, 12))"
    if (Test-Path -LiteralPath $stagingPath) {
        throw "A runtime staging directory already exists: $stagingPath"
    }
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    try {
        Write-Host 'Preparing an isolated desktop runtime. The first launch copies about 1.8 GB...'
        & robocopy.exe $sourceApp $stagingPath /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        $robocopyExitCode = $LASTEXITCODE
        if ($robocopyExitCode -gt 7) {
            throw "Copying the desktop runtime failed with robocopy exit code $robocopyExitCode."
        }

        $stagedAsar = Join-Path $stagingPath 'resources\app.asar'
        $stagedExecutable = Join-Path $stagingPath 'ChatGPT.exe'
        if (-not (Test-Path -LiteralPath $stagedAsar) -or -not (Test-Path -LiteralPath $stagedExecutable)) {
            throw 'The isolated desktop runtime is incomplete after copying.'
        }
        $stagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedAsar).Hash.ToLowerInvariant()
        if ($stagedHash -ne $sourceHash) {
            throw 'The isolated desktop runtime failed SHA-256 verification.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $stagedExecutable
        if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch 'OpenAI') {
            throw 'The isolated ChatGPT executable does not have a valid OpenAI signature.'
        }
        if ($UseNativeMenu) {
            $patcherRoot = Join-Path $PSScriptRoot 'renderer-patcher'
            $patcher = Join-Path $patcherRoot 'patch-windows-runtime.mjs'
            $component = Join-Path $patcherRoot 'windows-account-menu.js'
            $node = Join-Path $stagingPath 'resources\cua_node\bin\node.exe'
            if (-not (Test-Path -LiteralPath $patcher) -or
                -not (Test-Path -LiteralPath $component) -or
                -not (Test-Path -LiteralPath $node)) {
                throw 'The native-menu patcher payload is incomplete. Re-run build-windows.ps1.'
            }
            $patchOutput = & $node $patcher --resources (Join-Path $stagingPath 'resources') --component $component --token $ControlToken --port ([string]$ControlPort)
            $patchExitCode = $LASTEXITCODE
            if ($patchExitCode -ne 0) {
                throw 'The installed Codex renderer is not compatible with this native-menu patch.'
            }
            foreach ($line in @($patchOutput)) {
                Write-Host $line
            }
            $stagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedAsar).Hash.ToLowerInvariant()
            $metadata = [ordered]@{
                sourceHash = $sourceHash
                patchedHash = $stagedHash
                tokenHash = $tokenHash
                controlPort = $ControlPort
            } | ConvertTo-Json
            [System.IO.File]::WriteAllText(
                (Join-Path $stagingPath 'resources\codex-router-native.json'),
                $metadata,
                [System.Text.UTF8Encoding]::new($false)
            )
        }
        Set-RouterOwlProfile -RuntimePath $stagingPath -ProfileName $ProfileName
        Move-Item -LiteralPath $stagingPath -Destination $runtimePath
    } catch {
        Write-Warning "The incomplete staging directory was left for inspection: $stagingPath"
        throw
    }
    return $runtimePath
}

$stateRoot = Join-Path $env:USERPROFILE '.codex-mux'
if (Test-RouterHealth -Port $ControlPort) {
    if (-not $NoManager) {
        Open-RouterManager -Port $ControlPort -StateRoot $stateRoot
    }
    Write-Host 'Codex Subscription Router is already running.'
    exit 0
}
if ($ManagerOnly) {
    throw 'Codex Subscription Router is not running. Start it with launch-router.cmd first.'
}

$controlToken = Ensure-ControlToken -StateRoot $stateRoot
$resolvedMux = (Resolve-Path -LiteralPath $MuxPath -ErrorAction Stop).Path
$resolvedPackageRoot = Resolve-CodexPackageRoot -ConfiguredRoot $PackageRoot
$profileName = if ($NativeMenu) { 'CodexSubscriptionRouterNative' } else { 'CodexSubscriptionRouter' }
$desktopRuntime = Sync-DesktopRuntime -PackagePath $resolvedPackageRoot -UseNativeMenu $NativeMenu.IsPresent -ControlToken $controlToken -ControlPort $ControlPort -ProfileName $profileName
$desktopExecutable = Join-Path $desktopRuntime 'ChatGPT.exe'
$packagedCodex = Join-Path $desktopRuntime 'resources\codex.exe'
$realCodex = Join-Path $PSScriptRoot 'codex.real.exe'
if (-not (Test-Path -LiteralPath $desktopExecutable)) {
    throw "The ChatGPT desktop executable is missing: $desktopExecutable"
}
if (-not (Test-Path -LiteralPath $packagedCodex)) {
    throw "The bundled Codex executable is missing: $packagedCodex"
}
Sync-BundledCodex -SourcePath $packagedCodex -DestinationPath $realCodex

$profileRootName = if ($NativeMenu) { 'Codex Subscription Router Native' } else { 'Codex Subscription Router' }
$profileRoot = Join-Path $env:LOCALAPPDATA $profileRootName
$owlProfileRoot = Join-Path $env:APPDATA "Codex\web\$profileName"
$previousEnvironment = @{
    CODEX_CLI_PATH = $env:CODEX_CLI_PATH
    CODEX_MUX_REAL_CODEX = $env:CODEX_MUX_REAL_CODEX
    CODEX_MUX_HOME = $env:CODEX_MUX_HOME
    CODEX_MUX_CONTROL_PORT = $env:CODEX_MUX_CONTROL_PORT
    CODEX_ELECTRON_USER_DATA_PATH = $env:CODEX_ELECTRON_USER_DATA_PATH
}

try {
    $env:CODEX_CLI_PATH = $resolvedMux
    $env:CODEX_MUX_REAL_CODEX = $realCodex
    $env:CODEX_MUX_HOME = $stateRoot
    $env:CODEX_MUX_CONTROL_PORT = [string]$ControlPort
    $env:CODEX_ELECTRON_USER_DATA_PATH = $profileRoot
    $desktopProcess = Start-Process -FilePath $desktopExecutable -PassThru
} finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$($entry.Key)" $entry.Value
        }
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($desktopProcess.HasExited) {
        throw "The isolated desktop process exited before the router started (exit code $($desktopProcess.ExitCode))."
    }
    if (Test-RouterHealth -Port $ControlPort) {
        if (-not $NoManager) {
            Open-RouterManager -Port $ControlPort -StateRoot $stateRoot
        }
        Write-Host "Codex Subscription Router started with package $([System.IO.Path]::GetFileName($resolvedPackageRoot))."
        exit 0
    }
    Start-Sleep -Milliseconds 250
}

throw "The desktop app started, but the router did not become healthy on port $ControlPort. Close the preview app and inspect its profile under $owlProfileRoot."
