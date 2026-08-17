[CmdletBinding()]
param(
    [switch]$ApplyLiveWfp,
    [string]$LiveOwnerConfirmation,
    [uint32]$LiveInterfaceIndex,
    [string]$LiveExecutablePath,
    [AllowEmptyString()][string]$LivePackageFamilyName,
    [ValidateLength(0, 65535)][string]$LiveObservationJson,
    # 측정에 필요한 실제 값(기준 인터페이스 번호·대상 주소·앱 경로 등)이 든 설정 파일.
    # 저장소 밖에 두고 경로만 받는다. 값은 결과 JSON 에 한 글자도 들어가지 않는다 (설계 §4.1).
    [string]$MeasurementSettingsPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$fixtureRoot = Join-Path $PSScriptRoot "fixtures\wfp-spike"
$harnessProject = Join-Path $repoRoot "windows\VpnRouter.WfpSpike.Harness\VpnRouter.WfpSpike.Harness.csproj"
$buildScript = Join-Path $PSScriptRoot "build-portable.ps1"
$runStartedAtUtc = [DateTimeOffset]::UtcNow
$runNonce = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
$privateSpoolBase = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "VpnRouter\wfp-spike-spool"
$temporaryRoot = Join-Path $privateSpoolBase $runNonce
# 실행 폴더 — 실행 전에 자리를 정한다 (설계 §7.1 / FR-12 / AC-12-1).
# spool($temporaryRoot)의 형제 폴더여야 한다. spool 아래에 두면 finally 가 지운다.
$runDirectoryBase = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "VpnRouter\wfp-spike-runs"
$runDirectory = Join-Path $runDirectoryBase ($runStartedAtUtc.ToString("yyyyMMdd-HHmmss") + "Z-" + $runNonce.Substring(0, 8))
$observationScriptRoot = Join-Path $PSScriptRoot "wfp-observation"
$markerPath = Join-Path $temporaryRoot "automated-marker.json"
$automatedMutex = $null
$automatedMutexAcquired = $false
$finalResult = $null
$scriptExitCode = 0
$currentGate = "INITIALIZE"
$payloadReadHandles = [Collections.Generic.List[IO.FileStream]]::new()
$providedLiveObservations = @{}

$allowedResultCodes = @(
    "NONE", "ADMIN_REQUIRED", "EXPLICIT_OPTION_REQUIRED", "AUTOMATED_GATE_FAILED",
    "APP_PATH_INVALID", "APP_ID_LOOKUP_FAILED", "PACKAGE_IDENTITY_UNAVAILABLE",
    "PACKAGE_ID_LOOKUP_FAILED", "INTERFACE_NOT_FOUND", "INTERFACE_IDENTITY_MISMATCH",
    "BFE_ACCESS_DENIED", "ENGINE_OPEN_FAILED", "POLICY_ALREADY_EXISTS",
    "IPV4_POLICY_ADD_FAILED", "IPV6_POLICY_ADD_FAILED", "SESSION_CLOSE_FAILED",
    "INTERFACE_CHANGED", "NEW_CONNECTION_NOT_OBSERVED", "UNEXPECTED_INTERFACE",
    "DNS_APP_ID_NOT_PROPAGATED", "OWNER_ABORTED", "PROHIBITED_PATTERN_FOUND",
    "PUBLISH_CONTENT_MISSING", "ENVIRONMENT_UNAVAILABLE"
)

# ---------------------------------------------------------------------------
# 판정 계약 — PowerShell 거울 (설계 §2.1 · §2.2)
#
# 으뜸 출처는 fixtures\wfp-spike\verdict-contract.json 이다. 사람이 고치는 자리는 그 파일뿐이고,
# 아래 거울이 그 파일과 같은지는 Test-Fixtures 가 기계로 대조한다(Q-05). 다르면
# VERDICT_CONTRACT_MISMATCH 로 막힌다. 값을 여기서 따로 정하지 않는다.
#
# "실패가 아님" 같은 느슨한 조건을 쓰지 않는다. 네 판정값마다 허용 실패 코드를
# 정확한 목록으로 적는다 — 새 값이 하나 생겨도 조용히 통과하지 못한다.
# ---------------------------------------------------------------------------
$verdictContractPath = Join-Path $fixtureRoot "verdict-contract.json"
$outcomeFailureCodeContract = [ordered]@{
    PASS         = @("NONE")
    FAIL         = @("DNS_APP_ID_NOT_PROPAGATED", "UNEXPECTED_INTERFACE")
    NOT_RUN      = @("ENVIRONMENT_UNAVAILABLE", "OWNER_ABORTED", "PACKAGE_IDENTITY_UNAVAILABLE")
    INCONCLUSIVE = @("ENVIRONMENT_UNAVAILABLE", "NEW_CONNECTION_NOT_OBSERVED")
}

function Test-OutcomeFailureCodePair {
    param(
        [AllowEmptyString()][string]$Outcome,
        [AllowEmptyString()][string]$FailureCode
    )

    if (-not $outcomeFailureCodeContract.Contains($Outcome)) { return $false }
    return $outcomeFailureCodeContract[$Outcome] -ccontains $FailureCode
}

# 측정 루프가 쓰는 상태. 값이 정해지는 자리는 아래 한 곳뿐이다.
$policyAppliedAtUtc = $null
$measurementDeadlineUtc = $null
$measurementSettings = $null
$measurementInterfaceIndex = 0
$caseMatrixRows = @()
$caseMatrixTransports = @()

function New-LimitedResult {
    param(
        [ValidateSet("DRY_RUN", "LIVE")][string]$Mode,
        [ValidateSet("PASS", "FAIL", "PARTIAL")][string]$Verdict,
        [ValidateSet("MATCH", "MISMATCH")][string]$Fingerprint,
        [string]$FailureCode = "NONE"
    )

    return [ordered]@{
        schemaVersion = 2
        startedAtUtc = $runStartedAtUtc.ToString("O")
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        mode = $Mode
        verdict = $Verdict
        beforeAfterFingerprint = $Fingerprint
        caseTotal = 0
        passCount = 0
        failCount = 0
        notRunCount = 0
        inconclusiveCount = 0
        cleanupOutcome = "NOT_RUN"
        cleanupFailureCode = $FailureCode
        cases = @()
    }
}

function Write-LimitedResult {
    param([Parameter(Mandatory)]$Result)

    $json = $Result | ConvertTo-Json -Depth 6 -Compress
    if (Test-ProhibitedContent -Text $json) {
        $json = (New-LimitedResult -Mode $Result.mode -Verdict "FAIL" -Fingerprint $Result.beforeAfterFingerprint -FailureCode "PROHIBITED_PATTERN_FOUND") |
            ConvertTo-Json -Depth 6 -Compress
    }

    [Console]::Out.WriteLine($json)
}

function Test-ProhibitedContent {
    param([AllowEmptyString()][string]$Text)

    $patterns = @(
        '(?i)(?:[a-z]:\\|\\\\Device\\)',
        '(?i)PackageFamilyName|\bPFN\b|AppPath|AppId|\bblob\b',
        '(?<![0-9])(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(?:\.(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}(?![0-9])',
        '(?i)(?:\b[0-9a-f]{1,4}:){3,}[0-9a-f]{0,4}\b|::',
        '(?i)queryName|responseName|\bdomain\b|hostname|https?://',
        '(?i)\.conf\b|\[Interface\]|\[Peer\]|PrivateKey|PresharedKey|Endpoint|AllowedIPs',
        '(?i)stackTrace|exceptionMessage|rawError|logLines'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Assert-PathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.Split([IO.Path]::DirectorySeparatorChar) -contains '..') {
        throw "PRIVATE_SPOOL_PATH_INVALID"
    }
    return $fullPath
}

function Assert-NoReparsePath {
    param([Parameter(Mandatory)][string]$Path)

    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "PRIVATE_SPOOL_REPARSE_REJECTED"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Set-PrivateAcl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet("Directory", "File")][string]$Kind
    )

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $userSid = $identity.User
    $adminSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    if ($Kind -eq "Directory") {
        $security = [Security.AccessControl.DirectorySecurity]::new()
        $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    else {
        $security = [Security.AccessControl.FileSecurity]::new()
        $inheritance = [Security.AccessControl.InheritanceFlags]::None
    }
    $security.SetOwner($userSid)
    $security.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($userSid, $adminSid)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        [void]$security.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $security
}

function Assert-PrivateAcl {
    param([Parameter(Mandatory)][string]$Path)

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $userSid = $identity.User.Value
    $adminSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null).Value
    $acl = Get-Acl -LiteralPath $Path
    $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
    if (-not $acl.AreAccessRulesProtected -or $ownerSid -ne $userSid) {
        throw "PRIVATE_SPOOL_ACL_INVALID"
    }
    $identities = @($acl.Access | ForEach-Object {
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    } | Select-Object -Unique)
    if ($identities.Count -ne 2 -or $identities -notcontains $userSid -or $identities -notcontains $adminSid -or
        @($acl.Access | Where-Object { $_.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow }).Count -ne 0) {
        throw "PRIVATE_SPOOL_ACL_INVALID"
    }
}

function New-PrivateSpool {
    Assert-NoReparsePath -Path ([IO.Path]::GetDirectoryName($privateSpoolBase))
    if (-not (Test-Path -LiteralPath $privateSpoolBase)) {
        [void][IO.Directory]::CreateDirectory($privateSpoolBase)
    }
    Set-PrivateAcl -Path $privateSpoolBase -Kind Directory
    Assert-NoReparsePath -Path $privateSpoolBase
    Assert-PrivateAcl -Path $privateSpoolBase
    if (Test-Path -LiteralPath $temporaryRoot) {
        throw "PRIVATE_SPOOL_ALREADY_EXISTS"
    }
    [void][IO.Directory]::CreateDirectory($temporaryRoot)
    Set-PrivateAcl -Path $temporaryRoot -Kind Directory
    Assert-NoReparsePath -Path $temporaryRoot
    Assert-PrivateAcl -Path $temporaryRoot
}

function Write-PrivateNewFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )

    $fullPath = Assert-PathUnderRoot -Path $Path -Root $temporaryRoot
    Assert-NoReparsePath -Path ([IO.Path]::GetDirectoryName($fullPath))
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = [IO.FileStream]::new($fullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    Set-PrivateAcl -Path $fullPath -Kind File
    Assert-NoReparsePath -Path $fullPath
    Assert-PrivateAcl -Path $fullPath
}

function Copy-PrivateNewFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    Assert-NoReparsePath -Path $Source
    $fullDestination = Assert-PathUnderRoot -Path $Destination -Root $temporaryRoot
    $parent = [IO.Path]::GetDirectoryName($fullDestination)
    if (-not (Test-Path -LiteralPath $parent)) {
        [void][IO.Directory]::CreateDirectory($parent)
        Set-PrivateAcl -Path $parent -Kind Directory
    }
    Assert-NoReparsePath -Path $parent
    $input = [IO.FileStream]::new($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.FileStream]::new($fullDestination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose(); $input.Dispose() }
    Set-PrivateAcl -Path $fullDestination -Kind File
    Assert-PrivateAcl -Path $fullDestination
}

