# Get-WfpThirdPartyState.ps1 — 제3자 제품 상태 수집·비교기
#
# 설계: R4 설계서 §4.0 · §4.4 · §11.2(G-07) · §12.3
# 닫는 AC: R2-AC-05-4(읽기만 관찰) · AC-03-7 · AC-10-1~AC-10-4 · AC-13-2
#
# 이 스크립트는 읽기만 한다.
#   Get-Service · Get-NetAdapter · Get-MpComputerStatus · Get-NetFirewallProfile 만 쓴다.
#   서비스나 어댑터를 켜거나 끄거나 시작 유형을 바꾸는 명령은 하나도 쓰지 않는다
#   (NFR-05 · AC-02-8 · 회귀 확인 GR-12).
#
# G-07: 재는 대상 5개는 이 파일 안 고정 목록이다. 사람 입력이 명령에 닿지 않는다.
#
# 기준선을 언제 찍나: 터널을 올리기 "전"이다 (§9 단계 0').
# 터널이 올라간 상태를 기준선으로 삼으면 "설치 전으로 돌아왔다"가
# 터널이 남은 상태를 뜻하게 된다 (BL-09 · AC-10-3 · AC-13-2).

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("Capture", "Compare")][string]$Mode,
    [Parameter(Mandatory)][string]$RunDirectory,

    # 파일 이름이 되므로 G-06 과 같은 무늬로 좁힌다.
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9\-]{1,32}$')]
    [string]$Label,

    [AllowEmptyString()][string]$BaselinePath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolName = "Get-WfpThirdPartyState"
$startedAtUtc = [DateTimeOffset]::UtcNow

function Write-ToolResult {
    param(
        [Parameter(Mandatory)][ValidateSet("OK", "UNAVAILABLE", "ERROR")][string]$Status,
        [AllowEmptyString()][string]$FailureReason = "",
        [hashtable]$Extra = @{}
    )

    $result = [ordered]@{
        schemaVersion  = 1
        tool           = $toolName
        startedAtUtc   = $startedAtUtc.ToString("O")
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        source         = "MACHINE"
        status         = $Status
        failureReason  = if ([string]::IsNullOrWhiteSpace($FailureReason)) { "NONE" } else { $FailureReason }
    }
    foreach ($key in @($Extra.Keys)) { $result[$key] = $Extra[$key] }
    # 결과 한 줄은 PowerShell 성공 스트림으로 내보낸다.
    # [Console]::Out.WriteLine 은 호출한 쪽의 파이프라인을 건너뛰어 콘솔로 바로 나간다 —
    # test-wfp-app-routing-spike.ps1 이 `& <경로>` 로 이 스크립트를 같은 프로세스에서
    # 부르므로, 그렇게 내보내면 부르는 쪽이 결과를 한 줄도 못 받는다.
    Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
}

function Assert-PathUnderRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "RUN_DIRECTORY_PATH_INVALID"
    }
    return $fullPath
}

# "제품이 없다"와 "제품을 확인할 도구가 없다"는 다른 사실이다.
#   observed = $true  -> 들여다봤다. available 이 참이면 있고 거짓이면 없다.
#   observed = $false -> 못 들여다봤다. available 은 null 이고 뜻이 없다.
# 둘을 한 칸에 섞으면 OWNER-05(제3자 전후 비교)가 헛돈다.
$script:missingTools = [Collections.Generic.List[string]]::new()
$script:unobservedRows = [Collections.Generic.List[string]]::new()

function Test-ObservationCommand {
    param([Parameter(Mandatory)][string]$Name)

    if ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)) { return $true }
    if (-not $script:missingTools.Contains($Name)) { $script:missingTools.Add($Name) }
    return $false
}

function New-ProductRow {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("SERVICE", "ADAPTER", "DEFENDER", "FIREWALL")][string]$Kind,
        [AllowEmptyString()][string]$State = "UNKNOWN",
        [AllowEmptyString()][string]$StartMode = "UNKNOWN",
        [bool]$Available = $false,
        [bool]$Observed = $true,
        [AllowEmptyString()][string]$UnobservedReason = ""
    )

    if (-not $Observed -and -not $script:unobservedRows.Contains($Name)) { $script:unobservedRows.Add($Name) }
    return [ordered]@{
        name             = $Name
        kind             = $Kind
        state            = if ([string]::IsNullOrWhiteSpace($State)) { "UNKNOWN" } else { $State }
        startMode        = if ([string]::IsNullOrWhiteSpace($StartMode)) { "UNKNOWN" } else { $StartMode }
        available        = if ($Observed) { $Available } else { $null }
        observed         = $Observed
        unobservedReason = if ($Observed) { "NONE" } elseif ([string]::IsNullOrWhiteSpace($UnobservedReason)) { "UNKNOWN" } else { $UnobservedReason }
    }
}

