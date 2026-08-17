param(
    [string]$Version = "0.1.0",
    [string]$Configuration = "Release",
    [string]$CertificateThumbprint,
    [string]$TimestampServer = "http://timestamp.digicert.com",
    [switch]$IncludeWfpSpike,
    [switch]$DiscoverWfpBuildInputs,
    [string]$FeatureRepositoryRoot,
    [string[]]$FeatureProjectRelativePaths
)

$ErrorActionPreference = "Stop"

function Assert-WfpFeaturePath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RepositoryRoot)

    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]"\/")
    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    if ($fullPath -ne $root -and -not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "WFP feature input is outside the repository."
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "WFP feature input is missing."
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "WFP feature input contains a reparse point."
    }
    $cursor = $item.Directory
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "WFP feature input contains a reparse point."
        }
        if ($cursor.FullName -eq $root) { break }
        $cursor = $cursor.Parent
    }
    if ($null -eq $cursor) { throw "WFP feature input escaped the repository." }
    return $fullPath
}

function Get-WfpBuildInputPaths {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$ProjectRelativePaths
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]"\/")
    $result = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $importSeeds = [Collections.Generic.List[string]]::new()
    $automaticNames = @("Directory.Build.props", "Directory.Build.targets", "Directory.Packages.props", "global.json", "NuGet.Config")
    $startDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$startDirectories.Add($root)
    foreach ($projectRelativePath in $ProjectRelativePaths) {
        if ([string]::IsNullOrWhiteSpace($projectRelativePath) -or [IO.Path]::IsPathRooted($projectRelativePath)) {
            throw "WFP feature project path is invalid."
        }
        $projectPath = Assert-WfpFeaturePath -Path (Join-Path $root $projectRelativePath) -RepositoryRoot $root
        [void]$startDirectories.Add((Split-Path -Parent $projectPath))
        $importSeeds.Add($projectPath)
    }
    foreach ($startDirectory in $startDirectories) {
        $cursor = [IO.DirectoryInfo]::new($startDirectory)
        while ($null -ne $cursor) {
            foreach ($name in $automaticNames) {
                $candidate = Join-Path $cursor.FullName $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $candidate = Assert-WfpFeaturePath -Path $candidate -RepositoryRoot $root
                    $relative = [IO.Path]::GetRelativePath($root, $candidate).Replace("\", "/")
                    [void]$result.Add($relative)
                    if ([IO.Path]::GetExtension($candidate) -in @(".props", ".targets")) { $importSeeds.Add($candidate) }
                }
            }
            if ($cursor.FullName -eq $root) { break }
            $cursor = $cursor.Parent
        }
        if ($null -eq $cursor) { throw "WFP feature input ancestor escaped the repository." }
    }

    $visiting = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Visit-WfpImport([string]$ImportSource) {
        $source = Assert-WfpFeaturePath -Path $ImportSource -RepositoryRoot $root
        if ($visiting.Contains($source)) { throw "WFP feature input import cycle detected." }
        if (-not $visited.Add($source)) { return }
        [void]$visiting.Add($source)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.XmlResolver = $null
            try { $document.LoadXml((Get-Content -LiteralPath $source -Raw)) }
            catch { throw "WFP feature input XML is invalid." }
            foreach ($node in @($document.SelectNodes("//*[local-name()='Import']"))) {
                $value = [string]$node.GetAttribute("Project")
                if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[$@%]\(' -or
                    $value -match '[*?\[\]]' -or [IO.Path]::IsPathRooted($value)) {
                    throw "WFP feature input import is dynamic, rooted, or uses a glob."
                }
                if ([IO.Path]::GetExtension($value) -notin @(".props", ".targets", ".proj", ".csproj")) {
                    throw "WFP feature input import type is not allowed."
                }
                $target = Assert-WfpFeaturePath -Path (Join-Path (Split-Path -Parent $source) $value) -RepositoryRoot $root
                $relativeTarget = [IO.Path]::GetRelativePath($root, $target).Replace("\", "/")
                [void]$result.Add($relativeTarget)
                Visit-WfpImport $target
            }
        }
        finally { [void]$visiting.Remove($source) }
    }
    foreach ($seed in $importSeeds) { Visit-WfpImport $seed }

    $sorted = @($result)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    return $sorted
}