function Assert-LimitedResult {
    param([Parameter(Mandatory)]$Result)

    # 13개다. beforeAfterFingerprint 는 여기 없고 $allowed 에만 있다.
    # Test-Fixtures 의 $expectedSchemaProperties(14개)와 정확히 하나 차이다 (설계 §2.3).
    $required = @(
        "schemaVersion", "startedAtUtc", "completedAtUtc", "mode", "verdict",
        "caseTotal", "passCount", "failCount", "notRunCount", "inconclusiveCount",
        "cleanupOutcome", "cleanupFailureCode", "cases"
    )
    $allowed = @($required) + "beforeAfterFingerprint"
    foreach ($name in $required) {
        if ($Result.PSObject.Properties.Name -notcontains $name) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
    }
    if (@($Result.PSObject.Properties.Name | Where-Object { $allowed -notcontains $_ }).Count -ne 0) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }

    if ($Result.schemaVersion -ne 2 -or $Result.caseTotal -lt 0 -or $Result.caseTotal -gt 64) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    if ($Result.mode -notin @("DRY_RUN", "LIVE") -or
        $Result.verdict -notin @("PASS", "FAIL", "PARTIAL") -or
        $Result.cleanupOutcome -notin @("PASS", "FAIL", "NOT_RUN")) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    [DateTimeOffset]$timestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Result.startedAtUtc, [ref]$timestamp) -or
        -not [DateTimeOffset]::TryParse([string]$Result.completedAtUtc, [ref]$timestamp)) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    # 칸이 하나 늘었으므로 항도 하나 늘린다. 이 줄이 빠지면 "관찰 못 함"이
    # 조용히 사라져도 검사가 통과한다 (설계 §2.3 산술 불변식).
    if ($Result.caseTotal -ne ($Result.passCount + $Result.failCount + $Result.notRunCount + $Result.inconclusiveCount)) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    if ($allowedResultCodes -notcontains [string]$Result.cleanupFailureCode) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }

    $caseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in @($Result.cases)) {
        $caseProperties = @("caseId", "outcome", "failureCode", "observedAtUtc")
        if (@($case.PSObject.Properties.Name).Count -ne 4 -or
            @($case.PSObject.Properties.Name | Where-Object { $caseProperties -notcontains $_ }).Count -ne 0) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
        if ([string]$case.caseId -notmatch '^M-(00[1-9]|0[1-5][0-9]|06[0-4])$' -or -not $caseIds.Add([string]$case.caseId)) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
        # 판정 어휘와 실패 코드 짝짓기는 계약 한 곳만 본다. 여기서 값을 다시 적지 않는다.
        if (@($outcomeFailureCodeContract.Keys) -notcontains [string]$case.outcome -or
            -not [DateTimeOffset]::TryParse([string]$case.observedAtUtc, [ref]$timestamp)) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
        if ($allowedResultCodes -notcontains [string]$case.failureCode) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
        if (-not (Test-OutcomeFailureCodePair -Outcome ([string]$case.outcome) -FailureCode ([string]$case.failureCode))) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
    }
    if (@($Result.cases).Count -ne $Result.caseTotal) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    if ($Result.mode -eq "LIVE" -and $Result.verdict -eq "PASS") {
        $expectedIds = 1..64 | ForEach-Object { "M-{0:D3}" -f $_ }
        if ($Result.caseTotal -ne 64 -or @($expectedIds | Where-Object { -not $caseIds.Contains($_) }).Count -ne 0) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
        foreach ($case in @($Result.cases | Where-Object { [int]$_.caseId.Substring(2) -le 32 })) {
            if ($case.outcome -ne "PASS" -or $case.failureCode -ne "NONE") {
                throw "LIMITED_RESULT_SCHEMA_INVALID"
            }
        }
        $packageCases = @($Result.cases | Where-Object { [int]$_.caseId.Substring(2) -ge 33 })
        $packagePass = @($packageCases | Where-Object { $_.outcome -eq "PASS" -and $_.failureCode -eq "NONE" }).Count -eq 32
        $packageUnavailable = @($packageCases | Where-Object {
            $_.outcome -eq "NOT_RUN" -and $_.failureCode -eq "PACKAGE_IDENTITY_UNAVAILABLE"
        }).Count -eq 32
        if (-not $packagePass -and -not $packageUnavailable) {
            throw "LIMITED_RESULT_SCHEMA_INVALID"
        }
    }
    if ($Result.cleanupOutcome -eq "FAIL" -and
        ($Result.verdict -ne "FAIL" -or $Result.cleanupFailureCode -eq "NONE")) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }
    if ($Result.cleanupOutcome -eq "PASS" -and $Result.cleanupFailureCode -ne "NONE") {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }

    $serialized = $Result | ConvertTo-Json -Depth 8 -Compress
    if (Test-ProhibitedContent -Text $serialized) {
        throw "PROHIBITED_PATTERN_FOUND"
    }
}

function Read-BoundedProtocolTask {
    param(
        [Parameter(Mandatory)]$Task,
        [Parameter(Mandatory)][TimeSpan]$Timeout
    )

    if (-not $Task.Wait($Timeout) -or $null -eq $Task.Result -or
        [Text.Encoding]::UTF8.GetByteCount([string]$Task.Result) -gt 1MB) {
        throw "LIVE_PROTOCOL_TIMEOUT"
    }
    return [string]$Task.Result
}