# 대상 하나가 없으면 그 줄만 available=false 로 두고 나머지를 계속 잰다 (§4.4).
function Get-ServiceRow {
    param([Parameter(Mandatory)][string]$ServiceName)

    if (-not (Test-ObservationCommand -Name "Get-Service")) {
        return New-ProductRow -Name $ServiceName -Kind "SERVICE" -State "TOOL_MISSING" `
            -Observed $false -UnobservedReason "TOOL_MISSING:Get-Service"
    }

    $serviceErrors = $null
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue -ErrorVariable serviceErrors
    # 이름에 맞는 서비스가 없을 때도 오류가 하나 올라온다. 그것은 "제품 없음"이지 실패가 아니다.
    $realErrors = @($serviceErrors | Where-Object {
        [string]$_.FullyQualifiedErrorId -notlike "NoServiceFoundForGivenName*"
    })
    if ($realErrors.Count -gt 0) {
        [Console]::Error.WriteLine("GET_SERVICE_DIAGNOSTIC=" + ((@($realErrors | ForEach-Object { [string]$_.Exception.Message }) -join " ") -replace "\s+", " "))
        return New-ProductRow -Name $ServiceName -Kind "SERVICE" -State "QUERY_FAILED" `
            -Observed $false -UnobservedReason "QUERY_FAILED:Get-Service"
    }
    if ($null -eq $service) {
        return New-ProductRow -Name $ServiceName -Kind "SERVICE" -State "ABSENT" -StartMode "ABSENT" -Available $false
    }

    $startMode = "UNKNOWN"
    try { $startMode = [string]$service.StartType } catch { $startMode = "UNKNOWN" }
    return New-ProductRow -Name $ServiceName -Kind "SERVICE" -State ([string]$service.Status) -StartMode $startMode -Available $true
}

function Get-AdapterRow {
    param([Parameter(Mandatory)][string]$AdapterName)

    if (-not (Test-ObservationCommand -Name "Get-NetAdapter")) {
        return New-ProductRow -Name $AdapterName -Kind "ADAPTER" -State "TOOL_MISSING" `
            -Observed $false -UnobservedReason "TOOL_MISSING:Get-NetAdapter"
    }
    try {
        $adapter = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop |
                Where-Object { [string]$_.Name -eq $AdapterName -or [string]$_.InterfaceDescription -eq $AdapterName }) |
            Select-Object -First 1
    }
    catch {
        [Console]::Error.WriteLine("GET_NETADAPTER_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
        return New-ProductRow -Name $AdapterName -Kind "ADAPTER" -State "QUERY_FAILED" `
            -Observed $false -UnobservedReason "QUERY_FAILED:Get-NetAdapter"
    }
    if ($null -eq $adapter) {
        return New-ProductRow -Name $AdapterName -Kind "ADAPTER" -State "ABSENT" -StartMode "ABSENT" -Available $false
    }

    return New-ProductRow -Name $AdapterName -Kind "ADAPTER" -State ([string]$adapter.Status) -StartMode ([string]$adapter.AdminStatus) -Available $true
}

function Get-DefenderRow {
    # Get-MpComputerStatus 는 Defender 모듈이라 없을 수 있다 (§4.0).
    # 모듈이 없는 것은 "백신이 없다"가 아니다. 그 둘을 가른다.
    if (-not (Test-ObservationCommand -Name "Get-MpComputerStatus")) {
        return New-ProductRow -Name "Windows Defender" -Kind "DEFENDER" -State "TOOL_MISSING" `
            -Observed $false -UnobservedReason "TOOL_MISSING:Get-MpComputerStatus"
    }
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $state = "RealTimeProtection={0};AntivirusEnabled={1}" -f [bool]$status.RealTimeProtectionEnabled, [bool]$status.AntivirusEnabled
        $startMode = "AMServiceEnabled={0}" -f [bool]$status.AMServiceEnabled
        return New-ProductRow -Name "Windows Defender" -Kind "DEFENDER" -State $state -StartMode $startMode -Available $true
    }
    catch {
        [Console]::Error.WriteLine("GET_MPCOMPUTERSTATUS_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
        return New-ProductRow -Name "Windows Defender" -Kind "DEFENDER" -State "QUERY_FAILED" `
            -Observed $false -UnobservedReason "QUERY_FAILED:Get-MpComputerStatus"
    }
}

