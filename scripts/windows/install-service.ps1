param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$InstallRoot = "$env:ProgramFiles\VpnRouter"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell session."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$serviceProject = Join-Path $repoRoot "windows\VpnRouter.Service\VpnRouter.Service.csproj"
$publishDir = Join-Path $repoRoot "artifacts\service-publish"

dotnet publish $serviceProject `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained false `
    --output $publishDir

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Copy-Item -Path (Join-Path $publishDir "*") -Destination $InstallRoot -Recurse -Force

$exePath = Join-Path $InstallRoot "VpnRouter.Service.exe"

if (Get-Service -Name "VpnRouterService" -ErrorAction SilentlyContinue) {
    Stop-Service -Name "VpnRouterService" -ErrorAction SilentlyContinue
    sc.exe delete "VpnRouterService" | Out-Null
    Start-Sleep -Seconds 2
}

New-Service `
    -Name "VpnRouterService" `
    -BinaryPathName "`"$exePath`"" `
    -DisplayName "VPN Router Service" `
    -Description "Privileged background service for VPN Router split-domain routing." `
    -StartupType Manual

Write-Host "Installed VpnRouterService at $exePath"
Write-Host "Start with: Start-Service VpnRouterService"
