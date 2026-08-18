# Use-WfpSpikeTunnel.ps1 — 시험용 터널 준비·확인·정리
#
# 설계: R4 설계서 §4.0 · §4.5 · §9.1 · §11.2(G-08) · §12.3
# 닫는 AC: AC-03-8(6단계) · AC-11-2(IPv6 갈림) · AC-13-4(지문 창 밖) · AC-13-5(정책보다 나중에 내림) · AC-12-1
#
# 설정 파일을 열지 않는다 (NFR-02 · T-5 · GR-14)
#   -ConfigPath 는 wireguard.exe 에 그대로 넘길 뿐이다.
#   이 파일 안에 그 경로를 Get-Content · Select-String 으로 여는 줄이 0건이다.
#   결과 JSON 에도 경로가 들어가지 않는다 (configPath 칸이 없다).
#
# 순서 잠금 (BL-05 · AC-13-5)
#   Teardown 은 소유 정책이 0건인 것을 확인한 뒤에만 터널을 내린다.
#   정책이 터널 LUID 를 다음 홉으로 잡고 있으므로(NativePolicyBuffer.cs:51-56)
#   터널을 먼저 내리면 정책이 없는 인터페이스를 가리키게 된다.
#   이 순서를 사람 기억이 아니라 검사로 지킨다.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("Prepare", "Verify", "Teardown")][string]$Mode,

    # G-08: 있는지와 확장자만 확인하고 파일을 열지 않는다 (회귀 확인 GR-14).
    [AllowEmptyString()][string]$ConfigPath,

    [Parameter(Mandatory)][string]$RunDirectory,

    # G-08: 서비스·터널 이름은 정규식으로 좁힌다.
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_\-]{1,64}$')]
    [string]$TunnelServiceName,

    # 단계 2 "터널 너머로 실제 통신됨"을 재는 대상.
    # 주소를 스크립트에 적어 두지 않고 인자로 받는다 (§4.1 과 같은 규칙).
    [ipaddress]$ReachabilityAddress,
    [ValidateRange(1, 60000)][int]$ReachabilityTimeoutMs = 4000,

    # 하네스를 먼저 끝내고 정책이 0건인지 다시 센 뒤 정리로 들어갑니다.
    # 사람이 이 스위치를 준 실행에서만 동작합니다.
    #
    # 무인 자동 경로를 만들지 않는다 (NFR-03). PowerShell 스위치는 기본이 꺼짐이라
    # 기본값을 따로 적지 않는다. 이 저장소 안에서 이 스위치를 붙여 이 스크립트를
    # 부르는 자리는 0건이다 — 켜는 길은 사람이 명령줄에 직접 적는 것뿐이다.
    [switch]$StopHarnessFirst,

    # 하네스를 끝낸 뒤 정책이 사라지기를 기다리는 시간(밀리초). 기본 2000.
    # 상한을 거는 이유: 없으면 사고 복구 경로가 사람 손 없이 오래 멈춘다.
    [ValidateRange(0, 60000)][int]$HarnessStopWaitMs = 2000
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolName = "Use-WfpSpikeTunnel"
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

# test-wfp-app-routing-spike.ps1:454-479 (Get-NetworkFingerprint) 과 같은 방식으로 잰다.
# F0 과 F3 을 같은 자로 재야 "0단계로 돌아왔다"를 말할 수 있다 (§7.4).
function Get-NetworkFingerprint {
    $routeRows = Get-NetRoute -ErrorAction Stop |
        Select-Object AddressFamily, DestinationPrefix, InterfaceIndex, NextHop, RouteMetric, State |
        Sort-Object AddressFamily, DestinationPrefix, InterfaceIndex, NextHop, RouteMetric, State
    $dnsRows = Get-DnsClientServerAddress -ErrorAction Stop |
        Select-Object InterfaceIndex, AddressFamily, ServerAddresses |
        ForEach-Object {
            [pscustomobject]@{
                InterfaceIndex  = $_.InterfaceIndex
                AddressFamily   = $_.AddressFamily
                ServerAddresses = @($_.ServerAddresses | Sort-Object)
            }
        } | Sort-Object InterfaceIndex, AddressFamily
    $adapterRows = Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object { $_.Name -notlike "VpnRtr-*" -and $_.InterfaceDescription -notmatch '(?i)WireGuard' } |
        Select-Object InterfaceIndex, Status |
        Sort-Object InterfaceIndex, Status

    $canonical = [ordered]@{
        routes   = @($routeRows)
        dns      = @($dnsRows)
        adapters = @($adapterRows)
    } | ConvertTo-Json -Depth 6 -Compress
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)))
}

