param(
    [string]$ResultPath = "$env:LOCALAPPDATA\VpnRouter\logs\browser-routing-result.json"
)

$ErrorActionPreference = "Stop"

function Invoke-ChromeExpression {
    param(
        [Parameter(Mandatory = $true)][string]$WebSocketUrl,
        [Parameter(Mandatory = $true)][string]$Expression
    )

    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(20))
    try {
        $null = $socket.ConnectAsync([Uri]$WebSocketUrl, $timeout.Token).GetAwaiter().GetResult()
        $request = @{
            id = 1
            method = "Runtime.evaluate"
            params = @{
                expression = $Expression
                returnByValue = $true
                awaitPromise = $true
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $requestBytes = [Text.Encoding]::UTF8.GetBytes($request)
        $null = $socket.SendAsync(
            [ArraySegment[byte]]::new($requestBytes),
            [Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token).GetAwaiter().GetResult()

        $buffer = New-Object byte[] 65536
        $stream = [IO.MemoryStream]::new()
        do {
            $received = $socket.ReceiveAsync(
                [ArraySegment[byte]]::new($buffer),
                $timeout.Token).GetAwaiter().GetResult()
            $null = $stream.Write($buffer, 0, $received.Count)
        } while (-not $received.EndOfMessage)

        $response = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
        if ($null -ne $response.error) { throw ($response.error | ConvertTo-Json -Compress) }
        return $response.result.result.value
    }
    finally {
        $timeout.Dispose()
        $socket.Dispose()
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This browser routing test must run as administrator."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:LOCALAPPDATA "VpnRouter\logs"
$observationPath = Join-Path $env:LOCALAPPDATA "VpnRouter\dns-observations.json"
$serviceStdout = Join-Path $logDir "service-browser-test.out.log"
$serviceStderr = Join-Path $logDir "service-browser-test.err.log"
$chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$edgePath = if (Test-Path $chromePath) {
    $chromePath
} else {
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
}
$browserProcessName = [IO.Path]::GetFileName($edgePath)
$chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$chromePolicyName = "DnsOverHttpsMode"
$edgeProfileRoot = Join-Path $env:LOCALAPPDATA "VpnRouter\edge-test-profile"
$edgeRunProfile = "$edgeProfileRoot-$([Guid]::NewGuid().ToString('N'))"
$progressPath = Join-Path $logDir "browser-routing-progress.txt"
$restoreScript = Join-Path $repoRoot "scripts\windows\restore-network-dev.ps1"
$appPath = Join-Path $repoRoot "windows\VpnRouter.App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\VpnRouter.App.exe"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $edgeProfileRoot -Force | Out-Null
Set-Content $progressPath "started" -Encoding ascii

$adguard = Get-Service "Adguard Service" -ErrorAction SilentlyContinue
$adguardWasRunning = $null -ne $adguard -and $adguard.Status -eq "Running"
$adguardStartMode = if ($null -ne $adguard) {
    (Get-CimInstance Win32_Service -Filter "Name='Adguard Service'").StartMode
} else {
    $null
}
$chromePolicyHadValue = $false
$chromePolicyValue = $null
if ($edgePath -eq $chromePath -and (Test-Path $chromePolicyPath)) {
    $policy = Get-ItemProperty $chromePolicyPath
    $chromePolicyHadValue = $policy.PSObject.Properties.Name -contains $chromePolicyName
    if ($chromePolicyHadValue) { $chromePolicyValue = $policy.$chromePolicyName }
}

$result = [ordered]@{
    StartedAt = [DateTimeOffset]::Now
    Success = $false
    Error = $null
    Pages = @()
    NewObservations = @()
    NewRoutes = @()
}

try {
    Set-Content $progressPath "adguard-handoff-managed-by-service" -Encoding ascii

    if ($edgePath -eq $chromePath) {
        New-Item $chromePolicyPath -Force | Out-Null
        New-ItemProperty $chromePolicyPath -Name $chromePolicyName -Value "off" -PropertyType String -Force | Out-Null
    }

    $env:VpnRouter__Features__EnableWireGuardActivation = "true"
    $env:VpnRouter__Features__EnableWindowsDnsMutation = "true"
    $env:VpnRouter__Features__EnableWindowsRouteMutation = "true"

    Start-Process dotnet -ArgumentList @(
        "run", "--project", "windows\VpnRouter.Service\VpnRouter.Service.csproj", "--no-build"
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $serviceStdout -RedirectStandardError $serviceStderr
    Start-Sleep -Seconds 3
    $appProcess = Start-Process $appPath -WorkingDirectory (Split-Path $appPath) -PassThru
    Start-Sleep -Seconds 4

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $window = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
            $appProcess.Id))
    if ($null -eq $window) { throw "VPN Router window was not found." }

    $connectButton = $window.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.PropertyCondition]::new(
            [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
            "ConnectButton"))
    $connectButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 15
    Set-Content $progressPath "vpn-connect-wait-finished" -Encoding ascii

    $vpn = Get-NetAdapter | Where-Object { $_.Name -match "^VpnRtr-" } | Select-Object -First 1
    if ($null -eq $vpn) { throw "WireGuard adapter was not created." }

    $beforeVpnStats = Get-NetAdapterStatistics -Name $vpn.Name
    $fastHtml = (curl.exe -sS --max-time 20 "https://fast.com/" | Out-String)
    $fastScriptPath = [regex]::Match($fastHtml, 'src="([^"]+\.js)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($fastScriptPath)) { throw "Fast.com application script was not found." }
    $fastScriptUrl = if ($fastScriptPath -like "http*") { $fastScriptPath } else { "https://fast.com$fastScriptPath" }
    $fastScript = (curl.exe -sS --max-time 20 $fastScriptUrl | Out-String)
    $fastToken = [regex]::Match($fastScript, 'token["'']?\s*[:=]\s*["'']([^"'']{20,})["'']').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($fastToken)) { throw "Fast.com API token was not found." }

    $fastApiAddresses = @(Resolve-DnsName "api.fast.com" -Type A -DnsOnly |
        Where-Object { $_.IPAddress } |
        Select-Object -ExpandProperty IPAddress -Unique)
    try {
        foreach ($address in $fastApiAddresses) {
            New-NetRoute -DestinationPrefix "$address/32" -InterfaceIndex $vpn.ifIndex -NextHop "0.0.0.0" -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
        }
        $fastApiUrl = "https://api.fast.com/netflix/speedtest/v2?https=true&token=$fastToken&urlCount=1"
        $result.NetflixFastClient = (curl.exe -sS --max-time 20 $fastApiUrl | ConvertFrom-Json).client
    }
    finally {
        foreach ($address in $fastApiAddresses) {
            Get-NetRoute -DestinationPrefix "$address/32" -InterfaceIndex $vpn.ifIndex -ErrorAction SilentlyContinue |
                Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    $beforeRoutes = @(Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $vpn.ifIndex |
        Where-Object { $_.DestinationPrefix -like "*/32" } |
        Select-Object -ExpandProperty DestinationPrefix)
    Clear-DnsClientCache
    $beforeObservationCount = if (Test-Path $observationPath) {
        [IO.File]::ReadAllLines($observationPath).Count
    } else {
        0
    }

    $browserArguments = @(
        "--new-window",
        "--no-first-run",
        "--disable-background-networking",
        "--disable-features=DnsOverHttpsUpgrade",
        "--dns-over-https-mode=off",
        "--autoplay-policy=no-user-gesture-required",
        "--remote-debugging-port=9222",
        "--user-data-dir=$edgeRunProfile",
        "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
        "https://www.netflix.com/title/80057281",
        "https://example.com/"
    ) -join " "
    $shell = New-Object -ComObject Shell.Application
    $shell.ShellExecute($edgePath, $browserArguments, (Split-Path $edgePath), "open", 1)
    Start-Sleep -Seconds 25
    $result.BrowserProcessRunning = @(
        Get-CimInstance Win32_Process -Filter "Name='$browserProcessName'" |
            Where-Object { $_.CommandLine -like "*$edgeRunProfile*" }
    ).Count -gt 0
    $result.BrowserCommandLines = @(
        Get-CimInstance Win32_Process -Filter "Name='$browserProcessName'" |
            Where-Object { $_.CommandLine -like "*$edgeRunProfile*" } |
            Select-Object -ExpandProperty CommandLine
    )
    try {
        $browserTargets = Invoke-RestMethod -Uri "http://127.0.0.1:9222/json" -TimeoutSec 5
        $result.BrowserTargets = @($browserTargets | Where-Object { $_.type -eq "page" } | Select-Object title, url)
        $result.RegionSignals = @($browserTargets | Where-Object { $_.type -eq "page" } | ForEach-Object {
            $target = $_
            $expression = if ($target.url -like "*youtube.com*") {
                @'
                (async () => {
                    const context = window.ytcfg?.get?.('INNERTUBE_CONTEXT');
                    const video = document.querySelector('video');
                    let playError = null;
                    if (video) {
                        video.muted = true;
                        try {
                            if (video.paused) {
                                document.querySelector('.ytp-play-button')?.click();
                            }
                            await new Promise(resolve => setTimeout(resolve, 8000));
                        } catch (error) {
                            playError = String(error);
                        }
                    }
                    const mediaRequests = performance.getEntriesByType('resource')
                        .filter(entry => entry.name.includes('googlevideo.com'));
                    const playability = window.ytInitialPlayerResponse?.playabilityStatus ?? null;
                    const playerError = document.querySelector('.ytp-error-content-wrap-reason, .yt-playability-error-supported-renderers')?.textContent?.trim() ?? null;
                    const playButton = document.querySelector('.ytp-play-button');
                    let mediaProbe = null;
                    if (mediaRequests.length > 0) {
                        try {
                            const response = await fetch(mediaRequests[0].name, {
                                headers: { Range: 'bytes=0-1023' },
                                cache: 'no-store'
                            });
                            const body = await response.arrayBuffer();
                            mediaProbe = { ok: response.ok, status: response.status, bytes: body.byteLength };
                        } catch (error) {
                            mediaProbe = { ok: false, error: String(error) };
                        }
                    }
                    return {
                        service: 'youtube',
                        url: location.href,
                        title: document.title,
                        clientGl: context?.client?.gl ?? null,
                        clientHl: context?.client?.hl ?? null,
                        configGl: window.ytcfg?.get?.('GL') ?? null,
                        visibilityState: document.visibilityState,
                        videoElementCount: document.querySelectorAll('video').length,
                        playabilityStatus: playability,
                        playerError,
                        playButtonTitle: playButton?.getAttribute('title') ?? playButton?.getAttribute('aria-label') ?? null,
                        mediaNetwork: {
                            requestCount: mediaRequests.length,
                            transferBytes: mediaRequests.reduce((sum, entry) => sum + (entry.transferSize || 0), 0),
                            encodedBodyBytes: mediaRequests.reduce((sum, entry) => sum + (entry.encodedBodySize || 0), 0),
                            hosts: [...new Set(mediaRequests.map(entry => new URL(entry.name).hostname))]
                        },
                        mediaProbe,
                        playback: video ? {
                            currentTime: video.currentTime,
                            paused: video.paused,
                            readyState: video.readyState,
                            networkState: video.networkState,
                            sourceHost: video.currentSrc ? new URL(video.currentSrc).hostname : null,
                            playError
                        } : null
                    };
                })()
'@
            }
            elseif ($target.url -like "*netflix.com*") {
                @'
                (() => {
                    const match = location.pathname.match(/^\/([a-z]{2})(?:-|\/)/i);
                    return {
                        service: 'netflix',
                        url: location.href,
                        title: document.title,
                        htmlLang: document.documentElement.lang,
                        navigatorLanguage: navigator.language,
                        pathCountry: match?.[1]?.toUpperCase() ?? null
                    };
                })()
'@
            }
            else {
                $null
            }

            if ($null -ne $expression) {
                try {
                    if ($target.url -like "*youtube.com*") {
                        $null = Invoke-RestMethod -Uri "http://127.0.0.1:9222/json/activate/$($target.id)" -TimeoutSec 5
                        Start-Sleep -Seconds 5
                    }
                    Invoke-ChromeExpression -WebSocketUrl $target.webSocketDebuggerUrl -Expression $expression
                }
                catch {
                    [pscustomobject]@{
                        service = if ($target.url -like "*youtube.com*") { "youtube" } else { "netflix" }
                        url = $target.url
                        evaluationError = $_.Exception.Message
                    }
                }
            }
        })

        $netflixEffectiveUrl = & curl.exe -sS -L --max-time 20 -o NUL -w "%{url_effective}" -H "Accept-Language: en-US" "https://www.netflix.com/"
        $youtubeResponsePath = Join-Path $edgeRunProfile "youtube-region.html"
        & curl.exe -sS --compressed --max-time 20 -H "Accept-Language: en-US" -o $youtubeResponsePath "https://www.youtube.com/"
        $youtubeHtml = [IO.File]::ReadAllText($youtubeResponsePath)
        $youtubeCountryCandidates = @([regex]::Matches(
            $youtubeHtml,
            '"(?:countryCode|gl)"\s*:\s*"([A-Z]{2})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $result.CookieFreeRegionSignals = [pscustomobject]@{
            NetflixEffectiveUrl = $netflixEffectiveUrl
            YoutubeCountryCandidates = $youtubeCountryCandidates
        }
    }
    catch {
        if ($null -eq $result.BrowserTargets) { $result.BrowserTargets = @() }
        $result.BrowserDebugError = $_.Exception.Message
    }
    $result.Pages = @(
        [pscustomobject]@{ Name = "youtube"; Url = "https://www.youtube.com/watch?v=aqz-KE-bpKQ" }
        [pscustomobject]@{ Name = "netflix"; Url = "https://www.netflix.com/title/80057281" }
        [pscustomobject]@{ Name = "example"; Url = "https://example.com/" }
    )
    Set-Content $progressPath "edge-wait-finished" -Encoding ascii
    Start-Sleep -Seconds 5

    Set-Content $progressPath "collecting-routes" -Encoding ascii
    $afterRoutes = @(Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $vpn.ifIndex |
        Where-Object { $_.DestinationPrefix -like "*/32" } |
        Select-Object -ExpandProperty DestinationPrefix)
    $afterVpnStats = Get-NetAdapterStatistics -Name $vpn.Name
    $result.VpnTraffic = [pscustomobject]@{
        ReceivedBytesBefore = $beforeVpnStats.ReceivedBytes
        ReceivedBytesAfter = $afterVpnStats.ReceivedBytes
        ReceivedBytesDelta = $afterVpnStats.ReceivedBytes - $beforeVpnStats.ReceivedBytes
        SentBytesBefore = $beforeVpnStats.SentBytes
        SentBytesAfter = $afterVpnStats.SentBytes
        SentBytesDelta = $afterVpnStats.SentBytes - $beforeVpnStats.SentBytes
    }
    Set-Content $progressPath "routes-collected" -Encoding ascii
    Get-CimInstance Win32_Process -Filter "Name='$browserProcessName'" |
        Where-Object { $_.CommandLine -like "*$edgeRunProfile*" } |
        Invoke-CimMethod -MethodName Terminate | Out-Null
    Start-Sleep -Seconds 1
    Set-Content $progressPath "browser-stopped" -Encoding ascii

    $result.NewRoutes = @($afterRoutes | Where-Object { $_ -notin $beforeRoutes })
    $result.NewObservations = @(if (Test-Path $observationPath) {
        [IO.File]::ReadAllLines($observationPath) | Select-Object -Skip $beforeObservationCount
    } else {
        @()
    })
    $result.BeforeRouteCount = $beforeRoutes.Count
    $result.AfterRouteCount = $afterRoutes.Count
    Set-Content $progressPath "disconnecting" -Encoding ascii
    $connectButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Seconds 15
    $result.AfterGracefulDisconnect = [pscustomobject]@{
        Dns = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
        VpnCount = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^VpnRtr-" }).Count
        AdguardStatus = if ($null -ne $adguard) { (Get-Service "Adguard Service").Status.ToString() } else { "Missing" }
        RecoveryMarker = Test-Path (Join-Path $env:LOCALAPPDATA "VpnRouter\active-connection.json")
        DnsFilterHandoff = Test-Path (Join-Path $env:LOCALAPPDATA "VpnRouter\dns-filter-handoff.json")
    }
    $result.Success = $result.NewObservations.Count -gt 0 -and
        $result.NewRoutes.Count -gt 0 -and
        $result.AfterGracefulDisconnect.VpnCount -eq 0 -and
        $result.AfterGracefulDisconnect.Dns -notcontains "127.0.0.1" -and
        -not $result.AfterGracefulDisconnect.RecoveryMarker -and
        -not $result.AfterGracefulDisconnect.DnsFilterHandoff
    $result | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding utf8 -Force
    Set-Content $progressPath "result-written" -Encoding ascii
}
catch {
    $result.Error = $_.Exception.ToString()
}
finally {
    $cleanupErrors = @()
    try {
        Get-CimInstance Win32_Process -Filter "Name='$browserProcessName'" |
            Where-Object { $_.CommandLine -like "*$edgeRunProfile*" } |
            Invoke-CimMethod -MethodName Terminate | Out-Null
    }
    catch {
        $cleanupErrors += "Edge cleanup: $($_.Exception.Message)"
    }

    try {
        & $restoreScript
    }
    catch {
        $cleanupErrors += "Network cleanup: $($_.Exception.Message)"
    }

    try {
        if ($null -ne $adguard) {
            $startupType = switch ($adguardStartMode) {
                "Auto" { "Automatic" }
                "Manual" { "Manual" }
                "Disabled" { "Disabled" }
                default { "Automatic" }
            }
            Set-Service "Adguard Service" -StartupType $startupType
            if ($adguardWasRunning) { Start-Service "Adguard Service" }
        }
    }
    catch {
        $cleanupErrors += "AdGuard cleanup: $($_.Exception.Message)"
    }

    try {
        if ($edgePath -eq $chromePath) {
            if ($chromePolicyHadValue) {
                New-ItemProperty $chromePolicyPath -Name $chromePolicyName -Value $chromePolicyValue -PropertyType String -Force | Out-Null
            }
            else {
                Remove-ItemProperty $chromePolicyPath -Name $chromePolicyName -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        $cleanupErrors += "Chrome policy cleanup: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 3
    $result.CleanupErrors = $cleanupErrors
    $result.AfterCleanup = [pscustomobject]@{
        Dns = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
        VpnCount = @(Get-NetAdapter | Where-Object { $_.Name -match "^VpnRtr-" }).Count
        AdguardStatus = if ($null -ne $adguard) { (Get-Service "Adguard Service").Status.ToString() } else { "Missing" }
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding utf8 -Force
    Set-Content $progressPath "completed" -Encoding ascii
}
