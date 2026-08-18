param(
    [switch]$ResetDnsToDhcp,

    # 기본 두 뿌리 밖에 남은 자리(지난 차수의 예행 폴더 등)를 한 번 훑을 때 쓴다.
    # 아무 폴더나 훑게 두지 않는다 — 경계 3겹은 아래 Get-RestoreRunRootVerdict 에 있다.
    # 사용자 폴더를 통째로 재귀하는 자리를 만들지 않는다.
    [string[]]$AdditionalRunRoot = @()
)

$ErrorActionPreference = "Stop"

# 순서가 중요하다 (R4 설계 §8).
#   1 고아 하네스 프로세스를 끝낸다
#   2 WFP 소유 정책을 지운다        <- WireGuard 를 멈추기 "전"이어야 한다
#   3 실행 폴더에 남은 경로를 지운다
#   3b 관찰기가 남긴 pktmon 잡기를 멈춘다
#   3c 정리되지 않은 시험용 터널을 알린다
#   4 WireGuard 서비스 중지 (기존)
#   5 /32 경로 제거 · IPv4 DNS 복원 (기존)
#   6 IPv6 DNS 복원
#   7 spool 잔여 폴더를 지운다
#   8 %TEMP%\wfp-feature-* 잔여를 지운다
#
# 2가 4보다 앞이어야 하는 이유: 정책이 터널 LUID 를 다음 홉으로 잡고 있다
# (NativePolicyBuffer.cs:51-56). WireGuard 를 먼저 멈추면 정책이 없는
# 인터페이스를 가리키게 되고, 되돌리는 도구가 스스로 그 순서를 어긴다.
#
# 제3자 제품을 "새로" 건드리는 줄은 0건이다. 아래 Adguard 두 줄(Set-Service · Start-Service)은
# 우리 제품이 바꾼 것을 되돌리는 자리이고 R4 가 더한 것이 아니다. 지우지 않는다.
# 그 두 줄은 "순서 5" 뒤 dns-filter-handoff.json 블록 안에 있다.
# (줄 번호로 가리키지 않는다 — 앞에 줄이 늘면 가리키는 곳이 어긋난다.)

