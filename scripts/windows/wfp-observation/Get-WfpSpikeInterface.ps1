# Get-WfpSpikeInterface.ps1 — 인터페이스 관찰기
#
# 설계: R4 설계서 §4.0 · §4.2 · §11.2(G-04·G-05) · §12.3
# 닫는 AC: R2-AC-06-3 · R2-AC-06-4 · R2-AC-06-5 · AC-03-3 · AC-03-4 · AC-11-1
#
# 부르는 순서 (§4.2)
#   ① -Mode Start  : pktmon 잡기 시작
#   ② New-WfpSpikeFlow.ps1 : 흐름 한 개
#   ③ -Mode Stop   : 멈추고 판정
#
# 이 스크립트는 관찰값만 돌려준다. PASS/FAIL 같은 판정은 부르는 쪽이
# 설계 §4.2 매핑 표에 따라 붙인다 (§4.0).
#
# observedPath 는 네 값뿐이다: VPN · BASELINE · OTHER · UNOBSERVED
# UNOBSERVED 를 내는 조건은 아래 다섯 가지 말고는 없다 (AC-03-4).
#   ① 꾸러미 0개
#   ② pktmon 이 0이 아닌 종료 코드
#   ③ etl2txt 결과에서 구성 요소 번호를 못 읽음
#   ④ VPN 쪽과 기준 쪽 꾸러미 수가 같아 어느 쪽인지 못 가름
#   ⑤ 잡기 창이 -PolicyAppliedAtUtc 보다 앞섬
#
# 못 정한 것을 채우지 않는다: UNOBSERVED 일 때 observedInterfaceIndex 는 null 이고
# 기준 인터페이스로 채우거나 PASS 로 만들지 않는다 (§4.2).

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("Start", "Stop")][string]$Mode,

    [Parameter(Mandatory)][uint32]$VpnInterfaceIndex,
    [Parameter(Mandatory)][uint32]$BaselineInterfaceIndex,

    # G-04: 주소·포트는 형으로 받는다. 글자로 받지 않는다.
    [ipaddress]$TargetAddress,
    [uint16]$TargetPort,
    [Parameter(Mandatory)][ValidateSet("TCP", "UDP", "QUIC", "DNS")][string]$Transport,

    [Parameter(Mandatory)][string]$RunDirectory,

    # G-04: -CaseId 가 파일 이름이 되므로 정규식으로 좁힌다.
    # 경로 구분 기호·따옴표·공백을 아예 못 넣는다.
    [Parameter(Mandatory)]
    [ValidatePattern('^M-0(0[1-9]|[1-5][0-9]|6[0-4])$')]
    [string]$CaseId,

    [ValidateRange(1, 600)][int]$CaptureSeconds = 30,

    # UNOBSERVED 다섯 번째 갈래(잡기 창이 정책보다 앞섬)를 판정하는 데 쓴다.
    [AllowEmptyString()][string]$PolicyAppliedAtUtc,

    # TCP 대안 경로(NETTCP_FALLBACK)에서 되짚을 프로세스 번호.
    [uint32]$FlowProcessId
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolName = "Get-WfpSpikeInterface"
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

# pktmon 을 부르는 유일한 자리. 인자는 하나씩 넘기고 글자를 이어 붙이지 않는다.
function Invoke-Pktmon {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & $script:pktmonPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = @($output | ForEach-Object { [string]$_ })
    }
}

# ---------------------------------------------------------------------------
# pktmon 되돌리기 (설계 §4.0 "바꾼 것은 finally 에서 되돌리고, 되돌릴 목록을 실행 폴더에 남긴다")
#
# 왜 필요한가: `pktmon filter remove` 는 우리 거르개만 지우는 명령이 아니다.
# 이 PC 에 걸린 거르개를 전부 지운다. 그러므로 우리가 무엇이든 지우기 "전에"
# 지금 걸린 목록을 실행 폴더에 남기고, 끝날 때 그 목록을 되돌려 놓아야 한다.
# 되돌리지 못하면 삼키지 않고 표준 오류에 남긴다.
# ---------------------------------------------------------------------------
$script:filterSnapshot = $null
$script:filterSnapshotPath = $null
$script:filtersMutated = $false
$script:captureStarted = $false
$script:keepCaptureRunning = $false
# 되돌리기가 실제로 끝났는가. -Mode Stop 이 잡기 창 표식을 지워도 되는지를 가른다.
# 값으로 돌려주지 않고 표식 변수를 쓰는 이유: 되돌리기는 finally 에서 부르므로
# 돌려준 값이 표준 출력(결과 JSON 한 줄)에 섞인다.
$script:pktmonUndoSucceeded = $false

