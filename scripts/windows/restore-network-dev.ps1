param(
    [switch]$ResetDnsToDhcp
)

$ErrorActionPreference = "Stop"

Write-Host "Stopping VPN Router development processes..."
Get-Process VpnRouter.Service,VpnRouter.App -ErrorAction SilentlyContinue | Stop-Process -Force

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
            $addressFamily = [string]$entry.AddressFamily
            if ($addressFamily -notin @("2", "IPv4", "InterNetwork")) {
                continue
            }

            $servers = @($entry.ServerAddresses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($servers.Count -eq 0) {
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
    $startupType = switch ([string]$dnsFilterState.StartMode) {
        "Auto" { "Automatic" }
        "Manual" { "Manual" }
        "Disabled" { "Disabled" }
        default { "Automatic" }
    }
    Set-Service "Adguard Service" -StartupType $startupType -ErrorAction SilentlyContinue
    if ([string]$dnsFilterState.State -eq "Running") {
        Start-Service "Adguard Service" -ErrorAction SilentlyContinue
    }
    Remove-Item $dnsFilterStateFile -Force -ErrorAction SilentlyContinue
}

$activeConnectionFile = Join-Path $env:LOCALAPPDATA "VpnRouter\active-connection.json"
Remove-Item $activeConnectionFile -Force -ErrorAction SilentlyContinue

Write-Host "Development network restore completed."
