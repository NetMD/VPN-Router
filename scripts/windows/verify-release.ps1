param(
    [string]$Version = "0.1.0",
    [switch]$SkipBuild,
    [switch]$RequireSignature
)

$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$artifact = Join-Path $repoRoot "artifacts\portable\VpnRouter-$Version-x64.exe"
$checksumPath = "$artifact.sha256"

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot "build-portable.ps1") -Version $Version
}

if (-not (Test-Path -LiteralPath $artifact)) {
    throw "Portable artifact is missing: $artifact"
}

$versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($artifact)
if ($versionInfo.ProductVersion -notlike "$Version*") {
    throw "Product version mismatch. Expected $Version, got $($versionInfo.ProductVersion)."
}

$hash = Get-FileHash -LiteralPath $artifact -Algorithm SHA256
if (-not (Test-Path -LiteralPath $checksumPath)) {
    throw "Checksum file is missing: $checksumPath"
}

$recordedHash = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split "\s+")[0]
if (-not [string]::Equals($hash.Hash, $recordedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "SHA-256 checksum verification failed."
}

$signature = Get-AuthenticodeSignature -FilePath $artifact
if ($RequireSignature -and $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "A valid Authenticode signature is required. Current status: $($signature.Status)."
}

Write-Host "Running extraction-only smoke check..."
$extractionProcess = Start-Process `
    -FilePath $artifact `
    -ArgumentList "--extract-only" `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($extractionProcess.ExitCode -ne 0) {
    throw "Portable extraction-only smoke check failed with exit code $($extractionProcess.ExitCode)."
}

$cacheRoot = Join-Path $env:LOCALAPPDATA "VpnRouter\app"
$extracted = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$Version-*" } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $extracted -or
    -not (Test-Path -LiteralPath (Join-Path $extracted.FullName ".complete")) -or
    -not (Test-Path -LiteralPath (Join-Path $extracted.FullName "app\VpnRouter.App.exe")) -or
    -not (Test-Path -LiteralPath (Join-Path $extracted.FullName "backend\VpnRouter.Service.exe"))) {
    throw "Extracted portable payload is incomplete."
}

Write-Host "Release verification passed."
Write-Host "Artifact: $artifact"
Write-Host "Product version: $($versionInfo.ProductVersion)"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Signature: $($signature.Status)"