# 이 도구는 관리자 권한으로 돈다. 그래서 쓰기 전에 자리부터 확인한다.
# 접합(junction)이나 바로가기로 바꿔치기된 폴더에 관리자 권한으로 쓰면
# 우리가 의도하지 않은 자리에 파일이 생긴다.
function Assert-NoReparsePath {
    param([Parameter(Mandatory)][string]$Path)

    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "RESTORE_PATH_REPARSE_REJECTED"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

# --- 훑을 뿌리 목록 ---------------------------------------------------------
# 지금까지는 뿌리가 하나(wfp-spike-runs)뿐이라, 손으로 돈 예행이 남긴 잔여물을
# 이 도구가 아예 못 봤다. 그렇다고 2026-08-17 예행 폴더 이름(r4-preflight-dry 등)을
# 도구에 박으면 다음 차수에 또 낡는다.
#
# 그래서 규약을 세운다 — 손으로 도는 예행은 wfp-spike-manual-runs\<이름> 아래에
# 만든다. 그러면 도구가 앞으로 저절로 덮는다. 지난 차수 폴더는 -AdditionalRunRoot 로
# 한 번 훑는다.
$restoreRunRootBoundary = Join-Path $env:LOCALAPPDATA "VpnRouter"
$restoreRunRoots = @(
    (Join-Path $env:LOCALAPPDATA "VpnRouter\wfp-spike-runs"),          # 자동 실행이 만드는 자리
    (Join-Path $env:LOCALAPPDATA "VpnRouter\wfp-spike-manual-runs")    # 손으로 도는 예행 자리 (새 규약)
) + @($AdditionalRunRoot | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

# 뿌리 하나가 훑어도 되는 자리인지 본다. 경계 3겹 —
#   (가) %LOCALAPPDATA%\VpnRouter 아래여야 한다
#   (나) 실제로 있어야 한다 (없으면 만들지 않는다)
#   (다) 접합이나 바로가기로 바꿔치기된 자리가 아니어야 한다
#
# 셋을 하나의 답으로 합치지 않는다. "없다"와 "못 읽었다"는 다른 사실이기 때문이다 —
# 없는 뿌리는 잔여물이 정말 0건이지만, 못 읽은 뿌리는 0건이 아니라 모르는 것이다.
function Get-RestoreRunRootVerdict {
    param([Parameter(Mandatory)][string]$Root)

    try {
        $fullRoot = [IO.Path]::GetFullPath($Root)
        $fullBoundary = [IO.Path]::GetFullPath($restoreRunRootBoundary).TrimEnd('\') + '\'
        if (-not $fullRoot.StartsWith($fullBoundary, [StringComparison]::OrdinalIgnoreCase)) {
            return "UNREADABLE"
        }
        if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { return "ABSENT" }
        Assert-NoReparsePath -Path $fullRoot
        return "SCAN"
    }
    catch { return "UNREADABLE" }
}

# --- 순서 1 : 고아 하네스 프로세스를 끝낸다 --------------------------------
# 동적 세션은 프로세스가 죽으면 반드시 사라진다
# (NativeSessionBuffer.cs:36 FWPM_SESSION_FLAG_DYNAMIC). 가장 흔한 경우를 여기서 푼다.
Write-Host "Stopping VPN Router development processes..."
Get-Process VpnRouter.Service,VpnRouter.App,VpnRouter.WfpSpike.Harness -ErrorAction SilentlyContinue | Stop-Process -Force

# --- 순서 2 : WFP 소유 정책이 0건인지 다시 센다 ----------------------------
# 열거기는 읽기만 한다. 임의로 지우는 코드를 만들지 않는다 — 다른 세션이 만든
# 동적 개체를 새 세션에서 지울 수 있는지 코드로 확인되지 않았고, 확인 안 된 쓰기를
# 되돌리는 도구에 넣으면 되돌릴 수단 자체가 위험해진다.
# 순서 1 뒤에도 0건이 아니면 그 사실을 적고 재부팅을 권한다.
# 재부팅은 확실한 최후 수단이고, "0건 확인"을 대신하지 않는다.
$policyEnumerator = Join-Path $PSScriptRoot "wfp-observation\Get-WfpOwnedPolicyState.ps1"
$restoreLogRootUsable = $false
# 기록 폴더는 첫 뿌리에 고정한다. 정책 세기는 뿌리 수와 무관하게 여전히 한 번만 돈다 —
# netsh 상태 덤프(3MB 남짓)를 뿌리 수만큼 늘리지 않는다.
$restoreLogRoot = Join-Path $restoreRunRoots[0] "restore"
try {
    # netsh 가 이 폴더에 이 PC 네트워크 상태를 통째로 적는다(3MB 남짓).
    # 자리가 바꿔치기되어 있으면 그 파일이 남의 자리로 간다. 쓰기 전에 확인한다.
    Assert-NoReparsePath -Path $restoreLogRoot
    if (-not (Test-Path $restoreLogRoot)) { [void](New-Item -ItemType Directory -Path $restoreLogRoot -Force) }
    $restoreLogRootUsable = $true
}
catch {
    # 여기서 도구 전체를 멈추지 않는다. 이것은 되돌리는 도구다 —
    # 한 단계를 못 해도 나머지 단계는 돌아야 한다.
    Write-Warning "The restore log folder is not a plain folder (it may be a junction or a shortcut). Skipping the owned WFP policy count. Owned WFP policy count is unknown."
}

if ((Test-Path $policyEnumerator) -and $restoreLogRootUsable) {
    Write-Host "Counting owned WFP policies left behind..."
    try {
        $policyJson = & $policyEnumerator -RunDirectory $restoreLogRoot -Label "after-restore"
        $policyState = @($policyJson | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })[-1] | ConvertFrom-Json
        if ([string]$policyState.status -ne "OK") {
            Write-Warning "Could not count owned WFP policies ($($policyState.failureReason)). Do not record this as zero."
        }
        elseif ([int]$policyState.ownedPolicyCount -ne 0 -or [int]$policyState.ownerSessionCount -ne 0) {
            Write-Warning "Owned WFP policies are still present (policies=$($policyState.ownedPolicyCount), sessions=$($policyState.ownerSessionCount)). A reboot is the reliable last resort."
        }
        else {
            Write-Host "Owned WFP policies: 0."
        }
    }
    catch {
        Write-Warning "Could not count owned WFP policies. Do not record this as zero."
    }
}
elseif (-not (Test-Path $policyEnumerator)) {
    Write-Warning "The owned-policy counter was not found. Owned WFP policy count is unknown."
}

# --- 뿌리를 훑어 잔여물 목록을 모은다 (순서 3 · 3b · 3c 공통) ---------------
# 뿌리마다 한 번만 훑고 세 가지 잔여물을 한꺼번에 집는다. 훑기가 실패하면
# "0건"이 아니라 "못 셌다"로 센다 — -ErrorAction SilentlyContinue 로 삼키면
# 읽지 못한 폴더가 잔여물 0건으로 둔갑한다.
$scannedRunRootCount = 0
$unreadableRunRootCount = 0
$leftoverRouteLogs = [Collections.Generic.List[object]]::new()
$leftoverFilterRecords = [Collections.Generic.List[object]]::new()
$leftoverTunnelRecords = [Collections.Generic.List[object]]::new()
$leftoverFileNames = @("added-routes.json", "pktmon-filters-before.json", "tunnel-installed.json")

foreach ($runRoot in $restoreRunRoots) {
    $rootVerdict = Get-RestoreRunRootVerdict -Root $runRoot
    if ($rootVerdict -eq "ABSENT") { continue }
    if ($rootVerdict -eq "UNREADABLE") {
        Write-Warning "이 뿌리를 읽지 못했습니다: $runRoot. 잔여물 0건이 아니라 ""못 셌다""입니다."
        $unreadableRunRootCount++
        continue
    }

    try {
        $rootFiles = @(Get-ChildItem -LiteralPath $runRoot -Recurse -File -ErrorAction Stop |
                Where-Object { $leftoverFileNames -contains $_.Name })
    }
    catch {
        Write-Warning "이 뿌리를 읽지 못했습니다: $runRoot. 잔여물 0건이 아니라 ""못 셌다""입니다."
        $unreadableRunRootCount++
        continue
    }
    $scannedRunRootCount++

    foreach ($rootFile in $rootFiles) {
        switch ($rootFile.Name) {
            "added-routes.json"            { $leftoverRouteLogs.Add($rootFile) }
            "pktmon-filters-before.json"   { $leftoverFilterRecords.Add($rootFile) }
            "tunnel-installed.json"        { $leftoverTunnelRecords.Add($rootFile) }
        }
    }
}

# --- 순서 3 : 실행 폴더에 남은 added-routes.json 의 경로를 지운다 -----------
# 흐름 발생기가 /32(또는 /128) 경로를 심는다. 그 프로세스가 강제로 죽으면
# finally 가 안 돌아 경로가 남는다. 남은 목록을 여기서 집는다.
if ($leftoverRouteLogs.Count -gt 0) {
    Write-Host "Removing host routes left behind by the WFP spike flow generator..."
    $leftoverRouteLogs |
        ForEach-Object {
            $routeLog = $_.FullName
            try { $addedRoutes = @(Get-Content $routeLog -Raw | ConvertFrom-Json) } catch { $addedRoutes = @() }
            foreach ($addedRoute in $addedRoutes) {
                # 파일에서 읽은 값은 형으로 바꿔서만 쓴다. 못 바꾸면 그 줄을 건너뛴다.
                $prefix = [string]$addedRoute.destinationPrefix
                [uint32]$addedInterfaceIndex = 0
                if ([string]::IsNullOrWhiteSpace($prefix) -or
                    -not [uint32]::TryParse([string]$addedRoute.interfaceIndex, [ref]$addedInterfaceIndex)) {
                    continue
                }
                # 흐름 발생기가 심는 것은 /32(IPv4) 또는 /128(IPv6) 한 대짜리 경로뿐이다
                # (New-WfpSpikeFlow.ps1 의 $prefixLength). 지우는 쪽도 같은 경계를 지킨다.
                # 이 경계가 없으면 이 파일에 0.0.0.0/0 이 적혀 있을 때 기본 경로가 지워진다.
                if ($prefix -notmatch '/(?:32|128)$') {
                    Write-Warning "Skipping a recorded route that is not a single-host route: $prefix"
                    continue
                }
                Get-NetRoute -DestinationPrefix $prefix -InterfaceIndex $addedInterfaceIndex -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            }
            Remove-Item $routeLog -Force -ErrorAction SilentlyContinue
        }
}

# --- 순서 3b : 관찰기가 남긴 pktmon 잡기를 마무리한다 -----------------------
# Get-WfpSpikeInterface.ps1 은 -Mode Start 로 걸고 -Mode Stop 으로 걷는다.
# 그 사이에 프로세스가 죽으면 잡기가 계속 돌고 거르개가 우리 것으로 남는다.
# Start 가 남긴 pktmon-filters-before.json 이 그 흔적이다.
#
# 여기서는 잡기를 멈추는 것까지만 한다. 원래 거르개 목록을 되돌리는 일은
# 그 파일에 무엇이 적혔는지에 달렸으므로 사람이 보고 판단하도록 파일을 남기고 알린다.
# 지우지 않는다 — 되돌릴 목록을 우리가 없애면 되돌릴 길이 사라진다.
if ($leftoverFilterRecords.Count -gt 0) {
    Write-Host "Stopping a packet capture left behind by the WFP spike interface observer..."
    $pktmonPath = Join-Path ${env:SystemRoot} "System32\pktmon.exe"
    if (Test-Path -LiteralPath $pktmonPath -PathType Leaf) {
        & $pktmonPath "stop" *> $null
    }
    else {
        Write-Warning "pktmon.exe was not found at the standard location. The packet capture was not stopped."
    }
    foreach ($filterRecord in $leftoverFilterRecords) {
        Write-Warning "A saved pktmon filter list is still on disk: $($filterRecord.FullName). Check it before relying on this machine's pktmon filters."
    }
}

# --- 순서 3c : 준비만 되고 정리되지 않은 시험용 터널을 알린다 ---------------
# Use-WfpSpikeTunnel.ps1 -Mode Prepare 가 터널을 올린 뒤 tunnel-installed.json 을 남긴다.
# -Mode Teardown 이 그 파일을 지운다. 파일이 남아 있으면 정리가 안 끝난 것이다.
# 아래 순서 4가 서비스를 멈추므로 여기서는 알리기만 한다.
foreach ($tunnelRecord in $leftoverTunnelRecords) {
    Write-Warning "A test tunnel was installed but never torn down: $($tunnelRecord.FullName)"
}

# 훑기 요약. 못 읽은 뿌리가 있으면 "잔여물 0건"이라고 적지 않는다.
if ($unreadableRunRootCount -eq 0) {
    Write-Host "Scanned run roots: $scannedRunRootCount. Unreadable run roots: 0."
}
else {
    Write-Warning "Scanned run roots: $scannedRunRootCount. Unreadable run roots: $unreadableRunRootCount. Leftovers under the unreadable roots are unknown, not zero."
}

# --- 순서 4 : WireGuard 서비스 중지 (기존) ---------------------------------
Write-Host "Stopping WireGuard tunnel services created during testing..."
Get-Service "WireGuardTunnel*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue

Write-Host "Removing recorded VpnRouter IPv4 host routes when possible..."
$routeFile = Join-Path $env:LOCALAPPDATA "VpnRouter\managed-routes.json"
if (Test-Path $routeFile) {
    $routes = Get-Content $routeFile -Raw | ConvertFrom-Json
    foreach ($route in @($routes)) {
        if ($null -ne $route.Ip -and $null -ne $route.InterfaceIndex) {
            Get-NetRoute -DestinationPrefix "$($route.Ip)/32" -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    Set-Content $routeFile "[]" -Encoding utf8
}

if ($ResetDnsToDhcp) {
    Write-Host "Resetting IPv4 DNS server settings to DHCP/default on active non-WireGuard adapters..."
    Get-NetAdapter |
        Where-Object {
            $_.Status -eq "Up" -and
            $_.InterfaceDescription -notmatch "WireGuard|Wintun" -and
            $_.Name -notmatch "WireGuard|Wintun"
        } |
        ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses
        }
}
else {
    $snapshotFile = Join-Path $env:LOCALAPPDATA "VpnRouter\network-snapshot.json"
    if (Test-Path $snapshotFile) {
        Write-Host "Restoring IPv4 DNS server settings from the saved network snapshot..."
        $snapshot = Get-Content $snapshotFile -Raw | ConvertFrom-Json
        $dnsEntries = $snapshot.DnsClientServerAddressJson | ConvertFrom-Json
        foreach ($entry in @($dnsEntries)) {
            # --- 순서 6 : IPv6 DNS 도 되돌린다 -----------------------------
            # 지금까지는 IPv4 만 되돌렸다. IPv6 DNS 가 터널 값으로 남으면
            # "설치 전으로 돌아왔다"가 성립하지 않는다.
            $addressFamily = [string]$entry.AddressFamily
            if ($addressFamily -notin @("2", "IPv4", "InterNetwork", "23", "IPv6", "InterNetworkV6")) {
                continue
            }

            $servers = @($entry.ServerAddresses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($entry.IsAutomatic -eq $true -or $servers.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceIndex $entry.InterfaceIndex -ResetServerAddresses
            }
            else {
                Set-DnsClientServerAddress -InterfaceIndex $entry.InterfaceIndex -ServerAddresses $servers
            }
        }
    }
    else {
        Write-Warning "No saved network snapshot was found. Use -ResetDnsToDhcp if DNS still needs recovery."
    }
}

$dnsFilterStateFile = Join-Path $env:LOCALAPPDATA "VpnRouter\dns-filter-handoff.json"
if (Test-Path $dnsFilterStateFile) {
    Write-Host "Restoring DNS filter service state..."
    $dnsFilterState = Get-Content $dnsFilterStateFile -Raw | ConvertFrom-Json
    # 여기는 "우리가 바꾼 것을 우리가 되돌리는" 자리다. 되돌리기지 새로 설정하기가 아니다.
    # 그래서 기록해 둔 값이 우리가 아는 세 값이 아니면 아무것도 하지 않는다.
    # 예전에는 모르는 값이면 "Automatic" 으로 바꿨는데, 그것은 기록에 없는 값으로
    # 제3자 제품의 시작 방식을 바꾸는 일이라 되돌리기가 아니다.
    $startupType = switch ([string]$dnsFilterState.StartMode) {
        "Auto" { "Automatic" }
        "Manual" { "Manual" }
        "Disabled" { "Disabled" }
        default { $null }
    }
    if ($null -eq $startupType) {
        Write-Warning "The recorded DNS filter start mode '$($dnsFilterState.StartMode)' is not one this tool sets. Leaving the third-party service start type unchanged."
    }
    else {
        Set-Service "Adguard Service" -StartupType $startupType -ErrorAction SilentlyContinue
    }
    if ([string]$dnsFilterState.State -eq "Running") {
        Start-Service "Adguard Service" -ErrorAction SilentlyContinue
    }
    Remove-Item $dnsFilterStateFile -Force -ErrorAction SilentlyContinue
}

$activeConnectionFile = Join-Path $env:LOCALAPPDATA "VpnRouter\active-connection.json"
Remove-Item $activeConnectionFile -Force -ErrorAction SilentlyContinue

# --- 순서 7 : spool 잔여 폴더를 지운다 --------------------------------------
# 이것은 test-wfp-app-routing-spike.ps1 의 finally 정리가 건너뛰어진 흔적이다.
# 종료 경로 결함의 증거이므로 지우기 전후 개수를 함께 적는다.
$spoolRoot = Join-Path $env:LOCALAPPDATA "VpnRouter\wfp-spike-spool"
if (Test-Path $spoolRoot) {
    $spoolBefore = @(Get-ChildItem -Path $spoolRoot -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "Removing leftover WFP spike spool folders (before: $spoolBefore)..."
    Get-ChildItem -Path $spoolRoot -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $spoolAfter = @(Get-ChildItem -Path $spoolRoot -Directory -ErrorAction SilentlyContinue).Count
    Write-Host "Leftover WFP spike spool folders after: $spoolAfter."
}

# --- 순서 8 : %TEMP%\wfp-feature-* 잔여를 지운다 ----------------------------
# 이것은 종료 경로의 증거가 아니다. 만드는 자리는 하네스가 아니라 집중 시험
# (VpnRouter.Tests/Program.cs 의 BuildInputFixture)이고, 그 시험은 자동 검사 단계에서
# 매 실행마다 돈다. 그래서 여기서 0건으로 만들어도 다음 실행에서 다시 늘어난다.
# 뿌리는 그 fixture 의 Dispose 가 고친다. 여기는 증상 처리다.
#
# 폴더 안에 .git\objects\ 아래 읽기 전용 파일이 남아 있어 그냥 지우면 실패한다.
# 먼저 읽기 전용 속성을 내린 뒤 지운다.
$tempRoot = [IO.Path]::GetTempPath()
$featureLeftovers = @(Get-ChildItem -Path $tempRoot -Directory -Filter "wfp-feature-*" -ErrorAction SilentlyContinue)
if ($featureLeftovers.Count -gt 0) {
    Write-Host "Removing leftover test fixture folders (before: $($featureLeftovers.Count))..."
    foreach ($leftover in $featureLeftovers) {
        Get-ChildItem -Path $leftover.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.IsReadOnly = $false } catch { } }
        Remove-Item -LiteralPath $leftover.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    $featureAfter = @(Get-ChildItem -Path $tempRoot -Directory -Filter "wfp-feature-*" -ErrorAction SilentlyContinue).Count
    Write-Host "Leftover test fixture folders after: $featureAfter. The focused test suite creates about 12 more on each run."
}

# --- 터널 안내 -------------------------------------------------------------
# 이 파일에 /uninstalltunnelservice 는 0건이다. 순서 4가 하는 것은
# Get-Service "WireGuardTunnel*" | Stop-Service 뿐이다.
# 멈추는 것과 지우는 것은 다르다. 그 차이를 사람이 알게 여기서 말한다.
Write-Warning "이 도구는 터널 서비스를 멈추기만 하고 지우지 않습니다. 되돌리기를 돌렸으면 그 뒤에 정리를 한 번 더 돌리십시오."

Write-Host "Development network restore completed."
