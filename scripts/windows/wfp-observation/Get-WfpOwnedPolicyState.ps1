# Get-WfpOwnedPolicyState.ps1 — 소유 정책 열거기
#
# 설계: R4 설계서 §4.0 · §4.3 · §5 · §11.2(G-06) · §12.3
# 닫는 AC: R2-AC-03-8(강제 종료 뒤 소유 정책 0건) · R2-AC-05-5(자기 세션만 닫음)
#          · AC-03-5 · AC-03-6 · AC-08-1~AC-08-6
#
# 이 스크립트는 읽기만 한다. 정책을 지우지 않는다.
#   - 지우는 일은 restore-network-dev.ps1 의 몫이다 (§8).
#   - 0건을 확인하려고 삭제를 시도하는 방법은 설계 §5 에서 버렸다.
#
# 세 신호 (서로 독립이라 하나가 안 되면 나머지가 답한다 — §4.3)
#   S-1 소유 정책 GUID 4개가 providerContexts 에 있는가
#   S-2 우리 동적 세션("VPN Router WFP Spike")이 sessions 에 있는가
#   S-3 고아 하네스 프로세스가 살아 있는가
#
# netsh wfp 를 부르는 자리는 이 파일 안 함수 하나뿐이다 (§4.3 · GR-13).

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,

    # G-06: -Label 이 파일 이름이 되므로 정규식으로 좁힌다.
    # 경로 구분 기호·따옴표·공백을 아예 못 넣는다.
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9\-]{1,32}$')]
    [string]$Label,

    # 상태 파일은 3MB 가 넘고 이 PC 의 네트워크 상태가 통째로 들어 있다.
    # 주지 않으면 신호를 뽑은 뒤 지운다 (§4.3).
    [switch]$KeepDump
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolName = "Get-WfpOwnedPolicyState"
$startedAtUtc = [DateTimeOffset]::UtcNow

# WfpOwnedPolicyKeys.cs:7-10 의 GUID 4개. 콜론이 없으므로 금지 낱말 무늬에 걸리지 않는다.
$ownedPolicyKeys = @(
    "32458d2e-74f4-4bc1-9f0d-7809c7c70601",
    "32458d2e-74f4-4bc1-9f0d-7809c7c70602",
    "32458d2e-74f4-4bc1-9f0d-7809c7c70603",
    "32458d2e-74f4-4bc1-9f0d-7809c7c70604"
)

# NativeSessionBuffer.cs:33 이 붙이는 이름과 :36 의 동적 표시.
$ownerSessionName = "VPN Router WFP Spike"
$dynamicSessionFlag = "FWPM_SESSION_FLAG_DYNAMIC"
$harnessProcessName = "VpnRouter.WfpSpike.Harness"

# §12.3: netsh 상태 뜨기 상한 64MB. 이 단계 실측은 3.15MB 였다.
$maximumStateBytes = 64MB

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

# netsh wfp 를 부르는 유일한 자리 (§4.3 민감한 바깥 명령 모으기 · GR-13).
# 읽기만 한다 — show state 말고 다른 하위 명령을 부르지 않는다.
function Export-WfpStateFile {
    param([Parameter(Mandatory)][string]$DestinationPath)

    $output = & $script:netshPath "wfp" "show" "state" ("file=" + $DestinationPath) 2>&1
    return [pscustomobject]@{
        ExitCode = [int]$LASTEXITCODE
        Output   = @($output | ForEach-Object { [string]$_ })
    }
}

$state = [ordered]@{
    label                  = $Label
    ownedPolicyCount       = 0
    ownedPolicyKeys        = @()
    ownerSessionCount      = 0
    ownerSessionProcessIds = @()
    harnessProcessCount    = 0
    signals                = [ordered]@{
        ownedPolicyEnumeration = "UNKNOWN"
        ownerSession           = "UNKNOWN"
        harnessProcess         = "UNKNOWN"
        agreement              = "UNKNOWN"
    }
}

$stateFilePath = $null