# 터널이 아직 없을 때의 기본 경로 인터페이스 = 기준 인터페이스.
function Get-DefaultRouteInterfaceIndex {
    # 기본 경로가 여럿일 때 "실제로 나가는 길"을 고른다.
    #
    # 옛 코드가 틀린 자리 두 곳 (2026-08-18 실측으로 확인):
    #   ① `Sort-Object RouteMetric, InterfaceMetric` — `InterfaceMetric` 은
    #      Get-NetRoute 결과에 **없는 속성**이다(Get-NetIPInterface 쪽에 있다).
    #      그래서 두 번째 정렬 기준이 늘 비어 있었다.
    #   ② 끊긴 랜카드의 낡은 기본 경로를 거르지 않았다. 실측: 이더넷 17 이
    #      Disconnected 인데 기본 경로가 남아 있었고, 둘 다 RouteMetric 0 이라
    #      먼저 나온 17 이 뽑혔다. 실제로 나가는 길은 Wi-Fi 8 이었다.
    #      멀쩡한 제품이 UNEXPECTED_INTERFACE 로 적힐 수 있는 자리다.
    #
    # 그래서 어댑터가 'Up' 인 것만 후보로 두고, 두 metric 을 제대로 붙여 정렬한다.
    # 후보가 하나도 없으면 못 정한 것으로 두고 null 을 돌려준다 — 채우지 않는다(§4.0).
    $routes = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)
    if ($routes.Count -eq 0) { return $null }

    $candidates = foreach ($r in $routes) {
        $adapter = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
        if ($null -eq $adapter -or $adapter.Status -ne "Up") { continue }
        $ipInterface = Get-NetIPInterface -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [pscustomobject]@{
            InterfaceIndex  = [int]$r.InterfaceIndex
            RouteMetric     = [int]$r.RouteMetric
            InterfaceMetric = if ($null -eq $ipInterface) { [int]::MaxValue } else { [int]$ipInterface.InterfaceMetric }
        }
    }

    $picked = @($candidates | Sort-Object -Property RouteMetric, InterfaceMetric, InterfaceIndex) | Select-Object -First 1
    if ($null -eq $picked) { return $null }
    return [int]$picked.InterfaceIndex
}

function Get-TunnelAdapter {
    return @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.InterfaceAlias -eq $TunnelServiceName -or [string]$_.Name -eq $TunnelServiceName }) |
        Select-Object -First 1
}

function Test-TunnelReachable {
    param([Parameter(Mandatory)][ipaddress]$Address)

    # 바깥 도구를 더 쓰지 않는다. .NET 기본 형으로 재고, 못 재면 거짓이다.
    $ping = [Net.NetworkInformation.Ping]::new()
    try {
        $reply = $ping.Send($Address, $ReachabilityTimeoutMs)
        return $null -ne $reply -and $reply.Status -eq [Net.NetworkInformation.IPStatus]::Success
    }
    catch { return $false }
    finally { $ping.Dispose() }
}

$tunnelState = [ordered]@{
    mode                      = $Mode
    tunnelUp                  = $false
    tunnelInterfaceIndex      = $null
    reachable                 = $false
    ipv6GlobalAddressPresent  = $false
    ipv6DefaultRouteViaTunnel = $false
    ipv6Verdict               = "INCONCLUSIVE"
    baselineInterfaceIndex    = $null
    # 아래 두 칸은 모드가 달라도 늘 있다. 읽는 쪽이 칸이 있나 없나로 갈라지지 않게 한다.
    # Prepare · Verify 결과에도 같은 두 칸이 나온다.
    harnessStopRequested      = $false
    # 실제로 끝낸 프로세스 수. 못 세면 0 이 아니라 null 이다 —
    # "0건 확인"과 "못 셈"은 다른 사실이다. 갈래에 안 들어갔으면 null 이다.
    harnessProcessesStopped   = $null
}