function Test-Fixtures {
    $schema = Get-Content -LiteralPath (Join-Path $fixtureRoot "limited-result.schema.json") -Raw | ConvertFrom-Json
    # 14개다. Assert-LimitedResult 의 $required(13개)와 정확히
    # beforeAfterFingerprint 하나 차이다. 한쪽 수를 다른 쪽에 쓰면 그 자리에서 막힌다.
    $expectedSchemaProperties = @(
        "schemaVersion", "startedAtUtc", "completedAtUtc", "mode", "verdict",
        "beforeAfterFingerprint", "caseTotal", "passCount", "failCount", "notRunCount",
        "inconclusiveCount", "cleanupOutcome", "cleanupFailureCode", "cases"
    )
    if ($schema.additionalProperties -ne $false -or
        @($schema.required).Count -ne $expectedSchemaProperties.Count -or
        @($expectedSchemaProperties | Where-Object { $schema.required -notcontains $_ }).Count -ne 0 -or
        @($schema.properties.PSObject.Properties.Name | Where-Object { $expectedSchemaProperties -notcontains $_ }).Count -ne 0) {
        throw "LIMITED_RESULT_SCHEMA_INVALID"
    }

    $safeFixture = Get-Content -LiteralPath (Join-Path $fixtureRoot "dry-run-result.json") -Raw | ConvertFrom-Json
    Assert-LimitedResult -Result $safeFixture

    # --- Q-05 : 판정 계약 파일과 PowerShell 거울이 같은지 (AC-05-4 의 PowerShell 쪽 절반) ---
    # 사람이 고치는 자리는 verdict-contract.json 하나다. 거울만 고치거나 파일만 고치면
    # 여기서 막힌다. 네 자리를 각각 고치는 방식으로 돌아가지 않는다.
    $verdictContract = Get-Content -LiteralPath $verdictContractPath -Raw | ConvertFrom-Json
    if ($verdictContract.schemaVersion -ne 1) { throw "VERDICT_CONTRACT_MISMATCH" }

    # 같은 값을 두 번 적어도 개수만으로는 못 가린다 —
    # ["PASS","PASS","FAIL","NOT_RUN"] 은 개수 4에 전부 거울 안에 있는 값이라 그냥 지나간다.
    # 그래서 먼저 중복을 없앤 뒤 개수를 센다.
    $contractOutcomes = @(@($verdictContract.outcomes) | Select-Object -Unique)
    $mirrorOutcomes = @($outcomeFailureCodeContract.Keys)
    if (@($verdictContract.outcomes).Count -ne $contractOutcomes.Count -or
        $contractOutcomes.Count -ne $mirrorOutcomes.Count -or
        @($contractOutcomes | Where-Object { $mirrorOutcomes -notcontains $_ }).Count -ne 0) {
        throw "VERDICT_CONTRACT_MISMATCH"
    }
    foreach ($contractOutcome in $mirrorOutcomes) {
        $fileCodes = @($verdictContract.failureCodesByOutcome.$contractOutcome | Sort-Object)
        $mirrorCodes = @($outcomeFailureCodeContract[$contractOutcome] | Sort-Object)
        if (($fileCodes -join "|") -cne ($mirrorCodes -join "|")) { throw "VERDICT_CONTRACT_MISMATCH" }
        if (@($fileCodes | Where-Object { $allowedResultCodes -notcontains $_ }).Count -ne 0) {
            throw "VERDICT_CONTRACT_MISMATCH"
        }
    }

    # --- Q-06 : 계약 파일과 JSON Schema 의 outcome 목록이 같은지 ---
    # JSON Schema 는 함수를 부를 수 없어 값이 겹쳐 적히는 유일한 자리다. 그 하나를 기계가 지킨다.
    $schemaOutcomes = @($schema.properties.cases.items.properties.outcome.enum)
    if ($schemaOutcomes.Count -ne $contractOutcomes.Count -or
        @($schemaOutcomes | Where-Object { $contractOutcomes -notcontains $_ }).Count -ne 0) {
        throw "VERDICT_CONTRACT_MISMATCH"
    }

    $matrix = Get-Content -LiteralPath (Join-Path $fixtureRoot "case-matrix.json") -Raw | ConvertFrom-Json
    if (@($matrix.rowsInOrder).Count -ne 16 -or @($matrix.transportsInOrder).Count -ne 4) {
        throw "CASE_MATRIX_INVALID"
    }
    $caseIds = for ($value = [int]$matrix.caseIdMinimum; $value -le [int]$matrix.caseIdMaximum; $value++) {
        [string]::Format([Globalization.CultureInfo]::InvariantCulture, [string]$matrix.caseIdFormat, $value)
    }
    if (@($caseIds).Count -ne 64 -or $caseIds[0] -ne "M-001" -or $caseIds[-1] -ne "M-064" -or @($caseIds | Select-Object -Unique).Count -ne 64) {
        throw "CASE_MATRIX_INVALID"
    }

    $prohibitedFixtures = Get-Content -LiteralPath (Join-Path $fixtureRoot "prohibited-pattern-cases.json") -Raw | ConvertFrom-Json
    foreach ($case in @($prohibitedFixtures.cases)) {
        $candidate = [string]::Concat([string[]]$case.pieces)
        if (-not (Test-ProhibitedContent -Text $candidate)) {
            throw "PROHIBITED_PATTERN_FIXTURE_INVALID"
        }
    }

    $identityFixtures = Get-Content -LiteralPath (Join-Path $fixtureRoot "identity-boundaries.json") -Raw | ConvertFrom-Json
    foreach ($fixture in @($identityFixtures.fixtures)) {
        if ($fixture.expectedCode -eq "APP_PATH_INVALID") {
            $candidate = [IO.Path]::GetFullPath((Join-Path $fixtureRoot ([string]$fixture.relativeExecutable)))
            $isInvalid = -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
                [IO.Path]::GetExtension($candidate) -ne ".exe" -or
                ((Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            if (-not $isInvalid) { throw "IDENTITY_BOUNDARY_INVALID" }
        }
        elseif ($fixture.expectedCode -eq "INTERFACE_NOT_FOUND" -and [uint32]$fixture.interfaceIndex -ne 0) {
            throw "IDENTITY_BOUNDARY_INVALID"
        }
        elseif ($fixture.expectedCode -eq "PACKAGE_IDENTITY_UNAVAILABLE" -and $null -ne $fixture.packageValue) {
            throw "IDENTITY_BOUNDARY_INVALID"
        }
    }

    $negativeResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $negativeResult | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
    $rejected = $false
    try { Assert-LimitedResult -Result $negativeResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    $livePass = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $livePass.mode = "LIVE"
    $livePass.verdict = "PASS"
    $livePass.cleanupOutcome = "PASS"
    $rejected = $false
    try { Assert-LimitedResult -Result $livePass } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    $pendingLine = [Threading.Tasks.TaskCompletionSource[string]]::new()
    $rejected = $false
    try { [void](Read-BoundedProtocolTask -Task $pendingLine.Task -Timeout ([TimeSpan]::FromMilliseconds(1))) }
    catch { $rejected = $true }
    if (-not $rejected) { throw "LIVE_PROTOCOL_TIMEOUT_GATE_INVALID" }

    $duplicateCase = [pscustomobject]@{ caseId = "M-001"; outcome = "PASS"; failureCode = "NONE"; observedAtUtc = [DateTimeOffset]::UtcNow.ToString("O") }
    $duplicateResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $duplicateResult.caseTotal = 2; $duplicateResult.passCount = 2; $duplicateResult.cases = @($duplicateCase, $duplicateCase)
    $rejected = $false
    try { Assert-LimitedResult -Result $duplicateResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    $invalidCodeResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $invalidCodeResult.cleanupFailureCode = "UNLISTED_CODE"
    $rejected = $false
    try { Assert-LimitedResult -Result $invalidCodeResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    $failNoneResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $failNoneResult.caseTotal = 1; $failNoneResult.failCount = 1
    $failNoneResult.cases = @([pscustomobject]@{ caseId = "M-001"; outcome = "FAIL"; failureCode = "NONE"; observedAtUtc = [DateTimeOffset]::UtcNow.ToString("O") })
    $rejected = $false
    try { Assert-LimitedResult -Result $failNoneResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    $cleanupFailResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $cleanupFailResult.mode = "LIVE"; $cleanupFailResult.verdict = "PARTIAL"; $cleanupFailResult.cleanupOutcome = "FAIL"; $cleanupFailResult.cleanupFailureCode = "SESSION_CLOSE_FAILED"
    $rejected = $false
    try { Assert-LimitedResult -Result $cleanupFailResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    # --- Q-01 : inconclusiveCount 칸이 빠진 결과는 거부되어야 한다 ---
    # 이 시험이 통과해야 "필수 항목 12 -> 13" 이 실제로 들어갔다고 말할 수 있다.
    $missingCountResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $missingCountResult.PSObject.Properties.Remove("inconclusiveCount")
    $rejected = $false
    try { Assert-LimitedResult -Result $missingCountResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    # --- Q-02 : caseTotal 이 네 칸 합과 1 어긋나면 거부되어야 한다 ---
    $sumMismatchResult = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $sumMismatchResult.caseTotal = 1
    $rejected = $false
    try { Assert-LimitedResult -Result $sumMismatchResult } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    # --- Q-03 : INCONCLUSIVE 에 "재서 틀렸다" 코드를 붙이면 거부되어야 한다 ---
    # 붙일 수 있게 두면 FAIL 을 피해 가는 뒷문이 된다.
    $inconclusiveBackdoor = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $inconclusiveBackdoor.caseTotal = 1; $inconclusiveBackdoor.inconclusiveCount = 1
    $inconclusiveBackdoor.cases = @([pscustomobject]@{ caseId = "M-001"; outcome = "INCONCLUSIVE"; failureCode = "UNEXPECTED_INTERFACE"; observedAtUtc = [DateTimeOffset]::UtcNow.ToString("O") })
    $rejected = $false
    try { Assert-LimitedResult -Result $inconclusiveBackdoor } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }

    # --- Q-04 : FAIL 에 "관찰 못 함" 코드를 붙이면 거부되어야 한다 ---
    # 붙일 수 있게 두면 "관찰 못 함"과 "재서 틀렸음"이 한 칸에 섞인다.
    $failInconclusiveCode = $safeFixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $failInconclusiveCode.caseTotal = 1; $failInconclusiveCode.failCount = 1
    $failInconclusiveCode.cases = @([pscustomobject]@{ caseId = "M-001"; outcome = "FAIL"; failureCode = "NEW_CONNECTION_NOT_OBSERVED"; observedAtUtc = [DateTimeOffset]::UtcNow.ToString("O") })
    $rejected = $false
    try { Assert-LimitedResult -Result $failInconclusiveCode } catch { $rejected = $true }
    if (-not $rejected) { throw "NEGATIVE_RESULT_GATE_INVALID" }
}

function Get-NetworkFingerprint {
    $routeRows = Get-NetRoute -ErrorAction Stop |
        Select-Object AddressFamily, DestinationPrefix, InterfaceIndex, NextHop, RouteMetric, State |
        Sort-Object AddressFamily, DestinationPrefix, InterfaceIndex, NextHop, RouteMetric, State
    $dnsRows = Get-DnsClientServerAddress -ErrorAction Stop |
        Select-Object InterfaceIndex, AddressFamily, ServerAddresses |
        ForEach-Object {
            [pscustomobject]@{
                InterfaceIndex = $_.InterfaceIndex
                AddressFamily = $_.AddressFamily
                ServerAddresses = @($_.ServerAddresses | Sort-Object)
            }
        } | Sort-Object InterfaceIndex, AddressFamily
    $adapterRows = Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object { $_.Name -notlike "VpnRtr-*" -and $_.InterfaceDescription -notmatch '(?i)WireGuard' } |
        Select-Object InterfaceIndex, Status |
        Sort-Object InterfaceIndex, Status

    $canonical = [ordered]@{
        routes = @($routeRows)
        dns = @($dnsRows)
        adapters = @($adapterRows)
    } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

# ---------------------------------------------------------------------------
# 실행 폴더 (설계 §7.1 · §7.2 / FR-12 / AC-12-1 · AC-12-2)
#
# spool($temporaryRoot)의 형제 폴더다. finally(:1561-1565)가 지우는 것은 spool 이고
# 이 폴더는 그 밖이라 실기가 끝나도 남는다.
# 원문 진단과 관찰 기록이 들어가므로 spool 과 같은 방식으로 잠근다.
# 결과 JSON 에는 이 폴더의 내용이 한 글자도 들어가지 않는다.
# ---------------------------------------------------------------------------
function New-RunDirectory {
    if (-not (Test-Path -LiteralPath $runDirectoryBase)) {
        [void][IO.Directory]::CreateDirectory($runDirectoryBase)
    }
    # 폴더가 이미 있어도 매번 잠그고 매번 확인한다. 형제인 spool(:237-242)과 같은 방식이다.
    # 새로 만들 때만 잠그면, 지난 실행이나 다른 도구가 만들어 둔 폴더는 잠기지 않은 채로 쓰인다.
    Set-PrivateAcl -Path $runDirectoryBase -Kind Directory
    Assert-NoReparsePath -Path $runDirectoryBase
    Assert-PrivateAcl -Path $runDirectoryBase
    if (Test-Path -LiteralPath $runDirectory) { throw "RUN_DIRECTORY_ALREADY_EXISTS" }
    [void][IO.Directory]::CreateDirectory($runDirectory)
    Set-PrivateAcl -Path $runDirectory -Kind Directory
    Assert-NoReparsePath -Path $runDirectory
    Assert-PrivateAcl -Path $runDirectory
}

function Write-RunDirectoryText {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Append
    )

    if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { return }
    $fullPath = Assert-PathUnderRoot -Path (Join-Path $runDirectory $FileName) -Root $runDirectory
    $encoding = [Text.UTF8Encoding]::new($false)
    if ($Append) { [IO.File]::AppendAllText($fullPath, $Text, $encoding) }
    else { [IO.File]::WriteAllText($fullPath, $Text, $encoding) }
    try { Set-PrivateAcl -Path $fullPath -Kind File } catch { }
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Command
    )

    $logPath = Join-Path $temporaryRoot ("step-" + $Name + ".tmp")
    $stepFailed = $true
    try {
        & $Command *> $logPath
        $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
        $stepFailed = $exitCode -ne 0
        return $exitCode
    }
    catch {
        # 실패한 단계와 원인을 지우지 않는다. "C++ 컴파일러가 없다"가
        # "게시물이 없다"로 바뀌어 나오는 일을 막는다 (AC-12-2).
        $stepFailed = $true
        Write-RunDirectoryText -FileName "step-failures.txt" -Append -Text (
            "{0} step={1} error={2}`n" -f [DateTimeOffset]::UtcNow.ToString("O"), $Name, ($_.Exception.Message -replace "\s+", " "))
        return 1
    }
    finally {
        # 성공했으면 지금처럼 그냥 지운다. 실패했을 때만 원문을 실행 폴더로 옮긴다.
        if ($stepFailed -and (Test-Path -LiteralPath $logPath -PathType Leaf) -and
            (Test-Path -LiteralPath $runDirectory -PathType Container)) {
            try {
                $destination = Assert-PathUnderRoot -Path (Join-Path $runDirectory ("step-" + $Name + ".log")) -Root $runDirectory
                Copy-Item -LiteralPath $logPath -Destination $destination -Force
                Set-PrivateAcl -Path $destination -Kind File
            }
            catch { }
        }
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Harness {
    param(
        [string[]]$HarnessArguments = @(),
        [AllowNull()][string]$StandardInputJson,
        [AllowNull()][string]$ExecutablePath
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { "dotnet" } else { $ExecutablePath }
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    $argumentPrefix = if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { @("run", "--project", $harnessProject, "--no-build", "--") } else { @() }
    foreach ($argument in $argumentPrefix + $HarnessArguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ ExitCode = 1; Output = $null }
        }
        if ($null -ne $StandardInputJson) {
            if ([Text.Encoding]::UTF8.GetByteCount($StandardInputJson) -gt 65536 -or $StandardInputJson.Contains("`n") -or $StandardInputJson.Contains("`r")) {
                return [pscustomobject]@{ ExitCode = 1; Output = $null }
            }
            $process.StandardInput.WriteLine($StandardInputJson)
        }
        $process.StandardInput.Close()
        $output = $process.StandardOutput.ReadToEnd()
        [void]$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ([Text.Encoding]::UTF8.GetByteCount($output) -gt 1MB) {
            return [pscustomobject]@{ ExitCode = 1; Output = $null }
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
    }
    finally {
        $process.Dispose()
    }
}

function Get-StaticImportClosure {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$SeedPaths
    )

    $fullRoot = [IO.Path]::GetFullPath($Root)
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($seed in $SeedPaths) { $pending.Enqueue([IO.Path]::GetFullPath($seed)) }
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $nodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $edges = @{}
    while ($pending.Count -gt 0) {
        $source = $pending.Dequeue()
        if ([IO.Path]::GetExtension($source).ToLowerInvariant() -notin @(".props", ".targets", ".proj", ".csproj")) {
            throw "FEATURE_MANIFEST_SCOPE_INVALID"
        }
        [void](Assert-PathUnderRoot -Path $source -Root $fullRoot)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
        Assert-NoReparsePath -Path $source
        [void]$nodes.Add($source)
        if (-not $visited.Add($source)) { continue }
        $edges[$source] = [Collections.Generic.List[string]]::new()
        $xml = [Xml.XmlDocument]::new()
        $xml.XmlResolver = $null
        try { $xml.LoadXml((Get-Content -LiteralPath $source -Raw)) }
        catch { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
        foreach ($import in @($xml.SelectNodes("//*[local-name()='Import']"))) {
            $projectValue = [string]$import.GetAttribute("Project")
            if ([string]::IsNullOrWhiteSpace($projectValue) -or
                $projectValue -match '\$\(|@\(|%\(|[%*?\[\]]' -or [IO.Path]::IsPathRooted($projectValue)) {
                throw "FEATURE_MANIFEST_SCOPE_INVALID"
            }
            $target = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($source)) $projectValue))
            if ([IO.Path]::GetExtension($target).ToLowerInvariant() -notin @(".props", ".targets", ".proj", ".csproj")) {
                throw "FEATURE_MANIFEST_SCOPE_INVALID"
            }
            [void](Assert-PathUnderRoot -Path $target -Root $fullRoot)
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
            Assert-NoReparsePath -Path $target
            $edges[$source].Add($target)
            [void]$nodes.Add($target)
            $pending.Enqueue($target)
        }
    }

    # 동일 파일은 한 번만 읽되, import 순환은 명시적으로 거부한다.
    $indegree = @{}
    foreach ($node in $nodes) { $indegree[$node] = 0 }
    foreach ($source in $edges.Keys) {
        foreach ($target in $edges[$source]) { $indegree[$target] = [int]$indegree[$target] + 1 }
    }
    $ready = [Collections.Generic.Queue[string]]::new()
    foreach ($node in $nodes) { if ([int]$indegree[$node] -eq 0) { $ready.Enqueue($node) } }
    $processed = 0
    while ($ready.Count -gt 0) {
        $node = $ready.Dequeue()
        $processed++
        if ($edges.ContainsKey($node)) {
            foreach ($target in $edges[$node]) {
                $indegree[$target] = [int]$indegree[$target] - 1
                if ([int]$indegree[$target] -eq 0) { $ready.Enqueue($target) }
            }
        }
    }
    if ($processed -ne $nodes.Count) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
    return @($nodes)
}

function Get-FeatureManifest {
    $files = [Collections.Generic.List[IO.FileInfo]]::new()
    # 관찰 스크립트는 결과를 만드는 코드다. 자동 검사를 통과한 뒤 실기 직전에 바뀌면
    # "이 값은 기계가 관찰한 것"이라는 주장이 무너진다. 그래서 무결성 사슬에 넣는다.
    # 폴더 단위로 넣으므로 여섯 번째 스크립트를 나중에 더해도 저절로 들어간다.
    # build-portable.ps1:285 의 같은 목록과 반드시 함께 고친다 — 한쪽만 고치면
    # Assert-FeatureManifestMatchesCurrent 가 FEATURE_MANIFEST_MISMATCH 를 던진다 (설계 §6.4).
    foreach ($directory in @(
        (Join-Path $repoRoot "windows\VpnRouter.WfpSpike"),
        (Join-Path $repoRoot "windows\VpnRouter.WfpSpike.Harness"),
        (Join-Path $repoRoot "scripts\windows\wfp-observation")
    )) {
        Get-ChildItem -LiteralPath $directory -Recurse -File |
            Where-Object { $_.FullName -notmatch '\\(?:bin|obj)\\' } |
            ForEach-Object { $files.Add($_) }
    }
    foreach ($path in @(
        "windows\VpnRouter.Tests\Program.cs",
        "windows\VpnRouter.Tests\VpnRouter.Tests.csproj",
        "windows\VpnRouter.slnx",
        "windows\VpnRouterVs.sln",
        "scripts\windows\build-portable.ps1",
        "scripts\windows\test-wfp-app-routing-spike.ps1"
    )) {
        $files.Add((Get-Item -LiteralPath (Join-Path $repoRoot $path)))
    }

    # MSBuild/NuGet가 프로젝트 상위에서 자동으로 소비하는 입력만 고정 이름 allowlist로 포함한다.
    $automaticBuildInputNames = @(
        "Directory.Build.props", "Directory.Build.targets", "Directory.Packages.props",
        "global.json", "NuGet.Config"
    )
    $ancestorStarts = @(
        $repoRoot,
        (Join-Path $repoRoot "windows"),
        (Join-Path $repoRoot "windows\VpnRouter.WfpSpike"),
        (Join-Path $repoRoot "windows\VpnRouter.WfpSpike.Harness"),
        (Join-Path $repoRoot "windows\VpnRouter.Tests")
    )
    $automaticImportSeeds = [Collections.Generic.List[string]]::new()
    foreach ($start in $ancestorStarts) {
        $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($start))
        while ($null -ne $cursor) {
            foreach ($name in $automaticBuildInputNames) {
                $candidate = Join-Path $cursor.FullName $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $files.Add((Get-Item -LiteralPath $candidate -Force))
                    if ([IO.Path]::GetExtension($candidate) -in @(".props", ".targets")) {
                        $automaticImportSeeds.Add([IO.Path]::GetFullPath($candidate))
                    }
                }
            }
            if ($cursor.FullName -eq $repoRoot) { break }
            $cursor = $cursor.Parent
        }
        if ($null -eq $cursor) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
    }

    # 프로젝트가 명시적으로 가져오는 정적 repo 내부 파일도 재귀적으로 포함한다.
    $importSeeds = [Collections.Generic.List[string]]::new()
    foreach ($project in @(
        "windows\VpnRouter.WfpSpike\VpnRouter.WfpSpike.csproj",
        "windows\VpnRouter.WfpSpike.Harness\VpnRouter.WfpSpike.Harness.csproj",
        "windows\VpnRouter.Tests\VpnRouter.Tests.csproj"
    )) { $importSeeds.Add((Join-Path $repoRoot $project)) }
    foreach ($seed in $automaticImportSeeds) { $importSeeds.Add($seed) }
    foreach ($importPath in @(Get-StaticImportClosure -Root $repoRoot -SeedPaths @($importSeeds))) {
        $files.Add((Get-Item -LiteralPath $importPath -Force))
    }
    Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | ForEach-Object { $files.Add($_) }

    $relativePaths = @($files | ForEach-Object {
        $_.FullName.Substring($repoRoot.Length).TrimStart([char[]]"\/").Replace('\', '/')
    } | Select-Object -Unique)
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
    $entries = [Collections.Generic.List[object]]::new($relativePaths.Count)
    foreach ($relativePath in $relativePaths) {
        if ($relativePath -match '(?i)\.conf$' -or $relativePath -match '(^|/)(?:bin|obj)(/|$)') {
            throw "FEATURE_MANIFEST_SCOPE_INVALID"
        }
        $filePath = Join-Path $repoRoot $relativePath.Replace('/', '\')
        $file = Get-Item -LiteralPath $filePath -Force
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
        $stageLine = @(git ls-files --stage -- $relativePath) | Select-Object -First 1
        if ($LASTEXITCODE -ne 0) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
        $indexBlobOid = $null
        if (-not [string]::IsNullOrWhiteSpace($stageLine)) {
            $match = [regex]::Match([string]$stageLine, '^[0-7]{6} ([0-9a-fA-F]{40,64}) [0-3]\t')
            if (-not $match.Success) { throw "FEATURE_MANIFEST_SCOPE_INVALID" }
            $indexBlobOid = $match.Groups[1].Value.ToLowerInvariant()
        }
        $entries.Add([ordered]@{
            relativePath = $relativePath
            length = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            indexBlobOid = $indexBlobOid
        })
    }
    $json = [ordered]@{ schemaVersion = 1; files = @($entries) } | ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{ Json = $json; Hash = (Get-Sha256Text -Text $json); Entries = @($entries) }
}

function Assert-FeatureManifestMatchesCurrent {
    param([Parameter(Mandatory)][string]$ManifestPath)

    Assert-NoReparsePath -Path $ManifestPath
    $published = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $current = Get-FeatureManifest
    if ($published.schemaVersion -ne 1 -or @($published.files).Count -ne @($current.Entries).Count) {
        throw "FEATURE_MANIFEST_MISMATCH"
    }
    $currentByPath = @{}
    foreach ($entry in $current.Entries) { $currentByPath[[string]$entry.relativePath] = $entry }
    foreach ($entry in @($published.files)) {
        $match = $currentByPath[[string]$entry.relativePath]
        if ($null -eq $match -or [long]$match.length -ne [long]$entry.length -or
            [string]$match.sha256 -ne [string]$entry.sha256 -or
            [string]$match.indexBlobOid -ne [string]$entry.indexBlobOid) {
            throw "FEATURE_MANIFEST_MISMATCH"
        }
    }
    return (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FixturesManifestHash {
    $hash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($fixtureRoot.Length).TrimStart([char[]]"\/").Replace('\', '/')
            $hash.AppendData([Text.Encoding]::UTF8.GetBytes($relative))
            $hash.AppendData([IO.File]::ReadAllBytes($_.FullName))
        }
        return [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
    }
    finally { $hash.Dispose() }
}

function Read-StrictPublishManifest {
    param([Parameter(Mandatory)][string]$Path)

    Assert-NoReparsePath -Path $Path
    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (@($manifest.PSObject.Properties.Name).Count -ne 2 -or
        $manifest.PSObject.Properties.Name -notcontains "schemaVersion" -or
        $manifest.PSObject.Properties.Name -notcontains "files" -or
        $manifest.schemaVersion -ne 1) {
        throw "PUBLISH_MANIFEST_INVALID"
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($manifest.files)) {
        if (@($entry.PSObject.Properties.Name).Count -ne 3 -or
            $entry.PSObject.Properties.Name -notcontains "relativePath" -or
            $entry.PSObject.Properties.Name -notcontains "sha256" -or
            $entry.PSObject.Properties.Name -notcontains "length" -or
            [IO.Path]::IsPathRooted([string]$entry.relativePath) -or
            [string]$entry.relativePath -match '(^|[\\/])\.\.([\\/]|$)' -or
            [string]$entry.relativePath -notmatch '^[A-Za-z0-9._/\\-]+$' -or
            -not $seen.Add(([string]$entry.relativePath).Replace('\', '/')) -or
            [string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
            [long]$entry.length -lt 0) {
            throw "PUBLISH_MANIFEST_INVALID"
        }
    }
    if ($seen.Count -eq 0) { throw "PUBLISH_MANIFEST_INVALID" }
    return $manifest
}

function Test-SpikeExtraction {
    $artifact = Join-Path $repoRoot "artifacts\wfp-spike\VpnRouter-WfpSpike-0.1.0-x64.exe"
    $expectedManifestPath = Join-Path $repoRoot "artifacts\wfp-spike\wfp-spike.manifest.json"
    if (-not (Test-Path -LiteralPath $artifact) -or -not (Test-Path -LiteralPath $expectedManifestPath)) {
        throw "PUBLISH_CONTENT_MISSING"
    }
    $expectedManifest = Read-StrictPublishManifest -Path $expectedManifestPath
    $expectedManifestHash = (Get-FileHash -LiteralPath $expectedManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $process = Start-Process -FilePath $artifact -ArgumentList "--extract-only" -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "PUBLISH_CONTENT_MISSING"
    }

    $cacheRoot = Join-Path $env:LOCALAPPDATA "VpnRouter\app"
    $extracted = $null
    foreach ($candidate in @(Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "0.1.0-*" })) {
        $candidateManifest = Join-Path $candidate.FullName "wfp-spike\wfp-spike.manifest.json"
        if (Test-Path -LiteralPath $candidateManifest) {
            Assert-NoReparsePath -Path $candidateManifest
            if ((Get-FileHash -LiteralPath $candidateManifest -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedManifestHash) {
                $extracted = $candidate
                break
            }
        }
    }
    if ($null -eq $extracted) {
        throw "PUBLISH_CONTENT_MISSING"
    }

    $payloadRoot = Join-Path $extracted.FullName "wfp-spike"
    Assert-NoReparsePath -Path $payloadRoot
    foreach ($entry in @($expectedManifest.files)) {
        $relative = ([string]$entry.relativePath).Replace('/', '\')
        $filePath = Assert-PathUnderRoot -Path (Join-Path $payloadRoot $relative) -Root $payloadRoot
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "PUBLISH_CONTENT_MISSING" }
        Assert-NoReparsePath -Path $filePath
        $file = Get-Item -LiteralPath $filePath
        if ($file.Length -ne [long]$entry.length -or
            (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
            throw "PUBLISH_CONTENT_MISMATCH"
        }
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File | Where-Object { $_.Name -ne "wfp-spike.manifest.json" })
    if ($actualFiles.Count -ne @($expectedManifest.files).Count) {
        throw "PUBLISH_CONTENT_MISMATCH"
    }

    $harnessExecutable = Join-Path $payloadRoot "VpnRouter.WfpSpike.Harness.exe"
    $abiEvidencePath = Join-Path $payloadRoot "wfp-sdk-abi-x64.json"
    $gateEvidencePath = Join-Path $payloadRoot "wfp-gate-evidence.json"
    $abiProbeSource = Join-Path $repoRoot "windows\VpnRouter.WfpSpike\Native\WfpSdkAbiProbe.cpp"
    # AC-12-3: wfp-sdk-abi-x64.json 이 없으면 실패한다.
    # 지금은 build-portable.ps1 이 늘 만들어 주어 이 구멍이 안 열리지만,
    # 증거 사슬의 한 칸이 조용히 지나갈 수 있는 자리를 실기 전에 막는다.
    if (-not (Test-Path -LiteralPath (Join-Path $extracted.FullName ".complete")) -or
        -not (Test-Path -LiteralPath $harnessExecutable) -or
        -not (Test-Path -LiteralPath $abiEvidencePath) -or
        -not (Test-Path -LiteralPath $gateEvidencePath) -or
        -not (Test-Path -LiteralPath $abiProbeSource)) {
        throw "PUBLISH_CONTENT_MISSING"
    }
    $featureManifestPath = Join-Path $payloadRoot "wfp-feature-manifest.json"
    $featureManifestHash = Assert-FeatureManifestMatchesCurrent -ManifestPath $featureManifestPath
    $gateEvidence = Get-Content -LiteralPath $gateEvidencePath -Raw | ConvertFrom-Json
    if (@($gateEvidence.PSObject.Properties.Name).Count -ne 4 -or $gateEvidence.schemaVersion -ne 1 -or
        $gateEvidence.worktreeFingerprint -ne $featureManifestHash -or
        $gateEvidence.scriptSha256 -ne (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -or
        $gateEvidence.fixturesManifestSha256 -ne (Get-FixturesManifestHash)) {
        throw "PUBLISH_CONTENT_MISMATCH"
    }

    $libraries = @(
        @{ Name = "Fwpuclnt.dll"; Exports = @("FwpmEngineOpen0", "FwpmConnectionPolicyAdd0") },
        @{ Name = "Iphlpapi.dll"; Exports = @("ConvertInterfaceIndexToLuid", "ConvertInterfaceLuidToIndex") }
    )
    foreach ($library in $libraries) {
        [IntPtr]$handle = [IntPtr]::Zero
        if (-not [Runtime.InteropServices.NativeLibrary]::TryLoad($library.Name, [ref]$handle)) {
            throw "NATIVE_EXPORT_MISSING"
        }
        try {
            foreach ($export in $library.Exports) {
                [IntPtr]$address = [IntPtr]::Zero
                if (-not [Runtime.InteropServices.NativeLibrary]::TryGetExport($handle, $export, [ref]$address)) {
                    throw "NATIVE_EXPORT_MISSING"
                }
            }
        }
        finally {
            [Runtime.InteropServices.NativeLibrary]::Free($handle)
        }
    }

    return [pscustomobject]@{
        PayloadRoot = $payloadRoot
        HarnessExecutable = $harnessExecutable
        ArtifactSha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        PublishManifestSha256 = $expectedManifestHash
        HarnessSha256 = (Get-FileHash -LiteralPath $harnessExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        # 대체 해시 분기를 없앴다 (AC-12-3). 위 필수 존재 검사를 지났으면
        # 이 자리에 올 때 파일이 반드시 있다. 없는 것을 상수 해시로 덮지 않는다.
        AbiEvidenceSha256 = (Get-FileHash -LiteralPath $abiEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        AbiProbeSourceSha256 = (Get-FileHash -LiteralPath $abiProbeSource -Algorithm SHA256).Hash.ToLowerInvariant()
        WorktreeFingerprint = ([string]$gateEvidence.worktreeFingerprint).ToLowerInvariant()
        ScriptSha256 = ([string]$gateEvidence.scriptSha256).ToLowerInvariant()
        FixturesManifestSha256 = ([string]$gateEvidence.fixturesManifestSha256).ToLowerInvariant()
    }
}

function Assert-PrivatePayloadManifest {
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$ExpectedManifestSha256
    )

    $manifestPath = Join-Path $PayloadRoot "wfp-spike.manifest.json"
    Assert-NoReparsePath -Path $PayloadRoot
    if (-not (Test-Path -LiteralPath $manifestPath) -or
        (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ExpectedManifestSha256) {
        throw "PRIVATE_PAYLOAD_MISMATCH"
    }
    $manifest = Read-StrictPublishManifest -Path $manifestPath
    foreach ($entry in @($manifest.files)) {
        $path = Assert-PathUnderRoot -Path (Join-Path $PayloadRoot ([string]$entry.relativePath)) -Root $PayloadRoot
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "PRIVATE_PAYLOAD_MISMATCH" }
        Assert-NoReparsePath -Path $path
        $file = Get-Item -LiteralPath $path -Force
        if ($file.Length -ne [long]$entry.length -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
            throw "PRIVATE_PAYLOAD_MISMATCH"
        }
    }
    $actual = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File | Where-Object { $_.Name -ne "wfp-spike.manifest.json" })
    if ($actual.Count -ne @($manifest.files).Count) { throw "PRIVATE_PAYLOAD_MISMATCH" }
}

function Copy-AndLockPrivatePayload {
    param([Parameter(Mandatory)]$ExtractionEvidence)

    $destinationRoot = Join-Path $temporaryRoot "verified-payload"
    if (Test-Path -LiteralPath $destinationRoot) { throw "PRIVATE_PAYLOAD_ALREADY_EXISTS" }
    [void][IO.Directory]::CreateDirectory($destinationRoot)
    Set-PrivateAcl -Path $destinationRoot -Kind Directory
    $manifest = Read-StrictPublishManifest -Path (Join-Path $ExtractionEvidence.PayloadRoot "wfp-spike.manifest.json")
    foreach ($entry in @($manifest.files)) {
        $relative = ([string]$entry.relativePath).Replace('/', '\')
        Copy-PrivateNewFile -Source (Join-Path $ExtractionEvidence.PayloadRoot $relative) -Destination (Join-Path $destinationRoot $relative)
    }
    Copy-PrivateNewFile -Source (Join-Path $ExtractionEvidence.PayloadRoot "wfp-spike.manifest.json") -Destination (Join-Path $destinationRoot "wfp-spike.manifest.json")
    Assert-PrivatePayloadManifest -PayloadRoot $destinationRoot -ExpectedManifestSha256 $ExtractionEvidence.PublishManifestSha256

    foreach ($file in @(Get-ChildItem -LiteralPath $destinationRoot -Recurse -File | Sort-Object FullName)) {
        Assert-NoReparsePath -Path $file.FullName
        $payloadReadHandles.Add([IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read))
    }
    return [pscustomobject]@{
        Root = $destinationRoot
        HarnessExecutable = Join-Path $destinationRoot "VpnRouter.WfpSpike.Harness.exe"
        ManifestSha256 = $ExtractionEvidence.PublishManifestSha256
    }
}

function Test-PrivatePayloadLockNegativeGates {
    param([Parameter(Mandatory)]$PrivatePayload)

    $target = Join-Path $PrivatePayload.Root "wfp-feature-manifest.json"
    if (-not (Test-Path -LiteralPath $target)) { throw "PRIVATE_PAYLOAD_LOCK_GATE_INVALID" }
    $writeRejected = $false
    try {
        $writer = [IO.FileStream]::new($target, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $writer.Dispose()
    }
    catch { $writeRejected = $true }
    $deleteRejected = $false
    try { [IO.File]::Delete($target); $deleteRejected = -not (Test-Path -LiteralPath $target) } catch { $deleteRejected = $true }
    if (-not $writeRejected -or -not $deleteRejected -or -not (Test-Path -LiteralPath $target)) {
        throw "PRIVATE_PAYLOAD_LOCK_GATE_INVALID"
    }
}

function Test-IsElevatedAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-BoundedValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$AllowEmpty
    )

    $value = Read-Host $Prompt
    if ((-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($value)) -or $value.Length -gt 65535) {
        throw "LIVE_INPUT_INVALID"
    }
    return $value
}

# ---------------------------------------------------------------------------
# 측정 (설계 §4.2 · §7.3 / FR-11 · FR-14 / AC-11-1 · NFR-04)
#
# 값을 미리 넘기면 그 값은 측정이 아니다. -LiveObservationJson 으로 들어온 값은
# 하네스를 띄우기 "전"에 정해진 값이고, 스크립트는 그 값이 기계에서 왔는지
# 확인할 수단이 없다. 그래서 그 경로로 들어온 값의 출처는 HUMAN 이다.
# 본 실행은 그 인자를 쓰지 않고 정책이 걸린 창 안에서 기계가 잰다 (출처 MACHINE).
# ---------------------------------------------------------------------------
function New-CaseObservation {
    param(
        [Parameter(Mandatory)][string]$CaseId,
        [Parameter(Mandatory)][string]$Outcome,
        [Parameter(Mandatory)][string]$FailureCode,
        [Parameter(Mandatory)][ValidateSet("MACHINE", "HUMAN")][string]$Source,
        [AllowEmptyString()][string]$Rationale = "",
        [hashtable]$Evidence = @{}
    )

    # 계약에 없는 짝은 만들지 않는다. 여기서 막히면 그 자리를 고쳐야 한다.
    if (-not (Test-OutcomeFailureCodePair -Outcome $Outcome -FailureCode $FailureCode)) {
        throw "LIVE_INPUT_INVALID"
    }

    # 관찰값·시각·출처·근거 문장은 실행 폴더와 실행표에만 남는다.
    $record = [ordered]@{
        caseId        = $CaseId
        outcome       = $Outcome
        failureCode   = $FailureCode
        source        = $Source
        observedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        rationale     = $Rationale
    }
    foreach ($key in @($Evidence.Keys)) { $record[$key] = $Evidence[$key] }
    Write-RunDirectoryText -FileName ("observation-" + $CaseId + ".json") -Text ($record | ConvertTo-Json -Depth 6)

    # 하네스에는 세 칸만 보낸다. WfpObservationCollector.cs:21 이 정확히 세 칸을 요구하고,
    # 근거 문장이 결과에 들어가면 금지 낱말 검사에 걸려 결과 전체가 폐기된다 (BL-07).
    return [ordered]@{
        caseId      = $CaseId
        outcome     = $Outcome
        failureCode = $FailureCode
    }
}

function Invoke-ObservationScript {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    # 글자를 이어 붙여 명령줄을 만들지 않고, 글자를 명령으로 되돌려 실행하지도 않는다.
    # & <경로> 로 부르고 인자는 하나씩 넘긴다 (G-09 · 회귀 확인 GR-15).
    $scriptPath = Join-Path $observationScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return $null }
    try {
        $output = & $scriptPath @Arguments
        $lines = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($lines.Count -eq 0) { return $null }
        return ([string]$lines[-1] | ConvertFrom-Json)
    }
    catch {
        Write-RunDirectoryText -FileName "step-failures.txt" -Append -Text (
            "{0} tool={1} error={2}`n" -f [DateTimeOffset]::UtcNow.ToString("O"), $ScriptName, ($_.Exception.Message -replace "\s+", " "))
        return $null
    }
}

function Measure-LimitedObservation {
    param([Parameter(Mandatory)][string]$CaseId)

    # --- 1 : 정책이 걸린 시각이 없으면 아무것도 만들지 않는다 ---------------
    # 시각 없이 분류하면 정책 적용 전 연결이 섞인다. 그것은 측정이 아니다.
    if ($null -eq $policyAppliedAtUtc) { throw "LIVE_PROTOCOL_INVALID" }

    $number = [int]$CaseId.Substring(2)

    # --- 2 : 패키지 사례 -----------------------------------------------------
    if ($number -ge 33) {
        return New-CaseObservation -CaseId $CaseId -Outcome "NOT_RUN" -FailureCode "PACKAGE_IDENTITY_UNAVAILABLE" -Source "MACHINE" `
            -Rationale "WfpNativeApi.cs:27 이 패키지 신원 변환을 열지 않아 코드 수준에서 NOT_RUN 만 가능함"
    }

    if ($null -eq $measurementSettings -or $caseMatrixRows.Count -ne 16 -or $caseMatrixTransports.Count -ne 4) {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale "측정 설정 또는 사례 행렬이 없어 관찰 수단이 성립하지 않음"
    }

    # 행과 전송 방식은 case-matrix.json 에서 뽑는다. 그 파일은 한 글자도 고치지 않는다.
    $row = $caseMatrixRows[[math]::Floor(($number - 1) / 4)]
    $transport = [string]$caseMatrixTransports[($number - 1) % 4]
    $ipVersion = [string]$row.ipVersion
    $expectedPath = [string]$row.expectedPath
    $isDns = $transport -eq "DNS"
    $isIpv6 = $ipVersion -eq "IPv6"

    # --- 3 : 터널이 IPv6 를 안 주면 IPv6 사례는 잴 수 없다. 재시도하지 않는다 ---
    if ($isIpv6 -and [string]$measurementSettings.ipv6Verdict -ne "MEASURE") {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale ("이 회선과 시험용 터널 모두 IPv6 전역 주소와 ::/0 경로를 주지 않아 관찰 수단이 성립하지 않음 (관찰 시각: {0})" -f [DateTimeOffset]::UtcNow.ToString("O"))
    }

    # --- 4 : 관찰 A 가 "환경"이면 안 고른 앱의 기대 경로가 성립하지 않는다 ---
    if ([string]$measurementSettings.observationAPath -eq "VPN" -and $expectedPath -eq "BASELINE") {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale ("터널이 기본 경로를 통째로 가져가 정책과 무관하게 모든 앱이 VPN 으로 나감. 안 고른 앱의 기대 경로 BASELINE 이 이 환경에서 성립하지 않음 (관찰 시각: {0})" -f [DateTimeOffset]::UtcNow.ToString("O"))
    }

    # --- 5 : 남은 예산이 없으면 재지 않고 채운다 ----------------------------
    # 하네스를 죽게 두지 않는다. 30분에 걸려 하네스가 죽으면 정리가 안 돌아 정책이 남는다.
    if ($null -ne $measurementDeadlineUtc -and [DateTimeOffset]::UtcNow -ge $measurementDeadlineUtc) {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale ("측정 마감(정책 적용 뒤 20분)을 넘겨 재지 않음 (마감: {0})" -f $measurementDeadlineUtc.ToString("O"))
    }

    # --- 6 : 잰다 -----------------------------------------------------------
    $caseStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $policyText = $policyAppliedAtUtc.ToString("O")
    $baselineInterfaceIndex = [uint32]$measurementSettings.baselineInterfaceIndex
    $targetAddress = if ($isIpv6) { [string]$measurementSettings.ipv6TargetAddress } else { [string]$measurementSettings.ipv4TargetAddress }
    $targetPort = if ($isIpv6) { [int]$measurementSettings.ipv6TargetPort } else { [int]$measurementSettings.ipv4TargetPort }
    $dnsServer = if ($isIpv6) { [string]$measurementSettings.ipv6DnsServer } else { [string]$measurementSettings.ipv4DnsServer }
    $appPath = if ([string]$row.identity -like "SELECTED_*") { [string]$measurementSettings.selectedAppPath } else { [string]$measurementSettings.unselectedAppPath }
    $observedAddress = if ($isDns) { $dnsServer } else { $targetAddress }
    $observedPort = if ($isDns) { 53 } else { $targetPort }

    # ① 관찰기를 잡기 모드로 시작
    $startResult = Invoke-ObservationScript -ScriptName "Get-WfpSpikeInterface.ps1" -Arguments @{
        Mode                   = "Start"
        VpnInterfaceIndex      = $measurementInterfaceIndex
        BaselineInterfaceIndex = $baselineInterfaceIndex
        TargetAddress          = $observedAddress
        TargetPort             = $observedPort
        Transport              = $transport
        RunDirectory           = $runDirectory
        CaseId                 = $CaseId
        PolicyAppliedAtUtc     = $policyText
    }
    if ($null -eq $startResult -or [string]$startResult.status -ne "OK") {
        $caseStopwatch.Stop()
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale "관찰기를 시작하지 못해 이 사례를 재지 못함" `
            -Evidence @{ transport = $transport; ipVersion = $ipVersion; expectedPath = $expectedPath; observerStatus = "START_FAILED" }
    }

    # ② 흐름을 한 개 만든다
    $flowArguments = @{
        AppPath            = $appPath
        Transport          = $transport
        IpVersion          = $ipVersion
        PolicyAppliedAtUtc = $policyText
        RunDirectory       = $runDirectory
        TimeoutSeconds     = 45
    }
    if ($isDns) {
        $flowArguments["DnsServer"] = $dnsServer
        $flowArguments["QueryName"] = [string]$measurementSettings.queryName
    }
    else {
        $flowArguments["TargetAddress"] = $targetAddress
        $flowArguments["TargetPort"] = $targetPort
    }
    # 행이 "겹치는 경로"를 요구하면 기준 인터페이스로 가는 /32(또는 /128) 경로를 심어
    # WFP 정책과 경쟁시킨다. 이것이 R2-AC-06-4 가 재려던 것이다.
    if ([bool]$row.matchingHostRoute) {
        $flowArguments["InstallHostRoute"] = $true
        $flowArguments["HostRouteInterfaceIndex"] = $baselineInterfaceIndex
    }
    $flowResult = Invoke-ObservationScript -ScriptName "New-WfpSpikeFlow.ps1" -Arguments $flowArguments

    # ③ 관찰기를 멈추고 판정
    $stopArguments = @{
        Mode                   = "Stop"
        VpnInterfaceIndex      = $measurementInterfaceIndex
        BaselineInterfaceIndex = $baselineInterfaceIndex
        TargetAddress          = $observedAddress
        TargetPort             = $observedPort
        Transport              = $transport
        RunDirectory           = $runDirectory
        CaseId                 = $CaseId
        PolicyAppliedAtUtc     = $policyText
    }
    if ($null -ne $flowResult -and $null -ne $flowResult.processId) {
        $stopArguments["FlowProcessId"] = [uint32]$flowResult.processId
    }
    $stopResult = Invoke-ObservationScript -ScriptName "Get-WfpSpikeInterface.ps1" -Arguments $stopArguments
    $caseStopwatch.Stop()

    $flowStatus = if ($null -eq $flowResult) { "ERROR" } else { [string]$flowResult.status }
    $flowReason = if ($null -eq $flowResult) { "TOOL_UNAVAILABLE" } else { [string]$flowResult.failureReason }
    $observerStatus = if ($null -eq $stopResult) { "ERROR" } else { [string]$stopResult.status }
    $observedPath = if ($null -eq $stopResult) { "UNOBSERVED" } else { [string]$stopResult.observedPath }

    $evidence = @{
        transport              = $transport
        ipVersion              = $ipVersion
        identity               = [string]$row.identity
        expectedPath           = $expectedPath
        observedPath           = $observedPath
        observedInterfaceIndex = if ($null -eq $stopResult) { $null } else { $stopResult.observedInterfaceIndex }
        packetCount            = if ($null -eq $stopResult) { 0 } else { $stopResult.packetCount }
        method                 = if ($null -eq $stopResult) { "PKTMON" } else { [string]$stopResult.method }
        hostRouteInstalled     = if ($null -eq $flowResult) { $false } else { [bool]$flowResult.hostRouteInstalled }
        newConnectionCreated   = if ($null -eq $flowResult) { $false } else { [bool]$flowResult.newConnectionCreated }
        flowStatus             = $flowStatus
        flowFailureReason      = $flowReason
        observerStatus         = $observerStatus
        elapsedSeconds         = [math]::Round($caseStopwatch.Elapsed.TotalSeconds, 3)
    }

    # 사례 하나의 상한 60초 (E-11). 넘으면 그 사례만 관찰 못 함으로 닫는다.
    if ($caseStopwatch.Elapsed.TotalSeconds -ge 60) {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "NEW_CONNECTION_NOT_OBSERVED" -Source "MACHINE" `
            -Rationale "사례 하나의 상한 60초를 넘겨 관찰을 마치지 못함" -Evidence $evidence
    }

    # 관찰기 자체가 못 돌았으면 "관찰 못 함"이 아니라 "수단이 안 섰다"이다 (§4.2 매핑 표).
    if ($observerStatus -ne "OK") {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "ENVIRONMENT_UNAVAILABLE" -Source "MACHINE" `
            -Rationale "관찰기가 정상으로 끝나지 않아 이 사례를 재지 못함" -Evidence $evidence
    }

    # 흐름을 못 만들었으면 잰 것이 없다. 시간이 모자라 못 본 것과 도구가 안 선 것을 가른다.
    if ($flowStatus -ne "OK") {
        $flowFailureCode = if ($flowReason -eq "FLOW_TIMEOUT") { "NEW_CONNECTION_NOT_OBSERVED" } else { "ENVIRONMENT_UNAVAILABLE" }
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode $flowFailureCode -Source "MACHINE" `
            -Rationale "흐름 발생기가 새 연결을 만들지 못함" -Evidence $evidence
    }

    if ($observedPath -ceq "UNOBSERVED") {
        return New-CaseObservation -CaseId $CaseId -Outcome "INCONCLUSIVE" -FailureCode "NEW_CONNECTION_NOT_OBSERVED" -Source "MACHINE" `
            -Rationale "정책이 걸린 창 안에서 새 연결이 어느 인터페이스로 나갔는지 관찰되지 않음" -Evidence $evidence
    }

    if ($observedPath -ceq $expectedPath) {
        return New-CaseObservation -CaseId $CaseId -Outcome "PASS" -FailureCode "NONE" -Source "MACHINE" `
            -Rationale "기대한 경로가 실제로 관찰됨" -Evidence $evidence
    }

    # 재서 답이 나왔는데 기대와 달랐다. 이것은 FAIL 이고 INCONCLUSIVE 가 아니다.
    $mismatchCode = if ($isDns) { "DNS_APP_ID_NOT_PROPAGATED" } else { "UNEXPECTED_INTERFACE" }
    return New-CaseObservation -CaseId $CaseId -Outcome "FAIL" -FailureCode $mismatchCode -Source "MACHINE" `
        -Rationale "관찰된 경로가 기대와 다름" -Evidence $evidence
}

function Set-PolicyAppliedTimestamp {
    param([Parameter(Mandatory)][DateTimeOffset]$ReadyAtUtc)

    # 하네스가 READY 를 낸 시각이 곧 "정책이 걸린 시각"이다. 새 배선이 필요 없다 —
    # 이 값은 지금까지 파싱만 하고 버려지던 값이다 (설계 §7.3 M-1 · BL-08).
    # 처음 한 번만 정한다. 뒤에서 다시 정하면 측정 마감이 밀린다.
    if ($null -ne $script:policyAppliedAtUtc) { return }
    $script:policyAppliedAtUtc = $ReadyAtUtc
    # 측정 마감 20분. 하네스 대기 상한 30분보다 10분 이르다 —
    # 30분에 걸려 하네스가 죽으면 정리가 안 돌아 정책이 남는다.
    $script:measurementDeadlineUtc = $ReadyAtUtc.AddMinutes(20)
}

function Resolve-LimitedObservation {
    param([Parameter(Mandatory)][string]$CaseId)

    # 미리 넘어온 값이 있으면 그대로 쓰되 출처를 HUMAN 으로 적는다.
    # 스크립트는 그 값이 기계에서 왔는지 확인할 수단이 없다 (BL-03 · T-3).
    if ($providedLiveObservations.ContainsKey($CaseId)) {
        $provided = $providedLiveObservations[$CaseId]
        return New-CaseObservation -CaseId $CaseId `
            -Outcome ([string]$provided.outcome) -FailureCode ([string]$provided.failureCode) -Source "HUMAN" `
            -Rationale "-LiveObservationJson 으로 미리 넘어온 값. 스크립트는 이 값이 기계에서 왔는지 확인할 수단이 없음"
    }
    return Measure-LimitedObservation -CaseId $CaseId
}

function Initialize-ProvidedLiveObservations {
    param(
        [Parameter(Mandatory)][string]$Json,
        # 개수는 상수가 아니다. 패키지 입력이 없으면 32건, 있으면 64건이다.
        [Parameter(Mandatory)][ValidateSet(32, 64)][int]$ExpectedCount
    )

    try { $items = @($Json | ConvertFrom-Json -Depth 4) }
    catch { throw "LIVE_INPUT_INVALID" }
    if ($items.Count -ne $ExpectedCount) { throw "LIVE_INPUT_INVALID" }

    foreach ($item in $items) {
        $propertyNames = @($item.PSObject.Properties.Name)
        if ($propertyNames.Count -ne 3 -or
            @($propertyNames | Where-Object { $_ -notin @("caseId", "outcome", "failureCode") }).Count -ne 0) {
            throw "LIVE_INPUT_INVALID"
        }
        $caseId = [string]$item.caseId
        $outcome = ([string]$item.outcome).ToUpperInvariant()
        $failureCode = ([string]$item.failureCode).ToUpperInvariant()
        # 무늬는 M-001~M-064 로 넓히고, 이번 실행에서 실제로 받을 번호인지 따로 본다.
        if ($caseId -notmatch '^M-(00[1-9]|0[1-5][0-9]|06[0-4])$' -or
            [int]$caseId.Substring(2) -gt $ExpectedCount -or
            $providedLiveObservations.ContainsKey($caseId) -or
            @($outcomeFailureCodeContract.Keys) -notcontains $outcome -or
            $allowedResultCodes -notcontains $failureCode -or
            -not (Test-OutcomeFailureCodePair -Outcome $outcome -FailureCode $failureCode)) {
            throw "LIVE_INPUT_INVALID"
        }
        $providedLiveObservations[$caseId] = [ordered]@{
            caseId = $caseId
            outcome = $outcome
            failureCode = $failureCode
        }
    }
    if ((1..$ExpectedCount | Where-Object { -not $providedLiveObservations.ContainsKey(("M-{0:D3}" -f $_)) }).Count -ne 0) {
        throw "LIVE_INPUT_INVALID"
    }
}

function Invoke-LiveHarnessStreaming {
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string[]]$HarnessArguments,
        [Parameter(Mandatory)][string]$BootstrapJson,
        [Parameter(Mandatory)]$PrivatePayload,
        [Parameter(Mandatory)][bool]$HasPackageEvidence
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ExecutablePath
    $startInfo.WorkingDirectory = $PrivatePayload.Root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    foreach ($argument in $HarnessArguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    function Read-ProtocolLine {
        param([Parameter(Mandatory)][TimeSpan]$Timeout)
        return Read-BoundedProtocolTask -Task $process.StandardOutput.ReadLineAsync() -Timeout $Timeout
    }

    function Assert-ReadySignal {
        param(
            [Parameter(Mandatory)][string]$Line,
            [Parameter(Mandatory)][string]$ExpectedIdentity
        )
        $ready = $Line | ConvertFrom-Json
        $fields = @("schemaVersion", "signal", "identityKind", "readyAtUtc")
        if (@($ready.PSObject.Properties.Name).Count -ne 4 -or
            @($ready.PSObject.Properties.Name | Where-Object { $fields -notcontains $_ }).Count -ne 0 -or
            $ready.schemaVersion -ne 1 -or $ready.signal -ne "READY" -or $ready.identityKind -ne $ExpectedIdentity) {
            throw "LIVE_PROTOCOL_INVALID"
        }
        [DateTimeOffset]$readyAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$ready.readyAtUtc, [ref]$readyAt)) { throw "LIVE_PROTOCOL_INVALID" }
        # 이 값을 버리지 않고 함수 밖으로 돌려준다. 측정이 이 시각을 기준으로 갈린다.
        return $readyAt
    }

    try {
        Assert-PrivatePayloadManifest -PayloadRoot $PrivatePayload.Root -ExpectedManifestSha256 $PrivatePayload.ManifestSha256
        if (-not $process.Start()) { throw "LIVE_PROCESS_START_FAILED" }
        $process.StandardInput.WriteLine($BootstrapJson)
        $process.StandardInput.Flush()

        $desktopReady = Read-ProtocolLine -Timeout ([TimeSpan]::FromSeconds(60))
        # A live harness may fail before READY (for example during ABI/BFE
        # validation). Preserve its bounded result instead of treating it as
        # a protocol error and masking the real failure code.
        $earlyResult = $desktopReady | ConvertFrom-Json
        if ($earlyResult.PSObject.Properties.Name -contains "mode") {
            Assert-LimitedResult -Result $earlyResult
            if (-not $process.WaitForExit(60000)) { throw "LIVE_PROCESS_TIMEOUT" }
            $harnessError = $process.StandardError.ReadToEnd()
            if (-not [string]::IsNullOrWhiteSpace($harnessError)) { Write-Verbose ("HARNESS_DIAGNOSTIC=" + ($harnessError.Trim() -replace "\s+", " ")) }
            if ($process.ExitCode -ne 0 -and $earlyResult.verdict -eq "PASS") { throw "LIVE_PROCESS_FAILED" }
            return $earlyResult
        }
        Set-PolicyAppliedTimestamp -ReadyAtUtc (Assert-ReadySignal -Line $desktopReady -ExpectedIdentity "DESKTOP")
        Assert-PrivatePayloadManifest -PayloadRoot $PrivatePayload.Root -ExpectedManifestSha256 $PrivatePayload.ManifestSha256
        foreach ($number in 1..32) {
            $observation = Resolve-LimitedObservation -CaseId ("M-{0:D3}" -f $number)
            $process.StandardInput.WriteLine(($observation | ConvertTo-Json -Compress))
            $process.StandardInput.Flush()
        }
        $process.StandardInput.WriteLine('{"control":"COMPLETE"}')
        $process.StandardInput.Flush()

        $nextLine = Read-ProtocolLine -Timeout ([TimeSpan]::FromSeconds(60))
        $nextValue = $nextLine | ConvertFrom-Json
        $isPackageReady = $HasPackageEvidence -and $nextValue.PSObject.Properties.Name -contains "signal" -and $nextValue.signal -eq "READY"
        if ($isPackageReady) {
            Set-PolicyAppliedTimestamp -ReadyAtUtc (Assert-ReadySignal -Line $nextLine -ExpectedIdentity "PACKAGE")
            Assert-PrivatePayloadManifest -PayloadRoot $PrivatePayload.Root -ExpectedManifestSha256 $PrivatePayload.ManifestSha256
            foreach ($number in 33..64) {
                $observation = Resolve-LimitedObservation -CaseId ("M-{0:D3}" -f $number)
                $process.StandardInput.WriteLine(($observation | ConvertTo-Json -Compress))
                $process.StandardInput.Flush()
            }
            $process.StandardInput.WriteLine('{"control":"COMPLETE"}')
            $process.StandardInput.Flush()
            $finalLine = Read-ProtocolLine -Timeout ([TimeSpan]::FromSeconds(60))
        }
        else {
            $finalLine = $nextLine
        }

        $process.StandardInput.Close()
        $result = $finalLine | ConvertFrom-Json
        Assert-LimitedResult -Result $result
        if (-not $process.WaitForExit(60000)) { throw "LIVE_PROCESS_TIMEOUT" }
        $harnessError = $process.StandardError.ReadToEnd()
        if (-not [string]::IsNullOrWhiteSpace($harnessError)) { Write-Verbose ("HARNESS_DIAGNOSTIC=" + ($harnessError.Trim() -replace "\s+", " ")) }
        # The harness intentionally exits nonzero when it returns a structured
        # LIVE failure. Preserve that bounded result so the caller can see the
        # actual WFP failure code instead of masking it as ENVIRONMENT_UNAVAILABLE.
        if ($process.ExitCode -ne 0 -and $result.verdict -eq "PASS") { throw "LIVE_PROCESS_FAILED" }
        return $result
    }
    catch {
        $liveError = $_
        if (-not $process.HasExited) {
            try { $process.Kill($true); $process.WaitForExit(10000) } catch { }
        }
        try {
            $harnessError = $process.StandardError.ReadToEnd()
            if (-not [string]::IsNullOrWhiteSpace($harnessError)) { Write-Verbose ("HARNESS_DIAGNOSTIC=" + ($harnessError.Trim() -replace "\s+", " ")) }
            Write-Verbose ("HARNESS_EXITED={0} EXIT_CODE={1}" -f $process.HasExited, $(if ($process.HasExited) { $process.ExitCode } else { "RUNNING" }))
        }
        catch { }
        throw $liveError
    }
    finally {
        $process.Dispose()
    }
}

function Test-StaticImportExplorerNegativeGates {
    $testRoot = Join-Path $temporaryRoot "import-explorer-tests"
    $outsideRoot = Join-Path $temporaryRoot "import-explorer-outside"
    [void][IO.Directory]::CreateDirectory($testRoot)
    [void][IO.Directory]::CreateDirectory($outsideRoot)
    $seed = Join-Path $testRoot "Directory.Build.props"
    $nested = Join-Path $testRoot "nested.props"
    $target = Join-Path $testRoot "leaf.targets"
    $outsideFile = Join-Path $outsideRoot "outside.props"

    function Write-TestXml([string]$Path, [string]$Body) {
        [IO.File]::WriteAllText($Path, $Body, [Text.UTF8Encoding]::new($false))
    }
    function Get-TestClosureHash([string]$IndexIdentity) {
        $paths = @(Get-StaticImportClosure -Root $testRoot -SeedPaths @($seed))
        $entries = @($paths | Sort-Object | ForEach-Object {
            [ordered]@{
                relativePath = [IO.Path]::GetRelativePath($testRoot, $_).Replace('\', '/')
                length = (Get-Item -LiteralPath $_).Length
                sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
                indexBlobOid = if ($_ -eq $nested) { $IndexIdentity } else { $null }
            }
        })
        return [pscustomobject]@{
            Paths = $paths
            Hash = Get-Sha256Text -Text ([ordered]@{ schemaVersion = 1; files = $entries } | ConvertTo-Json -Depth 5 -Compress)
        }
    }
    function Assert-ExplorerRejects([string]$Name) {
        $rejected = $false
        try { [void](Get-StaticImportClosure -Root $testRoot -SeedPaths @($seed)) }
        catch { $rejected = $_.Exception.Message -in @("FEATURE_MANIFEST_SCOPE_INVALID", "PRIVATE_SPOOL_PATH_INVALID", "PRIVATE_SPOOL_REPARSE_REJECTED") }
        if (-not $rejected) { throw "STATIC_IMPORT_NEGATIVE_GATE_INVALID_$Name" }
    }

    try {
        Write-TestXml $target '<Project><PropertyGroup><SafeValue>one</SafeValue></PropertyGroup></Project>'
        Write-TestXml $nested '<Project><Import Project="leaf.targets" /></Project>'
        Write-TestXml $seed '<Project><Import Project="nested.props" /></Project>'
        $baseline = Get-TestClosureHash -IndexIdentity "1111111111111111111111111111111111111111"
        if (@($baseline.Paths).Count -ne 3 -or $baseline.Paths -notcontains $nested -or $baseline.Paths -notcontains $target) {
            throw "STATIC_IMPORT_RECURSION_GATE_INVALID"
        }
        Write-TestXml $nested '<Project><Import Project="leaf.targets" /><PropertyGroup><SafeValue>changed</SafeValue></PropertyGroup></Project>'
        $contentChanged = Get-TestClosureHash -IndexIdentity "1111111111111111111111111111111111111111"
        $identityChanged = Get-TestClosureHash -IndexIdentity "2222222222222222222222222222222222222222"
        if ($baseline.Hash -eq $contentChanged.Hash -or $contentChanged.Hash -eq $identityChanged.Hash) {
            throw "STATIC_IMPORT_MUTATION_GATE_INVALID"
        }

        Write-TestXml $seed '<Project><Import Project="$(UnsafeRoot)\nested.props" /></Project>'
        Assert-ExplorerRejects "DYNAMIC"
        Write-TestXml $seed '<Project><Import Project="*.props" /></Project>'
        Assert-ExplorerRejects "GLOB"
        Write-TestXml $seed '<Project><Import Project="missing.props" /></Project>'
        Assert-ExplorerRejects "MISSING"
        Write-TestXml $seed '<Project><Import Project="never-read.conf" /></Project>'
        Assert-ExplorerRejects "FORBIDDEN_EXTENSION"
        Write-TestXml $outsideFile '<Project />'
        Write-TestXml $seed '<Project><Import Project="..\import-explorer-outside\outside.props" /></Project>'
        Assert-ExplorerRejects "OUTSIDE"
        Write-TestXml $seed ("<Project><Import Project=`"$($outsideFile.Replace('\', '\'))`" /></Project>")
        Assert-ExplorerRejects "ROOTED"

        Write-TestXml $nested '<Project><Import Project="Directory.Build.props" /></Project>'
        Write-TestXml $seed '<Project><Import Project="nested.props" /></Project>'
        Assert-ExplorerRejects "CYCLE"

        $junctionTarget = Join-Path $outsideRoot "junction-target"
        [void][IO.Directory]::CreateDirectory($junctionTarget)
        Write-TestXml (Join-Path $junctionTarget "nested.props") '<Project />'
        $junction = Join-Path $testRoot "linked"
        [void](New-Item -ItemType Junction -Path $junction -Target $junctionTarget -Force)
        Write-TestXml $seed '<Project><Import Project="linked\nested.props" /></Project>'
        Assert-ExplorerRejects "REPARSE"
    }
    finally {
        foreach ($path in @($testRoot, $outsideRoot)) {
            if (Test-Path -LiteralPath $path) {
                [void](Assert-PathUnderRoot -Path $path -Root $temporaryRoot)
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
}

function Test-PrivateSpoolNegativeGates {
    $rejected = $false
    try { [void](Assert-PathUnderRoot -Path (Join-Path $temporaryRoot "..\escape.json") -Root $temporaryRoot) } catch { $rejected = $true }
    if (-not $rejected) { throw "PRIVATE_SPOOL_NEGATIVE_GATE_INVALID" }

    $existingPath = Join-Path $temporaryRoot "existing-file.test"
    Write-PrivateNewFile -Path $existingPath -Text "test"
    $rejected = $false
    try { Write-PrivateNewFile -Path $existingPath -Text "replacement" } catch { $rejected = $true }
    if (-not $rejected) { throw "PRIVATE_SPOOL_NEGATIVE_GATE_INVALID" }
    Remove-Item -LiteralPath $existingPath -Force

    $traversalManifestPath = Join-Path $temporaryRoot "traversal-manifest.test"
    Write-PrivateNewFile -Path $traversalManifestPath -Text '{"schemaVersion":1,"files":[{"relativePath":"../escape","sha256":"0000000000000000000000000000000000000000000000000000000000000000","length":0}]}'
    $rejected = $false
    try { [void](Read-StrictPublishManifest -Path $traversalManifestPath) } catch { $rejected = $true }
    if (-not $rejected) { throw "PRIVATE_SPOOL_NEGATIVE_GATE_INVALID" }
    Remove-Item -LiteralPath $traversalManifestPath -Force

    $contentA = [Text.Encoding]::UTF8.GetBytes("alpha")
    $contentB = [Text.Encoding]::UTF8.GetBytes("bravo")
    $entryA = [ordered]@{ relativePath = "windows/Directory.Build.props"; length = $contentA.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($contentA)).ToLowerInvariant(); indexBlobOid = "1111111111111111111111111111111111111111" }
    $entryB = [ordered]@{ relativePath = "windows/Directory.Build.props"; length = $contentB.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($contentB)).ToLowerInvariant(); indexBlobOid = $entryA.indexBlobOid }
    $entryStage = [ordered]@{ relativePath = $entryA.relativePath; length = $entryA.length; sha256 = $entryA.sha256; indexBlobOid = "2222222222222222222222222222222222222222" }
    $hashA = Get-Sha256Text -Text ([ordered]@{ schemaVersion = 1; files = @($entryA) } | ConvertTo-Json -Depth 4 -Compress)
    $hashB = Get-Sha256Text -Text ([ordered]@{ schemaVersion = 1; files = @($entryB) } | ConvertTo-Json -Depth 4 -Compress)
    $hashStage = Get-Sha256Text -Text ([ordered]@{ schemaVersion = 1; files = @($entryStage) } | ConvertTo-Json -Depth 4 -Compress)
    if ($hashA -eq $hashB -or $hashA -eq $hashStage) { throw "FEATURE_MANIFEST_NEGATIVE_GATE_INVALID" }
    Test-StaticImportExplorerNegativeGates
}

function Assert-AutomatedMarker {
    param([Parameter(Mandatory)]$Marker)

    $fields = @(
        "schemaVersion", "createdAtUtc", "commit", "nonce", "solutionBuildExitCode",
        "vsSolutionBuildExitCode", "testExitCode", "publishExitCode", "extractionExitCode",
        "dryHarnessExitCode", "beforeAfterFingerprint", "worktreeFingerprint", "artifactSha256",
        "publishManifestSha256", "harnessSha256", "scriptSha256", "fixturesManifestSha256",
        "abiEvidenceSha256", "abiProbeSourceSha256", "approvalTokenSha256"
    )
    if (@($Marker.Keys).Count -ne $fields.Count -or @($fields | Where-Object { -not $Marker.Contains($_) }).Count -ne 0 -or
        $Marker.schemaVersion -ne 1 -or $Marker.commit -notmatch '^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$' -or
        $Marker.nonce -notmatch '^[0-9a-f]{16,128}$' -or $Marker.beforeAfterFingerprint -ne "MATCH" -or
        @(@($Marker.solutionBuildExitCode, $Marker.vsSolutionBuildExitCode, $Marker.testExitCode,
            $Marker.publishExitCode, $Marker.extractionExitCode, $Marker.dryHarnessExitCode) | Where-Object { $_ -ne 0 }).Count -ne 0) {
        throw "AUTOMATED_MARKER_INVALID"
    }
    [DateTimeOffset]$created = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Marker.createdAtUtc, [ref]$created) -or
        ([DateTimeOffset]::UtcNow - $created) -gt [TimeSpan]::FromMinutes(15)) {
        throw "AUTOMATED_MARKER_INVALID"
    }
    foreach ($name in @("worktreeFingerprint", "artifactSha256", "publishManifestSha256", "harnessSha256",
        "scriptSha256", "fixturesManifestSha256", "abiEvidenceSha256", "abiProbeSourceSha256", "approvalTokenSha256")) {
        if ([string]$Marker[$name] -notmatch '^[0-9a-fA-F]{64}$') { throw "AUTOMATED_MARKER_INVALID" }
    }
}

function Test-AutomatedMarkerNegativeGates {
    param([Parameter(Mandatory)]$Marker)

    foreach ($mutation in @("expired", "hash", "exit")) {
        $copy = [ordered]@{}
        foreach ($key in $Marker.Keys) { $copy[$key] = $Marker[$key] }
        if ($mutation -eq "expired") { $copy.createdAtUtc = [DateTimeOffset]::UtcNow.AddMinutes(-16).ToString("O") }
        elseif ($mutation -eq "hash") { $copy.harnessSha256 = "not-a-hash" }
        else { $copy.publishExitCode = 1 }
        $rejected = $false
        try { Assert-AutomatedMarker -Marker $copy } catch { $rejected = $true }
        if (-not $rejected) { throw "AUTOMATED_MARKER_NEGATIVE_GATE_INVALID" }
    }
}

do {
try {
    $currentGate = "PRIVATE_SPOOL"
    New-PrivateSpool
    Test-PrivateSpoolNegativeGates

    # 실행 폴더는 실행 "전에" 자리를 정한다. 몇 시간짜리 실기의 증거가
    # 어디에 쌓일지 나중에 정하면 그 사이에 나온 증거가 사라진다 (AC-12-1).
    $currentGate = "RUN_DIRECTORY"
    New-RunDirectory
    # 인자 "이름"만 적는다. 값은 적지 않는다 — 실행 파일 경로·패키지 이름이 들어가면
    # 금지 낱말 검사에 걸릴 자료가 된다. 이름만 적어도 승인 문구를 도구가 자동으로
    # 채웠는지 확인할 수 있다 (§7.1 · AC-14-4 · GR-17).
    Write-RunDirectoryText -FileName "invocation.json" -Text (
        [ordered]@{
            schemaVersion  = 1
            startedAtUtc   = $runStartedAtUtc.ToString("O")
            parameterNames = @($PSBoundParameters.Keys | Sort-Object)
        } | ConvertTo-Json -Depth 4)

    $automatedMutex = [Threading.Mutex]::new($false, "Local\VpnRouter.WfpSpike.AutomatedGate.v2")
    $automatedMutexAcquired = $automatedMutex.WaitOne(0)
    if (-not $automatedMutexAcquired) {
        $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "FAIL" -Fingerprint "MATCH" -FailureCode "AUTOMATED_GATE_FAILED"
        $scriptExitCode = 1
        break
    }

    $currentGate = "FIXTURES"
    Test-Fixtures
    $currentGate = "WORKTREE_BEFORE"
    $featureManifestBefore = Get-FeatureManifest

    # HEAD 와 견준다. `git diff` 만 쓰면 작업 폴더와 색인을 견주므로
    # `git add` 로 색인에 올린 변경이 이 관문을 그냥 지나간다 (AC-01-4).
    # `HEAD --` 를 붙이면 올린 것과 안 올린 것을 함께 본다.
    $protectedDiff = @(git diff --name-only HEAD -- macos docs/v0.1.0-release-plan.md artifacts)
    if ($LASTEXITCODE -ne 0 -or $protectedDiff.Count -ne 0) {
        $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "FAIL" -Fingerprint "MATCH" -FailureCode "AUTOMATED_GATE_FAILED"
        $scriptExitCode = 1
        break
    }

    $currentGate = "NETWORK_BEFORE"
    $beforeFingerprint = Get-NetworkFingerprint
    $currentGate = "AUTOMATED_COMMANDS"
    $solutionBuildExitCode = Invoke-LoggedCommand -Name "solution-build" -Command {
        dotnet build .\windows\VpnRouter.slnx -nr:false
    }
    $vsSolutionBuildExitCode = Invoke-LoggedCommand -Name "vs-solution-build" -Command {
        dotnet build .\windows\VpnRouterVs.sln -nr:false
    }
    $testExitCode = Invoke-LoggedCommand -Name "focused-tests" -Command {
        dotnet run --project .\windows\VpnRouter.Tests\VpnRouter.Tests.csproj --no-build
    }

    $publishExitCode = 1
    $extractionExitCode = 1
    $extractionEvidence = $null
    $extractionFailureCode = "NONE"
    if (Test-Path -LiteralPath $buildScript) {
        $publishExitCode = Invoke-LoggedCommand -Name "spike-publish" -Command {
            & $buildScript -IncludeWfpSpike
        }
    }
    if ($publishExitCode -eq 0) {
        try {
            $currentGate = "PUBLISH_EXTRACTION"
            $extractionEvidence = Test-SpikeExtraction
            $privatePayload = Copy-AndLockPrivatePayload -ExtractionEvidence $extractionEvidence
            Test-PrivatePayloadLockNegativeGates -PrivatePayload $privatePayload
            $extractionExitCode = 0
        }
        catch {
            $extractionExitCode = 1
            $knownExtractionCodes = @("PUBLISH_CONTENT_MISSING", "PUBLISH_CONTENT_MISMATCH", "PUBLISH_MANIFEST_INVALID", "MANIFEST_PATH_INVALID", "NATIVE_EXPORT_MISSING", "FEATURE_MANIFEST_MISMATCH")
            $extractionFailureCode = if ($knownExtractionCodes -contains $_.Exception.Message) { $_.Exception.Message } else { "ENVIRONMENT_UNAVAILABLE" }
        }
    }

    $currentGate = "DRY_HARNESS"
    $dryHarnessExitCode = 1
    if (Test-Path -LiteralPath $harnessProject) {
        $dryHarnessInvocation = Invoke-Harness -HarnessArguments @() -StandardInputJson $null
        $dryHarnessExitCode = $dryHarnessInvocation.ExitCode
        if ($dryHarnessExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($dryHarnessInvocation.Output)) {
            try {
                $dryHarnessResult = $dryHarnessInvocation.Output | ConvertFrom-Json
                Assert-LimitedResult -Result $dryHarnessResult
                if ($dryHarnessResult.mode -ne "DRY_RUN" -or $dryHarnessResult.verdict -ne "PARTIAL") {
                    $dryHarnessExitCode = 1
                }
            }
            catch {
                $dryHarnessExitCode = 1
            }
        }
        else {
            $dryHarnessExitCode = 1
        }
    }

    $currentGate = "NETWORK_AFTER"
    $afterFingerprint = Get-NetworkFingerprint
    $fingerprintState = if ($beforeFingerprint -ceq $afterFingerprint) { "MATCH" } else { "MISMATCH" }
    $currentGate = "WORKTREE_AFTER"
    $featureManifestAfter = Get-FeatureManifest
    $automatedGatePassed = $solutionBuildExitCode -eq 0 -and
        $vsSolutionBuildExitCode -eq 0 -and
        $testExitCode -eq 0 -and
        $publishExitCode -eq 0 -and
        $extractionExitCode -eq 0 -and
        $dryHarnessExitCode -eq 0 -and
        $fingerprintState -eq "MATCH" -and
        $featureManifestBefore.Hash -ceq $featureManifestAfter.Hash

    if (-not $automatedGatePassed) {
        Write-Verbose ("AUTOMATED_STATUS solution={0} vs={1} tests={2} publish={3} extract={4} dry={5} network={6} worktree={7}" -f
            $solutionBuildExitCode, $vsSolutionBuildExitCode, $testExitCode, $publishExitCode, $extractionExitCode,
            $dryHarnessExitCode, $fingerprintState, ($featureManifestBefore.Hash -ceq $featureManifestAfter.Hash))
        Write-Verbose "EXTRACTION_STATUS=$extractionFailureCode"
        $failureCode = if ($publishExitCode -ne 0) { "PUBLISH_CONTENT_MISSING" } else { "AUTOMATED_GATE_FAILED" }
        $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode $failureCode
        $scriptExitCode = 1
        break
    }

    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-fA-F]{40}$|^[0-9a-fA-F]{64}$') {
        $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode "AUTOMATED_GATE_FAILED"
        $scriptExitCode = 1
        break
    }

    $approvalToken = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $currentGate = "MARKER"
    $marker = [ordered]@{
        schemaVersion = 1
        createdAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        commit = $commit
        nonce = $runNonce
        solutionBuildExitCode = $solutionBuildExitCode
        vsSolutionBuildExitCode = $vsSolutionBuildExitCode
        testExitCode = $testExitCode
        publishExitCode = $publishExitCode
        extractionExitCode = $extractionExitCode
        dryHarnessExitCode = $dryHarnessExitCode
        beforeAfterFingerprint = $fingerprintState
        worktreeFingerprint = $extractionEvidence.WorktreeFingerprint
        artifactSha256 = $extractionEvidence.ArtifactSha256
        publishManifestSha256 = $extractionEvidence.PublishManifestSha256
        harnessSha256 = $extractionEvidence.HarnessSha256
        scriptSha256 = $extractionEvidence.ScriptSha256
        fixturesManifestSha256 = $extractionEvidence.FixturesManifestSha256
        abiEvidenceSha256 = $extractionEvidence.AbiEvidenceSha256
        abiProbeSourceSha256 = $extractionEvidence.AbiProbeSourceSha256
        approvalTokenSha256 = Get-Sha256Text -Text $approvalToken
    }
    Assert-AutomatedMarker -Marker $marker
    Test-AutomatedMarkerNegativeGates -Marker $marker
    Write-PrivateNewFile -Path $markerPath -Text ($marker | ConvertTo-Json -Depth 4 -Compress)

    if (-not $ApplyLiveWfp) {
        $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "PARTIAL" -Fingerprint $fingerprintState
        break
    }

    if (-not (Test-IsElevatedAdministrator)) {
        $finalResult = New-LimitedResult -Mode "LIVE" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode "ADMIN_REQUIRED"
        $scriptExitCode = 1
        break
    }

    $ownerConfirmation = if ($PSBoundParameters.ContainsKey("LiveOwnerConfirmation")) {
        $LiveOwnerConfirmation
    } else {
        Read-BoundedValue -Prompt "실제 동적 WFP 정책 적용을 승인하려면 APPLY LIVE WFP를 입력하세요"
    }
    if ($ownerConfirmation -cne "APPLY LIVE WFP") {
        $finalResult = New-LimitedResult -Mode "LIVE" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode "OWNER_ABORTED"
        $scriptExitCode = 1
        break
    }

    $interfaceIndexText = if ($PSBoundParameters.ContainsKey("LiveInterfaceIndex")) {
        [string]$LiveInterfaceIndex
    } else {
        Read-BoundedValue -Prompt "WireGuard 인터페이스 index"
    }
    [uint32]$interfaceIndex = 0
    if (-not [uint32]::TryParse($interfaceIndexText, [ref]$interfaceIndex) -or $interfaceIndex -eq 0) {
        $finalResult = New-LimitedResult -Mode "LIVE" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode "INTERFACE_NOT_FOUND"
        $scriptExitCode = 1
        break
    }
    $executablePath = if ($PSBoundParameters.ContainsKey("LiveExecutablePath")) {
        $LiveExecutablePath
    } else {
        Read-BoundedValue -Prompt "시험 실행 파일의 전체 경로"
    }
    if ($executablePath.Length -ge 32767) {
        $finalResult = New-LimitedResult -Mode "LIVE" -Verdict "FAIL" -Fingerprint $fingerprintState -FailureCode "APP_PATH_INVALID"
        $scriptExitCode = 1
        break
    }
    $packageFamilyName = if ($PSBoundParameters.ContainsKey("LivePackageFamilyName")) {
        $LivePackageFamilyName
    } else {
        Read-BoundedValue -Prompt "선택적 패키지 이름(없으면 Enter)" -AllowEmpty
    }
    $packageAppContainerName = $null
    $packageSidBase64 = $null
    if (-not [string]::IsNullOrWhiteSpace($packageFamilyName)) {
        $packageAppContainerName = Read-BoundedValue -Prompt "검증된 패키지 AppContainer 이름"
        $packageSidBase64 = Read-BoundedValue -Prompt "검증된 패키지 SID(base64)"
        try { [void][Convert]::FromBase64String($packageSidBase64) } catch { throw "LIVE_INPUT_INVALID" }
    }

    $bootstrap = [ordered]@{
        nonce = $runNonce
        interfaceIndex = $interfaceIndex
        executablePath = $executablePath
        packageFamilyName = if ([string]::IsNullOrWhiteSpace($packageFamilyName)) { $null } else { $packageFamilyName }
        packageAppContainerName = $packageAppContainerName
        packageSidBase64 = $packageSidBase64
        approvalToken = $approvalToken
    } | ConvertTo-Json -Depth 3 -Compress

    # 하네스가 받을 사례 수는 상수가 아니다. 패키지 입력이 없으면 32건, 있으면 64건이다.
    $expectedObservationCount = if ([string]::IsNullOrWhiteSpace($packageFamilyName)) { 32 } else { 64 }
    if ($PSBoundParameters.ContainsKey("LiveObservationJson")) {
        Initialize-ProvidedLiveObservations -Json $LiveObservationJson -ExpectedCount $expectedObservationCount
    }

    # --- 측정 준비 (설계 §7.3) --------------------------------------------
    # 실제 값(기준 인터페이스 번호·대상 주소·앱 경로)은 저장소 밖 설정 파일에서 읽는다.
    # 그 값은 관찰 도구의 인자와 실행 폴더에만 쓰이고 결과 JSON 에는 한 글자도 안 들어간다.
    $currentGate = "MEASUREMENT_SETTINGS"
    $measurementInterfaceIndex = $interfaceIndex
    $caseMatrix = Get-Content -LiteralPath (Join-Path $fixtureRoot "case-matrix.json") -Raw | ConvertFrom-Json
    $caseMatrixRows = @($caseMatrix.rowsInOrder)
    $caseMatrixTransports = @($caseMatrix.transportsInOrder)
    if ($PSBoundParameters.ContainsKey("MeasurementSettingsPath")) {
        if (-not (Test-Path -LiteralPath $MeasurementSettingsPath -PathType Leaf)) { throw "MEASUREMENT_SETTINGS_INVALID" }
        $measurementSettings = Get-Content -LiteralPath $MeasurementSettingsPath -Raw | ConvertFrom-Json
        foreach ($settingName in @("baselineInterfaceIndex", "selectedAppPath", "unselectedAppPath", "ipv6Verdict", "observationAPath")) {
            if ($measurementSettings.PSObject.Properties.Name -notcontains $settingName) { throw "MEASUREMENT_SETTINGS_INVALID" }
        }
        # 두 값은 설계가 정한 목록 밖으로 나갈 수 없다. 넓히면 판정이 흐려진다.
        if ([string]$measurementSettings.ipv6Verdict -notin @("MEASURE", "INCONCLUSIVE") -or
            [string]$measurementSettings.observationAPath -notin @("VPN", "BASELINE", "OTHER", "UNOBSERVED")) {
            throw "MEASUREMENT_SETTINGS_INVALID"
        }
    }

    $currentGate = "LIVE_HARNESS"
    $liveResult = Invoke-LiveHarnessStreaming `
        -ExecutablePath $privatePayload.HarnessExecutable `
        -HarnessArguments @(
        "--apply-live-wfp",
        "--automated-marker", $markerPath,
        "--expected-commit", $commit
    ) `
        -BootstrapJson $bootstrap `
        -PrivatePayload $privatePayload `
        -HasPackageEvidence (-not [string]::IsNullOrWhiteSpace($packageFamilyName))
    $liveResult | Add-Member -NotePropertyName beforeAfterFingerprint -NotePropertyValue $fingerprintState
    $finalResult = $liveResult

    # LIVE 가 끝난 직후의 지문 F2 (설계 §7.4 / FR-13 / AC-13-1).
    # 결과의 beforeAfterFingerprint 칸은 게이트 값(F1)이고 여기서 덮지 않는다.
    # 사후 비교 값으로 덮으면 두 뜻이 한 칸에 섞인다 (AC-13-3). F2 는 결과 밖에만 남는다.
    try {
        $fingerprintF2 = Get-NetworkFingerprint
        Write-RunDirectoryText -FileName "fingerprint-f2.json" -Text (
            [ordered]@{
                measuredAtUtc        = [DateTimeOffset]::UtcNow.ToString("O")
                gateFingerprintAfter = $afterFingerprint
                fingerprintF2        = $fingerprintF2
                liveChangedNetwork   = ($afterFingerprint -cne $fingerprintF2)
            } | ConvertTo-Json -Depth 4)
    }
    catch { }
}
catch {
    # -Verbose 로 돌리면 이 줄이 화면에 나온다. 예외 원문에는 전체 경로가 섞일 수 있으므로
    # 결과 JSON 과 같은 검사를 지나게 한다. 걸리면 낱말 대신 가림표를 낸다 (AC-09-3).
    $failureDiagnostic = ($_.Exception.Message -replace "\s+", " ")
    if (Test-ProhibitedContent -Text $failureDiagnostic) { $failureDiagnostic = "REDACTED" }
    Write-Verbose ("FAILED_GATE={0} ERROR={1}" -f $currentGate, $failureDiagnostic)
    $mode = if ($ApplyLiveWfp) { "LIVE" } else { "DRY_RUN" }
    $finalResult = New-LimitedResult -Mode $mode -Verdict "FAIL" -Fingerprint "MISMATCH" -FailureCode "ENVIRONMENT_UNAVAILABLE"
    $scriptExitCode = 1
}
finally {
    foreach ($handle in $payloadReadHandles) {
        try { $handle.Dispose() } catch { }
    }
    $payloadReadHandles.Clear()
    Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    if ($automatedMutexAcquired -and $null -ne $automatedMutex) {
        [void]$automatedMutex.ReleaseMutex()
    }
    if ($null -ne $automatedMutex) {
        $automatedMutex.Dispose()
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        [void](Assert-PathUnderRoot -Path $temporaryRoot -Root $privateSpoolBase)
        Assert-NoReparsePath -Path $temporaryRoot
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
} while ($false)

Write-LimitedResult -Result $finalResult
if ($scriptExitCode -ne 0) {
    $host.SetShouldExit($scriptExitCode)
    return
}
