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

# `pktmon filter list` 의 글자 출력에서 거르개 줄만 뽑는다.
#
# 이 PC 의 pktmon 은 --json 을 받지 않는다(실측). 그렇다고 "못 읽었다"로 두면
# 거르개가 원래 0개였던 흔한 경우에도 되돌리기 실패로 적히고, 되돌릴 목록 파일이
# 실행마다 쌓인다. 그래서 글자도 읽는다.
#
# 자료 줄은 번호로 시작한다 — 머리글 줄은 `#`, 구분 줄은 `-` 로 시작한다.
# 숫자로 가르므로 화면 말이 어느 나라 말이든 같게 동작한다.
# 칸 차례는 `# 이름 프로토콜 IP주소 포트` 다.
function ConvertFrom-PktmonFilterText {
    param([AllowEmptyString()][string]$Text)

    $rows = [Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*\d+\s+(?<rest>\S.*?)\s*$')
        if (-not $match.Success) { continue }
        $tokens = @($match.Groups['rest'].Value -split '\s+')
        if ($tokens.Count -lt 1 -or [string]::IsNullOrWhiteSpace($tokens[0])) { continue }
        $rows.Add([pscustomobject]@{
            name     = $tokens[0]
            protocol = if ($tokens.Count -ge 2) { $tokens[1] } else { "" }
            ip       = if ($tokens.Count -ge 3) { $tokens[2] } else { "" }
            port     = if ($tokens.Count -ge 4) { $tokens[3] } else { "" }
        })
    }
    return @($rows)
}

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

