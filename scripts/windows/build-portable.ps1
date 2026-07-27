param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release",
    [string]$CertificateThumbprint,
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$artifactsRoot = Join-Path $repoRoot "artifacts\portable"
$workRoot = Join-Path $artifactsRoot "work-$Version-x64"
$payloadRoot = Join-Path $workRoot "payload"
$appOutput = Join-Path $payloadRoot "app"
$backendOutput = Join-Path $payloadRoot "backend"
$launcherOutput = Join-Path $workRoot "launcher"
$payloadArchive = Join-Path $workRoot "payload.zip"
$releaseOutput = Join-Path $artifactsRoot "VpnRouter-$Version-x64.exe"

$appProject = Join-Path $repoRoot "windows\VpnRouter.App\VpnRouter.App.csproj"
$backendProject = Join-Path $repoRoot "windows\VpnRouter.Service\VpnRouter.Service.csproj"
$launcherProject = Join-Path $repoRoot "windows\VpnRouter.Launcher\VpnRouter.Launcher.csproj"

if (Test-Path -LiteralPath $workRoot) {
    $resolvedWorkRoot = [System.IO.Path]::GetFullPath($workRoot)
    $resolvedArtifactsRoot = [System.IO.Path]::GetFullPath($artifactsRoot)
    if (-not $resolvedWorkRoot.StartsWith($resolvedArtifactsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove work directory outside the portable artifacts root: $resolvedWorkRoot"
    }
    Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $appOutput, $backendOutput, $launcherOutput | Out-Null

Write-Host "Publishing WinUI app..."
dotnet publish $appProject `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $appOutput `
    -p:Platform=x64 `
    -p:WindowsPackageType=None `
    -p:PublishTrimmed=false `
    -p:PublishReadyToRun=false
if ($LASTEXITCODE -ne 0) {
    throw "WinUI app publish failed with exit code $LASTEXITCODE."
}

Write-Host "Publishing elevated backend..."
dotnet publish $backendProject `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $backendOutput `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:PublishTrimmed=false `
    -p:PublishReadyToRun=false
if ($LASTEXITCODE -ne 0) {
    throw "Elevated backend publish failed with exit code $LASTEXITCODE."
}

Write-Host "Compressing portable payload..."
Add-Type -AssemblyName System.IO.Compression
if (Test-Path -LiteralPath $payloadArchive) {
    Remove-Item -LiteralPath $payloadArchive -Force
}

$archiveStream = [System.IO.File]::Open(
    $payloadArchive,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None)
$archive = [System.IO.Compression.ZipArchive]::new(
    $archiveStream,
    [System.IO.Compression.ZipArchiveMode]::Create,
    $false)
try {
    Get-ChildItem -LiteralPath $payloadRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($payloadRoot.Length).TrimStart([char[]]"\/").Replace("\", "/")
            $entry = $archive.CreateEntry(
                $relativePath,
                [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $inputStream = $_.OpenRead()
            $outputStream = $entry.Open()
            try {
                $inputStream.CopyTo($outputStream)
            }
            finally {
                $outputStream.Dispose()
                $inputStream.Dispose()
            }
        }
}
finally {
    $archive.Dispose()
    $archiveStream.Dispose()
}

Write-Host "Publishing one-file launcher..."
dotnet publish $launcherProject `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $launcherOutput `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false `
    -p:PublishReadyToRun=false `
    -p:Version=$Version `
    -p:PortablePayloadPath=$payloadArchive
if ($LASTEXITCODE -ne 0) {
    throw "Portable launcher publish failed with exit code $LASTEXITCODE."
}

$builtLauncher = Join-Path $launcherOutput "VpnRouter.exe"
if (-not (Test-Path -LiteralPath $builtLauncher)) {
    throw "Portable launcher was not generated: $builtLauncher"
}

Copy-Item -LiteralPath $builtLauncher -Destination $releaseOutput -Force

if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $normalizedThumbprint = $CertificateThumbprint.Replace(" ", "").ToUpperInvariant()
    $certificate = Get-ChildItem Cert:\CurrentUser\My,Cert:\LocalMachine\My |
        Where-Object {
            $_.Thumbprint -eq $normalizedThumbprint -and
            $_.HasPrivateKey
        } |
        Select-Object -First 1
    if ($null -eq $certificate) {
        throw "A code-signing certificate with the requested thumbprint and private key was not found."
    }

    Write-Host "Signing portable launcher with Authenticode..."
    $signature = Set-AuthenticodeSignature `
        -FilePath $releaseOutput `
        -Certificate $certificate `
        -HashAlgorithm SHA256 `
        -TimestampServer $TimestampServer
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode signing failed: $($signature.StatusMessage)"
    }
}

$hash = Get-FileHash -LiteralPath $releaseOutput -Algorithm SHA256
$artifactSize = (Get-Item -LiteralPath $releaseOutput).Length
$checksumOutput = "$releaseOutput.sha256"
Set-Content `
    -LiteralPath $checksumOutput `
    -Value "$($hash.Hash)  $([System.IO.Path]::GetFileName($releaseOutput))" `
    -Encoding ascii

Remove-Item -LiteralPath $workRoot -Recurse -Force

Write-Host "Portable artifact: $releaseOutput"
Write-Host "Size: $artifactSize bytes"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Checksum: $checksumOutput"
