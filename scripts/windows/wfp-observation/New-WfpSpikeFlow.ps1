# New-WfpSpikeFlow.ps1 — 흐름 발생기
#
# 설계: R4 설계서 §4.0 · §4.1 · §11.2(G-01·G-02·G-03) · §12.3
# 닫는 AC: R2-AC-06-1(기존/새 연결 구분) · R2-AC-06-2(16조합 x 4전송) · R2-AC-06-4(/32 경로)
#          · AC-03-1 · AC-03-2 · AC-11-7
#
# 이 스크립트가 하는 일
#   ① -PolicyAppliedAtUtc 가 비었으면 아무것도 하지 않고 ERROR/POLICY_TIMESTAMP_UNSET 으로 끝낸다.
#   ② -InstallHostRoute 면 대상 주소로 가는 /32(또는 /128) 경로를 심는다.
#   ③ 대상 앱을 "새로" 띄운다.
#   ④ 전송 방식별로 흐름을 한 번 만든다.
#   ⑤ finally 에서 앱을 끝내고 심은 경로를 지운다.
#
# 이 스크립트가 하지 않는 일 (§4.0)
#   - 판정값(PASS/FAIL/NOT_RUN/INCONCLUSIVE)을 만들지 않는다. 실패는 status 로만 적는다.
#   - 제3자 제품을 끄거나 켜지 않는다. 서비스 제어 명령은 하나도 쓰지 않는다 (회귀 확인 GR-12).
#   - 저장소 안에 아무것도 쓰지 않는다. 출력은 전부 -RunDirectory 아래로 간다.
#   - 주소·이름을 스크립트 안에 적어 두지 않는다. 전부 인자로 받는다.

[CmdletBinding()]
param(
    # G-01: 실제로 있는 .exe 만 받는다. 글자를 이어 붙여 명령줄을 만들지 않는다.
    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) { throw "APP_PATH_INVALID" }
        if ([IO.Path]::GetExtension($_) -ne ".exe") { throw "APP_PATH_INVALID" }
        $true
    })]
    [string]$AppPath,

    [Parameter(Mandatory)][ValidateSet("TCP", "UDP", "QUIC", "DNS")][string]$Transport,
    [Parameter(Mandatory)][ValidateSet("IPv4", "IPv6")][string]$IpVersion,

    # G-02: 주소·인터페이스 번호는 형으로 받는다. 글자로 받지 않는다.
    [ipaddress]$TargetAddress,
    [uint16]$TargetPort,

    # G-03: DNS 서버는 주소 형, 질의 이름은 정규식으로 좁힌다.
    [ipaddress]$DnsServer,
    [ValidatePattern('^[A-Za-z0-9]([A-Za-z0-9\-\.]{0,251})[A-Za-z0-9]$')][string]$QueryName,

    [switch]$InstallHostRoute,
    [uint32]$HostRouteInterfaceIndex,

    # 정책이 걸린 시각. 비어 있으면 아무것도 하지 않는다 (AC-03-2 두 번째 축).
    [AllowEmptyString()][string]$PolicyAppliedAtUtc,

    [Parameter(Mandatory)][string]$RunDirectory,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 45
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolName = "New-WfpSpikeFlow"
$startedAtUtc = [DateTimeOffset]::UtcNow
$flowId = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(8)).ToLowerInvariant()

# ---------------------------------------------------------------------------
# 공통 출력 (§4.0 결과 공통 칸) — 값마다 시각과 출처가 함께 나가고 빈 칸이 없다 (AC-03-9)
# ---------------------------------------------------------------------------
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

# 바깥 도구·명령이 실제로 있는지 시작할 때 확인한다 (§4.0 · T-11).
# 없으면 다른 것으로 대신 찾지 않고 그 자리에서 멈춘다.
function Test-RequiredCommand {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

# G-05 와 같은 검사: 쓰는 파일이 반드시 -RunDirectory 아래에 있게 한다.
function Assert-PathUnderRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "RUN_DIRECTORY_PATH_INVALID"
    }
    return $fullPath
}