try {
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        Write-ToolResult -Status "ERROR" -FailureReason "RUN_DIRECTORY_MISSING" -Extra $state
        return
    }

    # --- 바깥 도구 존재 확인 (§4.0 · T-11) ---------------------------------
    # 표준 자리를 "먼저" 본다. PATH 를 먼저 타면 PATH 에 든 아무 폴더에나
    # netsh.exe 라는 이름을 놓아 두는 것으로 이 관리자 권한 실행을 가로챌 수 있다.
    # PATH 를 보는 것은 표준 자리에 없을 때뿐이다 (T-11: 다른 도구로 대신하지는 않는다).
    $netshSystemPath = Join-Path ${env:SystemRoot} "System32\netsh.exe"
    if (Test-Path -LiteralPath $netshSystemPath -PathType Leaf) {
        $script:netshPath = $netshSystemPath
    }
    else {
        $netshCommand = Get-Command -Name "netsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $netshCommand) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "TOOL_MISSING:netsh" -Extra $state
            return
        }
        $script:netshPath = $netshCommand.Source
    }

    # --- S-3 고아 하네스 프로세스 (netsh 와 무관하게 먼저 잰다) -------------
    # 재 보지 않은 값을 좋은 신호로 적지 않는다. 확인하지 못했으면 UNOBSERVED 이고,
    # 개수는 0 이 아니라 null 이다 — "0건 확인"과 "못 셈"은 다른 사실이다.
    if ($null -eq (Get-Command -Name "Get-Process" -ErrorAction SilentlyContinue)) {
        $state.harnessProcessCount = $null
        $state.signals.harnessProcess = "UNOBSERVED:TOOL_MISSING:Get-Process"
    }
    else {
        $processErrors = $null
        $harnessProcesses = @(Get-Process -Name $harnessProcessName -ErrorAction SilentlyContinue -ErrorVariable processErrors)
        # 이름에 맞는 프로세스가 없을 때도 오류가 하나 올라온다. 그것은 "0건"이지 실패가 아니다.
        # 그 밖의 오류(접근 거부 등)는 "못 셈"이다.
        $realErrors = @($processErrors | Where-Object {
            [string]$_.FullyQualifiedErrorId -notlike "NoProcessFoundForGivenName*"
        })
        if ($realErrors.Count -gt 0) {
            [Console]::Error.WriteLine("GET_PROCESS_DIAGNOSTIC=" + ((@($realErrors | ForEach-Object { [string]$_.Exception.Message }) -join " ") -replace "\s+", " "))
            $state.harnessProcessCount = $null
            $state.signals.harnessProcess = "UNOBSERVED:QUERY_FAILED"
        }
        else {
            $state.harnessProcessCount = $harnessProcesses.Count
            $state.signals.harnessProcess = "OK"
        }
    }

    # --- 상태 뜨기 (한 번만) ------------------------------------------------
    $stateFilePath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory ("wfpstate-" + $Label + ".xml")) -Root $RunDirectory
    Remove-Item -LiteralPath $stateFilePath -Force -ErrorAction SilentlyContinue

    $exportResult = Export-WfpStateFile -DestinationPath $stateFilePath
    if ($exportResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $stateFilePath -PathType Leaf)) {
        # 0건이라고 적지 않는다. 못 쟀다고 적는다 (§4.3).
        [Console]::Error.WriteLine("NETSH_DIAGNOSTIC=" + (($exportResult.Output -join " ") -replace "\s+", " "))
        $state.signals.ownedPolicyEnumeration = "FAILED"
        $state.signals.ownerSession = "FAILED"
        $state.signals.agreement = "UNKNOWN"
        Write-ToolResult -Status "ERROR" -FailureReason "NETSH_FAILED" -Extra $state
        return
    }

    $stateFileLength = (Get-Item -LiteralPath $stateFilePath).Length
    if ($stateFileLength -gt $maximumStateBytes) {
        $state.signals.ownedPolicyEnumeration = "FAILED"
        $state.signals.ownerSession = "FAILED"
        Write-ToolResult -Status "ERROR" -FailureReason "WFPSTATE_TOO_LARGE" -Extra $state
        return
    }

    # netsh 는 최상위 요소를 하나가 아니라 둘 낸다 — <wfpstate> 와 <firewallState>
    # (이 PC 실측: 89,025행에서 두 번째가 시작된다). 그대로 읽으면 "루트가 여럿"이라
    # 파싱이 실패하고, 그러면 S-1·S-2 두 신호가 통째로 서지 않는다.
    # 우리가 감싸는 요소를 하나 씌워 읽는다. 안의 내용은 한 글자도 바꾸지 않는다.
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try {
        $stateText = [IO.File]::ReadAllText($stateFilePath)
        $stateText = [regex]::Replace($stateText, '^\s*<\?xml[^>]*\?>', '', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $document.LoadXml("<wfpStateRoot>" + $stateText + "</wfpStateRoot>")
    }
    catch {
        [Console]::Error.WriteLine("WFPSTATE_PARSE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
        $state.signals.ownedPolicyEnumeration = "FAILED"
        $state.signals.ownerSession = "FAILED"
        Write-ToolResult -Status "ERROR" -FailureReason "WFPSTATE_PARSE_FAILED" -Extra $state
        return
    }

    # --- S-1 소유 정책 GUID 4개 --------------------------------------------
    $foundKeys = [Collections.Generic.List[string]]::new()
    foreach ($node in @($document.SelectNodes("//providerContexts/item/providerContextKey"))) {
        $keyText = ([string]$node.InnerText).Trim().Trim('{', '}').ToLowerInvariant()
        if ($ownedPolicyKeys -contains $keyText -and -not $foundKeys.Contains($keyText)) {
            $foundKeys.Add($keyText)
        }
    }
    $state.ownedPolicyKeys = @($foundKeys)
    $state.ownedPolicyCount = $foundKeys.Count
    $state.signals.ownedPolicyEnumeration = "OK"

    # --- S-2 우리 동적 세션 --------------------------------------------------
    $sessionProcessIds = [Collections.Generic.List[int]]::new()
    foreach ($sessionNode in @($document.SelectNodes("//sessions/item"))) {
        $nameNode = $sessionNode.SelectSingleNode("displayData/name")
        if ($null -eq $nameNode -or ([string]$nameNode.InnerText).Trim() -ne $ownerSessionName) { continue }

        $isDynamic = $false
        foreach ($flagNode in @($sessionNode.SelectNodes("flags/item"))) {
            if (([string]$flagNode.InnerText).Trim() -eq $dynamicSessionFlag) { $isDynamic = $true; break }
        }
        if (-not $isDynamic) { continue }

        $processIdNode = $sessionNode.SelectSingleNode("processId")
        $processId = 0
        if ($null -ne $processIdNode -and [int]::TryParse(([string]$processIdNode.InnerText).Trim(), [ref]$processId)) {
            $sessionProcessIds.Add($processId)
        }
        else {
            $sessionProcessIds.Add(0)
        }
    }
    $state.ownerSessionProcessIds = @($sessionProcessIds)
    $state.ownerSessionCount = $sessionProcessIds.Count
    $state.signals.ownerSession = "OK"

    # --- 세 신호를 맞춰 본다. 가장 나쁜 쪽으로 읽는다 (§4.3) -----------------
    # 못 센 신호가 하나라도 있으면 "0건"이라고 말할 수 없다. 세 신호가 다 서고
    # 셋 다 0일 때만 AGREE 다. 못 셈을 괜찮음으로 세지 않는다.
    $harnessObserved = ([string]$state.signals.harnessProcess -eq "OK")
    if (-not $harnessObserved) {
        $state.signals.agreement = "INCOMPLETE_ASSUME_POLICY_PRESENT"
    }
    else {
        # S-1 이 0인데 S-2 나 S-3 이 1 이상이면 "정책이 남아 있다"고 본다.
        $disagrees = $state.ownedPolicyCount -eq 0 -and
            ($state.ownerSessionCount -gt 0 -or [int]$state.harnessProcessCount -gt 0)
        $state.signals.agreement = if ($disagrees) { "DISAGREE_ASSUME_POLICY_PRESENT" } else { "AGREE" }
    }

    Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $state
}
catch {
    [Console]::Error.WriteLine("GET_WFP_OWNED_POLICY_STATE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
    Write-ToolResult -Status "ERROR" -FailureReason "UNHANDLED_ERROR" -Extra $state
}
finally {
    # 결과 JSON 에는 숫자와 GUID 만 남는다. 원문 상태 파일은 기본으로 지운다.
    if (-not $KeepDump -and -not [string]::IsNullOrWhiteSpace($stateFilePath)) {
        Remove-Item -LiteralPath $stateFilePath -Force -ErrorAction SilentlyContinue
    }
}
