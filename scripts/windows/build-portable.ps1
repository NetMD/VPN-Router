param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release"
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
    -p:PublishTrimmed=false

Write-Host "Publishing elevated backend..."
dotnet publish $backendProject `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $backendOutput `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None

Write-Host "Compressing portable payload..."
Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $payloadArchive -CompressionLevel Optimal

Write-Host "Publishing one-file launcher..."
dotnet publish $launcherProject `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output $launcherOutput `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false `
    -p:Version=$Version `
    -p:PortablePayloadPath=$payloadArchive

$builtLauncher = Join-Path $launcherOutput "VpnRouter.exe"
if (-not (Test-Path -LiteralPath $builtLauncher)) {
    throw "Portable launcher was not generated: $builtLauncher"
}

Copy-Item -LiteralPath $builtLauncher -Destination $releaseOutput -Force
$hash = Get-FileHash -LiteralPath $releaseOutput -Algorithm SHA256
$artifactSize = (Get-Item -LiteralPath $releaseOutput).Length

Remove-Item -LiteralPath $workRoot -Recurse -Force

Write-Host "Portable artifact: $releaseOutput"
Write-Host "Size: $artifactSize bytes"
Write-Host "SHA256: $($hash.Hash)"