function Get-PktmonFilterSnapshot {
    $listJson = Invoke-Pktmon -Arguments @("filter", "list", "--json")
    if ($listJson.ExitCode -eq 0) {
        $text = ($listJson.Output -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return [pscustomobject]@{ Format = "JSON"; Filters = @(); Raw = "" }
        }
        try {
            return [pscustomobject]@{ Format = "JSON"; Filters = @($text | ConvertFrom-Json); Raw = $text }
        }
        catch { }
    }

    $listText = Invoke-Pktmon -Arguments @("filter", "list")
    if ($listText.ExitCode -eq 0) {
        $raw = ($listText.Output -join "`n")
        return [pscustomobject]@{
            Format  = "TEXT"
            Filters = @(ConvertFrom-PktmonFilterText -Text $raw)
            Raw     = $raw
        }
    }

    # 목록 자체를 못 얻었다. 되돌릴 수 없는 것을 되돌린 척하지 않는다.
    return [pscustomobject]@{
        Format  = "UNAVAILABLE"
        Filters = $null
        Raw     = ($listText.Output -join "`n")
    }
}

function ConvertTo-PktmonFilterArguments {
    param([Parameter(Mandatory)]$Filter)

    $names = @($Filter.PSObject.Properties.Name)
    $filterName = $null
    foreach ($key in @("name", "Name", "filterName", "FilterName")) {
        if ($names -contains $key -and -not [string]::IsNullOrWhiteSpace([string]$Filter.$key)) { $filterName = [string]$Filter.$key; break }
    }
    if ([string]::IsNullOrWhiteSpace($filterName)) { return $null }

    $arguments = [Collections.Generic.List[string]]::new()
    $arguments.Add("filter"); $arguments.Add("add"); $arguments.Add($filterName)
    foreach ($key in @("protocol", "Protocol", "transportProtocol", "TransportProtocol")) {
        if ($names -contains $key -and -not [string]::IsNullOrWhiteSpace([string]$Filter.$key)) {
            $arguments.Add("-t"); $arguments.Add([string]$Filter.$key); break
        }
    }
    foreach ($key in @("ip", "Ip", "ipAddress", "IpAddress")) {
        if ($names -contains $key -and -not [string]::IsNullOrWhiteSpace([string]$Filter.$key)) {
            $arguments.Add("-i"); $arguments.Add([string]$Filter.$key); break
        }
    }
    foreach ($key in @("port", "Port")) {
        if ($names -contains $key -and -not [string]::IsNullOrWhiteSpace([string]$Filter.$key)) {
            $arguments.Add("-p"); $arguments.Add([string]$Filter.$key); break
        }
    }
    return @($arguments)
}

function Restore-PktmonFilterState {
    if ($null -eq $script:filterSnapshot) { return $true }

    # 목록을 아예 못 읽었으면 되돌릴 수 없다. 기록을 남기고 알린다.
    if ($null -eq $script:filterSnapshot.Filters) {
        [Console]::Error.WriteLine("PKTMON_FILTERS_NOT_RESTORED=snapshot_format_" + [string]$script:filterSnapshot.Format +
            " record=" + [string]$script:filterSnapshotPath)
        return $false
    }

    # 원래 걸린 거르개가 없었으면 지운 상태가 곧 원래 상태다.
    if (@($script:filterSnapshot.Filters).Count -eq 0) { return $true }

    foreach ($savedFilter in @($script:filterSnapshot.Filters)) {
        $arguments = ConvertTo-PktmonFilterArguments -Filter $savedFilter
        if ($null -eq $arguments) {
            [Console]::Error.WriteLine("PKTMON_FILTERS_NOT_RESTORED=filter_not_rebuildable record=" + [string]$script:filterSnapshotPath)
            return $false
        }
        $addResult = Invoke-Pktmon -Arguments $arguments
        if ($addResult.ExitCode -ne 0) {
            [Console]::Error.WriteLine("PKTMON_FILTERS_NOT_RESTORED=add_failed record=" + [string]$script:filterSnapshotPath +
                " detail=" + ((($addResult.Output -join " ") -replace "\s+", " ")))
            return $false
        }
    }
    return $true
}

