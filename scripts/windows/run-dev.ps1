param(
    [switch]$EnableWireGuardActivation,
    [switch]$EnableWindowsDnsMutation,
    [switch]$EnableWindowsRouteMutation
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$solution = Join-Path $repoRoot "windows\VpnRouter.slnx"
$appProject = Join-Path $repoRoot "windows\VpnRouter.App\VpnRouter.App.csproj"

dotnet build $solution

Start-Process powershell -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSScriptRoot\run-service-dev.ps1`"",
    "-EnableWireGuardActivation:$($EnableWireGuardActivation.IsPresent)",
    "-EnableWindowsDnsMutation:$($EnableWindowsDnsMutation.IsPresent)",
    "-EnableWindowsRouteMutation:$($EnableWindowsRouteMutation.IsPresent)"
)

Start-Sleep -Seconds 2
dotnet run --project $appProject --no-build -p:Platform=x64