# 대상 주소·포트로 가는 TCP 연결의 로컬 포트를 모은다.
#
# Get-NetTCPConnection 을 쓰지 않는다. 한 번 부르는 데 165~233ms 가 걸려(실측),
# 몇 백 ms 살다 사라지는 연결을 표본에서 놓친다. 아래 .NET 열거는 3.3ms 다.
# 여는 것도 세는 것도 하지 않고 목록만 읽는다.
function Get-TargetTcpLocalPort {
    param(
        [Parameter(Mandatory)][ipaddress]$Address,
        [Parameter(Mandatory)][int]$Port
    )

    $addressText = $Address.IPAddressToString
    try {
        $connections = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections()
    }
    catch { return @() }

    $ports = foreach ($connection in $connections) {
        if ($connection.RemoteEndPoint.Port -ne $Port) { continue }
        if ($connection.RemoteEndPoint.Address.ToString() -ne $addressText) { continue }
        [int]$connection.LocalEndPoint.Port
    }
    return @($ports)
}

$flowState = [ordered]@{
    flowId                       = $flowId
    transport                    = $Transport
    ipVersion                    = $IpVersion
    processId                    = $null
    flowStartedAtUtc             = $null
    flowEndedAtUtc               = $null
    hostRouteInstalled           = $false
    bytesSent                    = $null
    newConnectionCreated         = $false
    newConnectionLocalPort       = $null
    newConnectionOwningProcessId = $null
}

$process = $null
$installedRoute = $null