if ($DiscoverWfpBuildInputs) {
    if ([string]::IsNullOrWhiteSpace($FeatureRepositoryRoot) -or $null -eq $FeatureProjectRelativePaths -or $FeatureProjectRelativePaths.Count -eq 0) {
        throw "Discovery mode requires a repository root and project paths."
    }
    $discovered = @(Get-WfpBuildInputPaths -RepositoryRoot $FeatureRepositoryRoot -ProjectRelativePaths $FeatureProjectRelativePaths)
    $entries = @($discovered | ForEach-Object {
        $relativePath = $_
        $fullPath = Join-Path $FeatureRepositoryRoot $relativePath
        $stageOutput = @(& git -C $FeatureRepositoryRoot ls-files --stage -- $relativePath 2>&1)
        $gitExitCode = $LASTEXITCODE
        if ($gitExitCode -ne 0) { throw "WFP feature input index lookup failed: $($stageOutput -join ' ')" }
        $stageLine = @($stageOutput | Select-Object -First 1)
        $indexBlobOid = if ($stageLine.Count -eq 1 -and $stageLine[0] -match '^\d+\s+([0-9a-fA-F]{40,64})\s+') { $Matches[1].ToLowerInvariant() } else { $null }
        [ordered]@{ relativePath = $relativePath; length = (Get-Item -LiteralPath $fullPath).Length; sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant(); indexBlobOid = $indexBlobOid }
    })
    [ordered]@{ schemaVersion = 1; files = $entries } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$artifactsRoot = if ($IncludeWfpSpike) {
    Join-Path $repoRoot "artifacts\wfp-spike"
} else {
    Join-Path $repoRoot "artifacts\portable"
}
$workRoot = Join-Path $artifactsRoot "work-$Version-x64"
$payloadRoot = Join-Path $workRoot "payload"
$appOutput = Join-Path $payloadRoot "app"
$backendOutput = Join-Path $payloadRoot "backend"
$wfpSpikeOutput = Join-Path $payloadRoot "wfp-spike"
$launcherOutput = Join-Path $workRoot "launcher"
$payloadArchive = Join-Path $workRoot "payload.zip"
$releaseOutput = if ($IncludeWfpSpike) {
    Join-Path $artifactsRoot "VpnRouter-WfpSpike-$Version-x64.exe"
} else {
    Join-Path $artifactsRoot "VpnRouter-$Version-x64.exe"
}

$appProject = Join-Path $repoRoot "windows\VpnRouter.App\VpnRouter.App.csproj"
$backendProject = Join-Path $repoRoot "windows\VpnRouter.Service\VpnRouter.Service.csproj"
$launcherProject = Join-Path $repoRoot "windows\VpnRouter.Launcher\VpnRouter.Launcher.csproj"
$wfpSpikeProject = Join-Path $repoRoot "windows\VpnRouter.WfpSpike.Harness\VpnRouter.WfpSpike.Harness.csproj"

if (Test-Path -LiteralPath $workRoot) {
    $resolvedWorkRoot = [System.IO.Path]::GetFullPath($workRoot)
    $resolvedArtifactsRoot = [System.IO.Path]::GetFullPath($artifactsRoot)
    if (-not $resolvedWorkRoot.StartsWith($resolvedArtifactsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove work directory outside the portable artifacts root: $resolvedWorkRoot"
    }
    Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
}

$outputDirectories = @($appOutput, $backendOutput, $launcherOutput)
if ($IncludeWfpSpike) {
    $outputDirectories += $wfpSpikeOutput
}
New-Item -ItemType Directory -Force -Path $outputDirectories | Out-Null

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

if ($IncludeWfpSpike) {
    Write-Host "Publishing isolated WFP spike harness..."
    dotnet publish $wfpSpikeProject `
        --configuration $Configuration `
        --runtime win-x64 `
        --self-contained true `
        --output $wfpSpikeOutput `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=None `
        -p:PublishTrimmed=false `
        -p:PublishReadyToRun=false
    if ($LASTEXITCODE -ne 0) {
        throw "WFP spike harness publish failed with exit code $LASTEXITCODE."
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "Visual Studio discovery tool is required for the WFP SDK ABI probe."
    }
    $vsRoot = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    $msvcRoot = Get-ChildItem -LiteralPath (Join-Path $vsRoot "VC\Tools\MSVC") -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $sdkIncludeRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
    $sdkVersionRoot = Get-ChildItem -LiteralPath $sdkIncludeRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $sdkLibRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Lib\$($sdkVersionRoot.Name)"
    $clExe = Join-Path $msvcRoot.FullName "bin\Hostx64\x64\cl.exe"
    $probeSource = Join-Path $repoRoot "windows\VpnRouter.WfpSpike\Native\WfpSdkAbiProbe.cpp"
    $probeExecutable = Join-Path $wfpSpikeOutput "WfpSdkAbiProbe.exe"
    $probeObject = Join-Path $workRoot "WfpSdkAbiProbe.obj"
    $probeArguments = @(
        "/nologo", "/EHsc", "/std:c++17", "/utf-8", "/DUNICODE", "/D_UNICODE",
        "/I$($msvcRoot.FullName)\include",
        "/I$($sdkVersionRoot.FullName)\shared",
        "/I$($sdkVersionRoot.FullName)\um",
        "/I$($sdkVersionRoot.FullName)\ucrt",
        "/Fo$probeObject", "/Fe$probeExecutable", $probeSource,
        "/link", "/LIBPATH:$($msvcRoot.FullName)\lib\x64",
        "/LIBPATH:$sdkLibRoot\um\x64", "/LIBPATH:$sdkLibRoot\ucrt\x64"
    )
    & $clExe @probeArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $probeExecutable)) {
        throw "WFP SDK ABI probe build failed with exit code $LASTEXITCODE."
    }
    $probeLayouts = (& $probeExecutable | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $probeLayouts.schemaVersion -ne 1 -or $probeLayouts.architecture -ne "x64") {
        throw "WFP SDK ABI probe execution failed."
    }
    $headerHash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        @("shared\fwpmtypes.h", "shared\fwptypes.h", "shared\netioapi.h", "shared\ifdef.h", "um\fwpmu.h", "um\userenv.h") |
            ForEach-Object {
                $headerHash.AppendData([Text.Encoding]::UTF8.GetBytes($_.Replace("\", "/")))
                $headerHash.AppendData([IO.File]::ReadAllBytes((Join-Path $sdkVersionRoot.FullName $_)))
            }
        $sdkHeaderSha256 = [Convert]::ToHexString($headerHash.GetHashAndReset())
    }
    finally {
        $headerHash.Dispose()
    }
    [ordered]@{
        schemaVersion = 1
        architecture = "x64"
        sdkHeaderSha256 = $sdkHeaderSha256
        probeSourceSha256 = (Get-FileHash -LiteralPath $probeSource -Algorithm SHA256).Hash
        probeBinarySha256 = (Get-FileHash -LiteralPath $probeExecutable -Algorithm SHA256).Hash
        layouts = $probeLayouts.layouts
        constants = $probeLayouts.constants
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $wfpSpikeOutput "wfp-sdk-abi-x64.json") -Encoding utf8NoBOM
    Copy-Item -LiteralPath $probeSource -Destination (Join-Path $wfpSpikeOutput "WfpSdkAbiProbe.cpp") -Force

    $fixtureRoot = Join-Path $repoRoot "scripts\windows\fixtures\wfp-spike"
    $fixtureHash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($fixtureRoot.Length).TrimStart([char[]]"\/").Replace("\", "/")
            $fixtureHash.AppendData([Text.Encoding]::UTF8.GetBytes($relative))
            $fixtureHash.AppendData([IO.File]::ReadAllBytes($_.FullName))
        }
        $fixturesManifestSha256 = [Convert]::ToHexString($fixtureHash.GetHashAndReset())
    }
    finally { $fixtureHash.Dispose() }
    $featurePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    # test-wfp-app-routing-spike.ps1 의 Get-FeatureManifest 와 같은 목록이다.
    # 한쪽만 고치면 FEATURE_MANIFEST_MISMATCH 로 자동 검사가 끊긴다 (R4 설계 §6.4).
    @("windows\VpnRouter.WfpSpike", "windows\VpnRouter.WfpSpike.Harness", "scripts\windows\fixtures\wfp-spike", "scripts\windows\wfp-observation") | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot $_) -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/](?:bin|obj)[\\/]' } |
            ForEach-Object { [void]$featurePaths.Add($_.FullName.Substring($repoRoot.Length).TrimStart([char[]]"\/").Replace("\", "/")) }
    }
    @("windows/VpnRouter.Tests/Program.cs", "windows/VpnRouter.Tests/VpnRouter.Tests.csproj", "windows/VpnRouter.slnx", "windows/VpnRouterVs.sln", "scripts/windows/build-portable.ps1", "scripts/windows/test-wfp-app-routing-spike.ps1") |
        ForEach-Object { [void]$featurePaths.Add($_) }

    # 자동 상위 입력과 그 입력이 가져오는 정적 import 그래프를 같은 탐색기로 묶는다.
    @(Get-WfpBuildInputPaths -RepositoryRoot $repoRoot -ProjectRelativePaths @(
        "windows/VpnRouter.WfpSpike/VpnRouter.WfpSpike.csproj",
        "windows/VpnRouter.WfpSpike.Harness/VpnRouter.WfpSpike.Harness.csproj",
        "windows/VpnRouter.Tests/VpnRouter.Tests.csproj"
    )) | ForEach-Object { [void]$featurePaths.Add($_) }
    $sortedFeaturePaths = @($featurePaths)
    [Array]::Sort($sortedFeaturePaths, [StringComparer]::Ordinal)
    $featureEntries = @($sortedFeaturePaths | ForEach-Object {
        $relativePath = $_
        $fullPath = Join-Path $repoRoot $relativePath
        [void](Assert-WfpFeaturePath -Path $fullPath -RepositoryRoot $repoRoot)
        $indexOutput = @(& git -C $repoRoot ls-files --stage -- $relativePath 2>&1)
        $gitExitCode = $LASTEXITCODE
        if ($gitExitCode -ne 0) { throw "WFP feature input index lookup failed: $($indexOutput -join ' ')" }
        $indexLine = @($indexOutput | Select-Object -First 1)
        $indexBlobOid = if ($indexLine.Count -eq 1 -and $indexLine[0] -match '^\d+\s+([0-9a-fA-F]{40,64})\s+') { $Matches[1].ToLowerInvariant() } else { $null }
        [ordered]@{
            relativePath = $relativePath
            length = (Get-Item -LiteralPath $fullPath).Length
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            indexBlobOid = $indexBlobOid
        }
    })
    $featureManifestPath = Join-Path $wfpSpikeOutput "wfp-feature-manifest.json"
    $featureManifestJson = [ordered]@{ schemaVersion = 1; files = $featureEntries } | ConvertTo-Json -Depth 5 -Compress
    [IO.File]::WriteAllText($featureManifestPath, $featureManifestJson, [Text.UTF8Encoding]::new($false))
    $worktreeFingerprint = (Get-FileHash -LiteralPath $featureManifestPath -Algorithm SHA256).Hash
    [ordered]@{
        schemaVersion = 1
        worktreeFingerprint = $worktreeFingerprint
        scriptSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot "scripts\windows\test-wfp-app-routing-spike.ps1") -Algorithm SHA256).Hash
        fixturesManifestSha256 = $fixturesManifestSha256
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $wfpSpikeOutput "wfp-gate-evidence.json") -Encoding utf8NoBOM

    $spikeManifestPath = Join-Path $wfpSpikeOutput "wfp-spike.manifest.json"
    $spikeFiles = @(
        Get-ChildItem -LiteralPath $wfpSpikeOutput -Recurse -File |
            Where-Object { $_.FullName -ne $spikeManifestPath } |
            Sort-Object FullName |
            ForEach-Object {
                [ordered]@{
                    relativePath = $_.FullName.Substring($wfpSpikeOutput.Length).TrimStart([char[]]"\/").Replace("\", "/")
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                    length = $_.Length
                }
            }
    )
    [ordered]@{
        schemaVersion = 1
        files = $spikeFiles
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $spikeManifestPath -Encoding utf8NoBOM
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

if ($IncludeWfpSpike) {
    Copy-Item -LiteralPath $spikeManifestPath -Destination (Join-Path $artifactsRoot "wfp-spike.manifest.json") -Force
}

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
