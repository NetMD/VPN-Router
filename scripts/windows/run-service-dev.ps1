param(
    [switch]$EnableWireGuardActivation,
    [switch]$EnableWindowsDnsMutation,
    [switch]$EnableWindowsRouteMutation
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$serviceProject = Join-Path $repoRoot "windows\VpnRouter.Service\VpnRouter.Service.csproj"

Write-Host "Starting VPN Router service in development mode..."
Write-Host "Keep this window open while using the app."
Write-Host "WireGuard activation: $EnableWireGuardActivation"
Write-Host "Windows DNS mutation: $EnableWindowsDnsMutation"
Write-Host "Windows route mutation: $EnableWindowsRouteMutation"

$env:VpnRouter__Features__EnableWireGuardActivation = $EnableWireGuardActivation.ToString().ToLowerInvariant()
$env:VpnRouter__Features__EnableWindowsDnsMutation = $EnableWindowsDnsMutation.ToString().ToLowerInvariant()
$env:VpnRouter__Features__EnableWindowsRouteMutation = $EnableWindowsRouteMutation.ToString().ToLowerInvariant()

dotnet run --project $serviceProject --no-build
