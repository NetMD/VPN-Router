param(
    [string]$ResultPath = "$env:LOCALAPPDATA\VpnRouter\logs\startup-recovery-result.json"
)

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This startup recovery test must run as administrator."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$logDir = Join-Path $env:LOCALAPPDATA "VpnRouter\logs"
$routePath = Join-Path $env:LOCALAPPDATA "VpnRouter\managed-routes.json"
$markerPath = Join-Path $env:LOCALAPPDATA "VpnRouter\active-connection.json"
$handoffPath = Join-Path $env:LOCALAPPDATA "VpnRouter\dns-filter-handoff.json"
$restoreScript = Join-Path $repoRoot "scripts\windows\restore-network-dev.ps1"
$appPath = Join-Path $repoRoot "windows\VpnRouter.App\bin\x64\Debug\net10.0-windows10.0.19041.0\win-x64\VpnRouter.App.exe"
$firstLog = Join-Path $logDir "startup-recovery-first.out.log"
$secondLog = Join-Path $logDir "startup-recovery-second.out.log"
$firstErrorLog = Join-Path $logDir "startup-recovery-first.err.log"
$secondErrorLog = Join-Path $logDir "startup-recovery-second.err.log"

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$result = [ordered]@{ StartedAt = [DateTimeOffset]::Now; Success = $false; Error = $null }

function Stop-TestProcesses {
    Get-Process VpnRouter.App -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -like "*VpnRouter.Service*" } |
        Invoke-CimMethod -MethodName Terminate | Out-Null
}

function Get-ManagedRouteCount {
    if (-not (Test-Path $routePath)) { return 0 }
    $parsedRoutes = Get-Content $routePath -Raw | ConvertFrom-Json
    return @($parsedRoutes).Count
}

try {
    & $restoreScript
    $adguard = Get-Service "Adguard Service" -ErrorAction SilentlyContinue
    if ($null -ne $adguard) {
        Set-Service "Adguard Service" -StartupType Automatic
        Start-Service "Adguard Service" -ErrorAction SilentlyContinue
    }

    $env:VpnRouter__Features__EnableWireGuardActivation = "true"
    $env:VpnRouter__Features__EnableWindowsDnsMutation = "true"
    $env:VpnRouter__Features__EnableWindowsRouteMutation = "true"

    Start-Process dotnet -ArgumentList @(
        "run", "--project", "windows\VpnRouter.Service\VpnRouter.Service.csproj", "--no-build"
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $firstLog -RedirectStandardError $firstErrorLog
    Start-Sleep -Seconds 4
    $appProcess = Start-Process $appPath -WorkingDirectory (Split-Path $appPath) -PassThru
    Start-Sleep -Seconds 5

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
    Start-Sleep -Seconds 18

    $connectedAdapter = Get-NetAdapter | Where-Object Name -like "VpnRtr-*" | Select-Object -First 1
    $dnsDuringConnection = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
    $routesDuringConnection = Get-ManagedRouteCount
    $result.BeforeCrash = [pscustomobject]@{
        VpnAdapter = $connectedAdapter.Name
        Dns = $dnsDuringConnection
        ManagedRouteCount = $routesDuringConnection
        RecoveryMarker = Test-Path $markerPath
        DnsFilterHandoff = Test-Path $handoffPath
        AdguardStatus = if ($null -ne $adguard) { (Get-Service "Adguard Service").Status.ToString() } else { "Missing" }
    }
    if ($null -eq $connectedAdapter -or $dnsDuringConnection -notcontains "127.0.0.1" -or -not (Test-Path $markerPath)) {
        throw "The connected state required for the crash test was not established."
    }

    Stop-TestProcesses
    Start-Sleep -Seconds 3
    $result.AfterCrash = [pscustomobject]@{
        VpnCount = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -like "VpnRtr-*").Count
        Dns = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
        RecoveryMarker = Test-Path $markerPath
    }

    Start-Process dotnet -ArgumentList @(
        "run", "--project", "windows\VpnRouter.Service\VpnRouter.Service.csproj", "--no-build"
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $secondLog -RedirectStandardError $secondErrorLog

    $recovered = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Seconds 1
        $dns = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
        $vpnCount = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -like "VpnRtr-*").Count
        $routeCount = Get-ManagedRouteCount
        $adguardRestored = $null -eq $adguard -or (Get-Service "Adguard Service").Status -eq "Running"
        if ($dns -notcontains "127.0.0.1" -and $vpnCount -eq 0 -and $routeCount -eq 0 -and -not (Test-Path $markerPath) -and $adguardRestored) {
            $recovered = $true
            break
        }
    }

    $result.AfterRestart = [pscustomobject]@{
        Recovered = $recovered
        Dns = (Get-DnsClientServerAddress -InterfaceIndex 8 -AddressFamily IPv4).ServerAddresses
        VpnCount = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -like "VpnRtr-*").Count
        ManagedRouteCount = Get-ManagedRouteCount
        RecoveryMarker = Test-Path $markerPath
        DnsFilterHandoff = Test-Path $handoffPath
        AdguardStatus = if ($null -ne $adguard) { (Get-Service "Adguard Service").Status.ToString() } else { "Missing" }
        RecoveryLogDetected = (Select-String -Path $secondLog -Pattern "Startup recovery detected stale state" -Quiet)
    }
    $result.Success = $recovered -and $result.AfterRestart.RecoveryLogDetected
}
catch {
    $result.Error = $_.Exception.ToString()
}
finally {
    Stop-TestProcesses
    & $restoreScript
    $adguard = Get-Service "Adguard Service" -ErrorAction SilentlyContinue
    if ($null -ne $adguard) {
        Set-Service "Adguard Service" -StartupType Automatic
        Start-Service "Adguard Service" -ErrorAction SilentlyContinue
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content $ResultPath -Encoding utf8 -Force
}
