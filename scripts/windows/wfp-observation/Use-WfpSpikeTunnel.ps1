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
    [ValidateRange(1, 60000)][int]$ReachabilityTimeoutMs = 4000
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
    $route = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object -Property RouteMetric, InterfaceMetric) | Select-Object -First 1
    if ($null -eq $route) { return $null }
    return [int]$route.InterfaceIndex
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