function Undo-PktmonState {
    # 잡기 멈춤이 깨끗했는가. 잡기를 아예 안 걸었으면 멈출 것도 없으므로 참이다.
    $stopClean = $true
    if ($script:captureStarted) {
        $stopUndo = Invoke-Pktmon -Arguments @("stop")
        if ($stopUndo.ExitCode -ne 0) {
            $stopClean = $false
            [Console]::Error.WriteLine("PKTMON_UNDO_STOP_FAILED=" + ((($stopUndo.Output -join " ") -replace "\s+", " ")))
        }
    }
    if (-not $script:filtersMutated) { return }

    $removeUndo = Invoke-Pktmon -Arguments @("filter", "remove")
    if ($removeUndo.ExitCode -ne 0) {
        [Console]::Error.WriteLine("PKTMON_UNDO_REMOVE_FAILED=" + ((($removeUndo.Output -join " ") -replace "\s+", " ")) +
            " record=" + [string]$script:filterSnapshotPath)
        return
    }

    # 되돌리기에 성공했을 때만 기록을 지운다. 실패하면 남겨 두어
    # restore-network-dev.ps1 이 그 파일을 보고 마무리한다.
    if (Restore-PktmonFilterState) {
        if (-not [string]::IsNullOrWhiteSpace($script:filterSnapshotPath)) {
            Remove-Item -LiteralPath $script:filterSnapshotPath -Force -ErrorAction SilentlyContinue
        }
        # 되돌리기가 끝났다는 표식. 성공 = 잡기 멈춤 성공 ∧ 거르개 되돌리기 성공.
        #
        # 거르개만 보고 표식을 세우면 이런 구멍이 생긴다 — pktmon stop 이 실패했는데
        # 거르개는 되돌려진 경우, 잡기 창 표식이 지워져 두 번째 Stop 이
        # CAPTURE_STATE_MISSING 로 되돌아가고 잡기가 영원히 도는 채로 남는다.
        # 고침이 새 사고를 만드는 모양이라 두 조건을 함께 본다.
        $script:pktmonUndoSucceeded = $stopClean
    }
}

# TCP 에 한해 쓰는 대안 경로 (§4.2 대안 경로 · method = NETTCP_FALLBACK).
# UDP·QUIC·DNS 에는 대안이 없다 — Get-NetUDPEndpoint 는 상대 주소를 주지 않아
# 어느 인터페이스로 나갔는지 되짚을 수 없다. 그 셋은 pktmon 이 안 되면 UNOBSERVED 다.
function Get-TcpFallbackInterfaceIndex {
    if ($Transport -ne "TCP" -or $FlowProcessId -eq 0) { return $null }
    # 축 2(도구 확인): "대안 도구가 없다"와 "대안으로 찾아봤는데 없다"는 다른 사실이다.
    # 둘 다 결과는 UNOBSERVED 지만, 왜 그렇게 됐는지는 표준 오류에 남긴다.
    foreach ($fallbackCommand in @("Get-NetTCPConnection", "Get-NetIPAddress")) {
        if ($null -eq (Get-Command -Name $fallbackCommand -ErrorAction SilentlyContinue)) {
            [Console]::Error.WriteLine("NETTCP_FALLBACK_UNAVAILABLE=TOOL_MISSING:" + $fallbackCommand)
            return $null
        }
    }

    $connections = @(Get-NetTCPConnection -OwningProcess $FlowProcessId -ErrorAction SilentlyContinue |
            Where-Object { $null -eq $TargetAddress -or [string]$_.RemoteAddress -eq $TargetAddress.IPAddressToString })
    foreach ($connection in $connections) {
        $address = @(Get-NetIPAddress -IPAddress ([string]$connection.LocalAddress) -ErrorAction SilentlyContinue) |
            Select-Object -First 1
        if ($null -ne $address) { return [int]$address.InterfaceIndex }
    }
    return $null
}