# 실행 폴더에 남은 되돌릴 목록을 읽는다. Start 와 Stop 이 같은 함수를 쓴다.
#
# 개수와 목록이 서로 맞지 않으면 "못 읽었다"로 본다. 예전에는 개수가 비어 있으면
# [int]$null 이 0 이 되어 "원래 0개였다"로 읽혔고, 그러면 되돌리기가 성공한 것으로
# 처리되어 이 기록 파일이 지워졌다 — 사용자 거르개의 유일한 사본이 사라진다.
function Read-PktmonFilterRecord {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $savedFormat = [string]$saved.format
        if ($savedFormat -ne "JSON" -and $savedFormat -ne "TEXT") {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        # 개수 칸이 비어 있으면 0 으로 읽지 않는다. 못 읽은 것이다.
        [int]$savedCount = -1
        if (-not [int]::TryParse([string]$saved.filterCount, [ref]$savedCount) -or $savedCount -lt 0) {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        $savedFilters = @()
        if ($savedCount -gt 0) { $savedFilters = @($saved.filters) }
        # 적어 둔 개수와 실제 목록 길이가 다르면 그 기록은 믿을 수 없다.
        if ($savedFilters.Count -ne $savedCount) {
            return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = [string]$saved.raw }
        }

        return [pscustomobject]@{ Format = $savedFormat; Filters = $savedFilters; Raw = [string]$saved.raw }
    }
    catch {
        return [pscustomobject]@{ Format = "UNAVAILABLE"; Filters = $null; Raw = "" }
    }
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
    if ($script:captureStarted) {
        $stopUndo = Invoke-Pktmon -Arguments @("stop")
        if ($stopUndo.ExitCode -ne 0) {
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

# 실행 폴더에 남긴 시각을 다시 읽을 때 쓴다.
#
# ConvertFrom-Json 은 ISO-8601 모양의 글자를 [datetime] 으로 바꿔 놓는다. 그 값을
# [string] 로 되돌리면 현재 문화권 서식의 "현지 시각·초 단위" 글자가 나온다
# (실측: "2026-08-17T06:35:26.2726621+00:00" -> "08/17/2026 15:35:26").
# 그대로 -PolicyAppliedAtUtc 와 견주면 같은 초에 걸린 두 시각이 "앞선다"로 뒤집혀
# UNOBSERVED ⑤ 로 닫힌다. 기록으로 남는 값도 UTC 가 아니게 된다.
# 2026-08-17 실측: 정책과 잡기 시작 간격 0.2초 -> CAPTURE_BEFORE_POLICY · 10초 -> 정상.
function ConvertTo-RoundTripUtcText {
    param($Value)

    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime().ToString("O") }
    if ($Value -is [datetime]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString("O") }
    return [string]$Value
}

# 꾸러미 줄 하나에서 구성 요소 번호를 뽑는다.
#
# pktmon etl2txt 의 칸 이름표는 창 표시 언어를 따라 번역된다. 이 PC 실측(2026-08-17):
#   영어  ... Direction Tx , Type Ethernet , Component 80, Edge 1, Filter 1, ...
#   한국어 ... 방향 Tx , 유형 Ethernet , 구성 요소 80, 에지 1, 필터 1, ...
# 그래서 "Component" 라는 이름표만 찾으면 한국어 PC 에서는 한 줄도 안 걸리고,
# 잡기가 정상이어도 꾸러미 0개(NO_PACKET_CAPTURED)로 닫힌다.
#
# 이름표가 번역돼도 칸의 자리는 같다. 쉼표로 나눈 순서는 이렇다.
#   0 PktGroupId · 1 PktNumber · 2 모양 · 3 방향 · 4 유형 · 5 구성 요소 · 6 에지 · 7 필터
#   · 8 OriginalSize · 9 LoggedSize
# 자리로 뽑은 값이 지도에 없으면 세지 않으므로, 서식이 바뀌어도 틀린 값을 만들지 않는다.
function Get-PacketComponentId {
    param([Parameter(Mandatory)][string]$Line)

    $match = [regex]::Match($Line, '(?i)\bComponent\s*[:=]?\s*(\d+)')
    if ($match.Success) { return $match.Groups[1].Value }

    $fields = $Line.Split(',')
    if ($fields.Count -lt 10) { return $null }
    $fieldMatch = [regex]::Match($fields[5], '(\d+)\s*$')
    if (-not $fieldMatch.Success) { return $null }
    return $fieldMatch.Groups[1].Value
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
    # pktmon 의 구성 요소 번호는 인터페이스 번호와 다르다. pktmon list 로 지도를 만든다.
    # 지도를 못 만들면 UNOBSERVED ③ 이다. 다른 도구로 임의로 대신하지 않는다.
    # pktmon list --json 은 평평한 목록이 아니다. 실측 구조(2026-08-17)는 이렇다.
    #   [ { "Group": "...", "Components": [ { "Id": 124, "Properties": [ { "Name": "ifIndex", "Value": 8 } ] } ] } ]
    # 인터페이스 번호는 구성 요소의 직접 속성이 아니라 Properties 목록 안 이름/값 쌍이다.
    # 옛 코드는 맨 바깥 객체에서 Id 와 ifIndex 를 직접 찾아, 지도가 늘 빈 채로 끝났다
    # (꾸러미를 세어도 COMPONENT_INDEX_UNREADABLE 로 닫혔다).
    # 평평한 목록으로 오는 판도 대비해 Components 가 없으면 그 객체 자체를 구성 요소로 본다.
    $componentToInterface = @{}
    $listResult = Invoke-Pktmon -Arguments @("list", "--json")
    if ($listResult.ExitCode -eq 0) {
        try {
            $listJson = ($listResult.Output -join "`n") | ConvertFrom-Json
            foreach ($group in @($listJson)) {
                if ($null -eq $group) { continue }
                $groupComponents = if ($group.PSObject.Properties.Name -contains "Components") { @($group.Components) } else { @($group) }
                foreach ($component in $groupComponents) {
                    if ($null -eq $component) { continue }

                    $componentId = $null
                    foreach ($name in @("Id", "ComponentId", "id")) {
                        if ($component.PSObject.Properties.Name -contains $name) { $componentId = [string]$component.$name; break }
                    }
                    if ([string]::IsNullOrWhiteSpace($componentId)) { continue }

                    $interfaceIndex = $null
                    # 먼저 직접 속성으로 있는지 본다.
                    foreach ($name in @("InterfaceIndex", "IfIndex", "NetworkInterfaceIndex", "ifIndex")) {
                        if ($component.PSObject.Properties.Name -contains $name) { $interfaceIndex = [string]$component.$name; break }
                    }
                    # 없으면 Properties 목록에서 이름으로 찾는다.
                    if ([string]::IsNullOrWhiteSpace($interfaceIndex)) {
                        foreach ($property in @($component.Properties)) {
                            if ($null -eq $property) { continue }
                            if ([string]$property.Name -in @("ifIndex", "IfIndex", "InterfaceIndex", "NetworkInterfaceIndex")) {
                                $interfaceIndex = [string]$property.Value
                                break
                            }
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($interfaceIndex)) { continue }

                    $componentToInterface[$componentId] = [int]$interfaceIndex
                }
            }
        }
        catch { $componentToInterface = @{} }
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
}
