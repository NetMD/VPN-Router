$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell session."
}

if (Get-Service -Name "VpnRouterService" -ErrorAction SilentlyContinue) {
    Stop-Service -Name "VpnRouterService" -ErrorAction SilentlyContinue
    sc.exe delete "VpnRouterService" | Out-Null
    Write-Host "Removed VpnRouterService."
}
else {
    Write-Host "VpnRouterService is not installed."
}