try {
    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        Write-ToolResult -Status "ERROR" -FailureReason "RUN_DIRECTORY_MISSING" -Extra $tunnelState
        return
    }

    # --- 바깥 도구 존재 확인 (§4.0 · T-11) ---------------------------------
    foreach ($required in @("Get-NetRoute", "Get-NetIPAddress", "Get-NetAdapter", "Get-DnsClientServerAddress")) {
        if ($null -eq (Get-Command -Name $required -ErrorAction SilentlyContinue)) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("TOOL_MISSING:" + $required) -Extra $tunnelState
            return
        }
    }
    # 설치 자리를 "먼저" 본다. PATH 를 먼저 타면 PATH 에 든 아무 폴더에나
    # wireguard.exe 라는 이름을 놓아 두는 것으로 이 관리자 권한 실행을 가로챌 수 있다.
    # PATH 를 보는 것은 설치 자리에 없을 때뿐이다 (T-11: 다른 도구로 대신하지는 않는다).
    $wireguardInstalledPath = Join-Path ${env:ProgramFiles} "WireGuard\wireguard.exe"
    if (Test-Path -LiteralPath $wireguardInstalledPath -PathType Leaf) {
        $wireguardPath = $wireguardInstalledPath
    }
    else {
        $wireguardCommand = Get-Command -Name "wireguard.exe" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $wireguardCommand) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "TOOL_MISSING:wireguard.exe" -Extra $tunnelState
            return
        }
        $wireguardPath = $wireguardCommand.Source
    }

    $baselinePath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory "tunnel-baseline.json") -Root $RunDirectory

    # =======================================================================
    # Prepare — 단계 0(기준선 지문 F0·기준 인터페이스) + 단계 1(터널 올림)
    # =======================================================================
    if ($Mode -eq "Prepare") {
        # G-08: 있는지와 확장자만 본다. 파일을 열지 않는다.
        if ([string]::IsNullOrWhiteSpace($ConfigPath) -or
            -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf) -or
            [IO.Path]::GetExtension($ConfigPath) -ne ".conf") {
            Write-ToolResult -Status "ERROR" -FailureReason "CONFIG_PATH_INVALID" -Extra $tunnelState
            return
        }

        # 터널을 올리기 "전"에 기준선을 고정한다. 올린 뒤에 찍으면
        # "설치 전으로 돌아왔다"가 터널이 남은 상태를 뜻하게 된다 (BL-09).
        $baselineInterfaceIndex = Get-DefaultRouteInterfaceIndex
        $tunnelState.baselineInterfaceIndex = $baselineInterfaceIndex
        $baseline = [ordered]@{
            capturedAtUtc          = [DateTimeOffset]::UtcNow.ToString("O")
            fingerprintF0          = Get-NetworkFingerprint
            baselineInterfaceIndex = $baselineInterfaceIndex
            tunnelServiceName      = $TunnelServiceName
        }
        Set-Content -LiteralPath $baselinePath -Value ($baseline | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM

        # 단계 1 — 터널 올림. 인자를 하나씩 넘긴다 (GR-15).
        $installOutput = & $wireguardPath "/installtunnelservice" $ConfigPath 2>&1
        $installExitCode = [int]$LASTEXITCODE
        if ($installExitCode -ne 0) {
            [Console]::Error.WriteLine("WIREGUARD_INSTALL_DIAGNOSTIC=" + ((@($installOutput) -join " ") -replace "\s+", " "))
            Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_START_FAILED" -Extra $tunnelState
            return
        }

        # 터널이 올라갔다는 사실을 "바로" 남긴다 (설계 §4.0 되돌릴 목록).
        # 아래 어느 단계에서 실패하든 이 파일이 남아 있어야 정리가 안 끝났다는 것을
        # 다음 사람이 알 수 있다. Teardown 이 성공하면 그때 이 파일을 지운다.
        $installedRecordPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory "tunnel-installed.json") -Root $RunDirectory
        Set-Content -LiteralPath $installedRecordPath -Encoding utf8NoBOM -Value (
            [ordered]@{
                installedAtUtc    = [DateTimeOffset]::UtcNow.ToString("O")
                tunnelServiceName = $TunnelServiceName
            } | ConvertTo-Json -Depth 3)

        # 서비스가 실제로 뜰 때까지 잠깐 기다린다.
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
        while ([DateTimeOffset]::UtcNow -lt $deadline) {
            if ($null -ne (Get-TunnelAdapter)) { break }
            Start-Sleep -Milliseconds 500
        }

        $adapter = Get-TunnelAdapter
        if ($null -eq $adapter) {
            # 서비스는 올렸는데 어댑터가 안 뜬다. 되돌릴 목록은 위에서 이미 남겼다.
            # 여기서 임의로 터널을 내리지 않는다 — §4.5 단계 2 가 "그 자리에서 멈추고
            # 사용자에게 알린다"이고, 반쯤 올라간 상태를 사람이 봐야 원인을 찾는다.
            [Console]::Error.WriteLine("TUNNEL_INSTALLED_BUT_ADAPTER_MISSING=record " + $installedRecordPath)
            Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_START_FAILED" -Extra $tunnelState
            return
        }
        $tunnelState.tunnelUp = ([string]$adapter.Status -eq "Up")
        $tunnelState.tunnelInterfaceIndex = [int]$adapter.InterfaceIndex

        Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $tunnelState
        return
    }

    # 기준선을 읽어 둔다 (Verify · Teardown 공통).
    $baseline = $null
    if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
        if ($null -ne $baseline.baselineInterfaceIndex) {
            $tunnelState.baselineInterfaceIndex = [int]$baseline.baselineInterfaceIndex
        }
    }

    # =======================================================================
    # Verify — 단계 2(생존 확인) · 3(IPv6 확인) · 5(터널 index 넘김)
    # =======================================================================
    if ($Mode -eq "Verify") {
        $adapter = Get-TunnelAdapter
        if ($null -eq $adapter) {
            Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_NOT_FOUND" -Extra $tunnelState
            return
        }
        $tunnelState.tunnelUp = ([string]$adapter.Status -eq "Up")
        $tunnelState.tunnelInterfaceIndex = [int]$adapter.InterfaceIndex

        if (-not $tunnelState.tunnelUp) {
            Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_NOT_UP" -Extra $tunnelState
            return
        }

        # 단계 2 — 터널 너머로 실제 통신되는지. 안 되면 그 자리에서 멈춘다.
        # 다른 설정 파일을 임의로 찾지 않는다 (§4.5 단계 2).
        if ($null -eq $ReachabilityAddress) {
            Write-ToolResult -Status "ERROR" -FailureReason "REACHABILITY_TARGET_UNSET" -Extra $tunnelState
            return
        }
        $tunnelState.reachable = Test-TunnelReachable -Address $ReachabilityAddress
        if (-not $tunnelState.reachable) {
            Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_NOT_REACHABLE" -Extra $tunnelState
            return
        }

        # 단계 3 — IPv6 확인. 둘 중 하나라도 없으면 INCONCLUSIVE 이고 재시도하지 않는다.
        $globalAddresses = @(Get-NetIPAddress -InterfaceIndex $tunnelState.tunnelInterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                Where-Object {
                    $candidate = [ipaddress][string]$_.IPAddress
                    -not $candidate.IsIPv6LinkLocal -and -not $candidate.IsIPv6SiteLocal -and
                    -not [Net.IPAddress]::IsLoopback($candidate)
                })
        $tunnelState.ipv6GlobalAddressPresent = $globalAddresses.Count -gt 0

        $ipv6DefaultRoutes = @(Get-NetRoute -DestinationPrefix "::/0" -ErrorAction SilentlyContinue |
                Where-Object { [int]$_.InterfaceIndex -eq [int]$tunnelState.tunnelInterfaceIndex })
        $tunnelState.ipv6DefaultRouteViaTunnel = $ipv6DefaultRoutes.Count -gt 0

        $tunnelState.ipv6Verdict = if ($tunnelState.ipv6GlobalAddressPresent -and $tunnelState.ipv6DefaultRouteViaTunnel) {
            "MEASURE"
        }
        else { "INCONCLUSIVE" }

        # 단계 5 — 터널 index 를 넘긴다. 하네스는 읽기만 한다 (R2-AC-05-3).
        Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $tunnelState
        return
    }

    # =======================================================================
    # Teardown — 단계 6(정책 0건 확인 -> 터널 내림 -> 지문 F3)
    # =======================================================================
    $adapter = Get-TunnelAdapter
    if ($null -ne $adapter) {
        $tunnelState.tunnelUp = ([string]$adapter.Status -eq "Up")
        $tunnelState.tunnelInterfaceIndex = [int]$adapter.InterfaceIndex
    }

    # =======================================================================
    # [신설] 사람이 고른 정리 갈래 — 하네스를 먼저 끝낸다 (A-1)
    #
    # 이 갈래는 -StopHarnessFirst 를 사람이 직접 준 실행에서만 돈다. 스위치를 안 준
    # 실행은 이 블록을 통째로 건너뛰고 아래 기존 관문으로 곧장 간다. 기존 블록을
    # 한 글자도 안 고치고 "앞에" 붙인 이유가 그것이다 — 스위치 없는 실행이 글자 그대로
    # 같은 경로를 지나는 것이 읽어서가 아니라 코드로 증명된다.
    #
    # 순서 잠금은 무르지 않는다. 이 갈래는 아래 관문을 대체하지 않고 그 "앞"에 선다.
    # 하네스가 안 죽었으면 여기서 멈추므로 터널을 내리는 명령까지 내려가지 않는다.
    # (그 명령 글자를 주석에 적지 않는다 — 회귀 확인이 이 파일에서 그 글자가 딱 한 번,
    #  곧 실제 호출 자리에서만 나오는 것을 센다.)
    #
    # 대가: netsh wfp show state 가 한 번 더 돈다 (이 갈래 1회 + 기존 관문 1회 = 2회).
    # 사고 복구 경로라 이 대가를 받는다.
    # =======================================================================
    if ($StopHarnessFirst) {
        $tunnelState.harnessStopRequested = $true

        # --- ① 알림 -------------------------------------------------------
        # 표준 출력은 결과 JSON 한 줄이고 부르는 쪽이 마지막 줄을 파싱한다.
        # 그래서 사람이 읽는 글자는 경고 스트림으로 낸다 — `& <경로>` 는 성공 스트림만
        # 잡으므로 이 글자가 결과 JSON 에 섞이지 않는다.
        Write-Warning "사람이 고른 갈래로 들어갑니다: 하네스 종료 → 대기 → 정책 재열거 → 정리 관문."

        # --- ② 하네스 종료 시도 --------------------------------------------
        # 끝낼 대상은 개수를 세는 쪽과 같은 이름 하나뿐이다
        # (Get-WfpOwnedPolicyState.ps1 의 $harnessProcessName). 세는 것과 끝내는 것의
        # 대상이 어긋나면 ④가 영영 통과 못 하거나 엉뚱한 것을 죽인다.
        # VpnRouter.Service · VpnRouter.App 은 건드리지 않는다 — 그 둘은
        # restore-network-dev.ps1 의 몫이다.
        $harnessProcessName = "VpnRouter.WfpSpike.Harness"
        if ($null -eq (Get-Command -Name "Get-Process" -ErrorAction SilentlyContinue)) {
            $tunnelState.harnessProcessesStopped = $null
        }
        else {
            $harnessQueryErrors = $null
            $harnessProcesses = @(Get-Process -Name $harnessProcessName -ErrorAction SilentlyContinue -ErrorVariable harnessQueryErrors)
            # 이름에 맞는 프로세스가 없을 때도 오류가 하나 올라온다. 그것은 "0건"이지
            # 실패가 아니다. 그 밖의 오류(접근 거부 등)는 "못 셈"이다.
            $realHarnessErrors = @($harnessQueryErrors | Where-Object {
                [string]$_.FullyQualifiedErrorId -notlike "NoProcessFoundForGivenName*"
            })
            if ($realHarnessErrors.Count -gt 0) {
                [Console]::Error.WriteLine("HARNESS_QUERY_DIAGNOSTIC=" +
                    ((@($realHarnessErrors | ForEach-Object { [string]$_.Exception.Message }) -join " ") -replace "\s+", " "))
                $tunnelState.harnessProcessesStopped = $null
            }
            else {
                $harnessStoppedCount = 0
                foreach ($harnessProcess in $harnessProcesses) {
                    try {
                        $harnessProcess.Kill()
                        [void]$harnessProcess.WaitForExit(5000)
                        $harnessStoppedCount++
                    }
                    catch {
                        [Console]::Error.WriteLine("HARNESS_STOP_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
                    }
                }
                $tunnelState.harnessProcessesStopped = $harnessStoppedCount
            }
        }

        # --- ③ 정책이 사라질 시간을 준다 ------------------------------------
        # 동적 세션은 프로세스가 죽으면 반드시 사라지지만
        # (NativeSessionBuffer.cs:36 FWPM_SESSION_FLAG_DYNAMIC), 그것이 곧바로
        # 열거에 반영되지는 않는다.
        if ($HarnessStopWaitMs -gt 0) { Start-Sleep -Milliseconds $HarnessStopWaitMs }

        # --- ④ 정책 재열거 --------------------------------------------------
        # 기존 관문과 "같은 순서"로 읽는다 — 세 신호가 전부 OK 인 것을 먼저 보고
        # 나서만 개수를 정수로 읽는다. 빈 값을 [int] 로 바꿔 0 이 되는 자리를
        # 새로 만들지 않는다.
        $harnessStopEnumeratorPath = Join-Path $PSScriptRoot "Get-WfpOwnedPolicyState.ps1"
        if (-not (Test-Path -LiteralPath $harnessStopEnumeratorPath -PathType Leaf)) {
            Write-ToolResult -Status "ERROR" -FailureReason "POLICY_ENUMERATOR_MISSING" -Extra $tunnelState
            return
        }
        $afterStopJson = & $harnessStopEnumeratorPath -RunDirectory $RunDirectory -Label "after-harness-stop"
        $afterStopState = $null
        $afterStopLines = @($afterStopJson | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($afterStopLines.Count -gt 0) {
            try { $afterStopState = ([string]$afterStopLines[-1] | ConvertFrom-Json) } catch { $afterStopState = $null }
        }
        if ($null -eq $afterStopState -or [string]$afterStopState.status -ne "OK") {
            Write-ToolResult -Status "ERROR" -FailureReason "POLICY_STATE_UNREADABLE" -Extra $tunnelState
            return
        }
        $afterStopSignalsComplete = [string]$afterStopState.signals.ownedPolicyEnumeration -eq "OK" -and
            [string]$afterStopState.signals.ownerSession -eq "OK" -and
            [string]$afterStopState.signals.harnessProcess -eq "OK"
        if (-not $afterStopSignalsComplete) {
            [Console]::Error.WriteLine("POLICY_SIGNALS_INCOMPLETE=" + (($afterStopState.signals | ConvertTo-Json -Compress) -replace "\s+", " "))
            Write-ToolResult -Status "ERROR" -FailureReason "POLICY_STATE_UNREADABLE" -Extra $tunnelState
            return
        }

        # 우리가 끝내려던 것이 안 끝났으면 여기서 멈춘다.
        # 이 낱말은 "하네스·세션이 아직 살아 있다"만 뜻한다. 정책만 남은 경우는
        # 아래 기존 관문의 POLICY_STILL_PRESENT 가 낸다 — 새 갈래는 기존 관문을
        # 대체하지 않는다.
        if ([int]$afterStopState.harnessProcessCount -ne 0 -or [int]$afterStopState.ownerSessionCount -ne 0) {
            Write-Warning "하네스를 끝내려 했지만 아직 살아 있습니다. 정책이 남은 채로 터널을 내리면 죽은 주소를 가리키는 정책이 남으므로 여기서 멈춥니다. 하네스를 직접 끝낸 뒤 다시 돌리십시오."
            Write-ToolResult -Status "ERROR" -FailureReason "HARNESS_STILL_RUNNING" -Extra $tunnelState
            return
        }
    }

    # 순서 잠금 — 정책이 0건인 것을 먼저 확인한다.
    $enumeratorPath = Join-Path $PSScriptRoot "Get-WfpOwnedPolicyState.ps1"
    if (-not (Test-Path -LiteralPath $enumeratorPath -PathType Leaf)) {
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_ENUMERATOR_MISSING" -Extra $tunnelState
        return
    }
    $policyJson = & $enumeratorPath -RunDirectory $RunDirectory -Label "before-teardown"
    $policyState = $null
    $policyLines = @($policyJson | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($policyLines.Count -gt 0) {
        try { $policyState = ([string]$policyLines[-1] | ConvertFrom-Json) } catch { $policyState = $null }
    }
    if ($null -eq $policyState -or [string]$policyState.status -ne "OK") {
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_STATE_UNREADABLE" -Extra $tunnelState
        return
    }

    # 가장 나쁜 쪽으로 읽는다 (§4.3 신호 어긋남 처리).
    # 세 신호가 "다 서고" 셋 다 0 일 때만 터널을 내린다. 신호 하나를 못 셌으면
    # 그 값은 0 이 아니라 null 이고, null 을 0 으로 읽으면 정책이 남은 채로
    # 터널을 내리게 된다 — 정책이 터널 LUID 를 잡고 있으므로 그것이 BL-05 위반이다.
    $signalsComplete = [string]$policyState.signals.ownedPolicyEnumeration -eq "OK" -and
        [string]$policyState.signals.ownerSession -eq "OK" -and
        [string]$policyState.signals.harnessProcess -eq "OK"
    if (-not $signalsComplete) {
        [Console]::Error.WriteLine("POLICY_SIGNALS_INCOMPLETE=" + (($policyState.signals | ConvertTo-Json -Compress) -replace "\s+", " "))
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_STATE_UNREADABLE" -Extra $tunnelState
        return
    }

    $policyClear = [int]$policyState.ownedPolicyCount -eq 0 -and
        [int]$policyState.ownerSessionCount -eq 0 -and
        [int]$policyState.harnessProcessCount -eq 0
    if (-not $policyClear) {
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_STILL_PRESENT" -Extra $tunnelState
        return
    }

    $uninstallOutput = & $wireguardPath "/uninstalltunnelservice" $TunnelServiceName 2>&1
    $uninstallExitCode = [int]$LASTEXITCODE
    if ($uninstallExitCode -ne 0) {
        [Console]::Error.WriteLine("WIREGUARD_UNINSTALL_DIAGNOSTIC=" + ((@($uninstallOutput) -join " ") -replace "\s+", " "))
        Write-ToolResult -Status "ERROR" -FailureReason "TUNNEL_STOP_FAILED" -Extra $tunnelState
        return
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($null -eq (Get-TunnelAdapter)) { break }
        Start-Sleep -Milliseconds 500
    }
    $tunnelState.tunnelUp = $null -ne (Get-TunnelAdapter)

    # 지문 F3 을 재고 F0 과 견준다. 비교 결과는 실행 폴더에 남긴다.
    $fingerprintF3 = Get-NetworkFingerprint
    $recovery = [ordered]@{
        comparedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        fingerprintF0 = if ($null -ne $baseline) { [string]$baseline.fingerprintF0 } else { "" }
        fingerprintF3 = $fingerprintF3
        recoveryState = "UNKNOWN"
    }
    if ([string]::IsNullOrWhiteSpace($recovery.fingerprintF0)) {
        $recovery.recoveryState = "BASELINE_MISSING"
    }
    elseif ($recovery.fingerprintF0 -ceq $fingerprintF3) {
        $recovery.recoveryState = "MATCH"
    }
    else { $recovery.recoveryState = "MISMATCH" }

    $recoveryPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory "tunnel-recovery.json") -Root $RunDirectory
    Set-Content -LiteralPath $recoveryPath -Value ($recovery | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM

    # 터널이 실제로 내려간 것을 확인한 뒤에만 되돌릴 목록을 지운다.
    # 아직 어댑터가 보이면 정리가 안 끝난 것이므로 기록을 남겨 둔다.
    if (-not $tunnelState.tunnelUp) {
        Remove-Item -LiteralPath (Join-Path $RunDirectory "tunnel-installed.json") -Force -ErrorAction SilentlyContinue
    }

    Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $tunnelState
}
catch {
    [Console]::Error.WriteLine("USE_WFP_SPIKE_TUNNEL_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
    Write-ToolResult -Status "ERROR" -FailureReason "UNHANDLED_ERROR" -Extra $tunnelState
}
finally {
    # 축 1(되돌리기) 자기 점검: 이 스크립트가 바꾸는 것은 시험용 터널 하나뿐이고,
    # 그것을 되돌리는 것은 -Mode Teardown 이다(설계 §4.5 단계 6). 되돌리기를 여기서
    # 자동으로 하지 않는 이유는 순서 잠금 때문이다 — 정책이 0건인 것을 확인하기 전에
    # 터널을 내리면 정책이 없는 인터페이스를 가리키게 된다(BL-05).
    # 그래서 "언제든 되돌릴 수 있는 기록"(tunnel-installed.json)을 남기는 쪽을 택했다.
}