function Get-FirewallRow {
    if (-not (Test-ObservationCommand -Name "Get-NetFirewallProfile")) {
        return New-ProductRow -Name "Windows Firewall" -Kind "FIREWALL" -State "TOOL_MISSING" `
            -Observed $false -UnobservedReason "TOOL_MISSING:Get-NetFirewallProfile"
    }
    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop | Sort-Object Name)
    }
    catch {
        [Console]::Error.WriteLine("GET_NETFIREWALLPROFILE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
        return New-ProductRow -Name "Windows Firewall" -Kind "FIREWALL" -State "QUERY_FAILED" `
            -Observed $false -UnobservedReason "QUERY_FAILED:Get-NetFirewallProfile"
    }
    # 방화벽 프로파일이 0개로 나오는 것은 정상 상태가 아니다. 못 본 것으로 다룬다.
    if ($profiles.Count -eq 0) {
        return New-ProductRow -Name "Windows Firewall" -Kind "FIREWALL" -State "QUERY_FAILED" `
            -Observed $false -UnobservedReason "QUERY_FAILED:NoFirewallProfile"
    }
    $state = ($profiles | ForEach-Object { "{0}={1}" -f [string]$_.Name, [bool]$_.Enabled }) -join ";"
    $startMode = ($profiles | ForEach-Object { "{0}:{1}" -f [string]$_.Name, [string]$_.DefaultOutboundAction }) -join ";"
    return New-ProductRow -Name "Windows Firewall" -Kind "FIREWALL" -State $state -StartMode $startMode -Available $true
}

try {
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        Write-ToolResult -Status "ERROR" -FailureReason "RUN_DIRECTORY_MISSING" -Extra @{ label = $Label }
        return
    }

    # =======================================================================
    # Capture — 지금 상태를 잰다
    # =======================================================================
    if ($Mode -eq "Capture") {
        # 재는 대상 5개 — 고정 목록 (§4.4 · G-07)
        $products = @(
            (Get-ServiceRow -ServiceName "Adguard Service"),
            (Get-AdapterRow -AdapterName "VPN Unlimited TAP"),
            (Get-DefenderRow),
            (Get-FirewallRow),
            (Get-ServiceRow -ServiceName "WarpJITSvc")
        )

        # 우리가 띄운 시험용 터널은 제3자 제품이 아니다. 다른 칸으로 뺀다 (AC-10-2 · BL-13).
        if (Test-ObservationCommand -Name "Get-Service") {
            $tunnelServices = @(Get-Service -Name "WireGuardTunnel*" -ErrorAction SilentlyContinue)
            $testInstrument = [ordered]@{
                name          = "WireGuardTunnel*"
                kind          = "SERVICE"
                observed      = $true
                instanceCount = $tunnelServices.Count
                states        = @($tunnelServices | ForEach-Object { [string]$_.Status })
            }
        }
        else {
            $testInstrument = [ordered]@{
                name          = "WireGuardTunnel*"
                kind          = "SERVICE"
                observed      = $false
                instanceCount = $null
                states        = @()
            }
        }

        $capture = [ordered]@{
            label          = $Label
            products       = @($products)
            testInstrument = $testInstrument
            observedCount  = @($products | Where-Object { $_.observed }).Count
            unobserved     = @($script:unobservedRows)
        }

        # 비교기가 나중에 가리킬 수 있게 실행 폴더에도 남긴다.
        $capturePath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory ("thirdparty-" + $Label + ".json")) -Root $RunDirectory
        Set-Content -LiteralPath $capturePath -Value ($capture | ConvertTo-Json -Depth 6) -Encoding utf8NoBOM

        # 한 줄이라도 못 들여다봤으면 "다 봤다"고 말하지 않는다.
        # 도구가 없어서 못 본 것과 제품이 없어서 못 찾은 것을 가려 적는다.
        if ($script:unobservedRows.Count -eq 0) {
            Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $capture
        }
        elseif ($script:missingTools.Count -gt 0) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("TOOL_MISSING:" + ($script:missingTools -join ",")) -Extra $capture
        }
        else {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("PRODUCT_QUERY_FAILED:" + ($script:unobservedRows -join ",")) -Extra $capture
        }
        return
    }

    # =======================================================================
    # Compare — 기준선과 견준다
    # =======================================================================
    $comparison = [ordered]@{
        baselineLabel       = "UNKNOWN"
        currentLabel        = $Label
        comparisonPerformed = $false
        changed             = @()
        unchangedCount      = 0
    }

    # 기준선이 없으면 비교하지 않는다. 없는 기준선을 지어내거나
    # "안 바뀌었다"로 적지 않는다 (AC-10-3 두 번째 축).
    if ([string]::IsNullOrWhiteSpace($BaselinePath) -or -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
        Write-ToolResult -Status "OK" -FailureReason "BASELINE_MISSING" -Extra $comparison
        return
    }

    # 이 스크립트는 관리자 권한으로 돈다. 읽는 자리도 -RunDirectory 안으로 가둔다.
    # 이 파일의 다른 경로 세 곳은 이미 같은 검사를 지난다 — 여기만 빠져 있었다.
    try { [void](Assert-PathUnderRoot -Path $BaselinePath -Root $RunDirectory) }
    catch {
        Write-ToolResult -Status "ERROR" -FailureReason "BASELINE_PATH_INVALID" -Extra $comparison
        return
    }

    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    $comparison.baselineLabel = if ([string]::IsNullOrWhiteSpace([string]$baseline.label)) { "UNKNOWN" } else { [string]$baseline.label }

    $current = @(
        (Get-ServiceRow -ServiceName "Adguard Service"),
        (Get-AdapterRow -AdapterName "VPN Unlimited TAP"),
        (Get-DefenderRow),
        (Get-FirewallRow),
        (Get-ServiceRow -ServiceName "WarpJITSvc")
    )

    $baselineByName = @{}
    foreach ($row in @($baseline.products)) { $baselineByName[[string]$row.name] = $row }

    $changed = [Collections.Generic.List[object]]::new()
    $unknown = [Collections.Generic.List[object]]::new()
    $unchanged = 0
    foreach ($row in $current) {
        $name = [string]$row.name
        if (-not $baselineByName.ContainsKey($name)) {
            $changed.Add([ordered]@{
                name          = $name
                field         = "presence"
                baselineValue = "ABSENT_FROM_BASELINE"
                currentValue  = "PRESENT"
            })
            continue
        }

        $before = $baselineByName[$name]
        # 어느 한쪽이라도 못 들여다본 줄은 "안 바뀌었다"로 세지 않는다.
        # 모르는 것을 안 바뀐 것으로 세면 OWNER-05 전후 비교가 헛돈다.
        $beforeObserved = ($null -eq $before.observed) -or ([bool]$before.observed)
        if (-not $beforeObserved -or -not [bool]$row.observed) {
            $unknown.Add([ordered]@{
                name             = $name
                baselineObserved = $beforeObserved
                currentObserved  = [bool]$row.observed
                reason           = [string]$row.unobservedReason
            })
            continue
        }

        $rowChanged = $false
        foreach ($field in @("state", "startMode", "available")) {
            $beforeValue = [string]$before.$field
            $currentValue = [string]$row[$field]
            if ($beforeValue -cne $currentValue) {
                $changed.Add([ordered]@{
                    name          = $name
                    field         = $field
                    baselineValue = $beforeValue
                    currentValue  = $currentValue
                })
                $rowChanged = $true
            }
        }
        if (-not $rowChanged) { $unchanged++ }
    }

    $comparison.comparisonPerformed = $true
    $comparison.changed = @($changed)
    $comparison.unchangedCount = $unchanged
    $comparison.unknown = @($unknown)

    if ($unknown.Count -eq 0) {
        Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $comparison
    }
    elseif ($script:missingTools.Count -gt 0) {
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("TOOL_MISSING:" + ($script:missingTools -join ",")) -Extra $comparison
    }
    else {
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("PRODUCT_QUERY_FAILED:" + ($script:unobservedRows -join ",")) -Extra $comparison
    }
}
catch {
    [Console]::Error.WriteLine("GET_WFP_THIRD_PARTY_STATE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
    Write-ToolResult -Status "ERROR" -FailureReason "UNHANDLED_ERROR" -Extra @{ label = $Label }
}
finally {
    # 축 1(되돌리기) 자기 점검: 이 스크립트는 PC 상태를 바꾸는 명령을 하나도 쓰지 않는다.
    # 읽기만 하므로 되돌릴 것이 없다. 다섯 스크립트의 모양을 맞추려고 이 자리를 비워 둔다.
}