try {
    # --- ① 정책 적용 시각이 없으면 아무것도 하지 않는다 -------------------
    # 시각이 없으면 "정책이 걸린 뒤에 생긴 연결"을 가릴 수 없다. 가리지 못한 값을
    # 만들어 내보내면 그것은 측정이 아니다 (AC-03-2 · BL-08).
    if ([string]::IsNullOrWhiteSpace($PolicyAppliedAtUtc)) {
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_TIMESTAMP_UNSET" -Extra $flowState
        return
    }

    [DateTimeOffset]$policyAppliedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($PolicyAppliedAtUtc, [ref]$policyAppliedAt)) {
        Write-ToolResult -Status "ERROR" -FailureReason "POLICY_TIMESTAMP_UNSET" -Extra $flowState
        return
    }

    if (-not (Test-Path -LiteralPath $RunDirectory -PathType Container)) {
        Write-ToolResult -Status "ERROR" -FailureReason "RUN_DIRECTORY_MISSING" -Extra $flowState
        return
    }

    # --- 바깥 도구 존재 확인 (§4.0) ----------------------------------------
    foreach ($required in @("Get-NetRoute", "New-NetRoute", "Remove-NetRoute", "Get-NetTCPConnection")) {
        if (-not (Test-RequiredCommand -Name $required)) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason ("TOOL_MISSING:" + $required) -Extra $flowState
            return
        }
    }
    if ($Transport -eq "DNS" -and -not (Test-RequiredCommand -Name "Resolve-DnsName")) {
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason "TOOL_MISSING:Resolve-DnsName" -Extra $flowState
        return
    }

    # 전송 방식별로 반드시 있어야 하는 인자를 여기서 확인한다.
    if ($Transport -eq "DNS") {
        if ([string]::IsNullOrWhiteSpace($QueryName) -or $null -eq $DnsServer) {
            Write-ToolResult -Status "ERROR" -FailureReason "DNS_TARGET_UNSET" -Extra $flowState
            return
        }
    }
    elseif ($null -eq $TargetAddress -or $TargetPort -eq 0) {
        Write-ToolResult -Status "ERROR" -FailureReason "FLOW_TARGET_UNSET" -Extra $flowState
        return
    }

    # 대상 주소의 주소 종류가 -IpVersion 과 어긋나면 그대로 멈춘다.
    $wantedFamily = if ($IpVersion -eq "IPv4") { "InterNetwork" } else { "InterNetworkV6" }
    $flowAddress = if ($Transport -eq "DNS") { $DnsServer } else { $TargetAddress }
    if ([string]$flowAddress.AddressFamily -ne $wantedFamily) {
        Write-ToolResult -Status "ERROR" -FailureReason "IP_VERSION_MISMATCH" -Extra $flowState
        return
    }

    # --- ② 경로 심기 [EXT-012 적용] ----------------------------------------
    # 같은 경로가 이미 있으면 심지도 지우지도 않는다. 같은 인자로 두 번 돌려도 결과가 같다.
    if ($InstallHostRoute) {
        if ($HostRouteInterfaceIndex -eq 0) {
            Write-ToolResult -Status "ERROR" -FailureReason "HOST_ROUTE_INTERFACE_UNSET" -Extra $flowState
            return
        }

        $prefixLength = if ($IpVersion -eq "IPv4") { 32 } else { 128 }
        $destinationPrefix = "{0}/{1}" -f $flowAddress.IPAddressToString, $prefixLength
        $existing = @(Get-NetRoute -DestinationPrefix $destinationPrefix -InterfaceIndex $HostRouteInterfaceIndex -ErrorAction SilentlyContinue)
        if ($existing.Count -eq 0) {
            try {
                [void](New-NetRoute -DestinationPrefix $destinationPrefix `
                        -InterfaceIndex $HostRouteInterfaceIndex `
                        -PolicyStore ActiveStore `
                        -ErrorAction Stop)
            }
            catch {
                Write-ToolResult -Status "UNAVAILABLE" -FailureReason "HOST_ROUTE_FAILED" -Extra $flowState
                return
            }

            $installedRoute = [ordered]@{
                destinationPrefix = $destinationPrefix
                interfaceIndex    = [uint32]$HostRouteInterfaceIndex
                installedAtUtc    = [DateTimeOffset]::UtcNow.ToString("O")
                flowId            = $flowId
            }
            $flowState.hostRouteInstalled = $true

            # 프로세스가 강제로 죽어 finally 가 안 돌아도 복구 도구가 이 파일을 보고 지운다
            # (D-ADD-1 · 복구 도구 순서 3).
            $routeLogPath = Assert-PathUnderRoot -Path (Join-Path $RunDirectory "added-routes.json") -Root $RunDirectory
            $recorded = @()
            if (Test-Path -LiteralPath $routeLogPath -PathType Leaf) {
                try { $recorded = @(Get-Content -LiteralPath $routeLogPath -Raw | ConvertFrom-Json) } catch { $recorded = @() }
            }
            $recorded += [pscustomobject]$installedRoute
            Set-Content -LiteralPath $routeLogPath -Value (@($recorded) | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM
        }
    }

    # --- ③ 앱을 새로 띄운다 -------------------------------------------------
    # "새 연결"의 보증은 여기서 나온다. 정책 적용 시각보다 뒤에 뜬 프로세스가 만든
    # 연결만 대상이므로 정책 적용 전 연결이 구조적으로 섞이지 않는다 (R2-AC-06-1).
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AppPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true

    # 인자는 하나씩 넣는다. 글자를 이어 붙여 명령줄을 만들지 않는다 (G-01 · GR-15).
    switch ($Transport) {
        "TCP"  { [void]$startInfo.ArgumentList.Add(("http://{0}:{1}/" -f $flowAddress.IPAddressToString, $TargetPort)) }
        "QUIC" { [void]$startInfo.ArgumentList.Add(("https://{0}:{1}/" -f $flowAddress.IPAddressToString, $TargetPort)) }
        "UDP"  { [void]$startInfo.ArgumentList.Add(("udp://{0}:{1}" -f $flowAddress.IPAddressToString, $TargetPort)) }
        "DNS"  { [void]$startInfo.ArgumentList.Add(("dns://{0}/{1}" -f $flowAddress.IPAddressToString, $QueryName)) }
    }

    # TCP 는 "새 연결"인지를 로컬 포트로 가른다. 앱을 띄우기 "전"에 이미 있던 연결의
    # 로컬 포트를 적어 두고, 뒤에서 그 목록에 없는 포트만 새 연결로 센다.
    # 이렇게 하지 않으면 앞 사례가 남긴 연결이 그대로 "새 연결"로 잡힌다.
    $preexistingLocalPorts = @()
    if ($Transport -eq "TCP" -and $null -ne $flowAddress) {
        $preexistingLocalPorts = @(Get-TargetTcpLocalPort -Address $flowAddress -Port ([int]$TargetPort))
    }

    $flowState.flowStartedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")

    # 흐름이 정책보다 앞서면 그 값은 이번 시험의 대상이 아니다.
    if ([DateTimeOffset]::Parse($flowState.flowStartedAtUtc) -lt $policyAppliedAt) {
        Write-ToolResult -Status "ERROR" -FailureReason "FLOW_BEFORE_POLICY" -Extra $flowState
        return
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            Write-ToolResult -Status "UNAVAILABLE" -FailureReason "APP_START_FAILED" -Extra $flowState
            return
        }
    }
    catch {
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason "APP_START_FAILED" -Extra $flowState
        return
    }
    $flowState.processId = $process.Id

    # --- ④ 전송 방식별로 흐름을 한 번 만든다 -------------------------------
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $observedConnection = $false

    if ($Transport -eq "TCP") {
        # TCP 는 우리가 직접 되짚을 수 있다. 앱이 만든 연결이 실제로 보이는지 본다.
        #
        # 옛 방식은 -OwningProcess <우리가 띄운 번호> 로 찾았다. 그것은 어느 브라우저에서도
        # 안 맞는다 (2026-08-17 실측).
        #   - 브라우저가 이미 떠 있으면 새로 띄운 실행기는 일을 넘기고 1.3초 만에 끝난다.
        #     옛 코드는 HasExited 로 곧장 빠져나가, 흐름이 실제로 일어났는데도
        #     FLOW_TIMEOUT 을 냈다.
        #   - 실행기가 살아 있어도 소켓을 여는 것은 브라우저의 network service 자식이다.
        #     실측: 실행기 22384 · 브라우저 뿌리 18700 · 연결 주인 18908.
        #
        # 게다가 이 연결은 오래 살지 않는다. Get-NetTCPConnection 한 번이 165~233ms 라
        # 250ms 씩 쉬며 물으면 표본 간격이 0.4초를 넘어 연결을 통째로 놓친다
        # (실측 3회 중 2회 놓침. 같은 회차의 pktmon 기록에는 SYN 이 16개 있었다).
        # 그래서 3.3ms 로 끝나는 .NET 열거로 25ms 마다 본다.
        #
        # 무엇을 "새 연결"로 보나: 대상 주소·포트로 가는 연결 가운데 "앱을 띄우기 전에는
        # 없던 로컬 포트". 프로세스 번호로 거르지 않는다 — 위에 적은 대로 주인이 우리가
        # 띄운 번호가 아니고, 주인을 되짚는 조회는 소켓이 사라진 뒤에나 끝나기 때문이다.
        # 대상 주소는 이 시험만 쓰는 주소이고 잡기 창은 정책이 걸린 뒤에 열리므로,
        # 그 창 안에 새로 생긴 대상행 소켓은 이번 흐름 말고 나올 곳이 없다.
        # 되짚을 수 있으면 주인 번호를 증거로 적되, 판정 조건으로 쓰지는 않는다.
        $appProcessBaseName = [IO.Path]::GetFileNameWithoutExtension($AppPath)
        while ([DateTimeOffset]::UtcNow -lt $deadline -and -not $observedConnection) {
            $newLocalPorts = @(Get-TargetTcpLocalPort -Address $flowAddress -Port ([int]$TargetPort) |
                    Where-Object { -not ($preexistingLocalPorts -contains [int]$_) })
            if ($newLocalPorts.Count -gt 0) {
                $observedConnection = $true
                $flowState.newConnectionLocalPort = [int]$newLocalPorts[0]
                # 주인 되짚기는 실패해도 그만이다. 값이 있으면 증거로만 적는다.
                try {
                    $owner = @(Get-NetTCPConnection -LocalPort ([int]$newLocalPorts[0]) -ErrorAction SilentlyContinue |
                            Where-Object { [string]$_.RemoteAddress -eq $flowAddress.IPAddressToString } |
                            Select-Object -First 1)
                    if ($owner.Count -eq 1) { $flowState.newConnectionOwningProcessId = [int]$owner[0].OwningProcess }
                }
                catch { }
                break
            }

            # 실행기가 끝났다는 것만으로 그만두지 않는다. 위에 적은 대로 실행기의 종료는
            # "흐름이 없다"가 아니라 "브라우저가 일을 넘겨받았다"는 뜻이다.
            # 그 실행 파일로 뜬 프로세스가 하나도 없을 때만 더 기다릴 이유가 없다.
            if ($process.HasExited) {
                $appAlive = 0
                try {
                    $appAlive = @(Get-Process -Name $appProcessBaseName -ErrorAction SilentlyContinue |
                            Where-Object { [string]$_.Path -eq $AppPath }).Count
                }
                catch { $appAlive = 0 }
                if ($appAlive -eq 0) { break }
            }
            Start-Sleep -Milliseconds 25
        }
    }
    else {
        # UDP·QUIC·DNS 는 연결을 되짚을 수단이 없다. 앱이 흐름을 낼 시간을 준 뒤
        # 프로세스가 실제로 떴다는 사실만 남긴다. 무엇이 어느 인터페이스로 나갔는지는
        # Get-WfpSpikeInterface.ps1 이 pktmon 으로 판정한다 (§4.2).
        $settleSeconds = [Math]::Min(5, $TimeoutSeconds)
        Start-Sleep -Seconds $settleSeconds
        $observedConnection = -not $process.HasExited -or $process.ExitCode -eq 0
    }

    $flowState.flowEndedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
    $flowState.newConnectionCreated = $observedConnection

    if (-not $observedConnection) {
        Write-ToolResult -Status "UNAVAILABLE" -FailureReason "FLOW_TIMEOUT" -Extra $flowState
        return
    }

    Write-ToolResult -Status "OK" -FailureReason "NONE" -Extra $flowState
}
catch {
    # 진단 원문은 표준 오류로만 나간다. 표준 출력(결과 JSON)에는 한 글자도 넣지 않는다.
    [Console]::Error.WriteLine("NEW_WFP_SPIKE_FLOW_DIAGNOSTIC=" + ($_.Exception.Message -replace "\s+", " "))
    Write-ToolResult -Status "ERROR" -FailureReason "UNHANDLED_ERROR" -Extra $flowState
}
finally {
    # --- ⑤ 되돌리기 --------------------------------------------------------
    if ($null -ne $process) {
        try { if (-not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(10000) } } catch { }
        try { $process.Dispose() } catch { }
    }

    # 우리가 심은 경로만 지운다. 이미 있던 경로는 건드리지 않는다.
    if ($null -ne $installedRoute) {
        try {
            Get-NetRoute -DestinationPrefix $installedRoute.destinationPrefix `
                -InterfaceIndex $installedRoute.interfaceIndex `
                -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
        catch { }

        try {
            $routeLogPath = Join-Path $RunDirectory "added-routes.json"
            if (Test-Path -LiteralPath $routeLogPath -PathType Leaf) {
                $remaining = @(Get-Content -LiteralPath $routeLogPath -Raw | ConvertFrom-Json |
                        Where-Object { [string]$_.flowId -ne $flowId })
                Set-Content -LiteralPath $routeLogPath -Value (@($remaining) | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM
            }
        }
        catch { }
    }
}