$observation = [ordered]@{
    caseId                = $CaseId
    observedPath          = "UNOBSERVED"
    observedInterfaceIndex = $null
    packetCount           = 0
    captureStartedAtUtc   = $null
    captureStoppedAtUtc   = $null
    method                = "PKTMON"
}

try {
    # --- 순수 해석 함수 들여오기 -------------------------------------------
    # 글자를 값으로 바꾸는 다섯 함수는 WfpObservationText.psm1 에 있다. 관찰 스크립트
    # 안에 두면 시험이 부를 수 없기 때문이다(스크립트를 점 소스하면 본문이 통째로 돈다).
    #
    # $PSScriptRoot 는 이 스크립트 자기 폴더라 부르는 쪽 폴더를 안 따라간다.
    # try 안에 두는 이유: 실패해도 JSON 한 줄로 닫히게 하려는 것이다. try 밖이면
    # 예외가 그대로 나가 부르는 쪽이 결과를 한 줄도 못 받는다.
    try {
        # -Verbose:$false 를 붙이는 이유: 실기는 -Verbose 로 돌고, 그 값은 여기서 부르는
        # 스크립트까지 그대로 내려온다. 그러면 사례 하나마다 들여오기 알림이 열몇 줄씩
        # 쌓여 사람이 봐야 할 진단이 묻힌다. 결과 JSON 은 성공 스트림이고 이 알림은
        # 자세히 스트림이라 섞이지는 않는다(실측 확인). 읽기 어려워지는 것만 막는다.
        Import-Module -Name (Join-Path $PSScriptRoot "WfpObservationText.psm1") -ErrorAction Stop -Verbose:$false
        # 같은 이름의 다른 모듈이 먼저 올라와 있는 경우를 막는다. 다섯 이름이 전부
        # 실제로 풀리는지 여기서 확인한다.
        foreach ($requiredFunction in @(
            "ConvertFrom-PktmonFilterText", "Read-PktmonFilterRecord", "ConvertTo-RoundTripUtcText",
            "Get-PacketComponentId", "ConvertFrom-PktmonComponentJson"
        )) {
            if ($null -eq (Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) {
                throw ("OBSERVATION_MODULE_FUNCTION_MISSING:" + $requiredFunction)
            }
        }
    }
    catch {
        [Console]::Error.WriteLine("OBSERVATION_MODULE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason "OBSERVATION_MODULE_UNAVAILABLE" -Extra $observation
        return
    }

    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        Write-ToolResult -Status "ERROR" -FailureReason "RUN_DIRECTORY_MISSING" -Extra $observation
        return
    }

    # --- 바깥 도구 존재 확인 (§4.0 · T-11) ---------------------------------
    # 표준 자리를 "먼저" 본다. PATH 를 먼저 타면 PATH 에 든 아무 폴더에나
    # pktmon.exe 라는 이름을 놓아 두는 것으로 이 관리자 권한 실행을 가로챌 수 있다.
    # PATH 를 보는 것은 표준 자리에 없을 때뿐이다 (T-11: 다른 도구로 대신하지는 않는다).
    $pktmonSystemPath = Join-Path ${env:SystemRoot} "System32\pktmon.exe"
    if (Test-Path -LiteralPath $pktmonSystemPath -PathType Leaf) {
        $script:pktmonPath = $pktmonSystemPath
    }
    else {
        $pktmonCommand = Get-Command -Name "pktmon" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $pktmonCommand) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "TOOL_MISSING:pktmon" -Extra $observation
            return
        }
        $script:pktmonPath = $pktmonCommand.Source
    }

    $script:filterSnapshotPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory "pktmon-filters-before.json") -Root $RunDirectory
    $statePath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory ($CaseId + ".capture-state.json")) -Root $RunDirectory
    $etlPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory ($CaseId + ".etl")) -Root $RunDirectory
    $textPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory ($CaseId + ".etl.txt")) -Root $RunDirectory

    # =======================================================================
    # Start — 잡기 시작
    # =======================================================================
    if ($Mode -eq "Start") {
        # 이 실행 폴더에는 사례 64개가 같은 기록 파일 하나를 나눠 쓴다.
        # 파일이 이미 있다는 것은 앞 사례가 되돌리기에 실패해 남겼다는 뜻이다
        # (성공하면 Stop 이 지운다). 그때 지금 상태를 다시 찍어 덮으면,
        # 덮어쓰는 값은 "우리가 이미 지워 놓은 상태"라서 사용자의 원래 거르개
        # 목록이 영영 사라진다. 그러므로 있으면 그것을 그대로 이어받는다.
        $existingRecord = Read-PktmonFilterRecord -Path $script:filterSnapshotPath
        if ($null -ne $existingRecord) {
            $script:filterSnapshot = $existingRecord
            [Console]::Error.WriteLine("PKTMON_FILTER_RECORD_REUSED=" + [string]$script:filterSnapshotPath +
                " format=" + [string]$existingRecord.Format)
        }
        else {
            # 무엇이든 지우기 "전에" 지금 걸린 거르개 목록을 남긴다.
            # 이 순서를 뒤집으면 되돌릴 대상을 스스로 지운 뒤에 기록하게 된다.
            $script:filterSnapshot = Get-PktmonFilterSnapshot
            Set-Content -LiteralPath $script:filterSnapshotPath -Encoding utf8NoBOM -Value (
                [ordered]@{
                    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
                    caseId        = $CaseId
                    format        = [string]$script:filterSnapshot.Format
                    filterCount   = if ($null -eq $script:filterSnapshot.Filters) { $null } else { @($script:filterSnapshot.Filters).Count }
                    filters       = $script:filterSnapshot.Filters
                    raw           = [string]$script:filterSnapshot.Raw
                } | ConvertTo-Json -Depth 8)
        }

        # 이미 도는 세션이 있으면 시작이 실패한다. 먼저 한 번 멈춘다 [EXT-012 적용].
        # 같은 인자로 두 번 돌려도 결과가 같다.
        [void](Invoke-Pktmon -Arguments @("stop"))
        $script:filtersMutated = $true
        [void](Invoke-Pktmon -Arguments @("filter", "remove"))

        # 대상 주소·포트·전송으로 좁힌다. DNS 는 포트 53 으로 좁힌다.
        $filterArguments = [Collections.Generic.List[string]]::new()
        $filterArguments.Add("filter")
        $filterArguments.Add("add")
        $filterArguments.Add("wfp-spike-" + $CaseId)
        if ($null -ne $TargetAddress) {
            $filterArguments.Add("-i")
            $filterArguments.Add($TargetAddress.IPAddressToString)
        }
        if ($TargetPort -ne 0) {
            $filterArguments.Add("-p")
            $filterArguments.Add([string][int]$TargetPort)
        }
        $filterTransport = switch ($Transport) {
            "TCP"  { "TCP" }
            "UDP"  { "UDP" }
            "QUIC" { "UDP" }   # QUIC 는 UDP 위에서 돈다
            "DNS"  { "UDP" }
        }
        $filterArguments.Add("-t")
        $filterArguments.Add($filterTransport)

        $filterResult = Invoke-Pktmon -Arguments @($filterArguments)
        if ($filterResult.ExitCode -ne 0) {
            [Console]::Error.WriteLine("PKTMON_FILTER_DIAGNOSTIC=" + (($filterResult.Output -join " ") -replace "\s+", " "))
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "PKTMON_FILTER_FAILED" -Extra $observation
            return
        }

        Remove-Item -LiteralPath $etlPath -Force -ErrorAction SilentlyContinue
        # --file-size 를 기본값(512MB)보다 작게 주지 않는다.
        # pktmon 은 CPU 하나마다 16MB 짜리 ETW 버퍼를 잡는다. 최대 파일 크기가 버퍼를
        # 모두 담을 만큼 크지 않으면 순환 기록이 버퍼를 통째로 덮어써서, 잡기가 정상으로
        # 끝나도 꾸러미 사건이 파일에 한 개도 안 남는다. 파일은 미리 잡아 두지 않으므로
        # 512 를 줘도 실제 크기는 담긴 만큼이다(실측 46KB).
        # 2026-08-17 실측 (CPU 16개 · 같은 거르개 · 같은 연결):
        #   --file-size 16 -> 꾸러미 0개 · 32 -> 346줄 · 64 -> 1009줄 · 512 -> 1149줄(완전)
        # 기본값에 기대지 않고 적어서 넘긴다. 기본값이 바뀌면 조용히 되돌아가기 때문이다.
        $startResult = Invoke-Pktmon -Arguments @("start", "--capture", "--file-name", $etlPath, "--file-size", "512")
        if ($startResult.ExitCode -ne 0) {
            [Console]::Error.WriteLine("PKTMON_START_DIAGNOSTIC=" + (($startResult.Output -join " ") -replace "\s+", " "))
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "PKTMON_START_FAILED" -Extra $observation
            return
        }

        $script:captureStarted = $true
        $observation.captureStartedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        $state = [ordered]@{
            caseId              = $CaseId
            captureStartedAtUtc = $observation.captureStartedAtUtc
            etlPath             = $etlPath
            transport           = $Transport
            policyAppliedAtUtc  = if ([string]::IsNullOrWhiteSpace($PolicyAppliedAtUtc)) { "" } else { $PolicyAppliedAtUtc }
        }
        Set-Content -LiteralPath $statePath -Value ($state | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM

        # 여기까지 왔으면 Start 가 성공했다. 잡기가 계속 돌아야 하므로 되돌리지 않는다 —
        # 되돌리는 것은 -Mode Stop 의 몫이다. 이 창에서 프로세스가 죽는 경우를 위해
        # 되돌릴 목록은 실행 폴더에 남아 있고 restore-network-dev.ps1 이 마무리한다.
        $script:keepCaptureRunning = $true
        Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $observation
        return
    }

    # =======================================================================
    # Stop — 멈추고 판정
    # =======================================================================
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        Write-ToolResult -Status "ERROR" -FailureReason "CAPTURE_STATE_MISSING" -Extra $observation
        return
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $observation.captureStartedAtUtc = ConvertTo-RoundTripUtcText $state.captureStartedAtUtc

    # Start 가 남긴 되돌릴 목록을 집어 든다. 이제 되돌리기는 이 실행의 몫이다.
    $script:filtersMutated = $true
    $script:captureStarted = $true
    # 개수와 목록이 어긋나거나 못 읽으면 UNAVAILABLE 로 돌아온다.
    # 그러면 되돌린 척하지 않고 기록 파일을 남긴다.
    $script:filterSnapshot = Read-PktmonFilterRecord -Path $script:filterSnapshotPath
    if ($null -eq $script:filterSnapshot) {
        $script:filterSnapshot = [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = "" }
    }

    # 잡기를 멈춘다. 거르개 되돌리기는 아래 finally 가 어떤 경로로 끝나든 수행한다.
    $stopResult = Invoke-Pktmon -Arguments @("stop")
    $observation.captureStoppedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")

    # --- UNOBSERVED ⑤ : 잡기 창이 정책보다 앞섬 -----------------------------
    $policyText = if ([string]::IsNullOrWhiteSpace($PolicyAppliedAtUtc)) { ConvertTo-RoundTripUtcText $state.policyAppliedAtUtc } else { $PolicyAppliedAtUtc }
    if (-not [string]::IsNullOrWhiteSpace($policyText)) {
        [DateTimeOffset]$policyAppliedAt = [DateTimeOffset]::MinValue
        [DateTimeOffset]$captureStartedAt = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($policyText, [ref]$policyAppliedAt) -and
            [DateTimeOffset]::TryParse($observation.captureStartedAtUtc, [ref]$captureStartedAt) -and
            $captureStartedAt -lt $policyAppliedAt) {
            Write-ToolResult -Status "OK" -FailureReason "CAPTURE_BEFORE_POLICY" -Extra $observation
            return
        }
    }

    # --- UNOBSERVED ② : pktmon 이 0이 아닌 종료 코드 ------------------------
    if ($stopResult.ExitCode -ne 0) {
        [Console]::Error.WriteLine("PKTMON_STOP_DIAGNOSTIC=" + (($stopResult.Output -join " ") -replace "\s+", " "))
        $fallbackIndex = Get-TcpFallbackInterfaceIndex
        if ($null -ne $fallbackIndex) {
            $observation.method = "NETTCP_FALLBACK"
            $observation.observedInterfaceIndex = $fallbackIndex
            $observation.observedPath = if ($fallbackIndex -eq [int]$VpnInterfaceIndex) { "VPN" }
                elseif ($fallbackIndex -eq [int]$BaselineInterfaceIndex) { "BASELINE" }
                else { "OTHER" }
            Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $observation
            return
        }
        Write-ToolResult -Status "OK" -FailureReason "PKTMON_STOP_FAILED" -Extra $observation
        return
    }

    if (-not (Test-Path -LiteralPath $etlPath -PathType Leaf)) {
        Write-ToolResult -Status "OK" -FailureReason "PKTMON_CAPTURE_MISSING" -Extra $observation
        return
    }

    Remove-Item -LiteralPath $textPath -Force -ErrorAction SilentlyContinue
    $textResult = Invoke-Pktmon -Arguments @("etl2txt", $etlPath, "--out", $textPath)
    if ($textResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $textPath -PathType Leaf)) {
        [Console]::Error.WriteLine("PKTMON_ETL2TXT_DIAGNOSTIC=" + (($textResult.Output -join " ") -replace "\s+", " "))
        Write-ToolResult -Status "OK" -FailureReason "PKTMON_ETL2TXT_FAILED" -Extra $observation
        return
    }

    # --- 구성 요소 번호 -> 인터페이스 번호 지도 ------------------------------
    # 지도를 만드는 논리는 WfpObservationText.psm1 의 ConvertFrom-PktmonComponentJson
    # 에 있다(실측 구조와 결함 기록도 그 함수 머리 주석에 함께 옮겼다).
    # 지도를 못 만들면 UNOBSERVED ③ 이다. 다른 도구로 임의로 대신하지 않는다.
    #
    # 빈 지도가 되는 갈래는 셋이고 전부 그대로다 — 종료 코드가 0 이 아님 · JSON 파싱
    # 실패 · 항목 없음.
    $componentToInterface = @{}
    $listResult = Invoke-Pktmon -Arguments @("list", "--json")
    if ($listResult.ExitCode -eq 0) {
        $componentToInterface = ConvertFrom-PktmonComponentJson -Json ($listResult.Output -join "`n")
    }

    # --- 잡힌 꾸러미를 인터페이스별로 센다 -----------------------------------
    $countsByInterface = @{}
    $totalPackets = 0
    foreach ($line in [IO.File]::ReadLines($textPath)) {
        # 꾸러미 줄을 가리는 표식은 PktGroupId 다. 이 낱말은 번역되지 않는다.
        # 이름표("Component")로 세면 창 표시 언어가 영어가 아닌 PC 에서 0개가 된다.
        if ($line.IndexOf("PktGroupId", [StringComparison]::Ordinal) -lt 0) { continue }
        $totalPackets++
        $componentId = Get-PacketComponentId -Line $line
        if ($null -eq $componentId) { continue }
        if (-not $componentToInterface.ContainsKey($componentId)) { continue }
        $interfaceIndex = [int]$componentToInterface[$componentId]
        $countsByInterface[$interfaceIndex] = [int]$countsByInterface[$interfaceIndex] + 1
    }
    $observation.packetCount = $totalPackets

    # 상태 파일에 남은 원문은 실행 폴더 안에만 둔다. 결과 JSON 에는 숫자만 나간다.
    if ($totalPackets -eq 0) {
        # --- UNOBSERVED ① : 꾸러미 0개 -------------------------------------
        Write-ToolResult -Status "OK" -FailureReason "NO_PACKET_CAPTURED" -Extra $observation
        return
    }
    if ($countsByInterface.Count -eq 0) {
        # --- UNOBSERVED ③ : 구성 요소 번호를 못 읽음 -----------------------
        Write-ToolResult -Status "OK" -FailureReason "COMPONENT_INDEX_UNREADABLE" -Extra $observation
        return
    }

    $vpnCount = [int]$countsByInterface[[int]$VpnInterfaceIndex]
    $baselineCount = [int]$countsByInterface[[int]$BaselineInterfaceIndex]

    if ($vpnCount -eq $baselineCount -and $vpnCount -gt 0) {
        # --- UNOBSERVED ④ : 양쪽이 같은 수라 못 가름 -----------------------
        Write-ToolResult -Status "OK" -FailureReason "AMBIGUOUS_INTERFACE" -Extra $observation
        return
    }

    if ($vpnCount -gt $baselineCount) {
        $observation.observedPath = "VPN"
        $observation.observedInterfaceIndex = [int]$VpnInterfaceIndex
    }
    elseif ($baselineCount -gt $vpnCount) {
        $observation.observedPath = "BASELINE"
        $observation.observedInterfaceIndex = [int]$BaselineInterfaceIndex
    }
    else {
        # 둘 다 0 인데 다른 인터페이스에서는 잡혔다 -> OTHER
        $other = @($countsByInterface.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1)
        if ($other.Count -eq 1) {
            $observation.observedPath = "OTHER"
            $observation.observedInterfaceIndex = [int]$other[0].Key
        }
        else {
            Write-ToolResult -Status "OK" -FailureReason "COMPONENT_INDEX_UNREADABLE" -Extra $observation
            return
        }
    }

    Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $observation
}
catch {
    [Console]::Error.WriteLine("GET_WFP_SPIKE_INTERFACE_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
    Write-ToolResult -Status "ERROR" -FailureReason "UNHANDLED_ERROR" -Extra $observation
}
finally {
    # 축 1(되돌리기): 어떤 경로로 끝나든 — 정상 종료·중간 반환·예외 — 우리가 바꾼
    # pktmon 상태를 되돌린다.
    #
    # 성공한 -Mode Start 하나만 예외다. 그때는 잡기가 계속 돌아야 하는 것이 이 도구의
    # 계약이기 때문이다(Start 로 걸고 Stop 으로 걷는 두 번 호출). 그 창에서 프로세스가
    # 죽으면 이 실행 안에서는 손쓸 수 없으므로, 되돌릴 목록을 실행 폴더에 남겨 두고
    # restore-network-dev.ps1 이 그 파일을 보고 마무리한다.
    if (-not $script:keepCaptureRunning -and ($script:filtersMutated -or $script:captureStarted)) {
        try { Undo-PktmonState }
        catch {
            # 되돌리기 실패를 삼키지 않는다.
            [Console]::Error.WriteLine("PKTMON_UNDO_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " ") +
                " record=" + [string]$script:filterSnapshotPath)
        }
    }

    # --- -Mode Stop 재실행 안전 (A-2) --------------------------------------
    # 지금까지 Stop 은 잡기 창 표식({사례}.capture-state.json)을 안 지웠다. 그래서
    # 두 번째 Stop 이 초기 관문(CAPTURE_STATE_MISSING)을 안 만나고 그대로 진행해,
    # 되돌릴 목록 없이 `pktmon filter remove` 를 불렀다 — 그 명령은 우리 거르개만이
    # 아니라 이 PC 에 걸린 거르개를 전부 지운다.
    #
    # 지우는 자리를 되돌리기 "뒤"에 두는 것이 핵심이다. try 안에서 지우면 되돌리기보다
    # 앞이 되어, 되돌리기가 실패했는데도 표식이 사라진다. PowerShell 의 try/catch/finally
    # 는 새 범위를 안 만들므로 $statePath 가 여기서 그대로 보인다. 다만 실행 폴더가 없어
    # 그 변수를 만들기 전에 되돌아간 실행이 있으므로 빈 값 검사를 함께 건다.
    if ($Mode -eq "Stop" -and $script:pktmonUndoSucceeded -and
        -not [string]::IsNullOrWhiteSpace([string]$statePath)) {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}
