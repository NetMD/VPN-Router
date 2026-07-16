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
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ResetServerAddresses
        }
}

Write-Host "Development network restore completed."
